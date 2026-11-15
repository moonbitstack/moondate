// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a period added to a date" {
  let date = @moondate.Date::new(2024, 1, 31)
  assert_eq(date.add(@moondate.Period::parse("P1M")).to_string(), "2024-02-29")
  assert_eq(date.add(@moondate.Period::parse("P1Y")).to_string(), "2025-01-31")
  assert_eq(
    date.add(@moondate.Period::parse("P2W3D")).to_string(),
    "2024-02-17",
  )
}

///|
test "a clock part added to a date is carried in whole days" {
  let date = @moondate.Date::new(2024, 1, 31)
  assert_eq(
    date.add(@moondate.Period::parse("PT12H")).to_string(),
    "2024-01-31",
  )
  assert_eq(
    date.add(@moondate.Period::parse("PT36H")).to_string(),
    "2024-02-01",
  )
  assert_eq(
    date.add(@moondate.Period::parse("-PT36H")).to_string(),
    "2024-01-30",
  )
}

///|
test "a period taken from a date" {
  let date = @moondate.Date::new(2024, 3, 31)
  assert_eq(
    date.subtract(@moondate.Period::parse("P1M")).to_string(),
    "2024-02-29",
  )
  assert_eq(
    date.subtract(@moondate.Period::parse("P31D")).to_string(),
    "2024-02-29",
  )
  assert_eq(
    date.subtract(@moondate.Period::parse("P32D")).to_string(),
    "2024-02-28",
  )
}

///|
test "a period whose fields disagree is refused by a date" {
  let date = @moondate.Date::new(2024, 1, 1)
  let mixed : Result[@moondate.Date, @moondate.Refused] = Ok(
    date.add(@moondate.Period::new(months=1, days=-1L)),
  ) catch {
    e => Err(e)
  }
  assert_eq(mixed is Err(_), true)
}

///|
test "a move past the years a date names is refused" {
  let date = @moondate.Date::new(2024, 1, 1)
  let far : Result[@moondate.Date, @moondate.Refused] = Ok(
    date.add(@moondate.Period::parse("P4294967295Y")),
  ) catch {
    e => Err(e)
  }
  assert_eq(far is Err(_), true)
}
