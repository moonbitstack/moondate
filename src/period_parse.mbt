// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A length read from the ISO 8601 text for a duration: `P1Y2M3DT4H5M6.007S`,
/// `P1W`, `-PT0.5S`.
///
/// The grammar is the one Temporal states: an optional sign, `P`, any of days,
/// weeks, months and years, and then `T` with any of hours, minutes and seconds.
/// A fraction is allowed on the last field only, and only from days down, because
/// half a month is not a number of days that two calendars agree on.
///
///     assert_eq(@moondate.Period::parse("P1Y2M3DT4H5M6.007S").to_string(), "P1Y2M3DT4H5M6.007S")
///     assert_eq(@moondate.Period::parse("-PT1.5H").to_string(), "-PT1H30M")
pub fn Period::parse(text : StringView) -> Period raise Refused {
  let mut at = 0
  let length = text.length()
  if length == 0 {
    raise Malformed("a duration is at least a P")
  }
  let mut sign = 1L
  let first = text[at].unsafe_to_char()
  if first == '-' || first == '+' {
    if first == '-' {
      sign = -1L
    }
    at = at + 1
  }
  if at >= length || text[at].unsafe_to_char() != 'P' {
    raise Malformed("a duration starts with P")
  }
  at = at + 1
  let mut period = zero
  let mut seen_any = false
  let mut in_time = false
  let mut fraction_seen = false
  while at < length {
    if text[at].unsafe_to_char() == 'T' {
      if in_time {
        raise Malformed("a duration has one T")
      }
      in_time = true
      at = at + 1
      continue
    }
    let (digits, fraction, moved) = read_number(text, at)
    at = moved
    if fraction_seen {
      raise Malformed("only the last field of a duration has a fraction")
    }
    let letter = if at < length {
      text[at].unsafe_to_char()
    } else {
      raise Truncated("a number in a duration is followed by its unit")
    }
    at = at + 1
    let whole = digits * sign
    if fraction != "" {
      fraction_seen = true
    }
    seen_any = true
    if !in_time {
      match letter {
        'Y' => period = { ..period, years: whole, }
        'M' => period = { ..period, months: whole, }
        'W' => period = { ..period, weeks: whole, }
        'D' => {
          period = { ..period, days: whole, }
          if fraction != "" {
            period = period.add(fraction_of(fraction, day_of_nanos, sign))
          }
        }
        _ => raise Malformed("a date field of a duration is Y, M, W or D")
      }
      if fraction != "" && letter != 'D' {
        raise Malformed(
          "a fraction of a year, a month or a week is not a length",
        )
      }
    } else {
      match letter {
        'H' => {
          period = { ..period, hours: whole, }
          if fraction != "" {
            period = period.add(fraction_of(fraction, 3_600_000_000_000L, sign))
          }
        }
        'M' => {
          period = { ..period, minutes: whole, }
          if fraction != "" {
            period = period.add(fraction_of(fraction, 60_000_000_000L, sign))
          }
        }
        'S' => {
          period = { ..period, seconds: whole, }
          if fraction != "" {
            period = period.add(fraction_of(fraction, 1_000_000_000L, sign))
          }
        }
        _ => raise Malformed("a time field of a duration is H, M or S")
      }
    }
  }
  if !seen_any {
    raise Malformed("a duration names at least one field")
  }
  period
}

///|
/// A number and the digits after its point, and where the text carries on.
fn read_number(
  text : StringView,
  from : Int32,
) -> (Int64, String, Int32) raise Refused {
  let length = text.length()
  let mut at = from
  let mut value = 0L
  let mut digits = 0
  while at < length && is_digit(text[at].to_int()) {
    value = value * 10L + (text[at].unsafe_to_char().to_int() - 48).to_int64()
    digits = digits + 1
    at = at + 1
  }
  if digits == 0 {
    raise Malformed("a field of a duration starts with a number")
  }
  let mut fraction = ""
  if at < length {
    let point = text[at].unsafe_to_char()
    if point == '.' || point == ',' {
      at = at + 1
      let start = at
      while at < length && is_digit(text[at].to_int()) {
        at = at + 1
      }
      if at == start {
        raise Malformed("a fraction of a duration has digits after its point")
      }
      fraction = text[start:at].to_owned()
    }
  }
  (value, fraction, at)
}

///|
/// The length a fraction of a field stands for: `5` of a day is twelve hours.
///
/// The digits are taken as a fraction of the field's own length, which is exact
/// for a field that divides evenly into nanoseconds, and the result is written in
/// the fields below the one it was written on.
fn fraction_of(digits : String, unit_nanos : Int64, sign : Int64) -> Period {
  if digits.length() > 9 {
    return zero
  }
  let mut scale = 1L
  let mut value = 0L
  for i in 0..<digits.length() {
    value = value * 10L + (digits[i].unsafe_to_char().to_int() - 48).to_int64()
    scale = scale * 10L
  }
  let part = value * (unit_nanos / scale)
  balanced_from(part * sign, Hours)
}
