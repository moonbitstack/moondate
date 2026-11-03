// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The layout tokens that are easy to mistake for something else: a day of the
// year next to a dot, the space-padded day of the year, the underscore that is a
// literal rather than a pad, a comma before the fraction, and a zone with seconds.
// The expected strings are Go 1.25's own `time.Format`.

///|
fn token_moment() -> @moondate.Moment raise @moondate.Refused {
  @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456789),
    zone=@moondate.Offset(480),
  )
}

///|
test "a day of the year after a dot" {
  // `.002` is not a fraction of a second: Go only reads a fraction when the run of
  // digits after the dot is the last one there, so this stays a day of the year.
  assert_eq(token_moment().layout("2006.002"), "2026.265")
  let early = @moondate.Moment::Zoned(
    date=@moondate.Date::new(1999, 1, 5),
    time=@moondate.Time::new(3, 4, second=7),
    zone=@moondate.Utc,
  )
  assert_eq(early.layout("2006.002"), "1999.005")
}

///|
test "the space-padded day of the year" {
  assert_eq(token_moment().layout("__2"), "265")
  let early = @moondate.Moment::Zoned(
    date=@moondate.Date::new(1999, 1, 5),
    time=@moondate.Time::new(3, 4, second=7),
    zone=@moondate.Utc,
  )
  assert_eq(early.layout("__2"), "  5")
  assert_eq(early.layout("__2 2006"), "  5 1999")
}

///|
test "an underscore before a year is a literal" {
  // `_2006` is a space and a four-digit year, not a padded day followed by a `6`.
  assert_eq(token_moment().layout("_2006"), "_2026")
}

///|
test "a comma introduces the fraction" {
  assert_eq(token_moment().layout("15:04:05,000"), "14:30:05,123")
  assert_eq(token_moment().layout("15:04:05,999"), "14:30:05,123")
}

///|
test "a zone with seconds" {
  assert_eq(token_moment().layout("Z07:00:00"), "+08:00:00")
  assert_eq(token_moment().layout("Z070000"), "+080000")
  assert_eq(token_moment().layout("-07:00:00"), "+08:00:00")
}

///|
test "the tokens read back" {
  let m = @moondate.parse_layout("2026.265", "2006.002")
  assert_eq(m.isoformat(), "2026-09-22")
  let padded = @moondate.parse_layout("  5 1999", "__2 2006")
  assert_eq(padded.isoformat(), "1999-01-05")
  let frac = @moondate.parse_layout("14:30:05,123", "15:04:05,000")
  assert_eq(frac.isoformat(), "14:30:05.123")
  let zoned = @moondate.parse_layout(
    "2026-09-22T14:30:05+08:00:00", "2006-01-02T15:04:05Z07:00:00",
  )
  assert_eq(zoned.isoformat(), "2026-09-22T14:30:05+08:00")
}
