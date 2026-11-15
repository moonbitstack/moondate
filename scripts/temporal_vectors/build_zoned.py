"""Turn the recorded test262 cases into MoonBit tables.

`collect_zoned.mjs` writes what the reference implementation did, operation by
operation; this decides which of those operations this library can be asked, and
writes the rest down under a reason. Nothing is invented: every row comes from a
record, and a record this builder cannot express is listed under its reason.

    python scripts/temporal_vectors/build_zoned.py --cases zoned.json \\
        --out src/tzdata/zoned_cases_wbtest.mbt --report exclusions.json

The tables are split into functions of a few hundred rows: a single literal of
several thousand would overflow the initialiser wasm gives a module.
"""

import argparse
import json
import sys

UNITS = {
    "year": 0, "years": 0, "month": 1, "months": 1, "week": 2, "weeks": 2,
    "day": 3, "days": 3, "hour": 4, "hours": 4, "minute": 5, "minutes": 5,
    "second": 6, "seconds": 6, "millisecond": 7, "milliseconds": 7,
    "microsecond": 8, "microseconds": 8, "nanosecond": 9, "nanoseconds": 9,
}
ROUNDING = {
    "ceil": 0, "floor": 1, "expand": 2, "trunc": 3, "halfCeil": 4,
    "halfFloor": 5, "halfExpand": 6, "halfTrunc": 7, "halfEven": 8,
}
FIELDS = ["year", "month", "day", "hour", "minute", "second", "nano"]

# Cases where this library's answer and the corpus's differ, named one by one so
# that the report says which and why rather than losing them among the reasons.
# They are differences, not gaps: the README's consistency section counts them,
# and the build refuses to run when an entry stops being reached or when one of
# them finds its way into the tables — a case cannot be both listed here and
# answered there. `prototype/until/largestunit.js`, the twin of the `since` case
# below, is not listed: it does not run under the reference at all.
DIFFERENCES = {
    "prototype/until/roundingincrement-addition-out-of-range.js":
        "a length of a hundred million days is more than a count of nanoseconds holds",
    "prototype/since/roundingincrement-addition-out-of-range.js":
        "a length of a hundred million days is more than a count of nanoseconds holds",
    "prototype/until/largestunit-plurals-accepted.js":
        "the corpus's expected value is the one a double holds, which is coarser than the instant",
    "prototype/since/largestunit-plurals-accepted.js":
        "the corpus's expected value is the one a double holds, which is coarser than the instant",
    "prototype/since/largestunit.js":
        "the corpus's expected value is the one a double holds, which is coarser than the instant",
    "prototype/withTimeZone/timezone-case-insensitive.js":
        "the name is matched whatever its case now, and Temporal writes the zone it finds as `UTC` where this library files it under the release's `Etc/UTC`",
    "prototype/withTimeZone/timezone-string-datetime.js":
        "the zone is written as a date and time, a form this library does not read as a zone",
    "prototype/withTimeZone/timezone-string-multiple-offsets.js":
        "the zone is written as a date and time, a form this library does not read as a zone",
    "prototype/equals/argument-valid.js":
        "the other value is written as a text, which this library reads before asking",
    "prototype/equals/argument-object.js":
        "the other value is a bag with an offset, a form this library does not convert",
    "prototype/with/overflow-reject-throws.js":
        "the three sub-second fields are one number here, so a field past its own range reads as a carry",
    "prototype/withTimeZone/timezone-string-leap-second.js":
        "the zone is written as a date and time with a leap second, which this library does not read as a zone",
    "prototype/with/overflow-options.js":
        "a field edit that neither fits nor refuses leaves a reading this library places differently",
}
ABSENT = -(2**63)

# The files a suite writes about the object rather than about a date: a method
# called on a receiver of the wrong brand, an argument of the wrong type, a
# property descriptor, the `length` and `name` of a function, the shape of a
# prototype. Each asserts something about the JavaScript object model, which a
# MoonBit value does not have; the reasoning is in the report, once per case.
OBJECT_MODEL_FILES = {
    "branding.js": "the method is called on a receiver of another brand",
    "prop-desc.js": "a property descriptor of the object is inspected",
    "length.js": "the `length` of a function is inspected",
    "name.js": "the `name` of a function is inspected",
    "wrong-type.js": "an argument of the wrong type is coerced",
    "prototype.js": "the shape of the prototype is inspected",
    "get-prototype-from-constructor-throws.js": "the constructor's prototype is inspected",
}


# The reasons that are about how a question is spelled rather than about a date:
# a bag where this library takes a field at a time, a text where it takes a value,
# an option where it takes a parameter. The computation behind each of them exists
# — `with_year` is what `with({year})` means, `parse` is what a text argument means
# — so these are not capabilities this library lacks, and they are counted apart
# from the ones that are.
SHAPE = {
    "the time carries an offset or a calendar":
        "a time-of-day text is the argument; this library takes a `Time`, and reads the text with `parse`",
    "a field bag in range is not refused":
        "a bag of fields; this library spells the edit as `with_year` and its siblings",
    "a field edit that neither fits nor refuses leaves a reading this library places differently":
        "a bag with an `overflow` option, which this library takes per field",
    "the zone is written as a date and time, a form this library does not read as a zone":
        "a zone written as a text; this library takes a `Tz`",
    "a zone the database has is not refused":
        "a zone written as a text; this library takes a `Tz`",
    "a time of day in range is not refused":
        "a time-of-day text is the argument; this library takes a `Time`",
    "the other value is a bag with an offset, a form this library does not convert":
        "the other value is a bag; this library takes a value",
    "a text rounds to a minute at the largest, as the reference does":
        "a text rounded to a date unit; this library's writer rounds to an hour at the largest",
    "the round is asked without a unit":
        "a round with no unit; this library's `round` takes the unit it rounds to",
    "the offset is written as text":
        "the offset is a number here and a text there",
    "the offset is written as text, which the text cases cover":
        "the offset is a number here and a text there",
    "the three sub-second fields are one number here, so a field past its own range reads as a carry":
        "the three sub-second fields are one `nanos` here, as a `Span` holds them",
    "the answer is not an instant":
        "the corpus answers with an object; this library answers the two parts of one",
    "the direction is not given":
        "a search with no direction; this library's asks for one",
}


def object_model(case):
    """Why a case is about the object and not about a date, or `None`."""
    return OBJECT_MODEL_FILES.get(case.rsplit("/", 1)[-1])

# The reasons that are about JavaScript and not about a date: the corpus asks the
# object model as much as the value — a receiver of the wrong brand, an argument
# coerced from a string or a bag, a getter on an options object read in a certain
# order, a property descriptor. A MoonBit library has no such model: the value is
# what is tested, through the typed API, and a case about the model has nothing to
# ask it. Everything else in the report is a gap in this library, counted there.
JAVASCRIPT_ONLY = {
    "the operation is about the host object, not the value":
        "the corpus calls a method the value does not have; the same computation is a function here",
    "the identifier is the value's own, not a computation":
        "`calendarId` and `timeZoneId` are strings this library writes, not readings of a value",
    "the value is not a zoned date and time":
        "the receiver is a subclass or a bag, which is a brand check on the object",
    "the other value is not a zoned date and time":
        "an argument is a bag or another type, which the corpus coerces",
    "the other value is written as a text, which this library reads before asking":
        "the argument is a text, which the corpus converts and this library's caller does",
    "the comparison converts its arguments from another shape":
        "`compare` takes anything convertible; this library's takes two values",
    "the sum passes what a JavaScript number holds exactly":
        "the reference adds in doubles; the corpus's expectation is that arithmetic",
    "the corpus's expected value is the one a double holds, which is coarser than the instant":
        "the corpus's own expected value is a double",
    "the duration is not a plain duration":
        "an argument is a duration-shaped bag, which the corpus converts",
    "the options are not a plain bag":
        "an options object built out of getters, which the corpus reads in order",
    "the field is not a number": "a field of a bag, which the corpus coerces",
    "a field is not a number": "a field of a bag, which the corpus coerces",
    "the increment is not a number": "an option, which the corpus coerces",
    "the increment is not a whole number": "an option, which the corpus coerces",
    "the digits are not a number": "an option, which the corpus coerces",
    "the digits is not a plain value": "an option, which the corpus coerces",
    "the rounding mode is not a plain value": "an option, which the corpus coerces",
    "the smallestUnit is not a plain value": "an option, which the corpus coerces",
    "the largestUnit is not a plain value": "an option, which the corpus coerces",
    "the direction is not a plain value": "an option, which the corpus coerces",
    "the offset option is not a plain value": "an option, which the corpus coerces",
    "the overflow option is not a plain value": "an option, which the corpus coerces",
    "the calendar option is not a plain value": "an option, which the corpus coerces",
    "the zone name is not a plain value": "an option, which the corpus coerces",
    "the time is not a text": "an argument, which the corpus converts",
    "the time is not a text of a time of day": "an argument, which the corpus converts",
    "the field is not a time of day": "an argument, which the corpus converts",
    "the time is not one this library has": "an argument, which the corpus converts",
    "an option is not a unit this library has": "an option, which the corpus coerces",
    "the smallestUnit is not a unit this library has": "an option, which the corpus coerces",
    "the largestUnit is not a unit this library has": "an option, which the corpus coerces",
    "the rounding mode is not one this library has": "an option, which the corpus coerces",
    "the unit is not one this library has": "an option, which the corpus coerces",
    "the direction is not one this library has": "an option, which the corpus coerces",
    "the zone name option is not one this library has": "an option, which the corpus coerces",
    "the offset option is not one this library has": "an option, which the corpus coerces",
    "the overflow option is not one this library has": "an option, which the corpus coerces",
    "the zone is not a name": "an argument, which the corpus converts",
    "the calendar option is not a plain value ": "an option, which the corpus coerces",
    "the duration has a field this library does not": "a duration-shaped bag, which the corpus converts",
    "the offset is written as text": "a reading this library writes, not computes",
    "the field bag changes the zone or the calendar":
        "an edit that changes the calendar, which is an object the corpus changes",
    "no operation — the case states no value this recorder sees":
        "the case asserts something about the object and never calls a value",
}


class Skip(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


def zoned(value):
    if value is None or value.get("t") != "zoned":
        raise Skip("the value is not a zoned date and time")
    if value.get("cal") != "iso8601":
        raise Skip("the calendar is not ISO 8601")
    return value


def stamp(value):
    entry = zoned(value)
    ns = int(entry["ns"])
    # An instant is kept as the seconds it holds and the nanoseconds after them,
    # so the whole range a zoned date and time names is a question this library
    # can be asked; only a count of nanoseconds would run out, and none is made.
    return (entry["tz"], ns // 10**9, ns % 10**9)


def text_of(value, what):
    if value is None or value.get("t") != "prim" or not isinstance(value.get("v"), str):
        raise Skip(what + " is not a text")
    return value["v"]


def bag(value):
    if value.get("t") == "undefined":
        return {}
    if value.get("t") != "object":
        raise Skip("the options are not a plain bag")
    return value["v"]


def prim(value, what):
    if value is None or value.get("t") != "prim" or "v" not in value:
        raise Skip(what + " is not a plain value")
    return value["v"]


def number(value, what):
    if value is None or value.get("t") not in ("prim", "bigint"):
        raise Skip(what + " is not a number")
    raw = value["v"]
    if isinstance(raw, bool):
        return 1 if raw else 0
    if not isinstance(raw, (int, float)):
        raise Skip(what + " is not a number")
    return int(raw)


def unit_of(options, key):
    if key not in options:
        return -1
    text = prim(options[key], "the " + key)
    if text == "auto":
        return -1
    if text not in UNITS:
        raise Skip("the " + key + " is not a unit this library has")
    return UNITS[text]


def rounding_of(options, default):
    if "roundingMode" not in options:
        return default
    text = prim(options["roundingMode"], "the rounding mode")
    if text not in ROUNDING:
        raise Skip("the rounding mode is not one this library has")
    return ROUNDING[text]


def increment_of(options):
    if "roundingIncrement" not in options:
        return 1
    value = options["roundingIncrement"]
    if value.get("t") != "prim" or "v" not in value or isinstance(value["v"], bool):
        raise Skip("the increment is not a number")
    if not isinstance(value["v"], (int, float)) or value["v"] != int(value["v"]):
        raise Skip("the increment is not a whole number")
    return int(value["v"])


def duration_of(value):
    if value.get("t") == "duration":
        return (int(value["y"]), int(value["mo"]), int(value["w"]), int(value["d"]),
                int(value["h"]), int(value["mi"]), int(value["s"]),
                int(value["ms"]) * 10**6 + int(value["us"]) * 10**3 + int(value["ns"]))
    if value.get("t") != "object":
        raise Skip("the duration is not a plain duration")
    singular = {"year": "years", "month": "months", "week": "weeks", "day": "days",
                "hour": "hours", "minute": "minutes", "second": "seconds",
                "millisecond": "milliseconds", "microsecond": "microseconds",
                "nanosecond": "nanoseconds"}
    parts = dict.fromkeys(singular.values(), 0)
    for key, entry in value["v"].items():
        key = singular.get(key, key)
        if key not in parts:
            raise Skip("the duration has a field this library does not")
        if entry.get("t") != "prim" or "v" not in entry or isinstance(entry["v"], bool):
            raise Skip("a duration field is not a number")
        parts[key] += int(entry["v"])
    return (parts["years"], parts["months"], parts["weeks"], parts["days"],
            parts["hours"], parts["minutes"], parts["seconds"],
            parts["milliseconds"] * 10**6 + parts["microseconds"] * 10**3
            + parts["nanoseconds"])


def is_throw(value):
    return value.get("t") == "throws"


def time_nanos(value):
    if value.get("t") == "time":
        return ((value["h"] * 3600 + value["mi"] * 60 + value["s"]) * 10**9
                + value["ms"] * 10**6 + value["us"] * 10**3 + value["ns"])
    if value.get("t") == "object":
        total = 0
        for key, entry in value["v"].items():
            scale = {"hour": 3_600 * 10**9, "minute": 60 * 10**9, "second": 10**9,
                     "millisecond": 10**6, "microsecond": 10**3,
                     "nanosecond": 1}.get(key)
            if scale is None:
                raise Skip("the field is not a time of day")
            if entry.get("t") != "prim":
                raise Skip("a time field is not a number")
            total += int(entry["v"]) * scale
        return total
    raise Skip("the time is not one this library has")


def flatten(row):
    out = []
    for item in row:
        if isinstance(item, tuple):
            out.extend(item)
        else:
            out.append(item)
    return out


class Tables:
    """Rows by family, each row a tuple in the order the emitter expects."""

    def __init__(self):
        self.rows = {}
        self.answered = set()
        self.seen = {}
        self.reasons = {}
        self.excluded = []
        self.differed = set()

    def add(self, family, row):
        self.answered.add(row[0])
        for item in flatten(row):
            if isinstance(item, int) and not isinstance(item, bool):
                if not -(2**63) <= item < 2**63:
                    raise Skip("the number does not fit the field this library keeps")
        key = json.dumps(row)
        if key in self.seen:
            return
        self.seen[key] = True
        self.rows.setdefault(family, []).append(row)

    def skip(self, case, op, reason):
        self.reasons[reason] = self.reasons.get(reason, 0) + 1
        self.excluded.append({"case": case, "op": op, "reason": reason})


def read(case, record, tables):
    op = record["op"]
    if case in DIFFERENCES:
        tables.differed.add(case)
        tables.skip(case, op, DIFFERENCES[case])
        return
    out = record["out"]
    me = record["self"]
    args = record["args"]
    try:
        if op.startswith("get:"):
            field(case, op[4:], me, out, tables)
        elif op in ("toString", "toJSON"):
            text(case, me, args if op == "toString" else [], out, tables)
        elif op in ("add", "subtract"):
            shift(case, me, args, out, op == "subtract", tables)
        elif op in ("until", "since"):
            diff(case, me, args, out, op == "since", tables)
        elif op == "round":
            rounding(case, me, args, out, tables)
        elif op == "equals":
            equals(case, me, args, out, tables)
        elif op == "compare":
            compare(case, args, out, tables)
        elif op == "startOfDay":
            if is_throw(out):
                raise Skip("the start of a day is not refused")
            tables.add("day", (case, stamp(me), stamp(out)))
        elif op == "hoursInDay":
            if is_throw(out):
                raise Skip("the length of a day is not refused")
            tables.add("hours", (case, stamp(me), number(out, "the hours")))
        elif op == "getTimeZoneTransition":
            transition(case, me, args, out, tables)
        elif op in ("toPlainDateTime", "toPlainDate", "toPlainTime", "toInstant",
                    "epochNanoseconds", "epochMilliseconds", "offsetNanoseconds",
                    "offset", "valueOf"):
            reading(case, me, out, op, tables)
        elif op == "with":
            fields(case, me, args, out, tables)
        elif op == "withPlainTime":
            plain_time(case, me, args, out, tables)
        elif op == "withTimeZone":
            into(case, me, args, out, tables)
        else:
            raise Skip("the operation is about the host object, not the value")
    except Skip as reason:
        tables.skip(case, op, reason.reason)


def field(case, name, me, out, tables):
    if name in ("epochNanoseconds", "timeZoneId", "calendarId", "timeZone",
                "calendar"):
        raise Skip("the identifier is the value's own, not a computation")
    if name in ("era", "eraYear"):
        # This library's calendar has no eras, and neither has the ISO calendar
        # the corpus asks about: the answer is `undefined`, which is a fact about
        # the value and not a gap. A calendar that does name eras is a table this
        # library does not carry, and those cases stay out.
        if out.get("t") != "undefined":
            raise Skip("the era of a calendar this library does not have")
        tables.add("eras", (case, *stamp(me), name))
        return
    if name == "offset":
        raise Skip("the offset is written as text, which the text cases cover")
    if out.get("t") not in ("prim", "bigint"):
        raise Skip("the field is not a number")
    if isinstance(out.get("v"), (str, bool)) or out.get("v") is None:
        if name == "monthCode" and isinstance(out.get("v"), str):
            # The month code is "M01" to "M12" in an ISO calendar, so the number
            # it names is the month, and the reading is still of this library's
            # own month field.
            code = out["v"]
            if not code.startswith("M"):
                raise Skip("the month code is not one an ISO calendar writes")
            tables.add("fields", (case, *stamp(me), name, int(code[1:])))
            return
        raise Skip("the field is not a number")
    if is_throw(out):
        raise Skip("a field is not refused")
    tables.add("fields", (case, *stamp(me), name, number(out, "the field")))


def text(case, me, args, out, tables):
    options = bag(args[0]) if args else {}
    offset = {"auto": True, "never": False}.get(
        prim(options["offset"], "the offset option") if "offset" in options else "auto")
    if offset is None:
        raise Skip("the offset option is not one this library has")
    choice = prim(options["timeZoneName"], "the zone name") if "timeZoneName" in options else "auto"
    if choice not in ("auto", "never", "critical"):
        raise Skip("the zone name option is not one this library has")
    name = choice != "never"
    critical = choice == "critical"
    if "calendarName" in options:
        if prim(options["calendarName"], "the calendar option") not in ("auto", "never"):
            raise Skip("a calendar in the text is not this library's shape")
    digits = -1
    if "fractionalSecondDigits" in options:
        raw = prim(options["fractionalSecondDigits"], "the digits")
        if raw != "auto":
            if not isinstance(raw, (int, float)) or isinstance(raw, bool):
                raise Skip("the digits are not a number")
            digits = int(raw)
    smallest = unit_of(options, "smallestUnit")
    if 0 <= smallest <= 3:
        raise Skip("a text rounds to a minute at the largest, as the reference does")
    rounding = rounding_of(options, 3)
    if is_throw(out):
        raise Skip("a text is not refused for a value in range")
    tables.add("texts", (case, stamp(me), offset, name, critical, digits, smallest,
                         rounding, prim(out, "the text")))


def shift(case, me, args, out, negate, tables):
    period = duration_of(args[0])
    # The reference keeps a duration as a JavaScript number, which is exact only
    # to 2^53: a sum past that is the reference's rounding, not a fact.
    here = stamp(me)
    total = here[1] * 10**9 + here[2] + sum(
        part * scale for part, scale in zip(
            period,
            [365 * 86400 * 10**9, 30 * 86400 * 10**9, 7 * 86400 * 10**9,
             86400 * 10**9, 3600 * 10**9, 60 * 10**9, 10**9, 1]))
    if abs(total) >= 2**53:
        raise Skip("the sum passes what a JavaScript number holds exactly")
    if is_throw(out):
        # The one refusal this library makes: a period whose fields disagree.
        mixed = any(part > 0 for part in period) and any(part < 0 for part in period)
        if not mixed:
            raise Skip("the refusal is about a value this library's types exclude")
        tables.add("refused_shifts", (case, stamp(me), negate) + period)
        return
    tables.add("shifts", (case, stamp(me), negate) + period + (stamp(out),))


def diff(case, me, args, out, since, tables):
    if not args:
        raise Skip("the other value is not given")
    other = stamp(args[0])
    options = bag(args[1]) if len(args) > 1 else {}
    largest = unit_of(options, "largestUnit")
    smallest = unit_of(options, "smallestUnit")
    rounding = rounding_of(options, 3)
    increment = increment_of(options)
    if is_throw(out):
        if refused_by_us(largest, smallest, increment):
            # A difference whose step or whose units this library refuses too:
            # the corpus says it must throw and this says why.
            tables.add("refused_diffs", (case, stamp(me), other, since, largest,
                                          smallest, rounding, increment))
            return
        raise Skip("a difference in range is not refused")
    if out.get("t") != "duration":
        raise Skip("the answer is not a duration")
    want = (int(out["y"]), int(out["mo"]), int(out["w"]), int(out["d"]),
            int(out["h"]), int(out["mi"]), int(out["s"]),
            int(out["ms"]) * 10**6 + int(out["us"]) * 10**3 + int(out["ns"]))
    tables.add("diffs", (case, stamp(me), other, since, largest, smallest,
                         rounding, increment, want))


def refused_by_us(largest, smallest, increment):
    """Whether this library refuses the step or the units a difference asks for."""
    # The increment is checked whether or not a smallest unit is given, and a
    # count of steps runs from one to a thousand million.
    if increment < 1 or increment > 10**9:
        return True
    if smallest < 0:
        return False
    # `UNITS` counts from the year down, so a smallest unit above the largest is
    # the one with the smaller number.
    if largest >= 0 and smallest < largest:
        return True
    return not step_taken(smallest, increment)


def step_taken(unit, increment):
    """Whether this library rounds by that step, which decides who refuses what."""
    if unit >= 7:
        return False
    if unit == 3:
        return increment == 1
    limit = 24 if unit == 4 else (60 if unit in (5, 6) else 1000)
    return increment < limit and limit % increment == 0


def rounding(case, me, args, out, tables):
    options = {}
    if args:
        if args[0].get("t") == "object":
            options = args[0]["v"]
        elif args[0].get("t") == "prim":
            if prim(args[0], "the unit") not in UNITS:
                raise Skip("the unit is not one this library has")
            options = {"smallestUnit": args[0]}
        elif args[0].get("t") != "undefined":
            raise Skip("the options are not a plain bag")
    smallest = unit_of(options, "smallestUnit")
    rounding_mode = rounding_of(options, 6)
    increment = increment_of(options)
    if smallest < 0:
        raise Skip("the round is asked without a unit")
    if is_throw(out):
        if step_taken(smallest, increment):
            # The step is one this library takes, so the refusal is about the
            # instant: the reference bounds one at a hundred million days and this
            # library's values run further, which the README says.
            raise Skip("the reference refuses a round this library answers, its instants being bounded and ours not")
        # A round this library refuses: the increment is not one it accepts, or
        # the value cannot be placed. Recorded as a refusal to be checked.
        tables.add("refused_rounds", (case, stamp(me), smallest, rounding_mode,
                                      increment))
        return
    tables.add("rounds", (case, stamp(me), smallest, rounding_mode, increment,
                          stamp(out)))


def equals(case, me, args, out, tables):
    if not args or args[0].get("t") != "zoned":
        raise Skip("the other value is not a zoned date and time")
    if is_throw(out):
        raise Skip("an equality is not refused")
    tables.add("equals", (case, stamp(me), stamp(args[0]), bool(prim(out, "the answer"))))


def compare(case, args, out, tables):
    if len(args) != 2:
        raise Skip("the comparison does not have two values")
    if any(arg.get("t") != "zoned" for arg in args):
        raise Skip("the comparison converts its arguments from another shape")
    if is_throw(out):
        raise Skip("a comparison of two values is not refused")
    tables.add("compares", (case, stamp(args[0]), stamp(args[1]),
                            number(out, "the answer")))


def transition(case, me, args, out, tables):
    if not args:
        raise Skip("the direction is not given")
    entry = args[0]
    if entry.get("t") == "object":
        options = entry["v"]
        if "direction" not in options:
            raise Skip("the direction is not given")
        entry = options["direction"]
    direction = prim(entry, "the direction")
    if direction not in ("next", "previous"):
        raise Skip("the direction is not one this library has")
    if is_throw(out):
        raise Skip("a search is not refused")
    found = out.get("t") == "zoned"
    tables.add("transitions", (case, stamp(me), direction == "next", found,
                               stamp(out) if found else ("", 0, 0)))


def reading(case, me, out, op, tables):
    if is_throw(out):
        raise Skip("a reading is not refused")
    here = stamp(me)
    if op == "toPlainDateTime":
        tables.add("dates", (case, here, (
            int(out["y"]), int(out["mo"]), int(out["d"]), int(out["h"]),
            int(out["mi"]), int(out["s"]),
            int(out["ms"]) * 10**6 + int(out["us"]) * 10**3 + int(out["ns"]))))
    elif op == "toPlainDate":
        tables.add("plaindates", (case, here,
                                  (int(out["y"]), int(out["mo"]), int(out["d"]))))
    elif op == "toPlainTime":
        tables.add("times", (case, here, (
            int(out["h"]), int(out["mi"]), int(out["s"]),
            int(out["ms"]) * 10**6 + int(out["us"]) * 10**3 + int(out["ns"]))))
    elif op in ("toInstant", "epochNanoseconds", "valueOf"):
        if out.get("t") != "bigint":
            raise Skip("the answer is not an instant")
        tables.add("instants", (case, here, int(out["v"])))
    elif op == "epochMilliseconds":
        tables.add("millis", (case, here, number(out, "the milliseconds")))
    elif op == "offsetNanoseconds":
        tables.add("offsets", (case, here, number(out, "the offset")))
    elif op == "offset":
        raise Skip("the offset is written as text")
    else:
        raise Skip("the operation is not a reading this library has")


def fields(case, me, args, out, tables):
    if not args:
        raise Skip("the fields are not given")
    options = bag(args[0])
    values = [ABSENT] * 7
    here = stamp(me)[2]
    sub = {}
    for key, entry in options.items():
        if key in ("calendar", "timeZone"):
            raise Skip("the field bag changes the zone or the calendar")
        if key == "monthCode":
            code = prim(entry, "the month code")
            if not (isinstance(code, str) and code.startswith("M")):
                raise Skip("the month code is not one an ISO calendar writes")
            values[1] = int(code[1:])
            continue
        if key in ("millisecond", "microsecond", "nanosecond"):
            if entry.get("t") != "prim" or "v" not in entry:
                raise Skip("a field is not a number")
            scale = {"millisecond": 10**6, "microsecond": 10**3, "nanosecond": 1}[key]
            if not isinstance(entry["v"], (int, float)) or isinstance(entry["v"], bool):
                raise Skip("a field is not a number")
            # A sub-second field replaces its own digits and leaves the finer
            # ones alone, so what is written is the reading with those digits
            # swapped, not a number of nanoseconds from zero.
            sub[key] = int(entry["v"])
            continue
        if key not in FIELDS:
            raise Skip("the field is not one an ISO calendar has")
        values[FIELDS.index(key)] = number(entry, "the field")
    if sub:
        # The three digits of each field named, and the digits around them as the
        # reading already has them.
        values[6] = here
        for key, value in sub.items():
            scale = {"millisecond": 10**6, "microsecond": 10**3, "nanosecond": 1}[key]
            values[6] = values[6] - values[6] % (scale * 1000) + value * scale + values[6] % scale
    strict = False
    if len(args) > 1 and args[1].get("t") == "object":
        more = args[1]["v"]
        if "overflow" in more:
            choice = prim(more["overflow"], "the overflow option")
            if choice == "reject":
                strict = True
            elif choice != "constrain":
                raise Skip("the overflow option is not one this library has")
    if is_throw(out):
        if not strict:
            raise Skip("a field bag in range is not refused")
        tables.add("refused_edits", (case, stamp(me), tuple(values)))
        return
    tables.add("edits", (case, stamp(me), tuple(values), strict, stamp(out)))


def clock_text(text):
    """A time of day as nanoseconds, from the ISO forms a text can be."""
    if "[" in text or "Z" in text or "+" in text or "-" in text:
        raise Skip("the time carries an offset or a calendar")
    if text.startswith("T") or text.startswith("t"):
        text = text[1:]
    parts = text.split(":")
    try:
        int(parts[0]) if False else None
    except ValueError:
        raise Skip("the time is not a text of a time of day")
    if len(parts) < 2 or len(parts) > 3:
        raise Skip("the time is not a text of a time of day")
    hours, minutes = int(parts[0]), int(parts[1])
    seconds, nanos = 0, 0
    if len(parts) == 3:
        whole = parts[2].split(".")
        seconds = int(whole[0])
        if len(whole) == 2:
            digits = (whole[1] + "000000000")[:9]
            nanos = int(digits)
    return ((hours * 3600 + minutes * 60 + seconds) * 10**9) + nanos


def plain_time(case, me, args, out, tables):
    entries = args[0] if args else {"t": "undefined"}
    if entries.get("t") == "undefined":
        at = 0
    elif entries.get("t") == "prim":
        at = clock_text(text_of(entries, "the time"))
    else:
        at = time_nanos(entries)
    if is_throw(out):
        raise Skip("a time of day in range is not refused")
    tables.add("timesets", (case, stamp(me), at, stamp(out)))


def canonical_zone(name):
    """The name a zone is filed under, from the spellings a text may use."""
    if name in ("UTC", "Etc/UTC", "Etc/GMT", "Z", "z", "+00:00", "-00:00",
                "+0000", "-0000", "+00", "-00"):
        return "UTC"
    if len(name) == 5 and name[0] in "+-":
        return name[:3] + ":" + name[3:]
    if len(name) == 6 and name[3] == ":" and name[0] in "+-":
        return name
    # A zone is named whatever its case, which the database's own lookup folds.
    return name


def into(case, me, args, out, tables):
    if not args or args[0].get("t") != "prim":
        raise Skip("the zone is not a name")
    if is_throw(out):
        raise Skip("a zone the database has is not refused")
    tables.add("zones", (case, stamp(me), canonical_zone(prim(args[0], "the zone")), stamp(out)))


# -- writing the MoonBit -------------------------------------------------------

STRUCTS = {
    "fields": ("FieldCase", "case : String; zone : String; epoch : Int64; nano : Int32; name : String; want : Int64"),
    "texts": ("TextCase", "case : String; zone : String; epoch : Int64; nano : Int32; offset : Bool; name : Bool; critical : Bool; digits : Int32; smallest : Int32; rounding : Int32; want : String"),
    "shifts": ("ShiftCase", "case : String; zone : String; epoch : Int64; nano : Int32; negate : Bool; years : Int64; months : Int64; weeks : Int64; days : Int64; hours : Int64; minutes : Int64; seconds : Int64; nanos : Int64; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "diffs": ("DiffCase", "case : String; zone : String; epoch : Int64; nano : Int32; other_zone : String; other_epoch : Int64; other_nano : Int32; since : Bool; largest : Int32; smallest : Int32; rounding : Int32; increment : Int64; years : Int64; months : Int64; weeks : Int64; days : Int64; hours : Int64; minutes : Int64; seconds : Int64; nanos : Int64"),
    "rounds": ("RoundCase", "case : String; zone : String; epoch : Int64; nano : Int32; smallest : Int32; rounding : Int32; increment : Int64; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "refused_rounds": ("RefusedRound", "case : String; zone : String; epoch : Int64; nano : Int32; smallest : Int32; rounding : Int32; increment : Int64"),
    "refused_edits": ("RefusedEdit", "case : String; zone : String; epoch : Int64; nano : Int32; year : Int64; month : Int64; day : Int64; hour : Int64; minute : Int64; second : Int64; nano_field : Int64"),
    "equals": ("EqualCase", "case : String; zone : String; epoch : Int64; nano : Int32; other_zone : String; other_epoch : Int64; other_nano : Int32; want : Bool"),
    "compares": ("CompareCase", "case : String; left_zone : String; left_epoch : Int64; left_nano : Int32; right_zone : String; right_epoch : Int64; right_nano : Int32; want : Int32"),
    "day": ("DayCase", "case : String; zone : String; epoch : Int64; nano : Int32; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "transitions": ("TransitionCase", "case : String; zone : String; epoch : Int64; nano : Int32; next : Bool; found : Bool; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "dates": ("DateCase", "case : String; zone : String; epoch : Int64; nano : Int32; year : Int32; month : Int32; day : Int32; hour : Int32; minute : Int32; second : Int32; nanos : Int64"),
    "plaindates": ("PlainDateCase", "case : String; zone : String; epoch : Int64; nano : Int32; year : Int32; month : Int32; day : Int32"),
    "times": ("TimeCase", "case : String; zone : String; epoch : Int64; nano : Int32; hour : Int32; minute : Int32; second : Int32; nanos : Int64"),
    "edits": ("EditCase", "case : String; zone : String; epoch : Int64; nano : Int32; year : Int64; month : Int64; day : Int64; hour : Int64; minute : Int64; second : Int64; nano_field : Int64; strict : Bool; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "timesets": ("TimeSetNanos", "case : String; zone : String; epoch : Int64; nano : Int32; at : Int64; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "zones": ("ZoneCase", "case : String; zone : String; epoch : Int64; nano : Int32; into_zone : String; want_zone : String; want_epoch : Int64; want_nano : Int32"),
    "eras": ("EraCase", "case : String; zone : String; epoch : Int64; nano : Int32; name : String"),
    "refused_diffs": ("RefusedDiff", "case : String; zone : String; epoch : Int64; nano : Int32; other_zone : String; other_epoch : Int64; other_nano : Int32; since : Bool; largest : Int32; smallest : Int32; rounding : Int32; increment : Int64"),
}

def lit(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        if -(2**31) <= value < 2**31:
            return str(value)
        return str(value) + "L"
    if isinstance(value, str):
        return json.dumps(value)
    raise ValueError(value)


def value_text(value, kind):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    if kind == "Int64":
        return str(int(value)) + "L"
    return str(int(value))


def render(family, rows):
    name, layout = STRUCTS[family]
    fields = [part.split(":") for part in layout.split(";")]
    fields = [(part[0].strip(), part[1].strip()) for part in fields]
    lines = []
    for row in rows:
        flat = []
        for item in row:
            if isinstance(item, tuple):
                flat.extend(item)
            else:
                flat.append(item)
        if len(flat) != len(fields):
            raise SystemExit("%s: %d values for %d fields" % (family, len(flat), len(fields)))
        pieces = []
        for (name_, kind), item in zip(fields, flat):
            pieces.append("%s: %s" % (name_, value_text(item, kind)))
        lines.append("  { " + ", ".join(pieces) + " },")
    return "\n".join(lines)


def emit(tables, pin, out_path):
    # The rows are sorted so that the file depends on what the corpus states and
    # not on the order a particular engine happened to hand the operations over.
    for family, rows in tables.rows.items():
        rows.sort(key=lambda row: json.dumps(row))
    total = sum(len(rows) for rows in tables.rows.values())
    chunks = ["""// Generated by scripts/temporal_vectors/build_zoned.py from test262 at %s,
// DON'T EDIT IT. Run the scripts in scripts/temporal_vectors/ to make it again.
//
// %d rows, each one operation the corpus states and this library answers. The
// cases the builder could not express are counted by reason in the script's
// report and listed one by one beside it.

""" % (pin, total)]
    for family, (name, layout) in STRUCTS.items():
        if not tables.rows.get(family):
            continue
        chunks.append("///|\nstruct %s {\n" % name)
        for part in layout.split(";"):
            chunks.append("  %s\n" % part.strip())
        chunks.append("}\n\n")
    for family, (name, _) in STRUCTS.items():
        rows = tables.rows.get(family, [])
        if not rows:
            continue
        limit = 250
        pieces = [rows[i:i + limit] for i in range(0, len(rows), limit)]
        for index, piece in enumerate(pieces, start=1):
            chunks.append("///|\nfn %s_part_%d(out : Array[%s]) -> Unit {\n" % (family, index, name))
            for line in render(family, piece).split("\n"):
                chunks.append("  out.push(%s)\n" % line.strip().rstrip(","))
            chunks.append("}\n\n")
        chunks.append("///|\nfn %s_all() -> Array[%s] {\n  let out : Array[%s] = []\n" % (family, name, name))
        for index in range(1, len(pieces) + 1):
            chunks.append("  %s_part_%d(out)\n" % (family, index))
        chunks.append("  out\n}\n\n")
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("".join(chunks))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--report", default=None)
    parser.add_argument("--pin", default="")
    args = parser.parse_args()

    data = json.load(open(args.cases, encoding="utf-8"))
    tables = Tables()
    cases = 0
    for entry in data["cases"]:
        for record in entry["records"]:
            cases += 1
            read(entry["path"], record, tables)
    operations = sum(len(entry["records"]) for entry in data["cases"])
    for entry in data["left"]:
        tables.skip(entry["path"], "-", entry["reason"] + " — " + entry["detail"])

    # The one case where a difference is written down and the case still answers:
    # a case listed in DIFFERENCES that reached the tables would be a case this
    # library gets wrong while the report says it is not put, so the build stops.
    answered_anyway = sorted(tables.differed & tables.answered)
    if answered_anyway:
        raise SystemExit("a difference in the tables: " + ", ".join(answered_anyway))
    # And the other way: an entry the corpus never reaches says nothing about a
    # case, and would inflate the count the README quotes.
    never_reached = sorted(set(DIFFERENCES) - tables.differed)
    if never_reached:
        raise SystemExit("a difference never reached: " + ", ".join(never_reached))

    emit(tables, data.get("pin") or args.pin, args.out)
    total = sum(len(rows) for rows in tables.rows.values())
    print(
        "records read: %d, rows written: %d, cases answered: %d"
        % (cases, total, len(tables.answered))
    )
    for family, rows in sorted(tables.rows.items(), key=lambda pair: -len(pair[1])):
        print("  %5d\t%s" % (len(rows), family))
    print("left out, by reason:")
    for reason, count in sorted(tables.reasons.items(), key=lambda pair: -pair[1]):
        print("  %5d\t%s" % (count, reason))
    if args.report:
        # One line per case and reason, so that the file says which cases are not
        # answered and why rather than repeating itself once per operation.
        # Two reasons say nothing about a case in particular: an operation about
        # the host object and a read of the value's own identifier. They are in
        # the totals, not in the list: what a reader asks is why a case is left
        # out, and those two are why an operation is.
        general = {
            "the operation is about the host object, not the value",
            "the identifier is the value's own, not a computation",
        }
        counted = {}
        # Each operation left out is counted once, under the reason it was left
        # out for; whether that reason is about the object or about a date is
        # decided here, so the two figures in the README can be added up from the
        # file instead of from a run.
        # A reason that is the why of a difference is counted as one, not as a gap:
        # the cases the builder names under `DIFFERENCES`, and the rounds the
        # reference refuses because its own instants stop where this library's do
        # not.
        difference_reasons = set(DIFFERENCES.values()) | {
            "the reference refuses a round this library answers, its instants being bounded and ours not"
        }
        javascript = {}
        shape = {}
        difference = {}
        library = {}
        for entry in tables.excluded:
            if entry["reason"] in general:
                continue
            reasons, count = counted.get(entry["case"], (set(), 0))
            reasons.add(entry["reason"])
            counted[entry["case"]] = (reasons, count + 1)
            about_the_object = (
                entry["reason"] in JAVASCRIPT_ONLY
                or entry["reason"].startswith("the case does not pass")
                or object_model(entry["case"]) is not None
            )
            if about_the_object:
                why = JAVASCRIPT_ONLY.get(
                    entry["reason"], object_model(entry["case"]) or "the object model"
                )
                slot = javascript.get(entry["reason"], {"operations": 0, "why": why})
                slot["operations"] = slot["operations"] + 1
                javascript[entry["reason"]] = slot
            elif entry["reason"] in difference_reasons:
                difference[entry["reason"]] = difference.get(entry["reason"], 0) + 1
            elif entry["reason"] in SHAPE:
                slot = shape.get(
                    entry["reason"],
                    {"operations": 0, "why": SHAPE[entry["reason"]]},
                )
                slot["operations"] = slot["operations"] + 1
                shape[entry["reason"]] = slot
            else:
                library[entry["reason"]] = library.get(entry["reason"], 0) + 1
        for reason in general:
            # The two reasons that say nothing about a case in particular are in
            # the totals, not in the list, so their operations are counted from
            # the reasons rather than from the cases.
            count = tables.reasons.get(reason, 0)
            if count:
                javascript[reason] = {"operations": count, "why": "not a computation of a value"}
        lines = [
            {"case": case, "reasons": sorted(reasons), "operations": count}
            for case, (reasons, count) in sorted(counted.items())
        ]
        # Every case is either asked, or named with a reason, or both — and a case
        # that is neither states nothing this transcription could reach. The four
        # counts are written down so that a figure in the README can be checked
        # against this file rather than against a run.
        listed = set(counted)
        rows_cases = set(tables.answered)
        total_cases = len(data["cases"]) + len(data["left"])
        accounted = {
            "cases": total_cases,
            "with_rows": len(rows_cases),
            "with_reason": len(listed),
            "both": len(rows_cases & listed),
            "neither": total_cases - len(rows_cases | listed),
        }
        with open(args.report, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(
                {
                    "pin": args.pin,
                    # What the corpus states, so that a number in the README can
                    # be checked against this file instead of against a run.
                    "corpus": {
                        "cases": len(data["cases"]) + len(data["left"]),
                        "run": len(data["cases"]),
                        "operations": operations,
                    },
                    "answered": {"rows": total, "cases": len(tables.answered)},
                    "accounted": accounted,
                    "differences": {
                        case: DIFFERENCES[case] for case in sorted(tables.differed)
                    },
                    "counts": dict(sorted(tables.reasons.items())),
                    "javascript_only": {
                        reason: slot
                        for reason, slot in sorted(javascript.items())
                    },
                    "shape": {
                        reason: slot for reason, slot in sorted(shape.items())
                    },
                    "difference": {
                        reason: count for reason, count in sorted(difference.items())
                    },
                    "library": {
                        reason: count for reason, count in sorted(library.items())
                    },
                    "cases": lines,
                },
                handle,
                indent=1,
            )
            handle.write("\n")


if __name__ == "__main__":
    main()
