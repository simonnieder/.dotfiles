#!/usr/bin/env python3
"""Print today's Timewarrior bookings and totals for a Waybar tooltip."""

from __future__ import annotations

import json
import subprocess
from collections import defaultdict
from datetime import datetime, time, timezone


def parse_timew(value: str) -> datetime:
    return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc).astimezone()


def duration(seconds: float) -> str:
    minutes = max(0, round(seconds / 60))
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h{minutes:02d}m" if hours else f"{minutes}m"


def main() -> None:
    now = datetime.now().astimezone()
    day_start = datetime.combine(now.date(), time.min, tzinfo=now.tzinfo)
    raw_intervals = json.loads(subprocess.run(
        ["timew", "export", ":day"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    ).stdout)

    intervals = []
    for raw in raw_intervals:
        start = max(parse_timew(raw["start"]), day_start)
        active = "end" not in raw
        end = parse_timew(raw["end"]) if not active else now
        if end <= start:
            continue
        intervals.append({
            "start": start,
            "end": end,
            "tag": ", ".join(raw.get("tags") or ["untagged"]),
            "active": active,
        })

    print("Today")
    if not intervals:
        print("No bookings")
        return

    totals: defaultdict[str, float] = defaultdict(float)
    for interval in intervals:
        seconds = (interval["end"] - interval["start"]).total_seconds()
        totals[interval["tag"]] += seconds
        suffix = " now" if interval["active"] else ""
        print(
            f'{interval["start"]:%H:%M}–{interval["end"]:%H:%M}  '
            f'{interval["tag"]}  {duration(seconds)}{suffix}'
        )

    print()
    for tag, seconds in sorted(totals.items(), key=lambda item: (-item[1], item[0])):
        print(f"{tag}: {duration(seconds)}")
    print(f"Tracked: {duration(sum(totals.values()))}")


if __name__ == "__main__":
    main()
