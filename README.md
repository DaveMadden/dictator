# Dictator

Fully local push-to-talk dictation for macOS. Hold the hotkey (`fn` by
default — Right Shift/Command/Option also available from the menu bar → Hotkey),
speak, release — text appears at your cursor in whatever app you're using. All speech recognition and
formatting runs on-device; the app makes **zero network calls at runtime**.

See [PLAN.md](PLAN.md) for the full architecture and roadmap.

## Status

| Milestone | State |
|---|---|
| M0 — menu bar app, fn hotkey, mic capture, paste injection (stub transcription) | ✅ |
| M1 — real local transcription (Parakeet TDT v3 via CoreML) | ✅ |
| M2 — streaming transcription, overlay pill, silence trim, toggle mode | ✅ |
| M3 — personal dictionary, spoken commands, history, settings window | ✅ |
| M4 — local LLM formatting, per-app tone, context awareness; whisper.cpp fallback | |
| M5 — signing, releases | |

## Build & run

Requires macOS 14+ on Apple Silicon and the Xcode Command Line Tools
(`xcode-select --install`). Full Xcode is **not** required.

```sh
make run     # build Dictator.app and launch it
make stop    # quit the app
make clean
```

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
disk). Two ways to get them onto a machine:

- **Online (default)**: on first launch the app downloads them once from
  Hugging Face into `~/Library/Application Support/FluidAudio/Models/` and
  never fetches again.
- **Offline / locked-down machine**: sideload them so the app performs **no
  network access at all** — the only host ever contacted is GitHub itself.
  From a fresh clone, **before first launch**:

  ```sh
  make install-models-from-repo
  ```

  This fetches this repo's `models` branch (the same models, chunked under
  GitHub's file-size limit), reassembles the tarball, verifies its SHA-256,
  and installs it. Sideloaded models take priority over the downloader,
  which then never runs.

  Alternative without any network: `make export-models` on a machine that
  has the models, move the tarball by AirDrop/USB, then
  `make install-models FILE=dictator-models-v3.tar.gz`.

## Privacy

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
