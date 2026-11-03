#!/usr/bin/env bash
# Static busybox + our out-of-tree module + /init -> work/initramfs.cpio.gz
#
# busybox has no scripts/config helper, so applets are turned on by editing
# .config and then verified: a symbol that silently fails to enable (typo, or an
# unmet dependency) would otherwise show up as a mysterious boot failure.
set -euo pipefail
source "$(dirname "$0")/env.sh"
ROOTFS="$WORK/rootfs"

# Verified against the busybox 1.38.0 tarball: applet symbols are declared either
# as "//config:config NAME" inside the applet .c file or in */Config.src.
REQUIRED=(
	STATIC SH_IS_ASH
	INSMOD RMMOD LSMOD
	MOUNT POWEROFF
	CAT ECHO LS GREP SED TR UNAME
)
BEST_EFFORT=(
	DMESG MKNOD UMOUNT REBOOT HALT
	FIND AWK CP MV MKDIR RM LN TOUCH
	SLEEP DATE PRINTF TAIL HEAD WC TRUE TEST
)
# busybox `defconfig` turns ~400 applets on, and some of them are compiled against
# the host's kernel uapi headers. tc.c references CBQ (struct tc_cbq_*), which was
# deleted from linux/pkt_sched.h, so it fails to build against a recent headers
# package -- CI proved that the hard way. btrfs is disabled on the same reasoning
# (an applet that tracks kernel headers), not because it is known to be broken.
# Neither belongs in an initramfs anyway: this is the userspace/kernel-header drift
# a real BSP integration hits constantly.
DISABLED=(TC BTRFS)

enable_in_config() {
	local s
	for s in "$@"; do
		if grep -qE "^# CONFIG_$s is not set$" .config; then
			sed -i "s/^# CONFIG_$s is not set\$/CONFIG_$s=y/" .config
		elif ! grep -qE "^CONFIG_$s=" .config; then
			echo "CONFIG_$s=y" >>.config
		fi
	done
}

disable_in_config() {
	local s
	for s in "$@"; do
		sed -i "s/^CONFIG_$s=[ym]\$/# CONFIG_$s is not set/" .config
	done
}

say "busybox"
BB="$WORK/busybox-$(cat "$WORK/busybox.version")"
cd "$BB"
if [ ! -f .config ]; then
	make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi

# Re-enabled on every run so a stale .config cannot skip the checks below.
enable_in_config "${REQUIRED[@]}" "${BEST_EFFORT[@]}"
disable_in_config "${DISABLED[@]}"
# stdin from /dev/null lets kconfig take defaults for new symbols; piping `yes ""`
# would abort this script on SIGPIPE because of `set -o pipefail`.
make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" oldconfig < /dev/null

missing=""
for s in "${REQUIRED[@]}"; do
	grep -qE "^CONFIG_$s=[ym]" .config || missing="$missing $s"
done
if [ -n "$missing" ]; then
	echo "busybox applets that should exist but did not enable:$missing"
	exit 1
fi
soft=""
for s in "${BEST_EFFORT[@]}"; do
	grep -qE "^CONFIG_$s=[ym]" .config || soft="$soft $s"
done
if [ -n "$soft" ]; then
	echo "note: optional applets unavailable:$soft"
fi
# kconfig can drag a symbol back in through a select; if a disabled applet is
# still on, the compile error we disabled it to avoid comes straight back.
still=""
for s in "${DISABLED[@]}"; do
	grep -qE "^CONFIG_$s=[ym]" .config && still="$still $s"
done
if [ -n "$still" ]; then
	echo "busybox applets that must stay off but kconfig re-enabled:$still"
	exit 1
fi
echo "required busybox applets enabled"

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
rm -f "$ROOTFS/linux"

cd "$ROOTFS"
# The kernel keeps whatever uid/gid the cpio headers say, but PID 1 always runs as
# root, so entries owned by the build user (uid 1000 on a runner) still work.
find . | cpio --create --format=newc --quiet | gzip -9n >"$WORK/initramfs.cpio.gz"
ls -lh "$WORK/initramfs.cpio.gz"
