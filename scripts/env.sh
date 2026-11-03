# Shared configuration for the board-free BSP lab. Sourced by scripts/*.sh.
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${WORK:-$LAB_ROOT/work}"

ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
QEMU="${QEMU:-qemu-system-aarch64}"
QEMU_MACHINE=virt
QEMU_CPU="${QEMU_CPU:-cortex-a53}"
QEMU_SMP="${QEMU_SMP:-2}"
QEMU_MEM="${QEMU_MEM:-1024}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-240}"
# On native aarch64 (cloud ARM VM) pass QEMU_EXTRA="-accel kvm" for hardware assist.
QEMU_EXTRA="${QEMU_EXTRA:-}"

DT_NODE="$LAB_ROOT/dts/hello-demo-node.dtsi"
BOOT_LOG="$WORK/boot.log"

KDIR() { echo "$WORK/linux-$(cat "$WORK/kernel.version")"; }

say() { printf '\n=== %s ===\n' "$*"; }
