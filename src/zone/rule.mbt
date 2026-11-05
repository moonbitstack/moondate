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
/// there to allow a quoted name like `<+0545>` and, in the same section, seconds in
/// the offsets.
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
  let _ = text
  raise Malformed(kind="a POSIX TZ string", at=0)
}

///|
/// The string a rule is written as.
pub fn Rule::text(self : Rule) -> String {
  let _ = self
  ""
}

///|
/// What the rule reads at an instant.
pub fn Rule::at(self : Rule, epoch : Int64) -> Reading {
  { epoch, offset: self.std_offset, is_dst: false, abbrev: self.std_abbrev, }
}
