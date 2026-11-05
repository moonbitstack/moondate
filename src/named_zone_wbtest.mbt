// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A moment that carries a zone with a name, written in each of the five text
// forms. The zone package is what produces such a moment; this package only has to
// write it, so the value is built here directly.

///|
/// One instant in New York, an hour before the clocks go back in 2026.
fn new_york() -> Moment raise Refused {
  Zoned(
    date=Date::new(2026, 11, 1),
    time=Time::new(1, 30),
    zone=Named({ name: "America/New_York", offset: -14400, abbrev: "EDT", }),
  )
}

///|
test "a named zone in the five text forms" {
  let moment = new_york()
  // `%Z` writes the abbreviation the database gave the zone, `%z` its offset.
  assert_eq(moment.strftime("%Z"), "EDT")
  assert_eq(moment.strftime("%z %:z %::z %:::z"), "-0400 -04:00 -04:00:00 -04")
  // LDML writes the abbreviation for `z` and the name for `V`.
  assert_eq(moment.pattern("z"), "EDT")
  assert_eq(moment.pattern("zzzz"), "EDT")
  assert_eq(moment.pattern("VV"), "America/New_York")
  assert_eq(moment.pattern("V"), "America/New_York")
  // A Go layout's `MST` is the abbreviation too, which is what Go's own `time`
  // writes for a location.
  assert_eq(moment.layout("MST"), "EDT")
  assert_eq(moment.layout(RFC1123), "Sun, 01 Nov 2026 01:30:00 EDT")
  // And the ISO form can keep the name beside the offset, as Temporal does.
  assert_eq(
    moment.isoformat(zone_name=true),
    "2026-11-01T01:30:00-04:00[America/New_York]",
  )
  assert_eq(moment.isoformat(), "2026-11-01T01:30:00-04:00")
}

///|
test "an offset that is not a whole number of minutes" {
  // New York ran 4:56:02 behind Greenwich until 1883. RFC 3339 has no seconds
  // field, so the written form keeps the minutes and the value keeps the rest;
  // Temporal's grammar has the seconds, so the ISO form writes them.
  let moment = Zoned(
    date=Date::new(1880, 1, 1),
    time=Time::new(12, 0),
    zone=Named({ name: "America/New_York", offset: -17762, abbrev: "LMT", }),
  )
  assert_eq(moment.strftime("%Z"), "LMT")
  assert_eq(moment.strftime("%z"), "-0456")
  assert_eq(moment.strftime("%::z"), "-04:56:02")
  assert_eq(moment.isoformat(), "1880-01-01T12:00:00-04:56:02")
  assert_eq(moment.to_string(), "1880-01-01T12:00:00-04:56")
}

///|
test "a name read back out of the text" {
  let text = "2026-11-01T01:30:00-04:00[America/New_York]"
  let moment = parse(text)
  assert_eq(
    moment.zone(),
    Some(Named({ name: "America/New_York", offset: -14400, abbrev: "", })),
  )
  assert_eq(moment.epoch(), new_york().epoch())
  // The text carried no abbreviation, so `%Z` falls back to the offset rather
  // than inventing one.
  assert_eq(moment.strftime("%Z"), "UTC-04:00")
  assert_eq(moment.pattern("VV"), "America/New_York")
  // A name with no offset is not an instant, and is refused rather than guessed.
  let outcome = try {
    let _ = parse("2026-11-01T01:30:00[America/New_York]")
    "read"
  } catch {
    Malformed(_) => "refused"
    _ => "another refusal"
  }
  assert_eq(outcome, "refused")
}

///|
test "a fixed offset keeps the spelling it had" {
  // Without a name there is nothing new to write: `UTC+08:00` for `%Z`, and the
  // offset for LDML's `z`.
  let moment = Zoned(
    date=Date::new(2026, 9, 22),
    time=Time::new(14, 30),
    zone=Offset(480),
  )
  assert_eq(moment.strftime("%Z"), "UTC+08:00")
  assert_eq(moment.pattern("z"), "+0800")
  assert_eq(moment.pattern("VV"), "UTC+08:00")
  assert_eq(moment.layout("MST"), "+08:00")
}
