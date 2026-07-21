# Dictator — a fully local Wispr Flow clone for macOS

Goal: hold a key, talk, release — clean, formatted text appears at your cursor in
whatever app you're using. Zero network traffic at runtime. Everything (speech
recognition, formatting, history) runs on-device.

Target machine: Apple Silicon Mac (dev machine is an M3 / 24GB / macOS 14.6).

---

## 1. What Wispr Flow actually is, under the hood

Understanding the product precisely is most of the design work. Wispr Flow is:

1. **A menu bar app with a push-to-talk loop.** Hold `fn` (configurable), speak,
   release. A small floating "pill" overlay at the bottom of the screen shows
   recording state. There's also a hands-free toggle mode.
2. **Cloud ASR.** Audio is streamed to Wispr's servers for speech recognition —
   this is the part your employer objects to, and it's the part we replace with
   a local model.
3. **LLM post-processing ("AI formatting").** The raw transcript is rewritten by
   a language model before insertion. This is the actual magic, and it's more
   than punctuation:
   - Filler removal: "um", "uh", "like", false starts.
   - **Self-correction resolution**: "send it Tuesday — no wait, Wednesday"
     becomes "send it Wednesday".
   - Auto punctuation, casing, paragraph breaks.
   - **Tone matching per app**: casual in Slack/iMessage, structured in email/docs.
   - **Personal dictionary**: names, jargon, product terms, spelled how you want.
   - Spoken commands: "new line", "scratch that".
4. **Context awareness.** It reads the frontmost app name and (via the
   Accessibility API) text near your cursor, and feeds that to the formatter so
   the output fits what you're writing.
5. **Text injection.** The final text is inserted at the cursor in any app —
   effectively simulated paste, universal across apps.
6. **Low perceived latency.** Transcription happens *while you speak* (streaming),
   so on key-release only the tail needs processing. Text lands in well under a
   second for short utterances.

Every one of these has a solid local equivalent on Apple Silicon in 2026.

---

## 2. Why a local clone is feasible now

- **ASR**: NVIDIA's **Parakeet TDT 0.6B v3** runs via CoreML/ANE on M-series at
  ~80–100ms per utterance — roughly 10x faster than Whisper — with word error
  rates competitive with Whisper large, across 25 languages. **Whisper
  large-v3-turbo** via whisper.cpp (Metal) is the fallback for the other ~75
  languages and noisy audio. Both are free to download and run offline.
- **Formatting LLM**: a 3–4B instruct model (Qwen3-4B, Llama-3.2-3B) at 4-bit
  runs at 60–100+ tok/s on an M3 via llama.cpp/MLX — fast enough to rewrite a
  sentence in ~200–400ms.
- **Everything else** is ordinary macOS systems programming: event taps, audio
  taps, the Accessibility API, and the pasteboard.

---

## 3. Stack decision

**Native Swift menu bar app.** No Electron, no Python.

Why: the hard parts (global `fn`-key capture, low-latency audio, text injection,
Accessibility reads, a non-activating overlay panel) are all macOS-native APIs.
A native app gets you Wispr-level polish and a tiny memory footprint; Electron
fights you on every one of those. If you ever need Windows too, the equivalent
cross-platform stack is Rust + Tauri (see the open-source app *Handy* for proof
it works) — but don't pay that complexity tax unless the work machine is a PC.

Core dependencies (all permissively licensed):

| Concern | Choice | License |
|---|---|---|
| ASR (primary) | FluidAudio (Parakeet TDT v3, CoreML) | Apache-2.0 |
| ASR (multilingual/fallback) | whisper.cpp via SwiftPM, Metal enabled | MIT |
| VAD / endpointing | Silero VAD (CoreML port, ships with FluidAudio) | MIT |
| Formatting LLM (optional) | llama.cpp embedded, or an already-running Ollama | MIT |
| Persistence | GRDB (SQLite) | MIT |
| UI | SwiftUI + AppKit (NSStatusItem, NSPanel) | — |

**Prerequisite**: full Xcode (you currently have only Command Line Tools).
Needed for the app bundle, entitlements, and signing. `xcodes` or the App Store.

---

## 4. Architecture

One app target, five subsystems, each behind a protocol so pieces are swappable:

```
┌─────────────────────────────────────────────────────────────┐
│                     Menu bar app (Swift)                     │
│                                                              │
│  HotkeyController      AudioEngine         Transcriber      │
│  CGEventTap on fn  ──▶ AVAudioEngine   ──▶ Parakeet/CoreML  │
│  hold + toggle         16kHz mono ring     (whisper.cpp     │
│  modes                 buffer + VAD        fallback)        │
│                                                 │            │
│  Injector          ◀── Formatter          ◀─────┘            │
│  pasteboard swap +     1) rules pass (<1ms)                  │
│  synthetic ⌘V,         2) local LLM pass (optional)          │
│  AX fallback           + app context via AX API              │
│                                                              │
│  Overlay pill (NSPanel)   History (SQLite)   Settings UI     │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 HotkeyController
- `CGEventTap` listening for `flagsChanged` to catch the `fn` key (Wispr's
  default and the best choice — it never conflicts with app shortcuts).
  Configurable alternatives: right-⌘, ⌥-space, etc.
- Two modes: **hold-to-talk** (release = commit) and **toggle** (tap to start,
  tap to stop) for long dictation.
- Requires the **Accessibility / Input Monitoring** permission; build a
  first-run flow that deep-links to the right System Settings pane.

### 4.2 AudioEngine
- `AVAudioEngine` input tap, downsampled to 16kHz mono Float32 into a ring
  buffer. Start the engine on hotkey-down; keep the audio unit pre-warmed so
  capture starts in <50ms.
- Silero VAD trims leading/trailing silence and provides endpointing for
  toggle mode (auto-stop after N seconds of silence, like Wispr's hands-free).

### 4.3 Transcriber (protocol, two implementations)
- **ParakeetTranscriber** (default): FluidAudio's CoreML Parakeet TDT v3.
  ~10x realtime on M3; near-instant results for utterance-sized audio. 25
  languages. ~600MB of model files.
- **WhisperTranscriber**: whisper.cpp with large-v3-turbo (quantized, ~1GB,
  Metal). Better for heavy accents, noise, and the long tail of languages.
- **Streaming strategy**: while the key is held, transcribe the buffer every
  ~2s of new audio (Parakeet is fast enough to just redo the whole utterance
  each pass, which sidesteps chunk-boundary errors for typical dictation
  lengths). On release, one final pass over the full buffer. Perceived
  release-to-text latency stays in the 200–400ms range.
- Models stay **resident in memory** after first load. Cold-load is the
  biggest latency killer; a menu toggle can unload them to reclaim RAM.

### 4.4 Formatter — the actual secret sauce
Two stages, so the app is excellent even with the LLM turned off:

**Stage 1 — deterministic (always on, <1ms):**
- Personal dictionary: case-insensitive replacements with word boundaries
  ("cloud flare" → "Cloudflare", coworker names, product jargon).
- Filler strip: um/uh/erm and configurable phrases.
- Spoken commands: "new line", "new paragraph", "period/comma" (opt-in),
  "scratch that" (drops the previous segment).
- Casing/spacing cleanup; smart join with surrounding text (leading space if
  cursor follows a word, capitalize after sentence-enders).

**Stage 2 — local LLM (optional, default-on above ~8 words):**
- Prompt = raw transcript + frontmost app name + up to ~500 chars of text
  before the cursor (read via `AXUIElement`, never stored) + dictionary + the
  app's tone profile (casual / neutral / formal, user-editable per app).
- Tasks: punctuation, disfluency removal, **apply self-corrections**, match
  tone. Temperature 0, strict "rewrite only — never add content" system
  prompt.
- **Hallucination guard**: if the output's length deviates >30% from the raw
  transcript or edit-distance is implausible, discard and fall back to
  Stage 1 output. Dictation must never say things you didn't say.
- Engine: embed llama.cpp with Qwen3-4B-Instruct Q4 (~2.5GB RAM), or detect a
  running Ollama and use it. Embedded is the better end state (no external
  dependency); Ollama is the faster path to working code.

### 4.5 Injector
- Default: save pasteboard contents → write text → synthesize ⌘V via
  `CGEvent` → restore pasteboard after ~200ms. Universal and instant.
- Fallbacks: direct `AXUIElement` value insertion where the focused element
  allows it; per-character `CGEventKeyboardSetUnicodeString` typing for apps
  that block programmatic paste.
- **Safety**: detect secure input mode (`IsSecureEventInputEnabled`) — i.e. a
  password field is focused — and refuse to inject, showing a notice instead.

### 4.6 Shell: overlay, history, settings
- **Overlay pill**: a non-activating `NSPanel` at the bottom of the screen —
  waveform while recording, spinner while formatting, brief error states.
  This is most of Wispr's perceived polish; worth doing early.
- **History**: local SQLite (GRDB): timestamp, app, raw transcript, final
  text. Searchable window, one-click re-copy, retention setting, purge
  button. Never leaves the machine.
- **Settings** (SwiftUI): hotkey, mode, model choice, language, dictionary
  editor, per-app tone profiles, LLM on/off, launch-at-login
  (`SMAppService`), history retention.
- **Model manager**: first-run downloads from Hugging Face with SHA256
  verification — the *only* network access in the app, clearly labeled. Also
  support a fully-offline path: drop model files into
  `~/Library/Application Support/Dictator/models/` by hand (matters on a
  locked-down work network).

---

## 5. Latency budget (release-to-text, short utterance)

| Step | Target |
|---|---|
| Audio flush + VAD trim | ~30ms |
| Final ASR pass (Parakeet, warm) | 80–150ms |
| Stage-1 formatting | <1ms |
| Injection (paste) | ~50ms |
| **Total without LLM** | **~200–250ms** |
| Stage-2 LLM (Qwen3-4B, short text) | +200–400ms |

Rule: short utterances (≤8 words) skip the LLM entirely — they rarely need it —
so quick "sounds good, ship it" dictations feel instantaneous. Never inject
first and rewrite after; text mutating under the cursor is worse than a
300ms wait.

---

## 6. Privacy & compliance posture

This is the story that gets it approved at work:

- **No runtime network calls.** The only network access is the explicit
  first-run model download, which can instead be done manually (or the models
  committed to the repo via Git LFS / attached to GitHub Releases).
- Trivially auditable: small from-scratch codebase, no analytics, no
  auto-update phoning home. `lsof`/Little Snitch will show zero connections.
- History is local SQLite, with retention controls and a purge button.
- AX context reads are used in-memory for the current utterance only.

Honest caveats to plan around:
- Even self-authored tools may need IT sign-off, and granting the
  Accessibility permission can require admin rights on managed Macs — check
  that before investing in polish.
- **Authorship and licensing**: written from scratch, this is your original
  work — publish under MIT with your name. Using Apache/MIT dependencies
  (FluidAudio, whisper.cpp, llama.cpp) with attribution is normal and fine.
  What you can't do is fork an existing GPL app (e.g. VoiceInk) and present
  it as solely yours — study prior art for architecture, write your own code.

Prior art worth reading, not copying: **VoiceInk** (Swift, GPL-3.0 — closest
existing thing to this plan), **Handy** (Rust/Tauri, MIT, cross-platform),
**macparakeet** (Swift, local Parakeet dictation).

---

## 7. Milestones

**M0 — Scaffold (½ day)**
Xcode project (menu bar `LSUIElement` app), mic + accessibility permission
flows, `fn`-key event tap spike proving hold/release detection.

**M1 — Core loop (1–2 days)** ← usable every day from here
Hold fn → record → Parakeet transcribe on release → paste at cursor.
Hardcoded settings, no UI beyond the menu.

**M2 — Feel (2–3 days)**
Streaming transcription while held, VAD trim, overlay pill with waveform,
toggle mode, model manager with offline install path, whisper.cpp fallback.

**M3 — Formatting v1 (2 days)**
Stage-1 deterministic pipeline: dictionary editor, filler strip, spoken
commands, smart join. Settings window, history window, launch-at-login.

**M4 — AI formatting (2–3 days)**
Local LLM stage via Ollama first, then embedded llama.cpp. AX context
capture, per-app tone profiles, hallucination guard, secure-input refusal.

**M5 — Ship (1–2 days)**
App icon, codesign + notarize (free Apple ID ad-hoc signing works for
personal use; notarization needs the $99 developer account), GitHub Actions
release build, README with the privacy/audit story, optional Homebrew tap.

Total: roughly two focused weeks to full Wispr-parity for personal use, with a
genuinely useful tool after day 2.

---

## 8. Open decisions

1. **Is the work machine a Mac?** This plan is macOS-native. If it's Windows,
   switch to the Rust + Tauri track before writing code.
2. **LLM engine**: start with Ollama (fast to integrate) and migrate to
   embedded llama.cpp, or embed from day one? Plan assumes Ollama-first.
3. **Model distribution**: downloader with checksums vs. Git LFS in-repo.
   Downloader is friendlier; LFS is more air-gap-proof.
