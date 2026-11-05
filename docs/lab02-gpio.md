# Lab 2: a real GPIO controller driver (PL061, MMIO + IRQ)

`hello_demo` proved the driver model. It never touched hardware. This lab does:
`drivers/labgpio/labgpio.c` drives the ARM PL061 GPIO block that QEMU's `virt`
machine puts at `0x09030000`. The in-kernel `gpio-pl061` is compiled out
(`scripts/build-kernel.sh`), so the only driver for the device is yours.

## What happens at boot, in order

1. QEMU's device tree has:
   ```dts
   pl061@9030000 {
       compatible = "arm,pl061", "arm,primecell";
       reg = <0x00 0x9030000 0x00 0x1000>;
       interrupts = <0 7 4>;            /* GIC SPI 7, level high */
       gpio-controller; #gpio-cells = <2>;
       clocks = <&apb-pclk>; clock-names = "apb_pclk";
   };
   gpio-keys {
       compatible = "gpio-keys";
       poweroff { gpios = <&pl061 3 0>; linux,code = <116>; };
   };
   ```
2. `arm,primecell` makes the kernel create an **AMBA device**, not a platform
   device. Drivers match it by the **peripheral ID** read from registers
   `0xfe0..0xffc` (`0x00041061`), not by compatible string.
3. Nothing binds it (no `gpio-pl061`). `gpio-keys` needs line 3, so fw_devlink
   holds it back: init prints `gpio-keys-before=waiting`.
4. `insmod labgpio.ko`: probe maps the registers, registers a `gpio_chip` and an
   `irq_chip`. `/dev/gpiochip0` appears. Registering a provider kicks the
   deferred-probe list, and `gpio-keys` binds on its own.

## What CI proves

| Result line | What it shows |
|---|---|
| `gpio-pl061-before=unbound` | the in-kernel driver really is gone |
| `labgpio: 8 lines at [mem 0x09030000-0x09030fff]` | probe ran, resource from DT |
| `gpio-loop line=N hi=1 lo=0` | output path: DIR register + masked DATA writes, read back |
| `gpio-keys=bound` | a consumer driver resolved `<&pl061 3 0>` to your chip |
| `gpio-line3 ... busy=yes` | gpiolib ownership: one consumer per line |
| `gpio-irq=fired` | **interrupt path**: host QMP `system_powerdown` -> PL061 line 3 -> GIC SPI -> your chained handler -> `generic_handle_domain_irq` -> gpio-keys ISR |
| `gpio-rmmod-in-use=refused` | consumers pin the provider module (`gc.owner`) |
| `gpio-rmmod=OK`, `chip-after-rmmod=gone` | devm teardown leaves nothing behind |

The interrupt is generated from **outside** the guest by `scripts/qmp-stimulus.py`.
It waits for `Result: gpio-wait-powerbtn` in the boot log, then talks to QEMU's
QMP socket. That is a real hardware-in-the-loop pattern: the test bench drives
a pin, the device under test must react.

## Concepts to be able to explain in an interview

- **Why the data register is at `base + (mask << 2)`**: address bits [9:2] are a
  write mask. Single-line set/clear without read-modify-write, so no lock.
- **raw_spinlock_t vs spinlock_t**: irq_chip callbacks run in hard IRQ context
  with the descriptor lock held; on PREEMPT_RT a `spinlock_t` sleeps.
- **Chained handler vs request_irq**: the PL061's GIC line is not an ISR. It is a
  flow handler that demultiplexes to 8 child IRQs in its own `irq_domain`.
  `chained_irq_enter/exit` do the parent's ack/eoi.
- **handle_edge_irq vs handle_level_irq**: edge is latched and must be acked
  (`irq_ack` writes `GPIOIC`); level is masked during the handler and clears when
  the pin goes inactive.
- **IRQCHIP_IMMUTABLE + gpiochip_enable_irq/disable_irq**: gpiolib needs to know a
  line is in use as an IRQ so userspace can't flip it to output.
- **Deferred probe and fw_devlink**: why gpio-keys waited and what kicked it.
- **devm ordering**: resources unwind in reverse order of acquisition.

## Exercises (do these yourself; add assertions for each)

1. **Debugfs first.** Read `/sys/kernel/debug/labgpio/regs` in the boot log after
   the power button. Explain every bit of `IS`, `IBE`, `IE`, `RIS`.
2. **Break it, then fix it.** Remove the `writeb(..., LAB_IC)` from `irq_ack`. Predict
   what happens (hint: edge status stays latched, the GIC line stays high). Run CI,
   read the log, restore it.
3. **regmap.** Convert the driver to `devm_regmap_init_mmio` with a
   `regmap_config` that marks `RIS`/`MIS` volatile. Then read
   `/sys/kernel/debug/regmap/` for free.
4. **PM.** Add `suspend`/`resume` that save and restore `DIR/IS/IBE/IEV/IE` and output
   levels (`DEFINE_SIMPLE_DEV_PM_OPS`). Test with `echo freeze > /sys/power/state`
   and a QMP `system_wakeup`.
5. **Compare with mainline.** Diff your driver with `drivers/gpio/gpio-pl061.c` in
   `work/linux-*`. List each difference and decide who is right.
6. **Userspace events.** Extend `tools/gpiotest` with `GPIO_V2_LINE_FLAG_EDGE_RISING`
   and `read()` of `struct gpio_v2_line_event`. Unbind gpio-keys first, then wait for
   the QMP-injected edge from userspace instead of from a kernel driver.
