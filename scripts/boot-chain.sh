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

say "assemble secure flash (bl1 at 0, fip at 1 MiB)"
dd if=/dev/zero of="$WORK/pflash0.img" bs=1M count=64 status=none
dd if=/dev/zero of="$WORK/pflash1.img" bs=1M count=64 status=none
dd if="$BL1" of="$WORK/pflash0.img" bs=1M conv=notrunc status=none
dd if="$FIP" of="$WORK/pflash0.img" bs=1M seek=1 conv=notrunc status=none

for f in "$WORK/disk.img"; do
	[ -f "$f" ] || { echo "missing $f -- run: make disk"; exit 1; }
done

say "booting chain in QEMU, feeding U-Boot commands after ${BOOT_DELAY}s"
{
	sleep "$BOOT_DELAY"
	printf 'version\r'
	sleep 3
	printf 'setenv bootargs "console=ttyAMA0 rdinit=/init"\r'
	sleep 2
	printf 'virtio scan\r'
	sleep 3
	printf 'fatls virtio 0:1\r'
	sleep 3
	printf 'fatload virtio 0:1 $kernel_addr_r Image\r'
	sleep 6
	printf 'fatload virtio 0:1 $fdt_addr_r hello.dtb\r'
	sleep 4
	# No ramdisk: the initramfs is embedded in Image by CONFIG_INITRAMFS_SOURCE.
	printf 'booti $kernel_addr_r - $fdt_addr_r\r'
} | timeout "$BOOT_TIMEOUT" "$QEMU" \
	-machine virt -cpu cortex-a53 -smp 2 -m 1024 \
	-nographic \
	-semihosting-config enable=on,target=native \
	-bios "$BL1" \
	-drive if=pflash,format=raw,file="$WORK/pflash0.img" \
	-drive if=pflash,format=raw,file="$WORK/pflash1.img" \
	-drive if=none,id=hd0,format=raw,file="$WORK/disk.img" \
	-device virtio-blk-device,drive=hd0 2>&1 | tee "$CHAIN_LOG"

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
[ "$rc" -eq 0 ] && echo "chain complete: TF-A -> U-Boot -> Linux -> hello_demo driver"
exit "$rc"
