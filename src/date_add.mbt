// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A period added to a date.
///
/// The months are added first and clamp to a day the month has, then the days,
/// and the clock part is carried as whole days — truncating, so twelve hours move
/// no date and thirty-six move it by one — because a date has no time of day to
/// keep the remainder in. A period whose fields do not all run the same way is
/// refused: a calendar cannot add one that goes forward and back at once, since
/// the answer would depend on the order the fields were taken in.
///
///     let date = @moondate.Date::new(2024, 1, 31)
///     assert_eq(date.add(@moondate.Period::parse("P1M")).to_string(), "2024-02-29")
///     assert_eq(date.add(@moondate.Period::parse("PT36H")).to_string(), "2024-02-01")
pub fn Date::add(self : Date, period : Period) -> Date raise Refused {
  checked(period)
  if period.has_mixed_sign() {
    raise Malformed("the fields of the period do not run the same way")
  }
  let (carried, _) = truncated(landing_of_clock(period))
  shifted(
    self,
    period.years * 12L + period.months,
    period.weeks * 7L + period.days + carried,
  )
}

///|
/// A period taken away from a date.
///
/// The subtraction is the addition of every field negated, which is not the same
/// as taking away the number of days the period happens to be: a month back from
/// the thirty-first of March is the twenty-ninth of February, and thirty-one days
/// back is the twenty-ninth of February only in a leap year.
pub fn Date::subtract(self : Date, period : Period) -> Date raise Refused {
  self.add(period.neg())
}
