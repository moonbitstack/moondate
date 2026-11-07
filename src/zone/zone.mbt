// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a zone, a rule or a wall clock was refused.
///
/// A zone database is a binary format with a version byte, a set of rules whose
/// text is a small language of its own, and a question — which instant does this
/// clock name — that has no answer for one hour a year in most of the world.
/// Each of those fails in its own way, and the message says which.
#derive(Eq, Debug)
pub(all) suberror Refused {
  /// The bytes are not a TZif file, or are one this reader does not know how to
  /// walk. `at` is the byte offset where reading stopped.
  Malformed(kind~ : String, at~ : Int32)
  /// Fewer bytes than the header promised.
  Truncated(want~ : Int32, got~ : Int32)
  /// A TZif version this reader does not implement, `'1'` to `'4'` being the ones
  /// it does.
  Unsupported(version~ : Char)
  /// A zone name no database has.
  Unknown(name~ : String)
  /// A wall clock that names no instant, refused by [`Fold::Reject`].
  Missing(text~ : String)
  /// A field of a date and time that is out of range, the refusal the calendar
  /// and the clock give: the day the month does not have, the second that is not
  /// a clock reading. It is carried here rather than raised by the package that
  /// does not have a calendar of its own, so a `ZonedDateTime` built from fields
  /// refuses with one type for both what is out of range and what the zone would
  /// not place.
  BadDate(@moondate.Refused)
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Malformed(kind~, at~) =>
      logger.write_string("\{kind} is malformed at byte \{at}")
    Truncated(want~, got~) =>
      logger.write_string("wanted \{want} bytes, got \{got}")
    Unsupported(version~) =>
      logger.write_string(
        "TZif version \{version} is not one this reader reads",
      )
    Unknown(name~) => logger.write_string("no such zone: \{name}")
    Missing(text~) => logger.write_string("this clock never happens: \{text}")
    BadDate(e) => logger.write_string(e.to_string())
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// What a zone reads at one instant: the offset in force, whether daylight saving
/// was on, and the abbreviation written for it.
///
/// `epoch` is when the reading began, not the instant it was asked about, so a
/// table of readings doubles as the list of changes.
#derive(Eq, Debug)
pub(all) struct Reading {
  epoch : Int64
  offset : Int32
  is_dst : Bool
  abbrev : String
}

///|
pub extend Reading with Debug::{to_repr}

///|
pub extend Reading with Eq::{not_equal, equal}

///|
/// Which side of a fold a wall clock lands on.
///
/// Most zones move their clocks twice a year, so one hour of the year happens
/// twice and another never happens at all. Asking a zone for an instant from a
/// wall clock therefore has three defensible answers and one that refuses.
///
/// `Compatible` is what Python's `fold=0` and Temporal's `disambiguation:
/// "compatible"` both do: the first of two repeated hours, the second of two
/// skipped ones. `Earlier` and `Later` pick by instant. Python's `fold=1` is
/// `Later` for a repeated clock and `Earlier` for a skipped one.
#derive(Eq, Debug)
pub(all) enum Fold {
  Compatible
  Earlier
  Later
  Reject
}

///|
pub extend Fold with Debug::{to_repr}

///|
pub extend Fold with Eq::{not_equal, equal}

///|
/// The instants a wall clock names in a zone.
///
/// Zero, one or two, and the difference is not an edge case: a timestamp written
/// by a program in a zone that observes daylight saving is ambiguous for one hour
/// every autumn and impossible for one hour every spring, and both have to be
/// handled rather than papered over.
#derive(Eq, Debug)
pub(all) enum Local {
  /// One instant, the usual case.
  Exact(instant~ : Int64)
  /// The clock happens twice. `earlier` is the reading before the clocks went
  /// back, `later` the one after.
  Ambiguous(earlier~ : Int64, later~ : Int64)
  /// The clock never happens, because the clocks went forward over it.
  /// `earlier` is where the text lands read by the offset after the change,
  /// `later` where it lands read by the offset before it.
  Skipped(earlier~ : Int64, later~ : Int64)
}

///|
pub extend Local with Debug::{to_repr}

///|
pub extend Local with Eq::{not_equal, equal}

///|
/// A `Local` as a sentence: `once, at 1793511000`, `twice, at 1793511000 and
/// 1793514600`, `never, between 1772951400 and 1772955000`.
pub impl Show for Local with fn output(self, logger) {
  match self {
    Exact(instant~) => logger.write_string("once, at \{instant}")
    Ambiguous(earlier~, later~) =>
      logger.write_string("twice, at \{earlier} and \{later}")
    Skipped(earlier~, later~) =>
      logger.write_string("never, between \{earlier} and \{later}")
  }
}

///|
pub extend Local with Show::{to_string, output}

///|
/// The instant a wall clock names, under a policy for the two hours a year that
/// have no single answer.
pub fn Local::epoch(
  self : Local,
  fold~ : Fold = Compatible,
) -> Int64 raise Refused {
  match self {
    Exact(instant~) => instant
    Ambiguous(earlier~, later~) =>
      match fold {
        Earlier => earlier
        Later => later
        Compatible => earlier
        Reject =>
          raise Missing(
            text="the clock reads twice, at \{earlier} and \{later}",
          )
      }
    Skipped(earlier~, later~) =>
      match fold {
        Earlier => earlier
        Later => later
        Compatible => later
        Reject =>
          raise Missing(
            text="the clock never reads, between \{earlier} and \{later}",
          )
      }
  }
}

///|
/// Whether the wall clock names exactly one instant.
pub fn Local::is_exact(self : Local) -> Bool {
  match self {
    Exact(_) => true
    _ => false
  }
}

///|
/// A zone: the readings it went through, in order, and the rule that carries on
/// after the last of them.
///
/// The first reading is the one in force from the beginning of time; each later
/// one starts at its own `epoch`. The rule is what a TZif file's footer holds and
/// what makes a date a century out answerable without a table that long.
pub struct Tz {
  name : String
  readings : Array[Reading]
  rule : Rule?
}

///|
/// The name the zone is filed under.
pub fn Tz::name(self : Tz) -> String {
  self.name
}

///|
/// The readings the zone has been through, oldest first.
pub fn Tz::readings(self : Tz) -> Array[Reading] {
  self.readings
}

///|
/// The rule that carries on past the last reading, when the zone has one.
pub fn Tz::rule(self : Tz) -> Rule? {
  self.rule
}

///|
/// What the zone reads at an instant.
pub fn Tz::at(self : Tz, epoch : Int64) -> Reading {
  let readings = self.readings
  // Past the table the rule decides, which is what a TZif footer is for.
  if readings.length() == 0 {
    return { epoch, offset: 0, is_dst: false, abbrev: "UTC", }
  }
  let last = readings[readings.length() - 1]
  match self.rule {
    Some(rule) if epoch >= last.epoch => return rule.at(epoch)
    _ => ()
  }
  let mut lo = 0
  let mut hi = readings.length() - 1
  let mut found = 0
  while lo <= hi {
    let mid = (lo + hi) / 2
    if readings[mid].epoch <= epoch {
      found = mid
      lo = mid + 1
    } else {
      hi = mid - 1
    }
  }
  readings[found]
}

///|
/// How far east of UTC the zone is at an instant, in seconds.
pub fn Tz::offset(self : Tz, epoch : Int64) -> Int32 {
  self.at(epoch).offset
}

///|
/// The abbreviation the zone writes at an instant.
pub fn Tz::abbrev(self : Tz, epoch : Int64) -> String {
  self.at(epoch).abbrev
}

///|
/// Whether daylight saving was on at an instant.
pub fn Tz::is_dst(self : Tz, epoch : Int64) -> Bool {
  self.at(epoch).is_dst
}

///|
/// The readings that begin between two instants, `from` included and `to` not.
pub fn Tz::changes(self : Tz, from~ : Int64, to~ : Int64) -> Array[Reading] {
  let out : Array[Reading] = []
  for reading in self.readings {
    if reading.epoch >= from && reading.epoch < to {
      out.push(reading)
    }
  }
  out
}

///|
/// The instants a wall clock names in this zone.
pub fn Tz::read(
  self : Tz,
  date : @moondate.Date,
  time : @moondate.Time,
) -> Local {
  resolve(self, date.days().to_int64() * 86400L + time.nanos() / 1_000_000_000L)
}

///|
/// The instant a wall clock names, under a policy for the two hours a year that
/// have no single answer.
pub fn Tz::epoch(
  self : Tz,
  date : @moondate.Date,
  time : @moondate.Time,
  fold~ : Fold = Compatible,
) -> Int64 raise Refused {
  self.read(date, time).epoch(fold~)
}

///|
/// The instant `epoch` read in this zone.
///
/// This is the direction that needs no policy: an instant is one instant, and the
/// zone only says what the clock read at it.
pub fn Tz::moment(
  self : Tz,
  epoch : Int64,
  nano~ : Int32 = 0,
) -> @moondate.Moment {
  let reading = self.at(epoch)
  @moondate.Moment::of_epoch(
    epoch,
    nano~,
    zone=Named({
      name: self.name,
      offset: reading.offset,
      abbrev: reading.abbrev,
    }),
  )
}

///|
/// A wall clock pinned to this zone.
///
/// A moment that already names an instant is moved to this zone instead, which is
/// what [`@moondate.Moment::astimezone`](moonbitstack/moondate) does with a fixed
/// offset and this does with a whole database.
pub fn Tz::zoned(
  self : Tz,
  moment : @moondate.Moment,
  fold~ : Fold = Compatible,
) -> @moondate.Moment raise Refused {
  match moment.epoch() {
    Some(instant) => self.moment(instant, nano=moment.time().nano)
    None => {
      let instant = self.epoch(moment.date().unwrap(), moment.time(), fold~)
      self.moment(instant, nano=moment.time().nano)
    }
  }
}

///|
/// A zone built from readings that were computed elsewhere.
///
/// The first reading is the one in force from the beginning of time; the rest
/// each begin at their own `epoch`. A zone database that is not a TZif file — a
/// table of its own, a test fixture — comes in through here.
pub fn Tz::of(name~ : String, readings~ : Array[Reading], rule? : Rule) -> Tz {
  { name, readings, rule, }
}

///|
/// The instants a wall clock names, given the seconds since the epoch that the
/// clock would name if UTC were the truth.
fn resolve(tz : Tz, wall : Int64) -> Local {
  // The two candidate offsets are the readings either side of the wall clock read
  // as if it were UTC; a transition inside the gap between them is what makes the
  // answer ambiguous or empty.
  let before = tz.at(wall - 86400L)
  let after = tz.at(wall + 86400L)
  let first = wall - before.offset.to_int64()
  let second = wall - after.offset.to_int64()
  if first == second {
    return Exact(instant=first)
  }
  // Both candidates have to agree with the offset the zone actually had at them.
  let ok_first = tz.offset(first) == before.offset
  let ok_second = tz.offset(second) == after.offset
  let early = if first < second { first } else { second }
  let late = if first < second { second } else { first }
  if ok_first && ok_second {
    Ambiguous(earlier=early, later=late)
  } else if ok_first {
    Exact(instant=first)
  } else if ok_second {
    Exact(instant=second)
  } else {
    Skipped(earlier=early, later=late)
  }
}
