// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why an expression was refused.
pub(all) suberror Refused {
  Fields(got~ : Int)
  Range(field~ : String, got~ : Int, low~ : Int, high~ : Int)
  Malformed(String)
} derive(Eq, Debug)

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Fields(got~) => logger.write_string("\{got} fields, expected five or six")
    Range(field~, got~, low~, high~) =>
      logger.write_string("\{field} is \{got}, outside \{low}..\{high}")
    Malformed(m) => logger.write_string("malformed: " + m)
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// A parsed expression: which values of each field it fires on.
///
/// Each field is a bit set, so asking whether a moment matches is six bit tests
/// rather than a search. `star_day` and `star_week` are kept because the two fields
/// interact — see [`Cron::matches`].
pub(all) struct Cron {
  seconds : Int64
  minutes : Int64
  hours : Int
  days : Int
  months : Int
  weekdays : Int
  star_day : Bool
  star_week : Bool
} derive(Eq, Debug)

///|
pub extend Cron with Debug::{to_repr}

///|
pub extend Cron with Eq::{not_equal, equal}

///|
/// An expression, in the five-field form crontab(5) defines or the six-field form
/// that puts seconds in front.
///
/// ```text
/// ┌───────────── second (0-59, six-field form only)
/// │ ┌───────────── minute (0-59)
/// │ │ ┌───────────── hour (0-23)
/// │ │ │ ┌───────────── day of month (1-31)
/// │ │ │ │ ┌───────────── month (1-12 or JAN-DEC)
/// │ │ │ │ │ ┌───────────── day of week (0-7 or SUN-SAT, both 0 and 7 being Sunday)
/// * * * * * *
/// ```
///
/// Each field takes `*`, a number, a range `a-b`, a step `*/n` or `a-b/n`, and a
/// comma-separated list of those. `?` reads as `*`, which is what Quartz writes in
/// whichever of the two day fields it is not using.
///
/// The shorthands `@yearly`, `@annually`, `@monthly`, `@weekly`, `@daily`,
/// `@midnight` and `@hourly` are the ones crontab(5) lists. `@reboot` is not here:
/// it names an event rather than a time, and this package answers when something
/// fires, not why.
pub fn parse(expr : StringView) -> Cron raise Refused {
  let text = expr.to_owned()
  let short = match trim(text).to_lower() {
    "@yearly" | "@annually" => Some("0 0 1 1 *")
    "@monthly" => Some("0 0 1 * *")
    "@weekly" => Some("0 0 * * 0")
    "@daily" | "@midnight" => Some("0 0 * * *")
    "@hourly" => Some("0 * * * *")
    _ => None
  }
  let fields = split(
    match short {
      Some(s) => s
      None => text
    },
  )
  let (sec, rest) = match fields.length() {
    5 => (bit64(0), 0)
    6 => (field64(fields[0], 0, 59, "second"), 1)
    n => raise Fields(got=n)
  }
  let days = field(fields[rest + 2], 1, 31, "day of month")
  let weekdays = week(fields[rest + 3 + 1])
  {
    seconds: sec,
    minutes: field64(fields[rest], 0, 59, "minute"),
    hours: field(fields[rest + 1], 0, 23, "hour"),
    days,
    months: month(fields[rest + 3]),
    weekdays,
    star_day: is_star(fields[rest + 2]),
    star_week: is_star(fields[rest + 3 + 1]),
  }
}

///|
/// Whether a field is unrestricted, which `?` is too (Quartz writes it in the day
/// field it is not using).
fn is_star(s : String) -> Bool {
  s == "*" || s == "?"
}

///|
/// Whether `m` is a moment this expression fires on.
///
/// The day-of-month and day-of-week fields are **or**-ed when both are restricted,
/// which is Vixie cron's rule and surprises everyone once: `0 0 13 * 5` is the
/// thirteenth *or* any Friday, not Friday the thirteenth. When one of them is `*`
/// they are and-ed, which is why `0 0 13 * *` is only the thirteenth.
pub fn Cron::matches(self : Cron, m : @moondate.Moment) -> Bool {
  let (date, time) = match m {
    Zoned(date~, time~, ..) | Plain(date~, time~) => (date, time)
    Day(date~) => (date, { hour: 0, minute: 0, second: 0, nano: 0, })
    Clock(_) => return false
  }
  if not64(self.seconds, time.second) ||
    not64(self.minutes, time.minute) ||
    !has(self.hours, time.hour) ||
    !has(self.months, date.month) {
    return false
  }
  let by_day = has(self.days, date.day)
  let by_week = has(self.weekdays, date.weekday())
  if self.star_day && self.star_week {
    true
  } else if self.star_day {
    by_week
  } else if self.star_week {
    by_day
  } else {
    by_day || by_week
  }
}

///|
/// The first moment strictly after `m` that this expression fires on.
///
/// `None` when it never does. An expression can name a day that does not exist —
/// `0 0 30 2 *` is the thirtieth of February — so the search is bounded at four
/// years, which is past any leap-year cycle a real schedule turns on.
pub fn Cron::next(self : Cron, m : @moondate.Moment) -> @moondate.Moment? {
  let mut at = m.plus(@moondate.second)
  // Start on a whole second: a schedule fires on the clock, not between ticks.
  at = floor(at)
  let limit = 4 * 366 * 24 * 60 * 60
  for i = 0; i < limit; i = i + 1 {
    if self.matches(at) {
      return Some(at)
    }
    at = at.plus(@moondate.second)
  }
  None
}

///|
/// The moment with its fraction of a second dropped.
fn floor(m : @moondate.Moment) -> @moondate.Moment {
  match m {
    Zoned(date~, time~, zone~) => Zoned(date~, time={ ..time, nano: 0, }, zone~)
    Plain(date~, time~) => Plain(date~, time={ ..time, nano: 0, })
    other => other
  }
}

// -- fields -------------------------------------------------------------------

///|
/// A field as a bit set over `low..=high`.
fn field(s : String, low : Int, high : Int, name : String) -> Int raise Refused {
  let mut out = 0
  for part in split_on(s, ',') {
    let (from, to, step) = span(part, low, high, name)
    for v = from; v <= to; v = v + step {
      out = out | (1 << v)
    }
  }
  out
}

///|
/// The same over a range that needs sixty-four bits.
fn field64(
  s : String,
  low : Int,
  high : Int,
  name : String,
) -> Int64 raise Refused {
  let mut out = 0L
  for part in split_on(s, ',') {
    let (from, to, step) = span(part, low, high, name)
    for v = from; v <= to; v = v + step {
      out = out | (1L << v)
    }
  }
  out
}

///|
/// One comma-separated piece as `(from, to, step)`.
fn span(
  s : String,
  low : Int,
  high : Int,
  name : String,
) -> (Int, Int, Int) raise Refused {
  let slash = find(s, '/')
  let head = if slash < 0 { s } else { s[0:slash].to_owned() }
  let step = if slash < 0 {
    1
  } else {
    let n = number(s[slash + 1:].to_owned(), name)
    if n < 1 {
      raise Range(field=name + " step", got=n, low=1, high~)
    }
    n
  }
  if is_star(head) {
    return (low, high, step)
  }
  let dash = find_from(head, '-', 1)
  if dash < 0 {
    let v = value(head, low, high, name)
    // `n/step` means from n to the end, which is what every implementation does
    // even though crontab(5) only documents `a-b/n`.
    return if slash < 0 { (v, v, 1) } else { (v, high, step) }
  }
  let from = value(head[0:dash].to_owned(), low, high, name)
  let to = value(head[dash + 1:].to_owned(), low, high, name)
  if to < from {
    raise Malformed("\{name} range runs backwards: \{head}")
  }
  (from, to, step)
}

///|
/// One value, checked against the field's range.
fn value(s : String, low : Int, high : Int, name : String) -> Int raise Refused {
  let v = number(s, name)
  if v < low || v > high {
    raise Range(field=name, got=v, low~, high~)
  }
  v
}

///|
/// The month field, which also takes the three-letter names.
fn month(s : String) -> Int raise Refused {
  field(names(s, month_names, 1), 1, 12, "month")
}

///|
/// The day-of-week field, which also takes the three-letter names, and where both
/// 0 and 7 are Sunday (crontab(5)).
fn week(s : String) -> Int raise Refused {
  let bits = field(names(s, day_names, 0), 0, 7, "day of week")
  if has(bits, 7) {
    (bits | 1) & 0x7f
  } else {
    bits
  }
}

///|
/// Three-letter names replaced by their numbers, so the rest of the parser sees
/// only digits. `base` is the number the first name stands for: months count from
/// one, days of the week from zero.
fn names(s : String, table : Array[String], base : Int) -> String {
  let out = StringBuilder()
  let upper = s.to_upper()
  let mut i = 0
  while i < upper.length() {
    let mut hit = -1
    if i + 3 <= upper.length() {
      let three = upper[i:i + 3].to_owned()
      for k = 0; k < table.length(); k = k + 1 {
        if table[k] == three {
          hit = k
          break
        }
      }
    }
    if hit >= 0 {
      out.write_string((hit + base).to_string())
      i = i + 3
    } else {
      out.write_char(upper[i].unsafe_to_char())
      i = i + 1
    }
  }
  out.to_string()
}

///|
let month_names : Array[String] = [
  "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
]

///|
let day_names : Array[String] = [
  "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT",
]

// -- text ---------------------------------------------------------------------

///|
/// The expression's fields, split on runs of whitespace.
fn split(s : String) -> Array[String] {
  let out : Array[String] = []
  let sb = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].to_int()
    if c == 0x20 || c == 0x09 {
      let piece = sb.to_string()
      if piece.length() > 0 {
        out.push(piece)
      }
      sb.reset()
    } else {
      sb.write_char(s[i].unsafe_to_char())
    }
  }
  let piece = sb.to_string()
  if piece.length() > 0 {
    out.push(piece)
  }
  out
}

///|
fn split_on(s : String, c : Char) -> Array[String] {
  let out : Array[String] = []
  let mut start = 0
  for i = 0; i <= s.length(); i = i + 1 {
    if i == s.length() || s[i].to_int() == c.to_int() {
      out.push(s[start:i].to_owned())
      start = i + 1
    }
  }
  out
}

///|
fn find(s : String, c : Char) -> Int {
  find_from(s, c, 0)
}

///|
fn find_from(s : String, c : Char, from : Int) -> Int {
  for i = from; i < s.length(); i = i + 1 {
    if s[i].to_int() == c.to_int() {
      return i
    }
  }
  -1
}

///|
fn number(s : String, name : String) -> Int raise Refused {
  if s.length() == 0 {
    raise Malformed(name + " has an empty value")
  }
  let mut out = 0
  for i = 0; i < s.length(); i = i + 1 {
    let d = s[i].to_int()
    if d < 0x30 || d > 0x39 {
      raise Malformed(name + " is not a number: " + s)
    }
    out = out * 10 + (d - 0x30)
  }
  out
}

///|
fn trim(s : String) -> String {
  let mut a = 0
  let mut b = s.length()
  while a < b && (s[a].to_int() == 0x20 || s[a].to_int() == 0x09) {
    a = a + 1
  }
  while b > a && (s[b - 1].to_int() == 0x20 || s[b - 1].to_int() == 0x09) {
    b = b - 1
  }
  s[a:b].to_owned()
}

///|
/// A bit set holding only `v`.
fn bit64(v : Int) -> Int64 {
  1L << v
}

///|
/// Whether `v` is absent from a sixty-four bit set.
fn not64(set : Int64, v : Int) -> Bool {
  ((set >> v) & 1L) == 0L
}

///|
/// Whether `v` is in a thirty-two bit set.
fn has(set : Int, v : Int) -> Bool {
  ((set >> v) & 1) == 1
}
