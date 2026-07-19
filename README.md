# wispr_clone

Local, offline smart dictation for macOS. Hold **Right-Cmd**, speak English /
Mandarin / a mix, release — clean **English text** is pasted at your cursor.

Built for a MacBook Air M1 (8GB): whisper large-v3-turbo (quantized, Metal)
for speech recognition, Qwen2.5-3B via Ollama for cleanup + Chinese→English
translation, with an instant rules-only fallback mode.

## Setup

```bash
./scripts/setup.sh   # installs whisper-cpp (~15MB), whisper model (~547MB),
                     # optionally Ollama + qwen2.5:3b (~2.5GB, Smart mode only)
make run             # builds dist/WisprClone.app and opens it
```

On first run grant **Microphone** and **Accessibility** permissions
(System Settings → Privacy & Security), then relaunch.

## Use

- Hold **Right-Cmd** → speak → release. Text appears at your cursor.
- Menu-bar 🎤 → switch **Smart mode** (LLM cleanup, zh→en translation) vs
  **Rules mode** (instant, filler-stripping only, no translation).
- Menu-bar 🎤 → **Language: Auto (EN+中文)** vs **English (faster)**.
  Auto-detect costs a full extra whisper pass (~4.1s vs ~2.1s measured on M1);
  pick English if you're not dictating Mandarin.
- Smart mode falls back to rules automatically if Ollama isn't running
  (start it with `ollama serve`).
- Say "give me the following in English: {Chinese}" to dictate Chinese and
  insert the English translation.

## Notes

- Whisper model loads on first dictation (~2s) and unloads after 10 min idle.
- Insertion uses clipboard + Cmd-V; your previous clipboard **string** is
  restored ~0.3s later (images/rich content are not restored).
- Recording caps at 2 minutes per dictation. Holds under 0.3s are ignored.
- The app is signed with the "WisprClone Dev" self-signed cert (created in the
  login keychain) so Accessibility grants survive rebuilds. Without the cert it
  falls back to ad-hoc signing, where every rebuild silently invalidates the
  grant — toggle it off/on in System Settings and relaunch.

## Dev

```bash
swift test    # unit tests
make bundle   # build dist/WisprClone.app without launching
```

## v1 acceptance (2026-07-19)

Manual E2E run on the target MacBook Air M1 (8GB) — see `E2E-CHECKLIST.md`.

- All 13 items: **PASS** (setup, rules mode, smart mode incl. zh→en,
  Ollama-down fallback, clipboard restore, busy/too-short pills, quit cleanup,
  10-min idle unload verified by background watcher).
- Found & fixed during the run: stale-instance hotkey failure after rebuild
  (ad-hoc TCC invalidation → now self-signed), 2x latency from language
  auto-detect (→ language toggle).

## Future ideas (v2+)

- **Context injection** (planned next): feed frontmost-app name, surrounding
  text, and a personal dictionary into whisper + the cleanup prompt.
- Stream-draft overlay via a small whisper model while speaking; token-streamed
  overlay for Smart mode. Deferred until better hardware — both keep extra
  models resident, which fights real workloads on 8GB.
- Live correction of already-pasted text (Wispr-style): deferred indefinitely.

### Open design questions

Things I'm actively thinking about for the deferred features:

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
