SHELL := /bin/bash
ARCH ?= arm64
CROSS_COMPILE ?= aarch64-linux-gnu-
export ARCH CROSS_COMPILE FORCE_KERNEL_VERSION
export QEMU_EXTRA BOOT_TIMEOUT BOOT_DELAY WORK

# Scripts are called with `bash` so the exec bit never matters (Windows checkout).
SCRIPTS := scripts

.PHONY: fetch kernel initramfs dtb boot check all lab clean chain-build chain-boot chain-run chain disk module

all: fetch kernel initramfs dtb

lab: all boot check

fetch:
	bash $(SCRIPTS)/fetch-sources.sh
kernel:
	bash $(SCRIPTS)/build-kernel.sh
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

chain-build: fetch kernel initramfs dtb
	bash $(SCRIPTS)/build-chain.sh

chain-boot: chain-build disk
	bash $(SCRIPTS)/boot-chain.sh

chain-run:
	bash $(SCRIPTS)/boot-chain.sh

chain: chain-boot

clean:
	rm -rf work
