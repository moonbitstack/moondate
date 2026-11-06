// Collect the Temporal cases from test262 that say something about reading a
// zoned date and time out of text.
//
// test262 asserts against its own implementation, so the assertions cannot be
// read as data by parsing the files: the values are built at run time, in loops,
// through helpers. What this does instead is run each file against a stand-in
// `Temporal` that records what it was asked and what the test expected back:
//
//   Temporal.ZonedDateTime.from(str)   -> a recording object;
//   assert.sameValue(recorded.x, v)    -> "that input has x = v";
//   assert.throws(RangeError, ...)     -> "that input must be refused".
//
// A case is written down only when a test says what it wants, so the output is
// what test262 actually asserts rather than what a heuristic guesses. Everything
// the stand-in cannot answer is ignored, and the run reports how much that was.

import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import vm from "node:vm";

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  args.set(process.argv[i], process.argv[i + 1]);
}
const tests = args.get("--tests");
const out = args.get("--out");
const pin = args.get("--pin") ?? "unknown";
if (!tests || !out) {
  console.error("usage: collect.mjs --tests <dir> --out <file> [--pin <sha>]");
  process.exit(2);
}

// ---- the stand-in ---------------------------------------------------------

let seq = 0;
const records = new Map();
let refusing = null;

function refusal(name) {
  const errors = { RangeError, TypeError, SyntaxError };
  const made = errors[name] ?? Error;
  return new made(`test262 expects ${name}`);
}

function format(value) {
  if (typeof value === "bigint") return value.toString();
  if (value === null) return "null";
  if (typeof value === "object" && value !== null && "__epochNs" in value) {
    return value.__epochNs;
  }
  return String(value);
}

// A recorded answer: every property the test reads comes back as a marker that
// says which record it belongs to, and `assert.sameValue` turns the marker plus
// the expected value into a fact.
function recorded(input, kind) {
  if (refusing !== null) {
    const id = ++seq;
    records.set(id, { input, kind, thrown: refusing });
    throw refusal(refusing);
  }
  const id = ++seq;
  records.set(id, { input, kind, expected: {} });
  const target = { __id: id };
  return new Proxy(target, {
    get(t, prop) {
      if (prop === "__id") return id;
      if (prop === "toString" || prop === "toJSON" || prop === "valueOf") {
        return () => `<record ${id}>`;
      }
      return { __rec: id, __prop: String(prop) };
    },
  });
}

class ZonedDateTimeStand {
  constructor(epochNs, zone) {
    this.__epochNs = format(epochNs);
    this.__zone = zone && typeof zone === "object" && "__zone" in zone
      ? zone.__zone
      : String(zone);
  }
  get epochNanoseconds() {
    return this.__epochNs;
  }
  get timeZoneId() {
    return this.__zone;
  }
  toString() {
    return `<zoned ${this.__epochNs} ${this.__zone}>`;
  }
}

// Anything else in the namespace answers with something that can be called, read
// and constructed without complaint, so a test that wanders off the subject
// keeps running instead of throwing a TypeError at us.
function anything() {
  const fn = function () {
    return anything();
  };
  const proxy = new Proxy(fn, {
    get(t, prop) {
      if (prop === Symbol.toPrimitive) return () => "";
      if (prop === "toString") return () => "";
      if (prop === "valueOf") return () => 0;
      if (prop === "__zone") return "";
      return anything();
    },
    construct() {
      return anything();
    },
    apply() {
      return anything();
    },
  });
  return proxy;
}

// One constructor per kind. `from` is the only thing under test; `new` is there
// for the tests that compare a reading against one they built by hand.
function kindNamespace(kind) {
  const made = function (...params) {
    return new ZonedDateTimeStand(...params);
  };
  made.from = function (value, options) {
    // A second argument is an options object, and `{ offset: "use" }` and
    // `{ offset: "ignore" }` read the same text two different ways. Such a case
    // says nothing about reading text, so it is not recorded.
    if (options !== undefined) return anything();
    return typeof value === "string"
      ? recorded(value, kind)
      : recorded("<not a string>", kind);
  };
  return made;
}

const Temporal = new Proxy(
  {
    ZonedDateTime: kindNamespace("ZonedDateTime"),
    PlainDate: kindNamespace("PlainDate"),
    PlainDateTime: kindNamespace("PlainDateTime"),
    PlainTime: kindNamespace("PlainTime"),
    Instant: kindNamespace("Instant"),
  },
  {
    get(t, prop) {
      if (prop in t) return t[prop];
      return anything();
    },
  },
);

// The helpers state a whole reading at once, so each one is a different sentence
// about the same record.
function fieldsOf(actual) {
  const id = actual && typeof actual === "object" ? actual.__id : undefined;
  if (typeof id !== "number" || !records.has(id)) return null;
  return records.get(id);
}

const TemporalHelpers = new Proxy(
  {
    // assertPlainDate(date, year, month, monthCode, day, description, era, eraYear)
    assertPlainDate(actual, year, month, monthCode, day) {
      const record = fieldsOf(actual);
      if (!record) return;
      record.expected.year = format(year);
      record.expected.month = format(month);
      record.expected.day = format(day);
    },
    // assertPlainDateTime(dt, year, month, monthCode, day, hour, minute, second,
    //                     millisecond, microsecond, nanosecond, description, …)
    assertPlainDateTime(actual, year, month, monthCode, day, hour, minute, second, ms, us, ns) {
      const record = fieldsOf(actual);
      if (!record) return;
      record.expected.year = format(year);
      record.expected.month = format(month);
      record.expected.day = format(day);
      record.expected.hour = format(hour);
      record.expected.minute = format(minute);
      record.expected.second = format(second);
      record.expected.millisecond = format(ms);
      record.expected.microsecond = format(us);
      record.expected.nanosecond = format(ns);
    },
    // assertPlainTime(time, hour, minute, second, millisecond, microsecond,
    //                 nanosecond, description)
    assertPlainTime(actual, hour, minute, second, ms, us, ns) {
      const record = fieldsOf(actual);
      if (!record) return;
      record.expected.hour = format(hour);
      record.expected.minute = format(minute);
      record.expected.second = format(second);
      record.expected.millisecond = format(ms);
      record.expected.microsecond = format(us);
      record.expected.nanosecond = format(ns);
    },
    assertZonedDateTimesEqual(actual, expected) {
      const id = actual && typeof actual === "object" ? actual.__id : undefined;
      if (typeof id !== "number" || !records.has(id)) return;
      if (!expected || typeof expected !== "object") return;
      if (expected.__epochNs === undefined) return;
      const record = records.get(id);
      record.expected.epochNanoseconds = expected.__epochNs;
      record.expected.timeZoneId = expected.__zone;
    },
  },
  {
    get(t, prop) {
      if (prop in t) return t[prop];
      return () => undefined;
    },
  },
);

const assert = new Proxy(
  {
    sameValue(actual, expected) {
      if (actual && typeof actual === "object") {
        const id = actual.__rec;
        const prop = actual.__prop;
        if (typeof id === "number" && typeof prop === "string" && records.has(id)) {
          records.get(id).expected[prop] = format(expected);
        }
        return;
      }
      if (typeof actual === "string") {
        const found = /^<record (\d+)>$/.exec(actual);
        if (found && records.has(Number(found[1]))) {
          records.get(Number(found[1])).expected.toString = String(expected);
        }
      }
    },
    throws(expected, fn) {
      const name = expected && expected.name ? expected.name : "Error";
      const was = refusing;
      refusing = name;
      try {
        fn();
      } catch (e) {
        // The stand-in threw the refusal the test asked for, which is the case
        // being recorded; anything else is the shim being asked something it
        // does not answer.
      } finally {
        refusing = was;
      }
    },
  },
  {
    get(t, prop) {
      if (prop in t) return t[prop];
      return () => undefined;
    },
  },
);

// ---- the run --------------------------------------------------------------

const files = [];
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) walk(path);
    else if (entry.endsWith(".js")) files.push(path);
  }
}
walk(tests);

let ran = 0;
let failed = 0;
const cases = [];

for (const file of files) {
  seq = 0;
  records.clear();
  const before = cases.length;
  const source = readFileSync(file, "utf8");
  const context = vm.createContext({
    Temporal,
    TemporalHelpers,
    assert,
    print: () => {},
    $DONOTEVALUATE: () => {
      throw new Error("$DONOTEVALUATE");
    },
  });
  try {
    new vm.Script(source, { filename: file }).runInContext(context, {
      timeout: 5000,
    });
    ran += 1;
  } catch (e) {
    // A test that needed something the stand-in does not model is not an error
    // in the corpus; the cases it recorded before it stopped are still good.
    ran += 1;
    failed += 1;
  }
  for (const [, record] of records) {
    if (record.input === "<not a string>") continue;
    const expected = record.expected ?? {};
    if (record.thrown) {
      cases.push({
        input: record.input,
        kind: record.kind,
        file: relative(tests, file),
        thrown: record.thrown,
      });
      continue;
    }
    if (expected.epochNanoseconds !== undefined) {
      cases.push({
        input: record.input,
        kind: record.kind,
        file: relative(tests, file),
        epochNanoseconds: expected.epochNanoseconds,
        timeZoneId: expected.timeZoneId ?? null,
      });
      continue;
    }
    // A plain reading states its fields rather than an instant. A zoned one has
    // those fields too, which is why the kind has to agree.
    if (expected.year !== undefined && record.kind !== "ZonedDateTime") {
      cases.push({
        input: record.input,
        kind: record.kind,
        file: relative(tests, file),
        fields: expected,
      });
      continue;
    }
    // Only the time zone was asserted, which is still a fact about the text.
    if (expected.timeZoneId !== undefined) {
      cases.push({
        input: record.input,
        kind: record.kind,
        file: relative(tests, file),
        epochNanoseconds: null,
        timeZoneId: expected.timeZoneId,
      });
    }
  }
}

const seen = new Set();
const unique = [];
for (const item of cases) {
  const key = JSON.stringify([
    item.input,
    item.kind,
    item.thrown ?? null,
    item.epochNanoseconds,
    item.timeZoneId,
    item.fields ?? null,
  ]);
  if (seen.has(key)) continue;
  seen.add(key);
  unique.push(item);
}

writeFileSync(
  out,
  JSON.stringify(
    {
      pin,
      files: files.length,
      files_that_ran: ran,
      files_that_stopped: failed,
      cases: unique.length,
      corpus: unique,
    },
    null,
    1,
  ) + "\n",
  "utf8",
);

console.log(
  `${files.length} files, ${ran} ran (${failed} stopped early), ${unique.length} distinct cases`,
);
