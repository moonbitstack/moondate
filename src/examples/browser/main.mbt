// A thin foreign-library package that re-exposes moondate to JavaScript for the
// docs site. Every function returns a String — one line per row, one tab between
// the fields of a row — so the page never meets a MoonBit type, an error, or an
// array. Built with `moon build --target js --release src/examples/browser`; the
// generated module exports the functions marked below.

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
/// Format a parsed moment in any of the five styles: a `%` directive string, a Go
/// layout, an LDML pattern, or the ECMAScript ISO shape.
#export_name("demo_format")
pub fn demo_format(s : String, style : String, arg : String) -> String {
  try {
    let m = @moondate.parse(s)
    match style {
      "pct" => m.strftime(arg)
      "layout" => m.layout(arg)
      "pattern" => m.pattern(arg)
      "iso" => m.isoformat()
      _ => "refused: unknown style " + style
    }
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
/// The next `n` cron firings after a starting moment, one per line.
///
/// Lines rather than an array: a MoonBit `Array` crosses into JavaScript as an
/// object with a buffer and a length rather than as a JavaScript array, so the
/// page would have to know how one is laid out. A string it can split.
#export_name("demo_cron_list")
pub fn demo_cron_list(expr : String, from : String, n : Int32) -> String {
  let c = @cron.parse(expr) catch { _ => return "refused: bad cron expression" }
  let mut at = @moondate.parse(from) catch {
    _ => return "refused: bad start time"
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
  join_lines(out)
}

///|
/// A list of lines as one string, which is what the page splits.
fn join_lines(items : Array[String]) -> String {
  let out = StringBuilder()
  for i = 0; i < items.length(); i = i + 1 {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string(items[i])
  }
  out.to_string()
}

// ---- zones ---------------------------------------------------------------
// The database is compiled in, so these functions answer from the same data the
// library ships: the release's own compendium, read on demand.

///|
/// Every name the database knows, for the page's list of zones.
#export_name("demo_zone_names")
pub fn demo_zone_names() -> String {
  join_lines(@tzdata.zones())
}

///|
/// The release the answers come from, so the page can say which one it is.
#export_name("demo_zone_release")
pub fn demo_zone_release() -> String {
  @tzdata.release
}

///|
/// `±HH:MM` for an offset in seconds, which a zone's offset is.
fn offset_text(seconds : Int32) -> String {
  let sign = if seconds < 0 { "-" } else { "+" }
  let a = if seconds < 0 { -seconds } else { seconds }
  let two = fn(n : Int32) -> String {
    if n < 10 {
      "0" + n.to_string()
    } else {
      n.to_string()
    }
  }
  sign + two(a / 3600) + ":" + two(a % 3600 / 60)
}

///|
/// The date part of a day, or nothing when the text is not one.
fn day_of(text : String) -> @moondate.Date? {
  match (@moondate.parse(text) catch { _ => return None }) {
    m => m.date()
  }
}

///|
/// The clock part of a time, or nothing when the text is not one.
fn clock_of(text : String) -> @moondate.Time? {
  match (@moondate.parse(text) catch { _ => return None }) {
    m => Some(m.time())
  }
}

///|
/// One instant read in several zones at once: `zones` is newline separated, and
/// each row comes back as `name \t date and time \t abbreviation \t offset \t
/// daylight`.
#export_name("demo_zone_rows")
pub fn demo_zone_rows(instant : String, zones : String) -> String {
  let out : Array[String] = []
  let at = @moondate.parse(instant) catch {
    _ => return "refused: that text is not a moment"
  }
  let epoch = match at.epoch() {
    Some(e) => e
    None => return "refused: that text names no instant"
  }
  for zone in zones.split("\n") {
    let name = zone.to_owned()
    if name == "" {
      continue
    }
    match @tzdata.find(name) {
      Some(tz) => {
        let reading = tz.at(epoch)
        out.push(
          name +
          "\t" +
          tz.moment(epoch).strftime("%Y-%m-%d %H:%M") +
          "\t" +
          reading.abbrev +
          "\t" +
          offset_text(reading.offset) +
          "\t" +
          (if reading.is_dst { "daylight" } else { "standard" }),
        )
      }
      None => out.push(name + "\trefused\tunknown zone\t\t")
    }
  }
  join_lines(out)
}

///|
/// A wall clock read in one zone, and what each policy does with it.
///
/// Each row is `label \t value \t note`: the first says whether the clock happens
/// once, twice or never, and the four after it are the `Fold` policies.
#export_name("demo_zone_read")
pub fn demo_zone_read(zone : String, date : String, time : String) -> String {
  let tz = match @tzdata.find(zone) {
    Some(tz) => tz
    None => return "read\trefused\tnothing is filed under that name"
  }
  let day = match day_of(date) {
    Some(d) => d
    None => return "read\trefused\tthat is not a date"
  }
  let clock = match clock_of(time) {
    Some(t) => t
    None => return "read\trefused\tthat is not a time"
  }
  let wall = tz.read(day, clock)
  let out : Array[String] = []
  match wall {
    Exact(_) => out.push("read\tonce\tthis clock names one instant")
    Ambiguous(..) => out.push("read\ttwice\tthis clock names two instants")
    Skipped(..) => out.push("read\tnever\tnothing on the clock reads like this")
  }
  let describe = fn(policy : String, fold : @zone.Fold) {
    let found : (Int64, @moondate.Moment)? = try {
      let epoch = wall.epoch(fold~)
      Some((epoch, tz.moment(epoch)))
    } catch {
      _ => None
    }
    match found {
      Some((epoch, moment)) =>
        out.push(
          policy +
          "\t" +
          moment.strftime("%Y-%m-%d %H:%M %Z") +
          "\t" +
          @moondate.Moment::of_epoch(epoch).to_string(),
        )
      None => out.push(policy + "\trefused\tthis policy declines to pick")
    }
  }
  describe("Compatible", @zone.Compatible)
  describe("Earlier", @zone.Earlier)
  describe("Later", @zone.Later)
  describe("Reject", @zone.Reject)
  join_lines(out)
}
