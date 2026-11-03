#!/usr/bin/env bash
# Assert the boot log proves the driver bound from device tree and worked.
set -euo pipefail
source "$(dirname "$0")/env.sh"
LOG="${1:-$BOOT_LOG}"
[ -f "$LOG" ] || { echo "no boot log at $LOG"; exit 1; }

fail=0
expect() {
	if grep -qF "$1" "$LOG"; then
		printf 'PASS  %s\n' "$1"
	else
		printf 'FAIL  %s (not in boot log)\n' "$1"
		fail=1
	fi
}

expect "Result: kernel-loaded"
expect "Result: dt-node=found"
expect "Result: insmod=OK"
expect "Result: sysfs-path=/sys/devices/platform/hello-demo"
expect "Result: sysfs-channels=3"
expect "Result: sysfs-model=board-free BSP lab"
expect "Result: dev-read=channels=3 model=board-free BSP lab reads=1"
expect "Result: dev-read-again=channels=3 model=board-free BSP lab reads=2"
expect "Result: rmmod=OK"
expect "Result: leftover-devnode=no"
expect "Result: lab-complete"

echo
if [ "$fail" -eq 0 ]; then
	echo "All checks passed: DT node -> platform driver -> sysfs + /dev/hello -> clean removal."
else
	# Make a red CI run actionable without downloading the artifact.
	echo "--- last 40 lines of $LOG ---"
	tail -n 40 "$LOG"
	echo "--- lines mentioning the driver, modules or errors ---"
	grep -iE 'hello|insmod|modpost|unknown symbol|not tainted|error|warning|panic' "$LOG" |
		tail -n 25 || true
	exit 1
fi
