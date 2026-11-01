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

///|
/// The two week numbers for every weekday January can start on, from CPython's `strftime`.
test "%U and %W in years that start on each day of the week" {
  for
    row in [
      (2017, 1, 1, "01", "00"),
      (2017, 1, 2, "01", "01"),
      (2017, 1, 7, "01", "01"),
      (2017, 1, 8, "02", "01"),
      (2017, 6, 15, "24", "24"),
      (2017, 12, 31, "53", "52"),
      (2018, 1, 1, "00", "01"),
      (2018, 1, 2, "00", "01"),
      (2018, 1, 7, "01", "01"),
      (2018, 1, 8, "01", "02"),
      (2018, 6, 15, "23", "24"),
      (2018, 12, 31, "52", "53"),
      (2019, 1, 1, "00", "00"),
      (2019, 1, 2, "00", "00"),
      (2019, 1, 7, "01", "01"),
      (2019, 1, 8, "01", "01"),
      (2019, 6, 15, "23", "23"),
      (2019, 12, 31, "52", "52"),
      (2020, 1, 1, "00", "00"),
      (2020, 1, 2, "00", "00"),
      (2020, 1, 7, "01", "01"),
      (2020, 1, 8, "01", "01"),
      (2020, 6, 15, "24", "24"),
      (2020, 12, 31, "52", "52"),
      (2021, 1, 1, "00", "00"),
      (2021, 1, 2, "00", "00"),
      (2021, 1, 7, "01", "01"),
      (2021, 1, 8, "01", "01"),
      (2021, 6, 15, "24", "24"),
      (2021, 12, 31, "52", "52"),
      (2022, 1, 1, "00", "00"),
      (2022, 1, 2, "01", "00"),
      (2022, 1, 7, "01", "01"),
      (2022, 1, 8, "01", "01"),
      (2022, 6, 15, "24", "24"),
      (2022, 12, 31, "52", "52"),
      (2023, 1, 1, "01", "00"),
      (2023, 1, 2, "01", "01"),
      (2023, 1, 7, "01", "01"),
      (2023, 1, 8, "02", "01"),
      (2023, 6, 15, "24", "24"),
      (2023, 12, 31, "53", "52"),
      (2024, 1, 1, "00", "01"),
      (2024, 1, 2, "00", "01"),
      (2024, 1, 7, "01", "01"),
      (2024, 1, 8, "01", "02"),
      (2024, 6, 15, "23", "24"),
      (2024, 12, 31, "52", "53"),
      (2025, 1, 1, "00", "00"),
      (2025, 1, 2, "00", "00"),
      (2025, 1, 7, "01", "01"),
      (2025, 1, 8, "01", "01"),
      (2025, 6, 15, "24", "23"),
      (2025, 12, 31, "52", "52"),
      (2026, 1, 1, "00", "00"),
      (2026, 1, 2, "00", "00"),
      (2026, 1, 7, "01", "01"),
      (2026, 1, 8, "01", "01"),
      (2026, 6, 15, "24", "24"),
      (2026, 12, 31, "52", "52"),
      (2027, 1, 1, "00", "00"),
      (2027, 1, 2, "00", "00"),
      (2027, 1, 7, "01", "01"),
      (2027, 1, 8, "01", "01"),
      (2027, 6, 15, "24", "24"),
      (2027, 12, 31, "52", "52"),
      (2028, 1, 1, "00", "00"),
      (2028, 1, 2, "01", "00"),
      (2028, 1, 7, "01", "01"),
      (2028, 1, 8, "01", "01"),
      (2028, 6, 15, "24", "24"),
      (2028, 12, 31, "53", "52"),
    ] {
    let (year, month, day, sunday, monday) = row
    let date = @moondate.Date::new(year, month, day)
    let moment = @moondate.Moment::combine(date, @moondate.Time::new(12, 0))
    assert_eq(moment.strftime("%U"), sunday)
    assert_eq(moment.strftime("%W"), monday)
    for spec in ["%Y %U %w", "%Y %W %w"] {
      assert_eq(
        @moondate.strptime(moment.strftime(spec), spec).date(),
        Some(date),
      )
    }
  }
}
