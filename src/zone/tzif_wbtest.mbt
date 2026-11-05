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
test "the files zic wrote, read by both versions of the format" {
  for entry in tzif_files {
    let name = entry.0
    let modern = Tz::parse(hex_bytes(entry.1), name~)
    let ancient = Tz::parse(hex_bytes(entry.2), name~)
    assert_eq(modern.name(), name)
    assert_eq(ancient.name(), name)
    for sample in tzif_samples {
      if sample.0 != name {
        continue
      }
      let reading = modern.at(sample.1)
      assert_eq(reading.offset, sample.2)
      assert_eq(reading.abbrev, sample.3)
      assert_eq(reading.is_dst, sample.4)
      // The 32-bit block is the same zone before 2038: it has no room for the
      // footer, so it cannot speak for a later instant.
      if sample.1 < 2147483647L {
        let older = ancient.at(sample.1)
        assert_eq(older.offset, sample.2)
        assert_eq(older.abbrev, sample.3)
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
  let whole = hex_bytes(tzif_files[2].1)
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
  let whole = hex_bytes(tzif_files[0].1)
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
