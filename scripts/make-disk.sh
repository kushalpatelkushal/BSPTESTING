#!/usr/bin/env bash
# FAT disk image holding kernel Image + initramfs + patched DTB, for U-Boot to
# load over virtio.
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

say "make work/disk.img (vfat)"
DISK="$WORK/disk.img"
rm -f "$DISK"
dd if=/dev/zero of="$DISK" bs=1M count=64 status=none
mkfs.vfat -F 32 "$DISK" >/dev/null

mcopy -i "$DISK" "$KDIR/arch/arm64/boot/Image" ::/Image
mcopy -i "$DISK" "$WORK/virt-hello.dtb" ::/hello.dtb
say "disk contents"
mdir -i "$DISK" ::/
