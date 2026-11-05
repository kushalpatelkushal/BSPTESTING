#!/usr/bin/env bash
# Fast loop for editing the driver: make module && make initramfs && make boot
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

# The kernel tree is only modules_prepare'd at this point -- vmlinux has not been
# linked, so there is no Module.symvers for modpost to check symbols against.
# Without this it reports "ERROR: modpost: misc_register ... undefined!" and
# refuses to produce the .ko. The symbols are resolved for real by the kernel's
# module loader at insmod time, so unresolved names here are only a warning.
# Once work/linux-*/Module.symvers exists (after `make kernel`), the check is
# strict again on its own.
modpost_args=()
if [ ! -f "$KDIR/Module.symvers" ]; then
	say "no Module.symvers yet -- building the module with modpost warnings only"
	modpost_args=(KBUILD_MODPOST_WARN=1)
fi

# Every directory under drivers/ with a Makefile is one out-of-tree module.
for d in "$LAB_ROOT"/drivers/*/; do
	d=${d%/}
	[ -f "$d/Makefile" ] || continue
	say "module: $(basename "$d")"
	make -C "$KDIR" M="$d" ARCH=$ARCH 		"${modpost_args[@]}" CROSS_COMPILE="$CROSS_COMPILE" modules
	for ko in "$d"/*.ko; do
		ls -lh "$ko"
		# awk, not `sed -n 1,12p`: sed stops reading and modinfo then dies of
		# SIGPIPE, which pipefail turns into a build failure.
		modinfo "$ko" | awk 'NR <= 12'
	done
done
