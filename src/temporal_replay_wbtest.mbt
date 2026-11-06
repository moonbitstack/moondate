// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The cases test262 states about reading a zoned date and time, replayed.
//
// The tables are generated from the corpus by scripts/temporal_vectors/build.py;
// this is the test that runs them. A case is one of three things: a text that
// names an instant, a text whose zone name is all the corpus asserts, or a text
// the corpus says must be refused.

///|
/// A moment's instant as the two halves the corpus writes: whole seconds past
/// 1970 and the nanoseconds after them.
fn instant_of(moment : Moment) -> (Int64, Int64)? {
  match moment.instant() {
    Some((seconds, nano)) => Some((seconds, nano.to_int64()))
    None => None
  }
}

///|
/// The name a moment's zone is filed under, which is what test262 calls
/// `timeZoneId`.
fn zone_name_of(moment : Moment) -> String {
  match moment.zone() {
    Some(zone) => zone.name()
    None => ""
  }
}

///|
/// One property of a reading, named the way test262 names it, or `None` when the
/// moment has no such property — a date has no hour, and a clock has no year.
///
/// A test may state one property rather than a whole reading: `prototype/year`
/// asks what year the text reads as and nothing else. The transcription keeps the
/// property and the name of it, so what is compared here is only what was said.
fn property_of(moment : Moment, name : String) -> Int32? {
  match name {
    "year" | "month" | "day" =>
      match moment.date() {
        None => None
        Some(date) =>
          Some(
            match name {
              "year" => date.year
              "month" => date.month
              _ => date.day
            },
          )
      }
    _ => {
      let nanos = moment.time().nanos()
      match name {
        "hour" => Some((nanos / 3_600_000_000_000L).to_int())
        "minute" => Some((nanos / 60_000_000_000L % 60L).to_int())
        "second" => Some((nanos / 1_000_000_000L % 60L).to_int())
        "millisecond" => Some((nanos / 1_000_000L % 1000L).to_int())
        "microsecond" => Some((nanos / 1_000L % 1000L).to_int())
        "nanosecond" => Some((nanos % 1000L).to_int())
        _ => None
      }
    }
  }
}

///|
test "test262: a zoned text states an instant" {
  let wrong : Array[String] = []
  for row in readings {
    let (text, seconds, nano, zone) = row
    let parsed = Some(parse(text)) catch { _ => None }
    match parsed {
      None => wrong.push("refused, want an instant: " + text)
      Some(moment) =>
        match instant_of(moment) {
          None => wrong.push("no instant: " + text)
          Some((got_seconds, got_nano)) => {
            if got_seconds != seconds || got_nano != nano {
              wrong.push(
                text +
                ": read " +
                got_seconds.to_string() +
                "s " +
                got_nano.to_string() +
                "ns, want " +
                seconds.to_string() +
                "s " +
                nano.to_string() +
                "ns",
              )
            }
            // A case that asserts only the instant says nothing about the name.
            if zone != "" {
              let got_zone = zone_name_of(moment)
              if got_zone != zone {
                wrong.push(
                  text + ": filed under " + got_zone + ", want " + zone,
                )
              }
            }
          }
        }
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a text states a zone and nothing else" {
  let wrong : Array[String] = []
  for row in names {
    let (text, zone) = row
    let parsed = Some(parse(text)) catch { _ => None }
    match parsed {
      None => wrong.push("refused, want a zone: " + text)
      Some(moment) => {
        let got = zone_name_of(moment)
        if got != zone {
          wrong.push(text + ": filed under " + got + ", want " + zone)
        }
      }
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a text states one property of a reading" {
  let wrong : Array[String] = []
  for row in partial_readings {
    let (text, name, want) = row
    let parsed = Some(parse(text)) catch { _ => None }
    match parsed {
      None => wrong.push("refused, want a " + name + ": " + text)
      Some(moment) =>
        match property_of(moment, name) {
          None => wrong.push("no " + name + " to read: " + text)
          Some(got) =>
            if got != want {
              wrong.push(
                text +
                ": " +
                name +
                " reads " +
                got.to_string() +
                ", want " +
                want.to_string(),
              )
            }
        }
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a zoned text is refused" {
  let wrong : Array[String] = []
  for row in refusals {
    let (text, want) = row
    let parsed = Some(parse(text)) catch { _ => None }
    if parsed is Some(moment) {
      wrong.push(text + ": read as " + moment.to_string() + ", want " + want)
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a text states a date" {
  let wrong : Array[String] = []
  for row in dates {
    let (text, year, month, day) = row
    let parsed = Some(parse(text)) catch { _ => None }
    match parsed {
      None => wrong.push("refused, want a date: " + text)
      Some(moment) =>
        match moment.date() {
          None => wrong.push("no date: " + text)
          Some(date) =>
            if date.year != year || date.month != month || date.day != day {
              wrong.push(
                text +
                ": read " +
                date.year.to_string() +
                "-" +
                date.month.to_string() +
                "-" +
                date.day.to_string(),
              )
            }
        }
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a text states an instant" {
  let wrong : Array[String] = []
  for row in instants {
    let (text, seconds, nano) = row
    let parsed = Some(parse(text)) catch { _ => None }
    match parsed {
      None => wrong.push("refused, want an instant: " + text)
      Some(moment) =>
        match instant_of(moment) {
          None => wrong.push("no instant: " + text)
          Some((got_seconds, got_nano)) =>
            if got_seconds != seconds || got_nano != nano {
              wrong.push(
                text +
                ": read " +
                got_seconds.to_string() +
                "s " +
                got_nano.to_string() +
                "ns, want " +
                seconds.to_string() +
                "s " +
                nano.to_string() +
                "ns",
              )
            }
        }
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: a date is refused" {
  let wrong : Array[String] = []
  for row in date_refusals {
    let (text, want) = row
    let parsed = Some(parse(text)) catch { _ => None }
    if parsed is Some(moment) {
      wrong.push(text + ": read as " + moment.to_string() + ", want " + want)
    }
  }
  assert_eq(wrong, [])
}

///|
test "test262: an instant is refused" {
  let wrong : Array[String] = []
  for row in instant_refusals {
    let (text, want) = row
    let parsed = Some(parse(text)) catch { _ => None }
    if parsed is Some(moment) {
      wrong.push(text + ": read as " + moment.to_string() + ", want " + want)
    }
  }
  assert_eq(wrong, [])
}
