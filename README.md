# Board-free embedded Linux BSP lab (QEMU arm64 + GitHub Actions)

Everything here runs with **no development board and no local disk**: the heavy
lifting happens on GitHub Actions or a cloud ARM VM, and the artifacts are a real
kernel, a real device tree and a real loadable driver.

## What the driver lab proves

`make lab` (CI job **driver lab**) does the whole loop, in this order:

1. resolves the newest stable kernel (GitHub mirror tags, falling back to
   kernel.org) and the newest busybox, then downloads both
2. configures an arm64 `defconfig` kernel and runs `modules_prepare`
3. builds a static busybox and an out-of-tree `hello_demo.ko`, packed into a cpio
   initramfs
4. dumps QEMU's own device tree with `dtc`, injects a `qoder,hello-demo` node,
   recompiles the DTB with the same CPU/memory topology used at boot
5. builds the kernel Image with that initramfs **embedded** (`CONFIG_INITRAMFS_SOURCE`)
   and a default `CONFIG_CMDLINE`, then boots headless: ROM -> kernel -> `/init`
6. asserts, from the boot log, that the DT node became a platform device, the
   driver bound, sysfs attributes were readable, `/dev/hello` returned data, and
   `rmmod` left nothing behind

Why the initramfs is embedded and the cmdline is compiled in: when you hand QEMU a
`-dtb` file you own the device tree, and QEMU is not obliged to write `/chosen`
bootargs or initrd addresses into it. Embedding the initramfs and defaulting the
command line removes that dependency (and is how a lot of production embedded
kernels ship anyway). `-append` is still passed, so if the boot loader side *does*
inject bootargs, that path is exercised too.

The assertion step is what makes this a lab rather than a demo: the checks live in
`scripts/check-log.sh` and fail the build.

## Files

| Path | Purpose |
|---|---|
| `drivers/hello_demo/hello_demo.c` | OF-matched platform driver: `of_property_read_u32`/`_string`, `dev_groups` sysfs attrs, miscdevice |
| `dts/hello-demo-node.dtsi` | the node injected into QEMU's device tree |
| `rootfs/init` | PID 1 in the initramfs; prints the `Result:` lines CI asserts on |
| `scripts/make-dtb.sh` | dtc round-trip: dump -> decompile -> insert -> recompile |
| `scripts/build-kernel.sh` | two phases: `prepare` (defconfig + `modules_prepare`) and `image` (embedded initramfs + default cmdline) |
| `scripts/build-initramfs.sh` | busybox + module + cpio |
| `scripts/boot.sh` | headless QEMU run with timeout and `panic=-1` |
| `scripts/build-chain.sh`, `scripts/boot-chain.sh` | TF-A + U-Boot -> Linux (experimental job) |
| `cloud/arm-vm-setup.sh` | native aarch64 VM setup |

## Run it

**CI (zero local install).** Push to GitHub, open the Actions tab. `driver lab` runs
on push, on a schedule (Mondays, so a kernel/toolchain regression shows up without you
prodding it), or manually with an optional pinned kernel version.

**Your machine, later.** Needs ~12 GB free and Ubuntu/Debian:

```sh
sudo apt-get install -y build-essential bc bison flex git libssl-dev libelf-dev \
  device-tree-compiler cpio xz-utils python3 kmod qemu-system-arm gcc-aarch64-linux-gnu
make all && make boot && make check
```

**Cloud ARM VM** (Oracle Ampere free tier, AWS Graviton): `bash cloud/arm-vm-setup.sh`,
then `make all CROSS_COMPILE=` and `make boot CROSS_COMPILE= QEMU_EXTRA='-accel kvm'`.
Real aarch64 cores plus a real NVMe disk, which is where storage-stack work belongs.

**Driver edit loop:** `make module && make initramfs && make kernel && make boot`
(the kernel relink picks up the new initramfs).

## The boot-chain job

`boot-chain.yml` builds U-Boot as BL33 and ARM Trusted Firmware for `PLAT=qemu_arm`,
lays them into the QEMU secure flash, then feeds U-Boot `virtio scan` / `fatload` /
`booti` over the serial console to load the same kernel and initramfs from a FAT image.
It tracks mainline U-Boot and TF-A unpinned, and is `continue-on-error: true` -- a red
run there is information, not a broken lab.

## Exercises that build on this

- replace the injected node with a **runtime DT overlay** through configfs
  (`CONFIG_OF_CONFIGFS` is already enabled) instead of rebuilding the DTB
- add an `ioremap`-using variant: QEMU virt has a free MMIO window and a `pl061` GPIO
  controller to bind against
- write an **I2C client driver** against QEMU's `versatile-i2c` adapter
- probe deferral: make the driver need a clock that is not ready and watch `-EPROBE_DEFER`
- threaded IRQs: `pl011` or the virtio ring, poll vs. hardirq vs. `request_threaded_irq`
- storage: `fio` + `blktrace` against the emulated NVMe, then the same on a cloud ARM VM

## What QEMU will not teach you

No scope or logic analyzer, no power-rail or reset-timing surprises, no "which boards
have you brought up" answer. Cover that later with one borrowed or cheap board for a
weekend of real bring-up, and describe the gap honestly rather than hiding it.

## Credibility target

One merged mainline patch is worth more on a BSP résumé than any demo. Start with device
tree binding schema warnings (`make dt_binding_check`), subsystem cleanups found by
`scripts/checkpatch.pl`, and read a few real BSP series per week to learn house style.
