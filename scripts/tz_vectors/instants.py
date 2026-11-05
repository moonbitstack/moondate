#!/usr/bin/env python3
"""The instants worth asking about: every point between 1800 and 2100 where a
zone might have changed its mind.

A TZif file says exactly where its own transitions are, so those come out of the
file. Past the last one the file hands over to a POSIX rule, and a rule is a
pattern rather than a list — those transitions are found by walking the years and
bisecting on the instant the answer changes.

The instants are shared by both reference scanners, so that what they are compared
on is the lookup rather than the search.
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, available_timezones, reset_tzpath

LOW = -5364662400  # 1800-01-01
HIGH = 4133980800  # 2101-01-01
STEP = 15 * 86400
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)


def block(data: bytes, head: int) -> tuple[bytes, int, int, int, int, int, int, int]:
    """The counts of the header at `head`, and where its data block starts."""
    version = data[head + 4 : head + 5]
    isut, isstd, leap, times, types, chars = struct.unpack(">6I", data[head + 20 : head + 44])
    return version, isut, isstd, leap, times, types, chars, head + 44


def length(counts: tuple[int, ...], width: int) -> int:
    isut, isstd, leap, times, types, chars = counts
    return times * width + times + types * 6 + chars + leap * (width + 4) + isstd + isut


def transitions(path: str) -> list[int]:
    data = open(path, "rb").read()
    if data[:4] != b"TZif":
        return []
    version, *rest = block(data, 0)
    counts = tuple(rest[:6])
    if version in (b"2", b"3", b"4"):
        head = 44 + length(counts, 4)
        version, *rest = block(data, head)
        counts = tuple(rest[:6])
        base, width = rest[6], 8
    else:
        base, width = 44, 4
    times = counts[3]
    out = []
    for k in range(times):
        at = base + k * width
        out.append(struct.unpack(">q" if width == 8 else ">i", data[at : at + width])[0])
    return out


def state(tz: ZoneInfo, when: int):
    moment = (EPOCH + timedelta(seconds=when)).astimezone(tz)
    return (
        int(moment.utcoffset().total_seconds()),
        moment.tzname() or "",
        moment.dst().total_seconds() != 0,
    )


def after_the_file(tz: ZoneInfo, start: int) -> list[int]:
    """The transitions a POSIX rule puts past the end of the table."""
    out = []
    here = start
    now = state(tz, here)
    while here < HIGH:
        ahead = min(here + STEP, HIGH)
        there = state(tz, ahead)
        if there != now:
            low, high = here, ahead
            while high - low > 1:
                middle = (low + high) // 2
                if state(tz, middle) == now:
                    low = middle
                else:
                    high = middle
            here = high
            now = state(tz, here)
            out.append(here)
            continue
        here = ahead
        now = there
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tzif", help="a tree built by zic")
    args = parser.parse_args()
    reset_tzpath([args.tzif])
    ZoneInfo.clear_cache()
    total = 0
    for name in sorted(available_timezones()):
        path = os.path.join(args.tzif, *name.split("/"))
        known = [t for t in transitions(path) if LOW <= t < HIGH]
        tz = ZoneInfo(name)
        edge = known[-1] if known else LOW
        found = sorted(set(known) | set(after_the_file(tz, max(edge, LOW))))
        # The first line of a zone is what it read before anything happened, which
        # is also the answer for a zone that never changed at all.
        print("{} {}".format(name, LOW))
        total += 1
        for at in found:
            print("{} {}".format(name, at))
            total += 1
    print("instants: {}".format(total), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
