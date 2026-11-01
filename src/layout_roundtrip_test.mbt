// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The Go layout language, read back: what `layout` writes, `parse_layout` must
// return as the same moment. These are the round trips the task asks for, one per
// shape a layout can name.

///|
test "layout round-trips RFC3339 in UTC" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5),
    zone=@moondate.Utc,
  )
  assert_eq(
    @moondate.parse_layout(m.layout(@moondate.RFC3339), @moondate.RFC3339),
    m,
  )
}

///|
test "layout round-trips RFC3339Nano with an offset and a fraction" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456789),
    zone=@moondate.Offset(480),
  )
  let s = m.layout(@moondate.RFC3339Nano)
  assert_eq(@moondate.parse_layout(s, @moondate.RFC3339Nano), m)
}

///|
test "layout round-trips a wall clock through DateTime" {
  let m = @moondate.Moment::Plain(
    date=@moondate.Date::new(1999, 1, 5),
    time=@moondate.Time::new(3, 4, second=7),
  )
  assert_eq(
    @moondate.parse_layout(m.layout(@moondate.DateTime), @moondate.DateTime),
    m,
  )
}

///|
test "layout round-trips a bare date through DateOnly" {
  let m = @moondate.Moment::Day(date=@moondate.Date::new(2000, 2, 29))
  assert_eq(
    @moondate.parse_layout(m.layout(@moondate.DateOnly), @moondate.DateOnly),
    m,
  )
}

///|
test "layout round-trips a bare time through TimeOnly" {
  let m = @moondate.Moment::Clock(time=@moondate.Time::new(23, 59, second=59))
  assert_eq(
    @moondate.parse_layout(m.layout(@moondate.TimeOnly), @moondate.TimeOnly),
    m,
  )
}

///|
test "layout round-trips a twelve-hour clock with a meridiem" {
  let m = @moondate.Moment::Plain(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5),
  )
  let ly = "02/01/2006 03:04:05 PM"
  assert_eq(@moondate.parse_layout(m.layout(ly), ly), m)
}
