// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A unit of time, from a year down to a nanosecond.
///
/// The first four have no fixed length — a month is not a number of days and a
/// day is not a number of hours wherever the clocks change — so they are the
/// units a [`Period`] is counted in rather than a [`Span`]. The rest are exact,
/// and are what a span's nanoseconds are read back as.
#derive(Eq, Debug)
pub(all) enum TimeUnit {
  Years
  Months
  Weeks
  Days
  Hours
  Minutes
  Seconds
  Millis
  Micros
  Nanos
}

///|
pub extend TimeUnit with Debug::{to_repr}

///|
pub extend TimeUnit with Eq::{not_equal, equal}

///|
/// How many nanoseconds the exact units hold. `None` for the four that have no
/// fixed length.
pub fn TimeUnit::nanos(self : TimeUnit) -> Int64? {
  match self {
    Hours => Some(3_600_000_000_000L)
    Minutes => Some(60_000_000_000L)
    Seconds => Some(1_000_000_000L)
    Millis => Some(1_000_000L)
    Micros => Some(1_000L)
    Nanos => Some(1L)
    _ => None
  }
}

///|
/// Whether the unit has a fixed length: everything below a day.
pub fn TimeUnit::is_exact(self : TimeUnit) -> Bool {
  match self {
    Years | Months | Weeks | Days => false
    _ => true
  }
}

///|
/// Which way a value that falls between two others is moved.
///
/// `Trunc` is towards zero, `Expand` away from it, which is what a negative
/// value needs to be rounded "up" the way `Ceil` rounds a positive one. The
/// `Half` forms differ only in what they do with an exact half, and `HalfEven`
/// is the banker's rounding that keeps a long sum from drifting.
#derive(Eq, Debug)
pub(all) enum Rounding {
  Ceil
  Floor
  Expand
  Trunc
  HalfCeil
  HalfFloor
  HalfExpand
  HalfTrunc
  HalfEven
}

///|
pub extend Rounding with Debug::{to_repr}

///|
pub extend Rounding with Eq::{not_equal, equal}

///|
/// `value` moved to the nearest multiple of `increment`.
///
/// The remainder is taken towards zero, so the sign is the value's own and the
/// direction words mean what they say for either sign: `Ceil` is towards
/// positive infinity, `Expand` away from zero.
pub fn round_increment(
  value : Int64,
  increment : Int64,
  rounding : Rounding,
) -> Int64 {
  if increment <= 1L {
    return value
  }
  let rest = value % increment
  if rest == 0L {
    return value
  }
  let down = value - rest
  let up = if value > 0L { down + increment } else { down - increment }
  // The two candidates, named by which way they move: `near` is the one the
  // mode's default reaches for, `far` the other.
  let twice = (if rest < 0L { -rest } else { rest }) * 2L
  match rounding {
    Ceil => if value > 0L { up } else { down }
    Floor => if value > 0L { down } else { up }
    // Away from zero is the same direction on both sides of it.
    Expand => up
    Trunc => down
    HalfCeil =>
      if twice > increment || (twice == increment && value > 0L) {
        up
      } else {
        down
      }
    HalfFloor =>
      if twice > increment || (twice == increment && value < 0L) {
        up
      } else {
        down
      }
    HalfExpand => if twice >= increment { up } else { down }
    HalfTrunc => if twice > increment { up } else { down }
    HalfEven =>
      if twice > increment {
        up
      } else if twice < increment {
        down
      } else if down / increment % 2L == 0L {
        down
      } else {
        up
      }
  }
}

///|
/// A length of time written in calendar units as well as clock units.
///
/// [`Span`] is a number of nanoseconds: an hour is sixty minutes and nothing
/// else. A period is what a calendar adds — a month is the same day of the next
/// month, a day is the same clock reading tomorrow, and both are a different
/// number of nanoseconds depending on where and when they are added. That is why
/// adding one needs a zone and a starting point, and why the answer to "how far
/// apart are these two dates" depends on the units it is asked for.
///
/// The fields are not normalized against each other: `Period::new(months=25)` is
/// twenty-five months and not two years and a month, because that is what was
/// asked for and what a round trip has to give back.
#derive(Eq, Debug)
pub(all) struct Period {
  years : Int64
  months : Int64
  weeks : Int64
  days : Int64
  hours : Int64
  minutes : Int64
  seconds : Int64
  nanos : Int64
}

///|
pub extend Period with Debug::{to_repr}

///|
pub extend Period with Eq::{not_equal, equal}

///|
/// A period of each named field.
pub fn Period::new(
  years~ : Int64 = 0L,
  months~ : Int64 = 0L,
  weeks~ : Int64 = 0L,
  days~ : Int64 = 0L,
  hours~ : Int64 = 0L,
  minutes~ : Int64 = 0L,
  seconds~ : Int64 = 0L,
  millis~ : Int64 = 0L,
  micros~ : Int64 = 0L,
  nanos~ : Int64 = 0L,
) -> Period {
  {
    years,
    months,
    weeks,
    days,
    hours,
    minutes,
    seconds,
    nanos: millis * 1_000_000L + micros * 1_000L + nanos,
  }
}

///|
/// The period of no length at all.
pub let zero : Period = {
  years: 0L,
  months: 0L,
  weeks: 0L,
  days: 0L,
  hours: 0L,
  minutes: 0L,
  seconds: 0L,
  nanos: 0L,
}

///|
/// `n` of one unit.
pub fn Period::of(unit : TimeUnit, n : Int64) -> Period {
  match unit {
    Years => { ..zero, years: n, }
    Months => { ..zero, months: n, }
    Weeks => { ..zero, weeks: n, }
    Days => { ..zero, days: n, }
    Hours => { ..zero, hours: n, }
    Minutes => { ..zero, minutes: n, }
    Seconds => { ..zero, seconds: n, }
    Millis => { ..zero, nanos: n * 1_000_000L, }
    Micros => { ..zero, nanos: n * 1_000L, }
    Nanos => { ..zero, nanos: n, }
  }
}

///|
/// Whether every field is zero.
pub fn Period::is_zero(self : Period) -> Bool {
  self.years == 0L &&
  self.months == 0L &&
  self.weeks == 0L &&
  self.days == 0L &&
  self.hours == 0L &&
  self.minutes == 0L &&
  self.seconds == 0L &&
  self.nanos == 0L
}

///|
/// The same period the other way round.
pub fn Period::neg(self : Period) -> Period {
  {
    years: -self.years,
    months: -self.months,
    weeks: -self.weeks,
    days: -self.days,
    hours: -self.hours,
    minutes: -self.minutes,
    seconds: -self.seconds,
    nanos: -self.nanos,
  }
}

///|
/// One period added to another, field by field.
pub fn Period::add(self : Period, other : Period) -> Period {
  {
    years: self.years + other.years,
    months: self.months + other.months,
    weeks: self.weeks + other.weeks,
    days: self.days + other.days,
    hours: self.hours + other.hours,
    minutes: self.minutes + other.minutes,
    seconds: self.seconds + other.seconds,
    nanos: self.nanos + other.nanos,
  }
}

///|
/// The clock part as a span: the fields from hours down, which are exact.
pub fn Period::span(self : Period) -> Span {
  {
    nanos: self.hours * 3_600_000_000_000L +
    self.minutes * 60_000_000_000L +
    self.seconds * 1_000_000_000L +
    self.nanos,
  }
}

///|
/// Whether the period has a part a calendar has to place: years, months, weeks
/// or days.
pub fn Period::has_date(self : Period) -> Bool {
  self.years != 0L || self.months != 0L || self.weeks != 0L || self.days != 0L
}

///|
/// The sign of the whole period: 1, -1, or 0 when it is empty. A period whose
/// fields disagree has no single sign, and the largest field that is not zero
/// is what a difference between two values gives.
pub fn Period::sign(self : Period) -> Int32 {
  for
    n in [
      self.years,
      self.months,
      self.weeks,
      self.days,
      self.hours,
      self.minutes,
      self.seconds,
      self.nanos,
    ] {
    if n > 0L {
      return 1
    }
    if n < 0L {
      return -1
    }
  }
  0
}

///|
/// Whether the fields disagree about which way the period runs.
///
/// A period is a thing to add, and a calendar cannot add one that both goes
/// forward and back: the answer would depend on the order the fields were taken
/// in, which is not a length. A difference between two values never has this
/// shape; a period written by hand can.
pub fn Period::has_mixed_sign(self : Period) -> Bool {
  let mut forward = false
  let mut backward = false
  for
    n in [
      self.years,
      self.months,
      self.weeks,
      self.days,
      self.hours,
      self.minutes,
      self.seconds,
      self.nanos,
    ] {
    if n > 0L {
      forward = true
    }
    if n < 0L {
      backward = true
    }
  }
  forward && backward
}

///|
/// A period as a sentence: the ISO 8601 text for a duration.
pub impl Show for Period with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub extend Period with Show::{output}

///|
/// The period as the ISO 8601 text for a duration: `P1Y2M3DT4H5M6.007S`.
///
/// A period whose fields all run the same way is written with one sign in front
/// and the fields in absolute value, which is how a reader expects a duration to
/// look; a period that mixes them — `until` never gives one, a caller can — is
/// written with each field signed, which is the only way to say it in the
/// grammar.
pub fn Period::to_string(self : Period) -> String {
  if self.is_zero() {
    return "PT0S"
  }
  let sign = self.sign()
  let mut mixed = false
  for
    n in [
      self.years,
      self.months,
      self.weeks,
      self.days,
      self.hours,
      self.minutes,
      self.seconds,
      self.nanos,
    ] {
    if n != 0L && (if n > 0L { 1 } else { -1 }) != sign {
      mixed = true
    }
  }
  let put = fn(n : Int64) -> String {
    if mixed {
      n.to_string()
    } else {
      (if n < 0L { -n } else { n }).to_string()
    }
  }
  let out = StringBuilder()
  if !mixed && sign < 0 {
    out.write_string("-")
  }
  out.write_string("P")
  for
    (n, letter) in [
      (self.years, "Y"),
      (self.months, "M"),
      (self.weeks, "W"),
      (self.days, "D"),
    ] {
    if n != 0L {
      out.write_string(put(n))
      out.write_string(letter)
    }
  }
  let seconds = self.seconds
  if self.hours != 0L || self.minutes != 0L || seconds != 0L || self.nanos != 0L {
    out.write_string("T")
    if self.hours != 0L {
      out.write_string(put(self.hours))
      out.write_string("H")
    }
    if self.minutes != 0L {
      out.write_string(put(self.minutes))
      out.write_string("M")
    }
    if seconds != 0L || self.nanos != 0L {
      out.write_string(put(seconds))
      if self.nanos != 0L {
        let rest = if self.nanos < 0L { -self.nanos } else { self.nanos }
        let mut digits = rest.to_string()
        while digits.length() < 9 {
          digits = "0" + digits
        }
        while digits.length() > 1 &&
              digits[digits.length() - 1].unsafe_to_char() == '0' {
          digits = digits[:digits.length() - 1].to_owned()
        }
        out.write_string(".")
        out.write_string(digits)
      }
      out.write_string("S")
    }
  }
  out.to_string()
}
