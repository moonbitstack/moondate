# The Temporal cases from test262

test262 is the conformance suite for ECMAScript, and its `Temporal` directory is
the closest thing to a specification of what "read a text into a date, an instant
or a zoned date and time" means. This directory turns the part of it this library
answers into a MoonBit test.

```bash
python scripts/temporal_vectors/run.py           # fetch, collect, write
python scripts/temporal_vectors/run.py --check    # write nothing; fail if the
                                                  # committed file is out of date
moon test src --target native                     # replay it
```

## Why the cases are extracted rather than read

test262 asserts against its own implementation, so the values are not in the files
in a form anything but JavaScript can read: they are built at run time, in loops,
through helpers like `TemporalHelpers.assertPlainDate`. Parsing the files would
recover the shape of the assertions and guess at the values.

`collect.mjs` runs each file instead, against a stand-in `Temporal` that records
what it was asked:

| In the test | What the stand-in does |
|:--|:--|
| `Temporal.ZonedDateTime.from(str)` | returns a record of `str` |
| `Temporal.PlainDate.from(str)` and its two siblings | the same, with the kind noted |
| `assert.sameValue(record.epochNanoseconds, 217207410100000000n)` | notes "that text is that instant" |
| `assert.sameValue(record.timeZoneId, "-08:00")` | notes "that text is filed there" |
| `TemporalHelpers.assertPlainDate(record, 1976, 11, "M11", 18)` | notes the day |
| `TemporalHelpers.assertZonedDateTimesEqual(record, new Temporal.ZonedDateTime(ns, zone))` | notes the instant and the zone |
| `assert.throws(RangeError, () => …from(str))` | notes "that text must be refused" |

The output is what the corpus actually asserts — 532 distinct cases — rather than
a reading of the source. Calls that carry an options object are skipped:
`{ offset: "use" }` and `{ offset: "ignore" }` read the same text two ways, so
they say nothing about reading text.

Three suites are run, because a text answers three different questions:

| Suite | The question |
|:--|:--|
| `ZonedDateTime` | the instant, and the zone it is filed under |
| `PlainDate` | the day, with the rest of the text ignored |
| `Instant` | the exact time, which needs an offset in the text |

## What is transcribed, and what is not

`build.py` answers a case when this library can, and otherwise writes it down
under a reason. Of the 532:

| | Cases |
|:--|--:|
| Transcribed | 248 |
| — zoned readings and names | 91 |
| — plain dates | 40 |
| — instants | 117 |
| — of which refusals | 81 |
| Not transcribed | 284 |

The refusals are the easier half: the corpus says the text must throw, and a
parser that throws is right whatever the reason. The exclusions, in order of size:

| Reason | Cases | What would close it |
|:--|--:|:--|
| A calendar or key-value annotation, `[u-ca=…]` | 72 | Temporal's annotation grammar |
| A reading that states only part of the date | 61 | nothing — those tests assert one property, not a text |
| An offset with a fraction of a second | 42 | an offset finer than the second a fixed zone here holds |
| A text with no offset, which `parse` reads as a plain moment | 33 | nothing — `Instant.from` asks a different question |
| A critical annotation, `[!UTC]` | 25 | the same grammar |
| A zone that needs the database | 12 | `tzdata`, which the root package does not carry |
| A text that names no zone, which `parse` reads | 7 | nothing — same as above |
| A year outside Temporal's range | 6 | nothing — this library's years go further |
| A year of minus zero, `-000000` | 6 | nothing — it reads as year nought here |
| A fraction longer than nine digits | 4 | nothing — truncation is the documented choice |
| A leap second | 4 | nothing — it is read as the minute it opens |
| A minus sign that is not the ASCII one | 3 | U+2212 as a sign |
| A text offset that disagrees with its zone | 3 | resolving the zone, which needs the database |
| More than one annotation | 3 | the same grammar |
| A comma before the fraction | 2 | a comma as the decimal mark |
| A text with no date, which this parser reads as a clock | 1 | nothing — a bare clock is a clock |

Several lines are decisions rather than gaps and the table says so: a text with no
zone is a plain moment to `parse` because that is a different question from
`ZonedDateTime.from`'s, a leap second is read as the minute it opens because that
keeps the instant, and a fraction past nine digits is dropped because that is what
the parser says it does.

## Moving the pin

`PIN` in `run.py` names the commit. Moving it is a decision: regenerate, read the
report, and look at what changed — the transcription is the record of the
decision, so a diff in `src/temporal_vectors_wbtest.mbt` should be explainable
line by line.
