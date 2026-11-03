// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The flags and the C99 E and O selectors, checked against glibc 2.43 (read
// through `strftime` in the C locale) and, where glibc and C++20 part ways, against
// [time.format] of C++20.

///|
fn flag_moment() -> @moondate.Moment raise @moondate.Refused {
  @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5, nano=123456789),
    zone=@moondate.Offset(480),
  )
}

///|
test "glibc flags: width, padding and case" {
  let m = flag_moment()
  // A width wider than the field pads with zeros, as glibc's `%10Y` does.
  assert_eq(m.strftime("%10Y"), "0000002026")
  assert_eq(m.strftime("%3m"), "009")
  assert_eq(m.strftime("%04y"), "0026")
  // `-` drops the padding, `_` fills with spaces, and neither changes a field
  // that is already two digits wide.
  assert_eq(m.strftime("%-d"), "22")
  assert_eq(m.strftime("%_d"), "22")
  assert_eq(m.strftime("%-j"), "265")
  assert_eq(m.strftime("%_j"), "265")
  // `^` upper-cases; `#` is glibc's change-case, which for a name is upper case.
  assert_eq(m.strftime("%^B"), "SEPTEMBER")
  assert_eq(m.strftime("%#B"), "SEPTEMBER")
  assert_eq(m.strftime("%#a"), "TUE")
  // `%p` is the one name `#` lower-cases, because AM and PM are already upper.
  assert_eq(m.strftime("%#p"), "pm")
}

///|
test "glibc E and O: a composite after the selector" {
  let m = flag_moment()
  // C99 lets `%Ec` stand for `%c` and `%Ex` for `%x`; glibc writes exactly that.
  assert_eq(m.strftime("%Ec"), m.strftime("%c"))
  assert_eq(m.strftime("%Ex"), "09/22/26")
  assert_eq(m.strftime("%EX"), "14:30:05")
  assert_eq(m.strftime("%Ey"), "26")
  assert_eq(m.strftime("%EY"), "2026")
  // The other selectors mean nothing without a locale, so they keep the plain form.
  assert_eq(m.strftime("%Om"), "09")
  assert_eq(m.strftime("%Od"), "22")
  assert_eq(m.strftime("%OH"), "14")
  assert_eq(m.strftime("%OS"), "05")
}

///|
test "the ISO 8601 selectors of C++20" {
  // glibc treats `%Ez` as `%z` and writes `+0800`; C++20 [time.format] gives the
  // selector its own meaning, `%Ez` the extended form and `%Oz` the basic one, and
  // that is the pair this package follows because it is the only reading under
  // which the letters differ.
  assert_eq(flag_moment().strftime("%Ez"), "+08:00")
  assert_eq(flag_moment().strftime("%Oz"), "+0800")
  assert_eq(flag_moment().strftime("%z"), "+0800")
  let utc = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5),
    zone=@moondate.Utc,
  )
  assert_eq(utc.strftime("%Ez"), "+00:00")
  assert_eq(utc.strftime("%Oz"), "+0000")
  assert_eq(utc.strftime("%#z"), "+0000")
}

///|
test "an offset at the precision it needs" {
  // GNU date's `%:::z` keeps the minutes of a half-hour offset (`+05:30`); chrono
  // drops them and writes `+05`, which loses the offset. The form that loses
  // nothing is the one here.
  let m = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2000, 2, 29),
    time=@moondate.Time::new(23, 59, second=59),
    zone=@moondate.Offset(-330),
  )
  assert_eq(m.strftime("%:::z"), "-05:30")
  let hour = @moondate.Moment::Zoned(
    date=@moondate.Date::new(2026, 9, 22),
    time=@moondate.Time::new(14, 30, second=5),
    zone=@moondate.Offset(540),
  )
  assert_eq(hour.strftime("%:::z"), "+09")
  assert_eq(hour.strftime("%:z"), "+09:00")
  assert_eq(hour.strftime("%::z"), "+09:00:00")
}

///|
test "the flags read back" {
  // A selector before a composite is a spelling of the composite, so the reader
  // takes the same text.
  assert_eq(
    @moondate.strptime("Tue Sep 22 14:30:05 2026", "%Ec").isoformat(),
    "2026-09-22T14:30:05",
  )
  // The E and O selectors on an offset do not change how a sign, hours and minutes
  // are read.
  let m = @moondate.strptime(
    "2026-09-22T14:30:05.123456+08:00", "%Y-%m-%dT%H:%M:%S%.6f%Ez",
  )
  assert_eq(m.isoformat(), "2026-09-22T14:30:05.123456+08:00")
  let plain = @moondate.strptime(
    "2026-09-22T14:30:05-0530", "%Y-%m-%dT%H:%M:%S%Oz",
  )
  assert_eq(plain.isoformat(), "2026-09-22T14:30:05-05:30")
}

///|
test "an offset without minutes reads back" {
  // `%:::z` writes `+09` for a whole-hour offset, and what it writes it reads.
  let m = @moondate.strptime(
    "2026-09-22 14:30:05 +09", "%Y-%m-%d %H:%M:%S %:::z",
  )
  assert_eq(m.isoformat(), "2026-09-22T14:30:05+09:00")
  let half = @moondate.strptime(
    "2026-09-22 14:30:05 +05:30", "%Y-%m-%d %H:%M:%S %:::z",
  )
  assert_eq(half.isoformat(), "2026-09-22T14:30:05+05:30")
  let basic = @moondate.strptime(
    "2026-09-22 14:30:05 -0530", "%Y-%m-%d %H:%M:%S %z",
  )
  assert_eq(basic.isoformat(), "2026-09-22T14:30:05-05:30")
}
