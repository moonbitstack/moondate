// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What a zone does to arithmetic, checked against the readings the database
// carries rather than against a rule written here: a day across a change is not
// twenty-four hours, and the difference between two instants depends on the
// units it is asked for.

///|
/// A value in New York, the zone most of these cases are about.
fn new_york(
  year : Int32,
  month : Int32,
  day : Int32,
  hour~ : Int32 = 0,
  minute~ : Int32 = 0,
) -> @zone.ZonedDateTime raise @zone.Refused {
  @zone.ZonedDateTime::of(
    year,
    month,
    day,
    hour~,
    minute~,
    zone=load("America/New_York"),
  )
}

///|
test "zone: a day added is a day, an hour added is an hour" {
  let start = new_york(2024, 3, 9, hour=12)
  let day = start.add(@moondate.Period::new(days=1))
  assert_eq(day.to_string(), "2024-03-10T12:00:00-04:00 America/New_York")
  let hours = start.add(@moondate.Period::new(hours=24))
  assert_eq(hours.to_string(), "2024-03-10T13:00:00-04:00 America/New_York")
}

///|
test "zone: the same two values are a day or twenty-three hours apart" {
  let start = new_york(2024, 3, 9, hour=12)
  let end = start.add(@moondate.Period::new(days=1))
  assert_eq(start.until(end, largest_unit=Days).to_string(), "P1D")
  assert_eq(start.until(end, largest_unit=Hours).to_string(), "PT23H")
  assert_eq(end.since(start, largest_unit=Days).to_string(), "P1D")
}

///|
test "zone: the days the clocks change are short and long" {
  assert_eq(new_york(2024, 3, 10, hour=12).hours_in_day(), 23)
  assert_eq(new_york(2024, 11, 3, hour=12).hours_in_day(), 25)
  assert_eq(new_york(2024, 6, 1, hour=12).hours_in_day(), 24)
}

///|
test "zone: the day starts before the clocks change" {
  assert_eq(
    new_york(2024, 3, 10, hour=12).start_of_day().to_string(),
    "2024-03-10T00:00:00-05:00 America/New_York",
  )
  assert_eq(
    new_york(2024, 11, 3, hour=12).start_of_day().to_string(),
    "2024-11-03T00:00:00-04:00 America/New_York",
  )
}

///|
test "zone: the changes either side of an instant" {
  let day = new_york(2024, 3, 10, hour=12)
  let next = day.get_time_zone_transition(direction=Next)
  assert_eq(
    next.unwrap().to_string(),
    "2024-11-03T01:00:00-05:00 America/New_York",
  )
  let previous = day.get_time_zone_transition(direction=Previous)
  assert_eq(
    previous.unwrap().to_string(),
    "2024-03-10T03:00:00-04:00 America/New_York",
  )
  // The instant of a change is the change: nothing happens between it and the
  // next one for the answer to be about.
  let change = previous.unwrap()
  assert_eq(
    change.get_time_zone_transition(direction=Previous).unwrap().to_string(),
    "2023-11-05T01:00:00-05:00 America/New_York",
  )
}

///|
test "zone: a day rounded to is the day the clocks are having" {
  assert_eq(
    new_york(2024, 3, 10, hour=12).round(smallest_unit=Days).to_string(),
    "2024-03-10T00:00:00-05:00 America/New_York",
  )
  assert_eq(
    new_york(2024, 11, 3, hour=12).round(smallest_unit=Days).to_string(),
    "2024-11-04T00:00:00-05:00 America/New_York",
  )
}

///|
test "zone: a month of the calendar is not a month of days" {
  let start = new_york(2023, 12, 1)
  let end = new_york(2024, 6, 1)
  assert_eq(start.until(end, largest_unit=Months).to_string(), "P6M")
  assert_eq(start.until(end, largest_unit=Days).to_string(), "P183D")
}

///|
test "zone: a reading that never happens is answered by the fold" {
  let compatible = new_york(2024, 3, 10, hour=2, minute=30)
  assert_eq(
    compatible.to_string(),
    "2024-03-10T03:30:00-04:00 America/New_York",
  )
  let earlier = Some(
    @zone.ZonedDateTime::of(
      2024,
      3,
      10,
      hour=2,
      minute=30,
      zone=load("America/New_York"),
      fold=@zone.Fold::Earlier,
    ),
  ) catch {
    _ => None
  }
  assert_eq(
    earlier.unwrap().to_string(),
    "2024-03-10T01:30:00-05:00 America/New_York",
  )
  let refused = Some(
    @zone.ZonedDateTime::of(
      2024,
      3,
      10,
      hour=2,
      minute=30,
      zone=load("America/New_York"),
      fold=@zone.Fold::Reject,
    ),
  ) catch {
    _ => None
  }
  assert_eq(refused is None, true)
}

///|
test "probe: the qualified unit" {
  let ny = load("America/New_York")
  let dusk = @zone.ZonedDateTime::of(2024, 3, 10, hour=12, minute=31, zone=ny)
  assert_eq(
    dusk.round(smallest_unit=@moondate.TimeUnit::Hours).isoformat(),
    "2024-03-10T13:00:00-04:00[America/New_York]",
  )
}
