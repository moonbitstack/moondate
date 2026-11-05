// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The fields a `Rule` line and a `Zone` line are made of: an offset, a time of
// day with the clock it is read against, a month, a day, and the year a stretch
// ends. They are the whole of the small language the database is written in, and
// every one of them has a shorter form that has to be read the same way.

///|
/// Which clock a time of day on a `Rule` or `Zone` line is read against.
priv enum Clock {
  Wall
  Std
  Utc
}

///|
/// The day a rule changes the clocks on.
priv enum Day {
  /// A day of the month, `15`.
  Dom(Int32)
  /// The last such weekday of the month, `lastSun`.
  Last(Int32)
  /// The first such weekday on or after a day, `Sun>=8`.
  From(Int32, Int32)
  /// The last such weekday on or before a day, `Sun<=25`.
  To(Int32, Int32)
}

///|
/// A `Rule` line.
priv struct Line {
  from : Int32
  to : Int32
  month : Int32
  day : Day
  at : Int32
  clock : Clock
  save : Int32
  letter : String
  is_dst : Bool
}

///|
/// Where a stretch of a zone gets its saving from.
priv enum Saving {
  None_
  /// A rule set by name.
  Named(String)
  /// One amount of saving for the whole stretch.
  Fixed(Int32)
}

///|
/// One stretch of a zone: from where the previous one ended until `until`.
priv struct Stretch {
  offset : Int32
  saving : Saving
  format : String
  /// `None` for the last stretch, which ends where the table does.
  until : Array[String]?
}

///|
/// A time of day as seconds, with the suffix that says which clock reads it.
fn time_of(text : String) -> (Int32, Clock) {
  let mut body = text
  let mut clock = Wall
  if text.length() > 0 {
    let last = text[text.length() - 1].unsafe_to_char()
    let head = text[0:text.length() - 1].to_owned()
    if last == 's' {
      clock = Std
      body = head
    } else if last == 'u' || last == 'g' || last == 'z' {
      clock = Utc
      body = head
    } else if last == 'w' {
      body = head
    }
  }
  (offset_of(body), clock)
}

///|
/// A signed run of hours, minutes and seconds, `-3:12:48`, as seconds east.
///
/// The same reader serves the offsets a zone line starts with and the amounts of
/// saving a rule line ends with; neither has a suffix, and the sign belongs to the
/// whole.
fn offset_of(text : String) -> Int32 {
  let mut i = 0
  let mut sign = 1
  if i < text.length() {
    let c = text[i].unsafe_to_char()
    if c == '-' {
      sign = -1
      i = i + 1
    } else if c == '+' {
      i = i + 1
    }
  }
  let parts : Array[Int32] = [0, 0, 0]
  let mut part = 0
  while i < text.length() {
    let c = text[i].unsafe_to_char()
    if c == ':' {
      part = part + 1
      i = i + 1
      continue
    }
    if part > 2 {
      break
    }
    parts[part] = parts[part] * 10 + (c.to_int() - 48)
    i = i + 1
  }
  sign * (parts[0] * 3600 + parts[1] * 60 + parts[2])
}

///|
/// A year, `2026`, or one of the two words that stand in for a range.
fn year_of(text : String, only : Bool) -> Int32 raise @zone.Refused {
  if text.length() == 0 {
    raise @zone.Malformed(kind="a year", at=0)
  }
  let head = text[0].unsafe_to_char()
  if head < '0' || head > '9' {
    // `max` is the horizon; `o` is the same year as the one that starts the rule.
    if text[0].unsafe_to_char() == 'm' {
      9999
    } else if only {
      -9999
    } else {
      raise @zone.Malformed(kind="a year: max or a number", at=0)
    }
  } else {
    let mut out = 0
    for k = 0; k < text.length(); k = k + 1 {
      out = out * 10 + (text[k].unsafe_to_char().to_int() - 48)
    }
    out
  }
}

///|
/// A month, written in full or cut to as few letters as stay unambiguous, which
/// is what the release's own shrinking does to the text.
fn month_of(text : String) -> Int32 raise @zone.Refused {
  let months : Array[String] = [
    "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov",
    "dec",
  ]
  let key = lower(text)
  for k = 0; k < 12; k = k + 1 {
    if starts_with(months[k], key) {
      return k + 1
    }
  }
  raise @zone.Malformed(kind="a month", at=0)
}

///|
/// A day of the month: a number, `lastSun`, `Sun>=8` or `Sun<=25`.
fn day_of(text : String) -> Day raise @zone.Refused {
  if text.length() >= 4 && starts_with(text, "last") {
    return Last(weekday_of(text[4:].to_owned()))
  }
  let mut cut = -1
  for k = 0; k < text.length() - 1; k = k + 1 {
    let c = text[k].unsafe_to_char()
    if c == '>' || c == '<' {
      cut = k
      break
    }
  }
  if cut > 0 {
    let weekday = weekday_of(text[0:cut].to_owned())
    let mut at = cut + 1
    if text[cut].unsafe_to_char() == '>' &&
      text[cut + 1].unsafe_to_char() == '=' {
      at = cut + 2
    } else if text[cut].unsafe_to_char() == '<' &&
      at + 1 < text.length() &&
      text[cut + 1].unsafe_to_char() == '=' {
      at = cut + 2
    }
    let n = number_of(text[at:].to_owned())
    if text[cut].unsafe_to_char() == '>' {
      From(weekday, n)
    } else {
      To(weekday, n)
    }
  } else {
    Dom(number_of(text))
  }
}

///|
/// A weekday, Sunday being 0.
fn weekday_of(text : String) -> Int32 raise @zone.Refused {
  let days : Array[String] = [
    "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
  ]
  let key = lower(text)
  for k = 0; k < 7; k = k + 1 {
    if starts_with(days[k], key) {
      return k
    }
  }
  raise @zone.Malformed(kind="a weekday", at=0)
}

///|
fn number_of(text : String) -> Int32 {
  let mut out = 0
  for k = 0; k < text.length(); k = k + 1 {
    let c = text[k].unsafe_to_char()
    if c >= '0' && c <= '9' {
      out = out * 10 + (c.to_int() - 48)
    }
  }
  out
}

///|
fn lower(text : String) -> String {
  let out = StringBuilder()
  for k = 0; k < text.length(); k = k + 1 {
    let c = text[k].unsafe_to_char()
    if c >= 'A' && c <= 'Z' {
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn starts_with(text : String, head : String) -> Bool {
  if head.length() > text.length() {
    return false
  }
  for k = 0; k < head.length(); k = k + 1 {
    if text[k] != head[k] {
      return false
    }
  }
  true
}

///|
/// Whether a stretch's saving is written as a fixed amount: it starts with a
/// digit or a sign, where a rule set's name never does.
fn is_saving_letter(text : String) -> Bool {
  if text.length() == 0 {
    return false
  }
  let c = text[0].unsafe_to_char()
  (c >= '0' && c <= '9') || c == '-' || c == '+'
}
