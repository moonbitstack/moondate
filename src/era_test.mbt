// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The calendar has no eras: a year is a signed number, and the ones before 1 are
// counted back from it.

///|
test "an era is what this calendar does not name" {
  let after = @moondate.Date::new(2026, 9, 22)
  assert_eq(after.era() is None, true)
  assert_eq(after.era_year() is None, true)
  // The years before 1 are told apart by the sign, which is why no era is needed:
  // year 0 is 1 BC and year -1 is 2 BC.
  assert_eq(@moondate.Date::new(0, 1, 1).to_string(), "0000-01-01")
  assert_eq(@moondate.Date::new(0, 1, 1).year, 0)
  assert_eq(@moondate.Date::new(0, 1, 1).era_year() is None, true)
}
