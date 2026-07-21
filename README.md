# Dictator

Fully local push-to-talk dictation for macOS. Hold the hotkey (`fn` by
default — Right Shift/Command/Option also available from the menu bar → Hotkey),
speak, release — text appears at your cursor in whatever app you're using.
While holding, tap **Space** to lock hands-free recording (the pill shows a
lock); tap the hotkey again to finish. A tap-to-toggle mode is also available
under menu → Activation. All speech recognition and
formatting runs on-device; the app makes **zero network calls at runtime**.

See [PLAN.md](PLAN.md) for the full architecture and roadmap.

## Status

| Milestone | State |
|---|---|
| M0 — menu bar app, fn hotkey, mic capture, paste injection (stub transcription) | ✅ |
| M1 — real local transcription (Parakeet TDT v3 via CoreML) | ✅ |
| M2 — streaming transcription, overlay pill, silence trim, toggle mode | ✅ |
| M3 — personal dictionary, spoken commands, history, settings window | ✅ |
| M4 — local LLM polish (embedded llama.cpp or Ollama), per-app tone, context | ✅ |
| M5 — whisper.cpp fallback, app icon, signing, releases | |

## Build & run

Requires macOS 14+ on Apple Silicon and the Xcode Command Line Tools
(`xcode-select --install`). Full Xcode is **not** required.

```sh
make run     # build Dictator.app and launch it
make stop    # quit the app
make clean
```

### Build modes

The default build contains **no inference engine and no downloader** — no code
that can open a network connection. Two opt-in components are compiled in only
when explicitly requested:

| Build | Command | Contains |
|---|---|---|
| Default | `make app` | Speech recognition only. No LLM, no downloader. |
| Full | `make app-full` | Adds llama.cpp AI polish + Hugging Face model download |

`make audit` verifies the claim on whatever you built: it lists network calls in
this project's source (with the compile flag guarding each one), networking
symbols in the executable, embedded frameworks, and live sockets held by the
running app. On a default build it reports no reachable network path and no
open sockets.

One honest note for auditors: the FluidAudio speech library ships its own model
downloader, so `NSURLSession` symbols link into the binary even in the default
build. Nothing in Dictator reaches them — `make audit` shows the only
`downloadAndLoad` call is behind `#if DICTATOR_DOWNLOAD`, and the running app
opens no sockets. `CFNetwork` arrives via Foundation and is unavoidable in any
Cocoa app.

## First-run setup

1. **Accessibility permission** — needed for the global `fn` hotkey and for
   pasting into other apps. The app prompts on first launch; enable *Dictator*
   in System Settings → Privacy & Security → Accessibility. If it doesn't
   appear, add `build/Dictator.app` with the + button. Some macOS versions also
   require Input Monitoring — the menu has shortcuts to both panes. Use
   *Retry Hotkey Listener* from the menu after granting.
2. **Microphone permission** — prompted the first time you hold `fn`.
3. **Free up the `fn` key** — System Settings → Keyboard → *Press 🌐 key to:*
   **Do Nothing**, so dictating doesn't also open the emoji picker.

Note: the app is ad-hoc signed, so rebuilding can invalidate previously granted
permissions — re-grant (toggle off/on) after a rebuild if the hotkey goes dead.
Proper local signing lands in M5.

## Speech models (and the zero-network install)

Transcription uses NVIDIA's Parakeet TDT 0.6B v3 as CoreML models (~470MB on
disk). **The app never downloads models by default** — it loads them only
from the paths shown in Settings → Models (both the speech folder and the
polish model are configurable there, so vetted copies can live anywhere: an
internal Artifactory checkout, a shared drive, a USB stick). If a model is
missing, the app reports it and stops; it does not fetch. Ways to get the
speech models onto a machine:

- **From this repo** — the only host contacted is GitHub itself. From a
  fresh clone, **before first launch**:

  ```sh
  make install-models-from-repo
  ```

  This fetches this repo's `models` branch (the same models, chunked under
  GitHub's file-size limit), reassembles the tarball, verifies its SHA-256,
  and installs it. Sideloaded models take priority over the downloader,
  which then never runs.

- **Without any network**: `make export-models` on a machine that has the
  models, move the tarball by AirDrop/USB, then
  `make install-models FILE=dictator-models-v3.tar.gz` — or point
  Settings → Models at wherever your organization keeps vetted copies.
- **Opt-in download**: Settings → Models has an off-by-default toggle to
  allow a one-time fetch from Hugging Face, for personal machines where
  that's acceptable. (The developer CLI's transcribe smoke test may also
  download; the app itself never does unless this toggle is on.)

## AI polish (optional, not in the default build)

Dictations of 8+ words can additionally be cleaned up by a local LLM:
self-correction resolution ("Tuesday, no wait, Wednesday" → "Wednesday"),
context-aware fixes, and per-app tone matching. **It ships disabled**: in
real-world testing a 4B model fixed less than it risked (missed most
self-corrections, occasionally paraphrased or obeyed instructions embedded
in the dictation — the latter now blocked by output guards). The
deterministic pipeline (fillers, spoken commands, quotes, dictionary) plus
Parakeet's own punctuation covers most needs at ~200ms.

To experiment, build with it compiled in — `make app-full` — then enable the
toggle in Settings and point Settings → Models at any GGUF chat model you
already have: a specific file (any filename, even Ollama's extension-less
blobs) or a folder of models (LM Studio's folder works as-is). The Models
section lists every model it can see with sizes and marks the active one;
click to switch. Left blank, it scans
`~/Library/Application Support/Dictator/llm/`. Inference runs in-process via
Metal — e.g. Qwen3-4B-Instruct Q4 (~2.5GB) — with no server to install and
no network access; the model file can come from wherever your policies allow
(an internal Artifactory, USB, Hugging Face). A larger (8B+) model may well
tip the tradeoff.

The text never leaves the machine. Output is guarded: rewrites that lose
content, deviate implausibly in length, or echo a word more often than the
input (a model partially obeying an instruction embedded in the dictation)
are discarded in favor of the deterministic text.

## Privacy

For a full account of the design decisions, permissions, threat considerations,
and how to verify the network claims yourself, see
[SECURITY.md](SECURITY.md).

- Audio is captured only while the hotkey is held, processed in memory, and
  never written to disk or the network.
- With sideloaded models (above) the app makes zero network connections,
  verifiable with Little Snitch or `lsof -i`.
- If a password field is focused (secure input), Dictator refuses to inject.

## Credits

- Speech recognition: [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
  by NVIDIA (CC-BY-4.0), running via [FluidAudio](https://github.com/FluidInference/FluidAudio)
  (Apache-2.0) CoreML conversions.

## License

MIT — see [LICENSE](LICENSE).
