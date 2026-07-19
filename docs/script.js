/* =========================================================
   Murmur site — theme, reveals, copy, hero demo loop
   ========================================================= */
(function () {
  "use strict";

  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- theme ---------- */
  var STORE_KEY = "murmur-theme";
  var toggle = document.getElementById("themeToggle");

  function applyTheme(theme) {
    root.setAttribute("data-theme", theme);
    if (toggle) toggle.setAttribute("aria-checked", String(theme === "dark"));
  }

  function initTheme() {
    var saved = null;
    try { saved = localStorage.getItem(STORE_KEY); } catch (e) {}
    if (saved === "light" || saved === "dark") {
      applyTheme(saved);
    } else {
      var prefersDark = !window.matchMedia("(prefers-color-scheme: light)").matches;
      applyTheme(prefersDark ? "dark" : "light");
    }
  }
  initTheme();

  if (toggle) {
    toggle.addEventListener("click", function () {
      var next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
      applyTheme(next);
      try { localStorage.setItem(STORE_KEY, next); } catch (e) {}
    });
  }

  /* ---------- scroll reveal ---------- */
  var reveals = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
  if (reduceMotion || !("IntersectionObserver" in window)) {
    reveals.forEach(function (el) { el.classList.add("is-in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.14, rootMargin: "0px 0px -8% 0px" });
    reveals.forEach(function (el) { io.observe(el); });
  }

  /* ---------- copy button ---------- */
  var copyBtn = document.getElementById("copyBtn");
  var INSTALL_CMD =
    "git clone https://github.com/jcoder121/murmur && cd murmur && ./scripts/setup.sh && make run";

  if (copyBtn) {
    var label = copyBtn.querySelector(".copy-btn__label");
    copyBtn.addEventListener("click", function () {
      var done = function () {
        copyBtn.classList.add("is-copied");
        if (label) label.textContent = "Copied";
        setTimeout(function () {
          copyBtn.classList.remove("is-copied");
          if (label) label.textContent = "Copy";
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(INSTALL_CMD).then(done, fallbackCopy);
      } else {
        fallbackCopy();
      }
      function fallbackCopy() {
        var ta = document.createElement("textarea");
        ta.value = INSTALL_CMD;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand("copy"); done(); } catch (e) {}
        document.body.removeChild(ta);
      }
    });
  }

  /* ---------- hero demo state machine ---------- */
  var el = {
    keycap: document.getElementById("keycap"),
    statusLabel: document.getElementById("statusLabel"),
    waveform: document.getElementById("waveform"),
    heardText: document.getElementById("heardText"),
    composerText: document.getElementById("composerText"),
    caret: document.getElementById("caret")
  };

  var RAW = "um so let's ship this uh tomorrow";
  var CLEAN = "Let's ship this tomorrow.";

  // guard: if the demo markup is absent, do nothing
  var haveDemo = el.keycap && el.statusLabel && el.composerText && el.caret;

  function wait(ms) {
    return new Promise(function (resolve) { setTimeout(resolve, ms); });
  }

  function typeInto(node, text, perChar) {
    return new Promise(function (resolve) {
      var i = 0;
      node.textContent = "";
      (function step() {
        if (i >= text.length) return resolve();
        node.textContent += text.charAt(i++);
        setTimeout(step, perChar);
      })();
    });
  }

  function reset() {
    el.keycap.classList.remove("is-held");
    el.waveform.classList.remove("is-on");
    el.statusLabel.textContent = "Ready";
    el.heardText.textContent = "";
    el.composerText.textContent = "";
  }

  function staticState() {
    // reduced-motion / no-JS-anim: show the finished transform
    el.heardText.textContent = RAW;
    el.composerText.textContent = CLEAN;
    el.statusLabel.textContent = "Done";
  }

  function runCycle() {
    return Promise.resolve()
      .then(function () {
        reset();
        return wait(900);
      })
      .then(function () {
        // press & hold
        el.keycap.classList.add("is-held");
        el.waveform.classList.add("is-on");
        el.statusLabel.textContent = "Listening";
        return wait(420);
      })
      .then(function () {
        // spoken input streams in (mono, dim)
        return typeInto(el.heardText, RAW, 46);
      })
      .then(function () { return wait(520); })
      .then(function () {
        // release
        el.keycap.classList.remove("is-held");
        el.waveform.classList.remove("is-on");
        el.statusLabel.textContent = "Cleaning up";
        return wait(760);
      })
      .then(function () {
        // written output types itself at the cursor (sans, bright)
        return typeInto(el.composerText, CLEAN, 40);
      })
      .then(function () {
        el.statusLabel.textContent = "Pasted";
        return wait(2800);
      });
  }

  function loop() {
    runCycle().then(loop);
  }

  if (haveDemo) {
    if (reduceMotion) {
      staticState();
    } else {
      // kick off once the hero is on screen (or immediately as a fallback)
      var stage = document.getElementById("demo");
      if ("IntersectionObserver" in window && stage) {
        var started = false;
        var demoIO = new IntersectionObserver(function (entries) {
          if (entries[0].isIntersecting && !started) {
            started = true;
            demoIO.disconnect();
            loop();
          }
        }, { threshold: 0.25 });
        demoIO.observe(stage);
      } else {
        loop();
      }
    }
  }
})();
