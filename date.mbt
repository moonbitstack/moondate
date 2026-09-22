// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a date, a time or a text form was refused.
///
/// A calendar that accepted the thirty-first of February would be no use as a
/// check, so every constructor here validates and says what was wrong.
pub(all) suberror Refused {
  Range(field~ : String, got~ : Int, low~ : Int, high~ : Int)
  Malformed(String)
  Truncated(String)
} derive(Eq, Debug)

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Range(field~, got~, low~, high~) =>
      logger.write_string("\{field} is \{got}, outside \{low}..\{high}")
    Malformed(m) => logger.write_string("malformed: " + m)
    Truncated(m) => logger.write_string("truncated: " + m)
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// A day on the proleptic Gregorian calendar.
///
/// Proleptic means the Gregorian rules are applied before 1582 as well, which is
/// what every interchange format in reach assumes and what makes arithmetic over
/// the whole range uniform.
pub(all) struct Date {
  year : Int
  month : Int
  day : Int
} derive(Eq, Compare, Debug)

///|
pub extend Date with Debug::{to_repr}

///|
pub extend Date with Eq::{not_equal, equal}

///|
pub extend Date with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
/// A time on a twenty-four hour clock, to the nanosecond.
///
/// A second of 60 is allowed: RFC 3339 §5.6 permits it for a leap second, and a
/// timestamp that records one is a real timestamp that a reader should not throw
/// away.
pub(all) struct Time {
  hour : Int
  minute : Int
  second : Int
  nano : Int
} derive(Eq, Compare, Debug)

///|
pub extend Time with Debug::{to_repr}

///|
pub extend Time with Eq::{not_equal, equal}

///|
pub extend Time with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
/// How far the clock is from UTC, in minutes east of it.
///
/// `Utc` and `Offset(0)` are both midnight-at-Greenwich, but they are not the same
/// thing to write down: RFC 3339 §4.3 gives `-00:00` to a timestamp whose offset is
/// unknown, and `Z` to one that is genuinely UTC.
pub(all) enum Zone {
  Utc
  Offset(Int)
} derive(Eq, Debug)

///|
pub extend Zone with Debug::{to_repr}

///|
pub extend Zone with Eq::{not_equal, equal}

///|
/// A point in time, in one of the four shapes a format names.
///
/// TOML 1.0.0 has exactly these four and gives them these meanings; RFC 3339
/// defines only `Zoned`. The distinction is not decoration: `Plain` is a wall
/// clock, which is what an alarm or an opening time is, and turning it into an
/// instant needs a zone nobody has supplied.
pub(all) enum Moment {
  Zoned(date~ : Date, time~ : Time, zone~ : Zone)
  Plain(date~ : Date, time~ : Time)
  Day(date~ : Date)
  Clock(time~ : Time)
} derive(Eq, Debug)

///|
pub extend Moment with Debug::{to_repr}

///|
pub extend Moment with Eq::{not_equal, equal}

///|
/// A length of time, to the nanosecond, with no calendar attached.
///
/// A span is not a number of months: a month is not a fixed length, so adding one
/// is a calendar operation (`Date::plus_months`) rather than arithmetic.
pub(all) struct Span {
  nanos : Int64
} derive(Eq, Compare, Debug)

///|
pub extend Span with Debug::{to_repr}

///|
pub extend Span with Eq::{not_equal, equal}

///|
pub extend Span with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
/// Nanoseconds in a second, a minute, an hour and a day.
pub let nanosecond : Span = { nanos: 1L, }

///|
pub let second : Span = { nanos: 1_000_000_000L, }

///|
pub let minute : Span = { nanos: 60L * 1_000_000_000L, }

///|
pub let hour : Span = { nanos: 3600L * 1_000_000_000L, }

///|
pub let day : Span = { nanos: 86400L * 1_000_000_000L, }

///|
/// A span of `n` of these.
pub fn Span::of(unit : Span, n : Int64) -> Span {
  { nanos: unit.nanos * n, }
}

///|
/// Two spans added.
pub fn Span::add(self : Span, other : Span) -> Span {
  { nanos: self.nanos + other.nanos, }
}

///|
/// One span less another.
pub fn Span::sub(self : Span, other : Span) -> Span {
  { nanos: self.nanos - other.nanos, }
}

///|
/// The span as whole seconds, rounded towards zero.
pub fn Span::seconds(self : Span) -> Int64 {
  self.nanos / 1_000_000_000L
}

// -- the calendar -------------------------------------------------------------

///|
/// Whether `year` has a twenty-ninth of February.
///
/// Every fourth year, except every hundredth, except every four-hundredth — the
/// rule that makes the calendar year 365.2425 days long.
pub fn leap(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// How many days `month` has in `year`.
pub fn length(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if leap(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// A date, checked against the calendar.
pub fn Date::new(year : Int, month : Int, day : Int) -> Date raise Refused {
  if month < 1 || month > 12 {
    raise Range(field="month", got=month, low=1, high=12)
  }
  let last = length(year, month)
  if day < 1 || day > last {
    raise Range(field="day", got=day, low=1, high=last)
  }
  { year, month, day, }
}

///|
/// Days since 1970-01-01, negative before it.
///
/// Howard Hinnant's `days_from_civil`: shift the year to start in March so the leap
/// day falls at the end, then the month lengths follow a pattern with no table.
pub fn Date::days(self : Date) -> Int {
  let y = if self.month <= 2 { self.year - 1 } else { self.year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let m = self.month
  let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + self.day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// The date `n` days after 1970-01-01, the inverse of [`Date::days`].
pub fn Date::of_days(n : Int) -> Date {
  let z = n + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  { year: if m <= 2 { y + 1 } else { y }, month: m, day: d, }
}

///|
/// The day of the week, Sunday being 0.
///
/// 1970-01-01 was a Thursday, which is where the 4 comes from.
pub fn Date::weekday(self : Date) -> Int {
  let d = (self.days() + 4) % 7
  if d < 0 {
    d + 7
  } else {
    d
  }
}

///|
/// The day of the year, the first of January being 1.
pub fn Date::yearday(self : Date) -> Int {
  self.days() - { year: self.year, month: 1, day: 1, }.days() + 1
}

///|
/// The date `n` days later, or earlier when `n` is negative.
pub fn Date::plus_days(self : Date, n : Int) -> Date {
  Date::of_days(self.days() + n)
}

///|
/// The date `n` months later, clamped to the end of the month it lands in.
///
/// The thirty-first of January plus one month is the twenty-eighth or
/// twenty-ninth of February, because there is no thirty-first. Every calendar
/// library makes this choice and they all make the same one.
pub fn Date::plus_months(self : Date, n : Int) -> Date {
  let total = self.year * 12 + (self.month - 1) + n
  let year = if total >= 0 { total / 12 } else { (total - 11) / 12 }
  let month = total - year * 12 + 1
  let last = length(year, month)
  { year, month, day: if self.day < last { self.day } else { last }, }
}

// -- the clock ----------------------------------------------------------------

///|
/// A time, checked against the clock.
pub fn Time::new(
  hour : Int,
  minute : Int,
  second? : Int = 0,
  nano? : Int = 0,
) -> Time raise Refused {
  if hour < 0 || hour > 23 {
    raise Range(field="hour", got=hour, low=0, high=23)
  }
  if minute < 0 || minute > 59 {
    raise Range(field="minute", got=minute, low=0, high=59)
  }
  // 60 is a leap second (RFC 3339 §5.6), which is a real reading of a real clock.
  if second < 0 || second > 60 {
    raise Range(field="second", got=second, low=0, high=60)
  }
  if nano < 0 || nano > 999_999_999 {
    raise Range(field="nano", got=nano, low=0, high=999_999_999)
  }
  { hour, minute, second, nano, }
}

///|
/// Nanoseconds since midnight.
pub fn Time::nanos(self : Time) -> Int64 {
  (
    (self.hour.to_int64() * 60L + self.minute.to_int64()) * 60L +
    self.second.to_int64()
  ) *
  1_000_000_000L +
  self.nano.to_int64()
}

// -- instants -----------------------------------------------------------------

///|
/// Seconds since 1970-01-01T00:00:00Z, for a moment that names one.
///
/// `None` for the three shapes that do not: a wall clock, a bare date and a bare
/// time are not instants until someone supplies the zone they are read in.
pub fn Moment::epoch(self : Moment) -> Int64? {
  match self {
    Zoned(date~, time~, zone~) => {
      let offset = match zone {
        Utc => 0
        Offset(m) => m
      }
      Some(
        date.days().to_int64() * 86400L +
        time.nanos() / 1_000_000_000L -
        offset.to_int64() * 60L,
      )
    }
    _ => None
  }
}

///|
/// The moment `span` later.
///
/// A bare date moves by whole days and a bare time wraps within the day, because
/// that is all each of them can mean.
pub fn Moment::plus(self : Moment, span : Span) -> Moment {
  match self {
    Zoned(date~, time~, zone~) => {
      let (d, t) = shift(date, time, span)
      Zoned(date=d, time=t, zone~)
    }
    Plain(date~, time~) => {
      let (d, t) = shift(date, time, span)
      Plain(date=d, time=t)
    }
    Day(date~) => Day(date=date.plus_days((span.nanos / day.nanos).to_int()))
    Clock(time~) => {
      let total = (time.nanos() + span.nanos) % day.nanos
      Clock(time=clock_of(if total < 0 { total + day.nanos } else { total }))
    }
  }
}

///|
/// A date and a time moved by a span, carrying into the date.
fn shift(date : Date, time : Time, span : Span) -> (Date, Time) {
  let total = time.nanos() + span.nanos
  let mut days = total / day.nanos
  let mut rest = total % day.nanos
  if rest < 0 {
    rest = rest + day.nanos
    days = days - 1L
  }
  (date.plus_days(days.to_int()), clock_of(rest))
}

///|
/// Nanoseconds since midnight as a time.
fn clock_of(nanos : Int64) -> Time {
  let s = nanos / 1_000_000_000L
  {
    hour: (s / 3600L).to_int(),
    minute: (s / 60L % 60L).to_int(),
    second: (s % 60L).to_int(),
    nano: (nanos % 1_000_000_000L).to_int(),
  }
}
