// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The day a daylight-saving rule changes the clocks on, as POSIX TZ strings
/// write it.
#derive(Eq, Debug)
pub(all) enum Onset {
  /// `Mm.w.d`: the `d`th weekday of the `w`th week of month `m`, week 5 being the
  /// last one however many it has.
  MonthWeekDay(month~ : Int32, week~ : Int32, weekday~ : Int32)
  /// `Jn`: day `n` of the year, counting February the twenty-eighth every year, so
  /// a leap day never shifts it.
  Julian(n~ : Int32)
  /// `n`: day `n` of the year, counting from zero and including February the
  /// twenty-ninth, so a leap day does shift it.
  Days(n~ : Int32)
}

///|
pub extend Onset with Debug::{to_repr}

///|
pub extend Onset with Eq::{not_equal, equal}

///|
/// When a change happens: which day, and how long after local midnight.
///
/// The seconds can pass a day — Ireland's rules once changed the clocks at
/// twenty-five hundred hours — because a rule is read as "so many hours after the
/// start of that day", not as a time of day.
#derive(Eq, Debug)
pub(all) struct ClockRule {
  onset : Onset
  seconds : Int32
}

///|
pub extend ClockRule with Debug::{to_repr}

///|
pub extend ClockRule with Eq::{not_equal, equal}

///|
/// A POSIX TZ string: the standard offset, and either no daylight saving or the
/// two changes that bracket it.
///
/// RFC 8536 §3.3 puts one of these in every TZif footer, which is how a file that
/// stops in 2037 still answers for 2100. The grammar is POSIX's `TZ`, extended
/// there to allow a quoted name like `<+0545>` and seconds in the offsets.
#derive(Eq, Debug)
pub(all) struct Rule {
  std_offset : Int32
  std_abbrev : String
  /// `None` when the zone has no daylight saving at all.
  dst_offset : Int32?
  dst_abbrev : String
  dst_start : ClockRule?
  dst_end : ClockRule?
}

///|
pub extend Rule with Debug::{to_repr}

///|
pub extend Rule with Eq::{not_equal, equal}

///|
/// A POSIX TZ string read.
///
/// `EST5EDT,M3.2.0,M11.1.0` is New York; `UTC0` is UTC; `<+0545>-5:45` is a fixed
/// offset with a name that needs the angle brackets because of the sign. The
/// offset in the string is what to *add* to local time to get UTC, so its sign is
/// the opposite of the one a timestamp writes, which is the one trap in the whole
/// format.
pub fn Rule::parse(text : StringView) -> Rule raise Refused {
  let s = text.to_owned()
  let (std_abbrev, start) = name_of(s, 0)
  let (std_west, from) = offset_of(s, start, "standard offset")
  let mut i = from
  let std_offset = -std_west
  if i >= s.length() {
    return {
      std_offset,
      std_abbrev,
      dst_offset: None,
      dst_abbrev: "",
      dst_start: None,
      dst_end: None,
    }
  }
  // A daylight-saving name follows, then an offset for it if one is given, then
  // the two changes.
  let mut dst_abbrev = std_abbrev
  if at(s, i) != ',' {
    let (name, next) = name_of(s, i)
    dst_abbrev = name
    i = next
  }
  let mut dst_offset = std_offset + 3600
  if i < s.length() && at(s, i) != ',' {
    let (west, next) = offset_of(s, i, "daylight-saving offset")
    dst_offset = -west
    i = next
  }
  if i >= s.length() {
    // No changes given: POSIX leaves the default to the implementation, and the
    // one every implementation picked is the United States rule of that era.
    return {
      std_offset,
      std_abbrev,
      dst_offset: Some(dst_offset),
      dst_abbrev,
      dst_start: Some({
        onset: MonthWeekDay(month=3, week=2, weekday=0),
        seconds: 7200,
      }),
      dst_end: Some({
        onset: MonthWeekDay(month=11, week=1, weekday=0),
        seconds: 7200,
      }),
    }
  }
  if at(s, i) != ',' {
    raise Malformed(kind="a POSIX TZ string: a comma before the rules", at=i)
  }
  let (start, next) = clock_rule_of(s, i + 1)
  i = next
  if at(s, i) != ',' {
    raise Malformed(kind="a POSIX TZ string: a comma between the rules", at=i)
  }
  let (end, next) = clock_rule_of(s, i + 1)
  i = next
  if i != s.length() {
    raise Malformed(kind="a POSIX TZ string: trailing text", at=i)
  }
  {
    std_offset,
    std_abbrev,
    dst_offset: Some(dst_offset),
    dst_abbrev,
    dst_start: Some(start),
    dst_end: Some(end),
  }
}

///|
/// The string a rule is written as, in the form [`Rule::parse`] reads.
pub fn Rule::text(self : Rule) -> String {
  let out = StringBuilder()
  out.write_string(posix_name(self.std_abbrev))
  out.write_string(posix_offset(self.std_offset))
  match (self.dst_offset, self.dst_start, self.dst_end) {
    (Some(dst), Some(start), Some(end)) => {
      out.write_string(posix_name(self.dst_abbrev))
      // An hour more than standard time is what a missing offset means, so it is
      // left out; anything else has to be said.
      if dst != self.std_offset + 3600 {
        out.write_string(posix_offset(dst))
      }
      out.write_string(",")
      out.write_string(posix_clock_rule(start))
      out.write_string(",")
      out.write_string(posix_clock_rule(end))
    }
    _ => ()
  }
  out.to_string()
}

///|
/// What the rule reads at an instant.
///
/// The two changes are placed year by year rather than tabulated: a rule is a
/// pattern, and asking it about a date a century out costs a handful of date
/// computations, which is how a TZif footer answers past the end of its table.
pub fn Rule::at(self : Rule, epoch : Int64) -> Reading {
  match (self.dst_offset, self.dst_start, self.dst_end) {
    (Some(dst_offset), Some(start), Some(end)) => {
      // The year the instant falls in is enough, but a change near New Year in a
      // zone at the far east or west can belong to the year either side, so the
      // neighbours are asked as well and the latest change wins.
      let year = year_of(epoch)
      let mut begun = -9223372036854775808L
      let mut daylight = false
      for y in [year - 1, year, year + 1] {
        let opens = instant_of(start, y, self.std_offset)
        let closes = instant_of(end, y, dst_offset)
        if opens <= epoch && opens > begun {
          begun = opens
          daylight = true
        }
        if closes <= epoch && closes > begun {
          begun = closes
          daylight = false
        }
      }
      if daylight {
        {
          epoch: begun,
          offset: dst_offset,
          is_dst: true,
          abbrev: self.dst_abbrev,
        }
      } else {
        {
          epoch: begun,
          offset: self.std_offset,
          is_dst: false,
          abbrev: self.std_abbrev,
        }
      }
    }
    _ =>
      {
        epoch,
        offset: self.std_offset,
        is_dst: false,
        abbrev: self.std_abbrev,
      }
  }
}

///|
/// The instant a change happens in year `y`, read against the offset in force
/// before it — standard time for the opening change, saving time for the closing
/// one, which is what POSIX means by a time of day.
fn instant_of(rule : ClockRule, year : Int32, before : Int32) -> Int64 {
  let day = day_of(rule.onset, year)
  day.days().to_int64() * 86400L + rule.seconds.to_int64() - before.to_int64()
}

///|
/// The date an onset names in a year.
fn day_of(onset : Onset, year : Int32) -> @moondate.Date {
  let jan1 : @moondate.Date = { year, month: 1, day: 1, }
  match onset {
    MonthWeekDay(month~, week~, weekday~) => {
      let first : @moondate.Date = { year, month, day: 1, }
      let mut day = 1 + (weekday - first.weekday() + 7) % 7 + (week - 1) * 7
      // Week five means the last one, which is the fourth in most months.
      let last = @moondate.length(year, month)
      while day > last {
        day = day - 7
      }
      { year, month, day, }
    }
    Julian(n~) => {
      // February the twenty-ninth is never counted, so a leap year skips it.
      let shift = if n >= 60 && @moondate.leap(year) { 1 } else { 0 }
      jan1.plus_days(n - 1 + shift)
    }
    Days(n~) => jan1.plus_days(n)
  }
}

///|
/// The year an instant falls in, on the UTC clock.
fn year_of(epoch : Int64) -> Int32 {
  @moondate.Date::of_days((epoch / 86400L).to_int()).year
}

// -- reading the text ---------------------------------------------------------

///|
/// A zone name at `from`: either the letters of a bare name or what is inside
/// angle brackets.
fn name_of(s : String, from : Int32) -> (String, Int32) raise Refused {
  if at(s, from) == '<' {
    let mut i = from + 1
    while i < s.length() && at(s, i) != '>' {
      i = i + 1
    }
    if i >= s.length() {
      raise Malformed(kind="a POSIX TZ name: a closing angle bracket", at=from)
    }
    if i == from + 1 {
      raise Malformed(
        kind="a POSIX TZ name: something inside the brackets",
        at=from,
      )
    }
    return (s[from + 1:i].to_owned(), i + 1)
  }
  let mut i = from
  while i < s.length() && is_letter(at(s, i)) {
    i = i + 1
  }
  if i - from < 3 {
    raise Malformed(kind="a POSIX TZ name: at least three letters", at=from)
  }
  (s[from:i].to_owned(), i)
}

///|
/// An offset at `from`, in the seconds POSIX writes — so the number in `EST5` is
/// five hours and the reading is minus five.
fn offset_of(
  s : String,
  from : Int32,
  what : String,
) -> (Int32, Int32) raise Refused {
  let mut i = from
  let mut sign = 1
  if at(s, i) == '-' {
    sign = -1
    i = i + 1
  } else if at(s, i) == '+' {
    i = i + 1
  }
  let (hours, next) = number_of(s, i, what)
  i = next
  let mut minutes = 0
  let mut seconds = 0
  if at(s, i) == ':' {
    let (value, next) = number_of(s, i + 1, what)
    minutes = value
    i = next
    if at(s, i) == ':' {
      let (value, next) = number_of(s, i + 1, what)
      seconds = value
      i = next
    }
  }
  if hours > 167 || minutes > 59 || seconds > 59 {
    raise Malformed(
      kind="a POSIX TZ offset: hours, minutes and seconds",
      at=from,
    )
  }
  (sign * (hours * 3600 + minutes * 60 + seconds), i)
}

///|
/// A change at `from`: the onset, an optional slash and the time of day.
fn clock_rule_of(s : String, from : Int32) -> (ClockRule, Int32) raise Refused {
  let mut i = from
  let onset = match at(s, i) {
    'M' => {
      let (month, after) = number_of(s, i + 1, "a Mm.w.d month")
      if at(s, after) != '.' {
        raise Malformed(kind="a POSIX TZ onset: Mm.w.d", at=after)
      }
      let (week, after) = number_of(s, after + 1, "a Mm.w.d week")
      if at(s, after) != '.' {
        raise Malformed(kind="a POSIX TZ onset: Mm.w.d", at=after)
      }
      let (weekday, after) = number_of(s, after + 1, "a Mm.w.d weekday")
      if month < 1 || month > 12 {
        raise Malformed(kind="a POSIX TZ onset: a month of 1 to 12", at=from)
      }
      if week < 1 || week > 5 {
        raise Malformed(kind="a POSIX TZ onset: a week of 1 to 5", at=from)
      }
      if weekday > 6 {
        raise Malformed(kind="a POSIX TZ onset: a weekday of 0 to 6", at=from)
      }
      i = after
      MonthWeekDay(month~, week~, weekday~)
    }
    'J' => {
      let (n, after) = number_of(s, i + 1, "a Jn day")
      if n < 1 || n > 365 {
        raise Malformed(kind="a POSIX TZ onset: a Jn day of 1 to 365", at=from)
      }
      i = after
      Julian(n~)
    }
    _ => {
      let (n, after) = number_of(s, i, "a day of the year")
      if n > 365 {
        raise Malformed(kind="a POSIX TZ onset: a day of 0 to 365", at=from)
      }
      i = after
      Days(n~)
    }
  }
  let mut seconds = 7200
  if at(s, i) == '/' {
    let (value, after) = offset_of(s, i + 1, "a POSIX TZ time of day")
    seconds = value
    i = after
  }
  ({ onset, seconds, }, i)
}

///|
/// A run of digits at `from`, at least one.
fn number_of(
  s : String,
  from : Int32,
  what : String,
) -> (Int32, Int32) raise Refused {
  let mut i = from
  let mut out = 0
  while i < s.length() && at(s, i) >= '0' && at(s, i) <= '9' {
    out = out * 10 + (at(s, i).to_int() - 48)
    i = i + 1
  }
  if i == from {
    raise Malformed(kind=what, at=from)
  }
  (out, i)
}

///|
fn is_letter(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

///|
fn at(s : String, i : Int32) -> Char {
  if i >= 0 && i < s.length() {
    s[i].unsafe_to_char()
  } else {
    ' '
  }
}

// -- writing the text ---------------------------------------------------------

///|
/// A name as POSIX writes it: bare when it is three or more letters, in angle
/// brackets otherwise, which is what RFC 8536 §3.3 extended the grammar with.
fn posix_name(name : String) -> String {
  let mut plain = name.length() >= 3
  for i = 0; i < name.length(); i = i + 1 {
    if !is_letter(at(name, i)) {
      plain = false
    }
  }
  if plain {
    name
  } else {
    "<" + name + ">"
  }
}

///|
/// An offset as POSIX writes it, with the sign the format gives it.
fn posix_offset(east : Int32) -> String {
  let west = -east
  let sign = if west < 0 { "-" } else { "" }
  sign + posix_duration(if west < 0 { -west } else { west })
}

///|
/// A length of time as POSIX writes one: whole hours bare, and the parts it needs
/// after a colon.
fn posix_duration(seconds : Int32) -> String {
  let hh = seconds / 3600
  let mm = seconds % 3600 / 60
  let ss = seconds % 60
  let head = hh.to_string()
  if ss != 0 {
    head + ":" + two(mm) + ":" + two(ss)
  } else if mm != 0 {
    head + ":" + two(mm)
  } else {
    head
  }
}

///|
fn two(n : Int32) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
fn posix_clock_rule(rule : ClockRule) -> String {
  let head = match rule.onset {
    MonthWeekDay(month~, week~, weekday~) =>
      "M" +
      month.to_string() +
      "." +
      week.to_string() +
      "." +
      weekday.to_string()
    Julian(n~) => "J" + n.to_string()
    Days(n~) => n.to_string()
  }
  if rule.seconds == 7200 {
    head
  } else {
    let sign = if rule.seconds < 0 { "-" } else { "" }
    head +
    "/" +
    sign +
    posix_duration(if rule.seconds < 0 { -rule.seconds } else { rule.seconds })
  }
}
