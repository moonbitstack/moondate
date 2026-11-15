// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The era a zoned date and time is named in.

///|
/// The era the calendar names this year in: `None`, because this calendar has
/// none. [`@moondate.Date::era`](moonbitstack/moondate) says why.
pub fn ZonedDateTime::era(self : ZonedDateTime) -> String? {
  let _ = self
  None
}

///|
/// The year counted inside the era: `None`, for the reason
/// [`@moondate.Date::era`](moonbitstack/moondate) gives.
pub fn ZonedDateTime::era_year(self : ZonedDateTime) -> Int32? {
  let _ = self
  None
}
