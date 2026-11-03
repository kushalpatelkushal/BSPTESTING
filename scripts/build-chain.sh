#!/usr/bin/env bash
# Build the pre-kernel stages: U-Boot (BL33) and ARM Trusted Firmware (BL1/BL2/BL31).
# Mainline clones are intentionally unpinned -- when this job breaks, that is a
# real signal that the boot chain moved under you.
set -euo pipefail
source "$(dirname "$0")/env.sh"

UBOOT="$WORK/u-boot"
TFA="$WORK/tf-a"

say "clone u-boot + trusted-firmware-a"
[ -d "$UBOOT" ] || git clone --depth 1 https://source.denx.de/u-boot/u-boot.git "$UBOOT"
[ -d "$TFA" ] || git clone --depth 1 https://github.com/ARM-software/arm-trusted-firmware.git "$TFA"
git -C "$UBOOT" describe --always --tags
git -C "$TFA" describe --always --tags

say "u-boot: qemu_arm64"
make -C "$UBOOT" CROSS_COMPILE="$CROSS_COMPILE" qemu_arm64_defconfig
make -C "$UBOOT" CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"
ls -lh "$UBOOT/u-boot.bin"

# TF-A's QEMU virt Armv8-A port is PLAT=qemu (docs/plat/qemu.rst); qemu_arm64 is
# U-Boot's board name, not a TF-A platform.
say "tf-a: PLAT=qemu, BL33=u-boot.bin"
make -C "$TFA" PLAT=qemu CROSS_COMPILE="$CROSS_COMPILE" \
	BL33="$UBOOT/u-boot.bin" -j"$(nproc)" all fip

BL1=$(find "$TFA/build/qemu" -name bl1.bin | sed -n '1p')
FIP=$(find "$TFA/build/qemu" -name fip.bin | sed -n '1p')
if [ -z "$BL1" ] || [ -z "$FIP" ]; then
	echo "bl1.bin/fip.bin not found under $TFA/build/qemu"
	exit 1
fi

{
	echo "BL1=$BL1"
	echo "FIP=$FIP"
	echo "UBOOT_BIN=$UBOOT/u-boot.bin"
} | tee "$WORK/chain.env"
