#!/usr/bin/env python3
"""Send one notification at each low battery threshold per discharge cycle."""
import os
from pathlib import Path
import subprocess


def check_battery(battery, state_dir):
    if (battery / "type").read_text().strip() != "Battery":
        return
    scope = battery / "scope"
    if scope.exists() and scope.read_text().strip() == "Device":
        return
    capacity = int((battery / "capacity").read_text().strip())
    status = (battery / "status").read_text().strip()
    state = state_dir / battery.name
    if status != "Discharging" or capacity > 20:
        state.unlink(missing_ok=True)
        return
    level = 2 if capacity <= 10 else 1
    previous = int(state.read_text()) if state.exists() else 0
    if level <= previous:
        return
    critical = level == 2
    subprocess.run([
        "notify-send", "--app-name=Battery", "--icon=battery-caution-symbolic",
        "--urgency=" + ("critical" if critical else "normal"),
        "--expire-time=" + ("0" if critical else "12000"),
        "--hint=string:x-dunst-stack-tag:battery",
        f"Battery {'critically low' if critical else 'low'}: {capacity}%",
    ], check=True)
    state.write_text(str(level))


def main():
    state_dir = Path(os.environ["XDG_RUNTIME_DIR"]) / "battery-notifications"
    state_dir.mkdir(mode=0o700, exist_ok=True)
    for battery in Path("/sys/class/power_supply").iterdir():
        check_battery(battery, state_dir)


if __name__ == "__main__":
    main()
