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

A calendar with the arithmetic that goes with it, the text forms four
specifications define, and a second package that answers when a schedule fires
next.

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

## What it reads and writes

| Form | Where it is used |
|:--|:--|
| RFC 3339 / ISO 8601 | TOML, JSON Schema's `date-time`, most of the wire |
| IMF-fixdate, RFC 850, asctime | HTTP's `Date` header (RFC 9110 §5.6.7): all three read, the first written |
| UTCTime, GeneralizedTime | ASN.1, so X.509 validity (ITU-T X.680 §47) |
| `strftime` / `strptime` | The `%` directives C89 defines |

The two-digit-year windows differ between HTTP and X.509: 69/70 against 49/50.
Each is applied where its own specification says, because a certificate read by
HTTP's rule expires a century early.

## Interface

Types are listed with the calls that matter most; the [API reference](https://moonbitstack.github.io/moondate/api.html)
has every method and every parameter.

| Type | Built with | Asked |
|:--|:--|:--|
| `Date` | `Date::new`, `of_days`, `of_ordinal`, `of_isocalendar` | `weekday`, `yearday`, `isocalendar`, `ordinal`, `days`, `diff`, `plus_days`, `plus_months`, `replace` |
| `Time` | `Time::new`, `midnight`, `end_of_day` | `nanos`, `replace` |
| `Moment` | `parse`, `of_isoformat`, `http`, `asn1`, `strptime`, `combine`, `of_epoch` | `epoch`, `timestamp`, `date`, `time`, `zone`, `utcoffset`, `astimezone`, `isoformat`, `strftime`, `http_text`, `asn1_text`, `ctime`, `timetuple`, `weekday`, `isocalendar`, `ordinal`, `diff`, `plus`, `replace` |
| `Span` | `Span::new`, `of`, `nanosecond` … `day` | `add`, `sub`, `seconds`, `total_seconds`, `parts`, `neg`, `abs` |
| `Zone` | `Utc`, `Offset(minutes)` | — |
| `Cron` | `@cron.parse` | `matches`, `next` |

Free functions: `parse`, `of_isoformat`, `strptime`, `http`, `asn1`, `leap`,
`length`. Constants: `min_date`, `max_date`, `min_year`, `max_year`,
`resolution`, `midnight`, `end_of_day`, and one span per unit from `nanosecond`
to `day`.

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
| [`format`](src/examples/format) | Every `%` directive against one moment, then `strptime` reading it back. |
| [`schedule`](src/examples/schedule) | Cron expressions: what they mean, the next few firings, the or-rule, the refusals. |

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

The calendar is `date.mbt`, the wire formats are `text.mbt`, the rest of the
surface is `python.mbt`, and the schedule is `cron/`. Each public item has a doc
comment saying what it does and, where there is a rule behind it, which
specification the rule comes from.

There is no `now()`. Reading the clock is I/O, this package has none, so a caller
passes what its own clock said to `Moment::of_epoch`.

Named zones — daylight saving, the IANA database — are not here. `Zone` is a
fixed offset. A zone database is a different thing with a different update
cadence, and `%Z` writes `UTC` or nothing rather than inventing a name it cannot
recover.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
