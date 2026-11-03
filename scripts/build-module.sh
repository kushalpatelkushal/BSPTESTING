#!/usr/bin/env bash
# Fast loop for editing the driver: make module && make initramfs && make boot
set -euo pipefail
source "$(dirname "$0")/env.sh"
KDIR=$(KDIR)

KO="$LAB_ROOT/drivers/hello_demo/hello_demo.ko"

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

make -C "$KDIR" M="$LAB_ROOT/drivers/hello_demo" ARCH=$ARCH \
	"${modpost_args[@]}" CROSS_COMPILE="$CROSS_COMPILE" modules
ls -lh "$KO"
# awk, not `sed -n 1,12p`: sed stops reading and modinfo then dies of SIGPIPE,
# which pipefail turns into a build failure.
modinfo "$KO" | awk 'NR <= 12'
