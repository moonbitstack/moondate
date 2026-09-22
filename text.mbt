// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A moment read from RFC 3339 text, in whichever of the four shapes it is written.
///
/// `2026-09-22T14:30:00Z` and `…+08:00` are `Zoned`; without an offset it is
/// `Plain`; a bare `2026-09-22` is `Day` and a bare `14:30:00` is `Clock`. TOML
/// 1.0.0 names these four and allows a space in place of the `T`, which is what a
/// person writes; RFC 3339 §5.6 allows it too, under NOTE.
pub fn parse(src : StringView) -> Moment raise Refused {
  let s = src.to_owned()
  // A bare time has a colon where a date would have a dash.
  if s.length() >= 5 && at(s, 2) == ':' {
    return Clock(time=time_of(s, 0, s.length()))
  }
  if s.length() < 10 {
    raise Truncated("a date needs ten characters")
  }
  let date = date_of(s, 0)
  if s.length() == 10 {
    return Day(date~)
  }
  let sep = at(s, 10)
  if sep != 'T' && sep != 't' && sep != ' ' {
    raise Malformed("a date and a time are joined by T or a space")
  }
  // The zone, if any, begins at the first Z or at a sign that is not part of the
  // time — which is any sign at all, since the time itself carries none.
  let mut cut = s.length()
  for i = 11; i < s.length(); i = i + 1 {
    let c = at(s, i)
    if c == 'Z' || c == 'z' || c == '+' || c == '-' {
      cut = i
      break
    }
  }
  let time = time_of(s, 11, cut)
  if cut == s.length() {
    return Plain(date~, time~)
  }
  Zoned(date~, time~, zone=zone_of(s, cut))
}

///|
/// The ten characters `YYYY-MM-DD` at `from`.
fn date_of(s : String, from : Int) -> Date raise Refused {
  if at(s, from + 4) != '-' || at(s, from + 7) != '-' {
    raise Malformed("a date is YYYY-MM-DD")
  }
  Date::new(digits(s, from, 4), digits(s, from + 5, 2), digits(s, from + 8, 2))
}

///|
/// `HH:MM`, `HH:MM:SS` or `HH:MM:SS.fff…` between `from` and `end`.
///
/// RFC 3339 requires the seconds; TOML's local time allows them to be left off, and
/// so does ISO 8601, so they are optional here.
fn time_of(s : String, from : Int, end : Int) -> Time raise Refused {
  if end - from < 5 || at(s, from + 2) != ':' {
    raise Malformed("a time is HH:MM[:SS[.fff]]")
  }
  let hour = digits(s, from, 2)
  let minute = digits(s, from + 3, 2)
  if end - from == 5 {
    return Time::new(hour, minute)
  }
  if at(s, from + 5) != ':' {
    raise Malformed("a time is HH:MM[:SS[.fff]]")
  }
  let second = digits(s, from + 6, 2)
  if end - from == 8 {
    return Time::new(hour, minute, second~)
  }
  if at(s, from + 8) != '.' {
    raise Malformed("a fraction of a second begins with a dot")
  }
  // Nine digits is a nanosecond; more are read and dropped, which is what every
  // parser does with a precision it cannot hold.
  let mut nano = 0
  let mut seen = 0
  for i = from + 9; i < end; i = i + 1 {
    let d = digit(s, i)
    if seen < 9 {
      nano = nano * 10 + d
      seen = seen + 1
    }
  }
  if seen == 0 {
    raise Malformed("a dot with no digits after it")
  }
  for i = seen; i < 9; i = i + 1 {
    nano = nano * 10
  }
  Time::new(hour, minute, second~, nano~)
}

///|
/// `Z`, `+HH:MM` or `-HH:MM` at `from`.
fn zone_of(s : String, from : Int) -> Zone raise Refused {
  let c = at(s, from)
  if c == 'Z' || c == 'z' {
    if s.length() != from + 1 {
      raise Malformed("trailing characters after Z")
    }
    return Utc
  }
  if s.length() - from != 6 || at(s, from + 3) != ':' {
    raise Malformed("an offset is +HH:MM or -HH:MM")
  }
  let hours = digits(s, from + 1, 2)
  let minutes = digits(s, from + 4, 2)
  if hours > 23 {
    raise Range(field="offset hour", got=hours, low=0, high=23)
  }
  if minutes > 59 {
    raise Range(field="offset minute", got=minutes, low=0, high=59)
  }
  let total = hours * 60 + minutes
  Offset(if c == '-' { -total } else { total })
}

///|
/// The character at `i`, or a space past the end so a caller's comparison fails
/// rather than reading out of bounds.
fn at(s : String, i : Int) -> Char {
  if i >= 0 && i < s.length() {
    s[i].unsafe_to_char()
  } else {
    ' '
  }
}

///|
/// One digit at `i`.
fn digit(s : String, i : Int) -> Int raise Refused {
  let c = at(s, i)
  if c < '0' || c > '9' {
    raise Malformed("expected a digit at \{i}")
  }
  c.to_int() - 48
}

///|
/// `n` digits starting at `from`, as the number they spell.
fn digits(s : String, from : Int, n : Int) -> Int raise Refused {
  let mut out = 0
  for i = 0; i < n; i = i + 1 {
    out = out * 10 + digit(s, from + i)
  }
  out
}

// -- writing ------------------------------------------------------------------

///|
/// A moment as RFC 3339 text, in the shape it is.
///
/// This is the inverse of [`parse`] and the form TOML writes, so a document read
/// and written again carries the same timestamps.
pub impl Show for Moment with fn output(self, logger) {
  logger.write_string(
    match self {
      Zoned(date~, time~, zone~) =>
        text_of(date) + "T" + text_of_time(time) + text_of_zone(zone)
      Plain(date~, time~) => text_of(date) + "T" + text_of_time(time)
      Day(date~) => text_of(date)
      Clock(time~) => text_of_time(time)
    },
  )
}

///|
pub extend Moment with Show::{to_string, output}

///|
pub impl Show for Date with fn output(self, logger) {
  logger.write_string(text_of(self))
}

///|
pub extend Date with Show::{to_string, output}

///|
pub impl Show for Time with fn output(self, logger) {
  logger.write_string(text_of_time(self))
}

///|
pub extend Time with Show::{to_string, output}

///|
/// `YYYY-MM-DD`, with a year past four digits written out in full.
fn text_of(d : Date) -> String {
  let sign = if d.year < 0 { "-" } else { "" }
  let y = if d.year < 0 { -d.year } else { d.year }
  sign + pad(y, 4) + "-" + pad(d.month, 2) + "-" + pad(d.day, 2)
}

///|
/// `HH:MM:SS`, with `.fff…` only when there is a fraction to write.
fn text_of_time(t : Time) -> String {
  let head = pad(t.hour, 2) + ":" + pad(t.minute, 2) + ":" + pad(t.second, 2)
  if t.nano == 0 {
    return head
  }
  // Trailing zeros are dropped, so a millisecond reads as one.
  let mut frac = pad(t.nano, 9)
  while frac.length() > 1 && frac[frac.length() - 1].to_int() == 48 {
    frac = frac[0:frac.length() - 1].to_owned()
  }
  head + "." + frac
}

///|
fn text_of_zone(z : Zone) -> String {
  match z {
    Utc => "Z"
    Offset(m) => {
      let sign = if m < 0 { "-" } else { "+" }
      let a = if m < 0 { -m } else { m }
      sign + pad(a / 60, 2) + ":" + pad(a % 60, 2)
    }
  }
}

///|
/// `n` written with at least `width` digits.
fn pad(n : Int, width : Int) -> String {
  let s = n.to_string()
  if s.length() >= width {
    return s
  }
  let out = StringBuilder()
  for i = s.length(); i < width; i = i + 1 {
    out.write_char('0')
  }
  out.write_string(s)
  out.to_string()
}

// -- HTTP ---------------------------------------------------------------------

///|
/// The three-letter day names IMF-fixdate uses, Sunday first.
let weekdays : Array[String] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

///|
/// The three-letter month names, January first.
let months : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
/// A moment as an HTTP date (RFC 9110 §5.6.7): `Sun, 06 Nov 1994 08:49:37 GMT`.
///
/// This is the one form a `Date` header may take. The two obsolete forms are read
/// by [`http`] and never written, which is what §5.6.7 asks for.
pub fn Moment::http_text(self : Moment) -> String raise Refused {
  let (d, t) = match self {
    Zoned(date~, time~, zone~) => {
      // The header is always GMT, so an offset moment is moved onto it first.
      let shift = match zone {
        Utc => 0
        Offset(m) => m
      }
      match
        Zoned(date~, time~, zone=Utc).plus(Span::of(minute, -shift.to_int64())) {
        Zoned(date~, time~, ..) => (date, time)
        _ => (date, time)
      }
    }
    Plain(date~, time~) => (date, time)
    Day(date~) => (date, { hour: 0, minute: 0, second: 0, nano: 0, })
    Clock(_) => raise Malformed("a time with no date is not an HTTP date")
  }
  weekdays[d.weekday()] +
  ", " +
  pad(d.day, 2) +
  " " +
  months[d.month - 1] +
  " " +
  pad(d.year, 4) +
  " " +
  pad(t.hour, 2) +
  ":" +
  pad(t.minute, 2) +
  ":" +
  pad(t.second, 2) +
  " GMT"
}

///|
/// An HTTP date read (RFC 9110 §5.6.7).
///
/// The preferred IMF-fixdate, and the two obsolete forms a recipient must still
/// accept: RFC 850's `Sunday, 06-Nov-94 08:49:37 GMT` and asctime's
/// `Sun Nov  6 08:49:37 1994`. A two-digit year is read as RFC 6265 §5.1.1 says:
/// 69 and under are 2000s, 70 and over are 1900s.
pub fn http(src : StringView) -> Moment raise Refused {
  let s = src.to_owned()
  let comma = find(s, ',')
  if comma < 0 {
    return asctime(s)
  }
  let rest = trim(s[comma + 1:].to_owned())
  // IMF-fixdate has spaces around the month; RFC 850 has dashes.
  if rest.length() >= 11 && at(rest, 2) == '-' {
    let year = digits(rest, 7, 2)
    return Zoned(
      date=Date::new(
        if year <= 68 {
          2000 + year
        } else {
          1900 + year
        },
        month_of(rest[3:6].to_owned()),
        digits(rest, 0, 2),
      ),
      time=time_of(rest, 10, 18),
      zone=Utc,
    )
  }
  if rest.length() < 20 {
    raise Truncated("an HTTP date")
  }
  Zoned(
    date=Date::new(
      digits(rest, 7, 4),
      month_of(rest[3:6].to_owned()),
      digits(rest, 0, 2),
    ),
    time=time_of(rest, 12, 20),
    zone=Utc,
  )
}

///|
/// The asctime form, whose day is space-padded rather than zero-padded.
fn asctime(s : String) -> Moment raise Refused {
  let t = trim(s)
  if t.length() < 24 {
    raise Truncated("an asctime date")
  }
  let day = if at(t, 8) == ' ' { digits(t, 9, 1) } else { digits(t, 8, 2) }
  Zoned(
    date=Date::new(digits(t, 20, 4), month_of(t[4:7].to_owned()), day),
    time=time_of(t, 11, 19),
    zone=Utc,
  )
}

///|
/// A three-letter month name as its number.
fn month_of(name : String) -> Int raise Refused {
  for i = 0; i < 12; i = i + 1 {
    if months[i] == name {
      return i + 1
    }
  }
  raise Malformed("not a month name: " + name)
}

///|
fn find(s : String, c : Char) -> Int {
  for i = 0; i < s.length(); i = i + 1 {
    if s[i].to_int() == c.to_int() {
      return i
    }
  }
  -1
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

// -- ASN.1 --------------------------------------------------------------------

///|
/// An ASN.1 UTCTime or GeneralizedTime (ITU-T X.680 §47), as DER writes them.
///
/// This is how a certificate spells its validity. DER requires the `Z` and whole
/// seconds; UTCTime's two-digit year is read as RFC 5280 §4.1.2.5.1 says — 49 and
/// under are 2000s, 50 and over are 1900s, which is not the same rule HTTP uses.
pub fn asn1(src : StringView) -> Moment raise Refused {
  let s = src.to_owned()
  let (year, from) = if s.length() == 13 {
    let y = digits(s, 0, 2)
    (if y < 50 { 2000 + y } else { 1900 + y }, 2)
  } else if s.length() == 15 {
    (digits(s, 0, 4), 4)
  } else {
    raise Malformed("an ASN.1 time is 13 or 15 characters")
  }
  if at(s, s.length() - 1) != 'Z' {
    raise Malformed("DER requires the Z")
  }
  Zoned(
    date=Date::new(year, digits(s, from, 2), digits(s, from + 2, 2)),
    time=Time::new(
      digits(s, from + 4, 2),
      digits(s, from + 6, 2),
      second=digits(s, from + 8, 2),
    ),
    zone=Utc,
  )
}

///|
/// A moment as an ASN.1 GeneralizedTime, which is the form DER uses from 2050 on
/// and the one that needs no windowing rule to read back.
pub fn Moment::asn1_text(self : Moment) -> String raise Refused {
  match self {
    Zoned(date~, time~, ..) | Plain(date~, time~) =>
      pad(date.year, 4) +
      pad(date.month, 2) +
      pad(date.day, 2) +
      pad(time.hour, 2) +
      pad(time.minute, 2) +
      pad(time.second, 2) +
      "Z"
    _ => raise Malformed("an ASN.1 time needs both a date and a time")
  }
}
