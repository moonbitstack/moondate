///|
/// The smallest complete program: read a timestamp, look inside it, write it back out.
///
/// Everything here goes through three calls — `parse`, an accessor, and one of the
/// writers — so this is the file to read first.
///
///     moon run examples/hello
fn main raise {
  // `parse` takes any of the four shapes the library knows: a full instant with a
  // zone, a bare date and time, a bare date, or a bare time. This one is the first
  // shape, RFC 3339 with a numeric offset.
  let stamp = @moondate.parse("2026-09-22T14:30:05.123456+08:00")

  // `Show` writes it back in the same shape it came in, so the round trip is
  // visible: this prints exactly the text that went in.
  println(stamp)

  // The same instant, written with the `sep` character you pick instead of `T`.
  // `isoformat` never invents a zone: what the moment carries is what gets written.
  println(stamp.isoformat(sep=' '))

  // Accessors return `Option` only where the answer depends on the shape. A zoned
  // moment always has a date, a time and a zone, but `Moment::date` is shared with
  // the shape that carries a clock and nothing else, so it hands back `Some` here.
  let date = stamp.date().unwrap()
  let time = stamp.time()
  println(date)
  println(time)

  // Formatting goes through `strftime` when you want layout rather than a
  // standard wire form.
  println(stamp.strftime("%A %d %B %Y at %H:%M"))

  // Bad input is refused, never guessed at. The error carries the reason.
  try {
    let _ = @moondate.parse("2026-02-30T00:00:00Z")
  } catch {
    err => println("refused: \{err}")
  }
}
