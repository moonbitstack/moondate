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
| `assert.sameValue(record.year, 2019)` | notes "that text reads as that year" |
| `TemporalHelpers.assertPlainDate(record, 1976, 11, "M11", 18)` | notes the day |
| `TemporalHelpers.assertZonedDateTimesEqual(record, new Temporal.ZonedDateTime(ns, zone))` | notes the instant and the zone |
| `assert.throws(RangeError, () => …from(str))` | notes "that text must be refused" |

The output is what the corpus actually asserts — 535 distinct cases — rather than
a reading of the source. Calls that carry an options object are skipped:
`{ offset: "use" }` and `{ offset: "ignore" }` read the same text two ways, so
they say nothing about reading text.

A property read one at a time is recorded as the property it is, not dropped.
`prototype/year/basic.js` asks a reading for its year and says nothing about the
rest of it, which is a fact about the text all the same; `build.py` puts those in
a table of their own and compares the one property. Two files that read different
properties of the same text are gathered into one case, since both are true of it.

Three suites are run, because a text answers three different questions:

| Suite | The question |
|:--|:--|
| `ZonedDateTime` | the instant, and the zone it is filed under |
| `PlainDate` | the day, with the rest of the text ignored |
| `Instant` | the exact time, which needs an offset in the text |

## What is transcribed, and what is not

`build.py` answers a case when this library can, and otherwise writes it down
under a reason. Of the 535:

| | Cases |
|:--|--:|
| Answered by `@moondate.parse` | 404 |
| — zoned readings and names | 103 |
| — plain dates | 131 |
| — instants | 166 |
| — one property of a reading | 4 |
| — of which refusals | 173 |
| Answered by `@tzdata.parse`, whose zone is a place | 12 |
| Not transcribed | 119 |

The four are counted apart so that they add up: a case that states one property is
one of the four rather than one of the readings it would otherwise have belonged
to, and the refusals are a count of the whole rather than a fifth part.

The four are counted apart so that they add up: a case that states one property is
one of the four rather than one of the readings it would otherwise have belonged
to, and the refusals are a count of the whole rather than a fifth part.

A refusal is a weak statement — the corpus says the text must throw, and a parser
that throws is right whatever the reason — so a refusal is transcribed as soon as
this library refuses it too. Only the texts it *reads* are excluded, which is a
shorter list and a different one from the texts it cannot read:

| Reason | Cases | What would close it |
|:--|--:|:--|
| A text with no offset, which `parse` reads as a plain moment | 33 | nothing — `Instant.from` asks a different question |
| An offset with a fraction of a second | 22 | nothing — Temporal refuses the form, and ISO 8601 has it |
| A year outside Temporal's range | 16 | nothing — this library's years go further |
| A year of minus zero, `-000000` | 10 | nothing — it reads as year nought here |
| A calendar this library does not have | 10 | a calendar, which it does not have |
| A text that names no zone, which `parse` reads | 7 | nothing — same as above |
| A fraction longer than nine digits | 6 | nothing — truncation is the documented choice |
| A leap second | 4 | nothing — it is read as the minute it opens |
| A minus sign that is not the ASCII one | 3 | U+2212 as a sign |
| A text offset that disagrees with its zone | 3 | resolving the zone, which needs the database |
| A comma before the fraction | 2 | a comma as the decimal mark |
| A `Z` beside a time, which `PlainDate` refuses | 2 | nothing — that is a moment here, and a date is its day |
| A text with no date, which this parser reads as a clock | 1 | nothing — a bare clock is a clock |

Several lines are decisions rather than gaps and the table says so: a text with no
zone is a plain moment to `parse` because that is a different question from
`ZonedDateTime.from`'s, a leap second is read as the minute it opens because that
keeps the instant, and a fraction past nine digits is dropped because that is what
the parser says it does.

This branch is the one that keeps a sub-second offset, so one line of the table
reads the other way round from `master`'s. `Zone::Precise` holds the nanoseconds,
so the eighteen cases spelled `+00:19:32.37` that `master` refuses are answered
here — and the twenty-two in which Temporal refuses a form ISO 8601 writes are
answered by this branch and not by Temporal, which is why they are excluded rather
than transcribed. 408 on `master` less 22 plus 18 is the 404 here.

## Moving the pin

`PIN` in `run.py` names the commit. Moving it is a decision: regenerate, read the
report, and look at what changed — the transcription is the record of the
decision, so a diff in `src/temporal_vectors_wbtest.mbt` should be explainable
line by line.
