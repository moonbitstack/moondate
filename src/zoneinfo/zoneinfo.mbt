// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a zone could not be read from this machine.
///
/// The files here fail in ways a database compiled into the program cannot: the
/// file is not there, the file is there and unreadable, the environment names
/// something that is neither a zone nor a rule, and a machine may name nothing at
/// all. Each says which, and the reader is left to decide what to do about it.
#derive(Eq, Debug)
pub suberror Refused {
  /// No file at that path.
  Missing(path~ : String)
  /// A file that is there and could not be read. `said` is what the filesystem
  /// said, which is the only thing that distinguishes a permission problem from a
  /// directory that is really a directory.
  Unreadable(path~ : String, said~ : String)
  /// Bytes that are not a TZif file, or a `TZ` that is not a POSIX rule.
  BadZone(@zone.Refused)
  /// Neither `TZ` nor `/etc/localtime` says what this machine's zone is.
  Unset
}

///|
pub impl Show for Refused with fn output(self, logger) {
  match self {
    Missing(path~) => logger.write_string("no such file: \{path}")
    Unreadable(path~, said~) =>
      logger.write_string("could not read \{path}: \{said}")
    BadZone(e) => logger.write_string(e.to_string())
    Unset =>
      logger.write_string(
        "this machine names no zone: TZ is unset and /etc/localtime is not there",
      )
  }
}

///|
pub extend Refused with Debug::{to_repr}

///|
pub extend Refused with Show::{to_string, output}

///|
pub extend Refused with Eq::{not_equal, equal}

///|
/// The earliest instant an `Int64` holds, used for the reading a rule is in force
/// from.
let beginning : Int64 = -9223372036854775808L

///|
/// The directory the zones are filed in.
///
/// `TZDIR` when the environment names one, and `/usr/share/zoneinfo` otherwise,
/// which is where the IANA release is installed on every system that has one. A
/// machine that keeps them elsewhere — a container with a copy in the image, a
/// program that carries its own — says so with `TZDIR`.
pub fn directory() -> String {
  match @env.get_env_var("TZDIR") {
    Some(dir) if dir != "" => dir
    _ => "/usr/share/zoneinfo"
  }
}

///|
/// A zone read from the TZif file at `path`.
///
///     let tz = @zoneinfo.open("/etc/localtime")
///     tz.abbrev(1790058605)          // EDT, on a machine set to New York
///
/// `name` is what the zone is filed under, and the path is what it is filed under
/// by default: a TZif file carries no name of its own, so the only name there is
/// is the one it was found by. [`named`] passes the zone's name instead.
pub fn open(path : StringView, name~ : String = "") -> @zone.Tz raise Refused {
  let file = path.to_owned()
  if !@fs.path_exists(file) {
    raise Missing(path=file)
  }
  let bytes = @fs.read_file_to_bytes(file) catch {
    @fs.IOError(said) => raise Unreadable(path=file, said~)
  }
  let filed_as = if name == "" { file } else { name }
  @zone.Tz::parse(bytes, name=filed_as) catch {
    e => raise BadZone(e)
  }
}

///|
/// The zone filed under `name` in [`directory`], which is what a zone name means
/// to the system: `Asia/Shanghai`, `America/New_York`, `Etc/UTC`.
pub fn named(name : StringView) -> @zone.Tz raise Refused {
  let wanted = name.to_owned()
  open(directory() + "/" + wanted, name=wanted)
}

///|
/// The zone this machine is set to.
///
/// What `TZ` says, and `/etc/localtime` when it says nothing — the two answers
/// every other library's `localtime` gives, in that order:
///
/// - `TZ` unset: the file at `/etc/localtime`, which is how a system states its
///   zone to everything that asks.
/// - `TZ` empty: UTC, which POSIX says outright rather than by omission.
/// - `TZ` a name, with or without the leading `:` glibc allows: the file of that
///   name in [`directory`].
/// - `TZ` a path, starting at `/`: that file, wherever it is.
/// - `TZ` anything else: a POSIX TZ rule, which is how `CST-8` and
///   `EST5EDT,M3.2.0,M11.1.0` are written and how a container states a zone
///   without carrying a database.
///
/// A machine that names nothing is `Unset` rather than UTC. Guessing UTC is how a
/// program silently writes timestamps eight hours out; a caller that wants UTC can
/// say so, and a machine whose `TZ` is empty has said it.
pub fn system() -> @zone.Tz raise Refused {
  match @env.get_env_var("TZ") {
    Some(text) => from_text(text)
    None =>
      open("/etc/localtime") catch {
        Missing(_) => raise Unset
        e => raise e
      }
  }
}

///|
/// The zone a `TZ` value names.
fn from_text(text : String) -> @zone.Tz raise Refused {
  // A leading colon is glibc's marker that the rest is a file name; it says
  // nothing about what follows, so it is dropped either way.
  let written = if text.length() > 0 && text[0].unsafe_to_char() == ':' {
    text[1:].to_owned()
  } else {
    text
  }
  if written == "" {
    return from_rule("UTC0", "UTC")
  }
  if written[0].unsafe_to_char() == '/' {
    return open(written)
  }
  // A name first, because `Asia/Shanghai` is a file in the directory and no POSIX
  // rule spells it; a rule second, because `CST-8` is the other way round. A file
  // that is there and is not a zone is neither, and says so rather than being read
  // as a rule that happens to look like its name.
  let from_file : @zone.Tz? = Some(named(written)) catch {
    Missing(_) | Unreadable(_) => None
    e => raise e
  }
  match from_file {
    Some(tz) => tz
    None => from_rule(written, written)
  }
}

///|
/// A zone built from a POSIX TZ rule, in force from the beginning of time.
fn from_rule(text : String, name : String) -> @zone.Tz raise Refused {
  let rule = @zone.Rule::parse(text) catch { e => raise BadZone(e) }
  // The zone opens in standard time and the rule carries on from there, so the one
  // reading is the rule's own standard offset rather than a computation at an
  // instant a rule has no opinion about.
  let opening : @zone.Reading = {
    epoch: beginning,
    offset: rule.std_offset,
    is_dst: false,
    abbrev: rule.std_abbrev,
  }
  @zone.Tz::of(name~, readings=[opening], rule~)
}
