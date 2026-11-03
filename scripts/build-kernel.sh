#!/usr/bin/env bash
# Kernel build, in two phases, because this lab boots a user-supplied DTB:
#   prepare -> configure + modules_prepare, so an out-of-tree module can build
#   image   -> builds Image with the initramfs embedded (INITRAMFS_SOURCE) and a
#              default cmdline, since QEMU does not reliably inject bootargs or
#              initrd addresses into a -dtb file.
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)
PHASE="${1:?usage: build-kernel.sh prepare|image}"
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
fi

case "$PHASE" in
prepare)
	./scripts/config --file .config --disable INITRAMFS_SOURCE
	make ARCH=$ARCH olddefconfig
	say "modules_prepare"
	make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" modules_prepare
	;;
image)
	INITRD="$WORK/initramfs.cpio.gz"
	[ -f "$INITRD" ] || { echo "missing $INITRD -- run: make initramfs"; exit 1; }
	./scripts/config --file .config \
		--set-str INITRAMFS_SOURCE "$INITRD" \
		--enable CMDLINE_BOOL \
		--enable CMDLINE \
		--set-str CMDLINE "console=ttyAMA0 rdinit=/init panic=-1" \
		--disable CMDLINE_FORCE
	make ARCH=$ARCH olddefconfig
	grep -E '^CONFIG_(INITRAMFS_SOURCE|CMDLINE)=' .config
	say "build Image with $(nproc) jobs"
	time make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" Image
	ls -lh arch/arm64/boot/Image
	;;
*)
	echo "unknown phase: $PHASE"
	exit 2
	;;
esac
