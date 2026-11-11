// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The rounding a difference is measured by, pinned to the answers test262's
// ZonedDateTime corpus states: one case per class of answer the earlier
// transcription had to leave out, so that a change which moves any of them is a
// failing test rather than a quiet drift. The corpus rows themselves are replayed
// in the `tzdata` package; these are the readable form of the ones that decided
// the algorithm.

///|
/// A value at an instant, in a fixed offset.
fn utc(epoch : Int64, nano~ : Int32 = 0) -> ZonedDateTime {
  ZonedDateTime::from_unix(epoch, nano~, zone=utc_zone())
}

///|
/// The zone the cases below are written in.
fn utc_zone() -> Tz {
  Tz::of(name="UTC", readings=[
    { epoch: -9223372036854775808L, offset: 0, is_dst: false, abbrev: "UTC", },
  ])
}

///|
/// The fields of a period, as a text that a failure can print.
fn spelled(period : @moondate.Period) -> String {
  period.to_string()
}

///|
test "rounding: an exact half of a difference follows the direction it names" {
  // 2019-01-01T00:00Z to 2020-07-02T00:00Z: one year is 365 days and two are
  // 731, so 548 days is exactly half of the second year.
  let start = utc(1546300800L)
  let end = utc(1593648000L)
  let rounded = fn(mode : @moondate.Rounding) -> String raise Refused {
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Years,
        rounding=mode,
      ),
    )
  }
  assert_eq(rounded(@moondate.Rounding::Trunc), "P1Y")
  assert_eq(rounded(@moondate.Rounding::Floor), "P1Y")
  assert_eq(rounded(@moondate.Rounding::HalfTrunc), "P1Y")
  assert_eq(rounded(@moondate.Rounding::HalfFloor), "P1Y")
  assert_eq(rounded(@moondate.Rounding::HalfEven), "P2Y")
  assert_eq(rounded(@moondate.Rounding::Ceil), "P2Y")
  assert_eq(rounded(@moondate.Rounding::Expand), "P2Y")
  assert_eq(rounded(@moondate.Rounding::HalfExpand), "P2Y")
  assert_eq(rounded(@moondate.Rounding::HalfCeil), "P2Y")
}

///|
test "rounding: an exact half of a negative difference turns the other way" {
  // The same two instants read the other way round, which is what `since` asks:
  // the half is a half of a negative length, so the direction words swap sides.
  let start = utc(1546300800L)
  let end = utc(1593648000L)
  let rounded = fn(mode : @moondate.Rounding) -> String raise Refused {
    spelled(
      start.since(
        end,
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Years,
        rounding=mode,
      ),
    )
  }
  assert_eq(rounded(@moondate.Rounding::Trunc), "-P1Y")
  assert_eq(rounded(@moondate.Rounding::Ceil), "-P1Y")
  assert_eq(rounded(@moondate.Rounding::HalfCeil), "-P1Y")
  assert_eq(rounded(@moondate.Rounding::HalfExpand), "-P2Y")
  assert_eq(rounded(@moondate.Rounding::Floor), "-P2Y")
  assert_eq(rounded(@moondate.Rounding::Expand), "-P2Y")
  assert_eq(rounded(@moondate.Rounding::HalfEven), "-P2Y")
}

///|
test "rounding: a step that fills the unit above is carried into it" {
  // 2022-01-01 to 2023-12-25 is one year, eleven months and twenty-four days;
  // a step up from eleven months reaches twelve, which is a year and not
  // `P1Y12M`.
  let start = utc(1640995200L)
  let end = utc(1703462400L)
  assert_eq(
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Months,
        rounding=@moondate.Rounding::Expand,
      ),
    ),
    "P2Y",
  )
  assert_eq(
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Months,
      ),
    ),
    "P1Y11M",
  )
}

///|
test "rounding: sixty minutes of a difference is the hour above" {
  // One hour, fifty-nine minutes and fifty-nine seconds, asked for in minutes
  // and rounded up: 120 minutes, which is two hours and not `PT1H120M`.
  let start = utc(0L)
  let end = utc(7199L)
  assert_eq(
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Hours,
        smallest_unit=@moondate.TimeUnit::Minutes,
        rounding=@moondate.Rounding::Expand,
      ),
    ),
    "PT2H",
  )
  // And the same with a calendar on top: a difference one nanosecond short of
  // two years rounds up to the two years it is short of.
  assert_eq(
    spelled(
      start.until(
        utc(63071999L, nano=999_999_999),
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Micros,
        rounding=@moondate.Rounding::Expand,
      ),
    ),
    "P2Y",
  )
}

///|
test "rounding: halfEven looks at the count, not only at the half" {
  // 2019-01-08T05:42:36.123456789Z to 2021-09-07T13:19:40.987654289Z: the
  // half-way point between 31 and 32 months, so the even one wins, and the same
  // between 2 and 3 years, where the odd one is the half and 3 is not even but
  // 2 is the smaller and the wrong side of the half.
  let start = utc(1546935756L, nano=123_456_789)
  let end = utc(1631018380L, nano=987_654_289)
  assert_eq(
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Months,
        smallest_unit=@moondate.TimeUnit::Months,
        rounding=@moondate.Rounding::HalfEven,
      ),
    ),
    "P32M",
  )
  assert_eq(
    spelled(
      start.until(
        end,
        largest_unit=@moondate.TimeUnit::Years,
        smallest_unit=@moondate.TimeUnit::Years,
        rounding=@moondate.Rounding::HalfEven,
      ),
    ),
    "P3Y",
  )
}

///|
/// Whether a question this library refuses is refused.
fn refused(ask : () -> Unit raise Refused) -> Bool {
  let answer : Result[Unit, Refused] = try {
    ask()
    Ok(())
  } catch {
    _ => Err(Refused::Missing(text=""))
  }
  answer is Err(_)
}

///|
test "rounding: a difference longer than a count of nanoseconds is refused" {
  let early = utc(-62_135_596_800L)
  let late = utc(253_402_300_800L)
  assert_eq(refused(fn() raise Refused { ignore(late.until(early)) }), true)
}

///|
test "rounding: a smallest unit above the largest is refused" {
  let start = utc(0L)
  let end = utc(86_400L)
  assert_eq(
    refused(fn() raise Refused {
      ignore(
        start.until(
          end,
          largest_unit=@moondate.TimeUnit::Hours,
          smallest_unit=@moondate.TimeUnit::Days,
        ),
      )
    }),
    true,
  )
}

///|
test "rounding: an increment has to divide the unit it steps by" {
  let start = utc(0L)
  let end = utc(86_400L)
  let by = fn(increment : Int64) -> Unit raise Refused {
    ignore(
      start.until(end, smallest_unit=@moondate.TimeUnit::Minutes, increment~),
    )
  }
  assert_eq(refused(fn() raise Refused { by(29L) }), true)
  assert_eq(refused(fn() raise Refused { by(60L) }), true)
  assert_eq(refused(fn() raise Refused { by(15L) }), false)
}
