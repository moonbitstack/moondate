"""Fetch test262, collect its Temporal cases, and write the transcription.

Three steps, one command:

    python scripts/temporal_vectors/run.py

The corpus is pinned to a commit: an unpinned corpus would turn a conformance
test into a moving target, and a new commit is a decision rather than a drift.
The tarball is cached under the work directory, so the second run is offline.

    python scripts/temporal_vectors/run.py --check

writes nothing and exits non-zero when the committed transcription is not what
the corpus gives, which is how CI notices that one of the two has moved.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# The commit the transcription is written against. Moving it means reading the
# report again and deciding what the change says.
PIN = "d11543772591a5c24b3229e6195a74c73e56032e"

# The three questions a text can answer here, and the suite that asks each.
SUITES = {
    "zoned": "test/built-ins/Temporal/ZonedDateTime",
    "dates": "test/built-ins/Temporal/PlainDate",
    "instants": "test/built-ins/Temporal/Instant",
}
OUT = os.path.join(ROOT, "src", "temporal_vectors_wbtest.mbt")
PLACES = os.path.join(ROOT, "src", "tzdata", "place_vectors_wbtest.mbt")


def fetch(work: str) -> dict:
    """Where each suite lives, downloading the release tarball once."""
    root = os.path.join(work, "test262-" + PIN)
    if all(os.path.isdir(os.path.join(root, path)) for path in SUITES.values()):
        return {name: os.path.join(root, path) for name, path in SUITES.items()}
    os.makedirs(work, exist_ok=True)
    archive = os.path.join(work, "test262-" + PIN + ".tar.gz")
    if not os.path.exists(archive):
        url = "https://codeload.github.com/tc39/test262/tar.gz/" + PIN
        print("fetching " + url, file=sys.stderr)
        with urllib.request.urlopen(url) as response, open(archive, "wb") as handle:
            shutil.copyfileobj(response, handle)
    with tarfile.open(archive) as tar:
        members = [
            m
            for m in tar.getmembers()
            if any("/" + path in m.name or m.name.endswith("/" + path) for path in SUITES.values())
        ]
        # `filter` arrived in 3.12; older interpreters take the same call without
        # it, and the archive is our own download over https either way.
        try:
            tar.extractall(work, members=members, filter="data")
        except TypeError:
            tar.extractall(work, members=members)
    return {name: os.path.join(root, path) for name, path in SUITES.items()}


def format_the_module() -> None:
    """Run `moon fmt`, which owns the layout of the generated files.

    The transcription writes each case on one line; where a line breaks is the
    formatter's business, and CI checks that the tree is what formatting leaves.
    """
    result = subprocess.run(["moon", "fmt"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)


def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", default=os.path.join(ROOT, ".temporal-cache"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    suites = fetch(args.work)
    cases = []
    for name, suite in suites.items():
        path = os.path.join(args.work, "cases-" + name + ".json")
        run(
            [
                "node",
                os.path.join(HERE, "collect.mjs"),
                "--tests",
                suite,
                "--out",
                path,
                "--pin",
                PIN,
            ]
        )
        cases.append(path)
    joined = ",".join(cases)

    before = {}
    for path in (OUT, PLACES):
        with open(path, encoding="utf-8") as handle:
            before[path] = handle.read()

    sys.stdout.write(
        run(
            [
                sys.executable,
                os.path.join(HERE, "build.py"),
                "--cases",
                joined,
                "--out",
                OUT,
                "--places-out",
                PLACES,
                "--report",
                os.path.join(args.work, "report.txt"),
            ]
        )
    )
    format_the_module()

    if args.check:
        # The file is written and formatted before the comparison, because the
        # layout is the formatter's: what has to match is what the two produce
        # together. A mismatch puts the old file back, so a check never leaves a
        # change behind.
        changed = []
        for path in (OUT, PLACES):
            with open(path, encoding="utf-8") as handle:
                if handle.read() != before[path]:
                    changed.append(path)
        if changed:
            for path in changed:
                with open(path, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(before[path])
            for path in changed:
                print("out of date: " + path, file=sys.stderr)
            raise SystemExit(1)
        print("the transcription is what the corpus gives")
        return

    print("written and formatted")


if __name__ == "__main__":
    main()
