// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The `%` directive language, round-tripped: what `strftime` writes, `strptime`
// must return as the same moment. One case per shape a format can name.

///|
test "% round-trips a zoned moment through an offset format" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456789),
    zone=@moondate.Offset(480),
  )
  let f = "%Y-%m-%dT%H:%M:%S%.9f%:z"
  assert_eq(@moondate.strptime(m.strftime(f), f), m)
}

///|
test "% round-trips a zoned moment through the chrono %+ form" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=500000000),
    zone=@moondate.Offset(480),
  )
  assert_eq(@moondate.strptime(m.strftime("%+"), "%+"), m)
}

///|
test "% round-trips a wall clock" {
  let m = @moondate.Moment::Plain(
    date=@moondate.Date::new(1999, 1, 5),
    time=@moondate.Time::new(3, 4, second=7),
  )
  let f = "%Y-%m-%d %H:%M:%S"
  assert_eq(@moondate.strptime(m.strftime(f), f), m)
}

///|
test "% round-trips a bare date" {
  let m = @moondate.Moment::Day(date=@moondate.Date::new(2000, 2, 29))
  assert_eq(@moondate.strptime(m.strftime("%Y-%m-%d"), "%Y-%m-%d"), m)
}

///|
test "% round-trips a bare time" {
  let m = @moondate.Moment::Clock(time=@moondate.Time::new(23, 59, second=59))
  assert_eq(@moondate.strptime(m.strftime("%H:%M:%S"), "%H:%M:%S"), m)
}
