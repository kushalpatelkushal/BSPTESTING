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
#
# QMP is QEMU's machine-control socket. The GPIO lab uses it as a test bench:
# when the guest prints the marker, the host "presses" the power button, which
# QEMU wires to PL061 line 3. Short /tmp path: unix socket paths cap at ~108 bytes.
QMP_SOCK="${TMPDIR:-/tmp}/bsplab-qmp-$$.sock"
rm -f "$QMP_SOCK" "$BOOT_LOG"
python3 "$LAB_ROOT/scripts/qmp-stimulus.py" "$QMP_SOCK" "$BOOT_LOG" \
	"Result: gpio-wait-powerbtn" "$BOOT_TIMEOUT" &
STIM_PID=$!

set +e
timeout "$BOOT_TIMEOUT" "$QEMU" \
	${QEMU_EXTRA:-} \
	-machine "$QEMU_MACHINE" -cpu "$QEMU_CPU" -smp "$QEMU_SMP" -m "$QEMU_MEM" \
	-nographic -no-reboot -nic none \
	-qmp "unix:$QMP_SOCK,server=on,wait=off" \
	-kernel "$KDIR/arch/arm64/boot/Image" \
	-dtb "$WORK/virt-hello.dtb" \
	-append "console=ttyAMA0 rdinit=/init panic=-1" 2>&1 | tee "$BOOT_LOG"
rc=${PIPESTATUS[0]}
kill "$STIM_PID" 2>/dev/null
wait "$STIM_PID" 2>/dev/null
rm -f "$QMP_SOCK"
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
