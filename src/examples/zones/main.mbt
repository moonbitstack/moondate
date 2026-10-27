/// Instants, offsets and the universal timeline.
///
/// An instant is one point on the timeline; a zone decides how that point is
/// spelled. Two moments written with different offsets can be the same instant,
/// and this file shows how to tell — and how to move between the spellings.
///
///     moon run src/examples/zones

///|
/// The offset of a moment from UTC, in minutes, as a signed number.
fn offset_minutes(m : @moondate.Moment) -> Int32 {
  match m.utcoffset() {
    Some(span) => (span.total_seconds() / 60.0).to_int()
    None => 0
  }
}

///|
fn main raise {
  // The same instant, written three ways. All three texts are different; the
  // moment behind them is not.
  let beijing = @moondate.parse("2026-09-22T14:30:00+08:00")
  let london = @moondate.parse("2026-09-22T07:30:00+01:00")
  let utc = @moondate.parse("2026-09-22T06:30:00Z")

  println(beijing)
  println(london)
  println(utc)
  println("same instant: " + (beijing.epoch() == utc.epoch()).to_string())
  println("")

  // The offsets differ, and `utcoffset` reports them as a span.
  println("beijing " + offset_minutes(beijing).to_string() + " minutes")
  println("london  " + offset_minutes(london).to_string() + " minutes")
  println("utc     " + offset_minutes(utc).to_string() + " minutes")
  println("")

  // `astimezone` rewrites the same instant in another zone. `Utc` is a value, not
  // a name to look up, and an offset is just minutes east.
  let as_utc = beijing.astimezone(@moondate.Utc).unwrap()
  println("in UTC   " + as_utc.to_string())

  let as_india = beijing.astimezone(@moondate.Offset(330)).unwrap()
  println("in +05:30 " + as_india.to_string())

  // Converting does not change the instant, only the spelling — compare the two
  // numbers above and they are the same.
  println(
    "still the same: " + (as_india.epoch() == beijing.epoch()).to_string(),
  )
  println("")

  // The other direction: a count of seconds since 1970, and a zone to read it in.
  let seconds = 1790058600L
  println(
    "from epoch, UTC   " + @moondate.Moment::of_epoch(seconds).to_string(),
  )
  println(
    "from epoch, +08:00 " +
    @moondate.Moment::of_epoch(seconds, zone=@moondate.Offset(480)).to_string(),
  )

  // `timestamp` is the same number as a float, seconds and fraction together,
  // which is what most other systems want.
  println("timestamp " + beijing.timestamp().unwrap().to_string())
  println("")

  // Subtracting two instants gives a span of real elapsed time. This is the only
  // subtraction in the library that needs both sides to sit on the timeline.
  let tomorrow = @moondate.parse("2026-09-23T06:30:00Z")
  let elapsed = tomorrow.diff(beijing).unwrap()
  println(
    "a day later minus beijing = " + elapsed.total_seconds().to_string() + " s",
  )

  // The same instant written with two different offsets subtracts to zero, which
  // is the proof that the offset is spelling and not position.
  let nothing = beijing.diff(london).unwrap()
  println(
    "beijing minus london = " + nothing.total_seconds().to_string() + " s",
  )
  println("")

  // Spans are built from named units, and only the ones you name are counted.
  let ninety = @moondate.Span::new(hours=1, minutes=30)
  println("90 minutes  = " + ninety.total_seconds().to_string() + " s")
  println("backwards   = " + ninety.neg().total_seconds().to_string() + " s")

  // Adding a span moves the instant, not the wall clock: an hour later is an hour
  // later even when the offset differs.
  let later = beijing.plus(ninety)
  println("plus 90 min " + later.to_string())
  println("plus a day  " + beijing.plus(@moondate.day).to_string())
  println("plus a nanosecond " + beijing.plus(@moondate.nanosecond).to_string())
  println("")

  // A span from named units can also be read as days, seconds and nanoseconds,
  // which is how a duration is usually stored.
  let long = @moondate.Span::new(
    days=3,
    hours=4,
    minutes=5,
    seconds=6,
    millis=7,
  )
  let (days, secs, nanos) = long.parts()
  println("days " + days.to_string())
  println("seconds " + secs.to_string())
  println("nanos " + nanos.to_string())
}
