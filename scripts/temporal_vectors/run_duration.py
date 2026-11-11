"""Ask the reference about lengths and write the table this library replays.

    python scripts/temporal_vectors/run_duration.py           # fetch, ask, write
    python scripts/temporal_vectors/run_duration.py --check   # fail if the
                                                             # committed table
                                                             # is out of date

The reference is the same one the ZonedDateTime transcription uses, pinned to the
same version: it is the implementation whose reading of the proposal the corpus
states, and a newer one would move the answers under the table.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

from run_zoned import format_the_module, installed, run  # noqa: E402

OUT = os.path.join(ROOT, "src", "period_vectors_test.mbt")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work", default=os.path.join(ROOT, ".temporal-cache"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    reference = installed(args.work)
    cases = os.path.join(args.work, "duration.json")
    run(
        [
            "node", "--no-warnings",
            os.path.join(HERE, "duration_cases.mjs"),
            "--temporal", reference,
            "--out", cases,
        ]
    )

    before = None
    if os.path.exists(OUT):
        with open(OUT, encoding="utf-8") as handle:
            before = handle.read()

    run(
        [
            sys.executable,
            os.path.join(HERE, "build_duration.py"),
            "--cases", cases,
            "--out", OUT,
        ]
    )
    format_the_module()

    if args.check:
        with open(OUT, encoding="utf-8") as handle:
            after = handle.read()
        if before != after:
            if before is not None:
                with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(before)
            print("out of date: " + OUT, file=sys.stderr)
            raise SystemExit(1)
        print("the table is what the reference gives")


if __name__ == "__main__":
    main()
