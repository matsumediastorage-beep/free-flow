# Free Flow

Hold **Left Shift**, talk, release. Clean text appears wherever your cursor is —
Slack, Mail, a code editor, anywhere.

A native macOS dictation app in the mold of Wispr Flow, with the speech model
running on your Mac's Neural Engine instead of someone else's server.

- **Free and private.** Parakeet TDT v3 runs on-device via CoreML. Your voice
  never leaves the machine, and it works on a plane.
- **Fast.** ~100–200ms from key release to pasted text.
- **Actually clean.** An AI pass fixes words the speech model misheard (using
  your sentence, the text already before your cursor, and your dictionary),
  strips "um" and "uh", applies "no wait, Thursday" corrections, and punctuates.
  Claude Haiku when you add a key, Apple's on-device model for free otherwise.
- **Remembers everything.** Every dictation is saved, searchable, and one click
  from your clipboard, with every word the AI changed highlighted.

---

## Setup

### 1. One-time: create a signing identity

```bash
./scripts/make-signing-cert.sh
```

**Don't skip this.** macOS ties permissions to an app's code signature. Without a
stable identity, every rebuild looks like a brand new app and macOS silently
forgets your permissions — the hotkey just stops working with no error. This
script creates a self-signed identity once so grants survive rebuilds.

### 2. Build and install

```bash
./scripts/build-app.sh release --install
```

Installs to `/Applications/Flow.app`. Keep it there — macOS also keys
permissions to the app's path.

### 3. Grant permissions

Launch Flow and it opens a setup window listing what's missing. Each row has a
button that takes you to the right page in System Settings.

| Permission | Why |
|---|---|
| **Accessibility** | Pastes text into whatever app you're using |
| **Input Monitoring** | Notices when you hold Left Shift |
| **Microphone** | Hears you |

macOS requires a human to flip these switches — no app can grant them for you.

### 4. First launch downloads the model

About 600MB of Parakeet weights, once. The menu bar shows progress. After that
it works offline forever.

Every launch after that loads the four CoreML models side by side (not one
after another) and runs one throwaway inference so CoreML specialises the graph.
It happens silently in the background; the hotkey works immediately, and a
dictation made in those first seconds simply waits for the model. Paying it at launch, on silence, is what
keeps your first real dictation as fast as every one after it. Turn on **Launch
at login** and you never see it at all.

---

## Using it

| Action | Result |
|---|---|
| **Hold Left Shift** (~300ms), speak, release | Dictates and pastes |
| **Left Shift + any key** | Types normally — never triggers |
| **Double-tap Left Shift** | Hands-free mode; tap again to stop |
| **Any key while recording** | Cancels |
| **Menu bar → Dashboard** | History, stats, and settings |

### Why Left Shift doesn't break your typing

Shift is also how you type capitals, so a naive implementation would fire on
every capital letter. Three rules prevent that:

1. The event tap is **listen-only** and never consumes the event, so Shift keeps
   behaving exactly like Shift.
2. Nothing happens until the key is held **alone for 300ms**.
3. Pressing **any other key** during that window aborts instantly.

So `Shift+A` types `A`, a normal capitalized sentence types normally, and a
deliberate hold starts dictation. This is covered by tests — see
`Tests/FlowTests/HotkeyStateMachineTests.swift`.

Prefer a different key? Settings → Dictation key. Right Shift, Right Option, and Fn have zero
typing conflict.

---

## AI cleanup

Parakeet writes what words *sound* like, so it produces "Blaire" for Blair,
"super base" for Supabase, and "there" for "their". The AI pass is what turns
that into what you meant, the way Wispr Flow does:

```
You say:  "um so I wanted to to let you know that there meeting is on tuesday no wait thursday"
Result:   "I wanted to let you know that their meeting is on Thursday."
```

It uses three clues to fix a misheard word:

1. **The sentence itself.** Which word makes sense here.
2. **The text before your cursor**, read through Accessibility (Settings → *Use
   the text around my cursor*). If the email above says "Hi Blair,", a later
   "blare" is obviously Blair. Password fields are never read.
3. **Your Dictionary** (sidebar → Dictionary). Names, clients and jargon get
   mapped onto your spelling whenever something sounds like them.

Two styles: **Light** fixes mistakes and otherwise keeps your exact words;
**Polished** (default) also smooths grammar and run-on sentences.

| Engine | Cost | Quality | Needs |
|---|---|---|---|
| **Claude Haiku 4.5** | ~$0.10–1/month | Best at mishears and messy speech | Anthropic API key (Settings → AI cleanup) |
| **Apple on-device** | Free | Good; catches obvious mishears | macOS 26 + Apple Intelligence on |
| **Basic** | Free | Removes um/uh, adds a period | Nothing (automatic fallback) |

The Claude connection is opened while you're still talking, so the network
handshake never lands in the wait after you release the key. If Claude fails
fast (offline, bad key) Flow uses Apple's model instead; if it times out it
pastes basic cleanup rather than making you wait twice.

Two guarantees baked into the prompt and the code:

- **It only edits.** It will never answer a question you dictate or act on
  an instruction inside the transcript.
- **It can never block you.** Timeout, no network, bad response, refusal — any
  failure still pastes your text.

Settings shows whether the last cleanup actually worked, and **Test cleanup
now** runs a deliberately messy sentence through it and shows the result.

---

---

## Installing it on someone else's Mac

Send them **https://matsumediastorage-beep.github.io/free-flow/** — a page with
a copy button and one command:

```bash
curl -fsSL https://raw.githubusercontent.com/matsumediastorage-beep/free-flow/main/install.sh | bash
```

The installer checks the machine, pulls the latest release, puts `Flow.app` in
`/Applications`, and launches it. Then macOS asks for the three permissions —
that part is unavoidable and has to be done by hand.

### Why it isn't a double-click

Free Flow is signed with a **self-signed certificate**, not an Apple Developer
ID, and it is **not notarized**. macOS flags anything a browser downloads with
`com.apple.quarantine`, and Gatekeeper refuses to open a quarantined app Apple
hasn't notarized — so shipping the `.dmg` by email or Slack gets everyone
*"Apple could not verify Flow is free of malware"*, and on macOS 15+ the old
right-click→Open trick no longer clears it.

`curl` isn't quarantine-aware, so a file they fetch never gets the
flag. The installer removes no security check; it just never picks one up. The
tradeoff is honest and worth stating: **your team trusts you instead of Apple.**
Reasonable for an internal tool, not for public distribution.

### Making it a real double-click

`./scripts/notarize.sh` does the whole job — hardened runtime, Developer ID
signing, submission to Apple, stapling — and refuses to run without a
certificate. It needs an [Apple Developer Program](https://developer.apple.com)
membership ($99/year). Setup steps are at the top of that script. With one,
`FreeFlow-x.y.z.dmg` opens with a genuine double-click on any Mac, no Terminal.

The App Store is not an option: Flow uses the Accessibility APIs to paste into
any app, and those are incompatible with the App Sandbox.

### Cutting a release

```bash
./scripts/build-app.sh release        # build the bundle
./scripts/package-dmg.sh              # optional, for a drag-install image
./scripts/release.sh 0.2.0            # zip, tag, and publish to GitHub
```

### What every machine needs

| | |
|---|---|
| **Apple Silicon** | M-series only. The model runs on the Neural Engine; there is no Intel build. |
| **macOS 14+** | Enforced by the installer. |
| **macOS 26 + Apple Intelligence** | Only for the free on-device cleanup. Below that, Flow falls back to basic local cleanup, or Claude if a key is set. |
| **~600MB disk** | Speech model, downloaded once per machine. |
| **Three permissions** | Accessibility, Input Monitoring, Microphone. Granted by hand, per machine. |

---

## Development

```bash
./scripts/update.sh          # build, test, install, relaunch, time the launch
./scripts/update.sh check    # build + tests only
swift build                  # compile
swift run FlowTests          # run the test suite
./scripts/build-app.sh       # debug bundle in ./build
./scripts/build-app.sh release --install
```

No Xcode required — this is a Swift Package plus a shell script that assembles
the `.app` bundle. Xcode's Command Line Tools are enough.

**Tests are a plain executable, not `swift test`.** The Command Line Tools ship
an unusable swift-testing (`_Testing_Foundation` has no module interface) and no
XCTest at all, so `swift test` needs a full ~10GB Xcode install. The logic that
decides whether you dictated or typed a capital letter is too important to only
be checkable on a machine with Xcode, so the suite runs against a ~60-line
harness in `Sources/FlowTests/TestSuite.swift` and works anywhere.

### Layout

```
Sources/Flow/       @main shim — starts NSApplication, nothing else
Sources/FlowKit/    the whole app, as a library so tests can link it
  Core/             hotkey state machine, audio capture, orchestration
  Transcription/    Parakeet engine behind a swappable protocol
  Formatting/       Claude and local cleanup passes
  Insertion/        clipboard save → paste → restore
  Storage/          history, settings, keychain
  UI/               overlay panel, dashboard, menu bar
Sources/FlowTests/  the runner and its tests
```

The pieces worth knowing:

- **`Core/HotkeyStateMachine.swift`** — the typing-guard logic, deliberately
  separated from CoreGraphics so it can be tested exhaustively.
- **`Core/AudioRecorder.swift`** — pre-warms the mic during the 300ms guard and
  keeps a pre-roll buffer, so the first syllable is never clipped.
- **`Insertion/TextInserter.swift`** — saves your clipboard, pastes, and restores
  it. Forces the modifier flags on the synthetic ⌘V so a still-held Shift can't
  turn it into ⌘⇧V.

### Troubleshooting

**Hotkey does nothing, but Accessibility is checked.** Stale TCC grant from an
older build:

```bash
./scripts/reset-tcc.sh
```

Then remove Flow from System Settings → Privacy & Security → Accessibility with
the `−` button and re-add it. If this happens on every rebuild, you skipped
`make-signing-cert.sh`.

**Text pastes into the wrong place.** The overlay is non-activating and never
takes focus, so this usually means the target app was already losing focus.

---

## Limitations

- **Apple Silicon only** (M-series). The model runs on the Neural Engine.
- **English and 24 other European languages.** Parakeet v3 does not cover
  Japanese — that needs a different model.
- **Not sandboxed.** The Accessibility APIs that make universal pasting work are
  incompatible with the App Sandbox.
