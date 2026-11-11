// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The reference's answers about lengths, replayed.
//
// The table is generated from temporal-polyfill by scripts/temporal_vectors; this
// is the test that runs it. Every row is a question the reference was asked about
// a length — rounded to a unit, counted in one unit, compared with another — with
// the date it was measured from and the answer it gave.

///|
/// A length from the eight fields a row writes.
fn length_of(
  fields : (Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64),
) -> @moondate.Period {
  let (years, months, weeks, days, hours, minutes, seconds, nanos) = fields
  { years, months, weeks, days, hours, minutes, seconds, nanos, }
}

///|
/// Whether a length has the fields a row expects.
fn length_is(
  length : @moondate.Period,
  fields : (Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64),
) -> Bool {
  let (years, months, weeks, days, hours, minutes, seconds, nanos) = fields
  length.years == years &&
  length.months == months &&
  length.weeks == weeks &&
  length.days == days &&
  length.hours == hours &&
  length.minutes == minutes &&
  length.seconds == seconds &&
  length.nanos == nanos
}

///|
/// The date a row measures from.
fn date_of(text : String) -> @moondate.Date raise @moondate.Refused {
  @moondate.parse(text).date().unwrap()
}

///|
/// The unit a row writes as a number.
fn length_unit(code : Int32) -> @moondate.TimeUnit {
  match code {
    0 => Years
    1 => Months
    2 => Weeks
    3 => Days
    4 => Hours
    5 => Minutes
    6 => Seconds
    7 => Millis
    8 => Micros
    _ => Nanos
  }
}

///|
/// The rounding a row writes as a number.
fn length_rounding(code : Int32) -> @moondate.Rounding {
  match code {
    0 => Ceil
    1 => Floor
    2 => Expand
    3 => Trunc
    4 => HalfCeil
    5 => HalfFloor
    6 => HalfExpand
    7 => HalfTrunc
    _ => HalfEven
  }
}

///|
/// The unit as its name, for a failure that has to say which one.
fn unit_name(unit : @moondate.TimeUnit) -> String {
  match unit {
    Years => "years"
    Months => "months"
    Weeks => "weeks"
    Days => "days"
    Hours => "hours"
    Minutes => "minutes"
    Seconds => "seconds"
    Millis => "milliseconds"
    Micros => "microseconds"
    Nanos => "nanoseconds"
  }
}

///|
test "duration: a length rounded to a unit" {
  let wrong : Array[String] = []
  for row in roundcase_all() {
    let length = length_of(row.length)
    let start = date_of(row.start)
    let got = Some(
      length.round(
        smallest_unit=length_unit(row.unit),
        rounding=length_rounding(row.mode),
        start~,
      ),
    ) catch {
      _ => None
    }
    match got {
      None => wrong.push(row.start + " " + length.to_string() + ": refused")
      Some(answer) =>
        if !length_is(answer, row.want) {
          wrong.push(
            row.start +
            " " +
            length.to_string() +
            " rounded to " +
            unit_name(length_unit(row.unit)) +
            ": " +
            answer.to_string() +
            ", want " +
            length_of(row.want).to_string(),
          )
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "duration: a length counted in one unit" {
  let wrong : Array[String] = []
  for row in totalcase_all() {
    let length = length_of(row.length)
    let start = date_of(row.start)
    let got = Some(length.total(unit=length_unit(row.unit), start~)) catch {
      _ => None
    }
    match got {
      None => wrong.push(row.start + " " + length.to_string() + ": refused")
      Some(answer) => {
        let scale = if row.want < 0.0 { -row.want } else { row.want }
        let tolerance = if scale * 1.0e-12 > 1.0e-9 {
          scale * 1.0e-12
        } else {
          1.0e-9
        }
        let off = answer - row.want
        let off = if off < 0.0 { -off } else { off }
        if off > tolerance {
          wrong.push(
            row.start +
            " " +
            length.to_string() +
            " in " +
            unit_name(length_unit(row.unit)) +
            ": " +
            answer.to_string() +
            ", want " +
            row.want.to_string(),
          )
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "duration: two lengths compared" {
  let wrong : Array[String] = []
  for row in comparecase_all() {
    let start = date_of(row.start)
    let got = Some(length_of(row.left).compare(length_of(row.right), start~)) catch {
      _ => None
    }
    match got {
      None => wrong.push(row.start + ": refused")
      Some(answer) =>
        if answer != row.want {
          wrong.push(
            row.start +
            " " +
            length_of(row.left).to_string() +
            " against " +
            length_of(row.right).to_string() +
            ": " +
            answer.to_string() +
            ", want " +
            row.want.to_string(),
          )
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "duration: a length read from its text" {
  let wrong : Array[String] = []
  for row in parsecase_all() {
    let got = Some(@moondate.Period::parse(row.text)) catch { _ => None }
    match got {
      None => wrong.push(row.text + ": refused")
      Some(answer) =>
        if !length_is(answer, row.want) {
          wrong.push(
            row.text +
            ": " +
            answer.to_string() +
            ", want " +
            length_of(row.want).to_string(),
          )
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}
