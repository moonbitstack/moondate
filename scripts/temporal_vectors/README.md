# The Temporal cases from test262

test262 is the conformance suite for ECMAScript, and its `Temporal` directory is
the closest thing to a specification of what "read a zoned date and time out of
text" means. This directory turns the part of it this library answers into a
MoonBit test.

```bash
python scripts/temporal_vectors/run.py           # fetch, collect, write
python scripts/temporal_vectors/run.py --check    # write nothing; fail if the
                                                  # committed file is out of date
moon test src --target native                     # replay it
```

## Why the cases are extracted rather than read

test262 asserts against its own implementation, so the values are not in the
files in a form anything but JavaScript can read: they are built at run time, in
loops, through helpers like `TemporalHelpers.assertZonedDateTimesEqual`. Parsing
the files would recover the shape of the assertions and guess at the values.

`collect.mjs` runs each file instead, against a stand-in `Temporal` that records
what it was asked:

| In the test | What the stand-in does |
|:--|:--|
| `Temporal.ZonedDateTime.from(str)` | returns a record of `str` |
| `assert.sameValue(record.epochNanoseconds, 217207410100000000n)` | notes "that text is that instant" |
| `assert.sameValue(record.timeZoneId, "-08:00")` | notes "that text is filed there" |
| `TemporalHelpers.assertZonedDateTimesEqual(record, new Temporal.ZonedDateTime(ns, zone))` | notes both |
| `assert.throws(RangeError, () => …from(str))` | notes "that text must be refused" |

The output is what the corpus actually asserts — 126 distinct cases from the 902
files — rather than a reading of the source. Calls that carry an options object
are skipped: `{ offset: "use" }` and `{ offset: "ignore" }` read the same text two
ways, so they say nothing about reading text.

## What is transcribed, and what is not

`build.py` answers a case when this library can, and otherwise writes it down
under a reason. Of the 126:

| | Cases |
|:--|--:|
| Transcribed | 57 |
| — that name an instant | 15 |
| — that name only a zone | 8 |
| — that must be refused | 34 |
| Not transcribed | 69 |

The refusals are the larger half and the easier one: the corpus says the text must
throw, and a parser that throws is right whatever the reason. The exclusions, in
order of size:

| Reason | Cases | What would close it |
|:--|--:|:--|
| The basic (no-colon) form, `19761118T152330`, `-0800` | 20 | reading ISO 8601's basic format, which RFC 3339 does not have |
| An offset with seconds, `-12:12:59` | 11 | an offset reader that keeps seconds or refuses them |
| A critical annotation, `[!UTC]` | 8 | Temporal's annotation grammar |
| A text that names no zone, which `parse` reads as a plain moment | 7 | nothing — the two APIs ask different questions |
| A time with no minutes, `T15` | 4 | reduced-precision times |
| A calendar or key-value annotation, `[u-ca=…]` | 4 | the same grammar |
| An offset with no minutes, `-08` | 3 | the same offset reader |
| A minus sign that is not the ASCII one | 3 | U+2212 as a sign |
| A year outside Temporal's range | 2 | nothing — this library's years go further |
| A fraction longer than nine digits | 2 | nothing — truncation is the documented choice |
| A leap second | 2 | nothing — it is read as the minute it opens |
| A text offset that disagrees with its zone | 2 | resolving the zone, which needs the database |
| A comma before the fraction | 1 | a comma as the decimal mark |

Two of those are not gaps but decisions, and the table says so: a text with no
zone is a plain moment to `parse` because that is a different question from
`ZonedDateTime.from`'s, and a leap second is read as the minute it opens because
that keeps the instant.

## Moving the pin

`PIN` in `run.py` names the commit. Moving it is a decision: regenerate, read the
report, and look at what changed — the transcription is the record of the
decision, so a diff in `src/temporal_vectors_wbtest.mbt` should be explainable
line by line.
