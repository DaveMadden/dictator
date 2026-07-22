# Dictator

Fully local push-to-talk dictation for macOS. Hold the hotkey (`fn` by
default — Right Shift/Command/Option also available from the menu bar → Hotkey),
speak, release — text appears at your cursor in whatever app you're using.
While holding, tap **Space** to lock hands-free recording (the pill shows a
lock); tap the hotkey again to finish. A tap-to-toggle mode is also available
under menu → Activation. All speech recognition and
formatting runs on-device; the app makes **zero network calls at runtime**.

See [PLAN.md](PLAN.md) for the full architecture and roadmap.

## Quick Run

If you already have the speech model downloaded and just want to build and run:

```sh
./scripts/build-app.sh   # builds build/Dictator.app
open build/Dictator.app  # launches the app
```

On first launch, ensure you have acquired Admin permissions so you can grant Accessibility and Microphone permissions when prompted. Then configure the model path in the menu bar → Settings → Models to point at your downloaded `parakeet-tdt-0.6b-v3-coreml` directory.

#### Getting Models via STR's Nexus

If you're on the STR network and need to download the speech model (`parakeet-tdt-0.6b-v3-coreml`):

1. **Connect to the STR VPN**

2. **Install the Hugging Face CLI** from PyPI:

   ```sh
   python3 -m pip install --user huggingface_hub==0.21.0
   ```

3. **Add the user CLI bin directory to your PATH** for the current shell:

   ```sh
   export PATH="$HOME/Library/Python/3.9/bin:$PATH"
   ```

4. **Point Hugging Face traffic at the STR Nexus proxy**:

   ```sh
   export HF_ENDPOINT="https://nexus.str.us/repository/it-hf-proxy/"
   export HF_HUB_DOWNLOAD_TIMEOUT=120
   export HF_HUB_ETAG_TIMEOUT=1800
   ```

5. **Download the model**:
   ```sh
   huggingface-cli download FluidInference/parakeet-tdt-0.6b-v3-coreml --local-dir ~/models/parakeet-tdt-0.6b-v3-coreml
   ```

**Important notes:**

- The working huggingface_hub version is `0.21.0` (not 1.21.0 as identified in the STR Nexus documentation)
- The installed command is `huggingface-cli`, not `hf`
- The package install comes from PyPI; model downloads route through Nexus once `HF_ENDPOINT` is set
- If you hit odd download behavior, move `~/.cache/huggingface` out of the way

After downloading, point the app at `~/models/parakeet-tdt-0.6b-v3-coreml` via Settings → Models.

## Status

| Milestone                                                                       | State |
| ------------------------------------------------------------------------------- | ----- |
| M0 — menu bar app, fn hotkey, mic capture, paste injection (stub transcription) | ✅    |
| M1 — real local transcription (Parakeet TDT v3 via CoreML)                      | ✅    |
| M2 — streaming transcription, overlay pill, silence trim, toggle mode           | ✅    |
| M3 — personal dictionary, spoken commands, history, settings window             | ✅    |
| M4 — local LLM polish (embedded llama.cpp or Ollama), per-app tone, context     | ✅    |
| M5 — whisper.cpp fallback, app icon, signing, releases                          |       |

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

| Build   | Command         | Contains                                               |
| ------- | --------------- | ------------------------------------------------------ |
| Default | `make app`      | Speech recognition only. No LLM, no downloader.        |
| Full    | `make app-full` | Adds llama.cpp AI polish + Hugging Face model download |

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
   pasting into other apps. The app prompts on first launch; enable _Dictator_
   in System Settings → Privacy & Security → Accessibility. If it doesn't
   appear, add `build/Dictator.app` with the + button. Some macOS versions also
   require Input Monitoring — the menu has shortcuts to both panes. Use
   _Retry Hotkey Listener_ from the menu after granting.
2. **Microphone permission** — prompted the first time you hold `fn`.
3. **Free up the `fn` key** — System Settings → Keyboard → _Press 🌐 key to:_
   **Do Nothing**, so dictating doesn't also open the emoji picker.

### Keeping permissions across rebuilds

The app is ad-hoc signed by default, so rebuilding invalidates previously granted
permissions (macOS treats each rebuild as a different app). To keep permissions
stable across rebuilds, create a local code signing certificate:

1. Open **Keychain Access** (Applications → Utilities)
2. Menu: Keychain Access → Certificate Assistant → Create a Certificate...
   - Name: `Dictator Dev` (must be exactly this name)
   - Identity Type: Self Signed Root
   - Certificate Type: Code Signing
   - Check "Let me override defaults", then Continue through defaults
   - Save to "login" keychain
3. Rebuild: `./scripts/build-app.sh` (you'll see "signed: Dictator Dev")
4. Re-grant permissions one last time in System Settings

After this, rebuilding won't reset your permissions.

### Launch at startup

Use the menu bar → Start at Login to enable/disable launching Dictator on login.
Alternatively, add it manually via System Settings → General → Login Items.

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

## Troubleshooting

### Hotkey won't activate after rebuilding

**Problem**: The app says "Hotkey inactive" even though Dictator is enabled in Accessibility settings.

**Cause**: Ad-hoc signed builds get a new signature each time, so macOS treats each rebuild as a different app. The Accessibility permission you granted is tied to the old signature.

**Workaround**:
1. System Settings → Privacy & Security → Accessibility
2. Select "Dictator" and click the **"-"** button to remove it completely
3. Click the **"+"** button and navigate to `build/Dictator.app`
4. Enable the toggle for the newly added entry
5. Relaunch the app

**Permanent fix**: Create a "Dictator Dev" signing certificate (see "Keeping permissions across rebuilds" above) so the signature stays stable across rebuilds.

## Credits

- Speech recognition: [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
  by NVIDIA (CC-BY-4.0), running via [FluidAudio](https://github.com/FluidInference/FluidAudio)
  (Apache-2.0) CoreML conversions.

## License

MIT — see [LICENSE](LICENSE).
