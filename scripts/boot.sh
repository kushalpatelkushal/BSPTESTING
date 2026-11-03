#!/usr/bin/env bash
# Headless boot: kernel Image + patched DTB + initramfs, over the PL011 console.
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

for f in "$KDIR/arch/arm64/boot/Image" "$WORK/virt-hello.dtb" "$WORK/initramfs.cpio.gz"; do
	[ -f "$f" ] || { echo "missing $f -- run: make all"; exit 1; }
done

say "boot arm64 QEMU ($QEMU_CPU, $QEMU_SMP cpus, ${QEMU_MEM}M) -- no board involved"
set +e
timeout "$BOOT_TIMEOUT" "$QEMU" \
	${QEMU_EXTRA:-} \
	-machine "$QEMU_MACHINE" -cpu "$QEMU_CPU" -smp "$QEMU_SMP" -m "$QEMU_MEM" \
	-nographic -no-reboot \
	-kernel "$KDIR/arch/arm64/boot/Image" \
	-dtb "$WORK/virt-hello.dtb" \
	-initrd "$WORK/initramfs.cpio.gz" \
	-append "console=ttyAMA0 rdinit=/init panic=-1" 2>&1 | tee "$BOOT_LOG"
rc=${PIPESTATUS[0]}
set -e
echo "qemu exit=$rc (124 means it hit the ${BOOT_TIMEOUT}s timeout)"
exit "$rc"
