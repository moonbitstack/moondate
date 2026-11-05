// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The database as a caller meets it: a name, an instant, and the forms the rest of
// the library writes.

///|
test "what the package says it carries" {
  assert_eq(release.length(), 5)
  assert_eq(release[0].unsafe_to_char(), '2')
  assert_eq(source_digest.length(), 64)
}

///|
test "the names the database knows" {
  let names = zones()
  assert_eq(names.length(), 598)
  assert_eq(names[0], "Africa/Abidjan")
  for name in ["Asia/Shanghai", "America/New_York", "UTC", "Pacific/Chatham"] {
    let mut found = false
    for candidate in names {
      if candidate == name {
        found = true
      }
    }
    assert_eq(found, true)
  }
}

///|
test "a name that has been renamed" {
  // `Asia/Calcutta` is what a caller who stored the old name still has.
  let tz = load("Asia/Calcutta")
  assert_eq(tz.name(), "Asia/Kolkata")
  assert_eq(tz.at(0L).offset, 19800)
  let older = links()
  let mut found = false
  for pair in older {
    if pair.0 == "Asia/Calcutta" {
      assert_eq(pair.1, "Asia/Kolkata")
      found = true
    }
  }
  assert_eq(found, true)
}

///|
test "a name the database does not have" {
  assert_eq(find("Mars/Olympus") is None, true)
  let outcome = try {
    let _ = load("Mars/Olympus")
    "read"
  } catch {
    @zone.Unknown(name~) => name
    _ => "another refusal"
  }
  assert_eq(outcome, "Mars/Olympus")
}

///|
test "an instant read in a zone" {
  let tz = load("Asia/Shanghai")
  let moment = tz.moment(1790058605L)
  assert_eq(moment.to_string(), "2026-09-22T14:30:05+08:00")
  assert_eq(
    moment.strftime("%Y-%m-%d %H:%M:%S %Z %z"),
    "2026-09-22 14:30:05 CST +0800",
  )
  assert_eq(moment.pattern("VV"), "Asia/Shanghai")
  assert_eq(moment.layout(@moondate.RFC1123), "Tue, 22 Sep 2026 14:30:05 CST")
  assert_eq(
    moment.isoformat(zone_name=true),
    "2026-09-22T14:30:05+08:00[Asia/Shanghai]",
  )
}

///|
test "the hour the clocks skip, read out of the database" {
  let tz = load("America/New_York")
  let date = @moondate.Date::new(2026, 3, 8)
  let time = @moondate.Time::new(2, 30)
  let at = tz.read(date, time)
  let skipped = match at {
    Skipped(earlier~, later~) => (earlier, later)
    _ => (0L, 0L)
  }
  assert_eq(skipped.1 - skipped.0, 3600L)
  // Read as standard time the clock lands an hour later than read as daylight
  // time, and the second of the two is where the clock actually gets to.
  assert_eq(skipped.1, 1772955000L)
  assert_eq(tz.epoch(date, time), 1772955000L)
  assert_eq(tz.epoch(date, time, fold=Earlier), 1772951400L)
}

///|
test "the hour the clocks repeat, read out of the database" {
  let tz = load("America/New_York")
  let date = @moondate.Date::new(2026, 11, 1)
  let time = @moondate.Time::new(1, 30)
  let at = tz.read(date, time)
  let twice = match at {
    Ambiguous(earlier~, later~) => (earlier, later)
    _ => (0L, 0L)
  }
  assert_eq(twice.1 - twice.0, 3600L)
  assert_eq(tz.epoch(date, time), twice.0)
  assert_eq(tz.epoch(date, time, fold=Later), twice.1)
  // The two instants an hour apart are the same wall clock in two offsets.
  assert_eq(tz.at(twice.0).abbrev, "EDT")
  assert_eq(tz.at(twice.1).abbrev, "EST")
}

///|
test "a zone that gave up daylight saving" {
  // Shanghai has not changed its clocks since 1991, and its last stretch has no
  // rules at all, so a date a century out is the same reading.
  let tz = load("Asia/Shanghai")
  assert_eq(tz.at(0L).offset, 28800)
  assert_eq(tz.at(4102444800L).offset, 28800)
  assert_eq(tz.changes(from=694224000L, to=4102444800L).length(), 0)
}

///|
test "a rule that carries a zone past the end of its table" {
  // The compiled table runs to the year 3000, so a date in 2400 is answered by the
  // rules the release states rather than by a guess.
  let tz = load("Europe/London")
  let winter = tz.at(1356998400L)
  assert_eq(winter.offset, 0)
  assert_eq(winter.abbrev, "GMT")
  let summer = tz.at(1372636800L)
  assert_eq(summer.offset, 3600)
  assert_eq(summer.abbrev, "BST")
  assert_eq(tz.at(13569465600L).offset, 0)
}
