// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Go's reference-time layout language. A layout is a template written with the
// single moment Go chose as its reference — `Mon Jan 2 15:04:05 MST 2006` — where
// every recognisable piece of that reference names a field and everything else is
// a literal. [`Moment::layout`] writes a moment the way the template says;
// [`parse_layout`] reads it back by treating the template as a pattern.

///|
/// A token of a Go layout: either literal text or one of the reference-time fields.
priv enum GKind {
  GLit
  GYear4
  GYear2
  GMonLong
  GMonShort
  GMon2
  GMon1
  GDay2
  GDay1
  GDaySpace
  GDayYear3
  GWDShort
  GWDLong
  GH24
  GH12z
  GH12
  GMin2
  GMin1
  GSec2
  GSec1
  GFrac
  GTZAbbr
  GTZColon
  GTZSign
  GMeridiem
}

///|
priv struct GToken {
  kind : GKind
  text : String
}

///|
/// The predefined layouts Go's `time` package ships with, so a caller need not
/// spell the reference time out by hand.
pub const ANSIC : String = "Mon Jan _2 15:04:05 2006"

///|
pub const UnixDate : String = "Mon Jan _2 15:04:05 MST 2006"

///|
pub const RubyDate : String = "Mon Jan 02 15:04:05 -0700 2006"

///|
pub const RFC822 : String = "02 Jan 06 15:04 MST"

///|
pub const RFC822Z : String = "02 Jan 06 15:04 -0700"

///|
pub const RFC850 : String = "Monday, 02-Jan-06 15:04:05 MST"

///|
pub const RFC1123 : String = "Mon, 02 Jan 2006 15:04:05 MST"

///|
pub const RFC1123Z : String = "Mon, 02 Jan 2006 15:04:05 -0700"

///|
pub const RFC3339 : String = "2006-01-02T15:04:05Z07:00"

///|
pub const RFC3339Nano : String = "2006-01-02T15:04:05.999999999Z07:00"

///|
pub const Kitchen : String = "3:04PM"

///|
pub const Stamp : String = "Jan _2 15:04:05"

///|
pub const StampMilli : String = "Jan _2 15:04:05.000"

///|
pub const StampMicro : String = "Jan _2 15:04:05.000000"

///|
pub const StampNano : String = "Jan _2 15:04:05.000000000"

///|
pub const DateTime : String = "2006-01-02 15:04:05"

///|
pub const DateOnly : String = "2006-01-02"

///|
pub const TimeOnly : String = "15:04:05"

///|
/// A moment written by a Go reference-time layout.
///
/// `Moment::layout(RFC3339)` is `2006-01-02T15:04:05Z07:00` with the fields
/// filled in, which is the same text Go's `time.Format` would write for the same
/// instant. A moment with no zone writes its offset forms as if it sat at UTC, and
/// a bare time or date is padded with 1 January 1900 as `strftime` does.
pub fn Moment::layout(self : Moment, layout : StringView) -> String {
  let (d, t, z, _) = decompose(self)
  let off = match z {
    Some(Utc) => 0
    Some(Offset(m)) => m
    None => 0
  }
  let toks = scan_layout(layout.to_owned())
  let out = StringBuilder()
  for i = 0; i < toks.length(); i = i + 1 {
    out.write_string(render_token(toks[i], d, t, off))
  }
  out.to_string()
}

///|
/// A moment read by a Go reference-time layout.
///
/// The layout is the pattern the text must follow: each field token pulls its
/// value out, and literal characters — including a layout space, which swallows any
/// run of whitespace — must match. A layout that names an offset yields a `Zoned`
/// moment; one that does not yields `Plain`, `Day` or `Clock`, as [`parse`] does.
pub fn parse_layout(
  src : StringView,
  layout : StringView,
) -> Moment raise Refused {
  let s = src.to_owned()
  let toks = scan_layout(layout.to_owned())
  let mut year = 1900
  let mut month = 1
  let mut mday = 1
  let mut hour = 0
  let mut minute = 0
  let mut sec = 0
  let mut nano = 0
  let mut doy : Int32? = None
  let mut pm : Bool? = None
  let mut off : Int32? = None
  let mut full_year = false
  let mut saw_date = false
  let mut saw_time = false
  let mut j = 0
  for i = 0; i < toks.length(); i = i + 1 {
    let tok = toks[i]
    match tok.kind {
      GLit => j = match_lit(s, j, tok.text)
      GYear4 => {
        let (v, k) = take(s, j, 4)
        year = v
        full_year = true
        j = k
        saw_date = true
      }
      GYear2 => {
        let (v, k) = take(s, j, 2)
        year = if v < 69 { 2000 + v } else { 1900 + v }
        j = k
        saw_date = true
      }
      GMonLong | GMonShort => {
        let (m, k) = read_month(s, j)
        month = m
        j = k
        saw_date = true
      }
      GMon2 => {
        let (v, k) = take(s, j, 2)
        month = v
        j = k
        saw_date = true
      }
      GMon1 => {
        let (v, k) = take(s, j, 2)
        month = v
        j = k
        saw_date = true
      }
      GDay2 | GDay1 => {
        let (v, k) = take(s, j, 2)
        mday = v
        j = k
        saw_date = true
      }
      GDaySpace => {
        if j < s.length() && s[j].to_int() == 0x20 {
          j = j + 1
        }
        let (v, k) = take(s, j, 2)
        mday = v
        j = k
        saw_date = true
      }
      GDayYear3 => {
        let (v, k) = take(s, j, 3)
        doy = Some(v)
        j = k
      }
      GWDShort | GWDLong => j = skip_name(s, j)
      GH24 | GH12z | GH12 => {
        let (v, k) = take(s, j, 2)
        hour = v
        j = k
        saw_time = true
      }
      GMin2 | GMin1 => {
        let (v, k) = take(s, j, 2)
        minute = v
        j = k
        saw_time = true
      }
      GSec2 | GSec1 => {
        let (v, k) = take(s, j, 2)
        sec = v
        j = k
        saw_time = true
      }
      GFrac => {
        if j < s.length() && s[j].to_int() == 0x2e {
          j = j + 1
        } else {
          raise Malformed("expected a dot before the fraction at \{j}")
        }
        let p = tok.text.length() - 1
        let start = j
        let mut v = 0
        while j < s.length() && is_digit(s[j].to_int()) && j - start < p {
          v = v * 10 + (s[j].to_int() - 48)
          j = j + 1
        }
        if j == start {
          raise Malformed("expected digits for the fraction at \{start}")
        }
        for k = j - start; k < 9; k = k + 1 {
          v = v * 10
        }
        nano = v
      }
      GTZAbbr => j = skip_name(s, j)
      GTZColon => {
        let (o, k) = read_offset(s, j)
        off = Some(o)
        j = k
      }
      GTZSign => {
        let (o, k) = read_offset(s, j)
        off = Some(o)
        j = k
      }
      GMeridiem => {
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
    }
  }
  match pm {
    Some(true) => if hour < 12 { hour = hour + 12 }
    Some(false) => if hour == 12 { hour = 0 }
    None => ()
  }
  match (doy, full_year) {
    (Some(v), true) => {
      let base = { year, month: 1, day: 1, }
      let dd = base.plus_days(v - 1)
      year = dd.year
      month = dd.month
      mday = dd.day
      saw_date = true
    }
    _ => ()
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
/// One field token turned into text for the moment it describes. `off` is the
/// offset in minutes, taken as zero when the moment names no zone.
fn render_token(tok : GToken, d : Date, t : Time, off : Int32) -> String {
  match tok.kind {
    GLit => tok.text
    GYear4 => year_field(d.year, 4)
    GYear2 => pad((d.year % 100 + 100) % 100, 2)
    GMonLong => long_months[d.month - 1]
    GMonShort => months[d.month - 1]
    GMon2 => pad(d.month, 2)
    GMon1 => d.month.to_string()
    GDay2 => pad(d.day, 2)
    GDay1 => d.day.to_string()
    GDaySpace =>
      if d.day < 10 {
        " " + d.day.to_string()
      } else {
        d.day.to_string()
      }
    GDayYear3 => pad(d.yearday(), 3)
    GWDShort => weekdays[d.weekday()]
    GWDLong => long_days[d.weekday()]
    GH24 => pad(t.hour, 2)
    GH12z => pad(hour12(t), 2)
    GH12 => hour12(t).to_string()
    GMin2 => pad(t.minute, 2)
    GMin1 => t.minute.to_string()
    GSec2 => pad(t.second, 2)
    GSec1 => t.second.to_string()
    GFrac => frac_text(t.nano, tok.text)
    GTZAbbr =>
      if off == 0 {
        "UTC"
      } else {
        // No zone database: the name a fixed offset carries here is `±HH:MM`.
        let sign = if off < 0 { "-" } else { "+" }
        let a = if off < 0 { -off } else { off }
        sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
      }
    GTZColon => if off == 0 { "Z" } else { offset_pattern(off, tok.text) }
    GTZSign => offset_pattern(off, tok.text)
    GMeridiem => {
      let upper = tok.text[0].to_int() == 0x50 || tok.text[0].to_int() == 0x41
      if t.hour >= 12 {
        if upper {
          "PM"
        } else {
          "pm"
        }
      } else if upper {
        "AM"
      } else {
        "am"
      }
    }
  }
}

///|
/// A year written with `width` digits, with a leading minus for a negative year.
fn year_field(year : Int32, width : Int32) -> String {
  if year < 0 {
    "-" + pad(-year, width)
  } else {
    pad(year, width)
  }
}

///|
/// The fractional second Go's `.999…` or `.000…` asks for.
fn frac_text(nano : Int32, text : String) -> String {
  let p = text.length() - 1
  let scale = power10(9 - p)
  let first = nano / scale
  let digits = pad(first, p)
  // A token of nines drops trailing zeros, and the whole fractional part when the
  // value is a whole second; a token of zeros always keeps its width.
  if text[1].to_int() == 0x30 {
    "." + digits
  } else {
    let mut s = digits
    while s.length() > 0 && s[s.length() - 1].to_int() == 48 {
      s = s[0:s.length() - 1].to_owned()
    }
    if s.length() == 0 {
      ""
    } else {
      "." + s
    }
  }
}

///|
/// An offset written the way a `Z` form or a sign form asks: `Z` for zero on a `Z`
/// form, otherwise the sign and the hours, minutes and seconds the pattern names.
fn offset_pattern(off : Int32, text : String) -> String {
  let sign = if off < 0 { "-" } else { "+" }
  let a = if off < 0 { -off } else { off }
  let hh = a / 60
  let mm = a % 60
  let ss = 0
  // The pattern after the leading `Z` or sign: digit groups with optional colons.
  let colons = count_char(text, 0x3a)
  let mut digits = 0
  for k = 0; k < text.length(); k = k + 1 {
    if is_digit(text[k].to_int()) {
      digits = digits + 1
    }
  }
  if colons == 0 {
    if digits <= 2 {
      sign + pad(hh, 2)
    } else if digits <= 4 {
      sign + pad(hh, 2) + pad(mm, 2)
    } else {
      sign + pad(hh, 2) + pad(mm, 2) + pad(ss, 2)
    }
  } else if colons == 1 {
    sign + pad(hh, 2) + ":" + pad(mm, 2)
  } else {
    sign + pad(hh, 2) + ":" + pad(mm, 2) + ":" + pad(ss, 2)
  }
}

///|
fn count_char(s : String, c : Int32) -> Int32 {
  let mut n = 0
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == c {
      n = n + 1
    }
  }
  n
}

///|
/// The layout split into tokens, longest field match first so `15` wins over `1`.
fn scan_layout(layout : String) -> Array[GToken] {
  let toks = []
  let mut i = 0
  while i < layout.length() {
    let (tok, next) = scan_token(layout, i)
    toks.push(tok)
    i = next
  }
  toks
}

///|
/// The token that starts at `i`, and where the layout continues after it.
fn scan_token(layout : String, i : Int32) -> (GToken, Int32) {
  if layout[i].to_int() == 0x2e {
    let mut k = i + 1
    while k < layout.length() {
      let c = layout[k].to_int()
      if c == 0x39 || c == 0x30 {
        k = k + 1
      } else {
        break
      }
    }
    if k > i + 1 {
      return ({ kind: GFrac, text: layout[i:k].to_owned(), }, k)
    }
  }
  let candidates : Array[(String, GKind)] = [
    ("Monday", GWDLong),
    ("January", GMonLong),
    ("Z07:00:00", GTZColon),
    ("Z070000", GTZColon),
    ("Z07:00", GTZColon),
    ("Z0700", GTZColon),
    ("Z07", GTZColon),
    ("-07:00:00", GTZSign),
    ("-070000", GTZSign),
    ("-07:00", GTZSign),
    ("-0700", GTZSign),
    ("-07", GTZSign),
    ("2006", GYear4),
    ("Mon", GWDShort),
    ("Jan", GMonShort),
    ("MST", GTZAbbr),
    ("002", GDayYear3),
    ("06", GYear2),
    ("01", GMon2),
    ("02", GDay2),
    ("15", GH24),
    ("03", GH12z),
    ("PM", GMeridiem),
    ("pm", GMeridiem),
    ("AM", GMeridiem),
    ("am", GMeridiem),
    ("_2", GDaySpace),
    ("04", GMin2),
    ("05", GSec2),
    ("1", GMon1),
    ("2", GDay1),
    ("3", GH12),
    ("4", GMin1),
    ("5", GSec1),
  ]
  for c = 0; c < candidates.length(); c = c + 1 {
    let (s, knd) = candidates[c]
    if starts_at(layout, i, s) {
      return ({ kind: knd, text: s, }, i + s.length())
    }
  }
  ({ kind: GLit, text: layout[i:i + 1].to_owned(), }, i + 1)
}

///|
fn starts_at(layout : String, i : Int32, s : String) -> Bool {
  if i + s.length() > layout.length() {
    return false
  }
  for k = 0; k < s.length(); k = k + 1 {
    if layout[i + k].to_int() != s[k].to_int() {
      return false
    }
  }
  true
}

///|
/// A literal run matched, with a single space swallowing any run of whitespace.
fn match_lit(s : String, j : Int32, text : String) -> Int32 raise Refused {
  let mut k = j
  for c = 0; c < text.length(); c = c + 1 {
    let ch = text[c].to_int()
    if ch == 0x20 {
      while k < s.length() && s[k].to_int() == 0x20 {
        k = k + 1
      }
    } else {
      if k >= s.length() || s[k].to_int() != ch {
        raise Malformed("text does not match the layout at \{k}")
      }
      k = k + 1
    }
  }
  k
}
