// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// How far apart two dates are, in the units asked for.
///
/// From a week down the answer is a count of days. A month is not a number of
/// days, so from a month up the answer is the whole months that fit and what is
/// left over: January the thirty-first to February the twenty-eighth is
/// twenty-eight days, because a month that clamps its day is not a month the
/// other end agrees with.
///
///     let from = @moondate.Date::new(2024, 1, 31)
///     let to = @moondate.Date::new(2024, 3, 1)
///     assert_eq(from.until(to, largest_unit=@moondate.TimeUnit::Months).to_string(), "P1M1D")
///     assert_eq(from.until(to).to_string(), "P30D")
pub fn Date::until(
  self : Date,
  other : Date,
  largest_unit~ : TimeUnit = Days,
) -> Period {
  let days = other.days() - self.days()
  match largest_unit {
    Weeks => {
      let weeks = days / 7
      { ..zero, weeks: weeks.to_int64(), days: (days % 7).to_int64(), }
    }
    Days => { ..zero, days: days.to_int64(), }
    _ => {
      let mut months = other.year.to_int64() * 12L +
        other.month.to_int64() -
        (self.year.to_int64() * 12L + self.month.to_int64())
      if months != 0L {
        let travel = if months > 0L { 1L } else { -1L }
        // A day of the month that moved backwards means a whole month does not
        // fit; taking one back leaves the days to say the rest.
        if (other.day - self.day).to_int64() * travel < 0L {
          months = months - travel
        }
      }
      let anchor = self.plus_months(months.to_int())
      let rest = other.days() - anchor.days()
      let years = if largest_unit == Years { months / 12L } else { 0L }
      { ..zero, years, months: months - years * 12L, days: rest.to_int64(), }
    }
  }
}
