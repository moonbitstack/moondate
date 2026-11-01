// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The directives neither the CPython nor the chrono oracle reaches: the quarter,
// the lower-case meridiem, and the glibc/chrono padding and case modifiers.

///|
test "%P is lower-case and %q names the quarter" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5),
    zone=@moondate.Utc,
  )
  assert_eq(m.strftime("%P"), "pm")
  assert_eq(m.strftime("%q"), "3")
  assert_eq(m.strftime("%^B"), "SEPTEMBER")
}

///|
test "the padding modifiers drop or change a field's width" {
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 5),
    time=@moondate.Time::new(4, 3, second=2),
    zone=@moondate.Utc,
  )
  assert_eq(m.strftime("%-d"), "5")
  assert_eq(m.strftime("%d"), "05")
  assert_eq(m.strftime("%_d"), " 5")
  assert_eq(m.strftime("%-H"), "4")
  assert_eq(m.strftime("%H"), "04")
}
