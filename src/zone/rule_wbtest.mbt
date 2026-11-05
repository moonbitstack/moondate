// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// POSIX TZ strings: the little language a TZif footer is written in, and the one
// a caller reaches for when there is no file at all.

///|
test "a rule with two changes, as New York writes it" {
  let rule = Rule::parse("EST5EDT,M3.2.0,M11.1.0")
  assert_eq(rule.std_offset, -18000)
  assert_eq(rule.std_abbrev, "EST")
  assert_eq(rule.dst_offset, Some(-14400))
  assert_eq(rule.dst_abbrev, "EDT")
  assert_eq(
    rule.dst_start,
    Some({ onset: MonthWeekDay(month=3, week=2, weekday=0), seconds: 7200, }),
  )
  assert_eq(
    rule.dst_end,
    Some({ onset: MonthWeekDay(month=11, week=1, weekday=0), seconds: 7200, }),
  )
  // January is standard time and July is not.
  assert_eq(rule.at(1768478400L).offset, -18000)
  assert_eq(rule.at(1768478400L).abbrev, "EST")
  assert_eq(rule.at(1768478400L).is_dst, false)
  assert_eq(rule.at(1784116800L).offset, -14400)
  assert_eq(rule.at(1784116800L).abbrev, "EDT")
  assert_eq(rule.at(1784116800L).is_dst, true)
  // 2026-03-08T07:00Z is the second Sunday of March at two in the morning, and
  // the second before it is still standard time.
  assert_eq(rule.at(1772953199L).offset, -18000)
  assert_eq(rule.at(1772953200L).offset, -14400)
}

///|
test "a fixed offset, written with angle brackets" {
  let rule = Rule::parse("<+0545>-5:45")
  assert_eq(rule.std_offset, 20700)
  assert_eq(rule.std_abbrev, "+0545")
  assert_eq(rule.dst_offset, None)
  assert_eq(rule.at(0L).offset, 20700)
  assert_eq(rule.at(0L).is_dst, false)
}

///|
test "the two onsets that count days of the year" {
  let julian = Rule::parse("AAA3BBB,J60/2,J300/2")
  assert_eq(julian.dst_start, Some({ onset: Julian(n=60), seconds: 7200, }))
  let days = Rule::parse("AAA3BBB,100,200")
  assert_eq(days.dst_start, Some({ onset: Days(n=100), seconds: 7200, }))
}

///|
test "a time of day that is not two in the morning" {
  let rule = Rule::parse("AAA3BBB,M3.2.0/1:30,M10.1.0/0")
  assert_eq(
    rule.dst_start,
    Some({ onset: MonthWeekDay(month=3, week=2, weekday=0), seconds: 5400, }),
  )
  assert_eq(
    rule.dst_end,
    Some({ onset: MonthWeekDay(month=10, week=1, weekday=0), seconds: 0, }),
  )
}

///|
test "a rule written back" {
  for
    text in [
      "EST5EDT,M3.2.0,M11.1.0", "UTC0", "<+0545>-5:45", "AAA3BBB,J60,J300", "AAA3BBB,100,200",
      "AAA3BBB,M3.2.0/1:30,M10.1.0/0",
    ] {
    let rule = Rule::parse(text)
    assert_eq(rule.text(), text)
    assert_eq(Rule::parse(rule.text()), rule)
  }
}

///|
test "a rule that is not one" {
  for
    text in [
      "ES5", "EST", "EST5EDT,M3.2", "EST5EDT,M13.2.0,M11.1.0", "EST5EDT,,",
    ] {
    let outcome = try {
      let _ = Rule::parse(text)
      "read"
    } catch {
      Malformed(..) => "refused"
      _ => "another refusal"
    }
    assert_eq(outcome, "refused")
  }
}
