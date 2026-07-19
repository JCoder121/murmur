# Chirp

Local, offline smart dictation for macOS. Hold **Right-Cmd**, speak English /
Mandarin / a mix, release — clean **English text** is pasted at your cursor.

An open-source homage to the Wispr Flow genre of dictation tools — built
from scratch, fully local, not affiliated with Wispr. (Started life as "wispr_clone",
briefly "Murmur"; fully renamed to Chirp 2026-07-19 — bundle id
`com.jeffrey.chirp`, signing cert `Chirp Dev`.)

Built for a MacBook Air M1 (8GB): whisper large-v3-turbo (quantized, Metal)
for speech recognition, Qwen2.5-3B via Ollama for cleanup + Chinese→English
translation, with an instant rules-only fallback mode.

## Setup

```bash
./scripts/setup.sh   # installs whisper-cpp (~15MB), whisper model (~547MB),
                     # optionally Ollama + qwen2.5:3b (~2.5GB, Smart mode only)
make run             # builds dist/Chirp.app and opens it
```

On first run grant **Microphone** and **Accessibility** permissions
(System Settings → Privacy & Security), then relaunch.

## Use

- Hold **Right-Cmd** → speak → release: **Rules mode** (instant regex cleanup,
  EN only). Text appears at your cursor.
- Hold **Right-Cmd + Right-Opt** → **Smart mode** (LLM cleanup, zh→en
  translation, symbol conversion). Add Right-Opt any time during the hold —
  the menu-bar icon turns 🟣 and qwen starts loading immediately, so the
  ~7.5s cold load overlaps your speech instead of following it.
- Menu-bar 🎤 → **Language: Auto (EN+中文)** vs **English (faster)**.
  Auto-detect costs a full extra whisper pass (~4.1s vs ~2.1s measured on M1);
  pick English if you're not dictating Mandarin.
- Smart mode falls back to rules automatically if Ollama isn't running
  (start it with `ollama serve`).
- Say "give me the following in English: {Chinese}" to dictate Chinese and
  insert the English translation.
- **Personal dictionary**: put your proper nouns (project names, tools, people)
  one per line in `~/Library/Application Support/Chirp/dictionary.txt`
  (`#` comments OK). Terms bias whisper's transcription in **both modes** and
  qwen's spelling in Smart mode. Re-read on every dictation — no relaunch.
- Smart mode adapts tone to the destination app (chat apps → casual,
  terminals/editors → verbatim, everything else → prose) using the frontmost
  app name + window title captured at key-press. No field content is read.

## Notes

- Whisper model loads on first dictation (~2s) and unloads after 10 min idle.
- Insertion uses clipboard + Cmd-V; your previous clipboard **string** is
  restored ~0.3s later (images/rich content are not restored).
- Recording caps at 2 minutes per dictation. Holds under 0.3s are ignored.
- The app is signed with the "Chirp Dev" self-signed cert (created in the
  login keychain) so Accessibility grants survive rebuilds. Without the cert it
  falls back to ad-hoc signing, where every rebuild silently invalidates the
  grant — toggle it off/on in System Settings and relaunch.

## Dev

```bash
swift test    # unit tests
make bundle   # build dist/Chirp.app without launching
```

## v1 acceptance (2026-07-19)

Manual E2E run on the target MacBook Air M1 (8GB) — see `E2E-CHECKLIST.md`.

- All 13 items: **PASS** (setup, rules mode, smart mode incl. zh→en,
  Ollama-down fallback, clipboard restore, busy/too-short pills, quit cleanup,
  10-min idle unload verified by background watcher).
- Found & fixed during the run: stale-instance hotkey failure after rebuild
  (ad-hoc TCC invalidation → now self-signed), 2x latency from language
  auto-detect (→ language toggle).

## Scaling up on more RAM (e.g. 32GB+)

Chirp's current models were sized for an 8GB M1, where both are aggressively
unloaded (qwen after ~5 min via Ollama's default, whisper after 10 min). On a
bigger machine the wins come in this order:

1. **Bump the cleanup LLM — biggest quality win.** qwen2.5:3b is the weak link;
   the cleanup/translation quality (grammar, zh→en, context/tone) scales
   directly with model size. Pull a larger one and point Chirp at it via the
   `model:` arg in `OllamaCleaner.init` (default `qwen2.5:3b`):
   - 16GB → `qwen2.5:7b` (Q4 ~4.7GB)
   - 32GB → `qwen2.5:14b` (Q4 ~9GB) — sweet spot; noticeably better zh→en.
   - 32GB+ headroom → `qwen2.5:32b` (Q4 ~20GB) works but crowds real workloads.
2. **Keep models resident — kills the cold-load latency, not accuracy.** With
   spare RAM you don't need the offload dance. Set Ollama `keep_alive: -1` (or a
   long value) in the request options so qwen stays pinned, and lengthen /
   disable the 10-min whisper idle timer (`scheduleIdleUnload`, 600s). First
   dictation after idle then loads instantly instead of eating the ~7.5s cold
   load.
3. **Whisper: don't bother with a bigger model — spend the RAM on streaming.**
   large-v3-turbo is already near the accuracy ceiling; a full large-v3 is ~3x
   slower for a marginal gain. The real upgrade is the deferred **stream-draft
   overlay** below — keep a small model (base.en/small) resident for live
   drafts while large-v3-turbo finalizes. That's a latency/UX win the 8GB box
   couldn't afford, not a transcription-accuracy one.

TL;DR: upgrade **qwen** for quality, keep **both** resident for speed, and
leave the whisper *model* alone — invest that headroom in the streaming overlay.

## Future ideas (v2+)

- ~~Context injection~~ — shipped in v2 (dictionary → whisper `initial_prompt`,
  app context + tone buckets → cleanup prompt). Extend the bucket map in
  `AppContext.swift` to teach it new chat/code apps.
- Stream-draft overlay via a small whisper model while speaking; token-streamed
  overlay for Smart mode. Deferred until better hardware — both keep extra
  models resident, which fights real workloads on 8GB.
- Live correction of already-pasted text (Wispr-style): deferred indefinitely.

### Open design questions

**Stream-draft overlay** (small model drafts live, large model finalizes)
- *Stable-prefix rendering*: overlapping windows make the draft's tail
  flicker as re-decodes revise it. Only render tokens that survive N
  consecutive windows? What N trades freshness against jitter?
- *Compute budget*: total streaming cost scales ~1/step-size. What's the
  largest step that still feels "live" (~1s?), and does base.en hold
  real-time factor < 1 on an M1 under thermal throttle?
- *Draft/final reconciliation*: when large-v3-turbo disagrees with the
  displayed draft, how do you swap without a jarring rewrite? Could
  draft-vs-final token agreement (or decoder logprobs) let confident
  dictations skip the final pass entirely?
- *Resource arbitration*: the GPU is shared with real workloads (browser,
  renders). How do you detect contention and degrade — pause streaming and
  fall back to v1's batch path — without user-visible mode churn?
- *VAD gating*: skip encoding silent windows to reclaim most of the
  streaming overhead during pauses?

**Live correction of inserted text**
- *Edit anchoring*: after pasting, the user may type or move the cursor.
  How do you re-locate the inserted range for replacement — AX marked
  ranges, content diff anchors, or give up beyond an edit distance?
- *Undo semantics*: every programmatic replacement pushes onto the target
  app's undo stack. Can corrections coalesce so Cmd-Z undoes the whole
  dictation, not one correction hop?
- *AX heterogeneity*: native NSTextView, Electron, and web content expose
  wildly different AX editing capability. Capability-detect per app and
  maintain a fallback matrix, or allowlist known-good apps?
- *Concurrent-typing races*: if the user keeps typing while a correction
  lands, who wins? Abort rules vs. operational-transform-style rebasing of
  the correction against their edits.
- *Prefix-stable generation*: can the cleanup LLM be constrained to
  append-mostly output (rather than free rewrites) so corrections shrink to
  small suffix patches?
