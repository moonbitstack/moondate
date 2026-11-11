// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A difference between two instants, rounded the way a calendar rounds one.
//
// A length in days, weeks, months or years has no fixed size: a day is
// twenty-three, twenty-four or twenty-five hours depending on whether the clocks
// change in it, and a month is twenty-eight to thirty-one days depending on where
// it starts. So rounding one is not arithmetic on a number — it is placing the two
// candidates either side of the truncated value on the timeline and asking which
// of them the destination is nearer. A value that comes out at the top of its
// window is then carried into the unit above, which is what turns sixty minutes
// into the next hour rather than leaving `PT1H60M`.
//
// Everything here is measured from the start of the difference and never as an
// absolute instant: two values three centuries apart are a difference this library
// can hold, and adding them to the epoch would not be.

///|
/// The start a rounded difference is measured from.
///
/// Rounding a calendar length means asking where a candidate lands, and where it
/// lands depends on the wall clock it started from and on the zone that clock is
/// in. The date and the time are kept apart because a date part moves the date and
/// leaves the reading alone.
priv struct Origin {
  value : ZonedDateTime
  date : @moondate.Date
  time : @moondate.Time
}

///|
fn origin_of(value : ZonedDateTime) -> Origin {
  let (date, time) = wall_of(value)
  { value, date, time, }
}

///|
/// The largest difference a count of nanoseconds holds, in seconds: 2^63
/// nanoseconds is a little over 292 years, and a difference past that has no
/// number here.
let longest_span : Int64 = 9_223_372_036L

///|
/// Nanoseconds from one instant to another, refused when the count does not fit.
///
/// A wrong number is worse than no number: a difference that wraps is a length
/// that looks plausible and is not, so it is refused rather than wrapped.
fn nanos_between(
  start : ZonedDateTime,
  end : ZonedDateTime,
) -> Int64 raise Refused {
  let seconds = end.epoch - start.epoch
  if seconds > longest_span || seconds < -longest_span {
    raise Range(
      text="the difference is longer than a count of nanoseconds holds",
    )
  }
  seconds * 1_000_000_000L + end.nano.to_int64() - start.nano.to_int64()
}

///|
/// Where a candidate length lands, in nanoseconds from the start of the
/// difference.
///
/// Only the date part moves the marker, and it moves it on the wall clock: the
/// clock reading is the start's, so the offset a zone had then is the one the
/// candidate is placed by. A length with no date part lands where it started,
/// which is what the carry below compares against.
fn lands_at(origin : Origin, period : @moondate.Period) -> Int64 raise Refused {
  if !period.has_date() {
    return 0L
  }
  let date = origin.date
    .plus_months((period.years * 12L + period.months).to_int())
    .plus_days((period.weeks * 7L + period.days).to_int())
  let epoch = origin.value.tz.epoch(date, origin.time)
  let seconds = epoch - origin.value.epoch
  if seconds > longest_span || seconds < -longest_span {
    raise Range(text="the length is longer than a count of nanoseconds holds")
  }
  seconds * 1_000_000_000L
}

///|
/// The nanoseconds the clock part of a period holds.
fn clock_nanos(period : @moondate.Period) -> Int64 {
  period.hours * 3_600_000_000_000L +
  period.minutes * 60_000_000_000L +
  period.seconds * 1_000_000_000L +
  period.nanos
}

///|
/// The period with every field below `unit` dropped, `unit` and the ones above
/// it kept as they are.
fn below(
  period : @moondate.Period,
  unit : @moondate.TimeUnit,
) -> @moondate.Period {
  match unit {
    Years =>
      {
        ..period,
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
        ..period,
        weeks: 0L,
        days: 0L,
        hours: 0L,
        minutes: 0L,
        seconds: 0L,
        nanos: 0L,
      }
    Weeks =>
      { ..period, days: 0L, hours: 0L, minutes: 0L, seconds: 0L, nanos: 0L, }
    Days => { ..period, hours: 0L, minutes: 0L, seconds: 0L, nanos: 0L, }
    Hours => { ..period, minutes: 0L, seconds: 0L, nanos: 0L, }
    Minutes => { ..period, seconds: 0L, nanos: 0L, }
    Seconds => { ..period, nanos: 0L, }
    Millis => { ..period, nanos: period.nanos - period.nanos % 1_000_000L, }
    Micros => { ..period, nanos: period.nanos - period.nanos % 1_000L, }
    Nanos => period
  }
}

///|
/// The value of the field a unit names.
fn field_of(period : @moondate.Period, unit : @moondate.TimeUnit) -> Int64 {
  match unit {
    Years => period.years
    Months => period.months
    Weeks => period.weeks
    Days => period.days
    Hours => period.hours
    Minutes => period.minutes
    Seconds => period.seconds
    Millis => period.nanos / 1_000_000L
    Micros => period.nanos / 1_000L
    Nanos => period.nanos
  }
}

///|
/// The period with one field replaced.
fn with_field(
  period : @moondate.Period,
  unit : @moondate.TimeUnit,
  value : Int64,
) -> @moondate.Period {
  match unit {
    Years => { ..period, years: value, }
    Months => { ..period, months: value, }
    Weeks => { ..period, weeks: value, }
    Days => { ..period, days: value, }
    Hours => { ..period, hours: value, }
    Minutes => { ..period, minutes: value, }
    Seconds => { ..period, seconds: value, }
    Millis => { ..period, nanos: value * 1_000_000L, }
    Micros => { ..period, nanos: value * 1_000L, }
    Nanos => { ..period, nanos: value, }
  }
}

///|
/// The unit a rank names, the inverse of [`rank`].
fn unit_at(rank : Int32) -> @moondate.TimeUnit {
  match rank {
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
/// The sign of a number, as a whole number.
fn sign_of(n : Int64) -> Int32 {
  if n > 0L {
    1
  } else if n < 0L {
    -1
  } else {
    0
  }
}

///|
/// How far into a window one instant lies, as a fraction of it.
///
/// When the instant is inside the window the fraction is taken exactly, and a
/// tie is kept as a tie: the two halves either side of one half are written a
/// fifth apart so that a comparison of doubled values, which is where a tie is
/// decided, cannot be lost to floating point. Only a value past the end of its
/// window — which a rounding increment can leave it beyond — is divided as
/// floating point, because only then is the answer known to be nearer one end.
fn fraction_of(at : Int64, from : Int64, to : Int64) -> Double {
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
/// Whether a number is exactly halfway between two whole numbers.
fn is_half(value : Double) -> Bool {
  let rest = value % 1.0
  (if rest < 0.0 { -rest } else { rest }) == 0.5
}

///|
/// A number of steps rounded to a whole number of them.
///
/// The nine directions are the ones a rounding mode names: `HalfFloor` and
/// `HalfCeil` agree with rounding to nearest except on an exact half, where they
/// take the half in the direction they name, and `HalfEven` takes the one whose
/// step count is even.
fn round_steps(steps : Double, rounding : @moondate.Rounding) -> Int64 {
  let answer = match rounding {
    Floor => steps.floor()
    HalfFloor => if is_half(steps) { steps.floor() } else { steps.round() }
    Ceil => steps.ceil()
    HalfCeil => if is_half(steps) { steps.ceil() } else { steps.round() }
    Trunc => steps.trunc()
    HalfTrunc => if is_half(steps) { steps.trunc() } else { steps.round() }
    Expand => if steps < 0.0 { steps.floor() } else { steps.ceil() }
    HalfExpand => if steps < 0.0 { -(-steps).round() } else { steps.round() }
    HalfEven =>
      if is_half(steps) {
        let whole = steps.trunc()
        whole + whole % 2.0
      } else {
        steps.round()
      }
  }
  answer.to_int64()
}

///|
/// A value rounded to a whole number of increments, the way a calendar measures
/// one: a length in years or days is a count, not a number of nanoseconds.
fn round_length(
  value : Double,
  increment : Int64,
  rounding : @moondate.Rounding,
) -> Int64 {
  round_steps(value / increment.to_double(), rounding) * increment
}

///|
/// A length rounded to a unit of the calendar: the candidate either side of the
/// truncated value is placed, and the destination is measured between them.
///
/// A length in weeks has its days folded into weeks first, because a rounding to
/// weeks is a rounding of whole weeks. The window is the step the increment names,
/// and it is slid one step along when the destination falls outside it — which
/// happens when the truncated value is not in the direction the length runs.
fn nudge_relative(
  origin : Origin,
  sign : Int32,
  length : @moondate.Period,
  destination : Int64,
  unit : @moondate.TimeUnit,
  increment : Int64,
  rounding : @moondate.Rounding,
) -> (@moondate.Period, Int64, Bool) raise Refused {
  let length = match unit {
    Weeks => { ..length, weeks: length.weeks + length.days / 7L, }
    _ => length
  }
  let base = below(length, unit)
  let truncated = field_of(length, unit) / increment * increment
  let step = increment * sign.to_int64()
  let lower = truncated
  let lower_at = lands_at(origin, with_field(base, unit, lower))
  let upper_at = lands_at(origin, with_field(base, unit, lower + step))
  let inside = if step > 0L {
    lower_at <= destination && destination <= upper_at
  } else {
    upper_at <= destination && destination <= lower_at
  }
  let (lower, lower_at) = if inside {
    (lower, lower_at)
  } else {
    (lower + step, upper_at)
  }
  let upper = lower + step
  let upper_at = lands_at(origin, with_field(base, unit, upper))
  let fraction = fraction_of(destination, lower_at, upper_at)
  let total = lower.to_double() + fraction * step.to_double()
  let rounded = round_length(total, increment, rounding)
  (
    with_field(base, unit, rounded),
    if rounded == upper {
      upper_at
    } else {
      lower_at
    },
    rounded != truncated,
  )
}

///|
/// A length rounded to an hour or something smaller, when the date part is what
/// a day on the calendar gives.
///
/// The question here is which side of a day the rounded clock part falls on: a
/// difference of twenty-three hours across the day the clocks go forward is a
/// day and not twenty-three hours once it is rounded to days, and the day it
/// fills is the one the zone is having rather than twenty-four hours.
fn nudge_zoned_time(
  origin : Origin,
  sign : Int32,
  length : @moondate.Period,
  unit : @moondate.TimeUnit,
  increment : Int64,
  rounding : @moondate.Rounding,
) -> (@moondate.Period, Int64, Bool) raise Refused {
  let step = unit.nanos().unwrap() * increment
  let clock = clock_nanos(length)
  let rounded = @moondate.round_increment(clock, step, rounding)
  let dated = below(length, Hours)
  let here = lands_at(origin, dated)
  let there = lands_at(origin, { ..dated, days: dated.days + sign.to_int64(), })
  let span = there - here
  if sign_of(span) != sign {
    raise Missing(text="the day this length falls in has no length")
  }
  let beyond = rounded - span
  let (moved, clock) = if beyond != 0L && sign_of(beyond) != sign {
    (0L, rounded)
  } else {
    (sign.to_int64(), @moondate.round_increment(beyond, step, rounding))
  }
  let clock = balance(clock, Hours)
  (
    {
      ..dated,
      days: dated.days + moved,
      hours: clock.hours,
      minutes: clock.minutes,
      seconds: clock.seconds,
      nanos: clock.nanos,
    },
    (if moved == 0L { here } else { there }) + clock_nanos(clock),
    moved != 0L,
  )
}

///|
/// A length rounded to an hour or something smaller, with no zone in the
/// question: every day is twenty-four hours here, and the answer is one number
/// written out in the units the largest one allows.
fn nudge_uniform_time(
  length : @moondate.Period,
  destination : Int64,
  largest : @moondate.TimeUnit,
  unit : @moondate.TimeUnit,
  increment : Int64,
  rounding : @moondate.Rounding,
) -> (@moondate.Period, Int64, Bool) raise Refused {
  let day = 86_400_000_000_000L
  if length.days > longest_span / day || length.days < -longest_span / day {
    raise Range(text="the length is longer than a count of nanoseconds holds")
  }
  let whole = length.days * day + clock_nanos(length)
  let rounded = @moondate.round_increment(
    whole,
    unit.nanos().unwrap() * increment,
    rounding,
  )
  let grew = sign_of(rounded / day - whole / day) == sign_of(whole)
  let fields = balance(
    rounded,
    if rank(largest) > rank(Days) {
      Days
    } else {
      largest
    },
  )
  (
    {
      ..length,
      days: fields.days,
      hours: fields.hours,
      minutes: fields.minutes,
      seconds: fields.seconds,
      nanos: fields.nanos,
    },
    destination + (rounded - whole),
    grew,
  )
}

///|
/// The rounded length carried into the unit above when it has filled it.
///
/// A rounding that lands on the top of its window is a whole unit of the next
/// size: seven days asked for in weeks is one week, twelve months asked for in
/// years is one year, and the fields below the one carried into are empty. The
/// carry is kept only while the carried length still lands where the rounded one
/// did, which is what tells an exact twelve months from eleven months and a
/// rounding up: the first reaches the same instant, the second overshoots it.
fn carried(
  origin : Origin,
  sign : Int32,
  length : @moondate.Period,
  destination : Int64,
  unit : @moondate.TimeUnit,
  largest : @moondate.TimeUnit,
) -> @moondate.Period raise Refused {
  let mut length = length
  let mut step = rank(if rank(unit) < rank(Days) { Days } else { unit }) + 1
  let top = rank(largest)
  while step <= top {
    let bigger = unit_at(step)
    if bigger != Weeks || largest == Weeks {
      let taller = with_field(
        below(length, bigger),
        bigger,
        field_of(length, bigger) + sign.to_int64(),
      )
      let lands = lands_at(origin, taller)
      let towards = if destination > lands {
        1
      } else if destination < lands {
        -1
      } else {
        0
      }
      if towards != 0 && towards != sign {
        break
      }
      length = taller
    }
    step = step + 1
  }
  length
}

///|
/// A difference rounded to the smallest unit asked for.
///
/// `exact` is the difference as the largest unit writes it, before rounding.
fn round_difference(
  origin : Origin,
  destination : Int64,
  exact : @moondate.Period,
  largest : @moondate.TimeUnit,
  unit : @moondate.TimeUnit,
  rounding : @moondate.Rounding,
  increment : Int64,
) -> @moondate.Period raise Refused {
  let sign = exact.sign()
  if sign == 0 {
    return exact
  }
  let (answer, landed, grew) = if unit.is_exact() {
    if rank(largest) >= rank(Days) {
      nudge_zoned_time(origin, sign, exact, unit, increment, rounding)
    } else {
      nudge_uniform_time(exact, destination, largest, unit, increment, rounding)
    }
  } else {
    let (answer, landed, grew) = nudge_relative(
      origin, sign, exact, destination, unit, increment, rounding,
    )
    (answer, landed, grew)
  }
  if grew && unit != Weeks {
    carried(origin, sign, answer, landed, unit, largest)
  } else {
    answer
  }
}
