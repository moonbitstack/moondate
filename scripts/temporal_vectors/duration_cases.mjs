// Answer a list of duration questions with the reference implementation and
// write down what it said.
//
//   node --no-warnings duration_cases.mjs --temporal <dir> --out duration.json
//
// The questions are the ones this library answers: a length rounded to a unit, a
// length counted in one unit, and two lengths compared. `relativeTo` is a plain
// date, which is the calendar a library with no database in it can offer; a
// length measured in a named zone is a difference between two instants, and that
// question is the ZonedDateTime transcription's.

import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  args[process.argv[i].replace(/^--/, "")] = process.argv[i + 1];
}

const require = createRequire(path.resolve(args.temporal, "package.json"));
const { Temporal } = require(path.resolve(args.temporal));

const UNITS = ["years", "months", "weeks", "days", "hours", "minutes", "seconds"];
const MODES = ["ceil", "floor", "expand", "trunc", "halfCeil", "halfFloor", "halfExpand", "halfTrunc", "halfEven"];
const STARTS = ["2024-01-01", "2024-01-31", "2024-02-29", "2023-12-31", "2024-03-09"];

// Lengths past the 292 years a count of nanoseconds reaches, which is the range
// this library used to refuse and does not: every one of them is a length the
// reference answers when the date it is measured from is inside its own range.
const LARGE = [
  { years: 200000 },
  { years: -200000 },
  { years: 200000, months: 6, days: 3 },
  { years: 271000, months: 6 },
  { days: 90000000, hours: 5 },
  { hours: 2000000000 },
  { seconds: 4000000000 },
  { years: 200000, nanoseconds: 999999999 },
  { months: 3000000, days: 17 },
];

const LENGTHS = [
  { years: 1, months: 11, days: 24 },
  { years: 2, months: 0, days: 0 },
  { years: 1, months: 6, days: 1 },
  { years: 0, months: 31, days: 0 },
  { years: 0, months: 0, weeks: 7, days: 3 },
  { years: 0, months: 0, days: 30, hours: 23 },
  { years: 0, months: 0, days: 0, hours: 23, minutes: 59, seconds: 59 },
  { years: 0, months: 0, days: 0, hours: 1, minutes: 30 },
  { years: 0, months: 0, days: 0, hours: 0, minutes: 90 },
  { years: 0, months: 0, days: 0, seconds: 90, milliseconds: 500 },
  { years: 0, months: 0, days: 0, milliseconds: 1500 },
  { years: 3, months: 6, days: 12, hours: 6 },
  { years: 0, months: 0, days: 13, hours: 11 },
  { years: 0, months: 1, days: 15 },
  { years: -1, months: -11, days: -24 },
  { years: 0, months: 0, days: -30, hours: -23 },
  { years: 0, months: 0, days: 0, hours: -1, minutes: -30 },
  { years: 1, months: 0, days: 0, hours: 0, minutes: 0, seconds: 0, nanoseconds: 1 },
];

function fields(length) {
  const out = { years: 0, months: 0, weeks: 0, days: 0, hours: 0, minutes: 0, seconds: 0, milliseconds: 0, microseconds: 0, nanoseconds: 0 };
  for (const key of Object.keys(length)) out[key] = length[key];
  return out;
}

function answer(fn) {
  try {
    return { ok: true, value: fn() };
  } catch (error) {
    return { ok: false, name: error && error.name };
  }
}

function durationOf(length) {
  return Temporal.Duration.from(fields(length));
}

const rounds = [];
for (const length of [...LENGTHS, ...LARGE]) {
  for (const unit of UNITS) {
    for (const mode of MODES) {
      for (const start of STARTS) {
        const result = answer(() => durationOf(length).round({ smallestUnit: unit, roundingMode: mode, relativeTo: start }));
        rounds.push({
          length: fields(length),
          unit,
          mode,
          start,
          ok: result.ok,
          fields: result.ok ? {
            years: result.value.years,
            months: result.value.months,
            weeks: result.value.weeks,
            days: result.value.days,
            hours: result.value.hours,
            minutes: result.value.minutes,
            seconds: result.value.seconds,
            milliseconds: result.value.milliseconds,
            microseconds: result.value.microseconds,
            nanoseconds: result.value.nanoseconds,
          } : null,
        });
      }
    }
  }
}

const totals = [];
for (const length of [...LENGTHS, ...LARGE]) {
  for (const unit of [...UNITS, "milliseconds", "microseconds", "nanoseconds"]) {
    for (const start of STARTS.slice(0, 3)) {
      const result = answer(() => durationOf(length).total({ unit, relativeTo: start }));
      totals.push({ length: fields(length), unit, start, ok: result.ok, value: result.ok ? result.value : null });
    }
  }
}

const ALL = [...LENGTHS, ...LARGE];
const compares = [];
for (let i = 0; i < ALL.length; i++) {
  for (let j = 0; j < ALL.length; j++) {
    const start = STARTS[(i + j) % STARTS.length];
    const result = answer(() => Temporal.Duration.compare(durationOf(ALL[i]), durationOf(ALL[j]), { relativeTo: start }));
    compares.push({ left: fields(ALL[i]), right: fields(ALL[j]), start, ok: result.ok, value: result.ok ? result.value : null });
  }
}

// A text read into a length, which the reference states as the fields it holds.
const texts = [
  "P1Y2M3DT4H5M6.007S", "P1W", "-P1D", "PT0S", "P0D", "-PT0.5S", "PT1.5H",
  "P1.5D", "P1Y", "P2M", "PT36H", "P1DT12H", "-P1Y2M", "PT0.000000001S",
  "P0.5W", "P1.5Y", "P1Y2M3W4DT5H6M7.00800901S",
];
const parses = texts.map((text) => {
  const result = answer(() => Temporal.Duration.from(text));
  return {
    text,
    ok: result.ok,
    fields: result.ok ? {
      years: result.value.years,
      months: result.value.months,
      weeks: result.value.weeks,
      days: result.value.days,
      hours: result.value.hours,
      minutes: result.value.minutes,
      seconds: result.value.seconds,
      milliseconds: result.value.milliseconds,
      microseconds: result.value.microseconds,
      nanoseconds: result.value.nanoseconds,
    } : null,
  };
});

// What the reference accepts as a length at all: every field is bounded at
// 2^32 - 1, and the fields have to run the same way. The answers are the range
// this library's own reader and arithmetic refuse at.
const LIMITS = [
  { years: 4294967295 },
  { years: 4294967296 },
  { years: -4294967295 },
  { years: -4294967296 },
  { seconds: 4294967295 },
  { seconds: 4294967296 },
  { nanoseconds: 4294967295 },
  { nanoseconds: 4294967296 },
  { hours: 4294967295 },
  { days: 4294967296 },
  { years: 0, months: 0, days: 0 },
];

const limits = LIMITS.map((length) => {
  const result = answer(() => Temporal.Duration.from(fields(length)));
  return {
    length: fields(length),
    ok: result.ok,
    fields: result.ok ? {
      years: result.value.years,
      months: result.value.months,
      weeks: result.value.weeks,
      days: result.value.days,
      hours: result.value.hours,
      minutes: result.value.minutes,
      seconds: result.value.seconds,
      milliseconds: result.value.milliseconds,
      microseconds: result.value.microseconds,
      nanoseconds: result.value.nanoseconds,
    } : null,
  };
});

fs.writeFileSync(args.out, JSON.stringify({ rounds, totals, compares, parses, limits }));
console.log(`rounds ${rounds.length}, totals ${totals.length}, compares ${compares.length}, parses ${parses.length}, limits ${limits.length}`);
