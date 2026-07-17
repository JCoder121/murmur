# wispr_clone — Design Spec

**Date:** 2026-07-17
**Status:** Approved by user (interview + design review in Claude Code session)

## Purpose

A local, offline "smart dictation" app for macOS (MacBook Air M1 2020, 8GB RAM, macOS 26.3, ~18GB free disk). Hold a hotkey, speak English / Mandarin / a mix, release — clean **English text** appears at the cursor of whatever app has focus. Nothing else: no app awareness, no assistant features, no Chinese text output.

## Core user flows

1. **Pure English → English**: filler words removed, punctuation fixed, light cleanup (not 100% raw STT).
2. **EN + ZH mixed → English**: e.g. user says "give me the following in English: {Chinese phrase}" — output is fully English.
3. **Chinese → English always**: any Chinese speech is translated; Chinese characters are never inserted.

## Decisions (from user interview)

| Decision | Choice |
|---|---|
| Codebase | Fresh native Swift menu-bar app (SwiftPM + Makefile, **no Xcode** — CLT only, Swift 6.0.3) |
| ASR | whisper.cpp (Metal) with **large-v3-turbo q5_0** (~600MB disk, ~1GB RAM loaded) |
| Smart layer | Menu-bar toggle: **Smart mode** (Qwen2.5-3B via Ollama) vs **Rules mode** (regex + whisper punctuation) |
| Hotkey | **Hold Right-Cmd** to talk, release to insert. Configurable later; holds <~0.3s ignored |
| Mode fallback | Smart mode silently falls back to Rules mode (with menu-bar warning) if Ollama is down/times out |
| Model RAM policy | Load whisper on first use; auto-unload after 10 min idle |
| Feedback UI | Small floating pill (bottom of screen): waveform while recording, spinner while processing; menu-bar icon mirrors state |
| Insertion | Save clipboard → set pasteboard → synthesize Cmd-V (CGEvent) → restore clipboard after ~300ms |
| V1 extras | None (no history, custom vocab, launch-at-login, streaming preview) |

## Architecture

Menu-bar app, single SwiftPM executable target. Pipeline per dictation:

```
Right-Cmd down ──► Recorder (AVAudioEngine, 16kHz mono PCM)
Right-Cmd up  ──► Transcriber (whisper.cpp large-v3-turbo, lang autodetect)
              ──► SmartCleaner (Smart: Ollama/Qwen prompt | Rules: regex)
              ──► Inserter (pasteboard + Cmd-V, clipboard restore)
```

### Components (`Sources/WisprClone/`)

- **App.swift** — NSApplication bootstrap, menu bar item (NSStatusItem), mode toggle, permissions onboarding (Accessibility + Microphone).
- **HotkeyMonitor.swift** — CGEventTap on `flagsChanged` for Right-Cmd (keycode 54). Emits `startRecording` / `stopRecording`. Re-enables tap if system disables it. Ignores holds < 0.3s.
- **Recorder.swift** — AVAudioEngine input tap → 16kHz mono Float32 buffer. Hard cap ~2 min per dictation.
- **Transcriber (WhisperServer.swift)** — manages a `whisper-server` child process (installed via `brew install whisper-cpp`): spawn with the turbo model on first use (lazy load), POST recorded WAV to `http://127.0.0.1:8642/inference`, terminate after 10 min idle (idle-unload). Language autodetect (`--language auto`). Rationale vs. embedding the whisper.cpp C API: no C++/Metal compilation on a CLT-only machine, same warm-model behavior, plain HTTP from Swift.
- **SmartCleaner.swift** — protocol `Cleaner` with two impls:
  - `LLMCleaner`: POST to `http://localhost:11434/api/chat` (Ollama, `qwen2.5:3b`), fixed system prompt: remove fillers, fix punctuation/casing, translate any Chinese to English, honor spoken meta-commands ("give me the following in English:"), output cleaned English text only — no commentary. Timeout ~10s → fallback.
  - `RuleCleaner`: regex strip of fillers (um, uh, like, you know…), whitespace/punctuation tidy. Chinese passes through untranslated (documented limitation of Rules mode).
- **Inserter.swift** — NSPasteboard save/set/restore + CGEvent Cmd-V synthesis.
- **Overlay.swift** — borderless floating NSPanel pill: recording waveform (input level), processing spinner, auto-hide.
- **Settings.swift** — UserDefaults-backed: mode (smart/rules), model paths, hotkey keycode (v1: constant, but stored for future configurability).

### Repo layout

```
wispr_clone/
  Package.swift
  Makefile              # build, codesign (ad-hoc + entitlements), install to /Applications, run
  Sources/WisprClone/   # components above
  scripts/setup.sh      # download whisper model (~600MB), install Ollama + pull qwen2.5:3b (~2.5GB); prints disk cost & prompts before each download
  docs/superpowers/specs/
```

## Error handling

- **No Accessibility/Mic permission** → menu-bar alert with step-by-step System Settings instructions; app stays alive.
- **Ollama down/timeout in Smart mode** → use RuleCleaner result, flash menu-bar warning icon.
- **whisper model file missing** → menu-bar error pointing at `scripts/setup.sh`.
- **Empty/too-short audio** → discard silently (no paste).
- **Event tap disabled by system** (timeout under load) → auto re-enable.
- **Clipboard restore** — always restore prior contents even if paste fails.

## Resource budget

- Disk: whisper turbo q5_0 ~600MB + Ollama app ~0.5GB + qwen2.5:3b q4 ~1.9GB ≈ **~3.2GB** (18GB free — OK).
- RAM: idle ≈ app only (<100MB); dictating ≈ +1GB whisper; smart mode ≈ +~2.5GB Ollama while resident. 8GB M1: acceptable; whisper idle-unload keeps steady-state low.
- Latency target: release → text ≈ 1–3s (rules mode), 2–5s (smart mode; first call after idle slower).

## Known risks / limitations

- Modifier-only hold via CGEventTap is the fiddliest piece (Right-Cmd emits `flagsChanged`, not keyDown/Up); mitigation: keycode-54-specific flag tracking, tested early (build order puts this first).
- Whisper's intra-sentence EN↔ZH code-switching is imperfect in all local models; the "meta-command then Chinese" phrasing is the reliable path.
- Rules mode cannot translate (LLM required) — accepted.
- Paste-based insertion briefly touches the clipboard — restored automatically; secure-input fields (password boxes) block synthetic paste by OS design.

## Testing

- Unit: RuleCleaner regex cases; LLMCleaner prompt/response parsing (mock server); Inserter clipboard save/restore logic.
- Integration (manual, scripted checklist): dictate the 3 core flows into TextEdit/Notes/Chrome; Ollama-down fallback; idle-unload; accidental-tap rejection; clipboard restoration.
- ASR smoke: canned WAV fixtures (EN, ZH, mixed) → transcriber → assert expected keywords.

## Out of scope (v1)

History, custom vocabulary, launch-at-login, streaming partial text, configurable hotkey UI, Chinese output mode, per-app context, App Store distribution.
