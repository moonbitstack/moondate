// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A TZif file read (RFC 9636).
///
/// The format is a header, a block of 32-bit transition times, a second header and
/// a block of 64-bit ones, then — from version 2 on — a footer holding a POSIX TZ
/// string that carries the zone past the last transition. A reader that only wants
/// the modern half skips the first block; one that wants the file's own account of
/// the years before 1901 has to read it.
pub fn Tz::parse(bytes : Bytes, name~ : String = "") -> Tz raise Refused {
  let _ = (bytes, name)
  raise Malformed(kind="a TZif file", at=0)
}
