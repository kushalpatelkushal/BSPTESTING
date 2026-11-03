// SPDX-License-Identifier: GPL-2.0
// Platform driver bound from a device tree node, with sysfs attributes and a
// misc /dev node. Deliberately has no reg/ioremap so it runs under QEMU.
#include <linux/fs.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/uaccess.h>

struct hello_priv {
	struct miscdevice misc;
	u32 channels;
	const char *model;
	u32 reads;
};

static struct hello_priv *to_hello(struct device *dev)
{
	return dev_get_drvdata(dev);
}

static ssize_t channels_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%u\n", to_hello(dev)->channels);
}
static DEVICE_ATTR_RO(channels);

static ssize_t model_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "%s\n", to_hello(dev)->model);
}
static DEVICE_ATTR_RO(model);

static struct attribute *hello_attrs[] = {
	&dev_attr_channels.attr,
	&dev_attr_model.attr,
	NULL,
};
ATTRIBUTE_GROUPS(hello);

static ssize_t hello_read(struct file *filp, char __user *buf, size_t count, loff_t *ppos)
{
	struct miscdevice *misc = filp->private_data;
	struct hello_priv *priv = container_of(misc, struct hello_priv, misc);
	char msg[128];
	int len;

	if (*ppos == 0)
		priv->reads++;

	len = scnprintf(msg, sizeof(msg), "channels=%u model=%s reads=%u\n",
		       priv->channels, priv->model, priv->reads);

	return simple_read_from_buffer(buf, count, ppos, msg, len);
}

static const struct file_operations hello_fops = {
	.owner = THIS_MODULE,
	.read = hello_read,
	.llseek = default_llseek,
};

static int hello_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct device_node *np = dev->of_node;
	const char *model;
	struct hello_priv *priv;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	priv->channels = 1;
	priv->model = "unknown";
	if (np) {
		if (of_property_read_u32(np, "qoder,channels", &priv->channels))
			dev_info(dev, "no qoder,channels property, defaulting to 1\n");
		if (!of_property_read_string(np, "qoder,model", &model))
			priv->model = model;
	}

	priv->misc.minor = MISC_DYNAMIC_MINOR;
	priv->misc.name = "hello";
	priv->misc.fops = &hello_fops;
	priv->misc.parent = dev;

	dev_set_drvdata(dev, priv);

	ret = misc_register(&priv->misc);
	if (ret) {
		dev_set_drvdata(dev, NULL);
		return ret;
	}

	dev_info(dev, "probed of_node=%pOF channels=%u model=%s\n",
		 np, priv->channels, priv->model);

	return 0;
}

static void hello_remove(struct platform_device *pdev)
{
	struct hello_priv *priv = dev_get_drvdata(&pdev->dev);

	misc_deregister(&priv->misc);
	dev_info(&pdev->dev, "removed\n");
}

static const struct of_device_id hello_of_match[] = {
	{ .compatible = "qoder,hello-demo" },
	{ /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, hello_of_match);

static struct platform_driver hello_driver = {
	.probe = hello_probe,
	.remove = hello_remove,
	.driver = {
		.name = "hello-demo",
		.of_match_table = hello_of_match,
		.dev_groups = hello_groups,
	},
};
module_platform_driver(hello_driver);

MODULE_DESCRIPTION("Device-tree bound demo platform driver for the board-free BSP lab");
MODULE_LICENSE("GPL");
