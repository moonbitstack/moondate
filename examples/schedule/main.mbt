/// Cron expressions: what they mean, when they fire, and when they never fire.
///
/// The expression language is Vixie cron's, the one every scheduler has copied.
/// This file reads expressions, asks whether an instant matches one, and walks
/// forward to the next few firings.
///
///     moon run examples/schedule

///|
/// The next `count` firings after `from`, one per line. `next` always returns a
/// moment strictly after the one you give it, so feeding the answer back in is
/// how you walk forward.
fn list_firings(expr : String, from : String, count : Int32) -> Unit raise {
  let cron = @cron.parse(expr)
  let mut at = @moondate.parse(from)
  let mut n = 0
  while n < count {
    match cron.next(at) {
      Some(fire) => {
        println("  " + fire.to_string())
        at = fire
        n = n + 1
      }
      None => {
        // An expression can name a day that never comes, such as 30 February.
        // There is no next firing, and saying so is better than looping forever.
        println("  never")
        n = count
      }
    }
  }
}

///|
fn main raise {
  let start = "2026-09-22T14:30:00Z" // a Tuesday afternoon

  // ---- the five fields ----------------------------------------------------
  //
  // minute, hour, day of month, month, day of week. Five fields, left to right.
  // `*` is "every", a number is itself, `a-b` is a range, `a,b` is a list, and
  // `*/n` steps through the field.
  //
  //     0 9 * * MON-FRI   at 09:00, Monday through Friday
  //     │ │ │ │ └───────── day of week, names allowed
  //     │ │ │ └─────────── month, 1-12 or JAN-DEC
  //     │ │ └───────────── day of month, 1-31
  //     │ └─────────────── hour, 0-23
  //     └───────────────── minute, 0-59

  println("0 9 * * MON-FRI")
  list_firings("0 9 * * MON-FRI", start, 5)
  println("")

  // A range with a step: every fifteen minutes, on the hour and after.
  println("*/15 * * * *")
  list_firings("*/15 * * * *", start, 6)
  println("")

  // Lists are written with commas and can mix numbers with names.
  println("0 0 1 JAN,JUL *")
  list_firings("0 0 1 JAN,JUL *", start, 3)
  println("")

  // ---- the seconds field --------------------------------------------------
  //
  // Six fields means the first one is seconds, which is what makes a schedule
  // that fires more than once a minute expressible at all.

  println("*/20 * * * * *")
  list_firings("*/20 * * * * *", start, 5)
  println("")

  // ---- the awkward rule ---------------------------------------------------
  //
  // When both day fields are restricted, Vixie cron fires when *either* matches,
  // not when both do. The thirteenth of the month, or any Friday — which is how
  // "Friday the 13th" is usually meant, and not how it reads.

  println("0 0 13 * FRI")
  list_firings("0 0 13 * FRI", start, 6)
  println("")

  // Star one of them and the other is the only condition, as you would expect.
  println("0 0 * * FRI")
  list_firings("0 0 * * FRI", start, 3)
  println("")

  // ---- matching -----------------------------------------------------------
  //
  // `matches` answers the question for one instant, which is what a scheduler
  // running inside an event loop wants: it can wake up every minute and ask
  // rather than compute.

  let hourly = @cron.parse("0 * * * *")
  let noon = @moondate.parse("2026-09-22T12:00:00Z")
  let half_past = @moondate.parse("2026-09-22T12:30:00Z")
  println("at 12:00 " + hourly.matches(noon).to_string())
  println("at 12:30 " + hourly.matches(half_past).to_string())
  println("")

  // ---- refusals -----------------------------------------------------------
  //
  // Four fields, or 61 minutes, or a month called FOO: each one is refused with
  // the field and the range that failed.

  let bad = ["0 9 * *", "61 * * * *", "0 0 * FOO *"]
  for expr in bad {
    try {
      let _ = @cron.parse(expr)
      println(expr + " -> accepted")
    } catch {
      err => println(expr + " -> " + err.to_string())
    }
  }
}
