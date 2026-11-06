// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Every name the database knows, the aliases included, in order.
pub fn zones() -> Array[String] {
  let out : Array[String] = []
  for line in lines_of(source_text()) {
    let tokens = tokens_of(line)
    if tokens.length() >= 2 {
      if tokens[0] == "Z" {
        out.push(tokens[1])
      } else if tokens[0] == "L" && tokens.length() >= 3 {
        out.push(tokens[2])
      }
    }
  }
  out.sort_by(by_name)
  out
}

///|
/// One name before another, letter by letter.
///
/// `String` compares by length first, which is a good order for a dictionary and
/// the wrong one for a list of zones: it files `CET` before `Africa/Abidjan`.
fn by_name(a : String, b : String) -> Int32 {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for k = 0; k < shared; k = k + 1 {
    let here = a[k].to_int()
    let there = b[k].to_int()
    if here != there {
      return if here < there { -1 } else { 1 }
    }
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

///|
/// The aliases the database keeps, each with the zone it names: `(alias, zone)`.
///
/// A link is a name a country used to be filed under, or the name of a city that
/// shares a zone with another: `Asia/Calcutta` is `Asia/Kolkata`, and a caller
/// that stored the old name should go on getting the right answer.
pub fn links() -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in lines_of(source_text()) {
    let tokens = tokens_of(line)
    if tokens.length() >= 3 && tokens[0] == "L" {
      out.push((tokens[2], tokens[1]))
    }
  }
  out.sort_by(by_alias)
  out
}

///|
/// One alias before another, by name.
fn by_alias(a : (String, String), b : (String, String)) -> Int32 {
  by_name(a.0, b.0)
}

///|
/// The character at `i`, or a space past the end so a comparison fails rather than
/// reading out of bounds.
fn char_at(s : String, i : Int32) -> Char {
  if i >= 0 && i < s.length() {
    s[i].unsafe_to_char()
  } else {
    ' '
  }
}

///|
/// Why a text could not be read as a moment in a named zone: the text itself, or
/// the zone it names.
pub suberror Refused {
  BadText(@moondate.Refused)
  BadZone(@zone.Refused)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    BadText(e) => logger.write_string(e.to_string())
    BadZone(e) => logger.write_string(e.to_string())
  }
}

///|
pub extend Refused with Show::{to_string, output}

///|
/// A moment read from text whose zone is named by a place.
///
/// [`@moondate.parse`] keeps a place name when the offset is written beside it and
/// refuses it when it is not: the place alone does not say which side of a
/// transition the clock was on. This is the entry point that knows — it reads the
/// place from the database and answers with `fold` for the hour that has none.
///
///     let moment = @tzdata.parse("2026-11-01T01:30:00[America/New_York]")
///     moment.strftime("%H:%M %Z")   // 01:30 EDT
///
/// A text that names an offset rather than a place is answered by
/// [`@moondate.parse`] alone, so this costs a database lookup and nothing else.
pub fn parse(
  text : StringView,
  fold~ : @zone.Fold = @zone.Compatible,
) -> @moondate.Moment raise Refused {
  let s = text.to_owned()
  let mut open = -1
  for i = 0; i < s.length(); i = i + 1 {
    if char_at(s, i) == '[' {
      open = i
      break
    }
  }
  if open < 0 {
    return @moondate.parse(text) catch { e => raise BadText(e) }
  }
  let mut close = open + 1
  while close < s.length() && char_at(s, close) != ']' {
    close = close + 1
  }
  if close >= s.length() {
    raise BadText(@moondate.Malformed("an annotation is written [key=value]"))
  }
  let written = s[open + 1:close].to_owned()
  // `[!UTC]` marks a zone the reader has to understand; the `!` is not its name.
  let name = if written.length() > 0 && char_at(written, 0) == '!' {
    written[1:].to_owned()
  } else {
    written
  }
  let tz = match find(name) {
    Some(tz) => tz
    // Not a place: an offset, a calendar annotation, or something malformed. The
    // root reader knows all three and says what is wrong with the last.
    None => return @moondate.parse(text) catch { e => raise BadText(e) }
  }
  // Drop the zone annotation and keep whatever follows it, so a calendar beside
  // the zone still reaches the reader that understands it.
  let body = s[:open].to_owned() + s[close + 1:].to_owned()
  let moment = @moondate.parse(body) catch { e => raise BadText(e) }
  tz.zoned(moment, fold~) catch {
    e => raise BadZone(e)
  }
}

///|
/// The zone filed under `name`, which may be an alias.
///
/// The zone is compiled from the release's source the first time it is asked for,
/// which is a table of a few hundred readings per zone; a program that needs a
/// dozen zones pays for a dozen.
pub fn load(name : StringView) -> @zone.Tz raise @zone.Refused {
  let wanted = name.to_owned()
  let text = source_text()
  let target = canonical(text, wanted)
  let stretches = stretches_of(text, target)
  let rules : Map[String, Array[Line]] = Map([])
  for stretch in stretches {
    match stretch.saving {
      Named(set) =>
        if !rules.contains(set) {
          rules.set(set, rules_of(text, set))
        }
      _ => ()
    }
  }
  brew(target, stretches, rules)
}

///|
/// The zone filed under `name`, or `None` when the database has no such name.
pub fn find(name : StringView) -> @zone.Tz? {
  Some(load(name)) catch {
    @zone.Malformed(_)
    | @zone.Truncated(..)
    | @zone.Unsupported(_)
    | @zone.Unknown(_)
    | @zone.Missing(_) => None
  }
}

///|
/// The zone an alias names, or the name itself when it is not an alias.
fn canonical(text : String, name : String) -> String {
  for line in lines_of(text) {
    let tokens = tokens_of(line)
    if tokens.length() >= 3 && tokens[0] == "L" && tokens[2] == name {
      return tokens[1]
    }
  }
  name
}

///|
/// The stretches of a zone, in the order they cover the timeline.
fn stretches_of(
  text : String,
  wanted : String,
) -> Array[Stretch] raise @zone.Refused {
  let out : Array[Stretch] = []
  let mut inside = false
  for line in lines_of(text) {
    let tokens = tokens_of(line)
    if tokens.length() == 0 {
      continue
    }
    match tokens[0] {
      "Z" => {
        inside = tokens.length() >= 3 && tokens[1] == wanted
        if inside {
          out.push(stretch_of(tokens, 2))
        }
      }
      "R" | "L" => inside = false
      "#" => ()
      _ =>
        // Everything else is another line of the stretch above it, which is how a
        // zone that changed its clocks a dozen times is written.
        if inside {
          out.push(stretch_of(tokens, 0))
        }
    }
  }
  if out.length() == 0 {
    raise @zone.Unknown(name=wanted)
  }
  out
}

///|
/// One stretch, from the fields that start at `from`: the offset, where the saving
/// comes from, the format, and the year it ends.
fn stretch_of(
  tokens : Array[String],
  from : Int32,
) -> Stretch raise @zone.Refused {
  if tokens.length() < from + 3 {
    raise @zone.Malformed(kind="a zone line", at=0)
  }
  let offset = offset_of(tokens[from])
  let saving = match tokens[from + 1] {
    "-" => None_
    text =>
      if is_saving_letter(text) {
        Fixed(offset_of(text))
      } else {
        Named(text)
      }
  }
  let until = if tokens.length() > from + 3 {
    Some(tokens[from + 3:].to_owned())
  } else {
    None
  }
  ({ offset, saving, format: tokens[from + 2], until, } : Stretch)
}

///|
/// The lines of one rule set.
fn rules_of(text : String, wanted : String) -> Array[Line] raise @zone.Refused {
  let out : Array[Line] = []
  for line in lines_of(text) {
    let tokens = tokens_of(line)
    if tokens.length() < 10 || tokens[0] != "R" || tokens[1] != wanted {
      continue
    }
    let from = year_of(tokens[2], false)
    let to = year_of(tokens[3], true)
    let kind = tokens[4]
    if kind != "-" && !applicable(kind, from) {
      // A rule whose years are described rather than listed applies to the years
      // that description names; the one description the release uses is `-`.
      continue
    }
    let (at, clock) = time_of(tokens[7])
    let letter = tokens[9]
    let mut save = offset_of(tokens[8])
    let mut daylight = save != 0
    // A saving written with a `d` or an `s` says outright which kind of time it
    // is, which matters for a zone whose standard time is the one with the saving:
    // Ireland has called winter its daylight time since 1968.
    let last = tokens[8][tokens[8].length() - 1].unsafe_to_char()
    if last == 'd' {
      daylight = true
      save = offset_of(tokens[8][0:tokens[8].length() - 1].to_owned())
    } else if last == 's' {
      daylight = false
      save = offset_of(tokens[8][0:tokens[8].length() - 1].to_owned())
    }
    out.push({
      from,
      to: if to == -9999 {
        from
      } else {
        to
      },
      month: month_of(tokens[5]),
      day: day_of(tokens[6]),
      at,
      clock,
      save,
      letter,
      is_dst: daylight,
    })
  }
  out
}

///|
/// Whether a year belongs to a rule whose years are described rather than listed.
/// The release lists every year it means, so this only has to answer for the forms
/// the format allows.
fn applicable(kind : String, year : Int32) -> Bool {
  match kind {
    "odd" => year % 2 == 1
    "even" => year % 2 == 0
    // A presidential election year is a leap year, which is the same rule the
    // calendar already knows.
    "uspres" => @moondate.leap(year)
    "nonpres" => !@moondate.leap(year)
    "nonuspres" => !@moondate.leap(year)
    _ => true
  }
}

///|
/// The lines of a text, without the empty one a trailing newline leaves.
fn lines_of(text : String) -> Array[String] {
  let out : Array[String] = []
  for line in text.split("\n") {
    out.push(line.to_owned())
  }
  if out.length() > 0 && out[out.length() - 1] == "" {
    let _ = out.pop()
  }
  out
}

///|
/// The fields of a line, split on runs of spaces and tabs.
fn tokens_of(line : String) -> Array[String] {
  let out : Array[String] = []
  let mut from = -1
  for k = 0; k <= line.length(); k = k + 1 {
    let space = k == line.length() ||
      line[k].unsafe_to_char() == ' ' ||
      line[k].unsafe_to_char() == '\t'
    if space {
      if from >= 0 {
        out.push(line[from:k].to_owned())
        from = -1
      }
    } else if from < 0 {
      from = k
    }
  }
  out
}
