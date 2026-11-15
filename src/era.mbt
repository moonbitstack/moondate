// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The era a calendar names a year in.

///|
/// The era the calendar names this year in: `None`, because this calendar has
/// none.
///
/// The library reads one calendar — the proleptic Gregorian, in the ISO 8601
/// reading every interchange format here uses — and that calendar counts years
/// from 1 and writes the ones before it with a sign: year 0 is 1 BC, year -1 is
/// 2 BC, and a second name for either would say nothing the year does not. A
/// calendar whose years are named twice — the Gregorian era beside a Japanese
/// one, a Buddhist year, a regnal year — is a table of eras with a start date
/// each, which is a database and not a rule, and no such table is carried here.
///
///     assert_eq(@moondate.Date::new(2026, 9, 22).era(), None)
pub fn Date::era(self : Date) -> String? {
  let _ = self
  None
}

///|
/// The year counted inside the era: `None`, for the reason [`Date::era`] gives.
///
/// The year itself is the `year` field, which is signed and needs no era to be
/// unambiguous.
pub fn Date::era_year(self : Date) -> Int32? {
  let _ = self
  None
}
