#!/usr/bin/env bash
# Native aarch64 cloud VM setup (Oracle Free Tier Ampere A1, AWS Graviton,
# Hetzner CAX). No board and no cross toolchain: build and boot natively, with
# KVM assisting QEMU.
set -euo pipefail

say() { printf '\n=== %s ===\n' "$*"; }

say "toolchain"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
	build-essential bc bison flex git curl ca-certificates \
	libssl-dev libelf-dev device-tree-compiler cpio xz-utils python3 kmod \
	qemu-system-arm dosfstools mtools

say "host check"
uname -m
nproc
free -h | sed -n 2p
df -h "$HOME" | tail -1
if [ -e /dev/kvm ]; then
	echo "/dev/kvm present -> QEMU runs with hardware assist"
else
	echo "no /dev/kvm -> QEMU falls back to TCG (slow but working)"
fi
echo "need roughly 10 GB free for kernel tree + build + busybox"

say "run the lab natively"
echo "  git clone <your-repo-url> embedded-lab && cd embedded-lab"
echo "  make all CROSS_COMPILE="
echo "  make boot  CROSS_COMPILE= QEMU_EXTRA='-accel kvm'"
echo "  make check CROSS_COMPILE="
echo
echo "This VM also has a real NVMe backing store -- useful for block-layer and"
echo "storage-stack experiments (fio, nvme-cli, blktrace) that QEMU cannot show."
