// SPDX-License-Identifier: GPL-2.0-only
/*
 * Nokia E5-00 (RapuYama) QWERTY keyboard: 8x8 GPIO matrix, polled.
 *
 * Copies the scan of the E5 ROM's ekeyb.dll (0x80157d78 / 0x80157e28):
 * column lines (outputs, gpio 0 3 13 33 36 38 45 55) are all driven high
 * except the scanned one, which is driven low; a pressed key pulls its row
 * line (gpio 114..119 121 2) to 0. The row level is read from the gpio irq
 * block's RAW state register, which uses the egpio "logical" pin number
 * (gpio >= 106 -> gpio - 18). The plain gpio input register does NOT show
 * these pins (checked on the device, K1/K2 2026-10-31).
 *
 * Pin directions are left as Symbian set them (columns outputs, all low at
 * rest; rows inputs). Nothing else in the gpio block is written: only the
 * set/clear registers of the eight column pins. At rest all columns are low
 * again, so an idle check costs two register reads.
 *
 * Without a "linux,keymap" property every key is reported as MSC_SCAN only,
 * and the learn parameter logs "key rN cM down/up" to find the layout.
 */
#include <linux/bitops.h>
#include <linux/delay.h>
#include <linux/input.h>
#include <linux/input/matrix_keypad.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/platform_device.h>
#include <linux/property.h>
#include <linux/workqueue.h>

#define E5KP_ROWS	8
#define E5KP_COLS	8
#define E5KP_ROW_SHIFT	3

/* gpio block (phys 0x20031900): output set / clear, bank k */
#define GPIO_OUT_SET(k)	(0x94 + 0x10 * (k))
#define GPIO_OUT_CLR(k)	(0x98 + 0x10 * (k))
/* direction, write 1 = that pin becomes input / output (egpio, K0) */
#define GPIO_DIR_IN(k)	(0xf4 + 0x10 * (k))
#define GPIO_DIR_OUT(k)	(0xf8 + 0x10 * (k))
/* irq block (phys 0x20033400): raw pin state, logical bank k */
#define IRQ_RAW(k)	(0x40 * (k) + 0x08)

/* ekeyb.dll defaults, RAM copies c8009c34 (rows) / c8009c54 (cols) */
static const u8 e5kp_row_gpio[E5KP_ROWS] = { 114, 115, 116, 117, 118, 119, 121, 2 };
static const u8 e5kp_col_gpio[E5KP_COLS] = { 0, 3, 13, 33, 36, 38, 45, 55 };
/* other boards (E72: 8 rows, 7 columns on other pins) name theirs in the
 * device tree: "nokia,row-gpios" / "nokia,col-gpios", u8 arrays */
#define E5KP_BANKS	4

static bool learn = true;
module_param(learn, bool, 0644);
MODULE_PARM_DESC(learn, "log every key change as row/column (default off)");

/* two keys on one row tie a low and a high column together when the idle
 * columns are driven high: the row then reads wrong (sym+@ on r0). hiz=1
 * floats the idle columns (input) instead, only the scanned one drives low
 */
static unsigned int p_rows[8] = { 26, 119, 35, 24, 120, 121, 38, 36 }, n_rows = 8;
static unsigned int p_cols[8] = { 61, 60, 59, 58, 62, 57, 56 }, n_cols = 7;
module_param_array_named(rows, p_rows, uint, &n_rows, 0444);
module_param_array_named(cols, p_cols, uint, &n_cols, 0444);
/* from symbian's ekeyb scan table (c8009a68), keys named by position */
static unsigned int p_keymap[64] = { 0x00000010, 0x00010011, 0x00020012, 0x00030013, 0x00040014, 0x00050015, 0x00060016, 0x0100001e, 0x0101001f, 0x01020020, 0x01030021, 0x01040022, 0x01050023, 0x01060024, 0x0200002c, 0x0201002d, 0x0202002e, 0x0203002f, 0x02040030, 0x02050031, 0x02060032, 0x03000017, 0x03010018, 0x03020019, 0x0303001d, 0x03040028, 0x03050001, 0x0306000f, 0x04000025, 0x04010026, 0x0402000e, 0x0403003b, 0x0404002a, 0x0405003c, 0x04060038, 0x05000033, 0x05010034, 0x0502001c, 0x0503007d, 0x0504006b, 0x05050027, 0x0506003d, 0x06000064, 0x06010039, 0x0602003e, 0x0603003f, 0x06040040, 0x06050041, 0x06060061, 0x07000067, 0x0701006c, 0x07020069, 0x0703006a, 0x0704001c, 0x07060042 };
static unsigned int n_keymap = 55;
module_param_array_named(keymap, p_keymap, uint, &n_keymap, 0444);
static bool hiz = true;
module_param(hiz, bool, 0644);
MODULE_PARM_DESC(hiz, "float idle columns while scanning (default on, 0 = drive them high)");

static unsigned int poll_ms = 20;
module_param(poll_ms, uint, 0644);
MODULE_PARM_DESC(poll_ms, "scan interval in ms (default 20)");

static unsigned int col_delay_us = 5;
module_param(col_delay_us, uint, 0644);
MODULE_PARM_DESC(col_delay_us, "settle time after driving a column, us (default 5)");

struct e5kp {
	struct device *dev;
	struct input_dev *input;
	void __iomem *gpio;
	void __iomem *irq;
	struct delayed_work work;

	unsigned int nrows, ncols;
	u32 col_mask[E5KP_BANKS];	/* column bits per gpio bank */
	u8 col_bank[E5KP_COLS];
	u32 col_bit[E5KP_COLS];
	u8 row_bank[E5KP_ROWS];		/* logical irq-block bank */
	u32 row_bit[E5KP_ROWS];
	u8 row_banks;			/* bit k: bank k has a row */

	u8 state[E5KP_COLS];		/* reported: bit r of state[c] = pressed */
	u8 last[E5KP_COLS];		/* previous raw scan, for debouncing */
};

static void e5kp_cols_dir(struct e5kp *kp, bool out)
{
	int k;

	for (k = 0; k < E5KP_BANKS; k++)
		if (kp->col_mask[k])
			writel(kp->col_mask[k], kp->gpio +
			       (out ? GPIO_DIR_OUT(k) : GPIO_DIR_IN(k)));
}

static void e5kp_cols_level(struct e5kp *kp, bool high)
{
	int k;

	for (k = 0; k < E5KP_BANKS; k++)
		if (kp->col_mask[k])
			writel(kp->col_mask[k], kp->gpio +
			       (high ? GPIO_OUT_SET(k) : GPIO_OUT_CLR(k)));
}

/* bit r set = row r reads 0 (pressed) */
static u8 e5kp_rows(struct e5kp *kp)
{
	u32 raw[E5KP_BANKS];
	u8 rows = 0;
	int r, k;

	for (k = 0; k < E5KP_BANKS; k++)
		if (kp->row_banks & BIT(k))
			raw[k] = readl_relaxed(kp->irq + IRQ_RAW(k));
	for (r = 0; r < kp->nrows; r++)
		if (!(raw[kp->row_bank[r]] & kp->row_bit[r]))
			rows |= BIT(r);
	return rows;
}

static void e5kp_scan(struct e5kp *kp, u8 *cols)
{
	int c;

	memset(cols, 0, E5KP_COLS);
	/* at rest all columns are low: any key pulls its row down */
	if (!e5kp_rows(kp))
		return;

	if (hiz) {
		/* columns keep their low output latch, only the direction moves */
		e5kp_cols_dir(kp, false);
		for (c = 0; c < kp->ncols; c++) {
			void __iomem *g = kp->gpio;

			writel(kp->col_bit[c], g + GPIO_DIR_OUT(kp->col_bank[c]));
			udelay(col_delay_us);
			cols[c] = e5kp_rows(kp);
			writel(kp->col_bit[c], g + GPIO_DIR_IN(kp->col_bank[c]));
		}
		e5kp_cols_dir(kp, true);
		return;
	}

	for (c = 0; c < kp->ncols; c++) {
		e5kp_cols_level(kp, true);
		writel(kp->col_bit[c], kp->gpio + GPIO_OUT_CLR(kp->col_bank[c]));
		udelay(col_delay_us);
		cols[c] = e5kp_rows(kp);
	}
	e5kp_cols_level(kp, false);
}

static void e5kp_work(struct work_struct *work)
{
	struct e5kp *kp = container_of(to_delayed_work(work), struct e5kp, work);
	const unsigned short *keycode = kp->input->keycode;
	u8 cols[E5KP_COLS];
	bool sync = false;
	int c, r;

	e5kp_scan(kp, cols);

	/* accept a change only when two scans in a row agree */
	for (c = 0; c < E5KP_COLS; c++) {
		u8 stable = ~(cols[c] ^ kp->last[c]);
		u8 changed = (cols[c] ^ kp->state[c]) & stable;

		kp->last[c] = cols[c];
		for (r = 0; r < E5KP_ROWS; r++) {
			unsigned int code = MATRIX_SCAN_CODE(r, c, E5KP_ROW_SHIFT);
			bool down = cols[c] & BIT(r);

			if (!(changed & BIT(r)))
				continue;
			if (learn)
				dev_info(kp->dev, "key r%d c%d %s (keycode %u)\n",
					 r, c, down ? "down" : "up", keycode[code]);
			input_event(kp->input, EV_MSC, MSC_SCAN, code);
			input_report_key(kp->input, keycode[code], down);
			sync = true;
		}
		kp->state[c] ^= changed;
	}
	if (sync)
		input_sync(kp->input);

	schedule_delayed_work(&kp->work, msecs_to_jiffies(poll_ms));
}

static void e5kp_stop(void *data)
{
	struct e5kp *kp = data;

	cancel_delayed_work_sync(&kp->work);
	e5kp_cols_level(kp, false);
}

static int e5kp_probe(struct platform_device *pdev)
{
	struct matrix_keymap_data no_keymap = { .keymap = p_keymap, .keymap_size = n_keymap };
	struct device *dev = &pdev->dev;
	struct resource *res;
	u8 rowg[E5KP_ROWS], colg[E5KP_COLS];
	struct e5kp *kp;
	int i, ret;

	kp = devm_kzalloc(dev, sizeof(*kp), GFP_KERNEL);
	if (!kp)
		return -ENOMEM;
	kp->dev = dev;

	/* plain ioremap: the irq block range is also listed by the intc node */
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -EINVAL;
	kp->gpio = devm_ioremap(dev, res->start, resource_size(res));
	res = platform_get_resource(pdev, IORESOURCE_MEM, 1);
	if (!res)
		return -EINVAL;
	kp->irq = devm_ioremap(dev, res->start, resource_size(res));
	if (!kp->gpio || !kp->irq)
		return -ENOMEM;

	memcpy(rowg, e5kp_row_gpio, sizeof(rowg));
	memcpy(colg, e5kp_col_gpio, sizeof(colg));
	kp->nrows = E5KP_ROWS;
	kp->ncols = E5KP_COLS;
	if (n_rows && n_cols) {
		kp->nrows = n_rows; kp->ncols = n_cols;
		for (i = 0; i < n_rows; i++) rowg[i] = p_rows[i];
		for (i = 0; i < n_cols; i++) colg[i] = p_cols[i];
	}
	ret = device_property_count_u8(dev, "nokia,row-gpios");
	if (ret > 0 && ret <= E5KP_ROWS) {
		kp->nrows = ret;
		device_property_read_u8_array(dev, "nokia,row-gpios", rowg, ret);
	}
	ret = device_property_count_u8(dev, "nokia,col-gpios");
	if (ret > 0 && ret <= E5KP_COLS) {
		kp->ncols = ret;
		device_property_read_u8_array(dev, "nokia,col-gpios", colg, ret);
	}
	for (i = 0; i < kp->ncols; i++) {
		unsigned int g = colg[i];

		if (g / 32 >= E5KP_BANKS)
			return dev_err_probe(dev, -EINVAL, "column %d: gpio %u\n", i, g);
		kp->col_bank[i] = g / 32;
		kp->col_bit[i] = BIT(g % 32);
		kp->col_mask[g / 32] |= BIT(g % 32);
	}
	for (i = 0; i < kp->nrows; i++) {
		unsigned int l = rowg[i];

		if (l >= 106)
			l -= 18;
		if (l / 32 >= E5KP_BANKS)
			return dev_err_probe(dev, -EINVAL, "row %d: bank %u\n", i, l / 32);
		kp->row_bank[i] = l / 32;
		kp->row_bit[i] = BIT(l % 32);
		kp->row_banks |= BIT(l / 32);
	}

	kp->input = devm_input_allocate_device(dev);
	if (!kp->input)
		return -ENOMEM;
	kp->input->name = "Nokia E72 keyboard (test)";
	kp->input->phys = "rapuyama-e5-keypad/input0";
	kp->input->id.bustype = BUS_HOST;

	ret = matrix_keypad_build_keymap(device_property_present(dev, "linux,keymap") ?
					 NULL : &no_keymap, NULL,
					 E5KP_ROWS, E5KP_COLS, NULL, kp->input);
	if (ret)
		return dev_err_probe(dev, ret, "keymap\n");
	input_set_capability(kp->input, EV_MSC, MSC_SCAN);
	__set_bit(EV_REP, kp->input->evbit);

	ret = input_register_device(kp->input);
	if (ret)
		return ret;

	/* scan always runs (learn mode needs it without any input reader) */
	INIT_DELAYED_WORK(&kp->work, e5kp_work);
	ret = devm_add_action_or_reset(dev, e5kp_stop, kp);
	if (ret)
		return ret;
	schedule_delayed_work(&kp->work, 0);

	dev_info(dev, "%ux%u matrix, polled %u ms, %s keymap, learn %d\n",
		 kp->nrows, kp->ncols, poll_ms,
		 device_property_present(dev, "linux,keymap") ? "dt" : "no", learn);
	return 0;
}

static const struct of_device_id e5kp_of_match[] = {
	{ .compatible = "nokia,rapuyama-e72-keypad-test" },
	{ }
};
MODULE_DEVICE_TABLE(of, e5kp_of_match);

static struct platform_driver e5kp_driver = {
	.probe	= e5kp_probe,
	.driver	= {
		.name		= "rapuyama-e72-keypad-test",
		.of_match_table	= e5kp_of_match,
	},
};
static struct platform_device *e72kp_pdev;
static const struct resource e72kp_res[] = {
	DEFINE_RES_MEM(0x20031900, 0x200),
	DEFINE_RES_MEM(0x20033400, 0x140),
};
static int __init e72kp_init(void)
{
	int ret = platform_driver_register(&e5kp_driver);

	if (ret)
		return ret;
	e72kp_pdev = platform_device_register_simple("rapuyama-e72-keypad-test", -1,
						     e72kp_res, ARRAY_SIZE(e72kp_res));
	if (IS_ERR(e72kp_pdev)) {
		platform_driver_unregister(&e5kp_driver);
		return PTR_ERR(e72kp_pdev);
	}
	return 0;
}
static void __exit e72kp_exit(void)
{
	platform_device_unregister(e72kp_pdev);
	platform_driver_unregister(&e5kp_driver);
}
module_init(e72kp_init);
module_exit(e72kp_exit);

MODULE_DESCRIPTION("Nokia E5-00 RapuYama polled keyboard matrix");
MODULE_LICENSE("GPL");
