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
  if (!input || !out) return;

  const render = () => {
    if (!api) return unavailable(out);
    const raw = input.value;
    const canon = api.demo_parse(raw);
    if (canon.startsWith("refused")) {
      out.innerHTML = '<span class="bad">' + canon.replace(/[<>&]/g, "") + "</span>";
      return;
    }
    const shape = shapeOf(canon);
    const formatted = format && format.value ? api.demo_strftime(raw, format.value) : "";
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
    const list = api.demo_cron_list(expr.value, from ? from.value : "2026-09-22T14:30:00Z", n);
    if (!Array.isArray(list) || list[0] === undefined) {
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

// ---- boot -----------------------------------------------------------------
initParse({ key: "date", input: "demo-date", format: "demo-format", out: "demo-out" });
initCron({ key: "home", expr: "demo-cron", from: "demo-cron-from", out: "demo-cron-out", n: 4 });

initParse({ key: "p", input: "p-date", format: "p-fmt", out: "p-out" });
initCron({ key: "c", expr: "c-expr", from: "c-from", count: "c-count", out: "c-list" });
