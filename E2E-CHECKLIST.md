# wispr_clone — v1 E2E Acceptance (Task 12)

## Setup
- [x] `make run` → grant **Microphone** when prompted
- [x] Grant **Accessibility** (System Settings → Privacy) → relaunch: `make run`
- [x] 🎤 visible in menu bar

## Step 1 — Rules mode (menu → Rules)
- [x] 1. TextEdit: dictate "um, hello world, this is, uh, a test" → fillers gone, capitalized, pasted at cursor
- [x] 2. Chrome address bar: dictate a search phrase → lands in focused field
- [x] 3. Tap Right-Cmd <0.3s → nothing pasted, overlay disappears
- [x] 4. Hold Right-Cmd in silence 2s → nothing pasted

## Step 2 — Smart mode (menu → Smart; run `ollama serve` first)
- [x] 5. "so um I think we should uh probably ship this tomorrow" → clean English, fillers/false starts gone
- [x] 6. "give me the following in English: 我明天要去北京开会" → English only, instruction not echoed
- [x] 7. Pure-Mandarin sentence → English translation inserted

## Step 3 — Failure modes
- [x] 8. `pkill ollama`, Smart mode → still works via rules; "Ollama down" warning pill
- [x] 9. Copy "KEEP" → dictate something → wait 1s → Cmd-V → "KEEP" pastes (clipboard restored)
- [ ] 10. Wait 10+ min → `pgrep whisper-server` empty (idle unload) → dictate again → works (~2s first-word delay)

## Extra probes (from final review)
- [x] 11. Quit app → `pgrep whisper-server` empty (quit cleanup)
- [x] 12. Two fast back-to-back dictations → second shows "Busy…" pill, clipboard ends correct
- [x] 13. Hold 0.3–0.5s → "Too short" pill shows

## Record
Note pass/fail per item here, then tell Claude — results go into README `## v1 acceptance` + commit.
