// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The `%` directive language, the union of C23, POSIX, glibc, Python, Rust chrono
// and C++20 `std::format`. Both directions are here: [`Moment::strftime`] writes a
// moment the way each directive says, and [`strptime`] reads it back.
//
// The modifiers glibc and chrono share — `-` no padding, `_` space padding, `0`
// zero padding, `^` upper case, `#` swap case — work on the directives they make
// sense on, and an optional width sits between the flags and the letter. The two
// C99 locale selectors `E` and `O` are kept for compatibility and behave like the
// plain directive, because this package carries no locale.

///|
/// A moment written by a format string of `%` directives.
///
/// The directives are the ones every Unix knows plus the ones chrono and C++ add;
/// the table below is the whole set. Literal text between directives is copied
/// through untouched, and `%%` is a single per cent sign.
///
/// | | |
/// |:--:|:--|
/// | `%Y` `%C` `%y` | year of four digits, century, two-digit year |
/// | `%G` `%g` | ISO week year, two-digit |
/// | `%m` `%B` `%b` `%h` | month, long and short name |
/// | `%d` `%e` | day of month, zero- and space-padded |
/// | `%j` | day of year, `001` to `366` |
/// | `%U` `%W` `%V` | week of year, Sunday-, Monday-, and ISO-based |
/// | `%u` `%w` | weekday, `1` to `7` and `0` to `6` |
/// | `%a` `%A` | short and long weekday name |
/// | `%q` | quarter of the year, `1` to `4 (chrono) |
/// | `%H` `%k` `%I` `%l` | hour, `00` and ` 0`, twelve-hour `01` and ` 1` |
/// | `%M` `%S` | minute, second |
/// | `%p` `%P` | AM/PM and am/pm |
/// | `%f` `%.f` `%.Nf` `%Nf` `%N` | fractional second, dot or not, N digits or auto |
/// | `%s` | seconds since the epoch |
/// | `%z` `%:z` `%::z` `%:::z` `%#z` `%Ez` `%Oz` | offset, with and without colons |
/// | `%Z` | `UTC`, `UTC±HH:MM` for a fixed offset, or nothing when there is no zone |
/// | `%c` `%x` `%X` `%D` `%F` `%T` `%R` `%r` `%v` `%+` | the composite forms |
/// | `%n` `%t` `%%` | a newline, a tab, a per cent sign |
///
/// A moment with no date writes its date directives as 1 January 1900, as Python's
/// `time.strftime` and C's `struct tm` do, so a bare time still formats.
pub fn Moment::strftime(self : Moment, format : StringView) -> String {
  let (d, t, z, epoch_secs) = decompose(self)
  let f = expand(format.to_owned())
  let out = StringBuilder()
  let mut i = 0
  while i < f.length() {
    guard f[i].to_int() == 0x25 && directive(f, i) is Some((spec, next)) else {
      out.write_char(f[i].unsafe_to_char())
      i = i + 1
      continue
    }
    let start = i
    i = next
    out.write_string(
      write_spec(d, t, z, epoch_secs, spec, f[start:next].to_owned()),
    )
  }
  out.to_string()
}

///|
/// The broken-down pieces a directive needs, and the epoch whether or not the
/// moment names one (a wall clock is read as if it sat at UTC, which is the only
/// deterministic choice a clock-less library can make).
fn decompose(m : Moment) -> (Date, Time, Zone?, Int64) {
  match m {
    Zoned(date~, time~, zone~) => (date, time, Some(zone), unwrap(m.epoch()))
    Plain(date~, time~) => (date, time, None, wall_epoch(date, time))
    Day(date~) => (date, midnight, None, wall_epoch(date, midnight))
    Clock(time~) =>
      (
        { year: 1900, month: 1, day: 1, },
        time,
        None,
        wall_epoch({ year: 1900, month: 1, day: 1, }, time),
      )
  }
}

///|
fn unwrap(x : Int64?) -> Int64 {
  match x {
    Some(v) => v
    None => 0L
  }
}

///|
fn wall_epoch(d : Date, t : Time) -> Int64 {
  d.days().to_int64() * 86400L + t.nanos() / 1_000_000_000L
}

///|
/// One directive's parts: the conversion letter, the flags, the width, and the
/// count of colons on a `%z` form.
priv struct Spec {
  conv : Char
  minus : Bool
  under : Bool
  zero : Bool
  upper : Bool
  swap : Bool
  dot : Bool
  alt : Bool
  width : Int32
  colon : Int32
}

///|
/// The directive that starts at the `%` at `i`, and the index after it; `None` when
/// the format ends before a conversion letter, which is then written as it stands.
fn directive(f : String, i : Int32) -> (Spec, Int32)? {
  let mut k = i + 1
  let mut minus = false
  let mut under = false
  let mut zero = false
  let mut upper = false
  let mut swap = false
  let mut dot = false
  let mut alt = false
  while k < f.length() {
    match f[k].to_int() {
      0x2d => {
        minus = true
        k = k + 1
      } // -
      0x5f => {
        under = true
        k = k + 1
      } // _
      0x30 => {
        zero = true
        k = k + 1
      } // 0
      0x5e => {
        upper = true
        k = k + 1
      } // ^
      0x23 => {
        swap = true
        k = k + 1
      } // #
      0x2e => {
        dot = true
        k = k + 1
      } // .
      0x45 | 0x4f => {
        alt = true
        k = k + 1
      } // E or O
      _ => break
    }
  }
  let start = k
  let mut width = 0
  while k < f.length() && is_digit(f[k].to_int()) {
    width = width * 10 + (f[k].to_int() - 48)
    k = k + 1
  }
  let width = if k == start { -1 } else { width }
  let mut colon = 0
  while k < f.length() && f[k].to_int() == 0x3a {
    colon = colon + 1
    k = k + 1
  }
  guard k < f.length() else { return None }
  Some(
    (
      {
        conv: f[k].unsafe_to_char(),
        minus,
        under,
        zero,
        upper,
        swap,
        dot,
        alt,
        width,
        colon,
      },
      k + 1,
    ),
  )
}

///|
/// `%F` and `%T` are shorthands, as are the composite forms the C locale and chrono
/// name, so they are spelt out once before either direction reads the format;
/// `%%F` stays a per cent sign and an F.
fn expand(f : String) -> String {
  let out = StringBuilder()
  let mut i = 0
  while i < f.length() {
    if f[i].to_int() == 0x25 && i + 1 < f.length() {
      match f[i + 1].unsafe_to_char() {
        'F' => out.write_string("%Y-%m-%d")
        'T' => out.write_string("%H:%M:%S")
        'D' => out.write_string("%m/%d/%y")
        'R' => out.write_string("%H:%M")
        'r' => out.write_string("%I:%M:%S %p")
        'v' => out.write_string("%e-%b-%Y")
        'c' => out.write_string("%a %b %e %H:%M:%S %Y")
        'x' => out.write_string("%m/%d/%y")
        'X' => out.write_string("%H:%M:%S")
        '+' => out.write_string("%Y-%m-%dT%H:%M:%S%.f%:z")
        c => {
          out.write_char('%')
          out.write_char(c)
        }
      }
      i = i + 2
    } else {
      out.write_char(f[i].unsafe_to_char())
      i = i + 1
    }
  }
  out.to_string()
}

///|
/// A number written with the padding and case the directive asked for.
fn render_num(
  spec : Spec,
  value : Int64,
  default_width : Int32,
  default_pad : Char,
) -> String {
  let w = if spec.width > 0 { spec.width } else { default_width }
  let pad = if spec.minus {
    if spec.width > 0 {
      ' '
    } else {
      '\u{0}'
    }
  } else if spec.under {
    ' '
  } else if spec.zero {
    '0'
  } else {
    default_pad
  }
  let s = value.to_string()
  if pad != '\u{0}' {
    let mut out = s
    while out.length() < w {
      out = pad.to_string() + out
    }
    out
  } else {
    s
  }
}

///|
fn render_text(spec : Spec, s : String) -> String {
  if spec.upper {
    s.to_upper()
  } else if spec.swap {
    swap_case(s)
  } else {
    s
  }
}

///|
fn swap_case(s : String) -> String {
  let out = StringBuilder()
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i].unsafe_to_char()
    let u = c.to_int()
    if u >= 0x41 && u <= 0x5a {
      out.write_char((u + 32).unsafe_to_char())
    } else if u >= 0x61 && u <= 0x7a {
      out.write_char((u - 32).unsafe_to_char())
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// The fractional second as a directive asks for it: Python's six digits for a bare
/// `%f`; exactly N digits, truncated, for `%Nf`, with a leading dot for `%.Nf`; and
/// for `%.f` as many as the value needs, three, six or nine, or nothing at all on a
/// whole second, as chrono writes it. `%N` is GNU date's nine-digit nanoseconds.
fn fraction(nano : Int32, spec : Spec) -> String {
  if spec.conv == 'N' {
    let n = if spec.width > 0 && spec.width < 9 { spec.width } else { 9 }
    return pad_nano(nano, n, false)
  }
  if spec.width > 0 {
    let n = if spec.width > 9 { 9 } else { spec.width }
    return pad_nano(nano, n, spec.dot)
  }
  if !spec.dot {
    return pad_nano(nano, 6, false)
  }
  if nano == 0 {
    ""
  } else if nano % 1_000_000 == 0 {
    "." + pad_nano(nano, 3, false)
  } else if nano % 1000 == 0 {
    "." + pad_nano(nano, 6, false)
  } else {
    "." + pad_nano(nano, 9, false)
  }
}

///|
fn pad_nano(nano : Int32, n : Int32, dot : Bool) -> String {
  let scale = power10(9 - n)
  let digits = pad(nano / scale, n)
  if dot {
    "." + digits
  } else {
    digits
  }
}

///|
fn power10(n : Int32) -> Int32 {
  let mut p = 1
  for i = 0; i < n; i = i + 1 {
    p = p * 10
  }
  p
}

///|
/// The offset text for a `%z` form, with the colon count the directive carried.
fn offset_text(minutes : Int32, spec : Spec) -> String {
  let sign = if minutes < 0 { "-" } else { "+" }
  let a = if minutes < 0 { -minutes } else { minutes }
  let hh = a / 60
  let mm = a % 60
  let ss = 0
  if spec.colon == 0 {
    sign + pad(hh, 2) + pad(mm, 2)
  } else if spec.colon == 1 {
    sign + pad(hh, 2) + ":" + pad(mm, 2)
  } else if spec.colon == 2 {
    sign + pad(hh, 2) + ":" + pad(mm, 2) + ":" + pad(ss, 2)
  } else {
    // chrono's `%:::z`: the offset written only as whole hours.
    sign + pad(hh, 2)
  }
}

///|
/// One directive turned into text for the moment it describes. `raw` is the exact
/// text the directive occupied; an unknown directive is written back as it stood.
fn write_spec(
  d : Date,
  t : Time,
  z : Zone?,
  epoch_secs : Int64,
  spec : Spec,
  raw : String,
) -> String {
  let (iso_year, iso_week, iso_day) = d.isocalendar()
  match spec.conv {
    'Y' => year_text(d.year, spec)
    'C' => render_num(spec, (d.year / 100).to_int64(), 2, '0')
    'y' => render_num(spec, (d.year % 100).to_int64(), 2, '0')
    'G' => render_num(spec, iso_year.to_int64(), 4, '0')
    'g' => render_num(spec, (iso_year % 100).to_int64(), 2, '0')
    'm' => render_num(spec, d.month.to_int64(), 2, '0')
    'B' => render_text(spec, long_months[d.month - 1])
    'b' => render_text(spec, months[d.month - 1])
    'h' => render_text(spec, months[d.month - 1])
    'd' => render_num(spec, d.day.to_int64(), 2, '0')
    'e' => render_num(spec, d.day.to_int64(), 2, ' ')
    'j' => render_num(spec, d.yearday().to_int64(), 3, '0')
    'U' => render_num(spec, week_sun(d).to_int64(), 2, '0')
    'W' => render_num(spec, week_mon(d).to_int64(), 2, '0')
    'V' => render_num(spec, iso_week.to_int64(), 2, '0')
    'u' => render_num(spec, iso_day.to_int64(), 1, '0')
    'w' => render_num(spec, d.weekday().to_int64(), 1, '0')
    'a' => render_text(spec, weekdays[d.weekday()])
    'A' => render_text(spec, long_days[d.weekday()])
    'q' => render_num(spec, ((d.month - 1) / 3 + 1).to_int64(), 1, '0')
    'H' => render_num(spec, t.hour.to_int64(), 2, '0')
    'k' => render_num(spec, t.hour.to_int64(), 2, ' ')
    'I' => render_num(spec, hour12(t).to_int64(), 2, '0')
    'l' => render_num(spec, hour12(t).to_int64(), 2, ' ')
    'M' => render_num(spec, t.minute.to_int64(), 2, '0')
    'S' => render_num(spec, t.second.to_int64(), 2, '0')
    'p' => render_text(spec, if t.hour < 12 { "AM" } else { "PM" })
    'P' => render_text(spec, if t.hour < 12 { "am" } else { "pm" })
    'f' => fraction(t.nano, spec)
    'N' => fraction(t.nano, spec)
    's' => epoch_secs.to_string()
    'z' => zone_offset(z, spec)
    'Z' =>
      match z {
        Some(Utc) => "UTC"
        Some(Offset(m)) =>
          if m == 0 {
            "UTC"
          } else {
            let sign = if m < 0 { "-" } else { "+" }
            let a = if m < 0 { -m } else { m }
            "UTC" + sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
          }
        None => ""
      }
    'n' => "\n"
    't' => "\t"
    '%' => "%"
    _ => raw
  }
}

///|
fn year_text(year : Int32, spec : Spec) -> String {
  if year < 0 {
    "-" + render_num(spec, (-year).to_int64(), 4, '0')
  } else {
    render_num(spec, year.to_int64(), 4, '0')
  }
}

///|
fn hour12(t : Time) -> Int32 {
  if t.hour % 12 == 0 {
    12
  } else {
    t.hour % 12
  }
}

///|
fn zone_offset(z : Zone?, spec : Spec) -> String {
  match z {
    None => ""
    Some(Utc) =>
      if spec.conv == 'Z' {
        "UTC"
      } else if spec.colon == 0 {
        "+0000"
      } else if spec.colon == 1 {
        "+00:00"
      } else if spec.colon == 2 {
        "+00:00:00"
      } else {
        "+00"
      }
    Some(Offset(m)) =>
      if spec.conv == 'Z' {
        "UTC"
      } else if m == 0 && spec.alt {
        // chrono's `%#z` writes `Z` for UTC.
        "Z"
      } else {
        offset_text(m, spec)
      }
  }
}

///|
/// The week number with Sunday as the first day, as `%U` writes it.
fn week_sun(d : Date) -> Int32 {
  (d.yearday() - 1 + 7 - d.weekday()) / 7
}

///|
/// The week number with Monday as the first day, as `%W` writes it.
fn week_mon(d : Date) -> Int32 {
  (d.yearday() - 1 + 7 - (d.weekday() + 6) % 7) / 7
}

///|
/// A moment read by a format string of `%` directives.
///
/// The directives are the ones [`Moment::strftime`] writes. Literal characters in
/// the format must match the text exactly, except that whitespace in the format
/// matches any run of whitespace, which is what C's `strptime` does and what makes
/// a format survive a double space.
///
/// The result is `Zoned` when the text carried an offset or a raw `%s`, `Plain`
/// when it carried a date and a time, `Day` when only a date, and `Clock` when only
/// a time — the same four shapes [`parse`] answers with.
pub fn strptime(src : StringView, format : StringView) -> Moment raise Refused {
  let s = src.to_owned()
  let f = expand(format.to_owned())
  let mut year = 1900
  let mut month = 1
  let mut mday = 1
  let mut hour = 0
  let mut minute = 0
  let mut sec = 0
  let mut nano = 0
  let mut offset : Int32? = None
  let mut pm : Bool? = None
  let mut saw_date = false
  let mut saw_time = false
  let mut century : Int32? = None
  let mut iso_year : Int32? = None
  let mut iso_week : Int32? = None
  let mut iso_wd : Int32? = None
  let mut week_mode = 0
  let mut week_num = 0
  let mut week_wd : Int32? = None
  let mut epoch_sec : Int64? = None
  let mut full_year = false
  let mut i = 0
  let mut j = 0
  while i < f.length() {
    let fc = f[i].to_int()
    if fc == 0x20 || fc == 0x09 {
      while j < s.length() && (s[j].to_int() == 0x20 || s[j].to_int() == 0x09) {
        j = j + 1
      }
      i = i + 1
      continue
    }
    if fc != 0x25 {
      if j >= s.length() || s[j].to_int() != fc {
        raise Malformed("text does not match the format at \{j}")
      }
      i = i + 1
      j = j + 1
      continue
    }
    guard directive(f, i) is Some((spec, next)) else {
      raise Malformed("a % at the end of the format")
    }
    i = next
    match spec.conv {
      'Y' => {
        let (v, k) = take(s, j, if spec.width > 0 { spec.width } else { 4 })
        year = v
        full_year = true
        j = k
        saw_date = true
      }
      'y' => {
        let (v, k) = take(s, j, 2)
        year = if v >= 69 { 1900 + v } else { 2000 + v }
        j = k
        saw_date = true
      }
      'C' => {
        let (v, k) = take(s, j, 2)
        century = Some(v)
        j = k
      }
      'g' => {
        let (v, k) = take(s, j, 2)
        iso_year = Some(if v >= 69 { 1900 + v } else { 2000 + v })
        j = k
      }
      'G' => {
        let (v, k) = take(s, j, 4)
        iso_year = Some(v)
        full_year = true
        j = k
        saw_date = true
      }
      'm' => {
        let (v, k) = take(s, j, 2)
        month = v
        j = k
        saw_date = true
      }
      'd' | 'e' => {
        if (spec.conv == 'e' || spec.under || spec.zero == false) &&
          j < s.length() &&
          s[j].to_int() == 0x20 {
          j = j + 1
        }
        let (v, k) = take(s, j, 2)
        mday = v
        j = k
        saw_date = true
      }
      'H' | 'I' | 'k' | 'l' => {
        if (spec.conv == 'k' || spec.conv == 'l' || spec.under) &&
          j < s.length() &&
          s[j].to_int() == 0x20 {
          j = j + 1
        }
        let (v, k) = take(s, j, 2)
        hour = v
        j = k
        saw_time = true
      }
      'M' => {
        let (v, k) = take(s, j, 2)
        minute = v
        j = k
        saw_time = true
      }
      'S' => {
        let (v, k) = take(s, j, 2)
        sec = v
        j = k
        saw_time = true
      }
      'f' | 'N' => {
        saw_time = true
        if spec.dot {
          if j < s.length() && s[j].to_int() == 0x2e {
            j = j + 1
          } else if spec.width < 0 {
            continue
          } else {
            raise Malformed("expected a dot before the fraction at \{j}")
          }
        }
        let most = if spec.width > 0 && spec.width < 9 { spec.width } else { 9 }
        let start = j
        let mut v = 0
        while j < s.length() && is_digit(s[j].to_int()) && j - start < most {
          v = v * 10 + (s[j].to_int() - 48)
          j = j + 1
        }
        if j == start {
          raise Malformed("expected digits for %f at \{start}")
        }
        for k = j - start; k < 9; k = k + 1 {
          v = v * 10
        }
        nano = v
      }
      'p' | 'P' => {
        if j + 2 > s.length() {
          raise Truncated("expected AM, PM, am or pm")
        }
        let word = s[j:j + 2].to_owned().to_upper()
        pm = match word {
          "AM" => Some(false)
          "PM" => Some(true)
          _ => raise Malformed("expected AM/PM at \{j}")
        }
        j = j + 2
      }
      'a' | 'A' => j = skip_name(s, j)
      'b' | 'B' | 'h' => {
        let (m, k) = read_month(s, j)
        month = m
        j = k
        saw_date = true
      }
      'j' => {
        let (v, k) = take(s, j, 3)
        j = k
        let base : Date = { year, month: 1, day: 1, }
        let dd = base.plus_days(v - 1)
        year = dd.year
        month = dd.month
        mday = dd.day
        saw_date = true
      }
      'U' => {
        let (v, k) = take(s, j, 2)
        week_mode = 1
        week_num = v
        j = k
      }
      'W' => {
        let (v, k) = take(s, j, 2)
        week_mode = 2
        week_num = v
        j = k
      }
      'w' => {
        let (v, k) = take(s, j, 1)
        week_wd = Some(if v == 7 { 0 } else { v })
        j = k
      }
      'u' => {
        let (v, k) = take(s, j, 1)
        week_wd = Some(if v == 7 { 0 } else { v })
        iso_wd = Some(v)
        j = k
      }
      'V' => {
        let (v, k) = take(s, j, 2)
        iso_week = Some(v)
        j = k
      }
      's' => {
        let (v, k) = take_int(s, j)
        epoch_sec = Some(v)
        j = k
      }
      'z' => {
        let (o, k) = read_offset(s, j)
        offset = Some(o)
        j = k
      }
      'Z' => j = skip_name(s, j)
      'n' => {
        if j >= s.length() || s[j].to_int() != 0x0a {
          raise Malformed("expected a newline at \{j}")
        }
        j = j + 1
      }
      't' => {
        if j >= s.length() || s[j].to_int() != 0x09 {
          raise Malformed("expected a tab at \{j}")
        }
        j = j + 1
      }
      '%' => {
        if j >= s.length() || s[j].to_int() != 0x25 {
          raise Malformed("expected a per cent sign at \{j}")
        }
        j = j + 1
      }
      other => raise Malformed("unknown directive %" + other.to_string())
    }
  }
  match pm {
    Some(true) => if hour < 12 { hour = hour + 12 }
    Some(false) => if hour == 12 { hour = 0 }
    None => ()
  }
  // A raw `%s` fixes the instant whatever else the format said.
  match epoch_sec {
    Some(secs) => return Moment::of_epoch(secs, zone=Utc)
    None => ()
  }
  // An ISO week date: the week year, the week number and the weekday decide the
  // date, as Python's `_strptime` does when all three are present.
  match (iso_year, iso_week, iso_wd) {
    (Some(y), Some(w), Some(wd)) => {
      let dd = Date::of_isocalendar(y, w, wd)
      year = dd.year
      month = dd.month
      mday = dd.day
      saw_date = true
    }
    _ => ()
  }
  // A Sunday- or Monday-based week number with a weekday decides the date, whatever else was
  // read, which is Python's rule.
  if week_mode != 0 {
    match week_wd {
      Some(wd) => {
        let dd = date_from_week(year, week_num, wd, week_mode)
        year = dd.year
        month = dd.month
        mday = dd.day
        saw_date = true
      }
      None => ()
    }
  }
  // A century without a full year is joined to the two-digit year the format read.
  match century {
    Some(c) => if !full_year { year = c * 100 + year % 100 } else { () }
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
  match offset {
    Some(0) => Zoned(date~, time~, zone=Utc)
    Some(m) => Zoned(date~, time~, zone=Offset(m))
    None => Plain(date~, time~)
  }
}

///|
/// The date a Sunday- or Monday-based week number names, when the weekday is known.
fn date_from_week(
  year : Int32,
  week : Int32,
  wd_sun : Int32,
  mode : Int32,
) -> Date {
  let jan1 = { year, month: 1, day: 1, }.weekday()
  // The days are counted from the week's first day, which is Sunday in mode 1 and Monday otherwise.
  let (first, day) = if mode == 1 {
    (jan1, wd_sun)
  } else {
    ((jan1 + 6) % 7, (wd_sun + 6) % 7)
  }
  let doy = if week == 0 {
    1 + day - first
  } else {
    1 + (7 - first) % 7 + (week - 1) * 7 + day
  }
  { year, month: 1, day: 1, }.plus_days(doy - 1)
}

///|
/// Up to `n` digits at `j`, and where reading stopped.
///
/// Fewer than `n` is allowed when what follows is not a digit, because `%m` reads
/// `1-2-3` the way a person writes it.
fn take(s : String, j : Int32, n : Int32) -> (Int32, Int32) raise Refused {
  let mut v = 0
  let mut k = j
  while k < s.length() && k - j < n && is_digit(s[k].to_int()) {
    v = v * 10 + (s[k].to_int() - 48)
    k = k + 1
  }
  if k == j {
    raise Malformed("expected a digit at \{j}")
  }
  (v, k)
}

///|
/// An integer starting at `j`, and where reading stopped; used for `%s`.
fn take_int(s : String, j : Int32) -> (Int64, Int32) raise Refused {
  let mut k = j
  let mut sign = 1L
  if k < s.length() && (s[k].to_int() == 0x2d || s[k].to_int() == 0x2b) {
    sign = if s[k].to_int() == 0x2d { -1L } else { 1L }
    k = k + 1
  }
  let start = k
  let mut v = 0L
  while k < s.length() && is_digit(s[k].to_int()) {
    v = v * 10L + (s[k].to_int() - 48).to_int64()
    k = k + 1
  }
  if k == start {
    raise Malformed("expected digits for %s at \{j}")
  }
  (sign * v, k)
}

///|
fn is_digit(c : Int32) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
/// Past a run of letters, for a name this parser does not need to keep.
fn skip_name(s : String, j : Int32) -> Int32 {
  let mut k = j
  while k < s.length() {
    let c = s[k].to_int()
    let letter = (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)
    if !letter {
      break
    }
    k = k + 1
  }
  k
}

///|
/// A month name at `j`, long form or short, as its number.
fn read_month(s : String, j : Int32) -> (Int32, Int32) raise Refused {
  let end = skip_name(s, j)
  if end == j {
    raise Malformed("expected a month name at \{j}")
  }
  let word = s[j:end].to_owned()
  for k = 0; k < 12; k = k + 1 {
    if long_months[k] == word {
      return (k + 1, end)
    }
  }
  if word.length() >= 3 {
    let three = word[0:3].to_owned()
    for k = 0; k < 12; k = k + 1 {
      if months[k] == three {
        return (k + 1, j + 3)
      }
    }
  }
  raise Malformed("not a month name: " + word)
}

///|
/// An offset at `j`, as `Z`, `+HHMM`, `+HH:MM`, `+HH:MM:SS`, or the reduced form.
fn read_offset(s : String, j : Int32) -> (Int32, Int32) raise Refused {
  if j < s.length() && (s[j].to_int() == 0x5a || s[j].to_int() == 0x7a) {
    return (0, j + 1)
  }
  if j + 2 > s.length() {
    raise Truncated("an offset")
  }
  let sign = s[j].to_int()
  if sign != 0x2b && sign != 0x2d {
    raise Malformed("an offset begins with a sign at \{j}")
  }
  let (h, a) = take(s, j + 1, 2)
  let b = if a < s.length() && s[a].to_int() == 0x3a { a + 1 } else { a }
  let (m, c) = take(s, b, 2)
  let mut d = c
  if d < s.length() && s[d].to_int() == 0x3a {
    let (_sec, e) = take(s, d + 1, 2)
    d = e
  }
  let total = h * 60 + m
  (if sign == 0x2d { -total } else { total }, d)
}

///|
let long_days : Array[String] = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
]

///|
let long_months : Array[String] = [
  "January", "February", "March", "April", "May", "June", "July", "August", "September",
  "October", "November", "December",
]
