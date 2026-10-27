// A thin foreign-library package that re-exposes moondate to JavaScript for the
// docs site. Each function returns a String (or, for the listing, an Array of
// Strings) so the browser demos can show real output without knowing MoonBit's
// error types. Built with `moon build --target js ./demo`; the generated module
// exports the three #export_name'd functions.

///|
/// Parse any of the four shapes and render it back.
#export_name("demo_parse")
pub fn demo_parse(s : String) -> String {
  @moondate.parse(s).to_string() catch {
    e => "refused: " + e.to_string()
  }
}

///|
/// Format a parsed moment with a strftime directive string.
#export_name("demo_strftime")
pub fn demo_strftime(s : String, fmt : String) -> String {
  try {
    let m = @moondate.parse(s)
    m.strftime(fmt)
  } catch {
    e => "refused: " + e.to_string()
  }
}

///|
/// The single next cron firing after a starting moment.
#export_name("demo_cron_next")
pub fn demo_cron_next(expr : String, from : String) -> String {
  let c = @cron.parse(expr) catch { _ => return "refused: bad cron expression" }
  let start = @moondate.parse(from) catch {
    _ => return "refused: bad start time"
  }
  match c.next(start) {
    Some(m) => m.to_string()
    None => "never"
  }
}

///|
/// The next `n` cron firings after a starting moment, as a list.
#export_name("demo_cron_list")
pub fn demo_cron_list(expr : String, from : String, n : Int32) -> Array[String] {
  let c = @cron.parse(expr) catch {
    _ => return ["refused: bad cron expression"]
  }
  let mut at = @moondate.parse(from) catch {
    _ => return ["refused: bad start time"]
  }
  let out : Array[String] = []
  let mut i = 0
  while i < n {
    match c.next(at) {
      Some(m) => {
        out.push(m.to_string())
        at = m
        i = i + 1
      }
      None => {
        out.push("never")
        break
      }
    }
  }
  out
}
