// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The LDML pattern language, read back: what `pattern` writes, `parse_pattern`
// must return as the same moment.

///|
test "pattern round-trips an ISO-style timestamp with an offset and a fraction" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123000000),
    zone=@moondate.Offset(480),
  )
  let p = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX"
  assert_eq(@moondate.parse_pattern(m.pattern(p), p), m)
}

///|
test "pattern round-trips a wall clock through a date-time pattern" {
  let m = @moondate.Moment::Plain(
    date=@moondate.Date::new(1999, 1, 5),
    time=@moondate.Time::new(3, 4, second=7),
  )
  let p = "yyyy-MM-dd HH:mm:ss"
  assert_eq(@moondate.parse_pattern(m.pattern(p), p), m)
}

///|
test "pattern round-trips a bare date through a long named pattern" {
  let m = @moondate.Moment::Day(date=@moondate.Date::new(2026, 9, 22))
  let p = "EEEE, MMMM d, yyyy"
  assert_eq(@moondate.parse_pattern(m.pattern(p), p), m)
}

///|
test "pattern round-trips a bare time through a twelve-hour pattern" {
  let m = @moondate.Moment::Clock(time=@moondate.Time::new(14, 30))
  let p = "h:mm a"
  assert_eq(@moondate.parse_pattern(m.pattern(p), p), m)
}

///|
test "pattern round-trips a bare time with seconds" {
  let m = @moondate.Moment::Clock(time=@moondate.Time::new(23, 59, second=59))
  let p = "HH:mm:ss"
  assert_eq(@moondate.parse_pattern(m.pattern(p), p), m)
}
