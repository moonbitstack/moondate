#!/usr/bin/env python3
"""What Python's zoneinfo reads at each instant instants.py asked about.

    scripts/tz_vectors/vectors.py /path/to/tzif instants.txt

The output is `zone epoch offset abbreviation daylight`, one line per instant, so
that the same lines can be put beside Go's.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, reset_tzpath

LOW = -5364662400
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def state(tz: ZoneInfo, when: int) -> tuple[int, str, bool]:
    moment = (EPOCH + timedelta(seconds=when)).astimezone(tz)
    return (
        int(moment.utcoffset().total_seconds()),
        moment.tzname() or "",
        moment.dst().total_seconds() != 0,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tzif")
    parser.add_argument("instants")
    args = parser.parse_args()
    reset_tzpath([args.tzif])
    ZoneInfo.clear_cache()
    wanted: dict[str, list[int]] = {}
    for line in open(args.instants, encoding="utf-8"):
        fields = line.split()
        if len(fields) == 2:
            wanted.setdefault(fields[0], []).append(int(fields[1]))
    for name in sorted(wanted):
        tz = ZoneInfo(name)
        for when in sorted(wanted[name]):
            offset, abbrev, daylight = state(tz, when)
            print("{} {} {} {} {}".format(name, when, offset, abbrev, int(daylight)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
