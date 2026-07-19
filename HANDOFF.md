# HANDOFF — wispr_clone build state (2026-07-18)

For the next Claude Code session. Read this fully before touching anything.

## What this project is

Local offline smart dictation for macOS (M1 Air 8GB): hold **Right-Cmd** → speak EN/ZH → release → clean **English** text pastes at cursor.

- **Spec (approved by user):** `docs/superpowers/specs/2026-07-17-wispr-clone-design.md`
- **Implementation plan (the source of truth for all tasks — complete code inside):** `docs/superpowers/plans/2026-07-17-wispr-clone.md`
- **Branch:** `feat/v1` (repo root = this directory). Commit each task there.
- **Execution mode chosen by user:** superpowers:subagent-driven-development (sequential; fresh implementer subagent per task + task reviewer per task + final whole-branch review). Progress ledger: `.superpowers/sdd/progress.md`. Helper scripts in the skill dir: `scripts/task-brief PLAN_FILE N` and `scripts/review-package BASE HEAD`.

## Environment facts (hard-won — do not rediscover)

1. **CLT was corrupted and has been FIXED.** Now: Command Line Tools 26.6, Swift 6.3.3. `swift build` verified working (test package built in 47s).
2. **Shells run under Rosetta** (user's nvm node v24.18.0 is x86_64, so every CC child process is x86_64-translated; `swift` targets x86_64 by default here). **Prefix all swift/make invocations with `arch -arm64`**, and the Makefile (plan Task 1) must be amended to use `SWIFT := arch -arm64 swift` (and `xcrun` equivalents if needed) so the app builds native arm64. User is separately investigating the Rosetta situation in another session — coordinate if they've changed node.
3. **Dual Homebrew:** arm64 at `/opt/homebrew` (use this, as `arch -arm64 /opt/homebrew/bin/brew`), legacy Intel remnants at `/usr/local`. Bare `brew` may not be on PATH.
4. **Sandbox note:** `git init`/builds sometimes hit sandbox "Operation not permitted" — those specific commands were run with sandbox disabled. `swift build` may need the same.
5. **Disk:** was critically low; user cleaned up — ~27GB free as of now. No longer a constraint.
6. Machine: macOS 26.3, M1, 8GB RAM. No Xcode — CLT only (never use xcodebuild; SwiftPM + Makefile per plan).

## Already installed & verified (do NOT reinstall)

- `whisper-cpp 1.9.1` via arm64 brew → `/opt/homebrew/bin/whisper-server` + `whisper-cli` (arm64 ✓)
- Whisper model at `~/Library/Application Support/WisprClone/models/ggml-large-v3-turbo-q5_0.bin` (547MB ✓)
- **ASR smoke test passed:** JFK sample (11s) transcribed in ~10.5s *including* model load; decode ~0.8s → warm-server latency will hit the 1–3s target
- Ollama (brew) + `qwen2.5:3b` pulled (1.9GB). `ollama serve` may still be running in the background from this session.
- **Smart-layer smoke test passed:** system prompt from plan Task 7 + input "um so please give me the following in english: 我明天要去北京开会" → "I'll be going to Beijing for a meeting tomorrow." (fillers stripped, meta-command honored, translation correct)

## Task status (mirror of .superpowers/sdd/progress.md)

| Plan task | Status |
|---|---|
| 1. Scaffold (Package.swift, Makefile, menu-bar skeleton) | **NOT DONE** — first attempt blocked by the (now-fixed) broken CLT; no commits exist. Re-dispatch fresh. Amend Makefile per Rosetta note above. Implementer cannot observe the menu bar — verify via `make bundle` + `codesign -dv` instead of `make run`. |
| 2. HotkeyMonitor | not started (riskiest piece — do early; needs user for manual verification, see below) |
| 3. RuleCleaner | not started (pure TDD, no user needed) |
| 4. WAVWriter | not started (pure TDD) |
| 5. Recorder | not started (manual mic test needs user) |
| 6. WhisperServer | not started (parse tests pure; integration can use the installed binary+model non-interactively — transcribe the JFK wav) |
| 7. OllamaCleaner | not started (TDD; fallback test uses dead port; live Ollama available) |
| 8. Inserter | not started (paste test needs user or can be verified by pasting into a TextEdit doc via scripted focus — safest: defer to user session) |
| 9. Overlay | not started (visual check needs user) |
| 10. Settings + AppController wiring | not started (Settings TDD; full pipeline manual test needs user) |
| 11. setup.sh + README | **DONE** commit `d01abff`, review clean. Minors logged in ledger for final review: (a) setup.sh idempotency check `ollama list | grep` needs daemon running; (b) cosmetic whitespace. Reviewer ⚠️: re-verify model-path/model-name constants against real WhisperServer.swift/OllamaCleaner.swift when Tasks 6–7 land. |
| 12. E2E acceptance checklist | not started — **requires the user at the machine** (grant Mic + Accessibility perms, dictate the flows in plan Task 12) |
| 13. Final whole-branch review | not started (use requesting-code-review's code-reviewer template, most capable model, package via `review-package $(git merge-base <base> HEAD) HEAD` — note branch base is commit `80f5c72`) |

## Process notes for the controller

- Implementer subagents: cheapest model tier (plan contains complete code — transcription + testing). Reviewers: mid tier. Final review: most capable.
- Dispatch pattern used so far: extract brief with `task-brief`, give subagent the brief path + report path (`.superpowers/sdd/task-N-report.md`) + environment adjustments (Rosetta/arch -arm64, no-Xcode, don't launch GUI apps), subagent returns STATUS/commits/one-line summary only.
- Manual verification steps in plan Tasks 2/5/8/9/10 need a human: batch them — implement + unit-test + build everything subagent-side, then run ONE consolidated user test session at the end (Task 12 covers most of it). Exception: consider asking the user to smoke-test Task 2 (hotkey) early since it's the riskiest integration point.
- Record every completed task in `.superpowers/sdd/progress.md` (`Task N: complete (commits X..Y, review clean)`), and Minor findings too — the final review triages them.
- User communication style: extremely concise; use AskUserQuestion for decisions.

## Interview decisions already locked (don't re-ask)

Fresh Swift menu-bar app · whisper large-v3-turbo q5_0 · Smart(Ollama qwen2.5:3b)/Rules menu-toggle with silent fallback · hold Right-Cmd (keycode 54), <0.3s ignored · output ALWAYS English (zh always translated) · load-on-demand + 10-min idle unload · floating pill feedback · pasteboard+Cmd-V insertion with string-clipboard restore · no v1 extras (no history/vocab/login-item).
