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
//
// A count of nanoseconds runs out after 292 years — an `Int64` holds no more —
// and a length does not: the reference a duration is measured against allows
// every field to 2^32 - 1, which is more than four thousand million years. So a
// length is never folded into one number here. It is placed as a [`Landing`]: the
// whole days from the date it started on, and the nanoseconds into the day. The
// two are added, rounded and compared as a pair, which is exact over the whole
// range and costs nothing in the range a single number could have held.

///|
/// The nanoseconds a day holds, which a plain calendar always has.
let day_of_nanos : Int64 = 86_400_000_000_000L

///|
/// The largest value a field of a length may hold: 2^32 - 1.
///
/// It is the reference's own bound rather than one this library chose, and it is
/// the bound the parser and the arithmetic refuse at, so a length that is written
/// down and a length that is calculated fail in the same place. It is the bound of
/// the calendar fields; the clock fields are bounded together, by [`checked`].
let largest_field : Int64 = 4_294_967_295L

///|
/// The largest number of seconds the clock part of a length may hold: 2^53.
///
/// A day, an hour, a minute and a second are not bounded one by one — a length of
/// four thousand million days is a length — only their sum is, and 2^53 seconds is
/// a little over 285 million years.
let largest_seconds : Int64 = 9_007_199_254_740_992L

///|
/// The days 2^53 seconds reaches, so that a clock part can be refused without
/// ever being counted in seconds.
let reach_in_days : Int64 = 104_249_991_374L

///|
/// The years a date can name, both ways from the epoch: a day count is an `Int32`
/// and a year is 365.2425 days of them.
let longest_year : Int64 = 5_877_641L

///|
/// `n` divided by `d`, rounded down, so the remainder is never negative.
fn floor_div(n : Int64, d : Int64) -> Int64 {
  let q = n / d
  if n % d < 0L {
    q - 1L
  } else {
    q
  }
}

///|
/// Where a length lands, counted in whole days from the date it started on and
/// nanoseconds into the day.
///
/// The nanoseconds are always in `0 .. day_of_nanos`, which is what lets a
/// comparison be two comparisons and a rounding be a remainder. A negative
/// landing keeps the form too: `-PT12H` is one day back and twelve hours on, so
/// `days` is the floor and `nanos` is never the sign's business.
priv struct Landing {
  days : Int64
  nanos : Int64
}

///|
/// A landing from a day count and a nanosecond count that may be past a day.
fn landing_of(days : Int64, nanos : Int64) -> Landing {
  let carried = floor_div(nanos, day_of_nanos)
  { days: days + carried, nanos: nanos - carried * day_of_nanos, }
}

///|
/// A landing from a count of nanoseconds, which is what a caller who already has
/// one — a clock part, a span — holds.
fn landing_of_nanos(total : Int64) -> Landing {
  landing_of(0L, total)
}

///|
/// `n` of a field whose `per` of them make a day.
fn landing_of_field(n : Int64, per : Int64, unit_nanos : Int64) -> Landing {
  let whole = floor_div(n, per)
  landing_of(whole, (n - whole * per) * unit_nanos)
}

///|
/// Two landings added.
fn Landing::plus(self : Landing, other : Landing) -> Landing {
  landing_of(self.days + other.days, self.nanos + other.nanos)
}

///|
/// One landing taken from another.
fn Landing::minus(self : Landing, other : Landing) -> Landing {
  landing_of(self.days - other.days, self.nanos - other.nanos)
}

///|
/// The landing the clock fields of a length name: everything below a day.
fn landing_of_clock(length : Period) -> Landing {
  landing_of_field(length.hours, 24L, 3_600_000_000_000L)
  .plus(landing_of_field(length.minutes, 1_440L, 60_000_000_000L))
  .plus(landing_of_field(length.seconds, 86_400L, 1_000_000_000L))
  .plus(landing_of_nanos(length.nanos))
}

///|
/// Which of two landings is further along.
fn Landing::compare(self : Landing, other : Landing) -> Int32 {
  if self.days < other.days {
    -1
  } else if self.days > other.days {
    1
  } else if self.nanos < other.nanos {
    -1
  } else if self.nanos > other.nanos {
    1
  } else {
    0
  }
}

///|
/// Whether the landing is before the date it started on.
fn Landing::is_negative(self : Landing) -> Bool {
  self.days < 0L
}

///|
/// The landing as one count of nanoseconds, for the questions a length under 292
/// years answers as a number. `None` past that, where no such count exists.
fn Landing::as_nanos(self : Landing) -> Int64? {
  let reach = 106_751L
  if self.days > reach || self.days < -reach {
    return None
  }
  Some(self.days * day_of_nanos + self.nanos)
}

///|
/// A date moved by whole months and whole days, refusing a move out of the range
/// a date names.
///
/// `Date::plus_months` and `Date::plus_days` count in an `Int32`, so a length of
/// a million years has to be refused there or it wraps; this is where the length
/// says which it is.
fn shifted(start : Date, months : Int64, days : Int64) -> Date raise Refused {
  let total = start.year.to_int64() * 12L +
    (start.month - 1).to_int64() +
    months
  let year = floor_div(total, 12L)
  if year > longest_year || year < -longest_year {
    raise Malformed("the length reaches past the years a date can name")
  }
  let month = total - year * 12L + 1L
  let last = length(year.to_int(), month.to_int())
  let landed = {
    year: year.to_int(),
    month: month.to_int(),
    day: if start.day < last {
      start.day
    } else {
      last
    },
  }
  let at = landed.days().to_int64() + days
  if at > 2_147_483_647L || at < -2_147_483_648L {
    raise Malformed("the length reaches past the days a date can name")
  }
  Date::of_days(at.to_int())
}

///|
/// Where a length lands, in days from the date it started on and nanoseconds into
/// the day.
///
/// A clock part longer than a day is counted in days first, so that a length of
/// twenty-five hours lands on the next day and not on an hour of the day after
/// the one it was written as.
fn lands_on(start : Date, length : Period) -> Landing raise Refused {
  let clock = landing_of_clock(length)
  let (carried, rest) = truncated(clock)
  let moved = shifted(
    start,
    length.years * 12L + length.months,
    length.weeks * 7L + length.days + carried,
  )
  landing_of(moved.days().to_int64() - start.days().to_int64(), rest)
}

///|
/// The length as the difference between a date and where it lands, written in the
/// fields the largest unit allows.
fn balanced(
  start : Date,
  length : Period,
  largest : TimeUnit,
) -> Period raise Refused {
  let clock = landing_of_clock(length)
  let (carried, rest) = truncated(clock)
  let moved = shifted(
    start,
    length.years * 12L + length.months,
    length.weeks * 7L + length.days + carried,
  )
  if largest.order() <= Hours.order() {
    return balanced_from(lands_on(start, length), largest)
  }
  let dates = start.until(moved, largest_unit=largest)
  let fields = balanced_from(landing_of(0L, rest), Hours)
  {
    ..dates,
    hours: fields.hours,
    minutes: fields.minutes,
    seconds: fields.seconds,
    nanos: fields.nanos,
  }
}

///|
/// The landing with the clock part carried into days the way a truncation does
/// it: towards zero, so that the remainder keeps the sign of the length.
///
/// Which day a length lands on is a question about the months above it, and the
/// months are counted from the day the truncating carry names: `-P30DT23H` is
/// thirty days back and twenty-three hours more, and a month is measured from the
/// day that leaves, not from the one below it.
fn truncated(clock : Landing) -> (Int64, Int64) {
  if clock.nanos == 0L {
    (clock.days, 0L)
  } else if clock.is_negative() {
    (clock.days + 1L, clock.nanos - day_of_nanos)
  } else {
    (clock.days, clock.nanos)
  }
}

///|
/// A landing as the fields from `largest` down, nothing above it.
fn balanced_from(total : Landing, largest : TimeUnit) -> Period raise Refused {
  let negative = total.is_negative()
  let sign = if negative { -1L } else { 1L }
  // The magnitude form: the fields are counted without a sign and written with
  // one at the end, so that every field of a length runs the same way.
  let mut days = if negative { -total.days } else { total.days }
  let mut nanos = total.nanos
  if negative && nanos != 0L {
    days = days - 1L
    nanos = day_of_nanos - nanos
  }
  let top = largest.order()
  if top < 6 {
    // Every exact unit divides a day, so the day count folds into the largest one
    // without the value ever becoming a count of nanoseconds.
    let unit = largest.nanos().unwrap()
    let per_day = day_of_nanos / unit
    if days > reach_in_days / per_day {
      raise Malformed("the length is more than a field of it can state")
    }
    let count = days * per_day + nanos / unit
    let rest = nanos % unit
    let fields = spread(count, rest, top)
    return {
      years: 0L,
      months: 0L,
      weeks: 0L,
      days: 0L,
      hours: fields.hours * sign,
      minutes: fields.minutes * sign,
      seconds: fields.seconds * sign,
      nanos: fields.nanos * sign,
    }
  }
  let hours = nanos / 3_600_000_000_000L
  nanos = nanos % 3_600_000_000_000L
  let minutes = nanos / 60_000_000_000L
  nanos = nanos % 60_000_000_000L
  let seconds = nanos / 1_000_000_000L
  nanos = nanos % 1_000_000_000L
  {
    years: 0L,
    months: 0L,
    weeks: 0L,
    days: days * sign,
    hours: hours * sign,
    minutes: minutes * sign,
    seconds: seconds * sign,
    nanos: nanos * sign,
  }
}

///|
/// A count of a unit, and the nanoseconds below it, as the clock fields from that
/// unit down.
fn spread(count : Int64, rest : Int64, top : Int32) -> Period {
  let mut count = count
  let mut rest = rest
  let mut hours = 0L
  let mut minutes = 0L
  let mut seconds = 0L
  if top >= 5 {
    hours = count
    count = 0L
    minutes = rest / 60_000_000_000L
    rest = rest % 60_000_000_000L
    seconds = rest / 1_000_000_000L
    rest = rest % 1_000_000_000L
  } else if top >= 4 {
    minutes = count
    count = 0L
    seconds = rest / 1_000_000_000L
    rest = rest % 1_000_000_000L
  } else if top >= 3 {
    seconds = count
    count = 0L
  } else {
    rest = count * 1_000_000L + rest
    count = 0L
  }
  let _ = count
  {
    years: 0L,
    months: 0L,
    weeks: 0L,
    days: 0L,
    hours,
    minutes,
    seconds,
    nanos: rest,
  }
}

///|
/// A landing rounded to a multiple of a step that divides a day.
///
/// The step divides the day, so what is rounded is the nanoseconds into the day
/// and the day count only ever moves by one — which is what keeps a length of a
/// million years rounded to the second without a count of nanoseconds that holds
/// it.
fn round_landing(value : Landing, step : Int64, rounding : Rounding) -> Landing {
  if step <= 1L {
    return value
  }
  let rest = value.nanos % step
  if rest == 0L {
    return value
  }
  let down = { days: value.days, nanos: value.nanos - rest, }
  let up = landing_of(down.days, down.nanos + step)
  let negative = value.is_negative()
  let twice = rest * 2L
  let over = twice > step
  let tie = twice == step
  let raise_up = match rounding {
    Ceil => true
    Floor => false
    Expand => !negative
    Trunc => negative
    HalfCeil => over || tie
    HalfFloor => over
    HalfExpand => if tie { !negative } else { over }
    HalfTrunc => if tie { negative } else { over }
    HalfEven =>
      if tie {
        // Two steps meet; the even one wins. A step smaller than a day leaves an
        // even number of them in a day, so only the nanoseconds decide there.
        if step == day_of_nanos {
          value.days % 2L != 0L
        } else {
          down.nanos / step % 2L != 0L
        }
      } else {
        over
      }
  }
  if raise_up {
    up
  } else {
    down
  }
}

///|
/// A landing rounded to a whole number of days.
fn round_landing_days(
  value : Landing,
  increment : Int64,
  rounding : Rounding,
) -> Landing raise Refused {
  if increment <= 1L && value.nanos == 0L {
    return value
  }
  if increment > largest_field {
    raise Malformed("the increment is more than a length holds")
  }
  let down = landing_of(floor_div(value.days, increment) * increment, 0L)
  if value.nanos == 0L && value.days == down.days {
    return value
  }
  let up = landing_of(down.days + increment, 0L)
  let negative = value.is_negative()
  // The distance to either candidate, compared as a landing rather than as a
  // count of nanoseconds, which a step of many days does not fit.
  let below = value
  let distance_down = landing_of(below.days - down.days, below.nanos)
  let distance_up = landing_of(up.days - below.days, -below.nanos)
  let nearer_up = distance_down.compare(distance_up) > 0
  let tie = distance_down.compare(distance_up) == 0
  let raise_up = match rounding {
    Ceil => true
    Floor => false
    Expand => !negative
    Trunc => negative
    HalfCeil => if tie { !negative } else { nearer_up }
    HalfFloor => if tie { negative } else { nearer_up }
    HalfExpand => if tie { !negative } else { nearer_up }
    HalfTrunc => if tie { negative } else { nearer_up }
    HalfEven => if tie { down.days / increment % 2L != 0L } else { nearer_up }
  }
  if raise_up {
    up
  } else {
    down
  }
}

///|
/// The nanoseconds between two landings, for the windows a rounding measures —
/// a week, a month, a year. `None` when the two are further apart than a count of
/// nanoseconds reaches, which no window is.
fn window_nanos(from : Landing, to : Landing) -> Int64? {
  let days = to.days - from.days
  if days > 106_751L || days < -106_751L {
    return None
  }
  Some(days * day_of_nanos + to.nanos - from.nanos)
}

///|
/// How far into a window a point lies, as a fraction of it.
///
/// An exact half is kept as one: the two halves either side of a half are written
/// a fifth apart, so that the comparison that decides a tie cannot be lost to
/// floating point.
fn fraction_within(at : Landing, from : Landing, to : Landing) -> Double {
  let numerator = window_nanos(from, at).unwrap_or(0L)
  if numerator == 0L {
    return 0.0
  }
  let denominator = window_nanos(from, to).unwrap_or(0L)
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
fn ratio_within(at : Landing, from : Landing, to : Landing) -> Double {
  window_nanos(from, at).unwrap_or(0L).to_double() /
  window_nanos(from, to).unwrap_or(1L).to_double()
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
/// Refuse a length one of whose fields is past what a duration holds.
///
/// A duration bounds its calendar fields one by one at 2^32 - 1 and its clock
/// fields together at 2^53 seconds, and the reference refuses the text or the
/// calculation that passes either bound. A period built by hand can state any
/// `Int64`, so this is where measuring it says which of the two it is.
fn checked(length : Period) -> Unit raise Refused {
  for
    (n, name) in [
      (length.years, "years"),
      (length.months, "months"),
      (length.weeks, "weeks"),
    ] {
    if n > largest_field || n < -largest_field {
      raise Malformed("\{name} is past the largest a field of a length holds")
    }
  }
  let clock = landing_of(length.days, 0L).plus(landing_of_clock(length))
  let days = if clock.days < 0L { -clock.days } else { clock.days }
  if days > reach_in_days {
    raise Malformed("the length is more than a duration holds")
  }
  if days == reach_in_days {
    // Only a count at the boundary has to be told exactly, and it fits an Int64
    // there: 2^53 seconds is a hundred thousand million days.
    let seconds = clock.days * 86_400L + clock.nanos / 1_000_000_000L
    if seconds >= largest_seconds || seconds <= -largest_seconds {
      raise Malformed("the length is more than a duration holds")
    }
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
  destination : Landing,
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
    // Below a week the fields a rounding may touch are a count of time: the years
    // and months above them are a calendar's answer and are not what is being
    // rounded, so only the day and the clock are taken apart.
    let whole = landing_of(exact.days, 0L).plus(landing_of_clock(exact))
    let rounded = if unit == Days {
      round_landing_days(whole, increment, rounding)
    } else {
      round_landing(whole, unit.nanos().unwrap() * increment, rounding)
    }
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
      rounded.days > whole.days
    } else {
      rounded.days < whole.days
    }
    // A step that fills the day is carried into the week or the month above it,
    // which is what turns thirty days asked for in months into one month.
    if moved && unit != Weeks {
      let landed = destination.plus(rounded).minus(whole)
      return carried_from(start, sign, length, landed, unit, largest)
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
    lower_at.compare(destination) <= 0 && destination.compare(upper_at) <= 0
  } else {
    upper_at.compare(destination) <= 0 && destination.compare(lower_at) <= 0
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
  landed : Landing,
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
      let towards = landed.compare(reaches)
      if towards != 0 && towards != sign {
        break
      }
      length = taller
    }
    order = order + 1
  }
  length
}

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
