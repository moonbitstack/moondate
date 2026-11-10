// Run test262's ZonedDateTime cases and write down what the reference
// implementation did, operation by operation.
//
// The corpus asserts against its own implementation, and the values in a case
// are built at run time, so the file is run rather than read: a recording
// `Temporal` stands in for the global, notes each operation with the state it
// was given and the answer it gave, and the case is only kept when it passes,
// which is what makes the corpus, and not this recorder, the authority.
//
//   node --harmony-temporal collect_zoned.mjs --root <test262> --out zoned.json
//
// `--harmony-temporal` is what Node 22 needs to have the namespace at all. The
// cases run in this realm rather than a fresh one: a `TypeError` from another
// realm is a different constructor, and the corpus compares constructors.

import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { createRequire } from "node:module";

const SUITE = "test/built-ins/Temporal/ZonedDateTime";

// -- what a value is, said in the terms a replay needs -------------------------

function kindOf(value) {
  if (value === null) return "null";
  const t = typeof value;
  if (t === "bigint") return "bigint";
  if (t !== "object" && t !== "function") return t;
  // A plain bag is classified before anything is read from it: a bag whose
  // properties are getters is a case about the order a host reads it, and
  // reading `epochNanoseconds` off one here would be that very read.
  if (Array.isArray(value)) return "array";
  const prototype = Object.getPrototypeOf(value);
  if (prototype === null || prototype === Object.prototype) return "object";
  if (typeof value.epochNanoseconds === "bigint" && "timeZoneId" in value) {
    return "zoned";
  }
  if (typeof value.epochNanoseconds === "bigint") return "instant";
  if (typeof value.years === "number" && typeof value.nanoseconds === "number") {
    return "duration";
  }
  if (typeof value.hour === "number" && typeof value.minute === "number") {
    if (typeof value.year === "number" && typeof value.month === "number") {
      return "datetime";
    }
    return "time";
  }
  if (typeof value.year === "number" && typeof value.month === "number") {
    return "date";
  }
  return "other";
}

function serialise(value) {
  switch (kindOf(value)) {
    case "zoned":
      return {
        t: "zoned",
        ns: value.epochNanoseconds.toString(),
        tz: value.timeZoneId,
        cal: value.calendarId,
      };
    case "instant":
      return { t: "instant", ns: value.epochNanoseconds.toString() };
    case "duration":
      return {
        t: "duration",
        y: value.years,
        mo: value.months,
        w: value.weeks,
        d: value.days,
        h: value.hours,
        mi: value.minutes,
        s: value.seconds,
        ms: value.milliseconds,
        us: value.microseconds,
        ns: value.nanoseconds,
      };
    case "datetime":
      return {
        t: "datetime",
        y: value.year,
        mo: value.month,
        d: value.day,
        h: value.hour,
        mi: value.minute,
        s: value.second,
        ms: value.millisecond,
        us: value.microsecond,
        ns: value.nanosecond,
      };
    case "date":
      return { t: "date", y: value.year, mo: value.month, d: value.day };
    case "time":
      return {
        t: "time",
        h: value.hour,
        mi: value.minute,
        s: value.second,
        ms: value.millisecond,
        us: value.microsecond,
        ns: value.nanosecond,
      };
    case "bigint":
      return { t: "bigint", v: value.toString() };
    case "array":
      return { t: "array", v: value.map(serialise) };
    case "object": {
      // An options bag or a field bag: what the operation was asked for, which
      // is half of what a replay needs. Only own data properties are read —
      // a bag built out of getters is a case about the order a host reads it,
      // and reading it here would be the very thing under test.
      const out = {};
      const descriptors = Object.getOwnPropertyDescriptors(value);
      for (const key of Object.keys(descriptors).sort()) {
        const description = descriptors[key];
        if (!("value" in description)) {
          out[key] = { t: "accessor" };
          continue;
        }
        out[key] = serialise(description.value);
      }
      return { t: "object", v: out };
    }
    case "function":
      return { t: "function" };
    case "other":
      return { t: "other", text: Object.prototype.toString.call(value) };
    case "undefined":
      return { t: "undefined" };
    case "string":
    case "number":
    case "boolean":
      return { t: "prim", v: Number.isFinite(value) || typeof value !== "number" ? value : String(value) };
    default:
      return { t: "other", text: typeof value };
  }
}

function errorName(error) {
  if (error && typeof error.name === "string") return error.name;
  return "Error";
}

// -- the recorder --------------------------------------------------------------

function buildRecorder(real, record) {
  const proto = real.ZonedDateTime.prototype;
  const wrappers = new Map();

  // Every member is taken from its own descriptor: `hoursInDay` reads like a
  // method and is an accessor, so asking the prototype for it would run it on
  // the prototype itself.
  for (const name of Object.getOwnPropertyNames(proto)) {
    if (name === "constructor") continue;
    const description = Object.getOwnPropertyDescriptor(proto, name);
    if (description.get) {
      const original = description.get;
      wrappers.set(name, {
        configurable: true,
        enumerable: description.enumerable,
        get() {
          const answer = original.call(this);
          record({ op: "get:" + name, self: describe(this), args: [], out: describe(answer) });
          return answer;
        },
      });
    } else if (typeof description.value === "function") {
      const original = description.value;
      wrappers.set(name, {
        configurable: true,
        enumerable: description.enumerable,
        writable: true,
        value: function (...args) {
          const self = describe(this);
          const written = args.map(serialise);
          try {
            const answer = original.apply(this, args);
            record({ op: name, self, args: written, out: describe(answer) });
            return answer;
          } catch (error) {
            record({
              op: name,
              self,
              args: written,
              out: { t: "throws", name: errorName(error) },
            });
            throw error;
          }
        },
      });
    }
  }

  const RealZoned = real.ZonedDateTime;
  function RecordingZonedDateTime(...args) {
    const self = new RealZoned(...args);
    record({ op: "new", self: null, args: args.map(describe), out: describe(self) });
    return self;
  }
  RecordingZonedDateTime.prototype = RealZoned.prototype;
  Object.setPrototypeOf(RecordingZonedDateTime, RealZoned);
  Object.defineProperty(RecordingZonedDateTime, "name", {
    value: "ZonedDateTime",
    configurable: true,
  });
  Object.defineProperty(RecordingZonedDateTime, "length", { value: 1, configurable: true });
  RecordingZonedDateTime.from = function (item, options) {
    const args = [describe(item), describe(options)];
    try {
      const answer = RealZoned.from(item, options);
      record({ op: "from", self: null, args, out: describe(answer) });
      return answer;
    } catch (error) {
      record({ op: "from", self: null, args, out: { t: "throws", name: errorName(error) } });
      throw error;
    }
  };
  Object.defineProperty(RecordingZonedDateTime.from, "length", { value: 1, configurable: true });
  RecordingZonedDateTime.compare = function (a, b) {
    const args = [describe(a), describe(b)];
    try {
      const answer = RealZoned.compare(a, b);
      record({ op: "compare", self: null, args, out: describe(answer) });
      return answer;
    } catch (error) {
      record({ op: "compare", self: null, args, out: { t: "throws", name: errorName(error) } });
      throw error;
    }
  };
  Object.defineProperty(RecordingZonedDateTime.compare, "length", { value: 2, configurable: true });

  // A case may delete or replace what it is testing — `subclass.js` and
  // `get-prototype-from-constructor-throws.js` both do — so each case starts
  // from a namespace and a prototype put back the way they were wrapped.
  // Writing our own descriptor again, rather than wrapping what is there now,
  // is what keeps a member from being recorded twice.
  return function fresh() {
    for (const [name, wrapper] of wrappers) {
      const now = Object.getOwnPropertyDescriptor(proto, name);
      if (now && now.get === wrapper.get && now.value === wrapper.value) continue;
      Object.defineProperty(proto, name, wrapper);
    }
    const namespace = {};
    for (const key of Object.getOwnPropertyNames(real)) {
      namespace[key] = key === "ZonedDateTime" ? RecordingZonedDateTime : real[key];
    }
    return namespace;
  };
}

// `describe` is `serialise` without asking a getter that would record: the
// recorder is re-entered by its own bookkeeping otherwise.
let describing = false;
function describe(value) {
  if (describing) return null;
  describing = true;
  try {
    return serialise(value);
  } finally {
    describing = false;
  }
}

// -- running one case ----------------------------------------------------------

function frontmatter(source) {
  const block = source.match(/\/\*---([\s\S]*?)---\*\//);
  if (!block) return {};
  const out = {};
  for (const line of block[1].split("\n")) {
    const entry = line.match(/^(includes|flags|features):\s*\[(.*)\]/);
    if (entry) {
      out[entry[1]] = entry[2].split(",").map((s) => s.trim()).filter(Boolean);
    }
  }
  return out;
}

function walk(directory) {
  const out = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.name.endsWith(".js")) out.push(full);
  }
  return out;
}

function main() {
  const args = {};
  for (let i = 2; i < process.argv.length; i += 2) {
    args[process.argv[i].replace(/^--/, "")] = process.argv[i + 1];
  }
  const root = args.root;
  const out = args.out;
  const harness = path.join(root, "harness");
  const suite = path.join(root, SUITE);

  // The reference is pinned like the corpus is: `temporal-polyfill` is the
  // implementation whose reading of the proposal the corpus at this commit
  // states, and a newer one would move the answers under the transcription.
  if (args.temporal) {
    const require = createRequire(path.join(args.temporal, "package.json"));
    globalThis.Temporal = require(args.temporal).Temporal;
  }

  // The harness goes into this realm once, so the corpora's own `assert` and
  // `TemporalHelpers` are the ones in force and a `TypeError` here is the one
  // the corpus compares against.
  globalThis.$262 = { global: globalThis, gc() {}, agent: {} };
  for (const include of ["assert.js", "sta.js", "temporalHelpers.js", "propertyHelper.js", "compareArray.js"]) {
    const p = path.join(harness, include);
    if (!fs.existsSync(p)) throw new Error("no harness file " + include);
    vm.runInThisContext(fs.readFileSync(p, "utf8"), { filename: include });
  }

  let sink = null;
  const fresh = buildRecorder(globalThis.Temporal, (entry) => {
    if (sink) sink(entry);
  });

  const files = walk(suite).sort();
  const kept = [];
  const left = [];
  for (const file of files) {
    const relative = path.relative(suite, file).split(path.sep).join("/");
    const source = fs.readFileSync(file, "utf8");
    const info = frontmatter(source);
    // A case is a function body rather than a script: the corpus declares
    // `const date` in a dozen files, and a body gives each its own scope.
    const records = [];
    const seen = new Set();
    sink = (entry) => {
      if (describing) return;
      const line = JSON.stringify(entry);
      if (seen.has(line)) return;
      seen.add(line);
      records.push(entry);
    };
    let failure = null;
    if (!failure) globalThis.Temporal = fresh();
    for (const include of info.includes || []) {
      const p = path.join(harness, include);
      if (!fs.existsSync(p)) {
        failure = { reason: "no harness file", detail: include };
        break;
      }
      if (["assert.js", "sta.js", "temporalHelpers.js", "propertyHelper.js", "compareArray.js"].includes(include)) continue;
      try {
        vm.runInThisContext(fs.readFileSync(p, "utf8"), { filename: include });
      } catch (error) {
        failure = { reason: "no harness file", detail: include + ": " + errorName(error) };
        break;
      }
    }
    if (!failure) {
      try {
        const body = new Function(source + "\n//# sourceURL=" + relative);
        body.call(globalThis);
      } catch (error) {
        failure = {
          reason: "the case does not pass",
          detail: errorName(error) + ": " + String(error && error.message).split("\n")[0].slice(0, 140),
        };
      }
    }
    sink = null;
    if (failure) left.push({ path: relative, reason: failure.reason, detail: failure.detail });
    else if (records.length === 0) {
      left.push({
        path: relative,
        reason: "no operation",
        detail: "the case states no value this recorder sees",
      });
    } else kept.push({ path: relative, records });
  }

  fs.writeFileSync(out, JSON.stringify({ pin: process.env.PIN || "", suite: SUITE, cases: kept, left }));
  const operations = kept.reduce((n, c) => n + c.records.length, 0);
  console.log(`cases ${files.length}, kept ${kept.length}, left ${left.length}, records ${operations}`);
  const tally = {};
  for (const entry of left) {
    const key = entry.reason + " — " + entry.detail.replace(/«[^»]*»/g, "«…»").replace(/\d+/g, "N").slice(0, 70);
    tally[key] = (tally[key] || 0) + 1;
  }
  for (const [reason, count] of Object.entries(tally).sort((a, b) => b[1] - a[1]).slice(0, 20)) {
    console.log(`  ${count}\t${reason}`);
  }
}

main();
