SHELL := /bin/bash
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-
export ARCH CROSS_COMPILE FORCE_KERNEL_VERSION
export QEMU_EXTRA BOOT_TIMEOUT BOOT_DELAY WORK

# The kernel's final Image embeds the initramfs, and the initramfs needs a
# configured kernel tree to build the out-of-tree module, so dependencies are
# declared rather than left to target order (make -j would reorder them).
#
#   fetch -> prepare -> initramfs -> kernel(image) ; dtb ; boot -> check
#
# Scripts are called with `bash` so the exec bit never matters (Windows checkout).
SCRIPTS := scripts

.PHONY: all lab fetch prepare kernel initramfs dtb boot check module clean \
	disk chain-build chain-run chain

all: kernel dtb

lab: all
	bash $(SCRIPTS)/boot.sh
	bash $(SCRIPTS)/check-log.sh

fetch:
	bash $(SCRIPTS)/fetch-sources.sh

prepare: fetch
	bash $(SCRIPTS)/build-kernel.sh prepare

initramfs: prepare
	bash $(SCRIPTS)/build-initramfs.sh

module: prepare
	bash $(SCRIPTS)/build-module.sh

dtb: fetch
	bash $(SCRIPTS)/make-dtb.sh

kernel: initramfs
	bash $(SCRIPTS)/build-kernel.sh image

boot: all
	bash $(SCRIPTS)/boot.sh

check:
	bash $(SCRIPTS)/check-log.sh

disk: all
	bash $(SCRIPTS)/make-disk.sh

chain-build: all
	bash $(SCRIPTS)/build-chain.sh

chain-run:
	bash $(SCRIPTS)/boot-chain.sh

chain: disk chain-build
	bash $(SCRIPTS)/boot-chain.sh

clean:
	rm -rf work
