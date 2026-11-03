#!/usr/bin/env bash
# Static busybox + our out-of-tree module + /init -> work/initramfs.cpio.gz
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOTFS="$WORK/rootfs"

say "busybox"
BB="$WORK/busybox-$(cat "$WORK/busybox.version")"
cd "$BB"
if [ ! -f .config ]; then
	make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" defconfig
	./scripts/config --file .config \
		--enable STATIC \
		--enable INSMOD --enable LSMOD --enable RMMOD \
		--enable DMSG --enable MKNOD --enable MOUNT --enable UMOUNT \
		--enable POWEROFF --enable REBOOT --enable HALT \
		--enable CAT --enable ECHO --enable LS --enable FIND --enable GREP \
		--enable SED --enable AWK --enable CP --enable MKDIR --enable TOUCH \
		--enable LN --enable RM --enable SLEEP --enable UNAME --enable DATE \
		--enable PRINTF --enable TAIL --enable HEAD --enable WC --enable TRUE --enable TEST
	yes "" | make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" oldconfig
fi
time make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"
rm -rf "$ROOTFS"
make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" CONFIG_PREFIX="$ROOTFS" install >/dev/null

say "hello_demo.ko"
bash "$LAB_ROOT/scripts/build-module.sh"
mkdir -p "$ROOTFS/lib/modules"
cp "$LAB_ROOT/drivers/hello_demo/hello_demo.ko" "$ROOTFS/lib/modules/"

say "initramfs"
mkdir -p "$ROOTFS"/{proc,sys,dev,etc,tmp}
cp "$LAB_ROOT/rootfs/init" "$ROOTFS/init"
chmod +x "$ROOTFS/init"
# devtmpfs (enabled in the kernel) creates /dev/console and the driver's node.
rm -f "$ROOTFS/linux"

cd "$ROOTFS"
find . | cpio --create --format=newc --quiet | gzip -9n >"$WORK/initramfs.cpio.gz"
ls -lh "$WORK/initramfs.cpio.gz"
