// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// TZif (RFC 9636). The file is a header, a block of 32-bit transition times, a
// second header and a block of 64-bit ones, then — from version 2 on — a footer
// holding a POSIX TZ string that carries the zone past the last transition.
//
// The 64-bit block is the one read, which is what every implementation of the
// format does: the 32-bit block exists so that a reader written before 2038 keeps
// working, and the two say the same thing about the years they share. A reader
// that took the 32-bit block would lose every rule written for the future.

///|
/// The counts a TZif header carries.
priv struct Head {
  version : Char
  isutcnt : Int32
  isstdcnt : Int32
  leapcnt : Int32
  timecnt : Int32
  typecnt : Int32
  charcnt : Int32
}

///|
/// One local time type: the offset, whether it is daylight saving, and where its
/// abbreviation sits in the file's character block.
priv struct TypeRecord {
  offset : Int32
  is_dst : Bool
  abbrev : Int32
}

///|
/// The smallest instant an `Int64` holds, used for the opening reading.
let beginning : Int64 = -9223372036854775808L

///|
/// A TZif file read (RFC 9636).
///
/// Versions 1 to 4 are read. A version 2 file carries the same zone twice — once
/// in 32-bit transition times, once in 64-bit — and the second copy is the one
/// used, because it is the one that keeps the years past 2038.
///
/// Leap-second records are checked for shape and then left alone: a zone answers
/// for civil time, and this library already lets a `Time` hold the sixtieth second
/// of a minute, so a leap second needs no table here.
pub fn Tz::parse(bytes : Bytes, name~ : String = "") -> Tz raise Refused {
  let first = head_at(bytes, 0)
  let modern = first.version == '2' ||
    first.version == '3' ||
    first.version == '4'
  let width = if modern { 8 } else { 4 }
  let (head, base) = if modern {
    // The 32-bit block is measured and stepped over, not read.
    let second = 44 + block_len(first, 4)
    let next = head_at(bytes, second)
    (next, second + 44)
  } else {
    (first, 44)
  }
  let (readings, rule) = block_at(bytes, base, width, head)
  { name, readings, rule, }
}

///|
/// How many bytes a data block takes, header aside.
fn block_len(head : Head, width : Int32) -> Int32 {
  head.timecnt * width +
  head.timecnt +
  head.typecnt * 6 +
  head.charcnt +
  head.leapcnt * (width + 4) +
  head.isstdcnt +
  head.isutcnt
}

///|
/// The header at `base`.
fn head_at(bytes : Bytes, base : Int32) -> Head raise Refused {
  if base + 44 > bytes.length() {
    raise Truncated(want=base + 44, got=bytes.length())
  }
  if byte_at(bytes, base) != 0x54 ||
    byte_at(bytes, base + 1) != 0x5A ||
    byte_at(bytes, base + 2) != 0x69 ||
    byte_at(bytes, base + 3) != 0x66 {
    raise Malformed(kind="a TZif file: the magic is \"TZif\"", at=base)
  }
  let version = match byte_at(bytes, base + 4) {
    0 => '1'
    v => v.unsafe_to_char()
  }
  if version != '1' && version != '2' && version != '3' && version != '4' {
    raise Unsupported(version~)
  }
  let head : Head = {
    version,
    isutcnt: i32_at(bytes, base + 20),
    isstdcnt: i32_at(bytes, base + 24),
    leapcnt: i32_at(bytes, base + 28),
    timecnt: i32_at(bytes, base + 32),
    typecnt: i32_at(bytes, base + 36),
    charcnt: i32_at(bytes, base + 40),
  }
  // A count that does not fit the file is a truncation, and a negative one is
  // corruption; both are refused before any of them is used as a length.
  if head.timecnt < 0 ||
    head.typecnt < 0 ||
    head.charcnt < 0 ||
    head.leapcnt < 0 ||
    head.isstdcnt < 0 ||
    head.isutcnt < 0 {
    raise Malformed(kind="a TZif header: a negative count", at=base + 20)
  }
  head
}

///|
/// The readings and the tail rule of the data block that starts at `base`.
fn block_at(
  bytes : Bytes,
  base : Int32,
  width : Int32,
  head : Head,
) -> (Array[Reading], Rule?) raise Refused {
  let end = base + block_len(head, width)
  if end > bytes.length() {
    raise Truncated(want=end, got=bytes.length())
  }
  let times_at = base
  let indices_at = times_at + head.timecnt * width
  let types_at = indices_at + head.timecnt
  let chars_at = types_at + head.typecnt * 6
  let types : Array[TypeRecord] = Array::makei(head.typecnt, k => {
    let at = types_at + k * 6
    {
      offset: i32_at(bytes, at),
      is_dst: byte_at(bytes, at + 4) != 0,
      abbrev: byte_at(bytes, at + 5),
    }
  })
  for k = 0; k < types.length(); k = k + 1 {
    if types[k].abbrev >= head.charcnt {
      raise Malformed(
        kind="a TZif type: an abbreviation past the block",
        at=types_at + k * 6 + 5,
      )
    }
  }
  let abbrev_of = k => {
    read_chars(bytes, chars_at + types[k].abbrev, chars_at + head.charcnt)
  }
  // What was in force before the first transition: the first standard-time type,
  // or the first type at all when the file has only daylight-saving ones, which is
  // the rule tzfile(5) states.
  let mut opening = 0
  for k = 0; k < types.length(); k = k + 1 {
    if !types[k].is_dst {
      opening = k
      break
    }
  }
  let readings : Array[Reading] = []
  readings.push(reading_of(types[opening], abbrev_of(opening), beginning))
  let mut previous = beginning
  for k = 0; k < head.timecnt; k = k + 1 {
    let epoch = if width == 8 {
      i64_at(bytes, times_at + k * 8)
    } else {
      i32_at(bytes, times_at + k * 4).to_int64()
    }
    if epoch < previous {
      raise Malformed(
        kind="a TZif transition list: out of order",
        at=times_at + k,
      )
    }
    previous = epoch
    let index = byte_at(bytes, indices_at + k)
    if index >= types.length() {
      raise Malformed(
        kind="a TZif transition: a type past the block",
        at=indices_at + k,
      )
    }
    let reading = reading_of(types[index], abbrev_of(index), epoch)
    // A transition that changes nothing is noise zic leaves out; a file that
    // carries one anyway is not refused, it is just not repeated.
    let last = readings[readings.length() - 1]
    if last.offset != reading.offset ||
      last.is_dst != reading.is_dst ||
      last.abbrev != reading.abbrev {
      readings.push(reading)
    }
  }
  (readings, footer_at(bytes, end, head.version))
}

///|
/// One reading built from a type record.
fn reading_of(record : TypeRecord, abbrev : String, epoch : Int64) -> Reading {
  { epoch, offset: record.offset, is_dst: record.is_dst, abbrev, }
}

///|
/// A NUL-terminated string in the character block.
fn read_chars(bytes : Bytes, from : Int32, end : Int32) -> String {
  let out = StringBuilder()
  let mut i = from
  while i < end && byte_at(bytes, i) != 0 {
    out.write_char(byte_at(bytes, i).unsafe_to_char())
    i = i + 1
  }
  out.to_string()
}

///|
/// The POSIX rule in the footer, if the file is version 2 or later and has one.
fn footer_at(
  bytes : Bytes,
  from : Int32,
  version : Char,
) -> Rule? raise Refused {
  if version == '1' || from >= bytes.length() {
    return None
  }
  if byte_at(bytes, from) != 0x0A {
    raise Malformed(kind="a TZif footer: a newline", at=from)
  }
  let out = StringBuilder()
  let mut i = from + 1
  while i < bytes.length() && byte_at(bytes, i) != 0x0A {
    out.write_char(byte_at(bytes, i).unsafe_to_char())
    i = i + 1
  }
  let text = out.to_string()
  if text == "" {
    None
  } else {
    Some(Rule::parse(text))
  }
}

///|
fn byte_at(bytes : Bytes, i : Int32) -> Int32 {
  bytes[i].to_int() & 0xFF
}

///|
/// A big-endian 32-bit signed integer, in two's complement.
fn i32_at(bytes : Bytes, i : Int32) -> Int32 {
  (byte_at(bytes, i) << 24) |
  (byte_at(bytes, i + 1) << 16) |
  (byte_at(bytes, i + 2) << 8) |
  byte_at(bytes, i + 3)
}

///|
/// A big-endian 64-bit signed integer, in two's complement.
fn i64_at(bytes : Bytes, i : Int32) -> Int64 {
  (i32_at(bytes, i).to_int64() << 32) |
  (i32_at(bytes, i + 4).to_int64() & 0xFFFFFFFFL)
}
