// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A date and a time that already names an instant, carried in a zone.
///
/// The instant is the point on the line — `epoch` seconds and `nano` nanoseconds
/// past 1970 — and the zone is what the clocks read at it. The two together are
/// the value Temporal calls a `ZonedDateTime`: move it to another zone and the
/// instant does not move, only the reading does; add a duration and the instant
/// moves by it, whatever a day happens to be here.
///
/// What [`@moondate.Moment`] carries is a `Zone` — a name with the offset in
/// force at that instant beside it. That is a value that can be written and
/// compared with no database in reach, but it cannot cross a change, because a
/// change is a question for the rules. This type is for that: it keeps a `Tz`,
/// the readings and the rule that carries on past them, so a step that lands on
/// the other side of a change reads the new offset back from the rules rather
/// than carrying a stale one forward.
///
///     let zone = @tzdata.load("America/New_York")
///     let zoned = ZonedDateTime::of(2026, 3, 8, hour=2, minute=30, zone~)
///     // 02:30 never happens, so the compatible answer is the later instant
///     zoned.isoformat()            // 2026-03-08T03:30:00-04:00[America/New_York]
///
/// The zone it is built in is what it is filed under. A wall clock that is
/// `Ambiguous` or `Skipped` is answered by [`Fold`]; under `Reject` it raises
/// rather than guessing. A field that is out of range is refused as
/// [`Refused::BadDate`], the calendar and the clock's own refusal carried here.
pub(all) struct ZonedDateTime {
  /// Seconds since 1970-01-01T00:00:00Z, the point on the line.
  epoch : Int64
  /// The nanoseconds of the instant, 0 to 999_999_999.
  nano : Int32
  /// The zone the instant is carried in.
  tz : Tz
}

///|
/// The zone the instant is carried in.
pub fn ZonedDateTime::zone(self : ZonedDateTime) -> Tz {
  self.tz
}

///|
/// The name the zone is filed under.
pub fn ZonedDateTime::zone_name(self : ZonedDateTime) -> String {
  self.tz.name()
}

///|
/// Seconds since 1970-01-01T00:00:00Z, the point on the line.
pub fn ZonedDateTime::epoch(self : ZonedDateTime) -> Int64 {
  self.epoch
}

///|
/// The nanoseconds of the instant, 0 to 999_999_999.
pub fn ZonedDateTime::nanos(self : ZonedDateTime) -> Int32 {
  self.nano
}

///|
/// What the zone read at the instant: the offset, the abbreviation, and whether
/// daylight saving was on.
pub fn ZonedDateTime::reading(self : ZonedDateTime) -> Reading {
  self.tz.at(self.epoch)
}

///|
/// How far east of UTC the zone is at the instant, in seconds.
pub fn ZonedDateTime::offset(self : ZonedDateTime) -> Int32 {
  self.tz.offset(self.epoch)
}

///|
/// How far east of UTC the zone is at the instant, in whole minutes.
///
/// A local mean time that is not a whole number of minutes loses the remainder,
/// which is what an offset written `±HH:MM` says.
pub fn ZonedDateTime::offset_minutes(self : ZonedDateTime) -> Int32 {
  self.offset() / 60
}

///|
/// The abbreviation the zone writes at the instant: `EST`, `EDT`, `UTC`.
pub fn ZonedDateTime::abbrev(self : ZonedDateTime) -> String {
  self.tz.abbrev(self.epoch)
}

///|
/// Whether daylight saving was on at the instant.
pub fn ZonedDateTime::is_dst(self : ZonedDateTime) -> Bool {
  self.tz.is_dst(self.epoch)
}

///|
/// The date the clocks read at the instant, in the zone.
pub fn ZonedDateTime::date(self : ZonedDateTime) -> @moondate.Date {
  let (d, _) = parts_at(self.epoch, self.nano, self.tz)
  d
}

///|
/// The time the clocks read at the instant, in the zone.
pub fn ZonedDateTime::time(self : ZonedDateTime) -> @moondate.Time {
  let (_, t) = parts_at(self.epoch, self.nano, self.tz)
  t
}

///|
/// The year the clocks read at the instant, in the zone.
pub fn ZonedDateTime::year(self : ZonedDateTime) -> Int32 {
  self.date().year
}

///|
/// The month the clocks read at the instant, in the zone, 1 to 12.
pub fn ZonedDateTime::month(self : ZonedDateTime) -> Int32 {
  self.date().month
}

///|
/// The day the clocks read at the instant, in the zone.
pub fn ZonedDateTime::day(self : ZonedDateTime) -> Int32 {
  self.date().day
}

///|
/// The hour the clocks read at the instant, in the zone, 0 to 23.
pub fn ZonedDateTime::hour(self : ZonedDateTime) -> Int32 {
  self.time().hour
}

///|
/// The minute the clocks read at the instant, in the zone, 0 to 59.
pub fn ZonedDateTime::minute(self : ZonedDateTime) -> Int32 {
  self.time().minute
}

///|
/// The second the clocks read at the instant, in the zone, 0 to 59.
///
/// A leap second is kept as the sixtieth second of its minute, the way the clock
/// here does; it is not projected to the next minute.
pub fn ZonedDateTime::second(self : ZonedDateTime) -> Int32 {
  self.time().second
}

///|
/// An instant in a zone, the direction that needs no policy.
///
/// An instant is one instant, and the zone only says what the clocks read at it.
/// This is what an arithmetic step lands on, and what a value is moved to with
/// [`into`].
pub fn ZonedDateTime::from_unix(
  epoch : Int64,
  nano~ : Int32 = 0,
  zone~ : Tz,
) -> ZonedDateTime {
  { epoch, nano, tz: zone, }
}

///|
/// A date and a time in a zone.
///
/// The two hours a year that have no single answer are decided by [`Fold`]: for
/// a wall clock read twice, `Compatible` (the default) takes the earlier instant
/// and `Later` the later; for one that never reads, `Compatible` takes the later
/// instant and `Earlier` the earlier. `Reject` raises for either. A field that
/// is not a date and time the calendar has is refused as [`Refused::BadDate`].
pub fn ZonedDateTime::of(
  year : Int32,
  month : Int32,
  day : Int32,
  hour~ : Int32 = 0,
  minute~ : Int32 = 0,
  second~ : Int32 = 0,
  nano~ : Int32 = 0,
  zone~ : Tz,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let date = @moondate.Date::new(year, month, day) catch {
    e => raise BadDate(e)
  }
  let time = @moondate.Time::new(hour, minute, second~, nano~) catch {
    e => raise BadDate(e)
  }
  let epoch = zone.epoch(date, time, fold~)
  { epoch, nano: time.nano, tz: zone, }
}

///|
/// A moment the caller already has, placed in a zone.
///
/// A moment that names an instant is put in the zone; one that does not — a
/// `Plain` wall clock — is answered by [`Fold`], and `Reject` raises for the
/// hours that have none.
pub fn ZonedDateTime::of_moment(
  moment : @moondate.Moment,
  zone~ : Tz,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  match moment.epoch() {
    Some(epoch) => { epoch, nano: moment.time().nano, tz: zone, }
    None => {
      let date = moment.date().unwrap()
      let epoch = zone.epoch(date, moment.time(), fold~)
      { epoch, nano: moment.time().nano, tz: zone, }
    }
  }
}

///|
/// The same instant carried in another zone.
///
/// The instant does not move; only the reading does. This is what
/// [`@moondate.Moment::astimezone`](moonbitstack/moondate) is, with a whole
/// database in place of a fixed offset.
pub fn ZonedDateTime::into(self : ZonedDateTime, zone : Tz) -> ZonedDateTime {
  { epoch: self.epoch, nano: self.nano, tz: zone, }
}

///|
/// The `Moment` the zone writes for the instant: a `Zoned` that carries the name
/// and the offset in force, so it can be written back with no database in reach.
///
/// This is the round trip that makes [`of`] and the writers agree: read the
/// value back as a moment, and the offset beside it is the one in force.
pub fn ZonedDateTime::moment(self : ZonedDateTime) -> @moondate.Moment {
  self.tz.moment(self.epoch, nano=self.nano)
}

///|
/// The instant as the ISO 8601 text it reads in the zone: the date and time the
/// clocks show, the offset in force beside it, and the name in brackets.
///
///     2026-09-22T14:30:00+08:00[Asia/Shanghai]
///
/// `fraction` is the number of fractional-second digits, 0 to 9; left out, as
/// many as the value needs. A number of digits is a granularity as well: the
/// value is rounded to it first, truncated unless `rounding` says otherwise.
/// `zone_name` leaves the name off when `false`, and `offset` leaves the
/// `±HH:MM` off, which is what a reader that already knows the zone wants.
///
/// `smallest_unit` says the granularity by unit instead: a minute has no seconds
/// to write and a millisecond three digits of a second.
pub fn ZonedDateTime::isoformat(
  self : ZonedDateTime,
  fraction? : Int32,
  zone_name~ : Bool = true,
  offset~ : Bool = true,
  smallest_unit? : @moondate.TimeUnit,
  rounding~ : @moondate.Rounding = Trunc,
  critical~ : Bool = false,
) -> String {
  match smallest_unit {
    Some(unit) => {
      let digits = match unit {
        Millis => 3
        Micros => 6
        Nanos => 9
        _ => 0
      }
      self
      .rounded(smallest_unit=unit, increment=1L, rounding~)
      .moment()
      .isoformat(
        fraction=digits,
        offset~,
        zone_name~,
        smallest_unit=unit,
        critical~,
      )
    }
    None =>
      match fraction {
        None =>
          self.moment().isoformat(fraction?, offset~, zone_name~, critical~)
        Some(count) => {
          let count = if count > 9 { 9 } else if count < 0 { 0 } else { count }
          let step = ten_to(9 - count)
          self
          .snap(step, rounding~)
          .moment()
          .isoformat(fraction=count, offset~, zone_name~, critical~)
        }
      }
  }
}

///|
/// Ten to the power `n`, for the digits of a second.
fn ten_to(n : Int32) -> Int64 {
  let mut out = 1L
  for _ in 0..<n {
    out = out * 10L
  }
  out
}

///|
/// The instant as a sentence: `2026-09-22T14:30:00+08:00 Asia/Shanghai`.
pub fn ZonedDateTime::to_string(self : ZonedDateTime) -> String {
  self.moment().isoformat(offset=true) + " " + self.zone_name()
}

///|
pub impl Show for ZonedDateTime with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub extend ZonedDateTime with Show::{output}

///|
/// The date and time the zone reads at an instant, in whole seconds.
///
/// The instant is split into the seconds it holds and the nanoseconds left over,
/// so a zone whose offset is not a whole second puts the clocks where the instant
/// says and not where the seconds alone would: the nanoseconds come back with the
/// reading, which is what keeps [`of`] and [`from_unix`] inverse.
fn parts_at(
  epoch : Int64,
  nano : Int32,
  tz : Tz,
) -> (@moondate.Date, @moondate.Time) {
  // The reading at an instant is what the zone writes for it, and the date and
  // time are the two halves of that moment.
  let m = tz.moment(epoch, nano~)
  (m.date().unwrap(), m.time())
}

// -- the fields, kept the way Temporal keeps them -----------------------------
//
// A field edit moves one part of the reading and keeps the rest. The question it
// raises is which instant the new reading names, and that is what [`OffsetPolicy`]
// answers with [`Fold`]. The default is Temporal's default: the offset that was
// in force is kept when it still is at the new reading, and when it is not, the
// zone's rules decide.

///|
/// How a field edit keeps the offset that was in force before the edit.
///
/// `Prefer` is the default: the instant the old offset named is kept when that
/// offset is still the one the zone has at the new reading, and when it is not,
/// [`Fold`] decides. `Ignore` goes straight to the zone's rules. `Use` keeps the
/// old offset whatever the zone says, so a change that fell in between moves the
/// reading — the instant does not move, but the date and time and the offset in
/// force do. `Reject` is the offset that refuses: a reading the old offset no
/// longer covers is an error, even when the zone would have answered it, which is
/// the one case the disambiguation is not the one to decide.
#derive(Eq, Debug)
pub(all) enum OffsetPolicy {
  Prefer
  Ignore
  Use
  Reject
}

///|
pub extend OffsetPolicy with Debug::{to_repr}

///|
pub extend OffsetPolicy with Eq::{not_equal, equal}

///|
/// The instant a wall clock names under an offset policy and a disambiguation.
///
/// The candidates are the instant the old offset names and the instant or
/// instants the zone names, and the policy says which is the answer. The
/// disambiguation is consulted only when the zone's rules are the ones deciding,
/// which is the case `Prefer`, `Ignore` and `Reject` all fall into.
fn place(
  date : @moondate.Date,
  time : @moondate.Time,
  tz : Tz,
  old_offset : Int32?,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> Int64 raise Refused {
  let wall = date.days().to_int64() * 86400L + time.nanos() / 1_000_000_000L
  match (offset, old_offset) {
    (Use, Some(old)) => wall - old.to_int64()
    (Ignore, _) => tz.epoch(date, time, fold~)
    (Prefer | Reject, Some(old)) => {
      let candidate = wall - old.to_int64()
      if tz.offset(candidate) == old {
        candidate
      } else if offset == Reject {
        raise Missing(text="the offset is no longer in force at this reading")
      } else {
        tz.epoch(date, time, fold~)
      }
    }
    _ => tz.epoch(date, time, fold~)
  }
}

///|
/// The instant with the year changed, the rest of the reading kept.
pub fn ZonedDateTime::with_year(
  self : ZonedDateTime,
  year : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let d = self.date()
  let date = @moondate.Date::new(year, d.month, d.day) catch {
    e => raise BadDate(e)
  }
  let t = self.time()
  let epoch = place(date, t, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the month changed, the rest of the reading kept. A month that
/// leaves no such day — the thirty-first into February — is refused as
/// [`Refused::BadDate`].
pub fn ZonedDateTime::with_month(
  self : ZonedDateTime,
  month : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let d = self.date()
  let date = @moondate.Date::new(d.year, month, d.day) catch {
    e => raise BadDate(e)
  }
  let t = self.time()
  let epoch = place(date, t, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the day changed, the rest of the reading kept. A day the
/// month does not have is refused as [`Refused::BadDate`].
pub fn ZonedDateTime::with_day(
  self : ZonedDateTime,
  day : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let d = self.date()
  let date = @moondate.Date::new(d.year, d.month, day) catch {
    e => raise BadDate(e)
  }
  let t = self.time()
  let epoch = place(date, t, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the hour changed, the rest of the reading kept.
pub fn ZonedDateTime::with_hour(
  self : ZonedDateTime,
  hour : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let (d, t) = parts_at(self.epoch, self.nano, self.tz)
  let time = t.replace(hour~) catch { e => raise BadDate(e) }
  let epoch = place(d, time, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the minute changed, the rest of the reading kept.
pub fn ZonedDateTime::with_minute(
  self : ZonedDateTime,
  minute : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let (d, t) = parts_at(self.epoch, self.nano, self.tz)
  let time = t.replace(minute~) catch { e => raise BadDate(e) }
  let epoch = place(d, time, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the second changed, the rest of the reading kept.
pub fn ZonedDateTime::with_second(
  self : ZonedDateTime,
  second : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let (d, t) = parts_at(self.epoch, self.nano, self.tz)
  let time = t.replace(second~) catch { e => raise BadDate(e) }
  let epoch = place(d, time, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}

///|
/// The instant with the nanoseconds changed, the rest of the reading kept.
///
/// The offset is in seconds, so the seconds the instant names are not moved: only
/// the fraction is replaced, and the reading is read back from the zone.
pub fn ZonedDateTime::with_nanos(
  self : ZonedDateTime,
  nanos : Int32,
) -> ZonedDateTime {
  { epoch: self.epoch, nano: nanos, tz: self.tz, }
}

// -- the instant, moved the way an instant is moved ---------------------------

///|
/// The instant `span` later, in the same zone.
///
/// The span is added to the point on the line, not to the reading: a day added
/// here is the instant a day later, and if a change falls in between, the reading
/// moves across it. That is what a duration means for an instant, and the one
/// thing that keeps a span added the same however it is split.
pub fn ZonedDateTime::plus(
  self : ZonedDateTime,
  span : @moondate.Span,
) -> ZonedDateTime {
  let total = self.epoch * 1_000_000_000L + self.nano.to_int64() + span.nanos
  let epoch = total / 1_000_000_000L
  let nano = (total % 1_000_000_000L).to_int()
  { epoch, nano, tz: self.tz, }
}

///|
/// The instant `days` later, in the same zone.
pub fn ZonedDateTime::plus_days(
  self : ZonedDateTime,
  days : Int64,
) -> ZonedDateTime {
  self.plus(@moondate.Span::of(@moondate.day, days))
}

///|
/// The instant `months` later, in the same zone.
///
/// A month is a calendar step, so the reading is moved rather than the instant:
/// the same day of the month, clamped to one that exists, is read in the month
/// `months` later, and the offset that was in force is kept if it still is.
/// Across a change the result is not the old instant plus a fixed number of days,
/// because that is not what a month is.
pub fn ZonedDateTime::plus_months(
  self : ZonedDateTime,
  months : Int64,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let d = self.date().plus_months(months.to_int())
  let t = self.time()
  let epoch = place(d, t, self.tz, Some(self.offset()), offset~, fold~)
  { epoch, nano: self.nano, tz: self.tz, }
}
