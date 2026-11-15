// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A length longer than a count of nanoseconds reaches: 292 years is where an
// `Int64` of nanoseconds runs out, and a duration is not bounded there.

///|
test "duration: a million years is built and written" {
  let length = @moondate.Period::parse("P1000000Y")
  assert_eq(length.years, 1_000_000L)
  assert_eq(length.to_string(), "P1000000Y")
  assert_eq(@moondate.Period::parse("-P1000000Y").to_string(), "-P1000000Y")
}

///|
test "duration: a million years added to a date" {
  let start = @moondate.Date::new(2024, 1, 1)
  let length = @moondate.Period::parse("P1000000Y")
  let landed = start.add(length)
  assert_eq(landed.to_string(), "1002024-01-01")
  assert_eq(landed.subtract(length).to_string(), "2024-01-01")
  // A month is applied to the day of the month it started on, which clamps to a
  // day the month has: the thirty-first of January plus a million months is the
  // thirty-first of January a million months later.
  let month_end = @moondate.Date::new(2024, 1, 31)
  assert_eq(
    month_end.add(@moondate.Period::parse("P12000000M")).to_string(),
    "1002024-01-31",
  )
}

///|
test "duration: a million years counted in days" {
  let start = @moondate.Date::new(2024, 1, 1)
  let length = @moondate.Period::parse("P1000000Y")
  assert_eq(length.total(unit=@moondate.TimeUnit::Days, start~), 365242500.0)
  assert_eq(length.total(unit=@moondate.TimeUnit::Hours, start~), 8765820000.0)
}

///|
test "duration: a million years rounded" {
  let start = @moondate.Date::new(2024, 1, 1)
  let length = @moondate.Period::parse("P1000000YT1.5S")
  let to_seconds = length.round(
    smallest_unit=@moondate.TimeUnit::Seconds,
    rounding=@moondate.Rounding::HalfExpand,
    start~,
  )
  assert_eq(to_seconds.to_string(), "P1000000YT2S")
  let to_days = length.round(
    smallest_unit=@moondate.TimeUnit::Days,
    rounding=@moondate.Rounding::HalfExpand,
    start~,
  )
  assert_eq(to_days.to_string(), "P1000000Y")
  let to_months = @moondate.Period::parse("P1000000Y").round(
    smallest_unit=@moondate.TimeUnit::Months,
    start~,
  )
  assert_eq(to_months.to_string(), "P1000000Y")
}

///|
test "duration: a million years compared" {
  let start = @moondate.Date::new(2024, 1, 1)
  let years = @moondate.Period::parse("P1000000Y")
  let days = @moondate.Period::parse("P365242500D")
  assert_eq(years.compare(days, start~), 0)
  assert_eq(days.compare(years, start~), 0)
  assert_eq(years.compare(@moondate.Period::parse("P365242501D"), start~), -1)
  // Two million years is longer than one, which a count of nanoseconds could not
  // have said at all.
  assert_eq(@moondate.Period::parse("P2000000Y").compare(years, start~), 1)
}

///|
test "duration: a length past the largest field is refused" {
  let refused = fn(text : String) -> Bool {
    let got : Result[@moondate.Period, @moondate.Refused] = Ok(
      @moondate.Period::parse(text),
    ) catch {
      e => Err(e)
    }
    got is Err(_)
  }
  // The calendar fields are bounded at 2^32 - 1 each, and the clock fields
  // together at 2^53 seconds.
  assert_eq(refused("P4294967295Y"), false)
  assert_eq(refused("P4294967296Y"), true)
  assert_eq(refused("P4294967296D"), false)
  assert_eq(refused("PT4294967296S"), false)
  assert_eq(refused("PT9007199254740992S"), true)
  // A length built by hand is measured the same way: the refusal is at the
  // measurement, so a field past the bound cannot be rounded or counted.
  let built = @moondate.Period::new(years=4_294_967_296L)
  let measured : Result[Double, @moondate.Refused] = Ok(
    built.total(unit=@moondate.TimeUnit::Years),
  ) catch {
    e => Err(e)
  }
  assert_eq(measured is Err(_), true)
}

///|
test "panic duration: a clock part longer than a span" {
  let length = @moondate.Period::new(hours=4_294_967_295L)
  let _ = length.span()
}
