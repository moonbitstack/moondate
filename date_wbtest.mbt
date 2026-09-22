// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "the calendar's leap rule is the one that makes a year 365.2425 days" {
  assert_eq(leap(2024), true)
  assert_eq(leap(2023), false)
  // Every hundredth is not, except every four-hundredth — the two cases a
  // hand-rolled `year % 4` gets wrong.
  assert_eq(leap(1900), false)
  assert_eq(leap(2000), true)
  assert_eq(length(2024, 2), 29)
  assert_eq(length(1900, 2), 28)
  assert_eq(length(2023, 4), 30)
  assert_eq(length(2023, 12), 31)
}

///|
test "a date that the calendar does not have is refused" {
  assert_eq(refused(() => Date::new(2023, 2, 29)), true)
  assert_eq(refused(() => Date::new(2023, 13, 1)), true)
  assert_eq(refused(() => Date::new(2023, 4, 31)), true)
  assert_eq(refused(() => Date::new(2023, 1, 0)), true)
  // And the twenty-ninth exists in a leap year.
  assert_eq(Date::new(2024, 2, 29).to_string(), "2024-02-29")
}

///|
test "days and dates are inverses across the epoch and the centuries" {
  // The day the epoch counts from, and the day before it.
  assert_eq(Date::new(1970, 1, 1).days(), 0)
  assert_eq(Date::new(1969, 12, 31).days(), -1)
  // A value every reference prints.
  assert_eq(Date::new(2000, 1, 1).days(), 10957)
  assert_eq(Date::new(2024, 2, 29).days(), 19782)
  for n in [-800000, -719162, -1, 0, 1, 19782, 100000, 2932896] {
    assert_eq(Date::of_days(n).days(), n)
  }
}

///|
test "the weekday is the one a calendar on the wall shows" {
  // 1970-01-01 was a Thursday, which is where the offset comes from.
  assert_eq(Date::new(1970, 1, 1).weekday(), 4)
  assert_eq(Date::new(2026, 9, 22).weekday(), 2)
  assert_eq(Date::new(2000, 1, 1).weekday(), 6)
  // Before the epoch the modulo has to be corrected, which is the case a naive
  // `%` gets wrong.
  assert_eq(Date::new(1969, 12, 31).weekday(), 3)
  assert_eq(Date::new(1900, 1, 1).weekday(), 1)
  // ISO counts from Monday as 1, so a Sunday is 7 rather than 0.
  assert_eq(Date::new(2026, 9, 20).weekday(), 0)
  assert_eq(Date::new(2026, 9, 20).isoweekday(), 7)
}

///|
test "the day of the year counts the leap day" {
  assert_eq(Date::new(2024, 1, 1).yearday(), 1)
  assert_eq(Date::new(2024, 3, 1).yearday(), 61)
  assert_eq(Date::new(2023, 3, 1).yearday(), 60)
  assert_eq(Date::new(2024, 12, 31).yearday(), 366)
  assert_eq(Date::new(2023, 12, 31).yearday(), 365)
}

///|
test "adding a month lands on a day the month has" {
  // The thirty-first of January plus one month is the end of February, because
  // there is no thirty-first of it.
  assert_eq(Date::new(2023, 1, 31).plus_months(1).to_string(), "2023-02-28")
  assert_eq(Date::new(2024, 1, 31).plus_months(1).to_string(), "2024-02-29")
  assert_eq(Date::new(2023, 1, 31).plus_months(12).to_string(), "2024-01-31")
  // And going backwards across a year boundary.
  assert_eq(Date::new(2023, 1, 15).plus_months(-1).to_string(), "2022-12-15")
  assert_eq(Date::new(2023, 3, 31).plus_months(-1).to_string(), "2023-02-28")
}

///|
test "the ISO week date puts the turn of the year in the right week" {
  // 2026-01-01 is a Thursday, so it is in week one of 2026.
  assert_eq(Date::new(2026, 1, 1).isocalendar(), (2026, 1, 4))
  // 2021-01-01 is a Friday, so it belongs to the last week of 2020.
  assert_eq(Date::new(2021, 1, 1).isocalendar(), (2020, 53, 5))
  // And 2019-12-30 is a Monday already in week one of 2020.
  assert_eq(Date::new(2019, 12, 30).isocalendar(), (2020, 1, 1))
  // Which reads back.
  for
    d in [
      Date::new(2026, 1, 1),
      Date::new(2021, 1, 1),
      Date::new(2019, 12, 30),
      Date::new(2024, 6, 15),
    ] {
    let (y, w, wd) = d.isocalendar()
    assert_eq(Date::of_isocalendar(y, w, wd), d)
  }
}

///|
test "the ordinal is Python's, counting 0001-01-01 as one" {
  assert_eq(Date::new(1, 1, 1).ordinal(), 1)
  assert_eq(Date::new(1970, 1, 1).ordinal(), 719163)
  assert_eq(Date::new(2026, 9, 22).ordinal(), 739881)
  for n in [1, 719163, 739881, 3652059] {
    assert_eq(Date::of_ordinal(n).ordinal(), n)
  }
}

///|
test "a time the clock does not show is refused, but a leap second is not" {
  assert_eq(refused_time(() => Time::new(24, 0)), true)
  assert_eq(refused_time(() => Time::new(0, 60)), true)
  assert_eq(refused_time(() => Time::new(0, 0, second=61)), true)
  // RFC 3339 §5.6 allows a second of 60, and a timestamp that records one is a
  // real reading of a real clock.
  assert_eq(Time::new(23, 59, second=60).to_string(), "23:59:60")
}

///|
test "a span is nanoseconds, and its parts are Python's three fields" {
  assert_eq(Span::of(day, 1L).nanos, 86_400_000_000_000L)
  assert_eq(Span::new(days=1L, hours=2L, minutes=3L).parts(), (1, 7380, 0))
  assert_eq(Span::new(seconds=90L).total_seconds(), 90.0)
  assert_eq(Span::new(millis=1500L).total_seconds(), 1.5)
  // A negative span normalises the way Python's does: whole days down, the rest
  // positive.
  assert_eq(Span::new(seconds=-1L).parts(), (-1, 86399, 0))
  assert_eq(Span::new(seconds=-1L).neg().parts(), (0, 1, 0))
  assert_eq(Span::new(seconds=-1L).abs().total_seconds(), 1.0)
}

///|
test "arithmetic carries across midnight in both directions" {
  let m = Plain(date=Date::new(2026, 9, 22), time=Time::new(23, 30))
  assert_eq(m.plus(Span::of(hour, 1L)).to_string(), "2026-09-23T00:30:00")
  assert_eq(m.plus(Span::of(hour, -24L)).to_string(), "2026-09-21T23:30:00")
  // A bare time wraps within the day rather than growing a date.
  let c = Clock(time=Time::new(23, 30))
  assert_eq(c.plus(Span::of(hour, 1L)).to_string(), "00:30:00")
  assert_eq(c.plus(Span::of(hour, -24L)).to_string(), "23:30:00")
  // A bare date moves by whole days.
  let d = Day(date=Date::new(2026, 9, 22))
  assert_eq(d.plus(Span::of(day, 10L)).to_string(), "2026-10-02")
}

///|
test "an instant is seconds since the epoch, both ways" {
  let m = Zoned(date=Date::new(2026, 9, 22), time=Time::new(14, 30), zone=Utc)
  assert_eq(m.epoch(), Some(1790087400L))
  assert_eq(Moment::of_epoch(1790087400L), m)
  // An offset is taken off to get to UTC, so the same instant written in two
  // zones has the same epoch.
  let east = Zoned(
    date=Date::new(2026, 9, 22),
    time=Time::new(22, 30),
    zone=Offset(480),
  )
  assert_eq(east.epoch(), Some(1790087400L))
  // And the three shapes that are not instants say so.
  assert_eq(
    Plain(date=Date::new(2026, 9, 22), time=Time::new(14, 30)).epoch(),
    None,
  )
  assert_eq(Day(date=Date::new(2026, 9, 22)).epoch(), None)
  assert_eq(Clock(time=Time::new(14, 30)).epoch(), None)
}

///|
test "the same instant reads in another zone" {
  let m = Zoned(date=Date::new(2026, 9, 22), time=Time::new(14, 30), zone=Utc)
  guard m.astimezone(Offset(480)) is Some(east) else {
    fail("an instant can be read anywhere")
  }
  assert_eq(east.to_string(), "2026-09-22T22:30:00+08:00")
  assert_eq(east.epoch(), m.epoch())
  // A wall clock cannot be moved, because nobody said which zone it was written in.
  assert_eq(
    Plain(date=Date::new(2026, 9, 22), time=Time::new(14, 30)).astimezone(Utc),
    None,
  )
}

///|
/// Whether a date constructor refused.
fn refused(f : () -> Date raise Refused) -> Bool {
  try {
    let _ = f()
    false
  } catch {
    _ => true
  }
}

///|
/// Whether a time constructor refused.
fn refused_time(f : () -> Time raise Refused) -> Bool {
  try {
    let _ = f()
    false
  } catch {
    _ => true
  }
}
