// SPDX-License-Identifier: GPL-2.0-only
/* Measurement tap: see meas_tap.h for the switches and the record format. */
#define _GNU_SOURCE
#include "fwsel.h"
#if MEAS_TAP
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>
#include "meas_tap.h"

struct slot { struct meas_tap_hdr h; uint8_t payload[MEAS_TAP_CAP]; };
static struct slot ring[MEAS_TAP_SLOTS];
static _Atomic unsigned head, tail;	/* head: pump only, tail: writer only */
static _Atomic int stopping, finished;
static unsigned seq, dropped;
static int on, fd = -1;
static const char *path;
static struct { int dev, res; } filter[8];	/* -1 = any */
static unsigned filters, all;
static pthread_t writer;
static char writer_stack[65536] __attribute__((aligned(16)));	/* own stack: e5rt maps fixed VAs */

static int parse_filter(const char *s)
{
	if (!s || !*s)
		s = "7c:38";
	if (!strcmp(s, "all")) {
		all = 1;
		return 0;
	}
	while (*s && filters < sizeof(filter) / sizeof(filter[0])) {
		int v[2];
		for (int i = 0; i < 2; i++) {
			if (*s == '*') {
				v[i] = -1;
				s++;
			} else {
				char *e;
				unsigned long x = strtoul(s, &e, 16);
				if (e == s || x > 255)
					return -1;
				v[i] = (int)x;
				s = e;
			}
			if (i == 0 && *s++ != ':')
				return -1;
		}
		filter[filters].dev = v[0];
		filter[filters++].res = v[1];
		if (*s == ',')
			s++;
		else if (*s)
			return -1;
	}
	return *s ? -1 : 0;
}

static int wanted(const uint8_t *p, uint32_t avail)
{
	if (all)
		return 1;
	if (!p || avail < 4)
		return 0;
	for (unsigned i = 0; i < filters; i++)
		if ((filter[i].dev < 0 || filter[i].dev == p[2]) && (filter[i].res < 0 || filter[i].res == p[3]))
			return 1;
	return 0;
}

void meas_tap_frame(const uint32_t desc[4], const uint8_t *p, uint32_t avail, uint64_t t_us)
{
	if (!on || !wanted(p, avail))
		return;
	unsigned h = atomic_load_explicit(&head, memory_order_relaxed);
	if (h - atomic_load_explicit(&tail, memory_order_acquire) >= MEAS_TAP_SLOTS) {
		dropped++;
		seq++;
		return;
	}
	struct slot *s = &ring[h % MEAS_TAP_SLOTS];
	uint32_t orig = p && avail >= 6 ? (uint32_t)(p[4] | p[5] << 8) + 6 : 0, n = 0;
	if (p) {
		n = orig && orig < avail ? orig : avail;
		if (n > 0xffff)
			n = 0xffff;
	}
	s->h = (struct meas_tap_hdr){.magic = MEAS_TAP_MAGIC, .version = MEAS_TAP_VERSION, .hdr_len = MEAS_TAP_HDR,
		.seq = seq++, .dropped = dropped, .t_us = t_us, .orig_len = orig > 0xffff ? 0xffff : (uint16_t)orig,
		.dev = p && avail > 2 ? p[2] : 0xff, .res = p && avail > 3 ? p[3] : 0xff, .msg = p && avail > 6 ? p[6] : 0xff};
	memcpy(s->h.desc, desc, sizeof(s->h.desc));
	if (p) {
		s->h.flags = 1;
		if (n > MEAS_TAP_CAP) {
			n = MEAS_TAP_CAP;
			s->h.flags |= 2;
		}
		memcpy(s->payload, p, n);
	}
	s->h.len = (uint16_t)n;
	atomic_store_explicit(&head, h + 1, memory_order_release);
}

static void write_all(const void *b, size_t n)
{
	const char *c = b;
	while (n && fd >= 0) {
		ssize_t w = write(fd, c, n);
		if (w > 0) {
			c += w;
			n -= (size_t)w;
		} else if (w < 0 && errno == EINTR) {
			continue;
		} else {	/* reader gone (EPIPE) or disk full: drop, reopen on the next record */
			close(fd);
			fd = -1;
		}
	}
}

static void *writer_main(void *arg)
{
	(void)arg;
	setpriority(PRIO_PROCESS, (id_t)syscall(SYS_gettid), 10);	/* below the runtime (nice -10) */
	for (;;) {
		unsigned t = atomic_load_explicit(&tail, memory_order_relaxed);
		unsigned h = atomic_load_explicit(&head, memory_order_acquire);
		if (t == h) {
			if (atomic_load(&stopping))
				break;
			struct timespec d = {0, 50 * 1000 * 1000};
			nanosleep(&d, NULL);
			continue;
		}
		if (fd < 0) {	/* FIFO without a reader: ENXIO, keep the records and retry (the pump drops when full) */
			fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NONBLOCK, 0600);
			if (fd < 0) {
				if (atomic_load(&stopping))
					break;
				struct timespec d = {0, 200 * 1000 * 1000};
				nanosleep(&d, NULL);
				continue;
			}
			fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
		}
		for (; t != h; t++) {
			const struct slot *s = &ring[t % MEAS_TAP_SLOTS];
			static const uint8_t pad[4];
			write_all(&s->h, sizeof(s->h));
			write_all(s->payload, s->h.len);
			write_all(pad, (4 - s->h.len % 4) % 4);
		}
		atomic_store_explicit(&tail, t, memory_order_release);
	}
	if (fd >= 0)
		close(fd);
	atomic_store(&finished, 1);
	return NULL;
}

int meas_tap_init(void)
{
	path = getenv("E5RT_MEAS_TAP");
	if (!path || !*path)
		return 0;
	if (parse_filter(getenv("E5RT_MEAS_FILTER"))) {
		fprintf(stderr, "meas tap: bad E5RT_MEAS_FILTER (dev:res hex pairs, '*', or all), tap off\n");
		return 0;
	}
	pthread_attr_t a;
	sigset_t allsig, old;
	sigfillset(&allsig);
	pthread_attr_init(&a);
	pthread_attr_setstack(&a, writer_stack, sizeof(writer_stack));
	pthread_sigmask(SIG_BLOCK, &allsig, &old);	/* the writer takes no signals (e5rt's SIGALRM/SIGSEGV stay on the main thread) */
	int r = pthread_create(&writer, &a, writer_main, NULL);
	pthread_sigmask(SIG_SETMASK, &old, NULL);
	pthread_attr_destroy(&a);
	if (r) {
		fprintf(stderr, "meas tap: writer thread: %s, tap off\n", strerror(r));
		return 0;
	}
	on = 1;
	atexit(meas_tap_close);
	fprintf(stderr, "meas tap: on (%s), %u filter(s)%s, record format v%d\n", path, filters, all ? " (all frames)" : "", MEAS_TAP_VERSION);
	return 1;
}

void meas_tap_close(void)
{
	if (!on)
		return;
	on = 0;
	atomic_store(&stopping, 1);
	for (int i = 0; i < 100 && !atomic_load(&finished); i++) {	/* at most 1 s (a stalled FIFO reader) */
		struct timespec d = {0, 10 * 1000 * 1000};
		nanosleep(&d, NULL);
	}
	if (atomic_load(&finished))
		pthread_join(writer, NULL);
	fprintf(stderr, "meas tap: %u records, %u dropped\n", seq - dropped, dropped);
}
#endif
