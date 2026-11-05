#!/usr/bin/env python3
"""Host-side test bench: press QEMU's power button when the guest asks for it.

On the virt machine (booted with -kernel, so no ACPI GED), QMP
"system_powerdown" pulses PL061 line 3 high for ~100 ms. That is a real
interrupt travelling pin -> PL061 -> GIC SPI -> our chained handler ->
gpio-keys, generated from outside the guest the way a lab bench would.

usage: qmp-stimulus.py QMP_SOCKET BOOT_LOG MARKER TIMEOUT_S
"""
import json
import socket
import sys
import time


def wait_for_marker(log_path, marker, deadline):
    while time.time() < deadline:
        try:
            with open(log_path, "r", errors="replace") as f:
                if marker in f.read():
                    return True
        except FileNotFoundError:
            pass
        time.sleep(0.5)
    return False


def connect(sock_path, deadline):
    while time.time() < deadline:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(sock_path)
            return s
        except OSError:
            s.close()
            time.sleep(0.5)
    return None


def qmp(f, s, cmd):
    s.sendall((json.dumps({"execute": cmd}) + "\n").encode())
    # Skip asynchronous events until the command's own reply arrives.
    while True:
        line = f.readline()
        if not line:
            return None
        msg = json.loads(line)
        if "return" in msg or "error" in msg:
            return msg


def main():
    sock_path, log_path, marker, timeout = sys.argv[1:5]
    deadline = time.time() + float(timeout)

    if not wait_for_marker(log_path, marker, deadline):
        print(f"[host] marker '{marker}' never appeared; no stimulus sent")
        return 0
    s = connect(sock_path, deadline)
    if s is None:
        print(f"[host] could not connect to QMP at {sock_path}")
        return 0
    with s:
        f = s.makefile("r")
        f.readline()  # greeting
        qmp(f, s, "qmp_capabilities")
        reply = qmp(f, s, "system_powerdown")
        print(f"[host] system_powerdown -> {reply}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
