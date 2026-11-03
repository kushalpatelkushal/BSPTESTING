#!/usr/bin/env bash
# Headless boot: kernel Image + patched DTB + initramfs, over the PL011 console.
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

for f in "$KDIR/arch/arm64/boot/Image" "$WORK/virt-hello.dtb"; do
	[ -f "$f" ] || { echo "missing $f -- run: make all"; exit 1; }
done

say "boot arm64 QEMU ($QEMU_CPU, $QEMU_SMP cpus, ${QEMU_MEM}M) -- no board involved"
# The initramfs is embedded in Image (CONFIG_INITRAMFS_SOURCE). bootargs are passed
# both ways on purpose: if QEMU injects -append into the user DTB it wins, otherwise
# the kernel falls back to its own CONFIG_CMDLINE.
set +e
timeout "$BOOT_TIMEOUT" "$QEMU" \
	${QEMU_EXTRA:-} \
	-machine "$QEMU_MACHINE" -cpu "$QEMU_CPU" -smp "$QEMU_SMP" -m "$QEMU_MEM" \
	-nographic -no-reboot \
	-kernel "$KDIR/arch/arm64/boot/Image" \
	-dtb "$WORK/virt-hello.dtb" \
	-append "console=ttyAMA0 rdinit=/init panic=-1" 2>&1 | tee "$BOOT_LOG"
rc=${PIPESTATUS[0]}
set -e
echo "qemu exit=$rc (124 means it hit the ${BOOT_TIMEOUT}s timeout)"
# QEMU's exit code says nothing about the driver: poweroff can race the console
# close, and a completed run still times out if PSCI sys_off is ignored.
# check-log.sh is the verdict; this script only fails on a hard launch error.
if [ "$rc" -eq 127 ] || [ ! -s "$BOOT_LOG" ]; then
	echo "QEMU produced no boot log (exit $rc) -- the launch itself failed"
	exit 1
fi
exit 0
