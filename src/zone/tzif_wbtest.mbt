// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// TZif files read (RFC 9636), replayed against the bytes zic wrote and the
// readings Python's zoneinfo and Go's time take from the same bytes.

///|
/// Hexadecimal as bytes.
fn hex_bytes(text : String) -> Bytes {
  let out : Array[Byte] = []
  for k = 0; k < text.length(); k = k + 2 {
    out.push(
      ((nibble(text[k].unsafe_to_char()) << 4) |
      nibble(text[k + 1].unsafe_to_char())).to_byte(),
    )
  }
  Bytes::from_array(out)
}

///|
fn nibble(c : Char) -> Int32 {
  let value = c.to_int()
  if value >= 97 {
    value - 87
  } else if value >= 65 {
    value - 55
  } else {
    value - 48
  }
}

///|
/// The fields of a line, split on spaces.
fn tokens_of(line : String) -> Array[String] {
  let out : Array[String] = []
  let mut from = -1
  for k = 0; k <= line.length(); k = k + 1 {
    let space = k == line.length() || line[k].unsafe_to_char() == ' '
    if space {
      if from >= 0 {
        out.push(line[from:k].to_owned())
        from = -1
      }
    } else if from < 0 {
      from = k
    }
  }
  out
}

///|
/// A signed whole number, as the samples write them.
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
/// The three parts of a line: the name, the version 2 bytes, the version 1 bytes.
fn fixture(line : String) -> (String, String, String) {
  let fields = tokens_of(line)
  (fields[0], fields[1], fields[2])
}

///|
test "the files zic wrote, read by both versions of the format" {
  for line in tzif_chunks {
    let (name, modern_bytes, ancient_bytes) = fixture(line)
    let modern = Tz::parse(hex_bytes(modern_bytes), name~)
    let ancient = Tz::parse(hex_bytes(ancient_bytes), name~)
    assert_eq(modern.name(), name)
    assert_eq(ancient.name(), name)
    for sample in tzif_samples.split("\n") {
      let fields = tokens_of(sample.to_owned())
      if fields[0] != name {
        continue
      }
      let when = numeral(fields[1])
      let reading = modern.at(when)
      assert_eq(reading.offset, numeral(fields[2]).to_int())
      assert_eq(reading.abbrev, fields[3])
      assert_eq(reading.is_dst, fields[4] == "1")
      // The 32-bit block is the same zone before 2038: it has no room for the
      // footer, so it cannot speak for a later instant.
      if when < 2147483647L {
        let older = ancient.at(when)
        assert_eq(older.offset, reading.offset)
        assert_eq(older.abbrev, reading.abbrev)
      }
    }
  }
}

///|
test "a file that is not a TZif file" {
  let not_ours : Array[Byte] = []
  for k = 0; k < 44; k = k + 1 {
    not_ours.push(b'\x00')
  }
  let not_ours = Bytes::from_array(not_ours)
  let outcome = try {
    let _ = Tz::parse(not_ours)
    "read"
  } catch {
    Malformed(kind~, ..) => kind
    _ => "another refusal"
  }
  assert_eq(outcome, "a TZif file: the magic is \"TZif\"")
}

///|
test "a file cut short" {
  let whole = hex_bytes(fixture(tzif_chunks[2]).1)
  let piece : Array[Byte] = []
  for k = 0; k < 60; k = k + 1 {
    piece.push(whole[k])
  }
  let piece = Bytes::from_array(piece)
  let outcome = try {
    let _ = Tz::parse(piece)
    "read"
  } catch {
    Truncated(..) => "truncated"
    _ => "another refusal"
  }
  assert_eq(outcome, "truncated")
}

///|
test "a version this reader does not know" {
  let whole = hex_bytes(fixture(tzif_chunks[0]).1)
  let strange : Array[Byte] = []
  for k = 0; k < whole.length(); k = k + 1 {
    strange.push(whole[k])
  }
  strange[4] = b'9'
  let strange = Bytes::from_array(strange)
  let outcome = try {
    let _ = Tz::parse(strange)
    "read"
  } catch {
    Unsupported(version~) => version.to_string()
    _ => "another refusal"
  }
  assert_eq(outcome, "9")
}
