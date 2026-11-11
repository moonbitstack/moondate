// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A length read from a text, rounded, counted and compared. The answers the
// reference implementation gives to the same questions are replayed from
// `period_vectors_test.mbt`; these are the same questions written out, with the
// reason each answer is what it is.

///|
test "period: a length is read from its ISO 8601 text" {
  assert_eq(
    @moondate.Period::parse("P1Y2M3DT4H5M6.007S").to_string(),
    "P1Y2M3DT4H5M6.007S",
  )
  assert_eq(@moondate.Period::parse("P1W").to_string(), "P1W")
  assert_eq(@moondate.Period::parse("-P1D").to_string(), "-P1D")
  assert_eq(@moondate.Period::parse("P0D").to_string(), "PT0S")
}

///|
test "period: a fraction is the fields below the one it is written on" {
  // Half a day is twelve hours and half an hour is thirty minutes, which is the
  // only reading of a fraction that two calendars agree on.
  assert_eq(@moondate.Period::parse("P1.5D").to_string(), "P1DT12H")
  assert_eq(@moondate.Period::parse("-PT1.5H").to_string(), "-PT1H30M")
  assert_eq(
    @moondate.Period::parse("PT0.000000001S").to_string(),
    "PT0.000000001S",
  )
}

///|
test "period: a text that is not a length is refused" {
  let refused = fn(text : String) -> Bool {
    let answer : Result[@moondate.Period, @moondate.Refused] = Ok(
      @moondate.Period::parse(text),
    ) catch {
      _ => Err(@moondate.Refused::Malformed(""))
    }
    answer is Err(_)
  }
  // A fraction of a month is not a number of days, a duration names something,
  // and the unit of each field has to be one the grammar has.
  assert_eq(refused("P0.5M"), true)
  assert_eq(refused("P"), true)
  assert_eq(refused("P1X"), true)
  assert_eq(refused("1D"), true)
  assert_eq(refused("PT1.5H2M"), true)
}

///|
test "period: rounding a length to a month fills the year above it" {
  // One year, eleven months and twenty-four days counted from the first of
  // January is nearer two years than one, and a step up from eleven months is
  // twelve, which is a year.
  let from = @moondate.Date::new(2024, 1, 1)
  let length = @moondate.Period::parse("P1Y11M24D")
  assert_eq(
    length
    .round(
      smallest_unit=@moondate.TimeUnit::Months,
      rounding=@moondate.Rounding::Expand,
      start=from,
    )
    .to_string(),
    "P2Y",
  )
  // The default rounding is to the nearer month, so the same length asks to be
  // two years; asking for the part that fits gives the eleven months back.
  assert_eq(
    length
    .round(
      smallest_unit=@moondate.TimeUnit::Months,
      rounding=@moondate.Rounding::Trunc,
      start=from,
    )
    .to_string(),
    "P1Y11M",
  )
}

///|
test "period: a length in days is counted from the date it starts on" {
  // Eleven months from the first of February is the twenty-ninth of a leap year
  // and the twenty-eighth of any other, so the length is not a count of days
  // until the date says which.
  let length = @moondate.Period::parse("P11M")
  assert_eq(
    length.total(
      unit=@moondate.TimeUnit::Days,
      start=@moondate.Date::new(2024, 2, 1),
    ),
    335.0,
  )
  assert_eq(
    length.total(
      unit=@moondate.TimeUnit::Days,
      start=@moondate.Date::new(2023, 2, 1),
    ),
    334.0,
  )
  assert_eq(
    length.total(
      unit=@moondate.TimeUnit::Hours,
      start=@moondate.Date::new(2024, 2, 1),
    ),
    8040.0,
  )
}

///|
test "period: two lengths of a year are compared from a date" {
  let month = @moondate.Period::parse("P1M")
  let days = @moondate.Period::parse("P31D")
  // February is a short month, March a long one, and the same two lengths fall
  // either side of each other because of it.
  assert_eq(month.compare(days, start=@moondate.Date::new(2024, 2, 1)), -1)
  assert_eq(month.compare(days, start=@moondate.Date::new(2024, 3, 1)), 0)
  assert_eq(month.compare(days, start=@moondate.Date::new(2024, 4, 1)), -1)
  assert_eq(
    @moondate.Period::parse("PT1H").compare(@moondate.Period::parse("PT60M")),
    0,
  )
}

///|
test "period: a length with a calendar field needs the date it starts from" {
  let answer = fn() -> @moondate.Period raise @moondate.Refused {
    @moondate.Period::parse("P1Y").round(
      smallest_unit=@moondate.TimeUnit::Months,
    )
  }
  let refused : Result[@moondate.Period, @moondate.Refused] = Ok(answer()) catch {
    _ => Err(@moondate.Refused::Malformed(""))
  }
  assert_eq(refused is Err(_), true)
  // A length of hours does not: an hour is sixty minutes wherever it falls.
  assert_eq(
    @moondate.Period::parse("PT90M")
    .round(smallest_unit=@moondate.TimeUnit::Hours)
    .to_string(),
    "PT2H",
  )
}
