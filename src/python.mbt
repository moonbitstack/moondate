// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The rest of the surface beyond the calendar itself: the ordinal, the ISO week
// date, combining and replacing parts, the epoch both ways, and the text forms
// RFC 3339, TOML, HTTP and ASN.1 name. The directive language lives in
// `strftime.mbt`.

///|
/// The earliest and latest dates this calendar writes with a four-digit year.
///
/// They are 1-01-01 and 9999-12-31, which is as far as a four-digit year writes;
/// the arithmetic here works outside that range, so these are a convention for
/// writing rather than a limit on computing.
pub let min_date : Date = { year: 1, month: 1, day: 1, }

///|
pub let max_date : Date = { year: 9999, month: 12, day: 31, }

///|
/// Midnight, and the last representable moment of a day.
pub let midnight : Time = { hour: 0, minute: 0, second: 0, nano: 0, }

///|
pub let end_of_day : Time = {
  hour: 23,
  minute: 59,
  second: 59,
  nano: 999_999_999,
}

///|
/// Days since 0001-01-01, that day being 1.
///
/// The proleptic Gregorian ordinal, which is what makes two dates subtractable
/// without going through an epoch.
pub fn Date::ordinal(self : Date) -> Int32 {
  self.days() + 719163
}

///|
/// The date with that ordinal.
pub fn Date::of_ordinal(n : Int32) -> Date {
  Date::of_days(n - 719163)
}

///|
/// The ISO 8601 week date: the year the week belongs to, the week number, and the
/// day of the week with Monday as 1.
///
/// The year is not always the calendar year. A week belongs to the year that holds
/// its Thursday, so the first of January can fall in the last week of the year
/// before — which is exactly the case a hand-rolled week number gets wrong.
pub fn Date::isocalendar(self : Date) -> (Int32, Int32, Int32) {
  let weekday = self.isoweekday()
  // The Thursday of this week decides which year the week counts against.
  let thursday = self.plus_days(4 - weekday)
  let year = thursday.year
  let jan1 = { year, month: 1, day: 1, }
  let week = (thursday.days() - jan1.days()) / 7 + 1
  (year, week, weekday)
}

///|
/// The day of the week with Monday as 1 and Sunday as 7.
///
/// [`Date::weekday`] counts from Sunday as 0, which is what cron and C's `tm_wday`
/// use; ISO counts from Monday as 1. Both are here because both are asked for, and
/// picking one silently is how an off-by-one gets into a schedule.
pub fn Date::isoweekday(self : Date) -> Int32 {
  let d = self.weekday()
  if d == 0 {
    7
  } else {
    d
  }
}

///|
/// The date named by an ISO week date.
pub fn Date::of_isocalendar(
  year : Int32,
  week : Int32,
  weekday : Int32,
) -> Date raise Refused {
  if week < 1 || week > 53 {
    raise Range(field="week", got=week, low=1, high=53)
  }
  if weekday < 1 || weekday > 7 {
    raise Range(field="weekday", got=weekday, low=1, high=7)
  }
  let jan4 : Date = { year, month: 1, day: 4, }
  // The fourth of January is always in week one, so the week's Monday follows.
  let week1 = jan4.plus_days(1 - jan4.isoweekday())
  week1.plus_days((week - 1) * 7 + weekday - 1)
}

///|
/// A date and a time as one wall-clock moment.
///
/// `zone` makes it an instant instead; leaving it off keeps it a wall clock, which
/// is what an opening time or an alarm is.
pub fn Moment::combine(date : Date, time : Time, zone? : Zone) -> Moment {
  match zone {
    Some(z) => Zoned(date~, time~, zone=z)
    None => Plain(date~, time~)
  }
}

///|
/// The same date with some parts replaced.
pub fn Date::replace(
  self : Date,
  year? : Int32,
  month? : Int32,
  day? : Int32,
) -> Date raise Refused {
  Date::new(
    match year {
      Some(v) => v
      None => self.year
    },
    match month {
      Some(v) => v
      None => self.month
    },
    match day {
      Some(v) => v
      None => self.day
    },
  )
}

///|
/// The same time with some parts replaced.
pub fn Time::replace(
  self : Time,
  hour? : Int32,
  minute? : Int32,
  second? : Int32,
  nano? : Int32,
) -> Time raise Refused {
  Time::new(
    match hour {
      Some(v) => v
      None => self.hour
    },
    match minute {
      Some(v) => v
      None => self.minute
    },
    second=match second {
      Some(v) => v
      None => self.second
    },
    nano=match nano {
      Some(v) => v
      None => self.nano
    },
  )
}

///|
/// The moment `seconds` after 1970-01-01T00:00:00Z, the inverse of
/// [`Moment::timestamp`].
///
/// Reading the clock is not this package's job — it has no I/O — so a caller that
/// wants "now" passes what its own clock said.
pub fn Moment::of_epoch(
  seconds : Int64,
  nano~ : Int32 = 0,
  zone~ : Zone = Utc,
) -> Moment {
  let offset = match zone {
    Utc => 0L
    Offset(m) => m.to_int64() * 60L
  }
  let wall = seconds + offset
  let mut days = wall / 86400L
  let mut rest = wall % 86400L
  if rest < 0L {
    rest = rest + 86400L
    days = days - 1L
  }
  Zoned(
    date=Date::of_days(days.to_int()),
    time={
      hour: (rest / 3600L).to_int(),
      minute: (rest / 60L % 60L).to_int(),
      second: (rest % 60L).to_int(),
      nano,
    },
    zone~,
  )
}

///|
/// One date less another, as a span of whole days.
pub fn Date::diff(self : Date, other : Date) -> Span {
  Span::of(day, (self.days() - other.days()).to_int64())
}

///|
/// One moment less another, for the two shapes that can be subtracted.
///
/// `None` when they are not comparable: an instant and a wall clock differ by an
/// amount that depends on a zone nobody supplied, and a bare time and a bare date
/// are not the same kind of thing.
pub fn Moment::diff(self : Moment, other : Moment) -> Span? {
  match (self.epoch(), other.epoch()) {
    (Some(a), Some(b)) => Some(Span::of(second, a - b))
    _ =>
      match (self, other) {
        (Plain(date~, time~), Plain(date=d2, time=t2)) =>
          Some({
            nanos: (date.days() - d2.days()).to_int64() * day.nanos +
            time.nanos() -
            t2.nanos(),
          })
        (Day(date~), Day(date=d2)) => Some(date.diff(d2))
        (Clock(time~), Clock(time=t2)) =>
          Some({ nanos: time.nanos() - t2.nanos(), })
        _ => None
      }
  }
}

///|
/// The span as seconds, fraction included.
pub fn Span::total_seconds(self : Span) -> Double {
  self.nanos.to_double() / 1.0e9
}

///|
/// The whole days in a span, and the seconds and nanoseconds left over — the three
/// fields a duration is usually stored in.
pub fn Span::parts(self : Span) -> (Int32, Int32, Int32) {
  let mut days = self.nanos / day.nanos
  let mut rest = self.nanos % day.nanos
  if rest < 0L {
    rest = rest + day.nanos
    days = days - 1L
  }
  (
    days.to_int(),
    (rest / 1_000_000_000L).to_int(),
    (rest % 1_000_000_000L).to_int(),
  )
}

///|
/// The years this calendar spans.
pub let min_year : Int32 = 1

///|
pub let max_year : Int32 = 9999

///|
/// The smallest difference two moments can have.
///
/// A nanosecond rather than a microsecond: the clock here is finer, which is
/// what a protocol timestamp and a benchmark both want.
pub let resolution : Span = nanosecond

///|
/// The date out of a moment.
///
/// `None` for a bare time, which has no date to give.
pub fn Moment::date(self : Moment) -> Date? {
  match self {
    Zoned(date~, ..) | Plain(date~, ..) | Day(date~) => Some(date)
    Clock(_) => None
  }
}

///|
/// The time out of a moment.
///
/// Midnight for a bare date, which is the time it names.
pub fn Moment::time(self : Moment) -> Time {
  match self {
    Zoned(time~, ..) | Plain(time~, ..) | Clock(time~) => time
    Day(_) => midnight
  }
}

///|
/// The zone a moment carries, or `None` when it carries none.
pub fn Moment::zone(self : Moment) -> Zone? {
  match self {
    Zoned(zone~, ..) => Some(zone)
    _ => None
  }
}

///|
/// How far the moment's clock is from UTC.
pub fn Moment::utcoffset(self : Moment) -> Span? {
  match self.zone() {
    Some(Utc) => Some(Span::of(minute, 0L))
    Some(Offset(m)) => Some(Span::of(minute, m.to_int64()))
    None => None
  }
}

///|
/// The same instant read in another zone.
///
/// `None` for the three shapes that are not instants: moving a wall clock to
/// another zone would be inventing the zone it was written in.
pub fn Moment::astimezone(self : Moment, zone : Zone) -> Moment? {
  match self.epoch() {
    Some(secs) => Some(Moment::of_epoch(secs, nano=self.time().nano, zone~))
    None => None
  }
}

///|
/// The same moment with some parts replaced.
pub fn Moment::replace(
  self : Moment,
  year? : Int32,
  month? : Int32,
  day? : Int32,
  hour? : Int32,
  minute? : Int32,
  second? : Int32,
  nano? : Int32,
  zone? : Zone,
) -> Moment raise Refused {
  let d = match self.date() {
    Some(d) => Some(d.replace(year?, month?, day?))
    None => None
  }
  let t = self.time().replace(hour?, minute?, second?, nano?)
  match (d, zone, self) {
    (Some(date), Some(z), _) => Zoned(date~, time=t, zone=z)
    (Some(date), None, Zoned(zone~, ..)) => Zoned(date~, time=t, zone~)
    (Some(date), None, Day(_)) => Day(date~)
    (Some(date), None, _) => Plain(date~, time=t)
    (None, _, _) => Clock(time=t)
  }
}

///|
/// The day of the week of the moment's date, Sunday being 0.
pub fn Moment::weekday(self : Moment) -> Int32? {
  self.date().map(d => d.weekday())
}

///|
/// The ISO week date of the moment's date.
pub fn Moment::isocalendar(self : Moment) -> (Int32, Int32, Int32)? {
  self.date().map(d => d.isocalendar())
}

///|
/// Days since 0001-01-01 of the moment's date.
pub fn Moment::ordinal(self : Moment) -> Int32? {
  self.date().map(d => d.ordinal())
}

///|
/// The moment as ISO 8601 text, which is what [`Show`] writes.
///
/// `sep` is the character between the date and the time, `T` by default; any
/// character works, and a space is what a log line wants.
///
/// `fraction` is the number of fractional-second digits, 0 to 9, truncated. Left out, it writes as
/// many as the value needs and none for a whole second, which is Temporal's `auto`.
///
/// `offset` writes the zone the moment carries, `Z` for UTC and `±HH:MM` for an
/// offset; `false` leaves the zone off, which is Temporal's `offset: "never"`.
pub fn Moment::isoformat(
  self : Moment,
  sep~ : Char = 'T',
  fraction? : Int32,
  offset~ : Bool = true,
) -> String {
  match self {
    Zoned(date~, time~, zone~) =>
      text_of(date) +
      sep.to_string() +
      iso_time(time, fraction) +
      iso_zone(Some(zone), offset)
    Plain(date~, time~) =>
      text_of(date) + sep.to_string() + iso_time(time, fraction)
    Day(date~) => text_of(date)
    Clock(time~) => iso_time(time, fraction)
  }
}

///|
/// The time part with the fractional-second digits `fraction` asks for.
fn iso_time(t : Time, fraction : Int32?) -> String {
  let head = pad(t.hour, 2) + ":" + pad(t.minute, 2) + ":" + pad(t.second, 2)
  match fraction {
    Some(n) if n <= 0 => head
    Some(n) => {
      let n = if n > 9 { 9 } else { n }
      head + "." + pad(t.nano / power10(9 - n), n)
    }
    None => {
      if t.nano == 0 {
        return head
      }
      let mut frac = pad(t.nano, 9)
      while frac.length() > 1 && frac[frac.length() - 1].to_int() == 48 {
        frac = frac[0:frac.length() - 1].to_owned()
      }
      head + "." + frac
    }
  }
}

///|
/// The zone part, or nothing when the moment carries none or `show` is false.
fn iso_zone(z : Zone?, show : Bool) -> String {
  if !show {
    return ""
  }
  match z {
    None => ""
    Some(Utc) => "Z"
    Some(Offset(m)) => {
      let sign = if m < 0 { "-" } else { "+" }
      let a = if m < 0 { -m } else { m }
      sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
    }
  }
}

///|
/// The `Date.prototype.toISOString` shape: always the UTC instant, always three
/// fractional digits, always a trailing `Z`.
///
/// A moment with no zone has no instant of its own, so its wall clock is taken as
/// UTC — the same convention [`Moment::strftime`] uses for a bare time.
pub fn Moment::to_iso_string(self : Moment) -> String {
  let (d0, t0, z) = match self {
    Zoned(date~, time~, zone~) => (date, time, Some(zone))
    Plain(date~, time~) => (date, time, None)
    Day(date~) => (date, midnight, None)
    Clock(time~) => ({ year: 1900, month: 1, day: 1, }, time, None)
  }
  let (date, time) = match z {
    Some(_) =>
      match self.epoch() {
        Some(secs) =>
          match Moment::of_epoch(secs, nano=self.time().nano, zone=Utc) {
            Zoned(date~, time~, ..) => (date, time)
            _ => (d0, t0)
          }
        None => (d0, t0)
      }
    None => (d0, t0)
  }
  text_of(date) +
  "T" +
  pad(time.hour, 2) +
  ":" +
  pad(time.minute, 2) +
  ":" +
  pad(time.second, 2) +
  "." +
  pad(time.nano / 1_000_000, 3) +
  "Z"
}

///|
/// The `Date.prototype.toUTCString` shape: `Tue, 22 Sep 2026 05:30:05 GMT`.
///
/// This is the HTTP date form [`Moment::http_text`] already writes, on the UTC
/// instant, which is exactly what ECMAScript's `toUTCString` produces.
pub fn Moment::to_utc_string(self : Moment) -> String raise Refused {
  self.http_text()
}

///|
/// A moment read from ISO 8601 text, which is what
/// [`parse`] does.
pub fn of_isoformat(src : StringView) -> Moment raise Refused {
  parse(src)
}

///|
/// The moment in C's `ctime` form: `Sun Nov  6 08:49:37 1994`.
///
/// The day is space-padded rather than zero-padded, which is the one thing that
/// distinguishes this form from every other.
pub fn Moment::ctime(self : Moment) -> String {
  let d = match self.date() {
    Some(d) => d
    None => { year: 1900, month: 1, day: 1, }
  }
  let t = self.time()
  let day_text = if d.day < 10 {
    " " + d.day.to_string()
  } else {
    d.day.to_string()
  }
  weekdays[d.weekday()] +
  " " +
  months[d.month - 1] +
  " " +
  day_text +
  " " +
  pad(t.hour, 2) +
  ":" +
  pad(t.minute, 2) +
  ":" +
  pad(t.second, 2) +
  " " +
  d.year.to_string()
}

///|
/// The nine fields of a broken-down time, in the usual order:
/// year, month, day, hour, minute, second, weekday counted from Monday as 0, day
/// of the year, and whether daylight saving applies — always `-1` here, because
/// that needs a zone database this package does not carry.
pub fn Moment::timetuple(
  self : Moment,
) -> (Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32, Int32) {
  let d = match self.date() {
    Some(d) => d
    None => { year: 1900, month: 1, day: 1, }
  }
  let t = self.time()
  (
    d.year,
    d.month,
    d.day,
    t.hour,
    t.minute,
    t.second,
    d.isoweekday() - 1,
    d.yearday(),
    -1,
  )
}

///|
/// Seconds since the epoch as a `Double`, fraction included.
pub fn Moment::timestamp(self : Moment) -> Double? {
  self.epoch().map(s => s.to_double() + self.time().nano.to_double() / 1.0e9)
}

///|
/// A span made of the usual parts: days, hours, minutes, seconds and fractions.
pub fn Span::new(
  days~ : Int64 = 0,
  hours~ : Int64 = 0,
  minutes~ : Int64 = 0,
  seconds~ : Int64 = 0,
  millis~ : Int64 = 0,
  micros~ : Int64 = 0,
  nanos~ : Int64 = 0,
) -> Span {
  {
    nanos: days * day.nanos +
    hours * hour.nanos +
    minutes * minute.nanos +
    seconds * second.nanos +
    millis * 1_000_000L +
    micros * 1_000L +
    nanos,
  }
}

///|
/// The span negated.
pub fn Span::neg(self : Span) -> Span {
  { nanos: -self.nanos, }
}

///|
/// The span with its sign dropped.
pub fn Span::abs(self : Span) -> Span {
  { nanos: if self.nanos < 0L { -self.nanos } else { self.nanos }, }
}
