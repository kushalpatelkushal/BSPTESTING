#!/usr/bin/env bash
# Dump QEMU's own DTB, insert our device node, recompile.
# This is the dtc round-trip a BSP engineer does on a real board, minus the board.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$WORK"

say "dump QEMU virt dtb"
"$QEMU" -machine "$QEMU_MACHINE,dumpdtb=$WORK/virt-plain.dtb" -cpu "$QEMU_CPU" \
	-m "$QEMU_MEM" -smp 1 -nographic >/dev/null 2>&1
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
