// SPDX-License-Identifier: GPL-2.0
/*
 * gpiotest - tiny GPIO character-device (uAPI v2) client for the lab.
 *
 * This is what libgpiod's gpioset/gpioget do underneath, written out so the
 * ioctls are visible. Linked static, it runs in the busybox initramfs.
 *
 *   gpiotest /dev/gpiochipN info          name=... label=... lines=N
 *   gpiotest /dev/gpiochipN loop LINE     drive 1 then 0, read each back
 *   gpiotest /dev/gpiochipN busy LINE     is LINE already claimed by a driver?
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int cmd_info(int fd)
{
	struct gpiochip_info ci;

	memset(&ci, 0, sizeof(ci));
	if (ioctl(fd, GPIO_GET_CHIPINFO_IOCTL, &ci) < 0) {
		perror("GPIO_GET_CHIPINFO_IOCTL");
		return 1;
	}
	printf("name=%s label=%s lines=%u\n", ci.name, ci.label, ci.lines);
	return 0;
}

static int request_line(int fd, unsigned int line, __u64 flags)
{
	struct gpio_v2_line_request req;

	memset(&req, 0, sizeof(req));
	req.offsets[0] = line;
	req.num_lines = 1;
	req.config.flags = flags;
	strncpy(req.consumer, "gpiotest", sizeof(req.consumer) - 1);
	if (ioctl(fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0)
		return -errno;
	return req.fd;	/* the line handle: every later ioctl goes here */
}

static int set_get(int lfd, int value)
{
	struct gpio_v2_line_values v;

	memset(&v, 0, sizeof(v));
	v.mask = 1;
	v.bits = value ? 1 : 0;
	if (ioctl(lfd, GPIO_V2_LINE_SET_VALUES_IOCTL, &v) < 0)
		return -errno;

	memset(&v, 0, sizeof(v));
	v.mask = 1;
	if (ioctl(lfd, GPIO_V2_LINE_GET_VALUES_IOCTL, &v) < 0)
		return -errno;
	return (int)(v.bits & 1);
}

static int cmd_loop(int fd, unsigned int line)
{
	int lfd, hi, lo;

	lfd = request_line(fd, line, GPIO_V2_LINE_FLAG_OUTPUT);
	if (lfd < 0) {
		printf("line=%u request-failed=%s\n", line, strerror(-lfd));
		return 1;
	}
	hi = set_get(lfd, 1);
	lo = set_get(lfd, 0);
	close(lfd);
	printf("line=%u hi=%d lo=%d\n", line, hi, lo);
	return !(hi == 1 && lo == 0);
}

static int cmd_busy(int fd, unsigned int line)
{
	int lfd = request_line(fd, line, GPIO_V2_LINE_FLAG_INPUT);

	if (lfd >= 0) {
		close(lfd);
		printf("line=%u busy=no\n", line);
		return 0;
	}
	printf("line=%u busy=%s\n", line, lfd == -EBUSY ? "yes" : strerror(-lfd));
	return 0;
}

int main(int argc, char **argv)
{
	int fd, rc;

	if (argc < 3) {
		fprintf(stderr, "usage: %s /dev/gpiochipN info|loop LINE|busy LINE\n", argv[0]);
		return 2;
	}
	fd = open(argv[1], O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror(argv[1]);
		return 1;
	}
	if (!strcmp(argv[2], "info"))
		rc = cmd_info(fd);
	else if (!strcmp(argv[2], "loop") && argc > 3)
		rc = cmd_loop(fd, strtoul(argv[3], NULL, 0));
	else if (!strcmp(argv[2], "busy") && argc > 3)
		rc = cmd_busy(fd, strtoul(argv[3], NULL, 0));
	else
		rc = 2;
	close(fd);
	return rc;
}
