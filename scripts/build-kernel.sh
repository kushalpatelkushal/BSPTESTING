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
	OF_OVERLAY
	CONFIGFS_FS
	SERIAL_AMBA_PL011
	SERIAL_AMBA_PL011_CONSOLE
	KALLSYMS
)
DISABLE=(DEBUG_INFO)

# scripts/config takes the command and the symbol as two separate arguments.
config_args=()
for s in "${ENABLE[@]}"; do config_args+=(--enable "$s"); done
for s in "${DISABLE[@]}"; do config_args+=(--disable "$s"); done

if [ ! -f .config ]; then
	say "defconfig"
	make ARCH=$ARCH defconfig
	./scripts/config --file .config "${config_args[@]}"
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
	# arm64 has no CMDLINE_BOOL: CONFIG_CMDLINE is a plain string and the
	# CMDLINE_FROM_BOOTLOADER / CMDLINE_FORCE choice only appears once it is
	# non-empty. From-bootloader is what we want, so do not force it.
	./scripts/config --file .config \
		--set-str INITRAMFS_SOURCE "$INITRD" \
		--set-str CMDLINE "console=ttyAMA0 rdinit=/init panic=-1"
	make ARCH=$ARCH olddefconfig
	grep -E '^CONFIG_(INITRAMFS_SOURCE|CMDLINE)=' .config ||
		echo "WARNING: INITRAMFS_SOURCE or CMDLINE not in the final config -- the kernel will boot without our initramfs"
	# Everything the lab silently depends on. A symbol that quietly failed to
	# enable shows up here instead of as an unexplained boot failure.
	grep -E '^CONFIG_(BLK_DEV_INITRD|DEVTMPFS|DEVTMPFS_MOUNT|MODULES|OF|OF_DYNAMIC|OF_OVERLAY|CONFIGFS_FS|SERIAL_AMBA_PL011|SERIAL_AMBA_PL011_CONSOLE)=' .config ||
		echo "WARNING: one or more lab config symbols are missing"
	say "build Image with $(nproc) jobs"
	time make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" Image
	ls -lh arch/arm64/boot/Image
	;;
*)
	echo "unknown phase: $PHASE"
	exit 2
	;;
esac
