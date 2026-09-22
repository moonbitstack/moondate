# moondate

Dates, times, instants, durations and cron expressions. The proleptic Gregorian
calendar with the arithmetic that goes with it, the text forms four specifications
define, and a package that answers when a schedule fires next.

```moonbit
let stamp = @moondate.parse("2026-09-22T14:30:00+08:00")
stamp.epoch()                          // seconds since 1970, for a moment that names one
stamp.astimezone(Utc)                  // the same instant, read elsewhere
stamp.strftime("%Y-%m-%d %H:%M %Z")    // written the way Python writes it
stamp.plus(@moondate.Span::new(days=3L))

@cron.parse("0 9 * * MON-FRI").next(stamp)   // nine o'clock on the next weekday
```

## The four shapes

A moment is one of four things, and the difference is not decoration:

| | What it is | Written |
|:--:|:--|:--|
| `Zoned` | An instant. Has an epoch, can be read in another zone. | `2026-09-22T14:30:00Z` |
| `Plain` | A wall clock. An alarm, an opening time. | `2026-09-22T14:30:00` |
| `Day` | A date with no time. | `2026-09-22` |
| `Clock` | A time with no date. | `14:30:00` |

Turning a `Plain` into an instant needs a zone nobody has supplied, so `epoch` and
`astimezone` answer `None` for it rather than guessing. These are exactly the four
TOML 1.0.0 names; RFC 3339 defines only the first.

## What it reads and writes

| Form | Where it is used |
|:--:|:--|
| RFC 3339 / ISO 8601 | TOML, JSON Schema's `date-time`, most of the wire |
| IMF-fixdate, RFC 850, asctime | HTTP's `Date` header (RFC 9110 §5.6.7) — all three read, only the first written |
| UTCTime, GeneralizedTime | ASN.1, so X.509 validity (ITU-T X.680 §47) |
| `strftime` / `strptime` | The `%` directives C89 defines and Python implements |

The two-digit-year windows differ between HTTP and X.509 — 68/69 against 49/50 —
and each is applied where its specification says, because a certificate read by
HTTP's rule expires a century early.

## Python's `datetime`, in this family's words

Everything in that module's `__all__` has a counterpart: `date` is `Date`, `time`
is `Time`, `datetime` is `Moment`, `timedelta` is `Span`, `timezone` is `Zone`.
`toordinal`, `isocalendar`, `isoweekday`, `combine`, `replace`, `fromtimestamp`,
`timestamp`, `total_seconds`, `timetuple`, `ctime`, `isoformat`, `strftime` and
`strptime` are all here under those names or the obvious one.

Two deliberate differences. The resolution is a nanosecond rather than a
microsecond, because a protocol timestamp wants it. And there is no `now()`:
reading the clock is I/O, this package has none, so a caller passes what its own
clock said to `Moment::of_epoch`.

`tzinfo` in its full sense — named zones, daylight saving, the IANA database — is
not here. `Zone` is Python's `timezone`, a fixed offset. A zone database is a
different thing with a different update cadence, and `%Z` writes `UTC` or nothing
rather than inventing a name it cannot recover.

## cron

```moonbit
@cron.parse("*/15 9-17 * * MON-FRI")   // every quarter hour in working hours
@cron.parse("@daily")
@cron.parse("30 2 1 * *").next(now)    // half past two on the first
```

Five fields as crontab(5) defines them, or six with seconds in front. `*`, `n`,
`a-b`, `*/n`, `a-b/n`, lists of those, month and day names, `?` as Quartz writes
it, and the `@`-shorthands. Both 0 and 7 are Sunday.

Day-of-month and day-of-week are **or**-ed when both are restricted, which is Vixie
cron's rule: `0 0 13 * 5` is the thirteenth *or* any Friday, not Friday the
thirteenth. When one is `*` they are and-ed. This surprises everyone once, so it
has a test that says so.

An expression naming a day that does not exist — `0 0 30 2 *` — answers `None`
rather than searching forever.

A package rather than a repository of its own: cron's whole output is a `Moment`,
so a caller wanting it would have to download this module anyway, and package-level
isolation already keeps it out of a build that does not import it.

## What is checked

The calendar against the leap rule's three cases, the ordinal and the epoch against
the numbers Python prints, the ISO week date against the years where the first of
January belongs to the week before, and every text form against the example printed
in the specification that defines it. `strftime` and `strptime` are checked against
each other on every directive pair.

## Install

```bash
moon add moonbitstack/moondate
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
