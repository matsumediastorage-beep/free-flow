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

Two guarantees baked into the prompt and the code:

- **It only reformats.** It will never answer a question you dictate or act on
  an instruction inside the transcript.
- **It can never block you.** Timeout, no network, bad response, refusal — any
  failure pastes the raw transcript instead.

Add names, clients, and jargon under Settings → Vocabulary so proper nouns come
out spelled right.

---

## Development

```bash
swift build                  # compile
swift test                   # run the hotkey state machine tests
./scripts/build-app.sh       # debug bundle in ./build
./scripts/build-app.sh release --install
```

No Xcode required — this is a Swift Package plus a shell script that assembles
the `.app` bundle. Xcode's Command Line Tools are enough.

### Layout

```
Sources/Flow/
  Core/         hotkey state machine, audio capture, orchestration
  Transcription/ Parakeet engine behind a swappable protocol
  Formatting/   Claude and local cleanup passes
  Insertion/    clipboard save → paste → restore
  Storage/      history, settings, keychain
  UI/           overlay panel, dashboard, menu bar
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
