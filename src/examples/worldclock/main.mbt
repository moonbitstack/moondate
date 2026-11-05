/// Four cities at one instant, and the two hours of the year that need a decision.
///
///     moon run src/examples/worldclock

///|
fn main raise {
  // 2026-09-22T14:30:05 in Shanghai, which is one and the same instant everywhere.
  let instant = 1790058605L
  for
    name in [
      "Asia/Shanghai", "America/New_York", "Europe/London", "Pacific/Chatham", "Asia/Kathmandu",
    ] {
    let tz = @tzdata.load(name)
    let moment = tz.moment(instant)
    println(
      "\{name}: \{moment.strftime("%Y-%m-%d %H:%M")} \{moment.pattern("z")} (\{moment.strftime("%z")})",
    )
  }
  // Two mornings a year the clocks and the calendar disagree. In New York the
  // second Sunday of March has no 02:30, and the first Sunday of November has two.
  let zone = @tzdata.load("America/New_York")
  let spring = zone.read(
    @moondate.Date::new(2026, 3, 8),
    @moondate.Time::new(2, 30),
  )
  println("\nthe skipped hour: \{spring.to_string()}")
  println("read as compatible: \{spring.epoch()}")
  println("read as earlier:    \{spring.epoch(fold=Earlier)}")
  let autumn = zone.read(
    @moondate.Date::new(2026, 11, 1),
    @moondate.Time::new(1, 30),
  )
  println("\nthe repeated hour: \{autumn.to_string()}")
  println("read as compatible: \{autumn.epoch()}")
  println("read as later:      \{autumn.epoch(fold=Later)}")
  // A moment read in a zone keeps the name, so the text can say which New York it
  // meant.
  let moment = zone.moment(1793514600L)
  println("\n\{moment.isoformat(zone_name=true)}")
}
