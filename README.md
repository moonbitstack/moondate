<div align="center">

# moondate

Dates, times, instants, durations and cron schedules.

<a href="https://moonbitstack.github.io/moondate/">Homepage</a> ·
<a href="https://moonbitstack.github.io/moondate/guide.html">Guide</a> ·
<a href="https://moonbitstack.github.io/moondate/api.html">API</a> ·
<a href="https://moonbitstack.github.io/moondate/showcase.html">Playground</a> ·
<a href="https://mooncakes.io/docs/moonbitstack/moondate">mooncakes</a>

</div>

---

A calendar with the arithmetic that goes with it, the five ways to write a moment
that C, Python, Rust, Go and JavaScript each speak, a second package that answers
when a schedule fires next, and two more that carry the IANA time zone database
for the callers who need it.

```bash
moon add moonbitstack/moondate
```

```moonbit
fn main raise {
  let stamp = @moondate.parse("2026-09-22T14:30:05.123456+08:00")
  println(stamp.strftime("%A %d %B %Y at %H:%M"))
  println(stamp.epoch())
}
```

```
Tuesday 22 September 2026 at 14:30
1790058605
```

## The four shapes

A moment is one of four things, and the difference is not decoration. Each
constructor answers a different question, and each one refuses the questions it
cannot.

| | What it is | Written | `epoch` |
|:--:|:--|:--|:--:|
| `Zoned` | An instant. Sits on the timeline. | `2026-09-22T14:30:00+08:00` | `Some` |
| `Plain` | A wall clock. An alarm, an opening time. | `2026-09-22T14:30:00` | `None` |
| `Day` | A date with no time. | `2026-09-22` | `None` |
| `Clock` | A time with no date. | `14:30:00` | `None` |

Turning a `Plain` into an instant needs a zone nobody supplied, so `epoch` and
`astimezone` answer `None` for it rather than guessing. `parse` keeps whatever
shape the text had; nothing is padded with a hidden midnight.

Two spellings besides the one in the table are read. ISO 8601's basic form drops
the separators — `20260922T143000+0800`, `20260922` — and a bracketed offset
stands in for the one beside it, so `2020-01-01[+09:00]` is midnight nine hours
ahead and `…[UTC]` needs nothing else. A bracketed *name* is a different thing:
`[America/New_York]` says which zone but not which side of a transition the clock
was on, so it is refused unless the offset is written beside it. A zone name also
keeps the minute — `[+01:35]` is a name, `[+01:35:00]` is not.

An offset written finer than a minute — `+00:19:32.37`, which is what a zone read
before standard time needs — is kept as `Zone::Precise`, a count of nanoseconds,
rather than rounded. `Moment::instant` is then the exact instant as two halves,
because one count of nanoseconds runs out in 2262 and this library's years do not:

```moonbit
let m = @moondate.parse("1970-01-01T00:00:00+00:19:32.37")
m.isoformat()                     // 1970-01-01T00:00:00+00:19:32.37
m.instant()                       // Some((-1173, 630000000)) — 1172.37 s before the epoch
m.epoch()                         // Some(-1173), the same instant floored
```

Annotations after the moment are Temporal's, and `parse` reads them: `[u-ca=iso8601]`
is the calendar it already has, `[foo=bar]` is somebody else's business and is
ignored, and `[!foo=bar]` says the reader *must* understand the key — which it does
not, so it refuses. Two zones, two calendars, or a key with a capital in it are
refused as well.

## What it reads and writes

| Form | Where it is used |
|:--|:--|
| RFC 3339 / ISO 8601 | TOML, JSON Schema's `date-time`, most of the wire |
| IMF-fixdate, RFC 850, asctime | HTTP's `Date` header (RFC 9110 §5.6.7): all three read, the first written |
| UTCTime, GeneralizedTime | ASN.1, so X.509 validity (ITU-T X.680 §47) |
| `strftime` / `strptime` | The `%` directives of C23, POSIX, glibc, Python, chrono and C++20 |
| `layout` / `parse_layout` | Go's `time` reference layouts (`RFC3339`, `RFC1123`, …) |
| `pattern` / `parse_pattern` | Unicode LDML patterns, what ICU, `Intl` and Java use |
| `isoformat`, `to_iso_string`, `to_utc_string` | ECMA-262's Date Time String Format and Temporal |

The two-digit-year windows differ between HTTP and X.509: 69/70 against 49/50.
Each is applied where its own specification says, because a certificate read by
HTTP's rule expires a century early.

## Five ways to write a moment

The same instant can be written five ways, and moondate speaks all of them in both
directions: whatever it writes, `strptime`, `parse_layout` or `parse_pattern` reads
back to the same moment.

| Style | Write | Read | Where it is from |
|:--|:--|:--|:--|
| `%` directives | `strftime` | `strptime` | C23, POSIX, glibc, Python, chrono, C++20 |
| Reference-time layout | `layout` | `parse_layout` | Go's `time` package |
| LDML pattern | `pattern` | `parse_pattern` | Unicode UTS #35, ICU, `Intl`, Java |
| ECMAScript ISO | `isoformat`, `to_iso_string`, `to_utc_string` | `parse` | ECMA-262 and Temporal |

```moonbit
let m = @moondate.parse("2026-09-22T14:30:05.123456+08:00")

m.strftime("%A %d %B %Y, %I:%M %p")           // Tuesday 22 September 2026, 02:30 PM
m.layout(@moondate.RFC1123)                    // Tue, 22 Sep 2026 14:30:05 +08:00
m.pattern("EEEE, MMMM d, yyyy 'at' HH:mm")     // Tuesday, September 22, 2026 at 14:30
m.to_iso_string()                              // 2026-09-22T06:30:05.123Z
m.isoformat(fraction=3, offset=false)          // 2026-09-22T14:30:05.123
```

The `%` set is the union of the six lineages, with the conflicts settled in the
table: `%f` is Python's six digits (chrono's nine are `%9f` or `%N`), `%Z` writes
`UTC±HH:MM` for a fixed offset, and `%+` is chrono's form. Flags sit between the
sign and the letter — `-` drops the padding, `_` pads with spaces, `0` pads with
zeros, a number sets the width, `^` and `#` change the case of a name — and the
C99 selectors `E` and `O` are kept: `%Ec` is `%c`, `%Ez` is `+08:00` and `%Oz` is
`+0800`. A moment that carries only a fixed offset has no name to write, so the
zone letters in a Go layout and an LDML pattern fall back to the offset
(`GMT±HH:MM` in LDML), which is what ICU and babel do for a zone they only know by
its offset. Give the moment a name — the next section is how — and `%Z`, LDML's
`z` and `V`, and a Go layout's `MST` write the name the database gave it.

```moonbit
m.strftime("%#B %10Y %-d")                     // SEPTEMBER 0000002026 22
m.strftime("%Ez %Oz")                          // +08:00 +0800
m.pattern("Y-'W'ww c B")                       // 2026-W39 2 in the afternoon
m.isoformat()                                  // 2026-09-22T14:30:05.123456+08:00
```

LDML answers in every width UTS #35 names, including the narrow era, quarter and
weekday, the day periods (`b` short, `B` long, with midnight and noon named), the
standalone weekday `c`, and the week year `Y` with its week `w`. A year outside
0000 to 9999 is written in the expanded form Temporal gives it — `+012026-01-02` —
and `parse` reads that form back.

The vectors come from each language's own implementation — CPython for the `%`
directives, a Rust program for chrono's additions, Go for the layout, Babel for
LDML, and Node for the ECMAScript strings — and are committed under `src/`; CI only
replays them. The generators are in `scripts/`.

One corpus is not a comparison but a specification: test262's `Temporal` suites,
pinned by commit, played against a stand-in that records what each test asserts.
A text there answers three questions — the instant, the day, the exact time — and
the cases this library answers for all three are replayed from
`src/temporal_vectors_wbtest.mbt`. The ones it does not are counted by reason; the
transcription is `scripts/temporal_vectors/`.

## Time zones

The calendar above has no database behind it, on purpose: `Zone` is a fixed offset,
which is everything a package with no I/O can honestly carry. The database is two
packages beside it, and they are separate because a caller that formats an HTTP
date should not have to carry a hundred kilobytes of rules it never reads.

| Package | What it is |
|:--|:--|
| `moonbitstack/moondate/zone` | A TZif file read (RFC 9636), the POSIX TZ strings a file's footer carries, and the question every wall clock raises in a zone |
| `moonbitstack/moondate/tzdata` | The IANA release itself, compiled from its own source the first time a zone is asked for |

```moonbit
let tz = @tzdata.load("America/New_York")
let moment = tz.moment(1790058605)                  // 2026-09-22T02:30:05-04:00
moment.strftime("%H:%M %Z %z")                      // 02:30 EDT -0400
moment.pattern("VV")                                // America/New_York
moment.layout(@moondate.RFC1123)                    // Tue, 22 Sep 2026 02:30:05 EDT
moment.isoformat(zone_name=true)                    // 2026-09-22T02:30:05-04:00[America/New_York]
```

A moment that carries a name carries the offset in force at that instant as well,
so it stays a value: it can be compared, written and moved to another zone with no
database in reach. Crossing a transition is the one thing a value cannot do, which
is what `Tz::moment` is for.

### The two hours that have no single answer

A place name is the one thing `parse` will not answer, because the answer depends
on a database it does not carry. `@tzdata.parse` is that entry point: it reads the
place from the release and takes `fold` for the hour that has none.

```moonbit
let moment = @tzdata.parse("2026-11-01T01:30:00[America/New_York]")
moment.strftime("%H:%M %Z")                         // 01:30 EDT
```

Twice a year a wall clock is a bad question. In most of the world one hour of a
spring morning never happens and one hour of an autumn night happens twice, and a
timestamp written by a program in that zone has to be read as one of the two.

| `fold` | A clock read twice | A clock never read |
|:--|:--|:--|
| `Compatible` (default) | the earlier instant | the later instant |
| `Earlier` / `Later` | by instant | by instant |
| `Reject` | refuses | refuses |

```moonbit
let tz = @tzdata.load("America/New_York")
tz.read(@moondate.Date::new(2026, 3, 8), @moondate.Time::new(2, 30))
// never, between 1772951400 and 1772955000
tz.read(@moondate.Date::new(2026, 11, 1), @moondate.Time::new(1, 30))
// twice, at 1793511000 and 1793514600
```

`Compatible` is what most callers mean and what the other implementations do by
default; `Reject` is there for a program that would rather stop than pick.

### Interface

| Type | Built with | Asked |
|:--|:--|:--|
| `Tz` | `@zone.Tz::parse(bytes)`, `@zone.Tz::of`, `@tzdata.load(name)` | `name`, `at`, `offset`, `abbrev`, `is_dst`, `changes`, `read`, `epoch`, `moment`, `zoned`, `readings`, `rule` |
| `Reading` | — | the fields: when it began, the offset in seconds, whether daylight saving was on, the abbreviation |
| `Local` | `Tz::read` | `epoch(fold~)`, `is_exact` |
| `Rule` | `Rule::parse` | `text`, `at` |
| `Tz` from the database | `@tzdata.load`, `@tzdata.find` | the same, plus `@tzdata.zones`, `@tzdata.links`, `@tzdata.release` |

Free functions in `zone`: `Tz::parse`, `Rule::parse`. In `tzdata`: `zones`,
`links`, `load`, `find`. Constants: `@tzdata.release` names the IANA version
carried and `@tzdata.source_digest` is the SHA-256 of the source text, so a release
can be recognised without reading it.

Errors are `zone.Refused`: `Malformed` carries what was expected and the byte it
stopped at, `Truncated` the size it wanted and the size it got, `Unsupported` the
TZif version it cannot read, `Unknown` a zone name no database has, and `Missing`
a wall clock that never happens when the policy is to refuse rather than guess.

### Where the data comes from

The package carries `tzdata.zi`, the release's own compendium of the `Rule`,
`Zone` and `Link` lines its editors maintain: 105 kB, a tenth the size of the
compiled tree, and readable in a diff when a release lands. `scripts/gen_tzdata.py`
fetches a release and rewrites `src/tzdata/data.mbt`; a workflow checks twice a
month for a new one and opens a pull request when there is.

Nothing in the database is a stub or a subset: every one of the 598 names the
release has is compiled from the same rules, and the transitions are the ones the
release's own `zic` writes.

## Interface

Types are listed with the calls that matter most; the [API reference](https://moonbitstack.github.io/moondate/api.html)
has every method and every parameter.

| Type | Built with | Asked |
|:--|:--|:--|
| `Date` | `Date::new`, `of_days`, `of_ordinal`, `of_isocalendar` | `weekday`, `yearday`, `isocalendar`, `ordinal`, `days`, `diff`, `plus_days`, `plus_months`, `replace` |
| `Time` | `Time::new`, `midnight`, `end_of_day` | `nanos`, `replace` |
| `Moment` | `parse`, `of_isoformat`, `http`, `asn1`, `strftime`, `strptime`, `layout`, `parse_layout`, `pattern`, `parse_pattern`, `combine`, `of_epoch` | `epoch`, `instant`, `timestamp`, `date`, `time`, `zone`, `utcoffset`, `astimezone`, `isoformat`, `to_iso_string`, `to_utc_string`, `strftime`, `layout`, `pattern`, `http_text`, `asn1_text`, `ctime`, `timetuple`, `weekday`, `isocalendar`, `ordinal`, `diff`, `plus`, `replace` |
| `Span` | `Span::new`, `of`, `nanosecond` … `day` | `add`, `sub`, `seconds`, `total_seconds`, `parts`, `neg`, `abs` |
| `Zone` | `Utc`, `Offset(minutes)`, `Named(name, offset, abbrev)`, `Precise(nanos)` | `nanos`, `seconds`, `minutes`, `name`, `abbrev` |
| `Cron` | `@cron.parse` | `matches`, `next` |

Free functions: `parse`, `of_isoformat`, `strptime`, `parse_layout`,
`parse_pattern`, `http`, `asn1`, `leap`, `length`. Constants: `min_date`,
`max_date`, `min_year`, `max_year`, `resolution`, `midnight`, `end_of_day`, the Go
layout constants (`RFC3339`, `RFC1123`, `ANSIC`, …), and one span per unit from
`nanosecond` to `day`.

Errors are one type with three reasons: `Range` carries the field, the value it
got and the range it wanted; `Malformed` carries what was expected; `Truncated`
carries the name of the thing that ran out of text.

## Examples

Every file under [`src/examples/`](src/examples) is a complete program with the output it
prints. Run one with `moon run src/examples/hello`.

| | What it shows |
|:--|:--|
| [`hello`](src/examples/hello) | The smallest complete program: read, look inside, write back. |
| [`shapes`](src/examples/shapes) | `Zoned`, `Plain`, `Day` and `Clock` side by side, and what each one can answer. |
| [`calendar`](src/examples/calendar) | Weekdays, ISO week dates, ordinals, month lengths, adding days and months. |
| [`zones`](src/examples/zones) | One instant written three ways, `astimezone`, the epoch both directions, spans. |
| [`wire`](src/examples/wire) | HTTP dates in three formats, ASN.1 time in two, and the refusals. |
| [`format`](src/examples/format) | One moment through all five styles: `%` directives, Go layout, LDML pattern, ECMAScript. |
| [`schedule`](src/examples/schedule) | Cron expressions: what they mean, the next few firings, the or-rule, the refusals. |
| [`worldclock`](src/examples/worldclock) | Five cities at one instant, and the two hours of the year that need a decision. |

## cron

```moonbit
let every_quarter = @cron.parse("*/15 9-17 * * MON-FRI")
let next = every_quarter.next(now)
```

Five fields as crontab(5) defines them, or six with seconds in front. `*`, `n`,
`a-b`, `*/n`, `a-b/n`, lists of those, month and day names, `?` for a day field
that is not in use, and the `@` shorthands. Both 0 and 7 are Sunday.

Day-of-month and day-of-week are or-ed when both are restricted, which is Vixie
cron's rule: `0 0 13 * 5` fires on the thirteenth or on any Friday, not only on
Friday the thirteenth. When one of them is `*` they are and-ed. This surprises
everyone once, so it has a test that says so.

An expression naming a day that does not exist — `0 0 30 2 *` — answers `None`
instead of searching forever.

## Reading the code

The calendar is `date.mbt`, the wire formats are `text.mbt`, the `%` directives
are `strftime.mbt`, the Go layout is `layout.mbt`, the LDML pattern is
`pattern.mbt`, the rest of the surface is `python.mbt`, the schedule is `cron/`,
the TZif reader and the POSIX rules are `zone/`, and the database is `tzdata/`.
Each public item has a doc comment saying what it does and, where there is a rule
behind it, which specification the rule comes from.

There is no `now()`. Reading the clock is I/O, this package has none, so a caller
passes what its own clock said to `Moment::of_epoch`.

This package never reads a file and never reads a clock. A zone database is a file,
and it is in `zone/` and `tzdata/` for the callers who need one.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
