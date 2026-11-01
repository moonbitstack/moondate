// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The parts of the ECMAScript/Temporal ISO shapes Node's Date cannot reach: a
// nanosecond value finer than a millisecond, and a non-UTC offset. The UTC
// millisecond cases live in the generated src/ecma_vectors_test.mbt.

///|
test "isoformat truncates nanoseconds and writes the offset" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456789),
    zone=@moondate.Offset(480),
  )
  assert_eq(m.isoformat(), "2026-09-22T14:30:05.123456789+08:00")
  assert_eq(m.isoformat(fraction=0), "2026-09-22T14:30:05+08:00")
  assert_eq(m.isoformat(fraction=3), "2026-09-22T14:30:05.123+08:00")
  assert_eq(m.isoformat(fraction=9), "2026-09-22T14:30:05.123456789+08:00")
  assert_eq(m.isoformat(fraction=6, offset=false), "2026-09-22T14:30:05.123456")
}

///|
test "to_iso_string and to_utc_string convert an offset moment to UTC" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456000),
    zone=@moondate.Offset(480),
  )
  assert_eq(m.to_iso_string(), "2026-09-22T06:30:05.123Z")
  assert_eq(m.to_utc_string(), "Tue, 22 Sep 2026 06:30:05 GMT")
}
