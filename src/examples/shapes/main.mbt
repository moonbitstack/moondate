/// The four shapes a moment can have, side by side.
///
/// A date library has one awkward question to answer: what is a "moment" when the
/// text only gave you a day, or only gave you a clock, or gave you both without
/// saying which time zone? This library answers it by keeping the shape rather
/// than filling in the guess — a bare date stays a date, it does not quietly
/// become midnight UTC.
///
///     moon run src/examples/shapes

///|
/// Write a zone the way an offset is usually written. `Offset` counts minutes
/// east of UTC, which is how RFC 3339 and every zone database spell it.
fn zone_text(zone : @moondate.Zone) -> String {
  match zone {
    @moondate.Utc => "UTC"
    @moondate.Offset(minutes) => {
      let sign = if minutes < 0 { "-" } else { "+" }
      let abs = if minutes < 0 { -minutes } else { minutes }
      let hh = abs / 60
      let mm = abs % 60
      let pad = if mm < 10 { "0" } else { "" }
      "\{sign}0\{hh}:\{pad}\{mm}"
    }
  }
}

///|
fn main raise {
  // `parse` accepts four text shapes. Each one lands in a different constructor of
  // `Moment`, and the constructor is what decides which questions you can ask.
  let zoned = @moondate.parse("2026-09-22T14:30:00+08:00") // Zoned: date, time, zone
  let plain = @moondate.parse("2026-09-22T14:30:00") // Plain: date, time
  let day = @moondate.parse("2026-09-22") // Day:   date only
  let clock = @moondate.parse("14:30:00") // Clock: time only

  // `Show` echoes the shape back, which is the quickest proof that nothing was
  // invented along the way.
  println(zoned)
  println(plain)
  println(day)
  println(clock)
  println("")

  // Only a zoned moment sits on the universal timeline. `epoch` is `None` for the
  // other three, and that is the whole point of having four shapes.
  fn epoch_text(m : @moondate.Moment) -> String {
    match m.epoch() {
      Some(seconds) => seconds.to_string()
      None => "off the timeline"
    }
  }

  println(epoch_text(zoned))
  println(epoch_text(plain))
  println(epoch_text(day))
  println(epoch_text(clock))
  println("")

  // The same split shows up in the zone.
  fn zone_of(m : @moondate.Moment) -> String {
    match m.zone() {
      Some(zone) => zone_text(zone)
      None => "carries no zone"
    }
  }

  println("zoned  " + zone_of(zoned))
  println("plain  " + zone_of(plain))
  println("")

  // A bare time has no date, so `date` is `None` — but it does have its clock.
  fn date_of(m : @moondate.Moment) -> String {
    match m.date() {
      Some(date) => date.to_string()
      None => "none"
    }
  }

  println("clock date " + date_of(clock))
  println("clock time " + clock.time().to_string())
  println("")

  // When you know the missing half, say it. `combine` puts a date, a time and a
  // zone together without going through text at all.
  let date = @moondate.Date::new(2026, 9, 22)
  let time = @moondate.Time::new(14, 30, second=0)
  let built = @moondate.Moment::combine(date, time, zone=@moondate.Offset(480))
  println(built)
  println(epoch_text(built))

  // Leave the zone off and you get a plain moment, off the timeline on purpose.
  let floating = @moondate.Moment::combine(date, time)
  println(floating)
  println(epoch_text(floating))
}
