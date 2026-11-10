// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The field edits, the arithmetic and the rounding of a zoned value, checked on
// a fixed offset so that what is being tested is the calendar rather than a
// database. The rules these follow are the ones test262 states; the cases
// themselves are replayed in the `tzdata` package, which has the database.

///|
/// A zone an hour east of Greenwich.
fn plus_one() -> Tz {
  Tz::of(name="+01:00", readings=[
    {
      epoch: -9223372036854775808L,
      offset: 3600,
      is_dst: false,
      abbrev: "+01:00",
    },
  ])
}

///|
/// A value at a wall clock in that zone.
fn zoned_at(
  year : Int32,
  month : Int32,
  day : Int32,
  hour~ : Int32 = 0,
  minute~ : Int32 = 0,
  second~ : Int32 = 0,
) -> ZonedDateTime raise Refused {
  ZonedDateTime::of(year, month, day, hour~, minute~, second~, zone=plus_one())
}

///|
test "zoned: a field edit keeps the rest of the reading" {
  let value = zoned_at(2024, 3, 9, hour=14, minute=30, second=15)
  let edited = value.with_fields(hour=7)
  assert_eq(edited.to_string(), "2024-03-09T07:30:15+01:00 +01:00")
  let later = value.with_fields(year=2025, month=12, day=31)
  assert_eq(later.to_string(), "2025-12-31T14:30:15+01:00 +01:00")
}

///|
test "zoned: a day the month does not have is folded into it" {
  let value = zoned_at(2024, 1, 31)
  let fitted = value.with_fields(month=2)
  assert_eq(fitted.to_string(), "2024-02-29T00:00:00+01:00 +01:00")
  let strict = Some(value.with_fields(month=2, strict=true)) catch { _ => None }
  assert_eq(strict is None, true)
}

///|
test "zoned: a clock field out of range is folded into the day" {
  let value = zoned_at(2024, 3, 9, hour=1)
  assert_eq(
    value.with_fields(hour=25).to_string(),
    "2024-03-09T23:00:00+01:00 +01:00",
  )
  let strict = Some(value.with_fields(hour=25, strict=true)) catch { _ => None }
  assert_eq(strict is None, true)
}

///|
test "zoned: the time of day replaced" {
  let value = zoned_at(2024, 3, 9, hour=14)
  let time = @moondate.Time::new(7, 30) catch { _ => @moondate.midnight }
  assert_eq(
    value.with_plain_time(time).to_string(),
    "2024-03-09T07:30:00+01:00 +01:00",
  )
}

///|
test "zoned: two values are equal when they name one instant in one zone" {
  let value = zoned_at(2024, 3, 9, hour=14)
  let same = zoned_at(2024, 3, 9, hour=14)
  assert_eq(value.equals(same), true)
  assert_eq(
    value.equals(
      value.into(
        Tz::of(name="+02:00", readings=[
          {
            epoch: -9223372036854775808L,
            offset: 7200,
            is_dst: false,
            abbrev: "+02:00",
          },
        ]),
      ),
    ),
    false,
  )
  assert_eq(value.compare(same), 0)
  assert_eq(value.compare(zoned_at(2024, 3, 9, hour=15)), -1)
  assert_eq(zoned_at(2024, 3, 9, hour=15).compare(value), 1)
}

///|
test "zoned: a period added moves the reading" {
  let value = zoned_at(2024, 1, 31, hour=12)
  let month = value.add(@moondate.Period::new(months=1))
  assert_eq(month.to_string(), "2024-02-29T12:00:00+01:00 +01:00")
  let back = month.subtract(@moondate.Period::new(months=1))
  assert_eq(back.to_string(), "2024-01-29T12:00:00+01:00 +01:00")
}

///|
test "zoned: a period that runs both ways is refused" {
  let value = zoned_at(2024, 3, 9, hour=14)
  let mixed = Some(value.add(@moondate.Period::new(days=1, hours=-2))) catch {
    _ => None
  }
  assert_eq(mixed is None, true)
}

///|
test "zoned: the period between two values borrows a month where it must" {
  let january = zoned_at(2021, 1, 31)
  let february = zoned_at(2021, 2, 28)
  assert_eq(january.until(february, largest_unit=Months).to_string(), "P28D")
  let march = zoned_at(2021, 3, 31)
  assert_eq(january.until(march, largest_unit=Months).to_string(), "P2M")
  assert_eq(january.until(march, largest_unit=Days).to_string(), "P59D")
  assert_eq(january.until(march, largest_unit=Weeks).to_string(), "P8W3D")
}

///|
test "zoned: a difference rounds to the unit it is asked for" {
  let value = zoned_at(2024, 3, 9, hour=12, minute=31, second=30)
  let later = zoned_at(2024, 3, 9, hour=14, minute=2)
  assert_eq(value.until(later, largest_unit=Hours).to_string(), "PT1H30M30S")
  assert_eq(
    value
    .until(later, largest_unit=Hours, smallest_unit=Hours, rounding=Ceil)
    .to_string(),
    "PT2H",
  )
  assert_eq(
    value
    .until(later, largest_unit=Minutes, smallest_unit=Minutes, rounding=Trunc)
    .to_string(),
    "PT90M",
  )
}

///|
test "zoned: since is until turned round, whichever side is later" {
  let early = zoned_at(2024, 3, 9, hour=12, minute=31, second=30)
  let late = zoned_at(2024, 3, 9, hour=14, minute=2)
  assert_eq(early.since(late).to_string(), "-PT1H30M30S")
  assert_eq(late.since(early).to_string(), "PT1H30M30S")
}

///|
test "zoned: the reading rounded to each direction" {
  let value = zoned_at(2024, 3, 9, hour=12, minute=31, second=30)
  let written = fn(rounding : @moondate.Rounding) -> String {
    (Some(value.round(smallest_unit=Hours, rounding~)) catch { _ => None })
    .unwrap()
    .to_string()
  }
  assert_eq(written(Ceil), "2024-03-09T13:00:00+01:00 +01:00")
  assert_eq(written(Floor), "2024-03-09T12:00:00+01:00 +01:00")
  assert_eq(written(Trunc), "2024-03-09T12:00:00+01:00 +01:00")
  assert_eq(written(Expand), "2024-03-09T13:00:00+01:00 +01:00")
  assert_eq(written(HalfExpand), "2024-03-09T13:00:00+01:00 +01:00")
  // Past the half, the halving modes all take the step; only a tie divides them.
  assert_eq(written(HalfTrunc), "2024-03-09T13:00:00+01:00 +01:00")
  // Half of an hour is thirty minutes: this reading is exactly on it, and the
  // two halves of the tie disagree on purpose.
  let half = zoned_at(2024, 3, 9, hour=12, minute=30)
  let at_half = fn(rounding : @moondate.Rounding) -> String {
    (Some(half.round(smallest_unit=Hours, rounding~)) catch { _ => None })
    .unwrap()
    .to_string()
  }
  assert_eq(at_half(HalfExpand), "2024-03-09T13:00:00+01:00 +01:00")
  assert_eq(at_half(HalfTrunc), "2024-03-09T12:00:00+01:00 +01:00")
}

///|
test "zoned: an increment the unit cannot be stepped by is refused" {
  let value = zoned_at(2024, 3, 9, hour=12, minute=31)
  let zero_step = Some(value.round(smallest_unit=Days, increment=0L)) catch {
    _ => None
  }
  assert_eq(zero_step is None, true)
}

///|
test "zoned: the increments a unit can be stepped by" {
  let value = zoned_at(2024, 3, 9, hour=12, minute=31)
  assert_eq(
    (Some(value.round(smallest_unit=Minutes, increment=7L)) catch { _ => None })
    is None,
    true,
  )
  assert_eq(
    (Some(value.round(smallest_unit=Days, increment=2L)) catch { _ => None })
    is None,
    true,
  )
  let fifteen = Some(value.round(smallest_unit=Minutes, increment=15L)) catch {
    _ => None
  }
  assert_eq(fifteen.unwrap().to_string(), "2024-03-09T12:30:00+01:00 +01:00")
}

///|
test "zoned: the start of the day and its length on a fixed offset" {
  let value = zoned_at(2024, 3, 9, hour=14, minute=30)
  assert_eq(
    value.start_of_day().to_string(),
    "2024-03-09T00:00:00+01:00 +01:00",
  )
  assert_eq(value.hours_in_day(), 24)
}

///|
test "zoned: a fixed offset has no change to find" {
  let value = zoned_at(2024, 3, 9, hour=14)
  assert_eq(value.get_time_zone_transition(direction=Previous) is None, true)
}
