#!/usr/bin/env bash
# Fast loop for editing the driver: make module && make initramfs && make boot
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

make -C "$KDIR" M="$LAB_ROOT/drivers/hello_demo" ARCH=$ARCH \
	CROSS_COMPILE="$CROSS_COMPILE" modules
ls -lh "$LAB_ROOT/drivers/hello_demo/hello_demo.ko"
modinfo "$LAB_ROOT/drivers/hello_demo/hello_demo.ko" | sed -n '1,12p'
