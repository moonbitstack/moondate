// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The zones on this machine, replayed against files written for the purpose:
// where a system keeps them, what a name means, and what `TZ` says. Nothing here
// assumes the machine under test has a zone database — the files are ours, in a
// directory beside the build.

///|
/// The bytes `zic` writes for `Etc/UTC`, in hexadecimal — the same file
/// `src/zone/tzif_files_wbtest.mbt` keeps, here to have something real to write.
let utc_file : String = "545a69663200000000000000000000000000000000000000000000000000000000000000" +
  "000000010000000400000000000055544300545a69663200000000000000000000000000" +
  "000000000000000000000000000000000000000000010000000400000000000055544300" +
  "0a555443300a"

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
/// A directory of our own under `_build`, which the build keeps and the repository
/// ignores, so a test writes where nothing else looks.
fn scratch(name : String) -> String {
  let mut made = @env.current_dir().unwrap()
  for piece in ["_build", "zoneinfo-test", name] {
    made = made + "/" + piece
    if !@fs.path_exists(made) {
      @fs.create_dir(made) catch {
        _ => ()
      }
    }
  }
  made
}

///|
/// A file written, or `false` when the machine would not have it.
fn put(path : String, bytes : Bytes) -> Bool {
  match (Ok(@fs.write_bytes_to_file(path, bytes)) catch { _ => Err(()) }) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
/// The zone a call answered with, or `None` when it refused.
fn answer(zone : @zone.Tz) -> @zone.Tz? {
  Some(zone)
}

///|
test "a zone is read from the path it is filed at" {
  let path = scratch("by-path") + "/utc.tzif"
  assert_true(put(path, hex_bytes(utc_file)))
  let tz = answer(open(path)) catch { _ => None }
  match tz {
    None => fail("the file was not read: \{path}")
    Some(tz) => {
      // A TZif file carries no name of its own, so the path is what it is filed
      // under unless the caller says otherwise.
      assert_eq(tz.name(), path)
      assert_eq(tz.offset(0L), 0)
      assert_eq(tz.abbrev(0L), "UTC")
      assert_eq(tz.moment(1790058605L).isoformat(), "2026-09-22T06:30:05+00:00")
    }
  }
}

///|
test "a name is read from the directory" {
  let dir = scratch("by-name")
  let nested = dir + "/Test"
  if !@fs.path_exists(nested) {
    @fs.create_dir(nested) catch {
      _ => ()
    }
  }
  assert_true(put(nested + "/Zone", hex_bytes(utc_file)))
  let before = @env.get_env_var("TZDIR")
  @env.set_env_var("TZDIR", dir)
  let tz = answer(named("Test/Zone")) catch { _ => None }
  // A name that is not there is a `Missing`, not a zone built from the name.
  let absent = Ok(named("Test/Nowhere")) catch { e => Err(e) }
  match before {
    Some(value) => @env.set_env_var("TZDIR", value)
    None => @env.unset_env_var("TZDIR")
  }
  match tz {
    None => fail("the zone was not read: Test/Zone")
    Some(tz) => assert_eq(tz.name(), "Test/Zone")
  }
  match absent {
    Err(Missing(path~)) => assert_true(path.has_suffix("Test/Nowhere"))
    _ => fail("a name that is not there was not `Missing`")
  }
}

///|
test "a name the directory does not have is still a POSIX rule" {
  let dir = scratch("rule")
  let before_tzdir = @env.get_env_var("TZDIR")
  let before_tz = @env.get_env_var("TZ")
  @env.set_env_var("TZDIR", dir)
  @env.set_env_var("TZ", "CST-8")
  let fixed = answer(system()) catch { _ => None }
  @env.set_env_var("TZ", "EST5EDT,M3.2.0,M11.1.0")
  let daylight = answer(system()) catch { _ => None }
  match before_tzdir {
    Some(value) => @env.set_env_var("TZDIR", value)
    None => @env.unset_env_var("TZDIR")
  }
  match before_tz {
    Some(value) => @env.set_env_var("TZ", value)
    None => @env.unset_env_var("TZ")
  }
  match fixed {
    None => fail("`CST-8` was not read as a rule")
    Some(tz) => {
      assert_eq(tz.offset(0L), 28800)
      assert_eq(tz.abbrev(0L), "CST")
      // A rule answers as far out as it is asked, in both directions.
      assert_eq(tz.offset(-62135596800L), 28800)
    }
  }
  match daylight {
    None => fail("`EST5EDT,M3.2.0,M11.1.0` was not read as a rule")
    Some(tz) => {
      // 2026-09-22, daylight time in New York; 2026-01-15, standard time.
      assert_eq(tz.offset(1790058605L), -14400)
      assert_eq(tz.abbrev(1790058605L), "EDT")
      assert_eq(tz.offset(1768478400L), -18000)
      assert_eq(tz.abbrev(1768478400L), "EST")
    }
  }
}

///|
test "an empty TZ is UTC, which POSIX says rather than means" {
  let before = @env.get_env_var("TZ")
  @env.set_env_var("TZ", "")
  let tz = answer(system()) catch { _ => None }
  match before {
    Some(value) => @env.set_env_var("TZ", value)
    None => @env.unset_env_var("TZ")
  }
  match tz {
    None => fail("an empty TZ was not read as UTC")
    Some(tz) => {
      assert_eq(tz.name(), "UTC")
      assert_eq(tz.offset(0L), 0)
      assert_eq(tz.abbrev(0L), "UTC")
    }
  }
}

///|
test "a TZ that starts with a colon is the name after it" {
  let dir = scratch("colon")
  let nested = dir + "/Test"
  if !@fs.path_exists(nested) {
    @fs.create_dir(nested) catch {
      _ => ()
    }
  }
  assert_true(put(nested + "/Zone", hex_bytes(utc_file)))
  let before_tzdir = @env.get_env_var("TZDIR")
  let before_tz = @env.get_env_var("TZ")
  @env.set_env_var("TZDIR", dir)
  @env.set_env_var("TZ", ":Test/Zone")
  let tz = answer(system()) catch { _ => None }
  match before_tzdir {
    Some(value) => @env.set_env_var("TZDIR", value)
    None => @env.unset_env_var("TZDIR")
  }
  match before_tz {
    Some(value) => @env.set_env_var("TZ", value)
    None => @env.unset_env_var("TZ")
  }
  match tz {
    None => fail("a colon before a name was not dropped")
    Some(tz) => assert_eq(tz.name(), "Test/Zone")
  }
}

///|
test "a TZ that is a path is read from that path" {
  // A `TZ` starting at the root is a file name rather than a name in the
  // directory, which is a form POSIX has and Windows does not: `TZ` there is a
  // C runtime variable, and a drive letter is not a root.
  let path = scratch("absolute") + "/Zone"
  assert_true(put(path, hex_bytes(utc_file)))
  if path.has_prefix("/") {
    let before = @env.get_env_var("TZ")
    @env.set_env_var("TZ", path)
    let tz = answer(system()) catch { _ => None }
    match before {
      Some(value) => @env.set_env_var("TZ", value)
      None => @env.unset_env_var("TZ")
    }
    match tz {
      None => fail("a path was not read: \{path}")
      Some(tz) => assert_eq(tz.name(), path)
    }
  }
}

///|
test "bytes that are not a zone are refused as bytes, not as a path" {
  let path = scratch("not-a-zone") + "/notes.txt"
  assert_true(put(path, Bytes::from_array([1, 2, 3, 4])))
  let outcome = Ok(open(path).name()) catch {
    BadZone(_) => Err("bad zone")
    e => Err(e.to_string())
  }
  assert_eq(outcome, Err("bad zone"))
}

///|
test "a path that is not there is missing" {
  let path = scratch("missing") + "/nowhere.tzif"
  let outcome = Ok(open(path).name()) catch {
    Missing(_) => Err("missing")
    e => Err(e.to_string())
  }
  assert_eq(outcome, Err("missing"))
}

///|
test "a machine that names no zone says so" {
  // `/etc/localtime` is not on Windows and need not be anywhere; when it is there
  // this is the zone the machine runs in, and when it is not, `Unset`.
  if @fs.path_exists("/etc/localtime") {
    let tz = answer(system()) catch { _ => None }
    assert_true(tz is Some(_))
  } else {
    let before = @env.get_env_var("TZ")
    @env.unset_env_var("TZ")
    let said = Ok(system().name()) catch {
      Unset => Err("unset")
      e => Err(e.to_string())
    }
    match before {
      Some(value) => @env.set_env_var("TZ", value)
      None => @env.unset_env_var("TZ")
    }
    assert_eq(said, Err("unset"))
  }
}
