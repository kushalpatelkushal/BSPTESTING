#!/usr/bin/env bash
# Run the whole chain in QEMU: ROM -> BL1 -> BL2 -> BL31 -> U-Boot -> Linux.
# U-Boot commands are piped into the serial console, then Linux runs /init and
# powers off, which makes QEMU exit.
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)
CHAIN_LOG="$WORK/chain.log"
BOOT_DELAY="${BOOT_DELAY:-40}"

# shellcheck disable=SC1091
source "$WORK/chain.env"

say "assemble boot ROM (bl1 at 0, fip at 256 KiB) per TF-A docs/plat/qemu.rst"
FLASH="$WORK/flash.bin"
dd if=/dev/zero of="$FLASH" bs=4096 count=1024 status=none
dd if="$BL1" of="$FLASH" bs=4096 conv=notrunc status=none
dd if="$FIP" of="$FLASH" bs=4096 seek=64 conv=notrunc status=none

for f in "$WORK/disk.img"; do
	[ -f "$f" ] || { echo "missing $f -- run: make disk"; exit 1; }
done

say "booting chain in QEMU, feeding U-Boot commands after ${BOOT_DELAY}s"
# Same cpu as the DTB was dumped with: hello.dtb describes cortex-a53 CPUs, and a
# kernel whose DT lies about the running CPU prints feature mismatches.
QEMU_CHAIN_CPU="${QEMU_CHAIN_CPU:-$QEMU_CPU}"
# The U-Boot prompt closes as soon as Linux powers off, so the feed side dies of
# SIGPIPE and QEMU may be killed by `timeout`. Neither is a lab failure -- the
# assertions below read the log. Disable errexit/pipefail for this pipeline only.
set +e; set +o pipefail
{
	sleep "$BOOT_DELAY"
	printf 'version\r'
	sleep 3
	printf 'setenv kernel_addr_r 0x44000000; setenv fdt_addr_r 0x48000000\r'
	sleep 2
	printf 'setenv bootargs "console=ttyAMA0 rdinit=/init panic=-1"\r'
	sleep 2
	printf 'virtio scan\r'
	sleep 3
	# disk.img is a superfloppy (mkfs.vfat with no MBR), so the whole device is
	# the FAT volume: "virtio 0", never "virtio 0:1".
	printf 'fatls virtio 0\r'
	sleep 3
	printf 'fatload virtio 0 $kernel_addr_r Image\r'
	sleep 6
	printf 'fatload virtio 0 $fdt_addr_r hello.dtb\r'
	sleep 4
	# No ramdisk: the initramfs is embedded in Image by CONFIG_INITRAMFS_SOURCE.
	printf 'booti $kernel_addr_r - $fdt_addr_r\r'
} | timeout "$BOOT_TIMEOUT" "$QEMU" \
	-machine virt,secure=on -cpu "$QEMU_CHAIN_CPU" -smp "$QEMU_SMP" -m "$QEMU_MEM" \
	-nographic \
	-semihosting-config enable=on,target=native \
	-bios "$FLASH" \
	-drive if=none,id=hd0,format=raw,file="$WORK/disk.img" \
	-device virtio-blk-device,drive=hd0 2>&1 | tee "$CHAIN_LOG"
qemu_rc=${PIPESTATUS[1]}
set -euo pipefail
echo "qemu exit: $qemu_rc (124 = timed out)"

say "chain assertions"
rc=0
for m in "U-Boot 20" "Result: insmod=OK" "Result: lab-complete"; do
	if grep -qF "$m" "$CHAIN_LOG"; then
		printf 'PASS  %s\n' "$m"
	else
		printf 'FAIL  %s\n' "$m"
		rc=1
	fi
done
# TF-A BL1/BL2 normally print over semihosting rather than the serial console,
# so these are informational only.
for m in "Boot: BL31" "## Flattened Device Tree"; do
	if grep -qF "$m" "$CHAIN_LOG"; then printf 'seen  %s\n' "$m"; else printf 'n/a   %s\n' "$m"; fi
done
if [ "$rc" -eq 0 ]; then
	echo "chain complete: TF-A -> U-Boot -> Linux -> hello_demo driver"
fi
exit "$rc"
