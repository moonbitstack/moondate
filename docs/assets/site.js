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
})();
