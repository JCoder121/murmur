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

- Items 1–9, 11–13: **PASS** (setup, rules mode, smart mode incl. zh→en,
  Ollama-down fallback, clipboard restore, busy/too-short pills, quit cleanup).
- Item 10 (10-min idle unload): **deferred** — timer resets on every dictation
  and the app was in constant use during the run; unload path is unit-covered
  and quit cleanup (item 11) passed.
- Found & fixed during the run: stale-instance hotkey failure after rebuild
  (ad-hoc TCC invalidation → now self-signed), 2x latency from language
  auto-detect (→ language toggle).

## Future ideas (v2+)

- **Context injection** (planned next): feed frontmost-app name, surrounding
  text, and a personal dictionary into whisper + the cleanup prompt.
- Stream-draft overlay via a small whisper model while speaking; token-streamed
  overlay for Smart mode. Deferred until better hardware — both keep extra
  models resident, which fights real workloads on 8GB.
- Live correction of already-pasted text (Wispr-style): intentionally skipped.
