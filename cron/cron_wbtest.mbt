// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The moment an expression next fires after `from`, as text.
fn after(expr : String, from : String) -> String raise {
  let start = @moondate.parse(from[:])
  match parse(expr[:]).next(start) {
    Some(m) => m.to_string()
    None => "never"
  }
}

///|
test "the five-field form fires when crontab(5) says" {
  // Every minute.
  assert_eq(after("* * * * *", "2026-09-22T14:30:00Z"), "2026-09-22T14:31:00Z")
  // Every hour on the hour.
  assert_eq(after("0 * * * *", "2026-09-22T14:30:00Z"), "2026-09-22T15:00:00Z")
  // Midnight.
  assert_eq(after("0 0 * * *", "2026-09-22T14:30:00Z"), "2026-09-23T00:00:00Z")
  // A given minute of a given hour.
  assert_eq(after("30 3 * * *", "2026-09-22T14:30:00Z"), "2026-09-23T03:30:00Z")
  // The first of the month.
  assert_eq(after("0 0 1 * *", "2026-09-22T14:30:00Z"), "2026-10-01T00:00:00Z")
}

///|
test "a field takes a list, a range and a step" {
  assert_eq(
    after("0,30 * * * *", "2026-09-22T14:05:00Z"),
    "2026-09-22T14:30:00Z",
  )
  assert_eq(
    after("*/15 * * * *", "2026-09-22T14:05:00Z"),
    "2026-09-22T14:15:00Z",
  )
  assert_eq(
    after("0 9-17 * * *", "2026-09-22T20:00:00Z"),
    "2026-09-23T09:00:00Z",
  )
  assert_eq(
    after("0 0 */10 * *", "2026-09-22T14:30:00Z"),
    "2026-10-01T00:00:00Z",
  )
  // `n/step` runs from n to the end of the field, which every implementation
  // does even though crontab(5) documents only `a-b/n`.
  assert_eq(
    after("0 5/6 * * *", "2026-09-22T00:00:00Z"),
    "2026-09-22T05:00:00Z",
  )
  assert_eq(
    after("0 5/6 * * *", "2026-09-22T06:00:00Z"),
    "2026-09-22T11:00:00Z",
  )
}

///|
test "names work where numbers do, in either case" {
  assert_eq(parse("0 0 1 JAN *"), parse("0 0 1 1 *"))
  assert_eq(parse("0 0 * * MON"), parse("0 0 * * 1"))
  assert_eq(parse("0 0 * * mon-fri"), parse("0 0 * * 1-5"))
  assert_eq(parse("0 0 1 jan,jul *"), parse("0 0 1 1,7 *"))
}

///|
test "both 0 and 7 are Sunday, which crontab(5) says outright" {
  assert_eq(parse("0 0 * * 0"), parse("0 0 * * 7"))
  assert_eq(after("0 0 * * 0", "2026-09-22T14:30:00Z"), "2026-09-27T00:00:00Z")
  assert_eq(after("0 0 * * 7", "2026-09-22T14:30:00Z"), "2026-09-27T00:00:00Z")
}

///|
test "day-of-month and day-of-week are or-ed when both are restricted" {
  // Vixie cron's rule, which surprises everyone once: the thirteenth **or** any
  // Friday, not Friday the thirteenth.
  let both = parse("0 0 13 * 5")
  // 2026-09-25 is a Friday and not the thirteenth.
  assert_eq(both.matches(@moondate.parse("2026-09-25T00:00:00Z")), true)
  // 2026-10-13 is the thirteenth and a Tuesday.
  assert_eq(both.matches(@moondate.parse("2026-10-13T00:00:00Z")), true)
  // With one of them unrestricted they are and-ed, so only the thirteenth counts.
  let day_only = parse("0 0 13 * *")
  assert_eq(day_only.matches(@moondate.parse("2026-09-25T00:00:00Z")), false)
  assert_eq(day_only.matches(@moondate.parse("2026-10-13T00:00:00Z")), true)
}

///|
test "the six-field form puts seconds in front" {
  assert_eq(
    after("30 * * * * *", "2026-09-22T14:30:00Z"),
    "2026-09-22T14:30:30Z",
  )
  assert_eq(
    after("*/30 * * * * *", "2026-09-22T14:30:05Z"),
    "2026-09-22T14:30:30Z",
  )
  // The five-field form fires on the zeroth second, not on every second.
  assert_eq(after("* * * * *", "2026-09-22T14:30:30Z"), "2026-09-22T14:31:00Z")
}

///|
test "the shorthands are the ones crontab(5) lists" {
  assert_eq(parse("@hourly"), parse("0 * * * *"))
  assert_eq(parse("@daily"), parse("0 0 * * *"))
  assert_eq(parse("@midnight"), parse("0 0 * * *"))
  assert_eq(parse("@weekly"), parse("0 0 * * 0"))
  assert_eq(parse("@monthly"), parse("0 0 1 * *"))
  assert_eq(parse("@yearly"), parse("0 0 1 1 *"))
  assert_eq(parse("@annually"), parse("0 0 1 1 *"))
}

///|
test "a question mark reads as a star, which is what Quartz writes" {
  assert_eq(parse("0 0 ? * MON"), parse("0 0 * * MON"))
  assert_eq(parse("0 0 13 * ?"), parse("0 0 13 * *"))
}

///|
test "an expression that names no day never fires" {
  // There is no thirtieth of February, so the search runs out rather than looping.
  assert_eq(after("0 0 30 2 *", "2026-09-22T14:30:00Z"), "never")
}

///|
test "a leap day is found, and only in a leap year" {
  assert_eq(after("0 0 29 2 *", "2026-09-22T14:30:00Z"), "2028-02-29T00:00:00Z")
}

///|
test "an expression that is not one is refused" {
  for
    bad in [
      "* * * *", "* * * * * * *", "60 * * * *", "* 24 * * *", "* * 32 * *", "* * * 13 *",
      "* * * * 8", "*/0 * * * *", "5-1 * * * *", "x * * * *", "",
    ] {
    assert_eq(refused(bad), true)
  }
}

///|
test "matching ignores a fraction of a second, because a schedule fires on the clock" {
  let every = parse("* * * * *")
  let on = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, nano=500_000_000),
    zone=Utc,
  )
  // The fraction does not stop it matching the minute…
  assert_eq(every.matches(on), true)
  // …and the next firing is on a whole second.
  match every.next(on) {
    Some(m) => assert_eq(m.to_string(), "2026-09-22T14:31:00Z")
    None => fail("every minute fires")
  }
}

///|
fn refused(expr : String) -> Bool {
  try {
    let _ = parse(expr[:])
    false
  } catch {
    _ => true
  }
}
