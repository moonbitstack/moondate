// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Which way along the line of changes a zone is asked about.
#derive(Eq, Debug)
pub(all) enum Direction {
  Next
  Previous
}

///|
pub extend Direction with Debug::{to_repr}

///|
pub extend Direction with Eq::{not_equal, equal}

///|
/// The date and the time the clocks read at the instant.
fn wall_of(value : ZonedDateTime) -> (@moondate.Date, @moondate.Time) {
  parts_at(value.epoch, value.nano, value.tz)
}

///|
/// The instant a wall clock names in the zone this value is carried in, keeping
/// the offset that was in force before the edit where the zone still has it.
fn instant_at(
  value : ZonedDateTime,
  date : @moondate.Date,
  time : @moondate.Time,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> Int64 raise Refused {
  place(date, time, value.tz, Some(value.offset()), offset~, fold~)
}

///|
/// The instant a wall clock names, answered the way the default disambiguation
/// answers it and without the error a refusal would raise.
///
/// The default answer never refuses — a clock that reads twice takes the earlier
/// reading and one that reads never takes the later — so this is the same instant
/// [`Fold::Compatible`] gives, written where a caller has no error to raise.
fn instant_compatible(
  tz : Tz,
  date : @moondate.Date,
  time : @moondate.Time,
) -> Int64 {
  match tz.read(date, time) {
    Exact(instant~) => instant
    Ambiguous(earlier~, ..) => earlier
    Skipped(later~, ..) => later
  }
}

///|
/// The value with some of its fields replaced, the rest of the reading kept.
///
/// The fields are the ones a wall clock has: a field left out keeps the reading
/// it had. A day the month does not have is clamped to the last one it has,
/// unless `strict` is set, which refuses it instead — the calendar's own choice
/// for a field edit is to fit the value into the month rather than to lose it.
///
/// Whether the new reading names one instant, two or none is decided by
/// [`OffsetPolicy`]: the offset in force is kept when the zone still has it at
/// the new reading, and the zone's rules answer when it does not.
pub fn ZonedDateTime::with_fields(
  self : ZonedDateTime,
  year? : Int32,
  month? : Int32,
  day? : Int32,
  hour? : Int32,
  minute? : Int32,
  second? : Int32,
  nano? : Int32,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
  strict~ : Bool = false,
) -> ZonedDateTime raise Refused {
  let (was_date, was_time) = wall_of(self)
  let year = year.unwrap_or(was_date.year)
  let month = if strict {
    month.unwrap_or(was_date.month)
  } else {
    clamp_month(month.unwrap_or(was_date.month))
  }
  let day = day.unwrap_or(was_date.day)
  let date = @moondate.Date::new(
    year,
    month,
    if strict {
      day
    } else {
      clamp_day(year, month, day)
    },
  ) catch {
    e => raise BadDate(e)
  }
  let hour = hour.unwrap_or(was_time.hour)
  let minute = minute.unwrap_or(was_time.minute)
  let second = second.unwrap_or(was_time.second)
  let nano = nano.unwrap_or(was_time.nano)
  // A field that is out of range is folded into it when the edit is allowed to
  // fit rather than refuse: an hour of twenty-five is eleven at night, the way a
  // day of thirty-one in a thirty-day month is the thirtieth.
  let (date, time) = if strict {
    let time = @moondate.Time::new(hour, minute, second~, nano~) catch {
      e => raise BadDate(e)
    }
    (date, time)
  } else {
    let time = @moondate.Time::new(
      clamp(hour, 0, 23),
      clamp(minute, 0, 59),
      second=clamp(second, 0, 59),
      nano=clamp(nano, 0, 999_999_999),
    ) catch {
      e => raise BadDate(e)
    }
    (date, time)
  }
  let epoch = instant_at(self, date, time, offset~, fold~)
  { epoch, nano: time.nano, tz: self.tz, }
}

///|
/// The last day `month` has in `year`, for a field edit that lands on one the
/// month does not have.
fn clamp_day(year : Int32, month : Int32, day : Int32) -> Int32 {
  let last = @moondate.length(year, month)
  if day > last {
    last
  } else if day < 1 {
    1
  } else {
    day
  }
}

///|
/// A number folded into a range, for a field edit that fits rather than refuses.
fn clamp(n : Int32, low : Int32, high : Int32) -> Int32 {
  if n < low {
    low
  } else if n > high {
    high
  } else {
    n
  }
}

///|
/// A month folded into the twelve a year has, for a field edit that is allowed to
/// fit rather than refuse.
fn clamp_month(month : Int32) -> Int32 {
  if month < 1 {
    1
  } else if month > 12 {
    12
  } else {
    month
  }
}

///|
/// The value with its time of day replaced, the date kept.
///
/// A new reading can fall in an hour the clocks skip or repeat, and [`Fold`] is
/// what decides which instant it names.
pub fn ZonedDateTime::with_plain_time(
  self : ZonedDateTime,
  time : @moondate.Time,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  let (date, _) = wall_of(self)
  let epoch = instant_at(self, date, time, offset~, fold~)
  { epoch, nano: time.nano, tz: self.tz, }
}

///|
/// The same instant in the same zone: two values are equal when they name one
/// instant and are filed under one name.
///
/// A fixed offset and a named zone that happens to have that offset at that
/// instant are not equal, because the values are not interchangeable: one can
/// answer for tomorrow and the other cannot.
pub fn ZonedDateTime::equals(
  self : ZonedDateTime,
  other : ZonedDateTime,
) -> Bool {
  self.epoch == other.epoch &&
  self.nano == other.nano &&
  self.zone_name() == other.zone_name()
}

///|
/// The instants ordered: negative when this one is earlier.
pub fn ZonedDateTime::compare(
  self : ZonedDateTime,
  other : ZonedDateTime,
) -> Int32 {
  if self.epoch != other.epoch {
    return if self.epoch < other.epoch { -1 } else { 1 }
  }
  if self.nano != other.nano {
    return if self.nano < other.nano { -1 } else { 1 }
  }
  0
}

///|
/// The first instant of the day the clocks read at this one: midnight, or the
/// moment the clocks jumped to midnight when they skipped it.
pub fn ZonedDateTime::start_of_day(self : ZonedDateTime) -> ZonedDateTime {
  let (date, _) = wall_of(self)
  {
    epoch: instant_compatible(self.tz, date, @moondate.midnight),
    nano: 0,
    tz: self.tz,
  }
}

///|
/// How many hours the day the clocks read at this instant holds.
///
/// Twenty-four, except on the two days a year the clocks change: the day they go
/// forward is short and the day they go back is long, by the size of the change.
pub fn ZonedDateTime::hours_in_day(self : ZonedDateTime) -> Int32 {
  let (date, _) = wall_of(self)
  let start = instant_compatible(self.tz, date, @moondate.midnight)
  let end = instant_compatible(self.tz, date.plus_days(1), @moondate.midnight)
  ((end - start) / 3600L).to_int()
}

///|
/// The next or the previous moment the zone's offset changed, as a value in the
/// same zone, or `None` when the zone has no such change left.
///
/// The search runs past the end of the file's table into the rule that carries
/// on after it, so a zone whose table stops in 2037 still answers for a century
/// after that.
pub fn ZonedDateTime::get_time_zone_transition(
  self : ZonedDateTime,
  direction~ : Direction,
) -> ZonedDateTime? {
  match self.tz.transition(self.epoch, direction~) {
    Some(epoch) => Some({ epoch, nano: 0, tz: self.tz, })
    None => None
  }
}
