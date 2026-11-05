// SPDX-License-Identifier: GPL-2.0
/*
 * labgpio - a from-scratch driver for the ARM PrimeCell PL061 GPIO block that
 * QEMU's "virt" machine puts at 0x09030000.
 *
 * Unlike hello_demo, this driver talks to (emulated) silicon:
 *
 *   - it is an AMBA driver, not a platform driver: the DT node says
 *     "arm,primecell", so the kernel creates an amba_device, reads the
 *     peripheral ID registers at 0xfe0..0xfff and matches on that ID
 *   - it maps the register window (devm_ioremap_resource) and drives the
 *     hardware with readb()/writeb()
 *   - it registers a gpio_chip, so lines show up as /dev/gpiochipN and other
 *     drivers (here: gpio-keys) can consume them through the DT phandle
 *   - it is an interrupt controller in its own right: one GIC SPI fans out to
 *     eight GPIO interrupts through a chained handler and an irq_domain that
 *     gpiolib builds for us (GPIOLIB_IRQCHIP)
 *
 * The in-kernel gpio-pl061 is switched off in the lab's kernel config, so this
 * module is the only thing that can bind. Register map: ARM DDI 0190B.
 */
#include <linux/amba/bus.h>
#include <linux/atomic.h>
#include <linux/bitops.h>
#include <linux/debugfs.h>
#include <linux/gpio/driver.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/irqchip/chained_irq.h>
#include <linux/module.h>
#include <linux/seq_file.h>
#include <linux/spinlock.h>

/*
 * The data register is not one address. Address bits [9:2] are a mask: a read
 * returns only the lines whose bit is set in the address, and a write changes
 * only those lines. That makes every single-line update atomic without a
 * read-modify-write, which is why there is no lock around get/set below.
 */
#define LAB_DATA(mask)	((mask) << 2)
#define LAB_DIR		0x400	/* 1 = output */
#define LAB_IS		0x404	/* interrupt sense: 1 = level, 0 = edge */
#define LAB_IBE		0x408	/* 1 = both edges (overrides IEV) */
#define LAB_IEV		0x40c	/* 1 = rising edge / high level */
#define LAB_IE		0x410	/* interrupt mask: 1 = enabled */
#define LAB_RIS		0x414	/* raw interrupt status */
#define LAB_MIS		0x418	/* masked interrupt status */
#define LAB_IC		0x41c	/* write 1 to clear an edge interrupt */

#define LAB_NGPIO	8

struct labgpio {
	/*
	 * raw_spinlock, not spinlock: irq_chip callbacks run with the irq
	 * descriptor lock held and interrupts off, and on PREEMPT_RT a plain
	 * spinlock_t becomes a sleeping lock that must not be taken there.
	 */
	raw_spinlock_t lock;
	void __iomem *base;
	struct gpio_chip gc;
	int parent_irq;
	atomic_t parent_hits;	/* how often the chained handler ran */
	struct dentry *dbg;
};

/* ---- gpio_chip: the part consumers and /dev/gpiochipN use ------------- */

static int labgpio_get_direction(struct gpio_chip *gc, unsigned int off)
{
	struct labgpio *lg = gpiochip_get_data(gc);

	return readb(lg->base + LAB_DIR) & BIT(off) ?
		GPIO_LINE_DIRECTION_OUT : GPIO_LINE_DIRECTION_IN;
}

static int labgpio_direction_input(struct gpio_chip *gc, unsigned int off)
{
	struct labgpio *lg = gpiochip_get_data(gc);
	unsigned long flags;

	/* DIR is a normal register shared by all lines: this one does need RMW. */
	raw_spin_lock_irqsave(&lg->lock, flags);
	writeb(readb(lg->base + LAB_DIR) & ~BIT(off), lg->base + LAB_DIR);
	raw_spin_unlock_irqrestore(&lg->lock, flags);

	return 0;
}

static int labgpio_direction_output(struct gpio_chip *gc, unsigned int off,
				    int value)
{
	struct labgpio *lg = gpiochip_get_data(gc);
	unsigned long flags;

	raw_spin_lock_irqsave(&lg->lock, flags);
	writeb(readb(lg->base + LAB_DIR) | BIT(off), lg->base + LAB_DIR);
	/*
	 * Write the level only after the pin is an output: the PL061 ignores
	 * data writes to input pins (QEMU models exactly that). Setting it
	 * first would leave the line at its old level until the next set().
	 * A real board would also care about a glitch here; drivers that do
	 * write the value both before and after flipping DIR.
	 */
	writeb(value ? BIT(off) : 0, lg->base + LAB_DATA(BIT(off)));
	raw_spin_unlock_irqrestore(&lg->lock, flags);

	return 0;
}

static int labgpio_get(struct gpio_chip *gc, unsigned int off)
{
	struct labgpio *lg = gpiochip_get_data(gc);

	return !!readb(lg->base + LAB_DATA(BIT(off)));
}

/* Since 6.17 gpio_chip::set returns int so bus-backed expanders can fail. */
static int labgpio_set(struct gpio_chip *gc, unsigned int off, int value)
{
	struct labgpio *lg = gpiochip_get_data(gc);

	writeb(value ? BIT(off) : 0, lg->base + LAB_DATA(BIT(off)));
	return 0;
}

/* ---- irq_chip: the part that turns pin changes into Linux IRQs ------- */

static void labgpio_irq_ack(struct irq_data *d)
{
	struct gpio_chip *gc = irq_data_get_irq_chip_data(d);
	struct labgpio *lg = gpiochip_get_data(gc);

	/* IC is write-1-to-clear: no RMW, other lines are untouched. */
	writeb(BIT(irqd_to_hwirq(d)), lg->base + LAB_IC);
}

static void labgpio_irq_mask(struct irq_data *d)
{
	struct gpio_chip *gc = irq_data_get_irq_chip_data(d);
	struct labgpio *lg = gpiochip_get_data(gc);
	irq_hw_number_t hwirq = irqd_to_hwirq(d);

	raw_spin_lock(&lg->lock);
	writeb(readb(lg->base + LAB_IE) & ~BIT(hwirq), lg->base + LAB_IE);
	raw_spin_unlock(&lg->lock);

	/* Tell gpiolib the line is no longer used as an IRQ (immutable chip). */
	gpiochip_disable_irq(gc, hwirq);
}

static void labgpio_irq_unmask(struct irq_data *d)
{
	struct gpio_chip *gc = irq_data_get_irq_chip_data(d);
	struct labgpio *lg = gpiochip_get_data(gc);
	irq_hw_number_t hwirq = irqd_to_hwirq(d);

	gpiochip_enable_irq(gc, hwirq);

	raw_spin_lock(&lg->lock);
	writeb(readb(lg->base + LAB_IE) | BIT(hwirq), lg->base + LAB_IE);
	raw_spin_unlock(&lg->lock);
}

static int labgpio_irq_set_type(struct irq_data *d, unsigned int type)
{
	struct gpio_chip *gc = irq_data_get_irq_chip_data(d);
	struct labgpio *lg = gpiochip_get_data(gc);
	u8 bit = BIT(irqd_to_hwirq(d));
	u8 is, ibe, iev;
	unsigned long flags;

	raw_spin_lock_irqsave(&lg->lock, flags);
	is = readb(lg->base + LAB_IS) & ~bit;
	ibe = readb(lg->base + LAB_IBE) & ~bit;
	iev = readb(lg->base + LAB_IEV) & ~bit;

	switch (type & IRQ_TYPE_SENSE_MASK) {
	case IRQ_TYPE_EDGE_RISING:
		iev |= bit;
		break;
	case IRQ_TYPE_EDGE_FALLING:
		break;
	case IRQ_TYPE_EDGE_BOTH:
		ibe |= bit;
		break;
	case IRQ_TYPE_LEVEL_HIGH:
		is |= bit;
		iev |= bit;
		break;
	case IRQ_TYPE_LEVEL_LOW:
		is |= bit;
		break;
	default:
		raw_spin_unlock_irqrestore(&lg->lock, flags);
		return -EINVAL;
	}

	writeb(is, lg->base + LAB_IS);
	writeb(ibe, lg->base + LAB_IBE);
	writeb(iev, lg->base + LAB_IEV);
	raw_spin_unlock_irqrestore(&lg->lock, flags);

	/*
	 * Edge interrupts are latched and must be acked (handle_edge_irq calls
	 * irq_ack); level interrupts clear themselves when the pin goes away
	 * and must be masked while the handler runs (handle_level_irq).
	 */
	if (type & IRQ_TYPE_LEVEL_MASK)
		irq_set_handler_locked(d, handle_level_irq);
	else
		irq_set_handler_locked(d, handle_edge_irq);

	return 0;
}

static void labgpio_irq_print_chip(struct irq_data *d, struct seq_file *p)
{
	struct gpio_chip *gc = irq_data_get_irq_chip_data(d);

	/* This is the chip name column of /proc/interrupts. */
	seq_puts(p, dev_name(gc->parent));
}

static const struct irq_chip labgpio_irq_chip = {
	.irq_ack	= labgpio_irq_ack,
	.irq_mask	= labgpio_irq_mask,
	.irq_unmask	= labgpio_irq_unmask,
	.irq_set_type	= labgpio_irq_set_type,
	.irq_print_chip	= labgpio_irq_print_chip,
	.flags		= IRQCHIP_IMMUTABLE,
	GPIOCHIP_IRQ_RESOURCE_HELPERS,
};

/*
 * Chained handler for the one GIC line. It is not a normal ISR: it runs as
 * the flow handler of the parent IRQ, finds which pins are pending and hands
 * each one to its own Linux IRQ in our domain.
 */
static void labgpio_parent_handler(struct irq_desc *desc)
{
	struct gpio_chip *gc = irq_desc_get_handler_data(desc);
	struct labgpio *lg = gpiochip_get_data(gc);
	struct irq_chip *parent = irq_desc_get_chip(desc);
	unsigned long pending;
	unsigned int off;

	chained_irq_enter(parent, desc);
	atomic_inc(&lg->parent_hits);

	pending = readb(lg->base + LAB_MIS);
	for_each_set_bit(off, &pending, LAB_NGPIO)
		generic_handle_domain_irq(gc->irq.domain, off);

	chained_irq_exit(parent, desc);
}

/* ---- debugfs: what you look at first when bring-up goes wrong -------- */

static int labgpio_regs_show(struct seq_file *s, void *unused)
{
	struct labgpio *lg = s->private;

	seq_printf(s, "DATA 0x%02x\n", readb(lg->base + LAB_DATA(0xff)));
	seq_printf(s, "DIR  0x%02x\n", readb(lg->base + LAB_DIR));
	seq_printf(s, "IS   0x%02x\n", readb(lg->base + LAB_IS));
	seq_printf(s, "IBE  0x%02x\n", readb(lg->base + LAB_IBE));
	seq_printf(s, "IEV  0x%02x\n", readb(lg->base + LAB_IEV));
	seq_printf(s, "IE   0x%02x\n", readb(lg->base + LAB_IE));
	seq_printf(s, "RIS  0x%02x\n", readb(lg->base + LAB_RIS));
	seq_printf(s, "MIS  0x%02x\n", readb(lg->base + LAB_MIS));
	seq_printf(s, "parent-irq-hits %d\n", atomic_read(&lg->parent_hits));
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(labgpio_regs);

static void labgpio_debugfs_remove(void *data)
{
	struct labgpio *lg = data;

	debugfs_remove_recursive(lg->dbg);
}

/* ---- probe ----------------------------------------------------------- */

static int labgpio_probe(struct amba_device *adev, const struct amba_id *id)
{
	struct device *dev = &adev->dev;
	struct gpio_irq_chip *girq;
	struct labgpio *lg;
	int ret;

	lg = devm_kzalloc(dev, sizeof(*lg), GFP_KERNEL);
	if (!lg)
		return -ENOMEM;

	/* adev->res is the DT "reg" property, already parsed by the AMBA bus. */
	lg->base = devm_ioremap_resource(dev, &adev->res);
	if (IS_ERR(lg->base))
		return PTR_ERR(lg->base);

	lg->parent_irq = adev->irq[0];
	if (!lg->parent_irq)
		return dev_err_probe(dev, -ENXIO, "no interrupt in DT\n");

	raw_spin_lock_init(&lg->lock);
	atomic_set(&lg->parent_hits, 0);

	/* Quiesce the block: firmware may have left interrupts enabled. */
	writeb(0, lg->base + LAB_IE);
	writeb(0xff, lg->base + LAB_IC);

	lg->gc.label = dev_name(dev);
	lg->gc.parent = dev;
	lg->gc.owner = THIS_MODULE;	/* consumers pin the module */
	lg->gc.base = -1;		/* dynamic numbering, always */
	lg->gc.ngpio = LAB_NGPIO;
	lg->gc.get_direction = labgpio_get_direction;
	lg->gc.direction_input = labgpio_direction_input;
	lg->gc.direction_output = labgpio_direction_output;
	lg->gc.get = labgpio_get;
	lg->gc.set = labgpio_set;

	girq = &lg->gc.irq;
	gpio_irq_chip_set_chip(girq, &labgpio_irq_chip);
	girq->parent_handler = labgpio_parent_handler;
	girq->num_parents = 1;
	girq->parents = devm_kcalloc(dev, 1, sizeof(*girq->parents), GFP_KERNEL);
	if (!girq->parents)
		return -ENOMEM;
	girq->parents[0] = lg->parent_irq;
	girq->default_type = IRQ_TYPE_NONE;	/* consumers pick via set_type */
	girq->handler = handle_bad_irq;		/* until set_type runs */

	ret = devm_gpiochip_add_data(dev, &lg->gc, lg);
	if (ret)
		return dev_err_probe(dev, ret, "gpiochip registration failed\n");

	/*
	 * devm actions unwind in reverse order, so debugfs disappears before
	 * the gpiochip does and a reader can never see a dead mapping.
	 */
	lg->dbg = debugfs_create_dir("labgpio", NULL);
	debugfs_create_file("regs", 0444, lg->dbg, lg, &labgpio_regs_fops);
	ret = devm_add_action_or_reset(dev, labgpio_debugfs_remove, lg);
	if (ret)
		return ret;

	amba_set_drvdata(adev, lg);
	dev_info(dev, "labgpio: %u lines at %pR, parent irq %d, periphid 0x%08x\n",
		 lg->gc.ngpio, &adev->res, lg->parent_irq, adev->periphid);
	return 0;
}

/* Matched on the PrimeCell peripheral ID, not on a compatible string. */
static const struct amba_id labgpio_ids[] = {
	{ .id = 0x00041061, .mask = 0x000fffff },
	{ 0, 0 },
};
MODULE_DEVICE_TABLE(amba, labgpio_ids);

static struct amba_driver labgpio_driver = {
	.drv = {
		.name = "labgpio",
	},
	.id_table = labgpio_ids,
	.probe = labgpio_probe,
};
module_amba_driver(labgpio_driver);

MODULE_DESCRIPTION("From-scratch PL061 GPIO + irqchip driver for the board-free BSP lab");
MODULE_LICENSE("GPL");
