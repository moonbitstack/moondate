// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The expanded year the ECMAScript Date Time String Format and Temporal write for
// anything outside 0000 to 9999: a sign and six digits. The expected strings are
// Node 22's `Date.prototype.toISOString`.

///|
fn far_zoned(y : Int32) -> @moondate.Moment raise @moondate.Refused {
  @moondate.Moment::Zoned(
    date=@moondate.Date::new(y, 1, 2),
    time=@moondate.Time::new(3, 4, second=5),
    zone=@moondate.Utc,
  )
}

///|
test "an expanded year in the Date shape" {
  assert_eq(far_zoned(12026).to_iso_string(), "+012026-01-02T03:04:05.000Z")
  assert_eq(far_zoned(-1).to_iso_string(), "-000001-01-02T03:04:05.000Z")
  // Four digits stay four digits, at both ends of the range.
  assert_eq(far_zoned(9999).to_iso_string(), "9999-01-02T03:04:05.000Z")
  assert_eq(far_zoned(0).to_iso_string(), "0000-01-02T03:04:05.000Z")
}

///|
test "an expanded year in the Temporal shape" {
  assert_eq(
    far_zoned(12026).isoformat(fraction=9),
    "+012026-01-02T03:04:05.000000000Z",
  )
  assert_eq(
    far_zoned(-1).isoformat(fraction=9),
    "-000001-01-02T03:04:05.000000000Z",
  )
  assert_eq(far_zoned(12026).isoformat(), "+012026-01-02T03:04:05Z")
  assert_eq(far_zoned(-1).isoformat(), "-000001-01-02T03:04:05Z")
}

///|
test "an expanded year reads back" {
  assert_eq(
    @moondate.parse("+012026-01-02T03:04:05Z").isoformat(fraction=9),
    "+012026-01-02T03:04:05.000000000Z",
  )
  assert_eq(@moondate.parse("-000001-01-02").isoformat(), "-000001-01-02")
  assert_eq(
    @moondate.parse("+012026-01-02T03:04:05+08:00").isoformat(),
    "+012026-01-02T03:04:05+08:00",
  )
  // The four-digit form is unchanged.
  assert_eq(
    @moondate.parse("2026-09-22T14:30:05Z").isoformat(),
    "2026-09-22T14:30:05Z",
  )
}
