// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The LDML letters beyond the plain date and time fields: the day periods, the
// standalone weekday, the narrow era and quarter, and the week year. The expected
// strings are Babel 2.17's `format_datetime(locale="en")`, which follows UTS #35.

///|
fn letter_moment(
  y : Int32,
  m : Int32,
  d : Int32,
  h : Int32,
  mi : Int32,
) -> @moondate.Moment raise @moondate.Refused {
  @moondate.Moment::Zoned(
    date=@moondate.Date::new(y, m, d),
    time=@moondate.Time::new(h, mi),
    zone=@moondate.Utc,
  )
}

///|
test "the day period letters" {
  // `b` is the short form and `B` the long one; both name midnight and noon.
  let afternoon = letter_moment(2026, 9, 22, 14, 30)
  assert_eq(afternoon.pattern("b"), "afternoon")
  assert_eq(afternoon.pattern("bbb"), "afternoon")
  assert_eq(afternoon.pattern("B"), "in the afternoon")
  assert_eq(afternoon.pattern("BBBB"), "in the afternoon")
  assert_eq(afternoon.pattern("BBBBB"), "in the afternoon")
  let morning = letter_moment(2021, 1, 3, 9, 5)
  assert_eq(morning.pattern("b"), "morning")
  assert_eq(morning.pattern("B"), "in the morning")
  let night = letter_moment(1999, 1, 5, 3, 4)
  assert_eq(night.pattern("b"), "night")
  assert_eq(night.pattern("B"), "at night")
  // Midnight and noon have names of their own, and a narrow `B` shortens them.
  let midnight = letter_moment(2026, 1, 1, 0, 0)
  assert_eq(midnight.pattern("b"), "midnight")
  assert_eq(midnight.pattern("B"), "midnight")
  assert_eq(midnight.pattern("BBBBB"), "mi")
  let noon = letter_moment(2026, 6, 15, 12, 0)
  assert_eq(noon.pattern("B"), "noon")
  assert_eq(noon.pattern("BBBBB"), "n")
}

///|
test "the standalone weekday width" {
  // `c` is `e` for a locale whose standalone and format names are the same, which
  // English is: a number, a short name, then a long one.
  let tuesday = letter_moment(2026, 9, 22, 14, 30)
  assert_eq(tuesday.pattern("c"), "2")
  assert_eq(tuesday.pattern("ccc"), "Tue")
  assert_eq(tuesday.pattern("cccc"), "Tuesday")
  assert_eq(tuesday.pattern("ccccc"), "T")
  let sunday = letter_moment(2021, 1, 3, 9, 5)
  assert_eq(sunday.pattern("c"), "7")
  assert_eq(sunday.pattern("cccc"), "Sunday")
}

///|
test "the narrow era and quarter" {
  let m = letter_moment(2026, 9, 22, 14, 30)
  assert_eq(m.pattern("GGGG"), "Anno Domini")
  assert_eq(m.pattern("GGGGG"), "A")
  assert_eq(m.pattern("QQQQ"), "3rd quarter")
  assert_eq(m.pattern("QQQQQ"), "3")
}

///|
test "the week year and its week" {
  // A week starts on Monday and the first week is the one that holds 1 January.
  let late = letter_moment(2024, 12, 30, 0, 0)
  assert_eq(late.pattern("w"), "1")
  assert_eq(late.pattern("ww"), "01")
  assert_eq(late.pattern("Y"), "2025")
  assert_eq(late.pattern("YY"), "25")
  let early = letter_moment(1999, 1, 5, 3, 4)
  assert_eq(early.pattern("w"), "2")
  assert_eq(early.pattern("Y"), "1999")
  let middle = letter_moment(2026, 9, 22, 14, 30)
  assert_eq(middle.pattern("w"), "39")
  assert_eq(middle.pattern("Y"), "2026")
}

///|
test "the new letters read back" {
  // The day period the reader passes over, and the rest of the pattern still lands.
  let m = @moondate.parse_pattern(
    "Tuesday, in the afternoon 14:30", "cccc, B HH:mm",
  )
  assert_eq(m.isoformat(), "14:30:00")
  let standalone = @moondate.parse_pattern("2 09/2026", "c MM/yyyy")
  assert_eq(standalone.isoformat(), "2026-09-01")
}

///|
test "a day of the year and a week date read back" {
  let m = letter_moment(2026, 9, 22, 14, 30)
  assert_eq(m.pattern("yyyy-DDD"), "2026-265")
  assert_eq(
    @moondate.parse_pattern("2026-265", "yyyy-DDD").isoformat(),
    "2026-09-22",
  )
  assert_eq(m.pattern("Y-'W'ww-e"), "2026-W39-2")
  assert_eq(
    @moondate.parse_pattern("2026-W39-2", "Y-'W'ww-e").isoformat(),
    "2026-09-22",
  )
  // The first day of a week year, where the week number and the Tuesday meet on a
  // date in the year before the week year.
  assert_eq(
    @moondate.parse_pattern("2025-W01-1", "Y-'W'ww-e").isoformat(),
    "2024-12-30",
  )
}
