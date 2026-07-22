# bluetooth-pi — UART Bluetooth controller

⚠️ **Legacy (Buster-era), Pi-only, not auto-installed** (default `no`).

Attaches a Broadcom UART Bluetooth controller with `btattach` on `/dev/ttyAMA0`.

On **modern Pi OS (Bookworm)** the OS brings the UART controller up itself
(`pi-bluetooth`/`hciuart` or a DT serdev), so `ttyAMA0` is either busy or not the
BT port (Pi 5 uses a different UART entirely). The service now carries
`ConditionPathExists=/dev/ttyAMA0`, so it simply doesn't start where that node is
absent — no crash-loop — but it will still fight `hciuart` where that owns the
UART. Use it only on older single-purpose images that don't already manage the
controller; otherwise prefer the OS's own Bluetooth stack.

```bash
systemctl start bluetooth-pi
```
