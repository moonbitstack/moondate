// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What Python's `datetime` module offers beyond the calendar itself: the ordinal,
// the ISO week date, combining and replacing parts, the epoch both ways, and the
// directive-driven format and parse of `strftime` and `strptime`.
//
// The names are this family's rather than Python's where the two disagree —
// `Date::ordinal` reads better than `toordinal` — but the meanings are the same,
// so a person who knows the Python module knows this one.

///|
/// The earliest and latest dates this calendar writes with a four-digit year.
///
/// Python's `date.min` and `date.max` are 1-01-01 and 9999-12-31; the arithmetic
/// here works outside that range, so these are a convention for writing rather than
/// a limit on computing.
pub let min_date : Date = { year: 1, month: 1, day: 1, }

///|
pub let max_date : Date = { year: 9999, month: 12, day: 31, }

///|
/// Midnight, and the last representable moment of a day.
pub let midnight : Time = { hour: 0, minute: 0, second: 0, nano: 0, }

///|
pub let end_of_day : Time = {
  hour: 23,
  minute: 59,
  second: 59,
  nano: 999_999_999,
}

///|
/// Days since 0001-01-01, that day being 1 (Python's `date.toordinal`).
///
/// The proleptic Gregorian ordinal, which is what makes two dates subtractable
/// without going through an epoch.
pub fn Date::ordinal(self : Date) -> Int {
  self.days() + 719163
}

///|
/// The date with that ordinal (Python's `date.fromordinal`).
pub fn Date::of_ordinal(n : Int) -> Date {
  Date::of_days(n - 719163)
}

///|
/// The ISO 8601 week date: the year the week belongs to, the week number, and the
/// day of the week with Monday as 1 (Python's `date.isocalendar`).
///
/// The year is not always the calendar year. A week belongs to the year that holds
/// its Thursday, so the first of January can fall in the last week of the year
/// before — which is exactly the case a hand-rolled week number gets wrong.
pub fn Date::isocalendar(self : Date) -> (Int, Int, Int) {
  let weekday = self.isoweekday()
  // The Thursday of this week decides which year the week counts against.
  let thursday = self.plus_days(4 - weekday)
  let year = thursday.year
  let jan1 = { year, month: 1, day: 1, }
  let week = (thursday.days() - jan1.days()) / 7 + 1
  (year, week, weekday)
}

///|
/// The day of the week with Monday as 1 and Sunday as 7 (Python's `isoweekday`).
///
/// [`Date::weekday`] counts from Sunday as 0, which is what cron and C's `tm_wday`
/// use; ISO counts from Monday as 1. Both are here because both are asked for, and
/// picking one silently is how an off-by-one gets into a schedule.
pub fn Date::isoweekday(self : Date) -> Int {
  let d = self.weekday()
  if d == 0 {
    7
  } else {
    d
  }
}

///|
/// The date named by an ISO week date (Python's `date.fromisocalendar`).
pub fn Date::of_isocalendar(
  year : Int,
  week : Int,
  weekday : Int,
) -> Date raise Refused {
  if week < 1 || week > 53 {
    raise Range(field="week", got=week, low=1, high=53)
  }
  if weekday < 1 || weekday > 7 {
    raise Range(field="weekday", got=weekday, low=1, high=7)
  }
  let jan4 : Date = { year, month: 1, day: 4, }
  // The fourth of January is always in week one, so the week's Monday follows.
  let week1 = jan4.plus_days(1 - jan4.isoweekday())
  week1.plus_days((week - 1) * 7 + weekday - 1)
}

///|
/// A date and a time as one wall-clock moment (Python's `datetime.combine`).
///
/// `zone` makes it an instant instead; leaving it off keeps it a wall clock, which
/// is what an opening time or an alarm is.
pub fn Moment::combine(date : Date, time : Time, zone? : Zone) -> Moment {
  match zone {
    Some(z) => Zoned(date~, time~, zone=z)
    None => Plain(date~, time~)
  }
}

///|
/// The same date with some parts replaced (Python's `date.replace`).
pub fn Date::replace(
  self : Date,
  year? : Int,
  month? : Int,
  day? : Int,
) -> Date raise Refused {
  Date::new(
    match year {
      Some(v) => v
      None => self.year
    },
    match month {
      Some(v) => v
      None => self.month
    },
    match day {
      Some(v) => v
      None => self.day
    },
  )
}

///|
/// The same time with some parts replaced (Python's `time.replace`).
pub fn Time::replace(
  self : Time,
  hour? : Int,
  minute? : Int,
  second? : Int,
  nano? : Int,
) -> Time raise Refused {
  Time::new(
    match hour {
      Some(v) => v
      None => self.hour
    },
    match minute {
      Some(v) => v
      None => self.minute
    },
    second=match second {
      Some(v) => v
      None => self.second
    },
    nano=match nano {
      Some(v) => v
      None => self.nano
    },
  )
}

///|
/// The moment `seconds` after 1970-01-01T00:00:00Z (Python's
/// `datetime.fromtimestamp`, with `tz` always supplied).
///
/// Reading the clock is not this package's job — it has no I/O — so a caller that
/// wants "now" passes what its own clock said.
pub fn Moment::of_epoch(
  seconds : Int64,
  nano? : Int = 0,
  zone? : Zone = Utc,
) -> Moment {
  let offset = match zone {
    Utc => 0L
    Offset(m) => m.to_int64() * 60L
  }
  let wall = seconds + offset
  let mut days = wall / 86400L
  let mut rest = wall % 86400L
  if rest < 0L {
    rest = rest + 86400L
    days = days - 1L
  }
  Zoned(
    date=Date::of_days(days.to_int()),
    time={
      hour: (rest / 3600L).to_int(),
      minute: (rest / 60L % 60L).to_int(),
      second: (rest % 60L).to_int(),
      nano,
    },
    zone~,
  )
}

///|
/// One date less another, as a span of whole days (Python's `date - date`).
pub fn Date::diff(self : Date, other : Date) -> Span {
  Span::of(day, (self.days() - other.days()).to_int64())
}

///|
/// One moment less another, for the two shapes that can be subtracted.
///
/// `None` when they are not comparable: an instant and a wall clock differ by an
/// amount that depends on a zone nobody supplied, and a bare time and a bare date
/// are not the same kind of thing.
pub fn Moment::diff(self : Moment, other : Moment) -> Span? {
  match (self.epoch(), other.epoch()) {
    (Some(a), Some(b)) => Some(Span::of(second, a - b))
    _ =>
      match (self, other) {
        (Plain(date~, time~), Plain(date=d2, time=t2)) =>
          Some({
            nanos: (date.days() - d2.days()).to_int64() * day.nanos +
            time.nanos() -
            t2.nanos(),
          })
        (Day(date~), Day(date=d2)) => Some(date.diff(d2))
        (Clock(time~), Clock(time=t2)) =>
          Some({ nanos: time.nanos() - t2.nanos(), })
        _ => None
      }
  }
}

///|
/// The span as seconds, fraction included (Python's `timedelta.total_seconds`).
pub fn Span::total_seconds(self : Span) -> Double {
  self.nanos.to_double() / 1.0e9
}

///|
/// The whole days in a span, and the seconds and nanoseconds left over — the three
/// fields Python's `timedelta` normalises to.
pub fn Span::parts(self : Span) -> (Int, Int, Int) {
  let mut days = self.nanos / day.nanos
  let mut rest = self.nanos % day.nanos
  if rest < 0L {
    rest = rest + day.nanos
    days = days - 1L
  }
  (
    days.to_int(),
    (rest / 1_000_000_000L).to_int(),
    (rest % 1_000_000_000L).to_int(),
  )
}

// -- strftime and strptime ----------------------------------------------------

///|
/// A moment written by a format string of `%` directives (Python's `strftime`).
///
/// The directives are the ones C89 defines and Python implements, less the two
/// that need a locale (`%c`, `%x`, `%X` are the C locale's) and the one that needs
/// a zone database (`%Z` writes `UTC` or the offset, never a name like `CEST`,
/// because a name cannot be recovered from an offset).
///
/// | | |
/// |:--:|:--|
/// | `%Y` `%y` `%m` `%d` | year, two-digit year, month, day |
/// | `%H` `%I` `%M` `%S` `%f` | hour, twelve-hour, minute, second, microseconds |
/// | `%p` `%j` `%a` `%A` `%b` `%B` | AM/PM, day of year, day and month names |
/// | `%z` `%Z` | offset as `+HHMM`, and `UTC` |
/// | `%G` `%V` `%u` `%w` | ISO year, ISO week, ISO weekday, weekday from Sunday |
/// | `%%` | a per cent sign |
pub fn Moment::strftime(self : Moment, format : StringView) -> String {
  let (d, t, z) = match self {
    Zoned(date~, time~, zone~) => (date, time, Some(zone))
    Plain(date~, time~) => (date, time, None)
    Day(date~) => (date, midnight, None)
    Clock(time~) => ({ year: 1900, month: 1, day: 1, }, time, None)
  }
  let f = format.to_owned()
  let out = StringBuilder()
  let mut i = 0
  while i < f.length() {
    if f[i].to_int() != 0x25 || i + 1 >= f.length() {
      out.write_char(f[i].unsafe_to_char())
      i = i + 1
      continue
    }
    let c = f[i + 1].unsafe_to_char()
    i = i + 2
    let (iso_year, iso_week, iso_day) = d.isocalendar()
    out.write_string(
      match c {
        'Y' => d.year.to_string()
        'y' => pad(d.year % 100, 2)
        'm' => pad(d.month, 2)
        'd' => pad(d.day, 2)
        'H' => pad(t.hour, 2)
        'I' => pad(if t.hour % 12 == 0 { 12 } else { t.hour % 12 }, 2)
        'M' => pad(t.minute, 2)
        'S' => pad(t.second, 2)
        'f' => pad(t.nano / 1000, 6)
        'p' => if t.hour < 12 { "AM" } else { "PM" }
        'j' => pad(d.yearday(), 3)
        'a' => weekdays[d.weekday()]
        'A' => long_days[d.weekday()]
        'b' => months[d.month - 1]
        'B' => long_months[d.month - 1]
        'G' => iso_year.to_string()
        'V' => pad(iso_week, 2)
        'u' => iso_day.to_string()
        'w' => d.weekday().to_string()
        'z' =>
          match z {
            Some(Utc) => "+0000"
            Some(Offset(m)) => {
              let sign = if m < 0 { "-" } else { "+" }
              let a = if m < 0 { -m } else { m }
              sign + pad(a / 60, 2) + pad(a % 60, 2)
            }
            None => ""
          }
        'Z' =>
          match z {
            Some(_) => "UTC"
            None => ""
          }
        '%' => "%"
        other => "%" + other.to_string()
      },
    )
  }
  out.to_string()
}

///|
/// A moment read by a format string of `%` directives (Python's `strptime`).
///
/// The directives are the ones [`Moment::strftime`] writes. Literal characters in
/// the format must match the text exactly, except that whitespace in the format
/// matches any run of whitespace, which is what C's `strptime` does and what makes
/// a format survive a double space.
///
/// The result is `Zoned` when the text carried an offset, `Plain` when it carried a
/// date and a time, `Day` when only a date, and `Clock` when only a time — the same
/// four shapes [`parse`] answers with.
pub fn strptime(src : StringView, format : StringView) -> Moment raise Refused {
  let s = src.to_owned()
  let f = format.to_owned()
  let mut year = 1900
  let mut month = 1
  let mut mday = 1
  let mut hour = 0
  let mut minute = 0
  let mut sec = 0
  let mut nano = 0
  let mut offset : Int? = None
  let mut pm : Bool? = None
  let mut saw_date = false
  let mut saw_time = false
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
    if i + 1 >= f.length() {
      raise Malformed("a % at the end of the format")
    }
    let c = f[i + 1].unsafe_to_char()
    i = i + 2
    match c {
      'Y' => {
        let (v, k) = take(s, j, 4)
        year = v
        j = k
        saw_date = true
      }
      'y' => {
        let (v, k) = take(s, j, 2)
        // Python's rule: 69 and over are 1900s, under are 2000s.
        year = if v >= 69 { 1900 + v } else { 2000 + v }
        j = k
        saw_date = true
      }
      'm' => {
        let (v, k) = take(s, j, 2)
        month = v
        j = k
        saw_date = true
      }
      'd' => {
        let (v, k) = take(s, j, 2)
        mday = v
        j = k
        saw_date = true
      }
      'H' | 'I' => {
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
      'f' => {
        let start = j
        let mut v = 0
        while j < s.length() && is_digit(s[j].to_int()) && j - start < 9 {
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
        saw_time = true
      }
      'j' => {
        let (v, k) = take(s, j, 3)
        j = k
        // Day of the year sets the date once the year is known.
        let base : Date = { year, month: 1, day: 1, }
        let d = base.plus_days(v - 1)
        month = d.month
        mday = d.day
        saw_date = true
      }
      'p' => {
        if j + 2 > s.length() {
          raise Truncated("expected AM or PM")
        }
        let word = s[j:j + 2].to_owned().to_upper()
        pm = match word {
          "AM" => Some(false)
          "PM" => Some(true)
          _ => raise Malformed("expected AM or PM, got " + word)
        }
        j = j + 2
      }
      'a' | 'A' => j = skip_name(s, j)
      'b' | 'B' => {
        let (m, k) = read_month(s, j)
        month = m
        j = k
        saw_date = true
      }
      'z' => {
        let (o, k) = read_offset(s, j)
        offset = Some(o)
        j = k
      }
      'Z' => j = skip_name(s, j)
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
/// Up to `n` digits at `j`, and where reading stopped.
///
/// Fewer than `n` is allowed when what follows is not a digit, because `%m` reads
/// `1-2-3` the way a person writes it.
fn take(s : String, j : Int, n : Int) -> (Int, Int) raise Refused {
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
fn is_digit(c : Int) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
/// Past a run of letters, for a name this parser does not need to keep.
fn skip_name(s : String, j : Int) -> Int {
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
fn read_month(s : String, j : Int) -> (Int, Int) raise Refused {
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
/// An offset at `j`, as `+HHMM`, `+HH:MM` or `Z`.
fn read_offset(s : String, j : Int) -> (Int, Int) raise Refused {
  if j < s.length() && (s[j].to_int() == 0x5a || s[j].to_int() == 0x7a) {
    return (0, j + 1)
  }
  if j + 5 > s.length() {
    raise Truncated("an offset")
  }
  let sign = s[j].to_int()
  if sign != 0x2b && sign != 0x2d {
    raise Malformed("an offset begins with a sign at \{j}")
  }
  let (h, a) = take(s, j + 1, 2)
  let b = if a < s.length() && s[a].to_int() == 0x3a { a + 1 } else { a }
  let (m, c) = take(s, b, 2)
  let total = h * 60 + m
  (if sign == 0x2d { -total } else { total }, c)
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

// -- the rest of Python's surface ---------------------------------------------

///|
/// The years Python's calendar spans (`MINYEAR` and `MAXYEAR`).
pub let min_year : Int = 1

///|
pub let max_year : Int = 9999

///|
/// The smallest difference two moments can have (Python's `resolution`).
///
/// A nanosecond rather than Python's microsecond: the clock here is finer, which is
/// what a protocol timestamp and a benchmark both want.
pub let resolution : Span = nanosecond

///|
/// The date out of a moment (Python's `datetime.date()`).
///
/// `None` for a bare time, which has no date to give.
pub fn Moment::date(self : Moment) -> Date? {
  match self {
    Zoned(date~, ..) | Plain(date~, ..) | Day(date~) => Some(date)
    Clock(_) => None
  }
}

///|
/// The time out of a moment (Python's `datetime.time()`).
///
/// Midnight for a bare date, which is the time it names.
pub fn Moment::time(self : Moment) -> Time {
  match self {
    Zoned(time~, ..) | Plain(time~, ..) | Clock(time~) => time
    Day(_) => midnight
  }
}

///|
/// The zone a moment carries, or `None` when it carries none (Python's `tzinfo`).
pub fn Moment::zone(self : Moment) -> Zone? {
  match self {
    Zoned(zone~, ..) => Some(zone)
    _ => None
  }
}

///|
/// How far the moment's clock is from UTC (Python's `utcoffset`).
pub fn Moment::utcoffset(self : Moment) -> Span? {
  match self.zone() {
    Some(Utc) => Some(Span::of(minute, 0L))
    Some(Offset(m)) => Some(Span::of(minute, m.to_int64()))
    None => None
  }
}

///|
/// The same instant read in another zone (Python's `astimezone`).
///
/// `None` for the three shapes that are not instants: moving a wall clock to
/// another zone would be inventing the zone it was written in.
pub fn Moment::astimezone(self : Moment, zone : Zone) -> Moment? {
  match self.epoch() {
    Some(secs) => Some(Moment::of_epoch(secs, nano=self.time().nano, zone~))
    None => None
  }
}

///|
/// The same moment with some parts replaced (Python's `datetime.replace`).
pub fn Moment::replace(
  self : Moment,
  year? : Int,
  month? : Int,
  day? : Int,
  hour? : Int,
  minute? : Int,
  second? : Int,
  nano? : Int,
  zone? : Zone,
) -> Moment raise Refused {
  let d = match self.date() {
    Some(d) => Some(d.replace(year?, month?, day?))
    None => None
  }
  let t = self.time().replace(hour?, minute?, second?, nano?)
  match (d, zone, self) {
    (Some(date), Some(z), _) => Zoned(date~, time=t, zone=z)
    (Some(date), None, Zoned(zone~, ..)) => Zoned(date~, time=t, zone~)
    (Some(date), None, Day(_)) => Day(date~)
    (Some(date), None, _) => Plain(date~, time=t)
    (None, _, _) => Clock(time=t)
  }
}

///|
/// The day of the week of the moment's date, Sunday being 0.
pub fn Moment::weekday(self : Moment) -> Int? {
  self.date().map(d => d.weekday())
}

///|
/// The ISO week date of the moment's date.
pub fn Moment::isocalendar(self : Moment) -> (Int, Int, Int)? {
  self.date().map(d => d.isocalendar())
}

///|
/// Days since 0001-01-01 of the moment's date (Python's `toordinal`).
pub fn Moment::ordinal(self : Moment) -> Int? {
  self.date().map(d => d.ordinal())
}

///|
/// The moment as ISO 8601 text, which is what [`Show`] writes (Python's
/// `isoformat`).
///
/// `sep` is the character between the date and the time, `T` by default; Python
/// allows any, and a space is what a log line wants.
pub fn Moment::isoformat(self : Moment, sep? : Char = 'T') -> String {
  let text = self.to_string()
  if sep == 'T' {
    return text
  }
  let out = StringBuilder()
  let mut swapped = false
  for i = 0; i < text.length(); i = i + 1 {
    if !swapped && text[i].to_int() == 0x54 {
      out.write_char(sep)
      swapped = true
    } else {
      out.write_char(text[i].unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// A moment read from ISO 8601 text (Python's `fromisoformat`), which is what
/// [`parse`] does.
pub fn of_isoformat(src : StringView) -> Moment raise Refused {
  parse(src)
}

///|
/// The moment in C's `ctime` form: `Sun Nov  6 08:49:37 1994`.
///
/// The day is space-padded rather than zero-padded, which is the one thing that
/// distinguishes this form from every other.
pub fn Moment::ctime(self : Moment) -> String {
  let d = match self.date() {
    Some(d) => d
    None => { year: 1900, month: 1, day: 1, }
  }
  let t = self.time()
  let day_text = if d.day < 10 {
    " " + d.day.to_string()
  } else {
    d.day.to_string()
  }
  weekdays[d.weekday()] +
  " " +
  months[d.month - 1] +
  " " +
  day_text +
  " " +
  pad(t.hour, 2) +
  ":" +
  pad(t.minute, 2) +
  ":" +
  pad(t.second, 2) +
  " " +
  d.year.to_string()
}

///|
/// The nine fields C's `struct tm` holds, in its order (Python's `timetuple`):
/// year, month, day, hour, minute, second, weekday from Monday as 0, day of the
/// year, and whether daylight saving applies — always `-1` here, because that
/// needs a zone database this package does not carry.
pub fn Moment::timetuple(
  self : Moment,
) -> (Int, Int, Int, Int, Int, Int, Int, Int, Int) {
  let d = match self.date() {
    Some(d) => d
    None => { year: 1900, month: 1, day: 1, }
  }
  let t = self.time()
  (
    d.year,
    d.month,
    d.day,
    t.hour,
    t.minute,
    t.second,
    d.isoweekday() - 1,
    d.yearday(),
    -1,
  )
}

///|
/// Seconds since the epoch as a `Double`, fraction included (Python's
/// `datetime.timestamp`).
pub fn Moment::timestamp(self : Moment) -> Double? {
  self.epoch().map(s => s.to_double() + self.time().nano.to_double() / 1.0e9)
}

///|
/// A span made of the parts Python's `timedelta` constructor takes.
pub fn Span::new(
  days? : Int64 = 0,
  hours? : Int64 = 0,
  minutes? : Int64 = 0,
  seconds? : Int64 = 0,
  millis? : Int64 = 0,
  micros? : Int64 = 0,
  nanos? : Int64 = 0,
) -> Span {
  {
    nanos: days * day.nanos +
    hours * hour.nanos +
    minutes * minute.nanos +
    seconds * second.nanos +
    millis * 1_000_000L +
    micros * 1_000L +
    nanos,
  }
}

///|
/// The span negated.
pub fn Span::neg(self : Span) -> Span {
  { nanos: -self.nanos, }
}

///|
/// The span with its sign dropped.
pub fn Span::abs(self : Span) -> Span {
  { nanos: if self.nanos < 0L { -self.nanos } else { self.nanos }, }
}
