SHELL := /bin/bash
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-
export ARCH CROSS_COMPILE FORCE_KERNEL_VERSION
export QEMU_EXTRA BOOT_TIMEOUT BOOT_DELAY WORK

# Build order matters: the kernel's final Image embeds the initramfs, and the
# initramfs needs a configured kernel tree to build the out-of-tree module.
#
#   fetch -> prepare -> initramfs -> dtb -> kernel -> boot -> check
#
# Scripts are called with `bash` so the exec bit never matters (Windows checkout).
SCRIPTS := scripts

.PHONY: all lab fetch prepare kernel initramfs dtb boot check module clean \
	disk chain-build chain-boot chain-run chain

all: fetch prepare initramfs dtb kernel

lab: all boot check

fetch:
	bash $(SCRIPTS)/fetch-sources.sh
prepare:
	bash $(SCRIPTS)/build-kernel.sh prepare
kernel:
	bash $(SCRIPTS)/build-kernel.sh image
initramfs:
	bash $(SCRIPTS)/build-initramfs.sh
dtb:
	bash $(SCRIPTS)/make-dtb.sh
boot:
	bash $(SCRIPTS)/boot.sh
check:
	bash $(SCRIPTS)/check-log.sh
module:
	bash $(SCRIPTS)/build-module.sh

disk:
	bash $(SCRIPTS)/make-disk.sh
chain-build:
	bash $(SCRIPTS)/build-chain.sh
chain-boot:
	bash $(SCRIPTS)/boot-chain.sh
chain-run:
	bash $(SCRIPTS)/boot-chain.sh
chain: all disk chain-build chain-boot

clean:
	rm -rf work
