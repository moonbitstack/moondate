// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A rounding whose step fills the day: the candidates either side of a length are
// a whole number of steps apart, and the one above may land exactly on the next
// day. The carry there is the one a landing has to make, and the answers below
// are the reference implementation's.

///|
test "a rounding that fills the day carries into it" {
  let half = @moondate.Period::parse("PT23H30M")
  assert_eq(
    half
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::HalfExpand,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "P1D",
  )
  assert_eq(
    half
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::Ceil,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "P1D",
  )
  assert_eq(
    @moondate.Period::parse("-PT23H30M")
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::Expand,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "-P1D",
  )
  assert_eq(
    @moondate.Period::parse("PT23H59M59.5S")
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::HalfExpand,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "P1D",
  )
}

///|
test "a step below a day that fills it carries into the day above" {
  let start = @moondate.Date::new(2024, 1, 1)
  let length = @moondate.Period::parse("P1DT23H30M")
  assert_eq(
    length
    .round(
      smallest_unit=@moondate.TimeUnit::Hours,
      rounding=@moondate.Rounding::HalfExpand,
      start~,
    )
    .to_string(),
    "P2D",
  )
  assert_eq(
    length
    .round(
      smallest_unit=@moondate.TimeUnit::Hours,
      rounding=@moondate.Rounding::Ceil,
      start~,
    )
    .to_string(),
    "P2D",
  )
  assert_eq(
    @moondate.Period::parse("-P1DT23H30M")
    .round(
      smallest_unit=@moondate.TimeUnit::Hours,
      rounding=@moondate.Rounding::Expand,
      start~,
    )
    .to_string(),
    "-P2D",
  )
  assert_eq(
    @moondate.Period::parse("P1DT23H59M59.5S")
    .round(
      smallest_unit=@moondate.TimeUnit::Seconds,
      rounding=@moondate.Rounding::HalfExpand,
      start~,
    )
    .to_string(),
    "P2D",
  )
  assert_eq(
    @moondate.Period::parse("P2DT30M")
    .round(
      smallest_unit=@moondate.TimeUnit::Hours,
      rounding=@moondate.Rounding::HalfExpand,
      start~,
    )
    .to_string(),
    "P2DT1H",
  )
}

///|
test "a rounding that fills the day keeps the unit it was asked for" {
  // Rounded to hours, twenty-four of them are the answer: the day above is not a
  // unit the question named.
  assert_eq(
    @moondate.Period::parse("PT47H30M")
    .round(
      smallest_unit=@moondate.TimeUnit::Hours,
      rounding=@moondate.Rounding::HalfExpand,
    )
    .to_string(),
    "PT48H",
  )
}

///|
test "an exact half of a day is decided by the mode" {
  assert_eq(
    @moondate.Period::parse("PT12H")
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::HalfEven,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "PT0S",
  )
  assert_eq(
    @moondate.Period::parse("PT36H")
    .round(
      smallest_unit=@moondate.TimeUnit::Days,
      rounding=@moondate.Rounding::HalfEven,
      start=@moondate.Date::new(2024, 1, 1),
    )
    .to_string(),
    "P2D",
  )
}
