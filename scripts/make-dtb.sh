#!/usr/bin/env bash
# Dump QEMU's own DTB, insert our device node, recompile.
# This is the dtc round-trip a BSP engineer does on a real board, minus the board.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$WORK"

say "dump QEMU virt dtb"
# Dump with the same cpu/memory topology as boot.sh: this DTB is what the kernel
# will actually see, so a mismatched CPU or memory node would silently lie.
# -nic none: QEMU adds a virtio-net card by default, and realising it wants the
# iPXE option ROM (efi-virtio.rom), which is not on a CI runner -- the dump aborts
# with "failed to find romfile". This lab needs no network device.
"$QEMU" -machine "$QEMU_MACHINE,dumpdtb=$WORK/virt-plain.dtb" -cpu "$QEMU_CPU" \
	-m "$QEMU_MEM" -smp "$QEMU_SMP" -nographic -nic none 2>&1 | tee "$WORK/dumpdtb.log" || true
[ -s "$WORK/virt-plain.dtb" ] || { echo "QEMU wrote no dtb (see dumpdtb.log)"; exit 1; }
dtc -I dtb -O dts -o "$WORK/virt-plain.dts" "$WORK/virt-plain.dtb"

say "insert hello-demo node at /"
python3 - "$WORK/virt-plain.dts" "$DT_NODE" "$WORK/virt-hello.dts" <<'PY'
import pathlib, sys
dts = pathlib.Path(sys.argv[1]).read_text()
node = pathlib.Path(sys.argv[2]).read_text()
tail = dts.rstrip()
i = tail.rfind("\n};")
if i < 0:
    sys.exit("no closing brace found in decompiled dts")
pathlib.Path(sys.argv[3]).write_text(tail[:i] + "\n" + node + tail[i:] + "\n")
PY

say "compile dtb"
dtc -I dts -O dtb -o "$WORK/virt-hello.dtb" "$WORK/virt-hello.dts"
dtc -I dtb -O dts "$WORK/virt-hello.dtb" 2>/dev/null | sed -n '/hello-demo/,/};/p'

# Evidence, not a build step: the boot chain runs QEMU with -machine virt,secure=on
# (TF-A needs EL3) while this DTB was dumped from the plain non-secure machine, and
# the chain boot has been silent. Print what actually differs between the two
# descriptions so "the DTB is wrong for the secure machine" can be confirmed or
# thrown away instead of argued about. QEMU's own hw/arm/virt.c sets the /intc reg,
# the /timer interrupts and the non-secure /pl011 node from gic-version and the
# memory map only -- not from vms->secure -- so the expected difference is limited to
# secure-world additions (/secure-chosen, /pl011@9400000, secure RAM, secure GPIO)
# and secure-status properties, none of which a non-secure kernel reads.
say "compare non-secure and secure machine descriptions"
if timeout 60 "$QEMU" -machine "$QEMU_MACHINE,secure=on,dumpdtb=$WORK/virt-secure.dtb" -cpu "$QEMU_CPU" \
	-m "$QEMU_MEM" -smp "$QEMU_SMP" -nographic -nic none >"$WORK/dumpdtb-secure.log" 2>&1 &&
	[ -s "$WORK/virt-secure.dtb" ]; then
	dtc -I dtb -O dts -o "$WORK/virt-secure.dts" "$WORK/virt-secure.dtb"
	echo "--- nodes/properties that differ (plain vs secure) ---"
	diff "$WORK/virt-plain.dts" "$WORK/virt-secure.dts" | sed -n '1,60p' || true
else
	echo "note: could not dump a secure=on dtb; QEMU said:"
	tail -n 5 "$WORK/dumpdtb-secure.log" 2>/dev/null || true
fi
