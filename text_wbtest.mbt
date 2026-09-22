// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read and written again, which is what a round trip through a document does.
fn round(s : String) -> String raise Refused {
  parse(s[:]).to_string()
}

///|
test "the four shapes TOML names, each read as itself" {
  // Offset date-time, which is what RFC 3339 defines.
  assert_eq(round("1979-05-27T07:32:00Z"), "1979-05-27T07:32:00Z")
  assert_eq(round("1979-05-27T00:32:00-07:00"), "1979-05-27T00:32:00-07:00")
  // Local date-time: a wall clock, with no zone.
  assert_eq(round("1979-05-27T07:32:00"), "1979-05-27T07:32:00")
  // Local date and local time.
  assert_eq(round("1979-05-27"), "1979-05-27")
  assert_eq(round("07:32:00"), "07:32:00")
  // And each is the variant it should be, not merely the same text.
  assert_eq(parse("1979-05-27T07:32:00Z") is Zoned(..), true)
  assert_eq(parse("1979-05-27T07:32:00") is Plain(..), true)
  assert_eq(parse("1979-05-27") is Day(..), true)
  assert_eq(parse("07:32:00") is Clock(..), true)
}

///|
test "a space joins a date and a time as well as a T" {
  // TOML 1.0.0 allows it and so does RFC 3339 under its NOTE, because it is what
  // a person writes.
  assert_eq(round("1979-05-27 07:32:00Z"), "1979-05-27T07:32:00Z")
  assert_eq(round("1979-05-27t07:32:00z"), "1979-05-27T07:32:00Z")
}

///|
test "a fraction of a second survives, and trailing zeros do not" {
  assert_eq(round("1979-05-27T07:32:00.999999Z"), "1979-05-27T07:32:00.999999Z")
  assert_eq(round("1979-05-27T07:32:00.500Z"), "1979-05-27T07:32:00.5Z")
  assert_eq(
    round("1979-05-27T07:32:00.000000001Z"),
    "1979-05-27T07:32:00.000000001Z",
  )
  // More precision than a nanosecond is read and dropped, which is what every
  // parser does with a precision it cannot hold.
  assert_eq(
    round("1979-05-27T07:32:00.1234567890123Z"),
    "1979-05-27T07:32:00.123456789Z",
  )
}

///|
test "the seconds may be left off, which ISO 8601 and TOML both allow" {
  assert_eq(round("07:32"), "07:32:00")
  assert_eq(round("1979-05-27T07:32"), "1979-05-27T07:32:00")
}

///|
test "text that is not a date or time is refused" {
  for
    bad in [
      "1979-05-27T", "1979-13-01", "1979-05-32", "1979/05/27", "79-05-27", "1979-05-27T25:00:00Z",
      "1979-05-27T07:60:00Z", "1979-05-27T07:32:00+25:00", "1979-05-27T07:32:00Zx",
      "1979-05-27T07:32:00.", "not a date",
    ] {
    assert_eq(refused_text(bad), true)
  }
}

///|
test "an HTTP date is written in one form and read in three" {
  // The preferred form, from RFC 9110 §5.6.7's own example.
  let m = http("Sun, 06 Nov 1994 08:49:37 GMT")
  assert_eq(m.to_string(), "1994-11-06T08:49:37Z")
  assert_eq(m.http_text(), "Sun, 06 Nov 1994 08:49:37 GMT")
  // The two obsolete forms a recipient must still accept, from the same section.
  assert_eq(
    http("Sunday, 06-Nov-94 08:49:37 GMT").to_string(),
    "1994-11-06T08:49:37Z",
  )
  assert_eq(
    http("Sun Nov  6 08:49:37 1994").to_string(),
    "1994-11-06T08:49:37Z",
  )
  // An offset moment is moved onto GMT before it is written, because the header
  // is always GMT.
  let east = Zoned(
    date=Date::new(1994, 11, 6),
    time=Time::new(16, 49, second=37),
    zone=Offset(480),
  )
  assert_eq(east.http_text(), "Sun, 06 Nov 1994 08:49:37 GMT")
}

///|
test "an ASN.1 time reads with the windowing rule certificates use" {
  // UTCTime's two digits: RFC 5280 §4.1.2.5.1 puts 49 and under in the 2000s.
  assert_eq(asn1("491231235959Z").to_string(), "2049-12-31T23:59:59Z")
  assert_eq(asn1("500101000000Z").to_string(), "1950-01-01T00:00:00Z")
  // Which is not the rule HTTP uses, where the boundary is 68/69.
  assert_eq(
    http("Sunday, 06-Nov-68 08:49:37 GMT").to_string(),
    "2068-11-06T08:49:37Z",
  )
  assert_eq(
    http("Sunday, 06-Nov-69 08:49:37 GMT").to_string(),
    "1969-11-06T08:49:37Z",
  )
  // GeneralizedTime spells the year out, which is why DER uses it from 2050 on.
  assert_eq(asn1("20260922143000Z").to_string(), "2026-09-22T14:30:00Z")
  assert_eq(
    Zoned(date=Date::new(2026, 9, 22), time=Time::new(14, 30), zone=Utc).asn1_text(),
    "20260922143000Z",
  )
  // DER requires the Z.
  assert_eq(refused_asn1("20260922143000"), true)
}

///|
test "strftime writes the directives Python writes" {
  let m = Zoned(
    date=Date::new(2026, 9, 22),
    time=Time::new(14, 30, second=5, nano=123_456_000),
    zone=Offset(480),
  )
  assert_eq(m.strftime("%Y-%m-%d"), "2026-09-22")
  assert_eq(m.strftime("%H:%M:%S.%f"), "14:30:05.123456")
  assert_eq(m.strftime("%I %p"), "02 PM")
  assert_eq(m.strftime("%a %A %b %B"), "Tue Tuesday Sep September")
  assert_eq(m.strftime("%j"), "265")
  assert_eq(m.strftime("%z"), "+0800")
  assert_eq(m.strftime("%G-W%V-%u"), "2026-W39-2")
  assert_eq(m.strftime("%w"), "2")
  assert_eq(m.strftime("100%%"), "100%")
  assert_eq(m.strftime("%y"), "26")
}

///|
test "strptime reads back what strftime writes" {
  let cases = [
    ("2026-09-22", "%Y-%m-%d"),
    ("2026-09-22 14:30:05", "%Y-%m-%d %H:%M:%S"),
    ("22/09/2026", "%d/%m/%Y"),
    ("Sep 22 2026", "%b %d %Y"),
    ("September 22, 2026", "%B %d, %Y"),
    ("2026-09-22T14:30:05+0800", "%Y-%m-%dT%H:%M:%S%z"),
    ("02:30:05 PM", "%I:%M:%S %p"),
  ]
  for c in cases {
    let (text, format) = c
    let m = strptime(text, format)
    assert_eq(m.strftime(format), text)
  }
}

///|
test "strptime gets the shape from what the text carried" {
  assert_eq(strptime("2026-09-22", "%Y-%m-%d") is Day(..), true)
  assert_eq(strptime("2026-09-22 14:30", "%Y-%m-%d %H:%M") is Plain(..), true)
  assert_eq(strptime("14:30", "%H:%M") is Clock(..), true)
  assert_eq(
    strptime("2026-09-22T14:30Z", "%Y-%m-%dT%H:%M%z") is Zoned(..),
    true,
  )
  // A twelve-hour clock needs its AM/PM to mean anything.
  assert_eq(strptime("12:30:00 AM", "%I:%M:%S %p").to_string(), "00:30:00")
  assert_eq(strptime("12:30:00 PM", "%I:%M:%S %p").to_string(), "12:30:00")
  // Two-digit years follow Python's rule: 69 and over are 1900s.
  assert_eq(strptime("69-01-01", "%y-%m-%d").to_string(), "1969-01-01")
  assert_eq(strptime("68-01-01", "%y-%m-%d").to_string(), "2068-01-01")
}

///|
test "strptime refuses text the format does not describe" {
  assert_eq(refused_strptime("2026-09-22", "%d/%m/%Y"), true)
  assert_eq(refused_strptime("not a date", "%Y-%m-%d"), true)
  assert_eq(refused_strptime("2026-13-01", "%Y-%m-%d"), true)
  assert_eq(refused_strptime("2026-09-22", "%Q"), true)
}

///|
test "isoformat takes the separator a log line wants" {
  let m = Plain(date=Date::new(2026, 9, 22), time=Time::new(14, 30))
  assert_eq(m.isoformat(), "2026-09-22T14:30:00")
  assert_eq(m.isoformat(sep=' '), "2026-09-22 14:30:00")
  assert_eq(of_isoformat(m.isoformat()[:]), m)
}

///|
test "ctime space-pads the day, which is what tells it apart" {
  let m = Zoned(
    date=Date::new(1994, 11, 6),
    time=Time::new(8, 49, second=37),
    zone=Utc,
  )
  assert_eq(m.ctime(), "Sun Nov  6 08:49:37 1994")
  let m2 = Zoned(
    date=Date::new(1994, 11, 16),
    time=Time::new(8, 49, second=37),
    zone=Utc,
  )
  assert_eq(m2.ctime(), "Wed Nov 16 08:49:37 1994")
}

///|
fn refused_text(s : String) -> Bool {
  try {
    let _ = parse(s[:])
    false
  } catch {
    _ => true
  }
}

///|
fn refused_asn1(s : String) -> Bool {
  try {
    let _ = asn1(s[:])
    false
  } catch {
    _ => true
  }
}

///|
fn refused_strptime(text : String, format : String) -> Bool {
  try {
    let _ = strptime(text[:], format[:])
    false
  } catch {
    _ => true
  }
}
