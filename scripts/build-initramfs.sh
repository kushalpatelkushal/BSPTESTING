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
	DMSG MKNOD UMOUNT REBOOT HALT
	FIND AWK CP MV MKDIR RM LN TOUCH
	SLEEP DATE PRINTF TAIL HEAD WC TRUE TEST
)

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

say "busybox"
BB="$WORK/busybox-$(cat "$WORK/busybox.version")"
cd "$BB"
if [ ! -f .config ]; then
	make ARCH=$ARCH CROSS_COMPILE="$CROSS_COMPILE" defconfig
fi

# Re-enabled on every run so a stale .config cannot skip the checks below.
enable_in_config "${REQUIRED[@]}" "${BEST_EFFORT[@]}"
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
find . | cpio --create --format=newc --quiet | gzip -9n >"$WORK/initramfs.cpio.gz"
ls -lh "$WORK/initramfs.cpio.gz"
