// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The C99 and Python forms are checked against what Python 3.14 on glibc writes for
// the same instants; the fractional forms are chrono's, whose rules are short enough
// to state in each expected string.

///|
fn at(
  seconds : Int64,
  nano~ : Int32 = 0,
  minutes~ : Int32 = 0,
) -> @moondate.Moment {
  let zone : @moondate.Zone = if minutes == 0 { Utc } else { Offset(minutes) }
  @moondate.Moment::of_epoch(seconds, nano~, zone~)
}

///|
test "%e pads the day with a space, %F and %T spell out the date and the time" {
  let m = at(1_699_226_000, minutes=-330) // 2023-11-05 17:43:20 -05:30
  assert_eq(m.strftime("%e|%d"), " 5|05")
  assert_eq(m.strftime("%F %T"), "2023-11-05 17:43:20")
  assert_eq(at(1_700_000_000).strftime("%e"), "14")
  // A doubled per cent sign stays a per cent sign before the letter.
  assert_eq(m.strftime("%%F|%%T"), "%F|%T")
}

///|
test "%z and %:z write the offset with and without a colon" {
  let m = at(1_699_226_000, minutes=-330)
  assert_eq(m.strftime("%z|%:z"), "-0530|-05:30")
  assert_eq(at(1_700_000_000).strftime("%z|%:z"), "+0000|+00:00")
  assert_eq(at(1_700_000_000, minutes=60).strftime("%:z"), "+01:00")
  // A moment with no zone writes no offset at all.
  let plain = @moondate.Moment::Plain(
    date=@moondate.Date::new(2023, 11, 14),
    time=@moondate.Time::new(23, 13),
  )
  assert_eq(plain.strftime("[%z%:z]"), "[]")
}

///|
test "%Y has four digits, as Python writes a year below a thousand" {
  let m = @moondate.Moment::Day(date=@moondate.Date::new(99, 1, 1))
  assert_eq(m.strftime("%Y"), "0099")
  assert_eq(at(1_700_000_000).strftime("%Y"), "2023")
}

///|
test "the fractional forms: %f, %Nf, %.Nf and %.f" {
  let m = at(1_700_000_000, nano=123_456_789, minutes=60)
  assert_eq(m.strftime("%H:%M:%S"), "23:13:20")
  // Python's %f: microseconds, six digits, no dot.
  assert_eq(m.strftime("%f"), "123456")
  // N digits, truncated rather than rounded, with or without the dot.
  assert_eq(m.strftime("%.3f|%.6f|%.9f|%.1f"), ".123|.123456|.123456789|.1")
  assert_eq(m.strftime("%3f|%9f"), "123|123456789")
  // %.f: three, six or nine digits, as few as the value needs, nothing on a whole
  // second.
  assert_eq(m.strftime("%.f"), ".123456789")
  assert_eq(at(0, nano=120_000_000).strftime("%.f"), ".120")
  assert_eq(at(0, nano=123_000).strftime("%.f"), ".000123")
  assert_eq(at(0).strftime("[%.f]"), "[]")
  assert_eq(at(0, nano=7).strftime("%.3f|%.9f"), ".000|.000000007")
}

///|
test "a directive this writer does not know is written as it stands" {
  let m = at(1_700_000_000)
  assert_eq(m.strftime("%Q|%.3Q|%:Q"), "%Q|%.3Q|%:Q")
  assert_eq(m.strftime("ends with %"), "ends with %")
}

///|
test "strptime reads the forms strftime writes" {
  let m = @moondate.strptime(
    " 5 Nov 2023 23:13:20.123+01:00", "%e %b %Y %H:%M:%S%.3f%:z",
  )
  assert_eq(m.strftime("%F %T%.9f%:z"), "2023-11-05 23:13:20.123000000+01:00")
  let n = @moondate.strptime("2023-11-14T22:13:20.5Z", "%FT%T%.f%z")
  assert_eq(n.strftime("%.6f"), ".500000")
  // %.f stands for nothing on a whole second; %.3f insists on its dot.
  let whole = @moondate.strptime("2023-11-14 22:13:20", "%F %T%.f")
  assert_eq(whole.strftime("%T%.3f"), "22:13:20.000")
  let refused = try @moondate.strptime("22:13:20", "%T%.3f") catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(refused)
  // %3f reads three digits and leaves the rest to the format.
  let short = @moondate.strptime("20.1234", "%S.%3f4")
  assert_eq(short.strftime("%.6f"), ".123000")
}

///|
test "every write reads back to the same instant" {
  let formats = ["%F %T%.9f%:z", "%Y-%m-%dT%H:%M:%S.%9f%z", "%e %b %Y %T%.f%:z"]
  for seconds in [0L, 1_700_000_000L, 1_699_226_000L, 951_782_400L] {
    for nano in [0, 1, 999_999_999, 120_000_000] {
      let m = at(seconds, nano~, minutes=-330)
      for f in formats {
        let back = @moondate.strptime(m.strftime(f), f)
        assert_eq(back.epoch(), m.epoch())
        assert_eq(back.time().nano, nano)
      }
    }
  }
}
