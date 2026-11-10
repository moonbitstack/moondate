// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A period is a length a calendar adds rather than a count of nanoseconds, so
// what is checked here is that it keeps the fields it was given, writes them the
// way ISO 8601 does, and rounds a number the way each of the nine modes says.

///|
test "period: a length keeps the fields it was given" {
  let period = @moondate.Period::new(
    years=1,
    months=2,
    days=3,
    hours=4,
    minutes=5,
    seconds=6,
    millis=7,
  )
  assert_eq(period.years, 1L)
  assert_eq(period.months, 2L)
  assert_eq(period.weeks, 0L)
  assert_eq(period.days, 3L)
  assert_eq(period.hours, 4L)
  assert_eq(period.nanos, 7_000_000L)
}

///|
test "period: twenty-five months stays twenty-five months" {
  let period = @moondate.Period::new(months=25)
  assert_eq(period.months, 25L)
  assert_eq(period.years, 0L)
}

///|
test "period: one unit at a time" {
  assert_eq(@moondate.Period::of(@moondate.Years, 2).years, 2L)
  assert_eq(@moondate.Period::of(@moondate.Weeks, 3).weeks, 3L)
  assert_eq(@moondate.Period::of(@moondate.Millis, 7).nanos, 7_000_000L)
  assert_eq(@moondate.Period::of(@moondate.Micros, 7).nanos, 7_000L)
  assert_eq(@moondate.Period::of(@moondate.Nanos, 7).nanos, 7L)
}

///|
test "period: an empty period is empty, and the sign is the largest field's" {
  assert_eq(@moondate.zero.is_zero(), true)
  assert_eq(@moondate.Period::new(days=1).is_zero(), false)
  assert_eq(@moondate.Period::new(years=-1).sign(), -1)
  assert_eq(@moondate.Period::new(years=1, days=-2).sign(), 1)
  assert_eq(@moondate.Period::new(years=1, days=-2).has_mixed_sign(), true)
  assert_eq(@moondate.Period::new(years=1, days=2).has_mixed_sign(), false)
}

///|
test "period: the clock part is a span and the date part is not" {
  let period = @moondate.Period::new(days=1, hours=2)
  assert_eq(period.span().nanos, 7_200_000_000_000L)
  assert_eq(period.has_date(), true)
  assert_eq(@moondate.Period::new(hours=2).has_date(), false)
  assert_eq(@moondate.Period::new(hours=2).neg().hours, -2L)
  assert_eq(
    @moondate.Period::new(days=1).add(@moondate.Period::new(days=2)).days,
    3L,
  )
}

///|
test "period: written the way ISO 8601 writes a duration" {
  assert_eq(@moondate.zero.to_string(), "PT0S")
  assert_eq(
    @moondate.Period::new(years=1, months=2, days=3).to_string(),
    "P1Y2M3D",
  )
  assert_eq(
    @moondate.Period::new(hours=4, minutes=5, seconds=6, millis=7).to_string(),
    "PT4H5M6.007S",
  )
  assert_eq(
    @moondate.Period::new(hours=376435, minutes=23).to_string(),
    "PT376435H23M",
  )
  assert_eq(@moondate.Period::new(days=-1).to_string(), "-P1D")
  assert_eq(@moondate.Period::new(weeks=40).to_string(), "P40W")
}

///|
test "rounding: a value moved to the nearest multiple" {
  // Positive values: the direction words mean what they say.
  assert_eq(@moondate.round_increment(7L, 5L, @moondate.Ceil), 10L)
  assert_eq(@moondate.round_increment(7L, 5L, @moondate.Floor), 5L)
  assert_eq(@moondate.round_increment(7L, 5L, @moondate.Trunc), 5L)
  assert_eq(@moondate.round_increment(7L, 5L, @moondate.Expand), 10L)
  assert_eq(@moondate.round_increment(7L, 5L, @moondate.HalfExpand), 5L)
  assert_eq(@moondate.round_increment(8L, 5L, @moondate.HalfExpand), 10L)
  // Exactly half: the four halves disagree on purpose.
  assert_eq(@moondate.round_increment(5L, 10L, @moondate.HalfEven), 0L)
  assert_eq(@moondate.round_increment(15L, 10L, @moondate.HalfEven), 20L)
  assert_eq(@moondate.round_increment(5L, 10L, @moondate.HalfCeil), 10L)
  assert_eq(@moondate.round_increment(5L, 10L, @moondate.HalfFloor), 0L)
  assert_eq(@moondate.round_increment(5L, 10L, @moondate.HalfTrunc), 0L)
  // Negative values: ceil is towards positive infinity, expand is away from
  // @moondate.zero, and the two are not the same word.
  assert_eq(@moondate.round_increment(-7L, 5L, @moondate.Ceil), -5L)
  assert_eq(@moondate.round_increment(-7L, 5L, @moondate.Floor), -10L)
  assert_eq(@moondate.round_increment(-7L, 5L, @moondate.Expand), -10L)
  assert_eq(@moondate.round_increment(-7L, 5L, @moondate.Trunc), -5L)
  assert_eq(@moondate.round_increment(-5L, 10L, @moondate.HalfEven), 0L)
  assert_eq(@moondate.round_increment(-15L, 10L, @moondate.HalfEven), -20L)
  // Nothing to move.
  assert_eq(@moondate.round_increment(10L, 5L, @moondate.Ceil), 10L)
  assert_eq(@moondate.round_increment(7L, 1L, @moondate.Ceil), 7L)
}

///|
test "unit: which units have a length of their own" {
  assert_eq(@moondate.TimeUnit::@moondate.Years.nanos() is None, true)
  assert_eq(@moondate.TimeUnit::@moondate.Days.nanos() is None, true)
  assert_eq(
    @moondate.TimeUnit::@moondate.Hours.nanos(),
    Some(3_600_000_000_000L),
  )
  assert_eq(@moondate.TimeUnit::@moondate.Nanos.nanos(), Some(1L))
  assert_eq(@moondate.TimeUnit::@moondate.Weeks.is_exact(), false)
  assert_eq(@moondate.TimeUnit::@moondate.Millis.is_exact(), true)
}
