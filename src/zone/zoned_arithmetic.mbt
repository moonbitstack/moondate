// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A period added to an instant, the way a calendar adds one.
///
/// The date part is added to the wall clock and read back in the zone, so a day
/// added across a change is a day on the calendar and not twenty-four hours; the
/// clock part is added to the instant, because an hour is an hour wherever it
/// falls. That split is what makes `add(day)` and `add(24 hours)` different
/// answers in most of the world, and both of them right.
pub fn ZonedDateTime::add(
  self : ZonedDateTime,
  period : @moondate.Period,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  if period.has_mixed_sign() {
    raise Missing(text="the fields of the period do not run the same way")
  }
  let (date, time) = wall_of(self)
  let moved = date
    .plus_months((period.years * 12L + period.months).to_int())
    .plus_days((period.weeks * 7L + period.days).to_int())
  let epoch = instant_at(self, moved, time, offset~, fold~)
  let total = epoch * 1_000_000_000L +
    self.nano.to_int64() +
    period.span().nanos
  let seconds = floor_div(total, 1_000_000_000L)
  let nano = (total - seconds * 1_000_000_000L).to_int()
  { epoch: seconds, nano, tz: self.tz, }
}

///|
/// A period taken away: the same as [`add`] with every field negated, which is
/// not the same as taking the instant back by the span the period holds.
pub fn ZonedDateTime::subtract(
  self : ZonedDateTime,
  period : @moondate.Period,
  offset~ : OffsetPolicy = Prefer,
  fold~ : Fold = Compatible,
) -> ZonedDateTime raise Refused {
  self.add(period.neg(), offset~, fold~)
}

///|
/// How far ahead of this value another one is, in the units asked for.
///
/// `largest_unit` is the biggest field the answer may use — a difference of
/// thirty days is `P1M` or `P30D` depending on it, and only the calendar can tell
/// which — and is an hour when left out, since an instant is a count of time
/// first. `smallest_unit` with `rounding` is how finely it is measured: a
/// difference of 25 hours is 1 day when asked for in days, and 2 when rounded up.
///
/// The answer's sign is the direction from this value to the other one.
pub fn ZonedDateTime::until(
  self : ZonedDateTime,
  other : ZonedDateTime,
  largest_unit? : @moondate.TimeUnit,
  smallest_unit? : @moondate.TimeUnit,
  rounding~ : @moondate.Rounding = Trunc,
  increment~ : Int64 = 1L,
) -> @moondate.Period raise Refused {
  difference(self, other, largest_unit?, smallest_unit?, rounding~, increment~)
}

///|
/// How far behind this value another one is.
///
/// The reading is [`until`]'s, negated: a difference is not symmetric in a
/// calendar — a month forward from the thirty-first of January lands on the
/// twenty-eighth of February, and the way back is thirty-one days — so the count
/// is taken from this value's side and then turned round, which is what makes
/// `a.since(b)` the negative of `a.until(b)`.
pub fn ZonedDateTime::since(
  self : ZonedDateTime,
  other : ZonedDateTime,
  largest_unit? : @moondate.TimeUnit,
  smallest_unit? : @moondate.TimeUnit,
  rounding~ : @moondate.Rounding = Trunc,
  increment~ : Int64 = 1L,
) -> @moondate.Period raise Refused {
  difference(
    self,
    other,
    largest_unit?,
    smallest_unit?,
    rounding=mirrored(rounding),
    increment~,
  ).neg()
}

///|
/// The same rounding seen from the other side: a length counted backwards rounds
/// up where the same length counted forwards rounds down.
fn mirrored(rounding : @moondate.Rounding) -> @moondate.Rounding {
  match rounding {
    Ceil => Floor
    Floor => Ceil
    HalfCeil => HalfFloor
    HalfFloor => HalfCeil
    _ => rounding
  }
}

///|
/// The largest unit a difference may use, given what was asked for.
///
/// An hour is the default, because an instant is a count of time first; a
/// smallest unit above it lifts the largest, because a difference asked for in
/// whole days cannot be answered in hours. Asking for a largest unit below the
/// smallest one is not a difference anyone can want, and it is refused rather
/// than quietly reordered.
fn largest_unit_of(
  largest_unit : @moondate.TimeUnit?,
  smallest_unit : @moondate.TimeUnit?,
) -> @moondate.TimeUnit raise Refused {
  match (largest_unit, smallest_unit) {
    (Some(largest), Some(smallest)) =>
      if rank(smallest) > rank(largest) {
        raise Range(text="the smallest unit is larger than the largest one")
      } else {
        largest
      }
    (Some(largest), None) => largest
    (None, Some(smallest)) =>
      if rank(smallest) > rank(Hours) {
        smallest
      } else {
        Hours
      }
    (None, None) => Hours
  }
}

///|
/// The increment a difference may be measured by.
///
/// A step has to land on the unit again — there is no fifteen past the hour in a
/// clock of eleven-minute steps — and a calendar unit is only stepped above one
/// when it is the whole answer, since half a month is not a month.
fn check_step(
  unit : @moondate.TimeUnit,
  increment : Int64,
  largest : @moondate.TimeUnit,
) -> Unit raise Refused {
  if increment < 1L {
    raise Range(text="the increment is not a positive number")
  }
  if !unit.is_exact() {
    if increment != 1L && unit != largest {
      raise Range(
        text="a calendar unit is stepped by one unless it is the whole answer",
      )
    }
    return
  }
  let limit = match unit {
    Hours => 24L
    Minutes | Seconds => 60L
    _ => 1000L
  }
  if increment >= limit || limit % increment != 0L {
    raise Range(text="the increment does not divide the unit it steps by")
  }
}

///|
/// The span from one value to another, before any rounding.
fn difference(
  start : ZonedDateTime,
  end : ZonedDateTime,
  largest_unit? : @moondate.TimeUnit,
  smallest_unit? : @moondate.TimeUnit,
  rounding~ : @moondate.Rounding,
  increment~ : Int64,
) -> @moondate.Period raise Refused {
  // The increment is read and checked whether or not a smallest unit names what
  // it steps: a count of steps has to be a positive whole number of them, and a
  // thousand million is the most a unit is ever cut into.
  if increment < 1L || increment > 1_000_000_000L {
    raise Range(text="the increment is not a number of steps a unit can take")
  }
  let largest = largest_unit_of(largest_unit, smallest_unit)
  if start.epoch == end.epoch && start.nano == end.nano {
    return @moondate.zero
  }
  let exact = difference_exact(start, end, largest)
  match smallest_unit {
    None => exact
    Some(unit) => {
      check_step(unit, increment, largest)
      if largest.is_exact() {
        // Below a day every unit has one length, so rounding the count of
        // nanoseconds and writing it out again is the whole of the question.
        let span = nanos_between(start, end)
        balance(
          @moondate.round_increment(
            span,
            unit.nanos().unwrap() * increment,
            rounding,
          ),
          largest,
        )
      } else {
        round_difference(
          origin_of(start),
          nanos_between(start, end),
          exact,
          largest,
          unit,
          rounding,
          increment,
        )
      }
    }
  }
}

///|
/// The difference with the fields the largest unit allows and nothing rounded.
///
/// Below a day every unit has the same length, so the answer is the instant
/// difference written out. From a day up the calendar decides, and a day is as
/// long as the clocks make it: the difference is taken on the wall clock, with
/// the remainder — the part of the day the reading is short of — measured on the
/// instant.
fn difference_exact(
  start : ZonedDateTime,
  end : ZonedDateTime,
  largest : @moondate.TimeUnit,
) -> @moondate.Period raise Refused {
  if largest.is_exact() {
    return balance_between(start, end, largest)
  }
  let sign = end.compare(start)
  if sign == 0 {
    return @moondate.zero
  }
  let (start_date, start_time) = wall_of(start)
  let (end_date, end_time) = wall_of(end)
  // The same day on the wall clock: what is left is a count of time, and the
  // clock part of an answer is written from hours down whatever the date part
  // was allowed to use.
  if start_date == end_date {
    return balance_between(start, end, Hours)
  }
  let mut correction = 0
  if (end_time.nanos() - start_time.nanos()) * sign.to_int64() < 0L {
    correction = 1
  }
  // At most two days of correction: one for a reading short of the other, and
  // one more when a change of offset falls in the day that correction moved
  // across.
  let limit = if sign > 0 { 2 } else { 1 }
  while true {
    let middle = end_date.plus_days(-correction * sign)
    let middle_epoch = start.tz.epoch(middle, start_time)
    // The comparison is on the instant, nanoseconds and all: a middle reading in
    // the same second as the end but after it in the fraction is past it. It is a
    // comparison of two instants, so it has no limit — a difference of three
    // centuries is a difference all the same.
    let towards = apart_of(middle_epoch - start.epoch, 0L).compare(
      apart_between(start, end),
    )
    let reached = if sign > 0 { towards <= 0 } else { towards >= 0 }
    if correction == limit || reached {
      let dates = start_date.until(middle, largest_unit=largest)
      let rest = (end.epoch - middle_epoch) * 1_000_000_000L +
        end.nano.to_int64() -
        start.nano.to_int64()
      let time = balance(rest, Hours)
      return {
        years: dates.years,
        months: dates.months,
        weeks: dates.weeks,
        days: dates.days,
        hours: time.hours,
        minutes: time.minutes,
        seconds: time.seconds,
        nanos: time.nanos,
      }
    }
    correction = correction + 1
  }
  @moondate.zero
}

///|
/// How big a unit is next to another: a nanosecond is 0, so a bigger number is a
/// longer unit.
fn rank(unit : @moondate.TimeUnit) -> Int32 {
  match unit {
    Nanos => 0
    Micros => 1
    Millis => 2
    Seconds => 3
    Minutes => 4
    Hours => 5
    Days => 6
    Weeks => 7
    Months => 8
    Years => 9
  }
}

///|
/// How far one instant is from another, written in the fields from `largest` down.
///
/// The two parts are what the answer is counted in rather than one number: a
/// difference of three centuries is nine thousand million hours, which no count of
/// nanoseconds holds and a field of a duration does.
fn balance_between(
  start : ZonedDateTime,
  end : ZonedDateTime,
  largest : @moondate.TimeUnit,
) -> @moondate.Period raise Refused {
  let apart = apart_between(start, end)
  if rank(largest) < rank(Seconds) {
    // Below a second the answer is a count of nanoseconds, and a difference that
    // long has none to be written as.
    match apart.as_nanos() {
      Some(total) => return balance(total, largest)
      None =>
        raise Range(
          text="the difference is longer than a count of nanoseconds holds",
        )
    }
  }
  if rank(largest) > rank(Days) {
    // A year, a month or a week is a calendar's answer and comes from `until` on
    // the dates, not from a count of time.
    raise Range(text="the unit a difference is written in is a calendar one")
  }
  let negative = apart.seconds < 0L
  let sign = if negative { -1L } else { 1L }
  let mut seconds = if negative { -apart.seconds } else { apart.seconds }
  let mut nanos = apart.nanos
  if negative && nanos != 0L {
    seconds = seconds - 1L
    nanos = 1_000_000_000L - nanos
  }
  let days = seconds / 86_400L
  let rest = seconds % 86_400L
  let hours = rest / 3_600L
  let minutes = rest % 3_600L / 60L
  let seconds_field = rest % 60L
  if rank(largest) >= rank(Days) {
    {
      ..@moondate.zero,
      days: days * sign,
      hours: hours * sign,
      minutes: minutes * sign,
      seconds: seconds_field * sign,
      nanos: nanos * sign,
    }
  } else if largest == Hours {
    {
      ..@moondate.zero,
      hours: (days * 24L + hours) * sign,
      minutes: minutes * sign,
      seconds: seconds_field * sign,
      nanos: nanos * sign,
    }
  } else if largest == Minutes {
    {
      ..@moondate.zero,
      minutes: (days * 1_440L + hours * 60L + minutes) * sign,
      seconds: seconds_field * sign,
      nanos: nanos * sign,
    }
  } else {
    {
      ..@moondate.zero,
      seconds: (days * 86_400L + rest) * sign,
      nanos: nanos * sign,
    }
  }
}

///|
/// A count of nanoseconds as the fields from `largest` down.
fn balance(total : Int64, largest : @moondate.TimeUnit) -> @moondate.Period {
  let sign = if total < 0L { -1L } else { 1L }
  let mut rest = if total < 0L { -total } else { total }
  let top = rank(largest)
  let mut days = 0L
  let mut hours = 0L
  let mut minutes = 0L
  let mut seconds = 0L
  if top >= 6 {
    days = rest / 86_400_000_000_000L
    rest = rest % 86_400_000_000_000L
  }
  if top >= 5 {
    hours = rest / 3_600_000_000_000L
    rest = rest % 3_600_000_000_000L
  }
  if top >= 4 {
    minutes = rest / 60_000_000_000L
    rest = rest % 60_000_000_000L
  }
  if top >= 3 {
    seconds = rest / 1_000_000_000L
    rest = rest % 1_000_000_000L
  }
  {
    years: 0L,
    months: 0L,
    weeks: 0L,
    days: days * sign,
    hours: hours * sign,
    minutes: minutes * sign,
    seconds: seconds * sign,
    nanos: rest * sign,
  }
}

///|
/// The period with everything below `unit` dropped.

///|
/// The instant moved to the nearest multiple of a unit, in this zone.
///
/// A day is the one unit whose length is not fixed: on the day the clocks change
/// it is short or long, and rounding to it means the day the zone is having, so
/// the two boundaries are the start of that day and the start of the next one.
/// Every other unit is a count of time, and rounds the instant itself.
pub fn ZonedDateTime::round(
  self : ZonedDateTime,
  smallest_unit~ : @moondate.TimeUnit,
  increment~ : Int64 = 1L,
  rounding~ : @moondate.Rounding = HalfExpand,
) -> ZonedDateTime raise Refused {
  if increment < 1L {
    raise Missing(text="the increment is not a positive number")
  }
  check_increment(smallest_unit, increment)
  if rank(smallest_unit) >= 7 {
    raise Missing(
      text="a week, a month and a year are not lengths an instant rounds to",
    )
  }
  if smallest_unit == Days {
    let (date, _) = wall_of(self)
    let length = day_length(self.tz, date)
    if length <= 0L {
      raise Missing(text="the day this reading is in has no length")
    }
  }
  self.rounded(smallest_unit~, increment~, rounding~)
}

///|
/// Refuse an increment a unit cannot be stepped by.
///
/// A step has to land on the unit again: there is no fifteen past the hour in a
/// clock of five-minute steps, and a day is the largest unit an instant rounds
/// to, so it has no step but one.
fn check_increment(
  unit : @moondate.TimeUnit,
  increment : Int64,
) -> Unit raise Refused {
  let limit = match unit {
    Hours => 24L
    Minutes | Seconds => 60L
    Millis | Micros | Nanos => 1000L
    _ => 1L
  }
  if unit == Days {
    if increment != 1L {
      raise Missing(text="a day is not stepped by more than one")
    }
    return
  }
  if rank(unit) >= 7 {
    return
  }
  if increment >= limit || limit % increment != 0L {
    raise Missing(text="the increment does not divide the unit it steps by")
  }
}

///|
/// How many nanoseconds the day a date names lasts in a zone.
fn day_length(tz : Tz, date : @moondate.Date) -> Int64 {
  (
    instant_compatible(tz, date.plus_days(1), @moondate.midnight) -
    instant_compatible(tz, date, @moondate.midnight)
  ) *
  1_000_000_000L
}

///|
/// [`round`] without the two checks: the increments a text form uses are one, and
/// a day of no length is not a day any zone has.
fn ZonedDateTime::rounded(
  self : ZonedDateTime,
  smallest_unit~ : @moondate.TimeUnit,
  increment~ : Int64,
  rounding~ : @moondate.Rounding,
) -> ZonedDateTime {
  if rank(smallest_unit) >= 7 {
    // A value is not rounded to a week, a month or a year: those are lengths a
    // calendar gives a reading, not steps an instant can be moved by.
    return self
  }
  if smallest_unit == Days {
    let (date, _) = wall_of(self)
    let start = instant_compatible(self.tz, date, @moondate.midnight)
    let length = day_length(self.tz, date)
    if length <= 0L {
      return self
    }
    let step = length * increment
    let total = (self.epoch - start) * 1_000_000_000L + self.nano.to_int64()
    let rounded = @moondate.round_increment(total, step, rounding)
    return {
      epoch: start + rounded / 1_000_000_000L,
      nano: (rounded % 1_000_000_000L).to_int(),
      tz: self.tz,
    }
  }
  self.snap(smallest_unit.nanos().unwrap() * increment, rounding~)
}

///|
/// The instant moved to the nearest multiple of `step` nanoseconds.
///
/// The reading is what is rounded, not the count of seconds since 1970: an hour
/// is the top of the hour on the clock the zone shows, so a zone an hour off
/// Greenwich rounds to a different instant than UTC does for the same reading.
fn ZonedDateTime::snap(
  self : ZonedDateTime,
  step : Int64,
  rounding~ : @moondate.Rounding,
) -> ZonedDateTime {
  let day = 86_400_000_000_000L
  if step <= 1L {
    return self
  }
  let (date, time) = wall_of(self)
  let landed = @moondate.round_increment(time.nanos(), step, rounding)
  let (moved, rest) = if landed >= day {
    (date.plus_days(1), landed - day)
  } else if landed < 0L {
    (date.plus_days(-1), landed + day)
  } else {
    (date, landed)
  }
  let seconds = rest / 1_000_000_000L
  let clock = @moondate.Time::new(
    (seconds / 3600L).to_int(),
    (seconds / 60L % 60L).to_int(),
    second=(seconds % 60L).to_int(),
    nano=(rest % 1_000_000_000L).to_int(),
  ) catch {
    _ => @moondate.midnight
  }
  {
    epoch: instant_compatible(self.tz, moved, clock),
    nano: (rest % 1_000_000_000L).to_int(),
    tz: self.tz,
  }
}

///|
/// `n` divided by `d`, rounded down, so the remainder is never negative.
fn floor_div(n : Int64, d : Int64) -> Int64 {
  let q = n / d
  if n % d < 0L {
    q - 1L
  } else {
    q
  }
}
