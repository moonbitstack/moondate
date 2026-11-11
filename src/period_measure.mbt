// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A length measured on a calendar rather than on a clock: reading one from a
// text, rounding one, adding one up, and comparing two.
//
// The lengths here are counted from a date, so a day is twenty-four hours and a
// month is the day of the month it started on. That is what a plain calendar can
// say; a length in a named zone is `@moondate/zone`'s question, because there a
// day is short or long on the two days a year the clocks change, and only the
// zone's rules know which.

///|
/// The nanoseconds a day holds, which a plain calendar always has.
let day_of_nanos : Int64 = 86_400_000_000_000L

///|
/// The longest length these functions will count in nanoseconds: a little over
/// 292 years, which is what an `Int64` of nanoseconds reaches.
let longest_length : Int64 = 106_751L

///|
/// How long a unit is next to the others: a bigger number is a longer unit.
pub fn TimeUnit::order(self : TimeUnit) -> Int32 {
  match self {
    Nanos => 0
    Micros => 1
    Millis => 2
    Seconds => 3
    Minutes => 4
    Hours => 5
    Days => 6
    Weeks => 7
    Months => 8
    Years => 9
  }
}

///|
/// The unit a position in [`TimeUnit::order`] names.
fn unit_of_order(order : Int32) -> TimeUnit {
  match order {
    0 => Nanos
    1 => Micros
    2 => Millis
    3 => Seconds
    4 => Minutes
    5 => Hours
    6 => Days
    7 => Weeks
    8 => Months
    _ => Years
  }
}

///|
/// The nanoseconds the clock part of a length holds: the fields from hours down.
fn length_clock(length : Period) -> Int64 {
  length.hours * 3_600_000_000_000L +
  length.minutes * 60_000_000_000L +
  length.seconds * 1_000_000_000L +
  length.nanos
}

///|
/// The value of the field a unit names.
fn field_of(length : Period, unit : TimeUnit) -> Int64 {
  match unit {
    Years => length.years
    Months => length.months
    Weeks => length.weeks
    Days => length.days
    Hours => length.hours
    Minutes => length.minutes
    Seconds => length.seconds
    Millis => length.nanos / 1_000_000L
    Micros => length.nanos / 1_000L
    Nanos => length.nanos
  }
}

///|
/// The length with one field replaced.
fn with_field_of(length : Period, unit : TimeUnit, value : Int64) -> Period {
  match unit {
    Years => { ..length, years: value, }
    Months => { ..length, months: value, }
    Weeks => { ..length, weeks: value, }
    Days => { ..length, days: value, }
    Hours => { ..length, hours: value, }
    Minutes => { ..length, minutes: value, }
    Seconds => { ..length, seconds: value, }
    Millis => { ..length, nanos: value * 1_000_000L, }
    Micros => { ..length, nanos: value * 1_000L, }
    Nanos => { ..length, nanos: value, }
  }
}

///|
/// The length with every field below `unit` dropped and the ones above it kept.
fn shorter_than(length : Period, unit : TimeUnit) -> Period {
  match unit {
    Years =>
      {
        ..length,
        months: 0L,
        weeks: 0L,
        days: 0L,
        hours: 0L,
        minutes: 0L,
        seconds: 0L,
        nanos: 0L,
      }
    Months =>
      {
        ..length,
        weeks: 0L,
        days: 0L,
        hours: 0L,
        minutes: 0L,
        seconds: 0L,
        nanos: 0L,
      }
    Weeks =>
      { ..length, days: 0L, hours: 0L, minutes: 0L, seconds: 0L, nanos: 0L, }
    Days => { ..length, hours: 0L, minutes: 0L, seconds: 0L, nanos: 0L, }
    Hours => { ..length, minutes: 0L, seconds: 0L, nanos: 0L, }
    Minutes => { ..length, seconds: 0L, nanos: 0L, }
    Seconds => { ..length, nanos: 0L, }
    Millis => { ..length, nanos: length.nanos - length.nanos % 1_000_000L, }
    Micros => { ..length, nanos: length.nanos - length.nanos % 1_000L, }
    Nanos => length
  }
}

///|
/// Where a length lands, in nanoseconds from the midnight of the date it started
/// on.
///
/// A clock part longer than a day is counted in days first, so that a length of
/// twenty-five hours lands on the next day and not on an hour of the day after
/// the one it was written as.
fn lands_on(start : Date, length : Period) -> Int64 raise Refused {
  let clock = length_clock(length)
  let carried = clock / day_of_nanos
  let moved = start
    .plus_months((length.years * 12L + length.months).to_int())
    .plus_days((length.weeks * 7L + length.days + carried).to_int())
  let days = moved.days().to_int64() - start.days().to_int64()
  if days > longest_length || days < -longest_length {
    raise Malformed("the length is longer than a count of nanoseconds holds")
  }
  days * day_of_nanos + clock % day_of_nanos
}

///|
/// The length as the difference between a date and where it lands, written in the
/// fields the largest unit allows.
fn balanced(
  start : Date,
  length : Period,
  largest : TimeUnit,
) -> Period raise Refused {
  let clock = length_clock(length)
  let carried = clock / day_of_nanos
  let moved = start
    .plus_months((length.years * 12L + length.months).to_int())
    .plus_days((length.weeks * 7L + length.days + carried).to_int())
  if largest.order() <= Hours.order() {
    return balanced_from(lands_on(start, length), largest)
  }
  let dates = start.until(moved, largest_unit=largest)
  let clock = balanced_from(clock % day_of_nanos, Hours)
  {
    ..dates,
    hours: clock.hours,
    minutes: clock.minutes,
    seconds: clock.seconds,
    nanos: clock.nanos,
  }
}

///|
/// A count of nanoseconds as the fields from `largest` down, nothing above it.
fn balanced_from(total : Int64, largest : TimeUnit) -> Period {
  let sign = if total < 0L { -1L } else { 1L }
  let mut rest = if total < 0L { -total } else { total }
  let top = largest.order()
  let mut days = 0L
  let mut hours = 0L
  let mut minutes = 0L
  let mut seconds = 0L
  if top >= 6 {
    days = rest / day_of_nanos
    rest = rest % day_of_nanos
  }
  if top >= 5 {
    hours = rest / 3_600_000_000_000L
    rest = rest % 3_600_000_000_000L
  }
  if top >= 4 {
    minutes = rest / 60_000_000_000L
    rest = rest % 60_000_000_000L
  }
  if top >= 3 {
    seconds = rest / 1_000_000_000L
    rest = rest % 1_000_000_000L
  }
  {
    years: 0L,
    months: 0L,
    weeks: 0L,
    days: days * sign,
    hours: hours * sign,
    minutes: minutes * sign,
    seconds: seconds * sign,
    nanos: rest * sign,
  }
}

///|
/// How far into a window a point lies, as a fraction of it.
///
/// An exact half is kept as one: the two halves either side of a half are written
/// a fifth apart, so that the comparison that decides a tie cannot be lost to
/// floating point.
fn fraction_within(at : Int64, from : Int64, to : Int64) -> Double {
  let numerator = at - from
  if numerator == 0L {
    return 0.0
  }
  let denominator = to - from
  let far = if numerator < 0L { -numerator } else { numerator }
  let wide = if denominator < 0L { -denominator } else { denominator }
  let sense = if (numerator < 0L) == (denominator < 0L) { 1.0 } else { -1.0 }
  if far <= wide {
    if far == wide {
      return sense
    }
    let twice = far * 2L
    let half = if twice > wide {
      1.0
    } else if twice < wide {
      -1.0
    } else {
      0.0
    }
    sense * (0.5 + half / 5.0)
  } else {
    numerator.to_double() / denominator.to_double()
  }
}

///|
/// How far into a window a point lies, as the reference counts it when the answer
/// is a total rather than a rounding: a plain ratio, with no tie kept.
fn ratio_within(at : Int64, from : Int64, to : Int64) -> Double {
  (at - from).to_double() / (to - from).to_double()
}

///|
/// Whether a number is exactly halfway between two whole numbers.
fn at_a_half(value : Double) -> Bool {
  let rest = value % 1.0
  (if rest < 0.0 { -rest } else { rest }) == 0.5
}

///|
/// A number of steps taken to a whole number of them.
fn steps_rounded(steps : Double, rounding : Rounding) -> Int64 {
  let answer = match rounding {
    Floor => steps.floor()
    HalfFloor => if at_a_half(steps) { steps.floor() } else { steps.round() }
    Ceil => steps.ceil()
    HalfCeil => if at_a_half(steps) { steps.ceil() } else { steps.round() }
    Trunc => steps.trunc()
    HalfTrunc => if at_a_half(steps) { steps.trunc() } else { steps.round() }
    Expand => if steps < 0.0 { steps.floor() } else { steps.ceil() }
    HalfExpand => if steps < 0.0 { -(-steps).round() } else { steps.round() }
    HalfEven =>
      if at_a_half(steps) {
        let whole = steps.trunc()
        whole + whole % 2.0
      } else {
        steps.round()
      }
  }
  answer.to_int64()
}

///|
/// A length rounded to a whole number of increments.
fn length_rounded(
  value : Double,
  increment : Int64,
  rounding : Rounding,
) -> Int64 {
  steps_rounded(value / increment.to_double(), rounding) * increment
}

///|
/// The longest field a length states, which is the unit it is counted in.
fn largest_of(length : Period) -> TimeUnit {
  if length.years != 0L {
    Years
  } else if length.months != 0L {
    Months
  } else if length.weeks != 0L {
    Weeks
  } else if length.days != 0L {
    Days
  } else if length.hours != 0L {
    Hours
  } else if length.minutes != 0L {
    Minutes
  } else if length.seconds != 0L {
    Seconds
  } else if length.nanos != 0L {
    Nanos
  } else {
    Nanos
  }
}

///|
/// The step a rounding may be measured by, refused when it does not land on the
/// unit again.
fn step_checked(
  unit : TimeUnit,
  increment : Int64,
  largest : TimeUnit,
) -> Unit raise Refused {
  if increment < 1L {
    raise Malformed("the increment is not a positive number")
  }
  if !unit.is_exact() {
    if increment != 1L && unit != largest {
      raise Malformed(
        "a calendar unit is stepped by one unless it is the whole answer",
      )
    }
    return
  }
  let limit = match unit {
    Hours => 24L
    Minutes | Seconds => 60L
    _ => 1000L
  }
  if increment >= limit || limit % increment != 0L {
    raise Malformed("the increment does not divide the unit it steps by")
  }
}

///|
/// The length rounded to the smallest unit asked for, counted from a date.
///
/// Below a week a length is a count of time, and a day here is always
/// twenty-four hours, so the rounding is a division. From a week up the
/// candidates either side have to be placed on the calendar: a month is not a
/// number of days, and only the date it started on says how long it is.
fn rounded_from(
  start : Date,
  exact : Period,
  destination : Int64,
  largest : TimeUnit,
  unit : TimeUnit,
  increment : Int64,
  rounding : Rounding,
) -> Period raise Refused {
  let sign = exact.sign()
  if sign == 0 {
    return exact
  }
  if unit.order() <= Days.order() {
    // Below a week the fields a rounding may touch are a count of nanoseconds:
    // the years and months above them are a calendar's answer and are not what
    // is being rounded, so only the day and the clock are taken apart.
    if exact.days > longest_length || exact.days < -longest_length {
      raise Malformed("the length is longer than a count of nanoseconds holds")
    }
    let whole = exact.days * day_of_nanos + length_clock(exact)
    let step = (if unit == Days { day_of_nanos } else { unit.nanos().unwrap() }) *
      increment
    let rounded = round_increment(whole, step, rounding)
    let fields = balanced_from(
      rounded,
      if largest.order() > Days.order() {
        Days
      } else {
        largest
      },
    )
    let length = {
      ..exact,
      days: fields.days,
      hours: fields.hours,
      minutes: fields.minutes,
      seconds: fields.seconds,
      nanos: fields.nanos,
    }
    let moved = if sign > 0 {
      rounded / day_of_nanos > whole / day_of_nanos
    } else {
      rounded / day_of_nanos < whole / day_of_nanos
    }
    // A step that fills the day is carried into the week or the month above it,
    // which is what turns thirty days asked for in months into one month.
    if moved && unit != Weeks {
      return carried_from(
        start,
        sign,
        length,
        destination + (rounded - whole),
        unit,
        largest,
      )
    }
    return length
  }
  let folded = match unit {
    Weeks => { ..exact, weeks: exact.weeks + exact.days / 7L, }
    _ => exact
  }
  let base = shorter_than(folded, unit)
  let truncated = field_of(folded, unit) / increment * increment
  let step = increment * sign.to_int64()
  let lower_at = lands_on(start, with_field_of(base, unit, truncated))
  let upper_at = lands_on(start, with_field_of(base, unit, truncated + step))
  let inside = if step > 0L {
    lower_at <= destination && destination <= upper_at
  } else {
    upper_at <= destination && destination <= lower_at
  }
  let lower = if inside { truncated } else { truncated + step }
  let lower_at = if inside { lower_at } else { upper_at }
  let upper = lower + step
  let upper_at = lands_on(start, with_field_of(base, unit, upper))
  let fraction = fraction_within(destination, lower_at, upper_at)
  let total = lower.to_double() + fraction * step.to_double()
  let rounded = length_rounded(total, increment, rounding)
  let answer = with_field_of(base, unit, rounded)
  // A week is a unit nothing is carried into: the fields above it are a calendar's
  // answer and a week has no whole number of them, so a rounding to weeks stops
  // where it is.
  if rounded != truncated && unit != Weeks {
    carried_from(
      start,
      sign,
      answer,
      if rounded == upper {
        upper_at
      } else {
        lower_at
      },
      unit,
      largest,
    )
  } else {
    answer
  }
}

///|
/// A rounded length carried into the unit above when it lands where the rounded
/// one did: twelve months is one year, and the months are emptied.
fn carried_from(
  start : Date,
  sign : Int32,
  length : Period,
  landed : Int64,
  unit : TimeUnit,
  largest : TimeUnit,
) -> Period raise Refused {
  let mut length = length
  let mut order = (if unit.order() < Days.order() { Days } else { unit }).order() +
    1
  let top = largest.order()
  while order <= top {
    let bigger = unit_of_order(order)
    if bigger != Weeks || largest == Weeks {
      let taller = with_field_of(
        shorter_than(length, bigger),
        bigger,
        field_of(length, bigger) + sign.to_int64(),
      )
      let reaches = lands_on(start, taller)
      let towards = if landed > reaches {
        1
      } else if landed < reaches {
        -1
      } else {
        0
      }
      if towards != 0 && towards != sign {
        break
      }
      length = taller
    }
    order = order + 1
  }
  length
}
