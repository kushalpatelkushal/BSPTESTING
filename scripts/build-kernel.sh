#!/usr/bin/env bash
# arm64 defconfig plus the options this lab needs (modules, initrd, DT, devtmpfs).
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)
cd "$KDIR"

ENABLE=(
	BLK_DEV_INITRD
	DEVTMPFS
	DEVTMPFS_MOUNT
	MODULES
	OF
	OF_DYNAMIC
	OF_CONFIGFS
	CONFIGFS_FS
	SERIAL_AMBA_PL011
	SERIAL_AMBA_PL011_CONSOLE
	KALLSYMS
)
DISABLE=(DEBUG_INFO)

if [ ! -f .config ]; then
	say "defconfig"
	make ARCH=$ARCH defconfig
	./scripts/config --file .config "${ENABLE[@]/#/--enable}" "${DISABLE[@]/#/--disable}"
	make ARCH=$ARCH olddefconfig
fi

say "build Image with $(nproc) jobs"
time make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" Image
ls -lh arch/arm64/boot/Image
