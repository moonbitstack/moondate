// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Unicode LDML date patterns, the language ICU, `Intl`, Java, date-fns and dayjs
// all speak: a run of a pattern letter names a field and its length picks the
// width, and text inside single quotes is copied through. [`Moment::pattern`]
// writes a moment the way a pattern says; [`parse_pattern`] reads it back.
//
// The letters are the ones UTS #35 Part 4 §8 defines, in English. A locale with a
// zone database would name a zone; this package has none, so the offset-based
// letters fall back to the `GMT±HH:MM` spelling, which is what babel and ICU do
// for a zone they only know by its offset.

///|
/// One piece of a pattern: either literal text or a run of a single pattern letter.
priv struct PToken {
  is_lit : Bool
  lit : String
  letter : Char
  count : Int32
}

///|
/// A moment written by an LDML date pattern.
///
/// `pattern("yyyy-MM-dd")` is the calendar date, `pattern("EEEE, MMMM d, yyyy")`
/// is `Tuesday, September 22, 2026`, and text in single quotes is literal, so
/// `pattern("yyyy-MM-dd'T'HH:mm:ss")` writes an ISO-style timestamp.
pub fn Moment::pattern(self : Moment, pattern : StringView) -> String {
  let (d, t, z, _) = decompose(self)
  let off = match z {
    Some(Utc) => 0
    Some(Offset(m)) => m
    None => 0
  }
  let toks = scan_pattern(pattern.to_owned())
  let out = StringBuilder()
  for i = 0; i < toks.length(); i = i + 1 {
    write_ptoken(out, toks[i], d, t, off)
  }
  out.to_string()
}

///|
/// A moment read by an LDML date pattern.
///
/// The inverse of [`Moment::pattern`] for the field letters that carry a value:
/// years, months (numeric or named), days, hours, minutes, seconds, fractions and
/// zone offsets. A pattern that names an offset yields `Zoned`; one that does not
/// yields `Plain`, `Day` or `Clock`.
pub fn parse_pattern(
  src : StringView,
  pattern : StringView,
) -> Moment raise Refused {
  let s = src.to_owned()
  let toks = scan_pattern(pattern.to_owned())
  let mut year = 1900
  let mut month = 1
  let mut mday = 1
  let mut hour = 0
  let mut minute = 0
  let mut sec = 0
  let mut nano = 0
  let mut pm : Bool? = None
  let mut off : Int32? = None
  let mut doy : Int32? = None
  let mut week_year_value : Int32? = None
  let mut week_value : Int32? = None
  let mut weekday_value : Int32? = None
  let mut saw_date = false
  let mut saw_time = false
  let mut j = 0
  for i = 0; i < toks.length(); i = i + 1 {
    let tok = toks[i]
    if tok.is_lit {
      j = plit(s, j, tok.lit)
      continue
    }
    let letter = tok.letter
    let count = tok.count
    match letter {
      'G' => j = skip_name(s, j)
      'y' | 'u' => {
        let n = if count == 2 { 2 } else { 4 }
        let (v, k) = take(s, j, n)
        year = if count == 2 && v < 69 {
          2000 + v
        } else if count == 2 {
          1900 + v
        } else {
          v
        }
        j = k
        saw_date = true
      }
      'Y' => {
        let (v, k) = take(s, j, if count == 2 { 2 } else { 4 })
        week_year_value = Some(
          if count == 2 && v < 69 {
            2000 + v
          } else if count == 2 {
            1900 + v
          } else {
            v
          },
        )
        j = k
      }
      'M' | 'L' => {
        if count <= 2 {
          let (v, k) = take(s, j, 2)
          month = v
          j = k
        } else {
          let (m, k) = read_month(s, j)
          month = m
          j = k
        }
        saw_date = true
      }
      'Q' | 'q' => j = skip_digits_or_name(s, j)
      'd' => {
        let (v, k) = take(s, j, 2)
        mday = v
        j = k
        saw_date = true
      }
      'D' => {
        // A day of the year, one to three digits, which decides the date once the
        // year is known.
        let (v, k) = take(s, j, 3)
        doy = Some(v)
        j = k
      }
      'w' => {
        let (v, k) = take(s, j, 2)
        week_value = Some(v)
        j = k
      }
      'F' | 'W' => j = skip_digits_or_name(s, j)
      // `E` is a name at every width; `e` and `c` are a number until the third
      // letter, where they turn into the same names.
      'E' => j = skip_name(s, j)
      'e' | 'c' =>
        if count >= 3 {
          j = skip_name(s, j)
        } else {
          let (v, k) = take(s, j, if count == 2 { 2 } else { 1 })
          weekday_value = Some(v)
          j = k
        }
      'a' => {
        if j + 2 > s.length() {
          raise Truncated("expected AM or PM")
        }
        let word = s[j:j + 2].to_owned().to_upper()
        pm = match word {
          "AM" => Some(false)
          "PM" => Some(true)
          _ => raise Malformed("expected AM or PM at \{j}")
        }
        j = j + 2
      }
      'h' | 'K' => {
        let (v, k) = take(s, j, 2)
        hour = v
        j = k
        saw_time = true
      }
      'H' | 'k' => {
        let (v, k) = take(s, j, 2)
        hour = if letter == 'k' && v == 24 { 0 } else { v }
        j = k
        saw_time = true
      }
      'm' => {
        let (v, k) = take(s, j, 2)
        minute = v
        j = k
        saw_time = true
      }
      's' => {
        let (v, k) = take(s, j, 2)
        sec = v
        j = k
        saw_time = true
      }
      'S' => {
        let most = if count > 9 { 9 } else { count }
        let start = j
        let mut v = 0
        while j < s.length() && is_digit(s[j].to_int()) && j - start < most {
          v = v * 10 + (s[j].to_int() - 48)
          j = j + 1
        }
        if j == start {
          raise Malformed("expected a fraction at \{start}")
        }
        for k = j - start; k < 9; k = k + 1 {
          v = v * 10
        }
        nano = v
        saw_time = true
      }
      'A' => j = skip_digits_or_name(s, j)
      'b' | 'B' => j = skip_words(s, j)
      'z' | 'Z' | 'O' | 'v' | 'V' | 'X' | 'x' => {
        // Long forms prefix the offset with `GMT`; skip it before the sign.
        if j + 3 <= s.length() && s[j:j + 3].to_owned() == "GMT" {
          j = j + 3
        }
        let (o, k) = read_offset(s, j)
        off = Some(o)
        j = k
      }
      _ => ()
    }
  }
  match pm {
    Some(true) => if hour < 12 { hour = hour + 12 }
    Some(false) => if hour == 12 { hour = 0 }
    None => ()
  }
  // A week date — the week year, the week and a weekday — decides the date, and a
  // day of the year does so once the year is known. Both are what `Y`/`w`/`e` and
  // `D` write, so a pattern that carries them reads back.
  match (week_year_value, week_value, weekday_value) {
    (Some(y), Some(w), Some(wd)) => {
      let first = week_start({ year: y, month: 1, day: 1, })
      let dd = first.plus_days((w - 1) * 7 + (wd - 1))
      year = dd.year
      month = dd.month
      mday = dd.day
      saw_date = true
    }
    _ => ()
  }
  match doy {
    Some(v) => {
      let dd = { year, month: 1, day: 1, }.plus_days(v - 1)
      year = dd.year
      month = dd.month
      mday = dd.day
      saw_date = true
    }
    None => ()
  }
  let time = Time::new(hour, minute, second=sec, nano~)
  if !saw_date {
    return Clock(time~)
  }
  let date = Date::new(year, month, mday)
  if !saw_time {
    return Day(date~)
  }
  match off {
    Some(0) => Zoned(date~, time~, zone=Utc)
    Some(m) => Zoned(date~, time~, zone=Offset(m))
    None => Plain(date~, time~)
  }
}

///|
fn write_ptoken(
  out : StringBuilder,
  tok : PToken,
  d : Date,
  t : Time,
  off : Int32,
) -> Unit {
  if tok.is_lit {
    out.write_string(tok.lit)
    return
  }
  let count = tok.count
  let wd = d.weekday()
  let q = (d.month - 1) / 3 + 1
  match tok.letter {
    'G' =>
      if count <= 3 {
        out.write_string("AD")
      } else if count == 4 {
        out.write_string("Anno Domini")
      } else {
        out.write_string("A")
      }
    'y' => out.write_string(year_digits(d.year, count))
    'Y' => out.write_string(year_digits(week_year(d).0, count))
    'u' => out.write_string(year_digits(d.year, count))
    'Q' | 'q' =>
      if count == 1 {
        out.write_string(q.to_string())
      } else if count == 2 {
        out.write_string(pad(q, 2))
      } else if count == 3 {
        out.write_string("Q" + q.to_string())
      } else if count == 4 {
        out.write_string(ordinal(q) + " quarter")
      } else {
        out.write_string(q.to_string())
      }
    'M' | 'L' =>
      if count == 1 {
        out.write_string(d.month.to_string())
      } else if count == 2 {
        out.write_string(pad(d.month, 2))
      } else if count == 3 {
        out.write_string(months[d.month - 1])
      } else if count == 4 {
        out.write_string(long_months[d.month - 1])
      } else {
        out.write_string(first_chars(long_months[d.month - 1], 1))
      }
    'w' => out.write_string(pad(week_year(d).1, count))
    'W' => out.write_string(pad(week_of_month(d), count))
    'd' => out.write_string(pad(d.day, count))
    'D' => out.write_string(pad(d.yearday(), count))
    'F' => out.write_string(pad((d.day - 1) / 7 + 1, count))
    'E' =>
      if count <= 3 {
        out.write_string(weekdays[wd])
      } else if count == 4 {
        out.write_string(long_days[wd])
      } else if count == 5 {
        out.write_string(first_chars(long_days[wd], 1))
      } else {
        out.write_string(first_chars(long_days[wd], 2))
      }
    'e' | 'c' =>
      if count == 1 {
        out.write_string(d.isoweekday().to_string())
      } else if count == 2 {
        out.write_string(pad(d.isoweekday(), 2))
      } else if count == 3 {
        out.write_string(weekdays[wd])
      } else if count == 4 {
        out.write_string(long_days[wd])
      } else if count == 5 {
        out.write_string(first_chars(long_days[wd], 1))
      } else {
        out.write_string(first_chars(long_days[wd], 2))
      }
    'a' =>
      if count >= 5 {
        out.write_string(if t.hour < 12 { "a" } else { "p" })
      } else {
        out.write_string(if t.hour < 12 { "AM" } else { "PM" })
      }
    'b' => out.write_string(day_period(t, false, false))
    'B' => out.write_string(day_period(t, true, count >= 5))
    'h' => out.write_string(pad(hour12(t), count))
    'H' => out.write_string(pad(t.hour, count))
    'K' => out.write_string(pad(t.hour % 12, count))
    'k' => out.write_string(pad(if t.hour == 0 { 24 } else { t.hour }, count))
    'm' => out.write_string(pad(t.minute, count))
    's' => out.write_string(pad(t.second, count))
    'S' => out.write_string(frac_digits(t.nano, count))
    'A' =>
      out.write_string(
        pad(
          (t.hour * 3600 + t.minute * 60 + t.second) * 1000 + t.nano / 1_000_000,
          count,
        ),
      )
    'z' => out.write_string(zone_z(off, count))
    'Z' => out.write_string(zone_Z(off, count))
    'O' => out.write_string(zone_O(off, count))
    'v' | 'V' => out.write_string(zone_z(off, count))
    'X' => out.write_string(zone_X(off, count, false))
    'x' => out.write_string(zone_X(off, count, true))
    other =>
      for fi = 0; fi < count; fi = fi + 1 {
        out.write_char(other)
      }
  }
}

///|
/// A year laid out by an LDML `y`/`Y`/`u` pattern: two digits when the count is
/// two, otherwise at least `count` digits.
fn year_digits(year : Int32, count : Int32) -> String {
  if count == 2 {
    return pad((year % 100 + 100) % 100, 2)
  }
  let width = if count < 1 { 1 } else { count }
  if year < 0 {
    "-" + pad(-year, width)
  } else {
    pad(year, width)
  }
}

///|
/// The week year and the week of it: a week starts on Monday and the first week is
/// the one that holds 1 January, which UTS #35 calls a first day of Monday and one
/// minimal day. A day in the last days of December can therefore belong to week 1
/// of the next year, and the pair [`write_ptoken`] uses for `Y` and `w` stays
/// consistent.
fn week_year(d : Date) -> (Int32, Int32) {
  let mut year = d.year
  let mut first = week_start({ year, month: 1, day: 1, })
  if d.days() < first.days() {
    year = year - 1
    first = week_start({ year, month: 1, day: 1, })
  } else {
    let next = week_start({ year: year + 1, month: 1, day: 1, })
    if d.days() >= next.days() {
      year = year + 1
      first = next
    }
  }
  (year, (d.days() - first.days()) / 7 + 1)
}

///|
/// The Monday on or before 1 January, which is where the first week begins.
fn week_start(jan1 : Date) -> Date {
  jan1.plus_days(-((jan1.weekday() + 6) % 7))
}

///|
fn week_of_month(d : Date) -> Int32 {
  let first = { year: d.year, month: d.month, day: 1, }
  let offset = (first.weekday() + 6) % 7
  (d.day - 1 + offset) / 7 + 1
}

///|
/// The day period of a clock: the short form, which `b` writes, or the long one,
/// which `B` writes. Midnight and noon have names of their own in both widths, and
/// English carries no separate narrow form, so a fifth letter gives what the fourth
/// does — except for those two, whose narrow forms are `mi` and `n`.
fn day_period(t : Time, long : Bool, narrow : Bool) -> String {
  if t.minute == 0 && t.second == 0 && (t.hour == 0 || t.hour == 12) {
    let name = if t.hour == 0 { "midnight" } else { "noon" }
    if narrow {
      return if t.hour == 0 { "mi" } else { "n" }
    }
    return name
  }
  let (short, wide) = if t.hour < 6 {
    ("night", "at night")
  } else if t.hour < 12 {
    ("morning", "in the morning")
  } else if t.hour < 18 {
    ("afternoon", "in the afternoon")
  } else if t.hour < 21 {
    ("evening", "in the evening")
  } else {
    ("night", "at night")
  }
  if long {
    wide
  } else {
    short
  }
}

///|
/// The first `n` characters of a name, for the narrow and short widths.
fn first_chars(s : String, n : Int32) -> String {
  let mut k = if n > s.length() { s.length() } else { n }
  if k < 0 {
    k = 0
  }
  s[0:k].to_owned()
}

///|
/// The fractional second as `count` digits, truncated from the nine-digit
/// nanoseconds, right-padded with zeros past nine.
fn frac_digits(nano : Int32, count : Int32) -> String {
  let full = pad(nano, 9)
  if count <= 9 {
    return full[0:count].to_owned()
  }
  let out = StringBuilder()
  out.write_string(full)
  for fi = 9; fi < count; fi = fi + 1 {
    out.write_char('0')
  }
  out.to_string()
}

///|
fn ordinal(n : Int32) -> String {
  let suffix = if n % 100 == 11 || n % 100 == 12 || n % 100 == 13 {
    "th"
  } else {
    match n % 10 {
      1 => "st"
      2 => "nd"
      3 => "rd"
      _ => "th"
    }
  }
  n.to_string() + suffix
}

///|
/// `z`: a short zone name, or the offset; the long form spells `GMT±HH:MM` out.
fn zone_z(off : Int32, count : Int32) -> String {
  if count >= 4 {
    if off == 0 {
      "Coordinated Universal Time"
    } else {
      "GMT" + offset_colon(off)
    }
  } else if off == 0 {
    "UTC"
  } else {
    offset_plain(off, false)
  }
}

///|
/// `Z`: `±HHMM`, `GMT±HH:MM`, or `Z`/`±HH:MM` for the five-letter form.
fn zone_Z(off : Int32, count : Int32) -> String {
  if count >= 5 {
    if off == 0 {
      "Z"
    } else {
      offset_colon(off)
    }
  } else if count == 4 {
    "GMT" + offset_colon(off)
  } else {
    offset_plain(off, false)
  }
}

///|
/// `O`: `GMT±H` or `GMT±HH:MM`.
fn zone_O(off : Int32, count : Int32) -> String {
  if count >= 4 {
    "GMT" + offset_colon(off)
  } else {
    let sign = if off < 0 { "-" } else { "+" }
    let a = if off < 0 { -off } else { off }
    "GMT" + sign + (a / 60).to_string()
  }
}

///|
/// `X` and `x`: the ISO 8601 offset. The upper-case `X` writes `Z` at UTC; the
/// lower-case `x` writes the zero offset out. `minus` selects the lower form.
fn zone_X(off : Int32, count : Int32, minus : Bool) -> String {
  let a = if off < 0 { -off } else { off }
  let hh = a / 60
  let mm = a % 60
  if off == 0 && !minus {
    return "Z"
  }
  let sign = if off < 0 { "-" } else { "+" }
  if count == 1 {
    if mm == 0 {
      sign + pad(hh, 2)
    } else {
      sign + pad(hh, 2) + pad(mm, 2)
    }
  } else if count == 2 || count == 4 {
    sign + pad(hh, 2) + pad(mm, 2)
  } else {
    sign + pad(hh, 2) + ":" + pad(mm, 2)
  }
}

///|
/// `±HHMM`.
fn offset_plain(off : Int32, _with_seconds : Bool) -> String {
  let sign = if off < 0 { "-" } else { "+" }
  let a = if off < 0 { -off } else { off }
  sign + pad(a / 60, 2) + pad(a % 60, 2)
}

///|
/// `±HH:MM`.
fn offset_colon(off : Int32) -> String {
  let sign = if off < 0 { "-" } else { "+" }
  let a = if off < 0 { -off } else { off }
  sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
}

///|
/// A pattern split into literal runs and single-letter runs, with quoting applied.
fn scan_pattern(pattern : String) -> Array[PToken] {
  let toks = []
  let mut i = 0
  while i < pattern.length() {
    let c = pattern[i].to_int()
    if c == 0x27 {
      // A quoted run: `''` is one quote, anything else is literal.
      let run = StringBuilder()
      i = i + 1
      while i < pattern.length() && pattern[i].to_int() != 0x27 {
        run.write_char(pattern[i].unsafe_to_char())
        i = i + 1
      }
      if i < pattern.length() {
        i = i + 1
      }
      toks.push({ is_lit: true, lit: run.to_string(), letter: ' ', count: 0, })
    } else if is_letter(c) {
      let letter = pattern[i].unsafe_to_char()
      let mut k = i + 1
      while k < pattern.length() && pattern[k].to_int() == c {
        k = k + 1
      }
      toks.push({ is_lit: false, lit: "", letter, count: k - i, })
      i = k
    } else {
      let run = StringBuilder()
      while i < pattern.length() &&
            !is_letter(pattern[i].to_int()) &&
            pattern[i].to_int() != 0x27 {
        run.write_char(pattern[i].unsafe_to_char())
        i = i + 1
      }
      toks.push({ is_lit: true, lit: run.to_string(), letter: ' ', count: 0, })
    }
  }
  toks
}

///|
fn is_letter(c : Int32) -> Bool {
  (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)
}

///|
/// A literal run matched, with a space swallowing a run of any whitespace.
fn plit(s : String, j : Int32, text : String) -> Int32 raise Refused {
  let mut k = j
  for c = 0; c < text.length(); c = c + 1 {
    let ch = text[c].to_int()
    if ch == 0x20 {
      while k < s.length() && s[k].to_int() == 0x20 {
        k = k + 1
      }
    } else {
      if k >= s.length() || s[k].to_int() != ch {
        raise Malformed("text does not match the pattern at \{k}")
      }
      k = k + 1
    }
  }
  k
}

///|
/// Past a day period, which is one word in the short form and two or three in the
/// long one (`in the afternoon`, `at night`).
fn skip_words(s : String, j : Int32) -> Int32 {
  let mut k = skip_name(s, j)
  let mut words = 1
  while words < 3 &&
        k + 1 < s.length() &&
        s[k].to_int() == 0x20 &&
        is_letter(s[k + 1].to_int()) {
    k = skip_name(s, k + 1)
    words = words + 1
  }
  k
}

///|
/// Past either digits or a name, for a field this reader does not keep.
fn skip_digits_or_name(s : String, j : Int32) -> Int32 {
  let mut k = j
  while k < s.length() && is_digit(s[k].to_int()) {
    k = k + 1
  }
  if k > j {
    return k
  }
  skip_name(s, j)
}
