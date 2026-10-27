// moondate docs — shared interactions.
// Theme toggle, copy buttons, a small MoonBit highlighter that also aligns
// trailing comments, scroll reveal, and the guide's table of contents.

(function () {
  "use strict";

  const root = document.documentElement;

  // ---- theme ---------------------------------------------------------------
  const THEME_KEY = "moondate-theme";
  try {
    const saved = localStorage.getItem(THEME_KEY);
    if (saved === "dark" || saved === "light") root.setAttribute("data-theme", saved);
  } catch (e) {
    /* localStorage may be unavailable */
  }

  document.addEventListener("click", function (ev) {
    const toggle = ev.target.closest(".theme-toggle");
    if (!toggle) return;
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    try {
      localStorage.setItem(THEME_KEY, next);
    } catch (e) {
      /* ignore */
    }
  });

  // ---- copy buttons --------------------------------------------------------
  document.addEventListener("click", function (ev) {
    const btn = ev.target.closest("[data-copy]");
    if (!btn) return;
    const sel = btn.getAttribute("data-copy");
    let text = "";
    if (sel === "self") {
      const code = btn.closest(".code");
      const el = code && code.querySelector("pre code");
      text = (el && (el._raw || el.textContent)) || "";
    } else {
      const target = document.querySelector(sel);
      text = target ? target.textContent : "";
    }
    const done = () => {
      const old = btn.textContent;
      btn.textContent = "Copied";
      setTimeout(() => {
        btn.textContent = old;
      }, 1200);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text.trim()).then(done, done);
    } else {
      done();
    }
  });

  // ---- MoonBit highlighter + comment alignment ----------------------------
  const KEYWORDS = new Set([
    "pub", "fn", "let", "mut", "match", "struct", "enum", "impl", "derive",
    "if", "else", "for", "in", "while", "return", "break", "continue", "try",
    "catch", "raise", "guard", "with", "self", "true", "false", "is", "as",
    "typealias", "suberror", "extend", "trait", "where", "init", "main",
  ]);

  const esc = (s) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const span = (cls, s) => '<span class="' + cls + '">' + esc(s) + "</span>";

  function wide(cp) {
    return (
      (cp >= 0x1100 && cp <= 0x115f) ||
      (cp >= 0x2e80 && cp <= 0xa4cf) ||
      (cp >= 0xac00 && cp <= 0xd7a3) ||
      (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xfe30 && cp <= 0xfe4f) ||
      (cp >= 0xff00 && cp <= 0xff60) ||
      (cp >= 0x1f300 && cp <= 0x1faff)
    );
  }

  function displayWidth(s) {
    let w = 0;
    for (const ch of s) w += wide(ch.codePointAt(0)) ? 2 : 1;
    return w;
  }

  // Index of a trailing `//` comment that follows code, or -1.
  function trailingComment(line) {
    let inStr = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inStr) {
        if (c === "\\") { i++; continue; }
        if (c === '"') inStr = false;
        continue;
      }
      if (c === '"') { inStr = true; continue; }
      if (c === "/" && line[i + 1] === "/") {
        if (line.slice(0, i).trim().length === 0) return -1;
        return i;
      }
    }
    return -1;
  }

  function alignComments(lines) {
    const idx = lines.map(trailingComment);
    let i = 0;
    while (i < lines.length) {
      if (idx[i] > 0) {
        let j = i;
        while (j < lines.length && idx[j] > 0) j++;
        const target = Math.max(
          ...idx.slice(i, j).map((k, n) => displayWidth(lines[i + n].slice(0, k).replace(/\s+$/, "")))
        ) + 2;
        for (let k = i; k < j; k++) {
          const codePart = lines[k].slice(0, idx[k]).replace(/\s+$/, "");
          const comment = lines[k].slice(idx[k]);
          const pad = Math.max(1, target - displayWidth(codePart));
          lines[k] = codePart + " ".repeat(pad) + comment;
        }
        i = j;
      } else i++;
    }
    return lines;
  }

  function highlight(code) {
    let out = "";
    let i = 0;
    const n = code.length;
    const isWord = (c) => (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c === "_";

    while (i < n) {
      const c = code[i];
      if (c === "/" && code[i + 1] === "/") {
        let j = code.indexOf("\n", i);
        if (j < 0) j = n;
        out += span("tok-com", code.slice(i, j));
        i = j;
        continue;
      }
      if (c === '"') {
        let j = i + 1;
        while (j < n) {
          if (code[j] === "\\") { j += 2; continue; }
          if (code[j] === '"') { j++; break; }
          if (code[j] === "\n") break;
          j++;
        }
        out += span("tok-str", code.slice(i, j));
        i = j;
        continue;
      }
      if (c >= "0" && c <= "9" && !(i > 0 && isWord(code[i - 1]))) {
        let j = i;
        while (j < n && (/[0-9_]/.test(code[j]) || code[j] === "." && /[0-9]/.test(code[j + 1] || ""))) j++;
        if (code[j] === "L") j++;
        out += span("tok-num", code.slice(i, j));
        i = j;
        continue;
      }
      if (isWord(c)) {
        let j = i;
        while (j < n && isWord(code[j])) j++;
        const w = code.slice(i, j);
        if (KEYWORDS.has(w)) out += span("tok-key", w);
        else if (/^[A-Z]/.test(w)) out += span("tok-type", w);
        else out += esc(w);
        i = j;
        continue;
      }
      out += esc(c);
      i++;
    }
    return out;
  }

  function renderCode(codeEl) {
    if (codeEl.dataset.rendered === "1") return;
    const raw = codeEl.textContent.replace(/\t/g, "  ");
    codeEl._raw = raw;
    const lines = alignComments(raw.split("\n"));
    codeEl.innerHTML = highlight(lines.join("\n"));
    codeEl.dataset.rendered = "1";
  }

  document.querySelectorAll(".code pre code").forEach(renderCode);

  // ---- reveal on scroll ----------------------------------------------------
  const revealables = document.querySelectorAll(".reveal");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((en) => {
          if (en.isIntersecting) {
            en.target.classList.add("in");
            io.unobserve(en.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 }
    );
    revealables.forEach((el) => io.observe(el));
  } else {
    revealables.forEach((el) => el.classList.add("in"));
  }

  // ---- guide table of contents --------------------------------------------
  const tocLinks = Array.from(document.querySelectorAll(".toc a[href^='#']"));
  if (tocLinks.length) {
    const targets = tocLinks
      .map((a) => document.getElementById(a.getAttribute("href").slice(1)))
      .filter(Boolean);
    let ticking = false;
    const update = () => {
      const y = window.scrollY + 120;
      let current = targets[0];
      for (const t of targets) {
        if (t.offsetTop <= y) current = t;
      }
      tocLinks.forEach((a) =>
        a.classList.toggle("active", current && a.getAttribute("href") === "#" + current.id)
      );
      ticking = false;
    };
    window.addEventListener(
      "scroll",
      () => {
        if (!ticking) {
          ticking = true;
          requestAnimationFrame(update);
        }
      },
      { passive: true }
    );
    update();
  }

  // ---- weather -------------------------------------------------------------
  // Each page falls in its own season, and every load picks a variation of that
  // season: summer storms one time in five, squalls one time in twenty, spring
  // rains on its petals one time in ten or brings leaves and no blossom one
  // time in ten, winter draws a snowflake three times in ten, autumn gusts
  // three times in ten. Everything else is the plain season the markup already
  // holds, so this only ever replaces the layer with the same weather plus or
  // minus something.
  //
  // `?weather=downpour` forces a state. The rare ones are hard to catch
  // otherwise, and this is how they get looked at.

  (function weather() {
    const layer = document.querySelector(".petals");
    if (!layer) return;

    const SVG = "http://www.w3.org/2000/svg";
    const season = root.getAttribute("data-season") || "spring";
    const calm = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const rand = (a, b) => a + Math.random() * (b - a);
    const pair = (p) => rand(p[0], p[1]);

    // How many of each material, plus the storm and gust intervals. The mixes
    // are the point of the feature: spring can rain over its petals, winter can
    // turn to sleet, and the sky carries both at once.
    const MIX = {
      petals: { petal: 12 },
      "petals-rain": { petal: 9, drop: 14 },
      "petals-leaves": { petal: 8, leaf: 7 },
      "petals-leaves-rain": { petal: 7, leaf: 6, drop: 12 },
      rain: { drop: 26 },
      thunder: { drop: 26, strike: [5000, 30000] },
      // Rain driven across the page so hard it leans, with the storm behind it.
      squall: { drop: 44, blow: true, strike: [4000, 20000] },
      downpour: { drop: 64, heavy: true, dim: true, strike: [2000, 7000] },
      snow: { snow: 22 },
      crystals: { crystal: 16 },
      sleet: { snow: 14, burst: { hail: 12, gap: [2600, 6500] } },
      wind: { snow: 16, crystal: 10, blow: true },
      leaves: { leaf: 11 },
      gust: { leaf: 11, gust: [5000, 10000] },
    };

    const SHAPE = {
      petal: { w: [10, 15], drift: [26, 58], dur: [13, 21], o: [0.55, 0.7] },
      leaf: { w: [16, 22], drift: [44, 72], dur: [10, 16], o: [0.6, 0.8] },
      drop: { w: [1.4, 2], h: [18, 30], drift: [18, 40], dur: [0.7, 1.5], o: [0.45, 0.8] },
      snow: { w: [3, 7], drift: [16, 42], dur: [15, 26], o: [0.6, 0.9] },
      crystal: { w: [12, 24], drift: [20, 60], dur: [16, 30], o: [0.6, 0.9] },
      hail: { w: [5, 8], drift: [6, 18], dur: [0.75, 1.2], o: [0.6, 0.9] },
    };

    const HEAVY = { w: [2, 2.6], h: [30, 54], drift: [10, 26], dur: [0.42, 0.75], o: [0.6, 0.9] };

    // Two snowflakes, drawn once and referenced by every crystal.
    const CRYSTAL_A =
      '<path fill="currentColor" opacity=".72" d="M888.650667 639.637333a16 16 0 0 1-12.682667 18.741334l-72.117333 13.909333 17.28 64.490667a16 16 0 0 1-30.912 8.277333l-21.728-81.088a16 16 0 0 1 12.426666-19.84l88.992-17.173333a16 16 0 0 1 18.741334 12.693333zM249.728 338.346667a16 16 0 0 1-9.344 18.922666l-69.226667 28.576a16 16 0 0 1-12.213333-29.578666l56.245333-23.221334-16.426666-61.28a16 16 0 0 1 30.912-8.277333l20.053333 74.848zM817.482667 251.968a16 16 0 0 1 9.813333 20.384l-24.277333 69.333333 64.426666 17.514667a16 16 0 1 1-8.394666 30.88l-81.013334-22.037333a16 16 0 0 1-10.901333-20.725334l29.962667-85.546666a16 16 0 0 1 20.384-9.813334zM235.594667 652.48a16 16 0 0 1 11.648 17.6l-10.133334 74.197333a16 16 0 0 1-31.712-4.330666l8.245334-60.288-61.226667-16.64a16 16 0 1 1 8.405333-30.88l74.773334 20.330666zM443.754667 118.901333a16 16 0 0 1 22.570666 1.610667l48.106667 55.509333 47.210667-47.210666a16 16 0 1 1 22.624 22.634666l-59.36 59.36a16 16 0 0 1-23.402667-0.842666l-59.36-68.48a16 16 0 0 1 1.6-22.581334zM502.282667 822.869333a16 16 0 0 1 21.066666-1.365333l59.36 45.664a16 16 0 1 1-19.52 25.365333l-48.213333-37.098666-44.864 44.864a16 16 0 1 1-22.624-22.634667l54.794667-54.794667z"/>' +
      '<path fill="currentColor" d="M901.28 727.573333a21.333333 21.333333 0 0 1-29.141333 7.808L140.565333 313.013333a21.333333 21.333333 0 1 1 21.333334-36.949333l731.573333 422.368a21.333333 21.333333 0 0 1 7.808 29.141333zM864.533333 566.496a21.333333 21.333333 0 0 1-13.226666 27.114667L736 633.28l14.336 118.890667a21.333333 21.333333 0 0 1-42.368 5.098666l-16.384-136a21.333333 21.333333 0 0 1 14.24-22.72l131.594667-45.290666a21.333333 21.333333 0 0 1 27.114666 13.226666zM342.4 389.706667a21.333333 21.333333 0 0 1-12.896 22.677333l-111.210667 46.506667a21.333333 21.333333 0 1 1-16.458666-39.36l96.010666-40.16-16.362666-115.733334a21.333333 21.333333 0 1 1 42.24-5.973333l18.677333 132.053333zM899.84 285.301333a21.333333 21.333333 0 0 1-7.925333 29.109334L158.773333 734.048a21.333333 21.333333 0 0 1-21.194666-37.024L870.72 277.376a21.333333 21.333333 0 0 1 29.12 7.914667zM742.154667 235.989333a21.333333 21.333333 0 0 1 16.768 25.077334l-23.733334 119.605333 109.952 47.456a21.333333 21.333333 0 1 1-16.906666 39.168l-125.770667-54.272a21.333333 21.333333 0 0 1-12.48-23.744l27.093333-136.512a21.333333 21.333333 0 0 1 25.066667-16.778667zM326.634667 598.24A21.333333 21.333333 0 0 1 339.733333 620.8l-15.765333 119.509333a21.333333 21.333333 0 1 1-42.304-5.578666l13.621333-103.178667-108.256-44.106667a21.333333 21.333333 0 0 1 16.106667-39.509333l123.498667 50.314667zM513.6 64a21.333333 21.333333 0 0 1 21.333333 21.333333v844.746667a21.333333 21.333333 0 1 1-42.666666 0V85.333333a21.333333 21.333333 0 0 1 21.333333-21.333333zM392.469333 176.362667a21.333333 21.333333 0 0 1 30.101334-2.101334l92.010666 80 95.797334-71.84a21.333333 21.333333 0 0 1 25.6 34.133334L526.4 298.752a21.333333 21.333333 0 0 1-26.794667-0.970667l-105.024-91.328a21.333333 21.333333 0 0 1-2.101333-30.090666zM500.448 716.928a21.333333 21.333333 0 0 1 26.069333-0.170667l95.893334 73.066667a21.333333 21.333333 0 0 1-25.856 33.930667l-82.784-63.072-92.053334 72.042666a21.333333 21.333333 0 1 1-26.293333-33.6l105.024-82.197333z"/>' +
      '<path fill="currentColor" d="M388.16 295.530667a21.333333 21.333333 0 0 1 19.2-1.696l107.274667 42.912 116.181333-34.421334a21.333333 21.333333 0 0 1 27.082667 16.8l17.045333 98.026667 77.034667 72.757333a21.333333 21.333333 0 0 1-0.426667 31.413334l-81.866667 73.258666-30.378666 121.493334a21.333333 21.333333 0 0 1-29.194667 14.4L512.448 688l-106.506667 34.08a21.333333 21.333333 0 0 1-27.776-18.688l-8.309333-107.978667-100.448-62.773333a21.333333 21.333333 0 0 1-1.493333-35.157333l101.866666-76.394667 8.384-109.088a21.333333 21.333333 0 0 1 9.994667-16.48z m30.325333 48.704l-6.912 89.770666a21.333333 21.333333 0 0 1-8.469333 15.424l-84.693333 63.530667 83.2 52a21.333333 21.333333 0 0 1 9.962666 16.448l7.061334 91.818667 88.458666-28.309334a21.333333 21.333333 0 0 1 15.008 0.757334l81.92 35.626666 25.856-103.424a21.333333 21.333333 0 0 1 6.474667-10.730666l69.461333-62.144-65.312-61.696a21.333333 21.333333 0 0 1-6.378666-11.850667l-14.154667-81.418667-100.32 29.717334a21.333333 21.333333 0 0 1-13.973333-0.64l-87.189334-34.88z"/>' +
      '<path fill="currentColor" opacity=".72" d="M513.216 343.306667a16 16 0 0 1 14.517333 8.512l36.085334 68.16 85.248-8.106667a16 16 0 0 1 15.498666 23.690667l-40.928 73.664 40.256 60.373333a16 16 0 0 1-13.312 24.885333h-85.76l-36.768 77.6a16 16 0 0 1-28.938666-0.032l-32.714667-69.525333-73.290667-8.149333a16 16 0 0 1-11.552-24.768l39.744-59.626667-48.874666-73.312a16 16 0 0 1 14.901333-24.8l80.074667 8.010667 31.712-67.392a16 16 0 0 1 14.101333-9.173334z m1.216 51.786666l-22.890667 48.64a16 16 0 0 1-16.074666 9.12l-57.642667-5.76 36.021333 54.016a16 16 0 0 1 0 17.76l-31.072 46.613334 56.053334 6.229333a16 16 0 0 1 12.714666 9.088l22.101334 46.965333 26.581333-56.138666a16 16 0 0 1 14.464-9.141334h65.994667l-29.077334-43.626666a16 16 0 0 1-0.672-16.64l30.890667-55.605334-65.621333 6.24a16 16 0 0 1-15.658667-8.437333l-26.112-49.322667z"/>';

    const CRYSTAL_B =
      '<path fill="currentColor" d="M510.44352 122.88a71.68 71.68 0 0 1 20.48 140.3904v66.16064l59.67872-59.67872a20.48 20.48 0 0 1 27.66848-1.19808l1.30048 1.19808a20.48 20.48 0 0 1 1.19808 27.65824l-1.19808 1.31072-86.8864 86.8864a20.69504 20.69504 0 0 1-1.75104 1.55648v14.04928a112.5376 112.5376 0 0 1 65.19808 37.66272l12.17536-7.03488c0.11264-0.768 0.27648-1.536 0.48128-2.29376l31.7952-118.69184a20.48 20.48 0 0 1 39.56736 10.5984l-21.84192 81.5104 57.2928-33.0752a71.68 71.68 0 1 1 20.48 35.4816l-57.2928 33.0752 81.53088 21.85216a20.48 20.48 0 0 1 14.85824 23.35744l-0.37888 1.73056a20.48 20.48 0 0 1-23.35744 14.85824l-1.73056-0.37888-118.6816-31.80544a20.69504 20.69504 0 0 1-2.23232-0.72704l-12.16512 7.0144c4.17792 11.776 6.4512 24.45312 6.4512 37.65248 0 13.2096-2.27328 25.87648-6.4512 37.65248l12.16512 7.0144c0.7168-0.27648 1.46432-0.52224 2.22208-0.72704l118.69184-31.80544a20.48 20.48 0 1 1 10.60864 39.56736l-81.52064 21.84192 57.2928 33.0752a71.68 71.68 0 1 1-20.48 35.4816l-57.2928-33.08544 21.83168 81.53088a20.48 20.48 0 0 1-12.8 24.55552l-1.67936 0.53248a20.48 20.48 0 0 1-24.55552-12.8l-0.53248-1.6896-31.7952-118.6816a20.69504 20.69504 0 0 1-0.48128-2.304l-12.1856-7.03488a112.5376 112.5376 0 0 1-65.19808 37.66272v14.04928c0.6144 0.48128 1.19808 1.00352 1.76128 1.55648l86.8864 86.8864a20.48 20.48 0 1 1-28.96896 28.96896l-59.66848-59.67872v66.16064a71.68 71.68 0 1 1-40.96 0v-66.16064l-59.6992 59.67872a20.48 20.48 0 0 1-27.648 1.19808l-1.31072-1.19808a20.48 20.48 0 0 1-1.19808-27.65824l1.19808-1.31072 86.8864-86.8864c0.5632-0.55296 1.14688-1.0752 1.75104-1.55648v-14.05952a112.5376 112.5376 0 0 1-65.19808-37.65248l-12.1856 7.03488c-0.1024 0.768-0.26624 1.536-0.47104 2.29376l-31.80544 118.69184a20.48 20.48 0 0 1-39.55712-10.5984l21.84192-81.5104-57.30304 33.0752a71.68 71.68 0 1 1-20.48-35.4816l57.30304-33.0752-81.53088-21.85216a20.48 20.48 0 0 1-14.85824-23.35744l0.37888-1.73056a20.48 20.48 0 0 1 23.35744-14.85824l1.73056 0.37888 118.6816 31.80544c0.768 0.2048 1.51552 0.45056 2.23232 0.72704l12.15488-7.0144A112.45568 112.45568 0 0 1 397.80352 512c0-13.2096 2.27328-25.87648 6.4512-37.65248l-12.16512-7.0144c-0.7168 0.27648-1.46432 0.52224-2.22208 0.72704l-118.69184 31.80544a20.48 20.48 0 1 1-10.60864-39.56736l81.52064-21.84192-57.2928-33.0752a71.68 71.68 0 1 1 20.48-35.4816l57.2928 33.08544-21.83168-81.53088a20.48 20.48 0 0 1 12.8-24.55552l1.67936-0.53248a20.48 20.48 0 0 1 24.55552 12.8l0.52224 1.6896 31.80544 118.6816c0.2048 0.768 0.36864 1.536 0.48128 2.304l12.1856 7.03488a112.5376 112.5376 0 0 1 65.18784-37.65248v-14.05952a20.69504 20.69504 0 0 1-1.7408-1.55648l-86.89664-86.8864a20.48 20.48 0 1 1 28.96896-28.96896l59.66848 59.67872V263.2704a71.68 71.68 0 0 1 20.48-140.3904z"/>';

    function sprite() {
      if (document.getElementById("snow-a")) return;
      const box = document.createElement("div");
      box.setAttribute("aria-hidden", "true");
      box.style.cssText = "position:absolute;width:0;height:0;overflow:hidden";
      box.innerHTML =
        '<svg xmlns="http://www.w3.org/2000/svg">' +
        '<symbol id="snow-a" viewBox="0 0 1024 1024">' + CRYSTAL_A + "</symbol>" +
        '<symbol id="snow-b" viewBox="0 0 1024 1024">' + CRYSTAL_B + "</symbol>" +
        "</svg>";
      document.body.appendChild(box);
    }

    function make(type, index, total, shape) {
      let el;
      if (type === "crystal") {
        sprite();
        el = document.createElementNS(SVG, "svg");
        el.setAttribute("class", "flake crystal");
        const use = document.createElementNS(SVG, "use");
        use.setAttribute("href", index % 2 ? "#snow-b" : "#snow-a");
        el.appendChild(use);
      } else {
        el = document.createElement("span");
        el.className = "flake " + type;
      }
      if (shape.mark) el.classList.add(shape.mark);

      // Spread each material across the full width, jittered inside its slot so
      // two materials falling at once do not line up into columns.
      const step = 96 / total;
      const css = [
        "left:" + (2 + (index + 0.5) * step + rand(-step * 0.4, step * 0.4)).toFixed(1) + "%",
        "--w:" + Math.round(pair(shape.w)) + "px",
        "--drift:" + Math.round(pair(shape.drift)) + "px",
        "--fall-o:" + pair(shape.o).toFixed(2),
        "animation-duration:" + pair(shape.dur).toFixed(1) + "s",
        "animation-delay:-" + rand(0.5, shape.dur[1] * 0.9).toFixed(1) + "s",
      ];
      if (shape.h) css.push("--h:" + Math.round(pair(shape.h)) + "px");
      el.style.cssText = css.join(";");
      return el;
    }

    function shapeFor(type, recipe) {
      if (recipe.heavy && type === "drop") return HEAVY;
      if (!recipe.blow) return SHAPE[type];
      // Wind is the same material, thrown leftwards. Rain is shortened into a
      // sheet and quickened; snow only needs a faster, longer slide. The rain
      // also gets a class, because wind is not only where it goes but which way
      // it leans.
      if (type === "drop") {
        return Object.assign({}, SHAPE[type], {
          w: [1.6, 2.3], h: [24, 42], drift: [-260, -140], dur: [0.45, 0.8],
          mark: "blown",
        });
      }
      const fast = type === "crystal" ? [9, 16] : [7, 13];
      const left = type === "crystal" ? [-150, -70] : [-180, -90];
      return Object.assign({}, SHAPE[type], { drift: left, dur: fast });
    }

    function build(recipe) {
      layer.textContent = "";
      ["petal", "leaf", "drop", "snow", "crystal", "hail"].forEach(function (type) {
        const n = recipe[type] || 0;
        for (let i = 0; i < n; i++) {
          layer.appendChild(make(type, i, n, shapeFor(type, recipe)));
        }
      });
    }

    // A strike comes down anywhere along the top edge and lights it for a moment.
    function storm(recipe, first) {
      if (calm) return;
      const bolt = document.createElement("div");
      bolt.className = "lightning";
      // One gradient definition, shared by the channel and its fork; the colours
      // come from CSS so each theme can pick its own light.
      bolt.innerHTML =
        '<svg class="bolt" viewBox="0 0 60 220" aria-hidden="true">' +
        '<linearGradient id="bolt-grad" x1="0" y1="0" x2="0" y2="1">' +
        '<stop class="g-root" offset="0"/>' +
        '<stop class="g-mid" offset=".45"/>' +
        '<stop class="g-tip" offset="1"/>' +
        "</linearGradient>" +
        '<path class="trunk" fill="url(#bolt-grad)"/>' +
        '<path class="fork" fill="url(#bolt-grad)"/>' +
        "</svg>";
      document.body.appendChild(bolt);
      const trunkOut = bolt.querySelector(".trunk");
      const forkOut = bolt.querySelector(".fork");

      // Lightning is not a line of one width: it leaves the sky thick, thins on
      // the way down and ends in a point, and its fork does the same in
      // miniature. A stroked path can only hold one width, so the channel is
      // built as an outline instead — offsets either side of a jagged
      // centreline by a width that falls away along the length.
      const channel = (points, rootW, tipW) => {
        const n = points.length;
        const side = (sign) =>
          points.map((p, i) => {
            const a = points[Math.max(0, i - 1)];
            const b = points[Math.min(n - 1, i + 1)];
            const dx = b[0] - a[0];
            const dy = b[1] - a[1];
            const len = Math.hypot(dx, dy) || 1;
            const t = i / (n - 1);
            const w = (tipW + (rootW - tipW) * Math.pow(1 - t, 0.8)) / 2;
            return [
              (p[0] + (sign * -dy * w) / len).toFixed(1),
              (p[1] + (sign * dx * w) / len).toFixed(1),
            ];
          });
        const left = side(1);
        const right = side(-1).reverse();
        return "M" + left.concat(right).map((q) => q.join(" ")).join("L") + "Z";
      };

      // A jagged centreline from just above the top edge down, kept inside the
      // box so the glow around the whole bolt stays even.
      const zigzag = () => {
        const steps = 4 + Math.floor(Math.random() * 3);
        const step = 220 / steps;
        let x = rand(26, 38);
        const points = [[x, -4]];
        for (let i = 1; i <= steps; i++) {
          x = Math.max(10, Math.min(50, x + rand(-13, 13)));
          points.push([x, step * i]);
        }
        return points;
      };

      // One fork off the side of the trunk, at a random height, so it does not
      // read as a plain zigzag doodle.
      const branch = (points) => {
        const i = 1 + Math.floor(Math.random() * (points.length - 2));
        let [x, y] = points[i];
        const dir = Math.random() < 0.5 ? -1 : 1;
        const out = [[x, y]];
        const segs = 2 + Math.floor(Math.random() * 2);
        for (let k = 0; k < segs; k++) {
          x = Math.max(4, Math.min(56, x + dir * rand(8, 15)));
          y += rand(15, 26);
          out.push([x, y]);
        }
        return out;
      };

      if (recipe.dim) {
        const dim = document.createElement("div");
        dim.className = "storm-dim";
        document.body.appendChild(dim);
      }

      const fire = () => {
        bolt.style.setProperty("--x", rand(12, 88).toFixed(0) + "%");
        bolt.style.setProperty("--flip", Math.random() < 0.5 ? "1" : "-1");
        const points = zigzag();
        trunkOut.setAttribute("d", channel(points, 4.6, 0.35));
        forkOut.setAttribute("d", channel(branch(points), 1.8, 0.2));
        bolt.classList.remove("strike");
        void bolt.offsetWidth;
        bolt.classList.add("strike");
      };
      if (first) fire();

      const loop = () => {
        setTimeout(() => {
          fire();
          loop();
        }, pair(recipe.strike));
      };
      loop();
    }

    // A gust is a burst, not a state. It arrives one of three ways: it comes
    // through and only carries the leaves already in the air off their course,
    // or it tears a handful off the tree, or it takes a whole branch's worth and
    // throws them across the hero. The direction is the same in all three.
    function gusts(recipe) {
      if (calm) return;

      // The leaves in the air are animated on `transform`, so a shove rides on
      // the separate `translate` property: the fall carries on undisturbed and
      // the whole path is simply carried sideways, which is what wind does. The
      // offset is remembered and clamped, so a run of gusts cannot walk a leaf
      // out of the picture.
      const push = (dir, reach) => {
        const leaves = layer.querySelectorAll(".flake.leaf");
        for (let i = 0; i < leaves.length; i++) {
          const el = leaves[i];
          const next = Math.max(
            -90,
            Math.min(90, (el._shift || 0) + dir * rand(reach * 0.5, reach))
          );
          el._shift = next;
          el.style.translate = next.toFixed(0) + "px 0";
        }
      };

      const wave = (dir, count) => {
        for (let i = 0; i < count; i++) {
          const el = document.createElement("span");
          el.className = "gustleaf";
          const w = Math.round(rand(12, 18));
          // The height it enters and leaves at comes from the keyframes, so the
          // flight is corner to corner; only the reach and the timing differ,
          // which is what keeps a wave from flying in a rank.
          el.style.cssText = [
            dir > 0 ? "left:-6%" : "left:104%",
            "width:" + w + "px",
            "height:" + (w * 0.62).toFixed(0) + "px",
            "--fly:" + (dir * rand(55, 82)).toFixed(0) + "vw",
            "animation-duration:" + rand(1.5, 2.4).toFixed(1) + "s",
            "animation-delay:" + (i * rand(0.05, 0.14)).toFixed(2) + "s",
          ].join(";");
          layer.appendChild(el);
          setTimeout(() => el.remove(), 4600);
        }
      };

      const blow = () => {
        const dir = Math.random() < 0.5 ? 1 : -1;
        const roll = Math.random();
        if (roll < 0.45) {
          push(dir, 70);
        } else if (roll < 0.8) {
          wave(dir, 5 + Math.floor(Math.random() * 4));
        } else {
          wave(dir, 15 + Math.floor(Math.random() * 8));
          push(dir, 40);
        }
        setTimeout(blow, pair(recipe.gust));
      };
      setTimeout(blow, rand(1200, 3000));
    }

    // Hail does not fall as a curtain. It comes down in short, fast bursts with
    // a random silence in between, so what you hear and see is a shower passing
    // rather than sleet going on without end.
    function hailfall(recipe) {
      if (calm) return;
      const spec = recipe.burst;
      const fall = () => {
        const n = spec.hail;
        for (let i = 0; i < n; i++) {
          const el = make("hail", i, n, SHAPE.hail);
          // Each pellet is a beat behind the one before it: that is the patter.
          el.style.animationDelay = "-" + rand(0, 0.24).toFixed(2) + "s";
          layer.appendChild(el);
          setTimeout(() => el.remove(), 2000);
        }
        setTimeout(fall, pair(spec.gap));
      };
      setTimeout(fall, rand(300, 1200));
    }

    function choose() {
      const r = Math.random();
      if (season === "summer") {
        if (r < 0.05) return "downpour";
        if (r < 0.1) return "squall";
        if (r < 0.3) return "thunder";
        return "rain";
      }
      if (season === "spring") {
        if (r < 0.05) return "petals-leaves-rain";
        if (r < 0.15) return "petals-leaves";
        if (r < 0.25) return "petals-rain";
        // Not every flowering week is the same week: sometimes the blossom is
        // over and only the young leaves are still coming down.
        if (r < 0.35) return "leaves";
        return "petals";
      }
      if (season === "winter") {
        if (r < 0.05) return "sleet";
        if (r < 0.15) return "wind";
        if (r < 0.45) return "crystals";
        return "snow";
      }
      if (season === "autumn") return r < 0.3 ? "gust" : "leaves";
      return "petals";
    }

    let forced = null;
    try {
      forced = new URLSearchParams(location.search).get("weather");
    } catch (e) {
      /* older browsers, and file:// */
    }

    const key = forced && MIX[forced] ? forced : choose();
    root.setAttribute("data-weather", key);
    const recipe = MIX[key];

    build(recipe);
    if (recipe.strike) storm(recipe, Boolean(forced));
    if (recipe.gust) gusts(recipe);
    if (recipe.burst) hailfall(recipe);
  })();

})();
