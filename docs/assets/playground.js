// moondate docs — live playground.
// Imports the freshly compiled MoonBit module (assets/moondate.js, built by the
// docs workflow) and drives the parse/format console and the cron schedule.
// Degrades quietly when the module has not been built.

const $ = (id) => document.getElementById(id);

function shapeOf(text) {
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return "Day";
  if (/^\d{2}:\d{2}:\d{2}/.test(text)) return "Clock";
  if (/Z$|[+-]\d{2}:\d{2}$/.test(text) && text.includes("T")) return "Zoned";
  if (text.includes("T")) return "Plain";
  return "?";
}

const WD = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
function weekdayOf(iso) {
  const m = iso.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return "";
  const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], 12));
  return WD[d.getUTCDay()];
}

function padEnd(s, n) {
  return s.length >= n ? s : s + " ".repeat(n - s.length);
}

let api = null;
try {
  api = await import("./moondate.js");
} catch (e) {
  api = null;
}

function unavailable(el) {
  if (!el) return;
  el.innerHTML = '<span class="k">live module not built in this preview</span>\n' +
    '<span class="k">the deployed site compiles it from the demo package</span>';
}

// ---- parse / format console ----------------------------------------------
function initParse(cfg) {
  const input = $(cfg.input);
  const format = $(cfg.format);
  const out = $(cfg.out);
  const styleBar = cfg.style ? $(cfg.style) : null;
  if (!input || !out) return;

  // A sensible starting pattern for each style; `iso` needs none.
  const styleDefaults = {
    pct: "%A, %d %B %Y",
    layout: "Mon, 02 Jan 2006 15:04:05 MST",
    pattern: "EEEE, MMMM d, yyyy",
    iso: "",
  };
  let style = "pct";

  const render = () => {
    if (!api) return unavailable(out);
    const raw = input.value;
    const canon = api.demo_parse(raw);
    if (canon.startsWith("refused")) {
      out.innerHTML = '<span class="bad">' + canon.replace(/[<>&]/g, "") + "</span>";
      return;
    }
    const shape = shapeOf(canon);
    const fmt = format ? format.value : "";
    const formatted = style === "iso" || fmt ? api.demo_format(raw, style, fmt) : "";
    let html = "";
    html += '<span class="k">' + padEnd("shape", 8) + "</span> " + '<span class="ok">' + shape + "</span>\n";
    html += '<span class="k">' + padEnd("canon", 8) + "</span> " + canon + "\n";
    if (formatted) {
      if (formatted.startsWith("refused")) {
        html += '<span class="k">' + padEnd("format", 8) + "</span> " + '<span class="bad">' + formatted + "</span>";
      } else {
        html += '<span class="k">' + padEnd("format", 8) + "</span> " + formatted;
      }
    }
    out.innerHTML = html.replace(/\n$/, "");
  };

  input.addEventListener("input", render);
  if (format) format.addEventListener("input", render);

  document.querySelectorAll("[data-set-" + cfg.key + "]").forEach((chip) => {
    chip.addEventListener("click", () => {
      const v = chip.getAttribute("data-set-" + cfg.key);
      input.value = v;
      render();
    });
  });
  document.querySelectorAll("[data-fmt-" + cfg.key + "]").forEach((chip) => {
    chip.addEventListener("click", () => {
      if (format) format.value = chip.getAttribute("data-fmt-" + cfg.key);
      render();
    });
  });

  if (styleBar) {
    const buttons = styleBar.querySelectorAll("[data-style]");
    buttons.forEach((btn) => {
      btn.addEventListener("click", () => {
        style = btn.getAttribute("data-style");
        buttons.forEach((b) => b.setAttribute("aria-pressed", b === btn ? "true" : "false"));
        if (format) {
          if (style === "iso") {
            format.value = "";
            format.disabled = true;
            format.placeholder = "the ISO shape needs no pattern";
          } else {
            format.disabled = false;
            format.value = styleDefaults[style] || format.value;
          }
        }
        render();
      });
    });
  }

  render();
}

// ---- cron schedule --------------------------------------------------------
function initCron(cfg) {
  const expr = $(cfg.expr);
  const from = $(cfg.from);
  const count = cfg.count ? $(cfg.count) : null;
  const out = $(cfg.out);
  if (!expr || !out) return;

  const render = () => {
    if (!api) return unavailable(out);
    const n = count
      ? Math.max(1, Math.min(20, parseInt(count.value, 10) || 6))
      : cfg.n || 6;
    // The module answers with one firing per line; an empty answer is no schedule.
    const list = String(api.demo_cron_list(expr.value, from ? from.value : "2026-09-22T14:30:00Z", n))
      .split("\n")
      .filter((line) => line.length > 0);
    if (list.length === 0) {
      out.innerHTML = '<div class="empty">no schedule</div>';
      return;
    }
    if (list.length === 1 && String(list[0]).startsWith("refused")) {
      out.innerHTML = '<div class="empty">' + String(list[0]) + "</div>";
      return;
    }
    if (list.length === 1 && list[0] === "never") {
      out.innerHTML = '<div class="empty">this expression never fires</div>';
      return;
    }
    out.innerHTML = list
      .map((iso, i) => {
        const text = String(iso);
        const wd = weekdayOf(text);
        return (
          '<div class="row"><span class="i">' + String(i + 1).padStart(2, "0") + "</span>" +
          '<span class="t">' + text + "</span>" +
          (wd ? '<span class="w">' + wd + "</span>" : "") +
          "</div>"
        );
      })
      .join("");
  };

  expr.addEventListener("input", render);
  if (from) from.addEventListener("input", render);
  if (count) count.addEventListener("change", render);

  document.querySelectorAll("[data-cron-" + cfg.key + "]").forEach((chip) => {
    chip.addEventListener("click", () => {
      expr.value = chip.getAttribute("data-cron-" + cfg.key);
      render();
    });
  });

  render();
}

// ---- zones ----------------------------------------------------------------
// Six cities that between them cover whole hours, half hours and the two hours
// of the year with no single answer.
const CITIES = [
  "America/New_York",
  "Europe/London",
  "Asia/Shanghai",
  "Asia/Kathmandu",
  "Australia/Lord_Howe",
  "Pacific/Chatham",
];

function esc(text) {
  return String(text).replace(/[<>&]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]));
}

function initZoneRows(cfg) {
  const input = $(cfg.input);
  const out = $(cfg.out);
  if (!input || !out) return;

  const render = () => {
    if (!api) return unavailable(out);
    const rows = String(api.demo_zone_rows(input.value, CITIES.join("\n")))
      .split("\n")
      .filter((line) => line.length > 0);
    if (rows.length === 0) {
      out.innerHTML = '<div class="empty">no answer</div>';
      return;
    }
    if (String(rows[0]).startsWith("refused")) {
      out.innerHTML = '<div class="empty">' + esc(rows[0]) + "</div>";
      return;
    }
    out.innerHTML = rows
      .map((row) => {
        const f = String(row).split("\t");
        if (f[1] === "refused") {
          return '<div class="row"><span class="t">' + esc(f[0]) +
            '</span><span class="c">no such zone</span></div>';
        }
        const daylight = f[4] === "daylight";
        return '<div class="row' + (daylight ? " daylight" : "") + '">' +
          '<span class="i">' + esc(f[2]) + "</span>" +
          '<span class="t">' + esc(f[1]) + "</span>" +
          '<span class="c">' + esc(f[0]) + "</span>" +
          '<span class="o">' + esc(f[3]) + "</span>" +
          "</div>";
      })
      .join("");
  };

  input.addEventListener("input", render);
  document.querySelectorAll("[data-zone-at]").forEach((chip) => {
    chip.addEventListener("click", () => {
      input.value = chip.getAttribute("data-zone-at");
      render();
    });
  });
  render();
}

function initZoneRead(cfg) {
  const zone = $(cfg.zone);
  const date = $(cfg.date);
  const time = $(cfg.time);
  const out = $(cfg.out);
  if (!zone || !date || !time || !out) return;

  const render = () => {
    if (!api) return unavailable(out);
    const rows = String(api.demo_zone_read(zone.value, date.value, time.value))
      .split("\n")
      .filter((line) => line.length > 0);
    if (rows.length === 0) {
      out.innerHTML = '<div class="line"><span class="k">read</span><span class="v bad">no answer</span></div>';
      return;
    }
    out.innerHTML = rows
      .map((row) => {
        const f = String(row).split("\t");
        const label = f[0] || "";
        const value = f[1] || "";
        const note = f[2] || "";
        const bad = value.startsWith("refused");
        const shown = bad ? note : value;
        return '<div class="line"><span class="k">' + esc(label) + "</span>" +
          '<span class="v' + (bad ? " bad" : "") + '">' + esc(shown) +
          (bad || !note ? "" : ' <span class="n">' + esc(note) + "</span>") +
          "</span></div>";
      })
      .join("");
  };

  zone.addEventListener("input", render);
  date.addEventListener("input", render);
  time.addEventListener("input", render);
  document.querySelectorAll("[data-zone-case]").forEach((chip) => {
    chip.addEventListener("click", () => {
      const [z, d, t] = chip.getAttribute("data-zone-case").split("|");
      zone.value = z;
      date.value = d;
      time.value = t;
      render();
    });
  });
  render();
}

// The zone field offers every name the release knows: 598 of them, alias included.
if (api) {
  const list = $("zone-names");
  if (list) {
    list.innerHTML = String(api.demo_zone_names())
      .split("\n")
      .filter((name) => name.length > 0)
      .map((name) => '<option value="' + esc(name) + '">')
      .join("");
  }
}

// ---- boot -----------------------------------------------------------------
initParse({ key: "date", input: "demo-date", format: "demo-format", out: "demo-out" });
initCron({ key: "home", expr: "demo-cron", from: "demo-cron-from", out: "demo-cron-out", n: 4 });

initParse({ key: "p", input: "p-date", format: "p-fmt", out: "p-out", style: "p-style" });
initCron({ key: "c", expr: "c-expr", from: "c-from", count: "c-count", out: "c-list" });

initZoneRows({ input: "z-at", out: "z-rows" });
initZoneRead({ zone: "f-zone", date: "f-date", time: "f-time", out: "f-out" });
