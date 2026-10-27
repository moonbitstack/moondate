///|
/// Calendar arithmetic on `Date`: counting days, naming weekdays, adding months.
///
/// Nothing in this file needs a clock or a zone. A date is a square on a wall
/// calendar, and the operations below are all the things you can do with squares.
///
///     moon run examples/calendar
fn main raise {
  let date = @moondate.Date::new(2026, 9, 22)

  // Where the day sits in the year, and in the week.
  // `weekday` counts from Monday as 0, which is what ISO and C's `struct tm` use.
  println("weekday  " + date.weekday().to_string()) // 0 = Monday
  println("isoweekday " + date.isoweekday().to_string()) // 1 = Monday
  println("yearday  " + date.yearday().to_string()) // 1 = 1 January

  // The ISO 8601 week date: which year the week belongs to, which week, which day.
  // The year is not always the calendar year — 1 January 2027 belongs to week 53
  // of 2026 — which is why this is a separate call and not three divisions.
  let (iso_year, iso_week, iso_day) = date.isocalendar()
  println("iso      \{iso_year}-W\{iso_week}-\{iso_day}")

  // The number of days since 1970-01-01, and back again. This pair is total over
  // the whole supported range, so it makes a compact key for a date.
  println("days     " + date.days().to_string())
  println("of_days  " + @moondate.Date::of_days(date.days()).to_string())

  // Python's ordinal counts 1 January of year 1 as day 1. Both directions exist.
  println("ordinal  " + date.ordinal().to_string())
  println(
    "of_ordinal " + @moondate.Date::of_ordinal(date.ordinal()).to_string(),
  )

  println("")

  // Month lengths are a table, but a computed one: February is the only month
  // that changes, and only in a leap year.
  let mut month = 1
  let mut lengths = ""
  while month <= 12 {
    lengths = lengths + @moondate.length(2024, month).to_string() + " "
    month = month + 1
  }
  println(lengths)
  println("2024 is a leap year: " + @moondate.leap(2024).to_string())
  println("2100 is a leap year: " + @moondate.leap(2100).to_string())
  println("")

  // Arithmetic is exact and takes you out of the month, the year, and the range
  // you would expect. Negative counts go back.
  println("+10 days    " + date.plus_days(10).to_string())
  println("-100 days   " + date.plus_days(-100).to_string())
  println("+5 months   " + date.plus_months(5).to_string())
  println("-12 months  " + date.plus_months(-12).to_string())
  println("")

  // Adding months clamps rather than overflows: 31 January plus one month is
  // 28 February in a common year, because there is no 31 February to land on.
  let end_of_january = @moondate.Date::new(2026, 1, 31)
  println("31 Jan +1 month " + end_of_january.plus_months(1).to_string())
  println("31 Jan +2 months " + end_of_january.plus_months(2).to_string())
  println("")

  // The distance between two dates is a span of whole days.
  let later = @moondate.Date::new(2027, 3, 1)
  let span = date.diff(later)
  let (days, seconds, nanos) = span.parts()
  println("days between    " + days.to_string())
  println("leftover seconds " + seconds.to_string())
  println("leftover nanos   " + nanos.to_string())
  println("total seconds    " + span.total_seconds().to_string())
  println("")

  // Ordering is structural, so sorting a list of dates is just `sort`.
  let holidays = [
    @moondate.Date::new(2026, 1, 1),
    @moondate.Date::new(2026, 10, 1),
    @moondate.Date::new(2026, 5, 1),
  ]
  holidays.sort()
  for holiday in holidays {
    // `strftime` lives on `Moment`, so a bare date is wrapped in the `Day` shape
    // first. Formatting is a property of the shape, not of the date alone.
    let as_day = @moondate.Day(date=holiday)
    println(holiday.to_string() + "  " + as_day.strftime("%A"))
  }

  // `replace` swaps single fields and re-checks the result, which is how you snap
  // a date to the first of its month without doing arithmetic on months at all.
  let first_of_month = date.replace(day=1)
  println("first of month " + first_of_month.to_string())
}
