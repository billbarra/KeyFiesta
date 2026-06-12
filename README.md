# 🎉 KeyFiesta

**English** | [简体中文](README.zh-CN.md)

A macOS menu-bar toy that sprays emoji fireworks/confetti at your text cursor and plays a random
silly sound on every keystroke.

Works with every input method (Pinyin, Wubi, any third-party IME) — it listens to keystrokes, not
to the input method. Written in native Swift: **0.7 MB** installed, ~**20 MB** RAM, near **0% CPU**
when idle.

## ✨ Features

- Emoji particles burst **at the text caret** on every keystroke (confetti 🎉🎊🎀✨🎈 / fireworks 🎆🎇💥⭐🌟)
- 12 procedurally-synthesized cartoon sound effects (boing, quack, horn, slide whistle…), 8-voice pool so it never clips
- Menu-bar toggles for effects / sound / volume (3 levels) / launch-at-login
- Auto-silent in password fields; shortcuts like ⌘C don't trigger it
- Zero idle cost: the audio engine pauses when you stop typing and never blocks system sleep

## 📦 Install

> This is a self-signed app (no $99/yr Apple Developer signature), so the first launch needs one manual approval.

1. Download `KeyFiesta.dmg` from [Releases](../../releases), open it, and drag **KeyFiesta** into **Applications**.
2. Double-click KeyFiesta in Applications — macOS blocks it ("cannot verify"); click **Done**.
3. Open **System Settings → Privacy & Security**, scroll to the security notice, click **Open Anyway**, authenticate, then click **Open**.
   - On macOS 13/14 you can instead right-click the app → **Open** → **Open**.
   - Or one line in Terminal: `xattr -dr com.apple.quarantine /Applications/KeyFiesta.app`
4. On first launch it asks for Accessibility: **System Settings → Privacy & Security → Accessibility → enable KeyFiesta**.
5. After you grant it, the app **relaunches itself once** (macOS only enables Accessibility queries after a process restart) — this is expected. The 🎉 menu-bar icon means it's ready.

Why Accessibility: to sense "a key was pressed" and to locate the text caret. It **never reads any
key content** (see below).

## 🔒 Privacy

- **Never reads, records, or transmits any keystroke content.** The code only treats "a key went down" as a cue to fire.
- No network access, no disk writes (except menu settings in UserDefaults).
- All source is in `Sources/KeyFiesta/` — a few hundred lines, easy to audit.

## 🎯 Cursor accuracy per app

| Category | Accuracy |
|---|---|
| Notes / Safari / Mail / Chrome / VS Code / Claude desktop / Obsidian and most apps | **character-precise** |
| Chinese Pinyin composition (located via the IME candidate window) | roughly on the caret |
| **WeChat** | **no effects** |

WeChat draws its own UI and exposes **nothing** about the caret to the system (every lookup/translation
tool on macOS falls back to the mouse position inside WeChat). Rather than fire in the wrong place,
KeyFiesta detects WeChat and stays quiet. Details in the [design doc](docs/superpowers/specs/2026-06-12-keyfiesta-design.md) (Chinese).

## 🛠 Build from source

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`) — no full Xcode needed:

```bash
python3 scripts/make_sounds.py   # generate sounds (already committed, can skip)
./scripts/build.sh               # → dist/KeyFiesta.app and .zip
./scripts/make_dmg.sh            # → dist/KeyFiesta.dmg
```

The build script ad-hoc signs by default (you must re-grant Accessibility after every rebuild). If a
self-signed certificate named `KeyFiesta Local Signer` exists in your keychain, it uses that instead —
the signing identity stays stable, so the grant survives rebuilds (recommended for development;
see the comment in `scripts/build.sh` for how to create the cert).

## ⚙️ How it works

Global keyDown monitor (Accessibility, passive — never intercepts) → caret location on a background
serial queue → particles via `CAEmitterLayer` (GPU) in a transparent, click-through, always-on-top
window + sounds via an 8-voice `AVAudioEngine` pool. Caret location degrades through several channels:

1. Classic AX (`kAXBoundsForRange`) — native apps
2. **TextMarker channel** (`AXSelectedTextMarkerRange` → anchor-wash → `AXBoundsForTextMarkerRange`) —
   character-precise in Chromium/Electron (Claude/Obsidian/browsers); the same private channel VoiceOver uses
3. IME candidate window + keystroke count — Chinese composition
4. Mouse position — fallback

## 🎵 Sound credits

All 12 sound effects are synthesized by `scripts/make_sounds.py` — original work, distribute freely.

## 🙏 Credits

Inspired by the typing effect in [WonderPen](https://www.tominlab.com/en/wonderpen).

## 📄 License

[MIT](LICENSE)
