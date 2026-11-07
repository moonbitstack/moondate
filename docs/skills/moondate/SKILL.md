---
name: moondate
description: Dates, times, durations, the five timestamp text forms, and named time zones for MoonBit. Use it to parse or format a timestamp (RFC 3339, HTTP dates, ASN.1, `strftime`, Go layouts, LDML patterns, ECMAScript ISO), to add a duration or a month to a date, to work out when a cron expression fires next, or to turn a wall clock in a named zone into an instant when the clocks change.
---

# moondate

Add the module and import the package you need. The calendar is the root package;
the schedule and the zone database are separate so that a program that formats an
HTTP date does not carry either.

```bash
moon add moonbitstack/moondate
```

| Package | Import | Brings |
|:--|:--|:--|
| calendar and text | `moonbitstack/moondate` | `Date`, `Time`, `Moment`, `Span`, `Zone`, `parse`, `strftime`, `layout`, `pattern`, `http`, `asn1` |
| schedules | `moonbitstack/moondate/cron` | `Cron`, `parse`, `next` |
| zones | `moonbitstack/moondate/zone` | `Tz`, `ZonedDateTime`, `Rule`, `Local`, `Fold`, `Reading` |
| the database | `moonbitstack/moondate/tzdata` | `load`, `find`, `zones`, `links`, `release` |
| the machine's zones | `moonbitstack/moondate/zoneinfo` | `open`, `named`, `system`, `directory` |

## Read a timestamp and write it another way

`parse` keeps the shape the text had — an instant, a wall clock, a date, or a
time — and every writer takes a `Moment` and writes it back in its own form.

```moonbit
fn main raise {
  let stamp = @moondate.parse("2026-09-22T06:30:05.123Z")
  println(stamp.strftime("%A %d %B %Y at %H:%M"))
  println(stamp.layout(@moondate.RFC1123))
  println(stamp.pattern("EEEE, MMMM d, yyyy 'at' HH:mm"))
  println(stamp.isoformat(fraction=3))
}
```

`epoch` answers `None` for the three shapes that are not instants. A wall clock
becomes an instant only when someone says which zone it was read in.

## A wall clock in a named zone

`@tzdata.load` gives back a `Tz`; `moment` reads an instant in it, and `epoch`
turns a wall clock into one.

```moonbit
let tz = @tzdata.load("America/New_York")
let moment = tz.moment(1790058605L)
println(moment.strftime("%H:%M %Z %z"))
println(moment.pattern("VV"))
let date = @moondate.Date::new(2026, 11, 1)
let time = @moondate.Time::new(1, 30)
println(tz.epoch(date, time))                    // the first of the two
println(tz.epoch(date, time, fold=@zone.Later))  // the second
```

Twice a year a wall clock names two instants or none. `tz.read(date, time)`
answers with `Ambiguous`, `Skipped` or `Exact`; `Local::epoch(fold~)` picks:
`Compatible` (the default, first of two and second of none), `Earlier`, `Later`,
or `Reject`, which raises rather than guessing.

## When a cron expression fires next

```moonbit
let every_quarter = @cron.parse("*/15 9-17 * * MON-FRI")
let now = @moondate.Moment::of_epoch(1790058605L)
match every_quarter.next(now) {
  Some(fire) => println(fire.to_string())
  None => println("this one never fires")
}
```

Five fields as crontab(5) has them, or six with seconds in front. Day of month and
day of week are or-ed when both are restricted, which is Vixie cron's rule.

## Rules that catch people out

- **Nothing reads a clock.** There is no `now()`: reading the time is I/O, and
  these packages have none of it. Pass what your clock said to `Moment::of_epoch`.
  `@zoneinfo` is the one package that opens a file, which is why it is a package of
  its own; a program that needs none of it does not link it.
- **A named zone is a reading, not a rule.** `Zone::Named` carries the offset in
  force at that instant, so adding a span across a transition leaves the offset
  stale. Go back through `Tz::moment` when a change has to be crossed.
- **A place name needs `@tzdata.parse`.** `@moondate.parse` has no database, so a
  text like `…[America/New_York]` with no offset beside it is refused there; the
  `tzdata` entry point resolves it and takes `fold` for the hour that has none.
- **Annotations are read, and a `!` binds you.** `[u-ca=iso8601]` and `[foo=bar]`
  are accepted and ignored; `[!foo=bar]` is refused, because the `!` says the
  reader has to understand the key. A key with a capital in it is refused too.
- **A place name needs `@tzdata.parse`.** `@moondate.parse` has no database, so a
  text like `…[America/New_York]` with no offset beside it is refused there; the
  `tzdata` entry point resolves it, and takes `fold` for the hour that has none.
- **Annotations are read, and a `!` binds you.** `[u-ca=iso8601]` and `[foo=bar]`
  are accepted and ignored; `[!foo=bar]` is refused, because the `!` says the
  reader has to understand the key. A key with a capital in it is refused too.
- **A bracketed name is an instant only when it is an offset.** `…[+09:00]` and
  `…[UTC]` parse on their own, and `…-04:00[America/New_York]` parses because the
  offset is there. `…[America/New_York]` alone is refused: a place does not say
  which side of a transition the clock was on.
- **`%Z` on a fixed offset writes `UTC±HH:MM`**, not a name: an offset cannot tell
  you which zone it came from. Load the zone if you want `EST`.
- **RFC 3339 has no seconds in an offset**, so a zone's local mean time keeps its
  minutes there (`-04:56`) while the value keeps the rest; `isoformat` writes the
  seconds, and `parse` reads them back.
- **The database is a release, not a rule of nature.** `@tzdata.release` names the
  version carried; a government can change a zone at any time.
