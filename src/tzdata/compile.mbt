// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Turning the release's stretches and rules into a table of readings, which is
// what `zic` does when it writes a TZif file.
//
// A stretch with a rule set is walked year by year: for each year the rules that
// apply are placed on the calendar, sorted by the clock they name, and turned into
// instants using the amount of saving the previous change left behind. That
// ordering is the whole of the algorithm — a rule that changes the clocks at
// two in the morning is read against the clock that was running a moment before
// it, so the instant cannot be computed without the change before it.

///|
/// The smallest instant an `Int64` holds.
let beginning : Int64 = -9223372036854775808L

///|
/// How far the table is generated. A stretch with no end is walked this far and no
/// further: a rule set is a pattern, so a year past this one is a year the release
/// says nothing about, and the last reading stands rather than being guessed.
let horizon : Int32 = 3000

///|
/// Drop a transition whose local clock does not move forward.
///
/// A zone that changes its standard offset and starts its daylight saving at the
/// same moment makes two changes an hour apart in UTC but not in the clock: zic
/// keeps one of them, at the earlier instant, carrying the later type. Argentina
/// did exactly that in 1999, and without this the table claims an hour that never
/// happened.
fn settle(readings : Array[@zone.Reading]) -> Array[@zone.Reading] {
  let out : Array[@zone.Reading] = []
  for reading in readings {
    if out.length() >= 2 {
      let last = out[out.length() - 1]
      let before = out[out.length() - 2]
      if reading.epoch + last.offset.to_int64() <=
        last.epoch + before.offset.to_int64() {
        out[out.length() - 1] = {
          ..last,
          offset: reading.offset,
          abbrev: reading.abbrev,
          is_dst: reading.is_dst,
        }
        continue
      }
    }
    out.push(reading)
  }
  out
}

///|
/// One change a rule set makes in one year, before it is placed on the timeline.
priv struct Change {
  /// The wall clock the change happens at, as seconds of an imaginary UTC clock.
  wall : Int64
  clock : Clock
  save : Int32
  letter : String
  is_dst : Bool
}

///|
/// The readings of a zone, from its stretches and the rule sets they name.
fn brew(
  name : String,
  stretches : Array[Stretch],
  rules : Map[String, Array[Line]],
) -> @zone.Tz raise @zone.Refused {
  let readings : Array[@zone.Reading] = []
  let mut start = beginning
  let mut save = 0
  let mut letter = ""
  let mut daylight = false
  // The clock in force just before the reading being placed: the stretch's own
  // standard time plus the saving the change before left.
  let mut before_state : Reading0 = { std: 0, save: 0, }
  for i = 0; i < stretches.length(); i = i + 1 {
    let stretch = stretches[i]
    // A reading is the offset and the abbreviation together, and both depend on
    // where on the timeline it stands, so the two are handed in rather than
    // captured: a stretch changes its mind a few hundred times.
    let emit = fn(
      epoch : Int64,
      saving : Int32,
      letters : String,
      is_dst : Bool,
    ) {
      readings.push({
        epoch,
        offset: stretch.offset + saving,
        is_dst,
        abbrev: abbrev_of(
          stretch.format,
          letters,
          stretch.offset + saving,
          is_dst,
        ),
      })
    }
    before_state = { std: stretch.offset, save: 0, }
    let opens = if readings.length() == 0 { beginning } else { start }
    // Where the stretch ends is read against the clock in force just before it,
    // which is the saving left behind by the last change inside the stretch — so
    // it is worked out after the stretch has been walked, not before.
    match stretch.saving {
      // A stretch with no rules, or with one fixed amount, reads the same all
      // through.
      None_ => {
        save = 0
        letter = ""
        daylight = false
        emit(opens, save, letter, daylight)
        before_state = { std: stretch.offset, save, }
      }
      Fixed(amount) => {
        save = amount
        letter = ""
        daylight = amount != 0
        emit(opens, save, letter, daylight)
        before_state = { std: stretch.offset, save, }
      }
      Named(set) =>
        match rules.get(set) {
          Some(lines) => {
            // Every rule set is walked from the first year it speaks about, not
            // from the year the stretch begins: a stretch that opens in 1944
            // inherits the saving a 1942 rule left behind, and a walk that started
            // at 1943 would miss it.
            let first = earliest(lines)
            let last = match edge_of(stretch, save) {
              Some(instant) => year_at(instant) + 1
              None => horizon
            }
            // What the stretch reads at the moment it begins: the last change
            // behind it, or, when it has none, the letter of the first standard
            // change ahead — the rule zic applies, and the reason 1883 in New York
            // reads EST rather than the bare ET its format would give.
            //
            // zic starts every stretch at nought and lets the rules correct it: a
            // stretch whose rule set has nothing to say before it begins is standard
            // time, not whatever the stretch before it ended on.
            save = 0
            letter = ""
            daylight = false
            let mut before = false
            let mut ahead : String? = None
            let mut lead = before_state
            let mut walk = first
            while walk <= last {
              for change in changes_in(lines, walk) {
                let instant = placed_at(change, lead, stretch.offset)
                if instant <= start {
                  before = true
                  lead = { std: stretch.offset, save: change.save, }
                } else if !before && ahead is None && change.save == 0 {
                  ahead = Some(change.letter)
                }
              }
              walk = walk + 1
            }
            let mut year = first
            let mut opened = false
            let mut done = false
            while year <= last && !done {
              for change in changes_in(lines, year) {
                let instant = placed_at(change, before_state, stretch.offset)
                if instant <= start {
                  // Behind the stretch: only the state it leaves matters.
                  if !opened {
                    save = change.save
                    letter = change.letter
                    daylight = change.is_dst
                    before_state = { std: stretch.offset, save, }
                  }
                  continue
                }
                match edge_of(stretch, save) {
                  Some(end) =>
                    if instant >= end {
                      done = true
                      break
                    }
                  None => ()
                }
                if !opened {
                  if letter == "" {
                    match ahead {
                      Some(found) => letter = found
                      None => ()
                    }
                  }
                  emit(opens, save, letter, save != 0)
                  before_state = { std: stretch.offset, save, }
                  opened = true
                }
                save = change.save
                letter = change.letter
                daylight = change.is_dst
                emit(instant, save, letter, daylight)
                before_state = { std: stretch.offset, save, }
              }
              year = year + 1
            }
            if !opened {
              emit(opens, save, letter, save != 0)
              before_state = { std: stretch.offset, save, }
            }
          }
          None =>
            raise @zone.Malformed(
              kind="a zone line naming a rule set the release does not have",
              at=0,
            )
        }
    }
    match edge_of(stretch, save) {
      Some(instant) => start = instant
      None => ()
    }
  }
  @zone.Tz::of(name~, readings=settle(readings))
}

///|
/// The changes a rule set makes in one year, in the order the clocks reach them.
fn changes_in(lines : Array[Line], year : Int32) -> Array[Change] {
  let out : Array[Change] = []
  for line in lines {
    if year < line.from || year > line.to {
      continue
    }
    let date = day_at(line.day, year, line.month)
    out.push({
      wall: date.days().to_int64() * 86400L + line.at.to_int64(),
      clock: line.clock,
      save: line.save,
      letter: line.letter,
      is_dst: line.is_dst,
    })
  }
  out.sort_by(earlier)
  out
}

///|
/// One change before another when its clock reads earlier.
fn earlier(a : Change, b : Change) -> Int32 {
  if a.wall < b.wall {
    -1
  } else if a.wall > b.wall {
    1
  } else {
    0
  }
}

///|
/// The instant a change happens, read against the offset in force before it.
fn instant_of(change : Change, offset : Int32, save : Int32) -> Int64 {
  let wall = change.wall
  match change.clock {
    Wall => wall - (offset + save).to_int64()
    Std => wall - offset.to_int64()
    Utc => wall
  }
}

///|
/// The same, with the clock read as the one in force just before the change rather
/// than the stretch's own standard time.
///
/// The difference only shows at a stretch boundary: a rule that fires at the very
/// moment a zone changes its standard offset is placed by the clock that was
/// running a second earlier, which is what zic does and what keeps Argentina's
/// 1999 change from inventing an hour that never happened.
fn placed_at(change : Change, before : Reading0, own_std : Int32) -> Int64 {
  match change.clock {
    Wall => instant_of(change, before.std, before.save)
    // A time given on the standard clock is the standard clock of the stretch it
    // stands in, whatever the stretch before ended on.
    Std => instant_of(change, own_std, 0)
    Utc => change.wall
  }
}

///|
/// The offset and the saving of the reading in force.
priv struct Reading0 {
  std : Int32
  save : Int32
}

///|
/// Where a stretch ends, given the saving in force just before it.
fn edge_of(stretch : Stretch, saving : Int32) -> Int64? raise @zone.Refused {
  match stretch.until {
    Some(fields) => Some(until_instant(fields, stretch.offset, saving))
    None => None
  }
}

///|
/// The instant a stretch ends, read against the offset in force before it.
///
/// A stretch's end takes the same day forms a rule does — `1960 Ap lastSu 2` is
/// the last Sunday of April at two in the morning — because it is the same
/// question asked of a different line.
fn until_instant(
  fields : Array[String],
  offset : Int32,
  save : Int32,
) -> Int64 raise @zone.Refused {
  let year = year_of(fields[0], false)
  let month = if fields.length() > 1 { month_of(fields[1]) } else { 1 }
  let date = if fields.length() > 2 {
    day_at(day_of(fields[2]), year, month)
  } else {
    ({ year, month, day: 1, } : @moondate.Date)
  }
  let (at, clock) = if fields.length() > 3 {
    time_of(fields[3])
  } else {
    (0, Wall)
  }
  let wall = date.days().to_int64() * 86400L + at.to_int64()
  match clock {
    Wall => wall - (offset + save).to_int64()
    Std => wall - offset.to_int64()
    Utc => wall
  }
}

///|
/// The date a day spec names in a month.
fn day_at(day : Day, year : Int32, month : Int32) -> @moondate.Date {
  let last = @moondate.length(year, month)
  match day {
    Dom(n) =>
      { year, month, day: if n < 1 { 1 } else if n > last { last } else { n }, }
    Last(weekday) => {
      let end : @moondate.Date = { year, month, day: last, }
      let back = (end.weekday() - weekday + 7) % 7
      { year, month, day: last - back, }
    }
    From(weekday, n) => {
      // The first such weekday on or after day `n`, which is the day itself when
      // it already falls on that weekday — and a day of the next month when the
      // month has none left: April the twenty-fifth of 1932 was a Monday, so
      // Toronto's `Ap Su>=25` began on the first of May.
      let begin : @moondate.Date = {
        year,
        month,
        day: if n < 1 {
          1
        } else {
          n
        },
      }
      begin.plus_days((weekday - begin.weekday() + 7) % 7)
    }
    To(weekday, n) => {
      let edge = if n > last { last } else if n < 1 { 1 } else { n }
      let end : @moondate.Date = { year, month, day: edge, }
      end.plus_days(-((end.weekday() - weekday + 7) % 7))
    }
  }
}

///|
/// The year an instant falls in, on the UTC clock.
fn year_at(instant : Int64) -> Int32 {
  @moondate.Date::of_days((instant / 86400L).to_int()).year
}

///|
/// The first year any of a rule set's lines speaks about.
fn earliest(lines : Array[Line]) -> Int32 {
  let mut out = 9999
  for line in lines {
    if line.from < out {
      out = line.from
    }
  }
  out
}

///|
/// The abbreviation a format writes, given the letter the rule carries.
///
/// A format is a piece of text with three possible specials: `%s` for the letter,
/// `%z` for the offset written numerically, and a slash separating the standard
/// and daylight-saving names.
fn abbrev_of(
  format : String,
  letter : String,
  offset : Int32,
  is_dst : Bool,
) -> String {
  if format == "%z" {
    return numeric_abbrev(offset)
  }
  let mut slash = -1
  let mut percent = -1
  for k = 0; k < format.length(); k = k + 1 {
    let c = format[k].unsafe_to_char()
    if c == '/' && slash < 0 {
      slash = k
    }
    if c == '%' && percent < 0 {
      percent = k
    }
  }
  if slash >= 0 {
    let head = format[0:slash].to_owned()
    let tail = format[slash + 1:format.length()].to_owned()
    return if is_dst { tail } else { head }
  }
  if percent >= 0 {
    let out = StringBuilder()
    let mut k = 0
    while k < format.length() {
      let c = format[k].unsafe_to_char()
      if c == '%' && k + 1 < format.length() {
        let spec = format[k + 1].unsafe_to_char()
        if spec == 's' {
          // A letter of `-` means the rule has no letter for this change.
          if letter != "-" {
            out.write_string(letter)
          }
        } else if spec == 'z' {
          out.write_string(numeric_abbrev(offset))
        }
        k = k + 2
        continue
      }
      out.write_char(c)
      k = k + 1
    }
    return out.to_string()
  }
  format
}

///|
/// An offset as an abbreviation: `-03`, `+0530`.
fn numeric_abbrev(offset : Int32) -> String {
  let sign = if offset < 0 { "-" } else { "+" }
  let a = if offset < 0 { -offset } else { offset }
  let hh = a / 3600
  let mm = a % 3600 / 60
  if mm == 0 {
    sign + (if hh < 10 { "0" } else { "" }) + hh.to_string()
  } else {
    sign +
    (if hh < 10 { "0" } else { "" }) +
    hh.to_string() +
    (if mm < 10 { "0" } else { "" }) +
    mm.to_string()
  }
}
