# Matsu Flow

Hold **Left Shift**, talk, release. Clean text appears wherever your cursor is —
Slack, Mail, a code editor, anywhere.

A native macOS dictation app in the mold of Wispr Flow, with the speech model
running on your Mac's Neural Engine instead of someone else's server.

- **Free and private.** Parakeet TDT v3 runs on-device via CoreML. Your voice
  never leaves the machine, and it works on a plane.
- **Fast.** ~100–200ms from key release to pasted text.
- **Actually clean.** An optional Claude Haiku pass strips "um" and "uh", adds
  punctuation, and formats lists — with a hard 1.5s timeout that falls back to
  the raw transcript, so it can never make you wait.
- **Remembers everything.** Every dictation is saved, searchable, and one click
  from your clipboard.

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

Every launch after that still loads those weights and runs one throwaway
inference to make CoreML compile and specialise the graph — a few seconds during
which the menu bar reads *Warming up*. Paying it at launch, on silence, is what
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

## AI cleanup (optional)

Without a key, Flow does conservative local cleanup (removes standalone "um" and
"uh", capitalizes, adds a final period).

With an Anthropic API key — Dashboard → Settings → AI cleanup — you get the real
thing:

```
You say:  "um so like send me the uh the file tomorrow ok"
Result:   "Send me the file tomorrow."
```

It uses Claude Haiku 4.5, costs roughly $0.10/month at typical use, and adds
~250ms. The key is stored in your **Keychain**, never in a plaintext file.

The wait scales with what you said: about 1.2s for a phrase, up to 5s for a long
paragraph. A flat budget meant long dictations — the ones cleanup helps most —
were the ones that always timed out and fell back to raw text.

Settings shows whether the last cleanup actually worked, and a **Test cleanup
now** button sends one throwaway request on demand. Failures are silent by
design so they can never block a paste, which otherwise makes a bad key look
identical to "nothing needed changing".

Two guarantees baked into the prompt and the code:

- **It only reformats.** It will never answer a question you dictate or act on
  an instruction inside the transcript.
- **It can never block you.** Timeout, no network, bad response, refusal — any
  failure pastes the raw transcript instead.

Add names, clients, and jargon under Settings → Vocabulary so proper nouns come
out spelled right.

---

---

## Installing it on someone else's Mac

Send them **https://matsumediastorage-beep.github.io/matsu-flow/** — a page with
a copy button and one command:

```bash
curl -fsSL https://raw.githubusercontent.com/matsumediastorage-beep/matsu-flow/main/install.sh | bash
```

The installer checks the machine, pulls the latest release, puts `Flow.app` in
`/Applications`, and launches it. Then macOS asks for the three permissions —
that part is unavoidable and has to be done by hand.

### Why it isn't a double-click

Matsu Flow is signed with a **self-signed certificate**, not an Apple Developer
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
`MatsuFlow-x.y.z.dmg` opens with a genuine double-click on any Mac, no Terminal.

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
