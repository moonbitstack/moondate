// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The whole database replayed against Python's zoneinfo and Go's time.
//
// The vectors are every point between 1800 and 2100 at which either reference
// says a zone changed what it reads, and each one is checked twice: at the instant
// itself, and a second before it, which is the pair that catches a transition
// placed on the wrong side of the second it belongs to.

///|
/// The vector text as one string.
fn vector_text() -> String {
  let out = StringBuilder()
  for chunk in transition_chunks {
    out.write_string(chunk)
    out.write_string("\n")
  }
  out.to_string()
}

///|
/// A signed whole number, as the vectors write them.
fn numeral(text : String) -> Int64 {
  let mut i = 0
  let mut sign = 1L
  if text.length() > 0 && text[0].unsafe_to_char() == '-' {
    sign = -1L
    i = 1
  }
  let mut out = 0L
  while i < text.length() {
    out = out * 10L + (text[i].unsafe_to_char().to_int() - 48).to_int64()
    i = i + 1
  }
  sign * out
}

///|
test "every transition of every zone, 1800 to 2100" {
  let mut zone : @zone.Tz? = None
  let mut name = ""
  let mut previous : (Int32, String, Bool)? = None
  let mut checked = 0
  let mut zones = 0
  let wrong : Array[String] = []
  for line in vector_text().split("\n") {
    let text = line.to_owned()
    if text.length() == 0 {
      continue
    }
    if text[0].unsafe_to_char() == 'Z' {
      name = text[2:].to_owned()
      zone = Some(load(name))
      previous = None
      zones = zones + 1
      continue
    }
    let fields = tokens_of(text)
    if fields.length() != 4 {
      wrong.push("a vector with " + fields.length().to_string() + " fields")
      continue
    }
    let at = numeral(fields[0])
    let offset = numeral(fields[1]).to_int()
    let abbrev = fields[2]
    let daylight = fields[3] == "1"
    let tz = zone.unwrap()
    let reading = tz.at(at)
    if reading.offset != offset ||
      reading.abbrev != abbrev ||
      reading.is_dst != daylight {
      wrong.push(
        "\{name} at \{at}: want \{offset} \{abbrev} \{daylight}, got \{reading.offset} \{reading.abbrev} \{reading.is_dst}",
      )
    }
    match previous {
      Some((was_offset, was_abbrev, was_daylight)) => {
        let before = tz.at(at - 1L)
        if before.offset != was_offset ||
          before.abbrev != was_abbrev ||
          before.is_dst != was_daylight {
          wrong.push(
            "\{name} a second before \{at}: want \{was_offset} \{was_abbrev} \{was_daylight}, got \{before.offset} \{before.abbrev} \{before.is_dst}",
          )
        }
      }
      None => ()
    }
    previous = Some((offset, abbrev, daylight))
    checked = checked + 1
  }
  if wrong.length() > 0 {
    let head = StringBuilder()
    for i = 0; i < wrong.length() && i < 10; i = i + 1 {
      head.write_string(wrong[i])
      head.write_string("\n")
    }
    fail(
      "\{wrong.length()} of \{checked} vectors are wrong, first ones:\n\{head.to_string()}",
    )
  }
  assert_eq(zones, 598)
  assert_eq(checked, 64891)
}
