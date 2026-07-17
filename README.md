# wispr_clone

Local, offline smart dictation for macOS. Hold **Right-Cmd**, speak English /
Mandarin / a mix, release — clean **English text** is pasted at your cursor.

Built for a MacBook Air M1 (8GB): whisper large-v3-turbo (quantized, Metal)
for speech recognition, Qwen2.5-3B via Ollama for cleanup + Chinese→English
translation, with an instant rules-only fallback mode.

## Setup

```bash
./scripts/setup.sh   # installs whisper-cpp (~15MB), whisper model (~574MB),
                     # optionally Ollama + qwen2.5:3b (~2.5GB, Smart mode only)
make run             # builds dist/WisprClone.app and opens it
```

On first run grant **Microphone** and **Accessibility** permissions
(System Settings → Privacy & Security), then relaunch.

## Use

- Hold **Right-Cmd** → speak → release. Text appears at your cursor.
- Menu-bar 🎤 → switch **Smart mode** (LLM cleanup, zh→en translation) vs
  **Rules mode** (instant, filler-stripping only, no translation).
- Smart mode falls back to rules automatically if Ollama isn't running
  (start it with `ollama serve`).
- Say "give me the following in English: {Chinese}" to dictate Chinese and
  insert the English translation.

## Notes

- Whisper model loads on first dictation (~2s) and unloads after 10 min idle.
- Insertion uses clipboard + Cmd-V; your previous clipboard **string** is
  restored ~0.3s later (images/rich content are not restored).
- Recording caps at 2 minutes per dictation. Holds under 0.3s are ignored.
- Rebuilding the app (ad-hoc signature) may occasionally require re-granting
  Accessibility permission.

## Dev

```bash
swift test    # unit tests
make bundle   # build dist/WisprClone.app without launching
```
