// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The cases test262 states about a zoned date and time, replayed.
//
// The tables are generated from the corpus by scripts/temporal_vectors; this is
// the test that runs them. A row is one operation the corpus asked the reference
// implementation for, with the state it was given and the answer it gave, and the
// same question is put to this library here.

///|
/// The zone a name stands for: a fixed offset written as text, or one the
/// database has.
fn zone_named(name : String) -> @zone.Tz? {
  if name == "UTC" {
    return Some(fixed(name, 0))
  }
  if name.length() == 6 && name[3].unsafe_to_char() == ':' {
    let sign = if name.has_prefix("-") { -1 } else { 1 }
    let hours = two_digits(name, 1)
    let minutes = two_digits(name, 4)
    return Some(fixed(name, sign * (hours * 60 + minutes) * 60))
  }
  if name.length() == 5 {
    let sign = if name.has_prefix("-") { -1 } else { 1 }
    let hours = two_digits(name, 1)
    let minutes = two_digits(name, 3)
    return Some(fixed(name, sign * (hours * 60 + minutes) * 60))
  }
  find(name)
}

///|
/// Two digits of a text, as the number they spell.
fn two_digits(text : String, from : Int32) -> Int32 {
  (text[from].unsafe_to_char().to_int() - 48) * 10 +
  (text[from + 1].unsafe_to_char().to_int() - 48)
}

///|
/// A zone whose offset never changes.
fn fixed(name : String, offset : Int32) -> @zone.Tz {
  @zone.Tz::of(name~, readings=[
    { epoch: -9223372036854775808L, offset, is_dst: false, abbrev: name, },
  ])
}

///|
/// The value a row names, or `None` when the database has no such zone.
fn value_of(zone : String, epoch : Int64, nano : Int32) -> @zone.ZonedDateTime? {
  match zone_named(zone) {
    None => None
    Some(tz) => Some(@zone.ZonedDateTime::from_unix(epoch, nano~, zone=tz))
  }
}

///|
/// The value as a sentence, for a failure that has to say what it got.
fn said(value : @zone.ZonedDateTime) -> String {
  value.zone_name() +
  "@" +
  value.epoch().to_string() +
  "s " +
  value.nanos().to_string() +
  "ns"
}

///|
/// The unit a row writes as a number.
fn unit_coded(code : Int32) -> @moondate.TimeUnit {
  match code {
    0 => Years
    1 => Months
    2 => Weeks
    3 => Days
    4 => Hours
    5 => Minutes
    6 => Seconds
    7 => Millis
    8 => Micros
    _ => Nanos
  }
}

///|
/// The rounding a row writes as a number.
fn rounding_coded(code : Int32) -> @moondate.Rounding {
  match code {
    0 => Ceil
    1 => Floor
    2 => Expand
    3 => Trunc
    4 => HalfCeil
    5 => HalfFloor
    6 => HalfExpand
    7 => HalfTrunc
    _ => HalfEven
  }
}

///|
/// The period a row writes as eight fields.
fn period_of(
  years : Int64,
  months : Int64,
  weeks : Int64,
  days : Int64,
  hours : Int64,
  minutes : Int64,
  seconds : Int64,
  nanos : Int64,
) -> @moondate.Period {
  { years, months, weeks, days, hours, minutes, seconds, nanos, }
}

///|
/// Whether a period reads as the one a row expects.
fn period_is(period : @moondate.Period, want : @moondate.Period) -> Bool {
  period.years == want.years &&
  period.months == want.months &&
  period.weeks == want.weeks &&
  period.days == want.days &&
  period.hours == want.hours &&
  period.minutes == want.minutes &&
  period.seconds == want.seconds &&
  period.nanos == want.nanos
}

///|
/// The field a row names, as the value has it, or `None` when this library has
/// no such reading.
fn field_named(value : @zone.ZonedDateTime, name : String) -> Int64? {
  match name {
    "year" => Some(value.year().to_int64())
    "month" => Some(value.month().to_int64())
    "day" => Some(value.day().to_int64())
    "hour" => Some(value.hour().to_int64())
    "minute" => Some(value.minute().to_int64())
    "second" => Some(value.second().to_int64())
    "nanosecond" => Some((value.nanos() % 1000).to_int64())
    "microsecond" => Some((value.nanos() / 1000 % 1000).to_int64())
    "millisecond" => Some((value.nanos() / 1_000_000 % 1000).to_int64())
    "offsetNanoseconds" => Some(value.offset().to_int64() * 1_000_000_000L)
    "hoursInDay" => Some(value.hours_in_day().to_int64())
    // The counts a calendar answers about a day, which the corpus asks for by
    // name. A month code is "M01" to "M12", so the number it names is the month.
    "monthCode" => Some(value.month().to_int64())
    "daysInMonth" =>
      Some(@moondate.length(value.year(), value.month()).to_int64())
    "daysInYear" => Some(if @moondate.leap(value.year()) { 366L } else { 365L })
    "monthsInYear" => Some(12L)
    "inLeapYear" => Some(if @moondate.leap(value.year()) { 1L } else { 0L })
    "daysInWeek" => Some(7L)
    "dayOfWeek" => Some(value.date().isoweekday().to_int64())
    "dayOfYear" => Some(value.date().yearday().to_int64())
    "weekOfYear" => {
      let (_, week, _) = value.date().isocalendar()
      Some(week.to_int64())
    }
    "yearOfWeek" => {
      let (year, _, _) = value.date().isocalendar()
      Some(year.to_int64())
    }
    "epochMilliseconds" =>
      Some(value.epoch() * 1000L + value.nanos().to_int64() / 1_000_000L)
    _ => None
  }
}

///|
/// A time of day from the nanoseconds since midnight.
fn clock_at(nanos : Int64) -> @moondate.Time? {
  let seconds = nanos / 1_000_000_000L
  Some(
    @moondate.Time::new(
      (seconds / 3600L).to_int(),
      (seconds / 60L % 60L).to_int(),
      second=(seconds % 60L).to_int(),
      nano=(nanos % 1_000_000_000L).to_int(),
    ),
  ) catch {
    _ => None
  }
}

///|
/// A value with its fields edited, or `None` when the edit is refused.
fn edited(
  value : @zone.ZonedDateTime,
  year : Int64,
  month : Int64,
  day : Int64,
  hour : Int64,
  minute : Int64,
  second : Int64,
  nano : Int64,
  strict : Bool,
) -> @zone.ZonedDateTime? {
  let absent = -9223372036854775808L
  let field = fn(n : Int64) -> Int32? {
    if n == absent {
      None
    } else {
      Some(n.to_int())
    }
  }
  Some(
    value.with_fields(
      year?=field(year),
      month?=field(month),
      day?=field(day),
      hour?=field(hour),
      minute?=field(minute),
      second?=field(second),
      nano?=field(nano),
      strict~,
    ),
  ) catch {
    _ => None
  }
}

///|
/// A value `period` later, or `None` when the step is refused.
fn stepped(
  value : @zone.ZonedDateTime,
  period : @moondate.Period,
  negate : Bool,
) -> @zone.ZonedDateTime? {
  if negate {
    Some(value.subtract(period)) catch {
      _ => None
    }
  } else {
    Some(value.add(period)) catch {
      _ => None
    }
  }
}

///|
/// The period from one value to another, or `None` when it is refused.
fn spanned(
  start : @zone.ZonedDateTime,
  end : @zone.ZonedDateTime,
  since : Bool,
  largest : @moondate.TimeUnit?,
  smallest : @moondate.TimeUnit?,
  rounding : @moondate.Rounding,
  increment : Int64,
) -> @moondate.Period? {
  if since {
    Some(
      start.since(
        end,
        largest_unit?=largest,
        smallest_unit?=smallest,
        rounding~,
        increment~,
      ),
    ) catch {
      _ => None
    }
  } else {
    Some(
      start.until(
        end,
        largest_unit?=largest,
        smallest_unit?=smallest,
        rounding~,
        increment~,
      ),
    ) catch {
      _ => None
    }
  }
}

///|
/// A value rounded, or `None` when the round is refused.
fn rounded_value(
  value : @zone.ZonedDateTime,
  unit : @moondate.TimeUnit,
  increment : Int64,
  rounding : @moondate.Rounding,
) -> @zone.ZonedDateTime? {
  Some(value.round(smallest_unit=unit, increment~, rounding~)) catch {
    _ => None
  }
}

///|
/// A value with its time of day replaced, or `None` when the clock is refused.
fn time_replaced(
  value : @zone.ZonedDateTime,
  time : @moondate.Time,
) -> @zone.ZonedDateTime? {
  Some(value.with_plain_time(time)) catch {
    _ => None
  }
}

///|
test "test262: the zone answers for the fields of a reading" {
  let wrong : Array[String] = []
  for row in fields_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match field_named(value, row.name) {
          None => wrong.push(row.case + ": no reading " + row.name)
          Some(field) =>
            if field != row.want {
              wrong.push(
                row.case +
                ": " +
                row.name +
                " is " +
                field.to_string() +
                ", want " +
                row.want.to_string(),
              )
            }
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the text a value writes" {
  let wrong : Array[String] = []
  for row in texts_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let got = if row.smallest >= 0 {
          value.isoformat(
            zone_name=row.name,
            offset=row.offset,
            smallest_unit=unit_coded(row.smallest),
            rounding=rounding_coded(row.rounding),
            critical=row.critical,
          )
        } else if row.digits < 0 {
          value.isoformat(
            zone_name=row.name,
            offset=row.offset,
            rounding=rounding_coded(row.rounding),
            critical=row.critical,
          )
        } else {
          value.isoformat(
            fraction=row.digits,
            zone_name=row.name,
            offset=row.offset,
            rounding=rounding_coded(row.rounding),
            critical=row.critical,
          )
        }
        if got != row.want {
          wrong.push(row.case + ": wrote " + got + ", want " + row.want)
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a period added to a value" {
  let wrong : Array[String] = []
  for row in shifts_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let period = period_of(
          row.years,
          row.months,
          row.weeks,
          row.days,
          row.hours,
          row.minutes,
          row.seconds,
          row.nanos,
        )
        match stepped(value, period, row.negate) {
          None => wrong.push(row.case + ": refused")
          Some(answer) =>
            if answer.epoch() != row.want_epoch ||
              answer.nanos() != row.want_nano ||
              answer.zone_name() != row.want_zone {
              wrong.push(
                row.case +
                ": landed on " +
                said(answer) +
                ", want " +
                row.want_epoch.to_string() +
                "s " +
                row.want_nano.to_string() +
                "ns",
              )
            }
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a period whose fields disagree is refused" {
  let wrong : Array[String] = []
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the period between two values" {
  let wrong : Array[String] = []
  for row in diffs_all() {
    let start = value_of(row.zone, row.epoch, row.nano)
    let end = value_of(row.other_zone, row.other_epoch, row.other_nano)
    match (start, end) {
      (Some(start), Some(end)) => {
        let largest = if row.largest < 0 {
          None
        } else {
          Some(unit_coded(row.largest))
        }
        let smallest = if row.smallest < 0 {
          None
        } else {
          Some(unit_coded(row.smallest))
        }
        let got = spanned(
          start,
          end,
          row.since,
          largest,
          smallest,
          rounding_coded(row.rounding),
          row.increment,
        )
        let want = period_of(
          row.years,
          row.months,
          row.weeks,
          row.days,
          row.hours,
          row.minutes,
          row.seconds,
          row.nanos,
        )
        match got {
          None => wrong.push(row.case + ": refused")
          Some(period) =>
            if !period_is(period, want) {
              wrong.push(
                row.case +
                ": " +
                period.to_string() +
                ", want " +
                want.to_string(),
              )
            }
        }
      }
      _ => wrong.push(row.case + ": the database has no " + row.zone)
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a value rounded" {
  let wrong : Array[String] = []
  for row in rounds_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match
          rounded_value(
            value,
            unit_coded(row.smallest),
            row.increment,
            rounding_coded(row.rounding),
          ) {
          None => wrong.push(row.case + ": refused")
          Some(answer) =>
            if answer.epoch() != row.want_epoch ||
              answer.nanos() != row.want_nano ||
              answer.zone_name() != row.want_zone {
              wrong.push(
                row.case +
                ": rounded to " +
                said(answer) +
                ", want " +
                row.want_epoch.to_string() +
                "s " +
                row.want_nano.to_string() +
                "ns",
              )
            }
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a rounding this library refuses" {
  let wrong : Array[String] = []
  for row in refused_rounds_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match
          rounded_value(
            value,
            unit_coded(row.smallest),
            row.increment,
            rounding_coded(row.rounding),
          ) {
          None => ()
          Some(answer) => wrong.push(row.case + ": rounded to " + said(answer))
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: two values compared" {
  let wrong : Array[String] = []
  for row in equals_all() {
    let left = value_of(row.zone, row.epoch, row.nano)
    let right = value_of(row.other_zone, row.other_epoch, row.other_nano)
    match (left, right) {
      (Some(left), Some(right)) =>
        if left.equals(right) != row.want {
          wrong.push(row.case + ": equality is not " + row.want.to_string())
        }
      _ => wrong.push(row.case + ": the database has no " + row.zone)
    }
  }
  for row in compares_all() {
    let left = value_of(row.left_zone, row.left_epoch, row.left_nano)
    let right = value_of(row.right_zone, row.right_epoch, row.right_nano)
    match (left, right) {
      (Some(left), Some(right)) => {
        let got = left.compare(right)
        if got != row.want {
          wrong.push(
            row.case +
            ": compared as " +
            got.to_string() +
            ", want " +
            row.want.to_string(),
          )
        }
      }
      _ => wrong.push(row.case + ": the database has no " + row.left_zone)
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the start and the length of a day" {
  let wrong : Array[String] = []
  for row in day_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let got = value.start_of_day()
        if got.epoch() != row.want_epoch ||
          got.nanos() != row.want_nano ||
          got.zone_name() != row.want_zone {
          wrong.push(row.case + ": the day starts at " + said(got))
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the changes of a zone" {
  let wrong : Array[String] = []
  for row in transitions_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let direction = if row.next {
          @zone.Direction::Next
        } else {
          @zone.Direction::Previous
        }
        match (value.get_time_zone_transition(direction~), row.found) {
          (None, true) => wrong.push(row.case + ": no change found")
          (Some(change), false) =>
            wrong.push(row.case + ": found a change at " + said(change))
          (Some(change), true) =>
            if change.epoch() != row.want_epoch ||
              change.nanos() != row.want_nano ||
              change.zone_name() != row.want_zone {
              wrong.push(row.case + ": found " + said(change))
            }
          (None, false) => ()
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the readings a value gives" {
  let wrong : Array[String] = []
  for row in dates_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let date = value.date()
        let time = value.time()
        if date.year != row.year ||
          date.month != row.month ||
          date.day != row.day ||
          time.hour != row.hour ||
          time.minute != row.minute ||
          time.second != row.second ||
          time.nano.to_int64() != row.nanos {
          wrong.push(row.case + ": reads " + value.to_string())
        }
      }
    }
  }
  for row in plaindates_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let date = value.date()
        if date.year != row.year ||
          date.month != row.month ||
          date.day != row.day {
          wrong.push(row.case + ": reads " + value.to_string())
        }
      }
    }
  }
  for row in times_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) => {
        let time = value.time()
        if time.hour != row.hour ||
          time.minute != row.minute ||
          time.second != row.second ||
          time.nano.to_int64() != row.nanos {
          wrong.push(row.case + ": reads " + value.to_string())
        }
      }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: fields edited" {
  let wrong : Array[String] = []
  for row in edits_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match
          edited(
            value,
            row.year,
            row.month,
            row.day,
            row.hour,
            row.minute,
            row.second,
            row.nano_field,
            row.strict,
          ) {
          None => wrong.push(row.case + ": refused")
          Some(answer) =>
            if answer.epoch() != row.want_epoch ||
              answer.nanos() != row.want_nano ||
              answer.zone_name() != row.want_zone {
              wrong.push(
                row.case +
                ": edited to " +
                said(answer) +
                ", want " +
                row.want_epoch.to_string() +
                "s " +
                row.want_nano.to_string() +
                "ns",
              )
            }
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a field edit this library refuses" {
  let wrong : Array[String] = []
  for row in refused_edits_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match
          edited(
            value,
            row.year,
            row.month,
            row.day,
            row.hour,
            row.minute,
            row.second,
            row.nano_field,
            true,
          ) {
          None => ()
          Some(answer) => wrong.push(row.case + ": edited to " + said(answer))
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: the time of day replaced" {
  let wrong : Array[String] = []
  for row in timesets_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match clock_at(row.at) {
          None => wrong.push(row.case + ": no clock at " + row.at.to_string())
          Some(time) =>
            match time_replaced(value, time) {
              None => wrong.push(row.case + ": refused")
              Some(answer) =>
                if answer.epoch() != row.want_epoch ||
                  answer.nanos() != row.want_nano ||
                  answer.zone_name() != row.want_zone {
                  wrong.push(
                    row.case +
                    ": replaced to " +
                    said(answer) +
                    ", want " +
                    row.want_epoch.to_string() +
                    "s " +
                    row.want_nano.to_string() +
                    "ns",
                  )
                }
            }
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}

///|
test "test262: a value moved to another zone" {
  let wrong : Array[String] = []
  for row in zones_all() {
    match value_of(row.zone, row.epoch, row.nano) {
      None => wrong.push(row.case + ": the database has no " + row.zone)
      Some(value) =>
        match zone_named(row.into_zone) {
          None =>
            wrong.push(row.case + ": the database has no " + row.into_zone)
          Some(tz) => {
            let moved = value.into(tz)
            if moved.epoch() != row.want_epoch ||
              moved.nanos() != row.want_nano ||
              moved.zone_name() != row.want_zone {
              wrong.push(row.case + ": moved to " + said(moved))
            }
          }
        }
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}
