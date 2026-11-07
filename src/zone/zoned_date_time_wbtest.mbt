// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A zoned date and time, the value that names an instant and the zone it is
// carried in, replayed against the two hours a year that have no single answer.

///|
/// A zone that changes its clocks the way the eastern United States does: forward
/// on 2026-03-08 at two in the morning, back on 2026-11-01 at two.
fn east_fixture() -> Tz {
  Tz::of(name="Test/East", readings=[
    {
      epoch: -9223372036854775808L,
      offset: -18000,
      is_dst: false,
      abbrev: "EST",
    },
    { epoch: 1772953200L, offset: -14400, is_dst: true, abbrev: "EDT", },
    { epoch: 1793512800L, offset: -18000, is_dst: false, abbrev: "EST", },
  ])
}

///|
/// A zone that never changes: UTC.
fn utc_fixture() -> Tz {
  Tz::of(name="UTC", readings=[
    { epoch: -9223372036854775808L, offset: 0, is_dst: false, abbrev: "UTC", },
  ])
}

///|
test "a reading with one answer carries the zone and its offset" {
  let zone = east_fixture()
  let zoned = ZonedDateTime::of(2026, 6, 1, hour=12, zone~)
  assert_eq(zoned.epoch(), 1780329600L)
  assert_eq(zoned.offset(), -14400)
  assert_eq(zoned.offset_minutes(), -240)
  assert_eq(zoned.abbrev(), "EDT")
  assert_eq(zoned.is_dst(), true)
  assert_eq(zoned.year(), 2026)
  assert_eq(zoned.month(), 6)
  assert_eq(zoned.day(), 1)
  assert_eq(zoned.hour(), 12)
  assert_eq(zoned.minute(), 0)
  assert_eq(zoned.second(), 0)
  assert_eq(zoned.zone_name(), "Test/East")
  assert_eq(zoned.isoformat(), "2026-06-01T12:00:00-04:00[Test/East]")
  assert_eq(zoned.isoformat(zone_name=false), "2026-06-01T12:00:00-04:00")
}

///|
test "a reading that happens twice is answered by the fold" {
  // 2026-11-01 01:30 happened twice, an hour apart: once in daylight time and
  // once in standard time.
  let zone = east_fixture()
  // Compatible is the default and Temporal's: the earlier of the two.
  let first = ZonedDateTime::of(2026, 11, 1, hour=1, minute=30, zone~)
  assert_eq(first.epoch(), 1793511000L)
  assert_eq(first.offset(), -14400)
  assert_eq(first.abbrev(), "EDT")
  assert_eq(first.is_dst(), true)
  // Earlier and later pick by instant.
  assert_eq(
    ZonedDateTime::of(2026, 11, 1, hour=1, minute=30, zone~, fold=Earlier).epoch(),
    1793511000L,
  )
  let second = ZonedDateTime::of(
    2026,
    11,
    1,
    hour=1,
    minute=30,
    zone~,
    fold=Later,
  )
  assert_eq(second.epoch(), 1793514600L)
  assert_eq(second.offset(), -18000)
  assert_eq(second.abbrev(), "EST")
  assert_eq(second.is_dst(), false)
  // Reject raises rather than choosing.
  let refused = try {
    let _ = ZonedDateTime::of(
      2026,
      11,
      1,
      hour=1,
      minute=30,
      zone~,
      fold=Reject,
    )
    "taken"
  } catch {
    Missing(_) => "refused"
    _ => "another refusal"
  }
  assert_eq(refused, "refused")
}

///|
test "a reading that never happens is answered by the fold" {
  // 2026-03-08 02:30 happened nowhere: the clocks went from 02:00 to 03:00.
  let zone = east_fixture()
  // Compatible and later both take the later instant, which reads as 03:30.
  let compatible = ZonedDateTime::of(2026, 3, 8, hour=2, minute=30, zone~)
  assert_eq(compatible.epoch(), 1772955000L)
  assert_eq(compatible.offset(), -14400)
  assert_eq(compatible.hour(), 3)
  assert_eq(compatible.minute(), 30)
  assert_eq(
    ZonedDateTime::of(2026, 3, 8, hour=2, minute=30, zone~, fold=Later).epoch(),
    1772955000L,
  )
  // Earlier takes the earlier instant, which reads as 01:30 in standard time.
  let earlier = ZonedDateTime::of(
    2026,
    3,
    8,
    hour=2,
    minute=30,
    zone~,
    fold=Earlier,
  )
  assert_eq(earlier.epoch(), 1772951400L)
  assert_eq(earlier.offset(), -18000)
  assert_eq(earlier.hour(), 1)
  assert_eq(earlier.minute(), 30)
  let refused = try {
    let _ = ZonedDateTime::of(2026, 3, 8, hour=2, minute=30, zone~, fold=Reject)
    "taken"
  } catch {
    Missing(_) => "refused"
    _ => "another refusal"
  }
  assert_eq(refused, "refused")
}

///|
test "an instant read back keeps the offset in force" {
  let zone = east_fixture()
  // 2026-06-01 12:00 EDT is 16:00 UTC, and the offset beside it is the one the
  // zone has at that instant.
  let zoned = ZonedDateTime::from_unix(1780329600L, zone~)
  assert_eq(zoned.offset(), -14400)
  assert_eq(zoned.date(), @moondate.Date::new(2026, 6, 1))
  assert_eq(zoned.hour(), 12)
  // The round trip through a moment carries the name and the offset.
  let moment = zoned.moment()
  assert_eq(moment.epoch(), Some(1780329600L))
  assert_eq(
    moment,
    Zoned(
      date=@moondate.Date::new(2026, 6, 1),
      time=@moondate.Time::new(12, 0),
      zone=Named({ name: "Test/East", offset: -14400, abbrev: "EDT", }),
    ),
  )
}

///|
test "a field read back and written is the same instant" {
  let zone = east_fixture()
  let zoned = ZonedDateTime::from_unix(1780329600L, zone~)
  let again = ZonedDateTime::of(
    zoned.year(),
    zoned.month(),
    zoned.day(),
    hour=zoned.hour(),
    minute=zoned.minute(),
    second=zoned.second(),
    nano=zoned.nanos(),
    zone~,
  )
  assert_eq(again.epoch(), zoned.epoch())
  assert_eq(again.isoformat(), zoned.isoformat())
}

///|
test "moving to another zone keeps the instant and changes the reading" {
  let east = east_fixture()
  let utc = utc_fixture()
  let zoned = ZonedDateTime::from_unix(1780329600L, zone=east)
  // 2026-06-01 12:00 EDT is 16:00 UTC: the point on the line is the same, only
  // the clocks that read it are not.
  let there = zoned.into(utc)
  assert_eq(there.epoch(), 1780329600L)
  assert_eq(there.offset(), 0)
  assert_eq(there.abbrev(), "UTC")
  assert_eq(there.date(), @moondate.Date::new(2026, 6, 1))
  assert_eq(there.hour(), 16)
}

///|
test "adding a duration moves the instant across a change" {
  let zone = east_fixture()
  // 2026-11-01 00:30 EDT, two hours before the clocks go back.
  let zoned = ZonedDateTime::of(2026, 11, 1, hour=0, minute=30, zone~)
  assert_eq(zoned.epoch(), 1793507400L)
  // Two hours later is 06:30 UTC, which the clocks read as 01:30 in standard
  // time: the reading moved across the change the instant was added over.
  let later = zoned.plus(@moondate.Span::of(@moondate.hour, 2))
  assert_eq(later.epoch(), 1793514600L)
  assert_eq(later.offset(), -18000)
  assert_eq(later.abbrev(), "EST")
  assert_eq(later.hour(), 1)
  assert_eq(later.minute(), 30)
  // A day added across no change is a day in the reading as well.
  let midsummer = ZonedDateTime::of(2026, 6, 1, hour=12, zone~)
  let next = midsummer.plus_days(1)
  assert_eq(next.epoch(), 1780416000L)
  assert_eq(next.day(), 2)
  assert_eq(next.hour(), 12)
}

///|
test "a field edit keeps the offset if it still is, else the zone decides" {
  let zone = east_fixture()
  // 2026-06-01 12:00 EDT. Move the month to November: 12:00 there is standard
  // time, so the daylight offset no longer covers the reading.
  let zoned = ZonedDateTime::of(2026, 6, 1, hour=12, zone~)
  // Prefer, the default, lets the zone decide and lands on 12:00 in standard time.
  let prefer = zoned.with_month(11)
  assert_eq(prefer.epoch(), 1793552400L)
  assert_eq(prefer.offset(), -18000)
  assert_eq(prefer.hour(), 12)
  // Use keeps the old offset whatever the zone says, so the instant and the
  // reading both move by the difference between the two offsets.
  let kept_offset = zoned.with_month(11, offset=Use)
  assert_eq(kept_offset.epoch(), 1793548800L)
  assert_eq(kept_offset.hour(), 11)
  // Ignore goes straight to the zone, the same as Prefer here because the offset
  // is not in force.
  let ignore = zoned.with_month(11, offset=Ignore)
  assert_eq(ignore.epoch(), 1793552400L)
}

///|
test "a field edit with the offset still in force keeps the instant" {
  let zone = east_fixture()
  // 2026-06-01 12:00 EDT. The minute changed to 13:00, still in daylight time, so
  // the offset that was in force still is and the instant moves by exactly the
  // difference.
  let zoned = ZonedDateTime::of(2026, 6, 1, hour=12, zone~)
  let later = zoned.with_hour(13)
  assert_eq(later.epoch(), 1780333200L)
  assert_eq(later.offset(), -14400)
  assert_eq(later.hour(), 13)
  // Reject refuses a reading the old offset no longer covers, even when the zone
  // would have answered it.
  let refused = try {
    let _ = zoned.with_month(11, offset=Reject)
    "taken"
  } catch {
    Missing(_) => "refused"
    _ => "another refusal"
  }
  assert_eq(refused, "refused")
  // And it does not refuse one the old offset still covers.
  let kept = zoned.with_hour(13, offset=Reject)
  assert_eq(kept.epoch(), 1780333200L)
}

///|
test "a month edit that leaves no such day is refused" {
  let zone = utc_fixture()
  // The thirty-first of January into February: there is no thirty-first.
  let zoned = ZonedDateTime::of(2026, 1, 31, hour=12, zone~)
  let refused = try {
    let _ = zoned.with_month(2)
    "taken"
  } catch {
    BadDate(_) => "bad date"
    _ => "another refusal"
  }
  assert_eq(refused, "bad date")
}

///|
test "a field out of range is refused as a date and time" {
  let zone = utc_fixture()
  let refused = try {
    let _ = ZonedDateTime::of(2026, 13, 1, zone~)
    "taken"
  } catch {
    BadDate(_) => "bad date"
    _ => "another refusal"
  }
  assert_eq(refused, "bad date")
  let refused = try {
    let _ = ZonedDateTime::of(2026, 1, 1, hour=24, zone~)
    "taken"
  } catch {
    BadDate(_) => "bad date"
    _ => "another refusal"
  }
  assert_eq(refused, "bad date")
}

///|
test "a moment that names an instant is placed without a fold" {
  let zone = east_fixture()
  // An instant does not need a policy: it is one instant, and the zone only says
  // what the clocks read at it.
  let moment : @moondate.Moment = Zoned(
    date=@moondate.Date::new(2026, 6, 1),
    time=@moondate.Time::new(12, 0),
    zone=Named({ name: "Test/East", offset: -14400, abbrev: "EDT", }),
  )
  let zoned = ZonedDateTime::of_moment(moment, zone~)
  assert_eq(zoned.epoch(), 1780329600L)
  assert_eq(zoned.offset(), -14400)
}

///|
test "a wall clock with no instant is answered by the fold" {
  let zone = east_fixture()
  // A `Plain` moment is a wall clock, so placing it in the zone is the question
  // the fold answers.
  let wall : @moondate.Moment = Plain(
    date=@moondate.Date::new(2026, 11, 1),
    time=@moondate.Time::new(1, 30),
  )
  let first = ZonedDateTime::of_moment(wall, zone~)
  assert_eq(first.epoch(), 1793511000L)
  let second = ZonedDateTime::of_moment(wall, zone~, fold=Later)
  assert_eq(second.epoch(), 1793514600L)
}
