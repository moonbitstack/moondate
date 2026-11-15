// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The length rounded to the smallest unit asked for.
///
/// A length in hours or less is a count of time, so it is divided. A length in
/// days, weeks, months or years is not: an hour is sixty minutes wherever it
/// falls, but a month is twenty-eight to thirty-one days depending on where it
/// starts, so the candidates either side have to be placed on a calendar and
/// `start` is the date they are placed from.
///
///     let from = @moondate.Date::new(2022, 1, 1)
///     let length = @moondate.Period::new(years=1, months=11, days=24)
///     assert_eq(
///       length.round(smallest_unit=@moondate.TimeUnit::Months, rounding=@moondate.Rounding::Expand, start=from).to_string(),
///       "P2Y",
///     )
pub fn Period::round(
  self : Period,
  smallest_unit~ : TimeUnit,
  increment~ : Int64 = 1L,
  rounding~ : Rounding = HalfExpand,
  start? : Date,
) -> Period raise Refused {
  checked(self)
  let largest = {
    let stated = largest_of(self)
    if smallest_unit.order() > stated.order() {
      smallest_unit
    } else {
      stated
    }
  }
  step_checked(smallest_unit, increment, largest)
  if self.is_zero() {
    return self
  }
  let answer = match start {
    Some(date) => {
      let destination = lands_on(date, self)
      let exact = balanced(date, self, largest)
      rounded_from(
        date, exact, destination, largest, smallest_unit, increment, rounding,
      )
    }
    None =>
      if self.has_date() || !smallest_unit.is_exact() {
        raise Malformed(
          "a length in days, weeks, months or years needs the date it starts from",
        )
      } else {
        let whole = landing_of_clock(self)
        balanced_from(
          round_landing(
            whole,
            smallest_unit.nanos().unwrap() * increment,
            rounding,
          ),
          largest,
        )
      }
  }
  checked(answer)
  answer
}

///|
/// The whole length as a count of one unit: how many days, or hours, a length is.
///
/// The answer is a fraction when the unit does not divide the length, which is
/// why it is a number rather than a count: eleven months is 0.91 of a year, and
/// the number of days in it depends on the date it started. A length with a date
/// part needs `start`, and an exact unit does not.
///
///     let length = @moondate.Period::parse("PT1H30M")
///     assert_eq(length.total(unit=@moondate.TimeUnit::Hours), 1.5)
pub fn Period::total(
  self : Period,
  unit~ : TimeUnit,
  start? : Date,
) -> Double raise Refused {
  checked(self)
  if !self.has_date() && unit.is_exact() {
    let whole = landing_of_clock(self)
    let per_day = day_of_nanos / unit.nanos().unwrap()
    return whole.days.to_double() * per_day.to_double() +
      whole.nanos.to_double() / unit.nanos().unwrap().to_double()
  }
  let date = match start {
    Some(date) => date
    None =>
      raise Malformed(
        "a length in days, weeks, months or years needs the date it starts from",
      )
  }
  let destination = lands_on(date, self)
  if unit.is_exact() {
    let per_day = day_of_nanos / unit.nanos().unwrap()
    return destination.days.to_double() * per_day.to_double() +
      destination.nanos.to_double() / unit.nanos().unwrap().to_double()
  }
  if self.is_zero() {
    return 0.0
  }
  let exact = balanced(date, self, unit)
  let whole = field_of(exact, unit)
  let base = shorter_than(exact, unit)
  let lower_at = lands_on(date, with_field_of(base, unit, whole))
  let step = if exact.sign() < 0 { -1L } else { 1L }
  let upper_at = lands_on(date, with_field_of(base, unit, whole + step))
  let fraction = ratio_within(destination, lower_at, upper_at)
  whole.to_double() + fraction * step.to_double()
}

///|
/// Two lengths ordered by how long they are.
///
/// A length in hours or less is a count of nanoseconds and needs nothing else. A
/// length with days, months or years in it is only a length once it has a date to
/// start from, and two lengths of eleven months can be different numbers of days
/// from different dates — which is the whole reason this takes one.
///
///     let short = @moondate.Period::parse("P1M")
///     let long = @moondate.Period::parse("P31D")
///     assert_eq(short.compare(long, start=@moondate.Date::new(2024, 2, 1)), -1)
pub fn Period::compare(
  self : Period,
  other : Period,
  start? : Date,
) -> Int32 raise Refused {
  checked(self)
  checked(other)
  if !self.has_date() && !other.has_date() {
    return landing_of_clock(self).compare(landing_of_clock(other))
  }
  let date = match start {
    Some(date) => date
    None =>
      raise Malformed(
        "a length in days, weeks, months or years needs the date it starts from",
      )
  }
  lands_on(date, self).compare(lands_on(date, other))
}
