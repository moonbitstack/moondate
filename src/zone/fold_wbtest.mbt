// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The two hours of the year that have no single answer: the one the clocks skip
// over in spring and the one they read twice in autumn.

///|
/// A zone that changes its clocks the way the eastern United States does: forward
/// on 2026-03-08 at two in the morning, back on 2026-11-01 at two.
fn eastern() -> Tz {
  Tz::of(name="Test/Eastern", readings=[
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
test "a clock the zone never reads" {
  // 2026-03-08 02:30 happened nowhere: the clocks went from 02:00 to 03:00.
  let zone = eastern()
  let at = zone.read(
    @moondate.Date::new(2026, 3, 8),
    @moondate.Time::new(2, 30),
  )
  // Read as daylight time it lands at 06:30Z, read as standard time at 07:30Z.
  assert_eq(at, Skipped(earlier=1772951400L, later=1772955000L))
  assert_eq(at.is_exact(), false)
  // Python's `fold=0` and Temporal's "compatible" both take the later instant,
  // which is what a caller who did not think about it means.
  assert_eq(at.epoch(), 1772955000L)
  assert_eq(at.epoch(fold=Earlier), 1772951400L)
  assert_eq(at.epoch(fold=Later), 1772955000L)
  let refused = try {
    let _ = at.epoch(fold=Reject)
    "taken"
  } catch {
    Missing(..) => "refused"
    _ => "another refusal"
  }
  assert_eq(refused, "refused")
}

///|
test "a clock the zone reads twice" {
  // 2026-11-01 01:30 happened twice, an hour apart.
  let zone = eastern()
  let at = zone.read(
    @moondate.Date::new(2026, 11, 1),
    @moondate.Time::new(1, 30),
  )
  assert_eq(at, Ambiguous(earlier=1793511000L, later=1793514600L))
  assert_eq(at.is_exact(), false)
  // Python's `fold=0` takes the first reading, `fold=1` the second.
  assert_eq(at.epoch(), 1793511000L)
  assert_eq(at.epoch(fold=Earlier), 1793511000L)
  assert_eq(at.epoch(fold=Later), 1793514600L)
  let refused = try {
    let _ = at.epoch(fold=Reject)
    "taken"
  } catch {
    Missing(..) => "refused"
    _ => "another refusal"
  }
  assert_eq(refused, "refused")
}

///|
test "a clock with one answer" {
  let zone = eastern()
  let at = zone.read(
    @moondate.Date::new(2026, 6, 1),
    @moondate.Time::new(12, 0),
  )
  assert_eq(at, Exact(instant=1780329600L))
  assert_eq(at.epoch(fold=Reject), 1780329600L)
  // The reading that instant is in is daylight time, an hour ahead.
  let reading = zone.at(1780329600L)
  assert_eq(reading.offset, -14400)
  assert_eq(reading.abbrev, "EDT")
  assert_eq(reading.is_dst, true)
}

///|
test "the edge of a change is exact" {
  // The second the clocks go forward is the first second of daylight time, and
  // the second before it is the last of standard time.
  let zone = eastern()
  assert_eq(zone.at(1772953199L).offset, -18000)
  assert_eq(zone.at(1772953200L).offset, -14400)
  assert_eq(zone.at(1793512799L).offset, -14400)
  assert_eq(zone.at(1793512800L).offset, -18000)
}

///|
test "a moment carries the zone it was read in" {
  let zone = eastern()
  let moment = zone.moment(1780329600L)
  assert_eq(
    moment,
    Zoned(
      date=@moondate.Date::new(2026, 6, 1),
      time=@moondate.Time::new(12, 0),
      zone=Named({ name: "Test/Eastern", offset: -14400, abbrev: "EDT", }),
    ),
  )
  assert_eq(moment.epoch(), Some(1780329600L))
  // A wall clock pinned to the zone is the other direction, and it is the one
  // that needs a policy.
  let wall = @moondate.Moment::combine(
    @moondate.Date::new(2026, 11, 1),
    @moondate.Time::new(1, 30),
  )
  assert_eq(zone.zoned(wall, fold=Later).epoch(), Some(1793514600L))
  assert_eq(zone.zoned(wall).epoch(), Some(1793511000L))
}

///|
test "the changes between two instants" {
  let zone = eastern()
  let year = zone.changes(from=1767225600L, to=1798761600L)
  assert_eq(year.length(), 2)
  assert_eq(year[0].epoch, 1772953200L)
  assert_eq(year[1].epoch, 1793512800L)
  assert_eq(zone.changes(from=0L, to=1L), [])
  // The opening reading stands for all of time before the first change, so it
  // belongs to no window at all.
  assert_eq(zone.changes(from=-1000L, to=0L).length(), 0)
}
