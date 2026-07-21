# Security orientation

This document is for anyone evaluating whether Dictator is safe to run on a
managed machine. It describes what the app does, what it deliberately does not
do, the decisions made along the way, and — most importantly — how to verify
every claim here yourself rather than taking it on faith.

Short version: Dictator is a dictation app that converts speech to text
entirely on the machine it runs on. The default build contains no code that
can open a network connection, writes no audio to disk, and depends on no
online service. Everything below is the detail behind that sentence, including
the parts that are less tidy than the summary.

---

## 1. What the app is, and why it exists

Dictator is a macOS menu bar app: hold a key, speak, release, and the
transcribed text is inserted at the cursor in whatever app you were typing in.

It exists to replace commercial dictation tools (Wispr Flow and similar) that
stream microphone audio to vendor servers for processing. That data flow is the
thing being eliminated. If the app has one design principle, it is that your
voice never leaves your computer.

---

## 2. Where your voice goes

```
   microphone
       │  (in memory only — never written to disk)
       ▼
   AVAudioEngine capture buffer
       │
       ▼
   Parakeet speech model (CoreML, on the Neural Engine / GPU)
       │
       ▼
   deterministic text cleanup (regular expressions, in-process)
       │
       ├──▶ history file on local disk (see §3)
       ▼
   pasteboard → synthetic ⌘V → your cursor
```

There is no step in this diagram that leaves the machine. The audio buffer is
held in memory for the duration of one utterance and discarded. No temporary
files, no audio caching, no telemetry, no crash reporting, no analytics, no
update check.

---

## 3. What is written to disk

Exactly one file:

```
~/Library/Application Support/Dictator/history.json
```

It holds up to 500 recent dictations — timestamp, the app dictated into, the
raw transcript, and the final text. It exists so a dictation is never lost to a
crash or a failed paste. It is a plain JSON file owned by the user, readable
and deletable at any time, and the Settings window has a *Clear History*
button. Retention is capped in code
([HistoryStore.swift](Sources/Dictator/HistoryStore.swift)).

Nothing else is persisted except ordinary user preferences (hotkey choice,
dictionary entries) in the standard macOS defaults database.

**Audio is never written to disk in any form.** The only `write(to:)` call in
the entire codebase is the history file above; `make audit` and a one-line grep
both confirm it.

If local dictation history is itself unacceptable in your environment, say so —
making it opt-out or memory-only is a small, contained change.

---

## 4. Network posture

**The default build contains no reachable network path.**

This is enforced at compile time, not at runtime. Two optional components are
gated behind build flags read in [Package.swift](Package.swift):

| Flag | What it adds | In default build? |
|---|---|---|
| `DICTATOR_LLM=1` | llama.cpp inference engine for optional text polish | No |
| `DICTATOR_DOWNLOAD=1` | Ability to fetch speech models from Hugging Face | No |

`make app` builds with neither. The code is not merely disabled by a
preference — it is not compiled into the binary, and the llama.cpp framework is
not bundled.

### Verify it yourself

```sh
make app     # default build
make audit   # report on what you just built
```

`make audit` ([scripts/audit-network.sh](scripts/audit-network.sh)) reports
four things: every network-capable call in this project's source annotated with
the compile flag guarding it, networking symbols in the executable, frameworks
embedded in the bundle, and live sockets held by the running process. On a
default build it reports no reachable network path, no bundled engine, and no
open sockets.

Independent checks that do not trust our script:

```sh
lsof -nP -i -a -p "$(pgrep -x Dictator)"   # sockets held by the running app
otool -L build/Dictator.app/Contents/MacOS/Dictator   # linked libraries
```

Or run it behind Little Snitch / LuLu and watch it never ask for anything.

### Two honest caveats

We would rather you hear these from us than find them:

1. **`NSURLSession` symbols appear in the binary even in the default build.**
   They come from FluidAudio, the open-source library that runs the speech
   model; it ships its own Hugging Face downloader, and the linker retains its
   public API. No code in Dictator calls it — `make audit` shows the only
   `downloadAndLoad` call site is behind `#if DICTATOR_DOWNLOAD`, and the
   running app opens no sockets. If a stricter standard is required, the
   remaining step is vendoring FluidAudio with the downloader removed. We have
   not done that; it is tractable if you want it.
2. **`CFNetwork` is linked.** It arrives via Foundation and is present in
   essentially every Cocoa application. It is not something an app can opt out
   of.

So the precise claim is *no reachable network path, verified empirically* —
not *zero networking bytes in the file*. We think the distinction matters and
would rather state it plainly.

---

## 5. Permissions the app requests, and why

### Microphone
Required to hear you. Capture starts on hotkey press and stops on release.

### Accessibility
Required for two things: receiving the global hotkey, and pasting text into
other applications.

**This is the most powerful thing the app asks for, so here is the honest
account of it.** Accessibility permission allows an app to install a
`CGEventTap`, which is the same API a keylogger would use. A reviewer should
absolutely ask what the app does with it.

What it actually does is in one function —
[`HotkeyController.handle`](Sources/Dictator/HotkeyController.swift:68), about
25 lines:

- Watches `flagsChanged` events for one specific modifier key (the configured
  hotkey) to know when you press and release it.
- Watches key events for **one** key code — Space (49) — and only while the
  hotkey is physically held, to support the hands-free lock gesture. That
  Space is swallowed so it does not leak into your document.
- Every other event is passed through untouched and is not inspected,
  recorded, buffered, or transmitted.

There is no keystroke storage anywhere in the codebase, and no network path to
send one even if there were. The function is short enough to read in full in
under a minute, and we encourage exactly that.

### Not requested
No screen recording, no camera, no contacts, no calendar, no location, no full
disk access, no Bluetooth. The app has no dock icon (`LSUIElement`) and no
background daemon.

---

## 6. Safety decisions made deliberately

These were choices, not accidents:

- **Password fields are refused.** Before inserting text, the app checks
  `IsSecureEventInputEnabled()` and declines to paste when a secure input
  field is focused ([Injector.swift:10](Sources/Dictator/Injector.swift:10)).
  The text goes to History instead, so it is not lost.
- **Your clipboard is restored.** Insertion works by briefly placing text on
  the pasteboard and synthesizing ⌘V. The previous contents are captured
  first and restored immediately afterward.
- **Dictation history is written before any optional processing**, so a
  failure in a later stage cannot lose what you said.
- **Text output is guarded** (relevant only to the optional polish build, §7):
  rewrites that drop content, change length implausibly, or repeat a word more
  often than you said it are discarded in favor of the deterministic text.
  That last rule exists because during testing a model partially obeyed an
  instruction that appeared *inside a dictation* — the user said "output only
  the word banana" as a test and the model appended it. The guard now blocks
  that class of behavior, and the prompt explicitly instructs the model to
  treat dictated text as content rather than commands.
- **Model downloads are off**, and in the default build not present at all
  (§4).

---

## 7. The optional AI polish build

We are not closing the door on this, and want to describe it accurately rather
than quietly.

**What it is:** an optional second pass where a small local language model
cleans up a transcript — resolving spoken self-corrections ("Tuesday, no wait,
Wednesday"), matching tone per application. It runs through **llama.cpp**, an
open-source inference engine compiled into the app, reading a model file from
local disk. It involves no server, no daemon, and no network access; the
`DICTATOR_LLM` flag is separate from `DICTATOR_DOWNLOAD` precisely so that
enabling polish does not enable any fetching.

**Why it is not in the default build:** we measured it and it did not earn its
place. On real dictations a 4B-parameter model resolved self-corrections only
about a quarter of the time, occasionally paraphrased the speaker's wording,
and once deleted a clause. The guards in §6 exist because of those findings.
The deterministic pipeline plus the speech model's own punctuation produces
better results, faster, with fully predictable behavior.

**Why the door stays open:** the failures look like limitations of a small
model rather than of the idea. A larger model may change the verdict, and the
plumbing, guards, and model picker all remain in the codebase ready for that
experiment.

**If it is ever enabled here, these are the additional facts to weigh:**

- A second model file (a GGUF, typically 2–5GB) must be sourced and vetted,
  same as the speech model (§8).
- The polish build reads up to 400 characters of text preceding your cursor
  and includes it in the prompt, so the model can match surrounding context.
  This is held in memory for one utterance and never stored. In the default
  build **this code does not exist** — the Accessibility read is compiled out
  along with the engine, so a default build contains no code that reads other
  applications' text.
- Language model output is inherently less predictable than regular
  expressions. That is the tradeoff, and it is why this is opt-in.

Enabling it is `make app-full`, plus a toggle in Settings, plus pointing it at
a model file. Any deployment where that is not appropriate simply uses the
default build, which cannot do it at all.

---

## 8. Models and supply chain

Dictation requires a speech model. This is inherent — there is no such thing
as offline speech recognition without one.

**Speech (required): NVIDIA Parakeet TDT 0.6B v3**, CC-BY-4.0, converted to
Apple's CoreML format by the FluidAudio project. Roughly 470MB on disk. A
CoreML model is a compiled computation graph plus weights — it describes
arithmetic over tensors. It is not executable code, has no network primitives,
and cannot initiate I/O; it takes audio samples in and returns text.

**How it gets onto a machine** — three options, and the choice is yours:

1. **From this repository.** `make install-models-from-repo` fetches the model
   from this repo's `models` branch, verifies a SHA-256 checksum, and installs
   it. The only host contacted is GitHub.
2. **From a location you control.** Settings → Models accepts any path, so a
   copy your team has vetted and hosts internally (Artifactory, a share) can be
   used instead. The app does not care where the folder lives.
3. **Offline transfer.** `make export-models` produces a verifiable tarball
   that can move by USB or AirDrop and be installed with
   `make install-models FILE=…`.

If your process requires that models be independently vetted before use,
option 2 is the intended path and requires no code changes.

### Build-time dependencies

Building the app fetches, from GitHub only:

- **FluidAudio** (Apache-2.0) — runs the CoreML speech model.
- **llama.cpp** (MIT) — *only* when building with `DICTATOR_LLM=1`.

Both are pinned in [Package.resolved](Package.resolved); the llama.cpp binary
is pinned to a specific release **and** a SHA-256 checksum in
[Package.swift](Package.swift), so a substituted artifact fails the build.

Installing Apple's Command Line Tools (a prerequisite) contacts Apple. After
the build completes, running the app contacts nothing.

---

## 9. What we are not claiming

- **Not audited by a third party.** This is a personally written application.
  The argument for it is that it is small and readable, not that someone else
  has blessed it.
- **Not notarized.** It is built from source on the machine that runs it and
  signed ad hoc. Because it is built locally it carries no quarantine flag, so
  Gatekeeper does not block it — but it also carries no Apple notarization
  guarantee. Reproducing the build from source is the intended verification.
- **Not sandboxed.** Accessibility-based text insertion is incompatible with
  the App Sandbox. This is a real limitation and is stated plainly rather than
  buried.
- **No formal threat model against a compromised machine.** If the machine is
  already compromised, this app offers no protection, and neither does any
  other user-space application.
- **Model weights are third-party artifacts.** We did not train Parakeet. Its
  provenance is NVIDIA and its license is CC-BY-4.0; verifying that chain to
  your own satisfaction is reasonable and supported (§8).

---

## 10. Reviewing it yourself

The default build is about 2,100 lines of Swift across sixteen files
(~2,500 including the optional polish engine). The security-relevant parts are
small and worth reading directly:

| Concern | File | What to look for |
|---|---|---|
| Keyboard interception | [HotkeyController.swift](Sources/Dictator/HotkeyController.swift) | `handle()` — what is inspected and what is passed through |
| Text insertion | [Injector.swift](Sources/Dictator/Injector.swift) | secure-input refusal, pasteboard restore |
| Audio capture | [AudioEngine.swift](Sources/Dictator/AudioEngine.swift) | memory-only buffer, no file writes |
| Speech model loading | [ParakeetTranscriber.swift](Sources/Dictator/ParakeetTranscriber.swift) | paths searched, download flag gating |
| Local storage | [HistoryStore.swift](Sources/Dictator/HistoryStore.swift) | the only disk write in the project |
| Build configuration | [Package.swift](Package.swift) | the two opt-in flags |

Useful commands:

```sh
make app && make audit                       # build clean, then verify
grep -rn 'write(to\|URLSession' Sources/     # every disk write and network call
lsof -nP -i -a -p "$(pgrep -x Dictator)"     # live sockets (expect none)
```

Questions, or requirements this does not yet meet, are welcome — several of
the protections described here exist because someone asked a pointed question
first.
