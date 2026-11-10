"""Fetch test262, replay its ZonedDateTime cases against the reference, write the tables.

Three steps, one command:

    python scripts/temporal_vectors/run_zoned.py

The corpus is pinned to a commit and the reference implementation to a version:
an unpinned corpus would turn a conformance test into a moving target, and a
reference whose reading of the proposal moves would move the answers under the
transcription.

    python scripts/temporal_vectors/run_zoned.py --check

writes nothing and exits non-zero when the committed tables are not what the
corpus gives, which is how CI notices that one of the two has moved.
"""

import argparse
import http.client
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# The commit the transcription is written against, and the implementation whose
# answers it records.
PIN = "d11543772591a5c24b3229e6195a74c73e56032e"
REFERENCE = "temporal-polyfill@1.0.8"

SUITE = "test/built-ins/Temporal/ZonedDateTime"
OUT = os.path.join(ROOT, "src", "tzdata", "zoned_cases_wbtest.mbt")
REPORT = os.path.join(HERE, "zoned_exclusions.json")


def download(url: str, archive: str, attempts: int = 3) -> None:
    """Fetch a file, and fetch it whole.

    A download that stops in the middle leaves a file that looks like the
    corpus and is not one, so the bytes land beside it and only a complete
    transfer is given the name: a second run then either skips the work or
    starts it again, never unpacks half a suite.
    """
    partial = archive + ".part"
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(url) as response, open(partial, "wb") as handle:
                shutil.copyfileobj(response, handle)
            os.replace(partial, archive)
            return
        except (OSError, http.client.HTTPException) as error:
            if os.path.exists(partial):
                os.remove(partial)
            if attempt == attempts:
                raise
            print("  the transfer stopped (%s), trying again" % error, file=sys.stderr)


def fetch(work: str) -> str:
    """The corpus, downloading the release tarball once."""
    root = os.path.join(work, "test262-" + PIN)
    if os.path.isdir(os.path.join(root, SUITE)):
        return root
    os.makedirs(work, exist_ok=True)
    archive = os.path.join(work, "test262-" + PIN + ".tar.gz")
    if not os.path.exists(archive):
        url = "https://codeload.github.com/tc39/test262/tar.gz/" + PIN
        print("fetching " + url, file=sys.stderr)
        download(url, archive)
    with tarfile.open(archive) as tar:
        members = [
            m for m in tar.getmembers()
            if "/" + SUITE in m.name or "/harness/" in m.name
        ]
        try:
            tar.extractall(work, members=members, filter="data")
        except TypeError:
            tar.extractall(work, members=members)
    return root


def installed(work: str) -> str:
    """The reference implementation, installed once under the work directory."""
    target = os.path.join(work, "reference")
    package = os.path.join(target, "node_modules", "temporal-polyfill", "package.json")
    if os.path.exists(package):
        return os.path.join(target, "node_modules", "temporal-polyfill")
    os.makedirs(target, exist_ok=True)
    print("installing " + REFERENCE, file=sys.stderr)
    # `npm` is a shell script on Unix and a `.cmd` on Windows, and only one of the
    # two is found by name.
    npm = shutil.which("npm") or "npm"
    run([npm, "install", "--prefix", target, "--no-audit", "--no-fund", REFERENCE])
    return os.path.join(target, "node_modules", "temporal-polyfill")


def format_the_module() -> None:
    """Run `moon fmt`, which owns the layout of the generated tables."""
    run(["moon", "fmt"], cwd=ROOT)


def run(command, cwd=None, quiet=False):
    result = subprocess.run(command, cwd=cwd or ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise SystemExit(result.returncode)
    if not quiet:
        sys.stdout.write(result.stdout)
    return result.stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", default=os.path.join(ROOT, ".temporal-cache"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    root = fetch(args.work)
    reference = installed(args.work)
    cases = os.path.join(args.work, "zoned.json")
    run(
        [
            "node", "--no-warnings",
            os.path.join(HERE, "collect_zoned.mjs"),
            "--root", root,
            "--temporal", reference,
            "--out", cases,
        ]
    )

    before = {}
    for path in (OUT, REPORT):
        if os.path.exists(path):
            with open(path, encoding="utf-8") as handle:
                before[path] = handle.read()

    run(
        [
            sys.executable,
            os.path.join(HERE, "build_zoned.py"),
            "--cases", cases,
            "--out", OUT,
            "--report", REPORT,
            "--pin", PIN,
        ]
    )
    format_the_module()

    if args.check:
        changed = []
        for path in (OUT, REPORT):
            with open(path, encoding="utf-8") as handle:
                if before.get(path) != handle.read():
                    changed.append(path)
        for path in changed:
            if path in before:
                with open(path, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(before[path])
            print("out of date: " + path, file=sys.stderr)
        if changed:
            raise SystemExit(1)
        print("the tables and the report are what the corpus gives")


if __name__ == "__main__":
    main()
