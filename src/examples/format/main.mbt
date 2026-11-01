///|
/// The five writing styles, one moment at a time.
///
/// The `%` directives every Unix has, Go's reference-time layout, the Unicode
/// LDML pattern, and the ECMAScript ISO shapes. This file runs one moment through
/// each language, then reads the pieces back.
///
///     moon run src/examples/format
fn main raise {
  let moment = @moondate.parse("2026-09-22T14:30:05.123456+08:00")

  // One line per directive, so the table doubles as a reference. The columns are
  // the directive, what it means, and what it gives for this moment.
  let lines = [
    ("%Y", "four-digit year", "%Y"),
    ("%y", "two-digit year", "%y"),
    ("%m", "month, 01 to 12", "%m"),
    ("%d", "day of month, 01 to 31", "%d"),
    ("%H", "hour on a 24-hour clock", "%H"),
    ("%I", "hour on a 12-hour clock", "%I"),
    ("%M", "minute", "%M"),
    ("%S", "second", "%S"),
    ("%f", "microseconds", "%f"),
    ("%p", "AM or PM", "%p"),
    ("%j", "day of year, 001 to 366", "%j"),
    ("%a", "short weekday name", "%a"),
    ("%A", "long weekday name", "%A"),
    ("%b", "short month name", "%b"),
    ("%B", "long month name", "%B"),
    ("%G", "ISO week year", "%G"),
    ("%V", "ISO week number", "%V"),
    ("%u", "ISO weekday, 1 to 7", "%u"),
    ("%w", "weekday, 0 to 6, Sunday is 0", "%w"),
    ("%z", "offset from UTC, no colon", "%z"),
    ("%Z", "zone name", "%Z"),
    ("%%", "a literal percent sign", "%%"),
  ]
  for (directive, meaning, pattern) in lines {
    let value = moment.strftime(pattern)
    println(directive + "\t" + meaning + "\t" + value)
  }
  println("")

  // A format string is usually longer than one directive, and the literal text
  // between them is copied through untouched.
  println(moment.strftime("%A, %d %B %Y at %H:%M:%S %z"))
  println(moment.strftime("%G-W%V-%u, day %j of %Y"))
  println(moment.strftime("%I:%M %p on day %d"))
  println("")

  // The shape decides what the missing pieces are. A bare day is midnight, a bare
  // clock is 1 January 1900 — the same defaults C's `struct tm` has always had.
  let day = @moondate.parse("2026-09-22")
  println(day.strftime("%Y-%m-%d %H:%M:%S"))

  let clock = @moondate.parse("14:30:05")
  println(clock.strftime("%Y-%m-%d %H:%M:%S"))
  println("")

  // Reading is the other direction. Directives in the format match the pieces in
  // the text; anything else has to match character for character.
  let read = @moondate.strptime("22 September 2026, 14:30", "%d %B %Y, %H:%M")
  println(read)
  println(read.strftime("%Y-%m-%dT%H:%M:%S"))

  // Whitespace in the format matches any run of whitespace, which is what makes a
  // format survive text that was aligned by hand.
  println(
    @moondate.strptime("Sun Nov  6 08:49:37 1994", "%a %b %d %H:%M:%S %Y"),
  )
  println("")

  // Go's reference-time layout. The template is Go's own reference moment
  // (`Mon Jan 2 15:04:05 MST 2006`), and each recognisable piece names a field.
  println(moment.layout(@moondate.RFC3339))
  println(moment.layout(@moondate.RFC1123))
  println(moment.layout("Monday, 02-Jan-06 15:04:05 MST"))
  println("")

  // A Unicode LDML pattern: a run of a letter names a field, and its length is the
  // width. Text in single quotes is literal.
  println(moment.pattern("EEEE, MMMM d, yyyy 'at' HH:mm"))
  println(moment.pattern("yyyy-MM-dd'T'HH:mm:ssXXX"))
  println("")

  // The ECMAScript shapes: `to_iso_string` is always the UTC instant with
  // milliseconds, `to_utc_string` is the HTTP-style GMT form, and `isoformat`
  // picks its own precision and writes the offset or leaves it off.
  println(moment.to_iso_string())
  println(moment.to_utc_string())
  println(moment.isoformat(fraction=3, offset=false))
  println("")

  // A format that does not match the text is refused, and the reason says which
  // piece failed rather than "invalid input".
  try {
    let _ = @moondate.strptime("2026-09-22", "%Y/%m/%d")
  } catch {
    err => println("refused: " + err.to_string())
  }

  // The same goes for a value that is out of range: 31 is a fine day, but not in
  // a month that has 30 of them.
  try {
    let _ = @moondate.strptime("2026-04-31", "%Y-%m-%d")
  } catch {
    err => println("refused: " + err.to_string())
  }
}
