// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The lengths the reference holds and the ones it does not, replayed.
//
// Every field of a length is bounded at 2^32 - 1 — four thousand million years —
// and the reference refuses the field that passes it. The table says which
// lengths it took and which it refused, and the same lengths are measured here:
// a length past the bound is refused where it is measured, which is the same
// place the reference refuses it.

///|
/// A length from the eight fields a row writes.
fn limit_length(
  fields : (Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64),
) -> @moondate.Period {
  let (years, months, weeks, days, hours, minutes, seconds, nanos) = fields
  { years, months, weeks, days, hours, minutes, seconds, nanos, }
}

///|
test "duration: the range a length is held in" {
  let wrong : Array[String] = []
  for row in limitcase_all() {
    let length = limit_length(row.length)
    // The text is the shape a caller writes and this library reads, so reading it
    // back is where the bound is tested: a length the reference takes is a text
    // this reader takes, and one it refuses is a text this reader refuses.
    let text = length.to_string()
    let got = Some(@moondate.Period::parse(text)) catch { _ => None }
    match (row.taken, got) {
      (true, None) => wrong.push(text + ": refused, want taken")
      (false, Some(_)) => wrong.push(text + ": taken, want refused")
      _ => ()
    }
  }
  for line in wrong {
    println(line)
  }
  assert_eq(wrong.length(), 0)
}
