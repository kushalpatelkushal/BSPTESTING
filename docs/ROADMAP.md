# BSP curriculum: from zero board to "can own a board support package"

Every level ends in something CI can prove. A level is done only when its
assertions are in `scripts/check-log.sh` (or its own checker) and the job is green.

Status: `[x]` done and asserted in CI, `[ ]` not started.

## Level 1: driver model basics
- [x] OF-matched platform driver, DT properties, sysfs `dev_groups`, miscdevice (`drivers/hello_demo`)
- [x] DTB round trip with `dtc`: dump, decompile, patch, recompile (`scripts/make-dtb.sh`)
- [x] Boot chain ROM -> TF-A -> U-Boot -> Linux (`boot-chain.yml`)

## Level 2: real hardware access (MMIO + IRQ)
- [x] `drivers/labgpio`: PL061 AMBA driver, `ioremap`, `gpio_chip`, chained `irq_chip`,
      debugfs register dump, consumer (`gpio-keys`) + deferred probe, host-injected IRQ over QMP
      -- see [lab02-gpio.md](lab02-gpio.md)
- [ ] Your turn: the exercises at the end of lab02 (level IRQs, regmap, PM ops)
- [ ] `pl031` RTC: `rtc_class_ops`, alarm IRQ, `hwclock` and `rtcwake` from userspace
- [ ] `pl011` read-through: how `uart_port`, `console` and `earlycon` fit together

## Level 3: buses without a board
- [ ] I2C client driver against `i2c-stub` (regmap-i2c, `probe` from DT, IIO or hwmon class)
- [ ] GPIO consumer driver against `gpio-sim` (configfs-created chip, edge events)
- [ ] Switch machine: `-M mcimx6ul-evk` or `-M sabrelite` (NXP i.MX6). Real I2C, SPI, GPIO,
      SD and Ethernet controllers with mainline drivers and a mainline board DTS.
      Write the board DTS yourself: pinctrl groups, clocks, regulators, aliases.
- [ ] `-M ast2600-evb`: I2C buses with emulated `tmp105` sensors, BMC-style BSP

## Level 4: model the hardware yourself
- [ ] Write a QEMU device model: a MAX30003-style SPI ECG front end (register file,
      FIFO, interrupt pin) and attach it to the i.MX6 ECSPI controller
- [ ] Write the Linux IIO SPI driver for it: triggered buffer, IRQ, DT binding in YAML,
      `make dt_binding_check` clean
- [ ] Check whether mainline already has a driver for the part; if not, this is an upstream candidate

## Level 5: build systems
- [ ] Buildroot `qemu_aarch64_virt_defconfig` + a `BR2_EXTERNAL` tree that packages labgpio
- [ ] Yocto: own layer, machine conf, kernel `.bbappend` with patches and config fragments,
      module recipe, image recipe. Cache sstate; build on a cloud ARM VM if CI is too small.

## Level 6: bootloader and product concerns
- [ ] U-Boot: own board defconfig + DTS, environment, `bootcmd`, a driver-model (DM) driver
- [ ] FIT image, signed FIT / verified boot
- [ ] A/B updates with RAUC or SWUpdate, rollback on failed boot

## Level 7: debugging (the part interviews really test)
- [ ] `qemu -s -S` + `gdb vmlinux`: breakpoint in `labgpio_probe`, step through `ioremap`
- [ ] `ftrace` / `trace-cmd`: trace `irq_handler_entry` for the power button IRQ
- [ ] Break it on purpose: NULL deref, lockdep splat, KASAN use-after-free. Decode each oops
      with `scripts/decode_stacktrace.sh`.
- [ ] `dynamic_debug`: turn on the `dev_dbg` lines in a driver at runtime

## Level 8: credibility
- [ ] One mainline patch via `git send-email` (DT binding YAML conversion or `checkpatch` cleanup)
- [ ] One cheap real board weekend (STM32MP157 DK fits best since you know ST; BeaglePlay or a
      Raspberry Pi also work): serial console, U-Boot, your DTS, one of your drivers on real pins
