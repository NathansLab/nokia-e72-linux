// SPDX-License-Identifier: GPL-2.0
/*
 * e72pdm: silent first test for the E72 uplink microphones (built, not yet run). Nothing here makes a sound: it only reads the two digital mic
 * lines and, in mode 1, drives the mic clock pin.
 *
 * Hardware (see docs/audio-vibra.md): B2100 primary (L/R = GND) and
 * B2104 secondary (L/R = VDigimic) PDM mics share DigiMICData = GenIO39 and
 * DigiMICClk = GenIO72 (via R2101 33R). Supply VDigimic from Gazoo N2200.
 * Under Symbian these pins belong to the DSP side (unknown block), so the
 * pad function of GenIO39/72 may not be "gpio": mode 0 checks that first.
 *
 * mode=0 (default, read only): sample the raw input state of both pins for
 *        `probe_ms` and count level changes. Clock toggling = something
 *        (DSP) still clocks the mics; data toggling with clock idle = noise.
 * mode=1: bit-bang the clock on GenIO72 for `ms` milliseconds with IRQs off
 *        in chunks of `chunk_us`, sample GenIO39 after each edge, keep 2 bits
 *        per clock (rising, falling) in a buffer, readable from /dev/e72pdm.
 *        Decode on the Mac with pdm2wav.py. GenIO72 is set back to input at
 *        the end. If VDigimic is off the data line stays constant (no harm).
 *
 * Registers (drivers/gpio/gpio-rapuyama.c): gpio block 0x20031900, out bank k
 * 0x94/0x98 + 0x10k set/clr, dir 0xf4/0xf8 + 0x10k in/out; raw input state in
 * the irq block 0x20033400 + 0x40k + 0x08.
 */
#include <linux/io.h>
#include <linux/ktime.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/vmalloc.h>
#include <linux/irqflags.h>
#include <linux/delay.h>
#include <linux/math64.h>

#define GPIO_PA		0x20031900
#define GIRQ_PA		0x20033400
#define OUT_SET(k)	(0x94 + 0x10 * (k))
#define OUT_CLR(k)	(0x98 + 0x10 * (k))
#define DIR_IN(k)	(0xf4 + 0x10 * (k))
#define DIR_OUT(k)	(0xf8 + 0x10 * (k))
#define RAW(k)		(0x40 * (k) + 0x08)

static int mode;
module_param(mode, int, 0444);
static unsigned int clk_gpio = 72, dat_gpio = 39;
module_param(clk_gpio, uint, 0444);
module_param(dat_gpio, uint, 0444);
static unsigned int probe_ms = 200, ms = 2000, chunk_us = 2000, spin = 0;
module_param(probe_ms, uint, 0444);
module_param(ms, uint, 0444);
module_param(chunk_us, uint, 0444);
module_param(spin, uint, 0444);	/* extra busy loops per half period */

static void __iomem *gp, *gi;
static u8 *buf;
static size_t buf_len, buf_used;

static inline int rd(unsigned int g)
{
	return !!(readl_relaxed(gi + RAW(g / 32)) & BIT(g % 32));
}

static void probe(void)
{
	unsigned int kc = clk_gpio / 32, kd = dat_gpio / 32, n = 0, tc = 0, td = 0;
	int lc = rd(clk_gpio), ld = rd(dat_gpio), ones = 0;
	ktime_t end = ktime_add_ms(ktime_get(), probe_ms);

	pr_info("e72pdm: latch bank%u %08x bank%u %08x, raw clk %d dat %d\n",
		kc, readl(gp + 0x90 + 0x10 * kc), kd, readl(gp + 0x90 + 0x10 * kd), lc, ld);
	while (ktime_before(ktime_get(), end)) {
		int c = rd(clk_gpio), d = rd(dat_gpio);

		tc += c != lc; td += d != ld; ones += d; lc = c; ld = d; n++;
		if (!(n & 0xfff))
			cond_resched();
	}
	pr_info("e72pdm: %u samples, clk changes %u, data changes %u, data ones %d\n",
		n, tc, td, ones);
}

static void capture(void)
{
	unsigned int kc = clk_gpio / 32, kd = dat_gpio / 32;
	u32 cb = BIT(clk_gpio % 32), db = BIT(dat_gpio % 32);
	void __iomem *set = gp + OUT_SET(kc), *clr = gp + OUT_CLR(kc);
	void __iomem *raw = gi + RAW(kd);
	size_t bit = 0, nbits = buf_len * 8;
	ktime_t t0, t1;
	unsigned long flags;

	writel(db, gp + DIR_IN(kd));
	writel(cb, clr);			/* level first, then direction */
	writel(cb, gp + DIR_OUT(kc));
	udelay(100);
	t0 = ktime_get();
	while (bit + 2 <= nbits && ktime_ms_delta(ktime_get(), t0) < ms) {
		ktime_t c_end = ktime_add_us(ktime_get(), chunk_us);

		local_irq_save(flags);
		while (bit + 2 <= nbits) {
			unsigned int s;

			writel_relaxed(cb, set);
			for (s = spin; s; s--)
				cpu_relax();
			if (readl_relaxed(raw) & db)
				buf[bit >> 3] |= BIT(bit & 7);
			bit++;
			writel_relaxed(cb, clr);
			for (s = spin; s; s--)
				cpu_relax();
			if (readl_relaxed(raw) & db)
				buf[bit >> 3] |= BIT(bit & 7);
			bit++;
			if (!(bit & 0x3ff) && ktime_after(ktime_get(), c_end))
				break;
		}
		local_irq_restore(flags);
		cond_resched();
	}
	t1 = ktime_get();
	writel(cb, clr);
	writel(cb, gp + DIR_IN(kc));		/* leave the clock pin floating */
	buf_used = bit / 8;
	{
		u64 us = ktime_us_delta(t1, t0);

		pr_info("e72pdm: %zu clocks in %llu us = %llu kHz average (gaps between chunks included)\n",
			bit / 2, us, us ? div64_u64((u64)(bit / 2) * 1000, us) : 0);
	}
}

static ssize_t pdm_read(struct file *f, char __user *u, size_t n, loff_t *pos)
{
	return simple_read_from_buffer(u, n, pos, buf, buf_used);
}

static const struct file_operations pdm_fops = {
	.owner = THIS_MODULE,
	.read = pdm_read,
	.llseek = default_llseek,
};

static struct miscdevice pdm_misc = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "e72pdm",
	.fops = &pdm_fops,
	.mode = 0400,
};

static int __init pdm_init(void)
{
	int ret;

	if (clk_gpio >= 160 || dat_gpio >= 160)	/* in banks 0-4 only */
		return -EINVAL;
	gp = ioremap(GPIO_PA, 0x200);
	gi = ioremap(GIRQ_PA, 0x200);
	if (!gp || !gi)
		goto nomem;
	if (mode == 0) {
		probe();
		iounmap(gp); iounmap(gi);
		return -EAGAIN;			/* nothing to keep loaded */
	}
	buf_len = 1024 * 1024;			/* 4 Mbit = 2 s at ~2 MHz */
	buf = vzalloc(buf_len);
	if (!buf)
		goto nomem;
	capture();
	ret = misc_register(&pdm_misc);
	if (ret) {
		vfree(buf);
		iounmap(gp); iounmap(gi);
	}
	return ret;
nomem:
	if (gp) iounmap(gp);
	if (gi) iounmap(gi);
	return -ENOMEM;
}

static void __exit pdm_exit(void)
{
	misc_deregister(&pdm_misc);
	vfree(buf);
	iounmap(gp);
	iounmap(gi);
}

module_init(pdm_init);
module_exit(pdm_exit);
MODULE_DESCRIPTION("E72 digital mic probe / bit-bang capture (draft)");
MODULE_LICENSE("GPL");
