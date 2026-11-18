// SPDX-License-Identifier: GPL-2.0-only
/* offline check of the measurement tap: build with -DMEAS_TAP=1 meas_tap.c, run with E5RT_MEAS_TAP=<file>.
 * Pushes matching, non-matching, truncated and payload-less frames, reads the file back. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "meas_tap.h"
int main(void)
{
	const char *path = getenv("E5RT_MEAS_TAP");
	if (!path || !meas_tap_init())
		return 2;
	static uint8_t f[2048];
	uint32_t d[4] = {0x11, 0x22, 0x33, 0x141000};
	unsigned expect = 0;
	for (unsigned i = 0; i < 10; i++) {	/* 10 x DSP res 0x38, 234 bytes */
		memset(f, i, sizeof(f));
		f[0] = 0x12; f[1] = 0; f[2] = 0x7c; f[3] = 0x38; f[4] = 0xea; f[5] = 0; f[6] = 0x15;
		meas_tap_frame(d, f, 0x1000, 1000 + i);
		expect++;
	}
	f[3] = 0x0a;
	meas_tap_frame(d, f, 0x1000, 2000);	/* other resource: filtered */
	f[3] = 0x38; f[4] = 0xff; f[5] = 0x07;	/* 2047 + 6 > cap: truncated */
	meas_tap_frame(d, f, sizeof(f), 3000);
	expect++;
	meas_tap_frame(d, NULL, 0, 4000);	/* no payload: filtered by the default dev:res filter */
	meas_tap_close();
	FILE *in = fopen(path, "rb");
	if (!in)
		return 3;
	struct meas_tap_hdr h;
	unsigned n = 0, trunc = 0;
	while (fread(&h, sizeof(h), 1, in) == 1) {
		if (h.magic != MEAS_TAP_MAGIC || h.version != 1 || h.hdr_len != 48 || h.dev != 0x7c || h.res != 0x38 || h.msg != 0x15) {
			fprintf(stderr, "record %u: bad header\n", n);
			return 1;
		}
		uint8_t b[MEAS_TAP_CAP + 3];
		unsigned len = (h.len + 3) & ~3u;
		if (fread(b, 1, len, in) != len || b[3] != 0x38 || (h.flags & 2 && (h.len != MEAS_TAP_CAP || h.orig_len != 2053)) ||
		    (!(h.flags & 2) && (h.len != 240 || h.orig_len != 240 || b[100] != (uint8_t)n || h.t_us != 1000 + n))) {
			fprintf(stderr, "record %u: bad payload (len %u orig %u flags %x)\n", n, h.len, h.orig_len, h.flags);
			return 1;
		}
		trunc += (h.flags & 2) != 0;
		n++;
	}
	if (n != expect || trunc != 1) {
		fprintf(stderr, "%u records (expected %u), %u truncated\n", n, expect, trunc);
		return 1;
	}
	printf("meas tap selftest: %u records, filter, truncation and record format v%d passed\n", n, MEAS_TAP_VERSION);
	return 0;
}
