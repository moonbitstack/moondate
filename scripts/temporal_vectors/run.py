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

SUITE = "test/built-ins/Temporal/ZonedDateTime"
OUT = os.path.join(ROOT, "src", "temporal_vectors_wbtest.mbt")


def fetch(work: str) -> str:
    """The suite's directory, downloading the release tarball once."""
    suite = os.path.join(work, "test262-" + PIN, SUITE)
    if os.path.isdir(suite):
        return suite
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
            if "/" + SUITE in m.name or m.name.endswith("/" + SUITE)
        ]
        # `filter` arrived in 3.12; older interpreters take the same call without
        # it, and the archive is our own download over https either way.
        try:
            tar.extractall(work, members=members, filter="data")
        except TypeError:
            tar.extractall(work, members=members)
    return suite


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

    suite = fetch(args.work)
    cases = os.path.join(args.work, "cases.json")
    run(
        [
            "node",
            os.path.join(HERE, "collect.mjs"),
            "--tests",
            suite,
            "--out",
            cases,
            "--pin",
            PIN,
        ]
    )

    if args.check:
        temporary = os.path.join(args.work, "generated.mbt")
        run(
            [
                sys.executable,
                os.path.join(HERE, "build.py"),
                "--cases",
                cases,
                "--out",
                temporary,
            ]
        )
        with open(temporary, encoding="utf-8") as handle:
            made = handle.read()
        with open(OUT, encoding="utf-8") as handle:
            kept = handle.read()
        if made != kept:
            print("the transcription is not what the corpus gives", file=sys.stderr)
            raise SystemExit(1)
        print("the transcription is what the corpus gives")
        return

    sys.stdout.write(
        run(
            [
                sys.executable,
                os.path.join(HERE, "build.py"),
                "--cases",
                cases,
                "--out",
                OUT,
                "--report",
                os.path.join(os.path.dirname(cases), "report.txt"),
            ]
        )
    )


if __name__ == "__main__":
    main()
