// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The next or the previous instant the zone's offset changed.
///
/// The table of readings a file carries answers up to its last entry; after that
/// the footer's rule does, and a rule is a pattern rather than a list, so the
/// changes it holds are placed year by year. A zone with neither — a fixed
/// offset — has none, which is `None`.
pub fn Tz::transition(
  self : Tz,
  epoch : Int64,
  direction~ : Direction,
) -> Int64? {
  let readings = self.readings
  match direction {
    Next => {
      for reading in readings {
        if reading.epoch > epoch {
          return Some(reading.epoch)
        }
      }
      match self.rule {
        None => None
        Some(rule) => {
          let from = if readings.length() > 0 {
            let last = readings[readings.length() - 1].epoch
            if epoch > last {
              epoch
            } else {
              last
            }
          } else {
            epoch
          }
          rule.next_change(from)
        }
      }
    }
    Previous => {
      // The first reading is the beginning of the zone's history, not a change
      // from anything, so it is never the answer.
      let mut found : Int64? = None
      for i = 1; i < readings.length(); i = i + 1 {
        if readings[i].epoch < epoch {
          found = Some(readings[i].epoch)
        }
      }
      match found {
        Some(at) => Some(at)
        None =>
          match self.rule {
            None => None
            Some(rule) => rule.previous_change(epoch)
          }
      }
    }
  }
}

///|
/// The first change the rule makes after an instant.
fn Rule::next_change(self : Rule, after : Int64) -> Int64? {
  let mut best : Int64? = None
  let year = year_of(after)
  for y = year - 1; y <= year + 2; y = y + 1 {
    for at in self.changes_in(y) {
      if at > after {
        match best {
          Some(found) => if at < found { best = Some(at) }
          None => best = Some(at)
        }
      }
    }
  }
  best
}

///|
/// The last change the rule makes before an instant.
fn Rule::previous_change(self : Rule, before : Int64) -> Int64? {
  let mut best : Int64? = None
  let year = year_of(before)
  for y = year - 2; y <= year + 1; y = y + 1 {
    for at in self.changes_in(y) {
      if at < before {
        match best {
          Some(found) => if at > found { best = Some(at) }
          None => best = Some(at)
        }
      }
    }
  }
  best
}

///|
/// The two instants the rule changes the clocks in one year; none when it has no
/// daylight saving at all.
fn Rule::changes_in(self : Rule, year : Int32) -> Array[Int64] {
  match (self.dst_offset, self.dst_start, self.dst_end) {
    (Some(dst), Some(start), Some(end)) =>
      [instant_of(start, year, self.std_offset), instant_of(end, year, dst)]
    _ => []
  }
}
