# Snapclip

A tiny screenshot hotkey that **captures any window** and **copies the file path to your clipboard** — ready to paste into whatever you're feeding screenshots to (an AI coding assistant, a chat, a bug report). One keystroke: capture, saved to a managed folder, path on your clipboard. No Desktop clutter.

This is the **macOS** version. (Snapclip is the brand — Linux/Windows versions can follow under the same name.)

## The problem it solves (macOS)

macOS gates screen capture behind the **Screen Recording** permission, and wiring a screenshot to a hotkey the obvious way is a trap:

- Trigger `screencapture` from an **Automator Quick Action or a shell script**, and macOS attributes the capture to the **frontmost app** — the very window you're shooting. So it works on apps you've granted and silently fails on ones you haven't. Whack-a-mole.
- Try to fix that with a wrapper **`.app` whose executable is a shell script**, and it's *worse*: that app has no compiled binary of its own, so the running process is `/bin/bash` — a generic system interpreter with no grantable identity. macOS **never even prompts**, and every capture is silently denied.

## The fix

Snapclip builds a **real, compiled applet** (a Mach-O binary via `osacompile`), code-signed, whose only job is to run `screencapture` under **its own stable identity**. Because it's a genuine app:

- macOS **prompts** for Screen Recording the first time, and you grant it **once**.
- Screen Recording permission is about the *capturing* app's right to record — not the captured window's consent — so it can then grab **any** window: new apps, password managers, game launchers, anything.
- Signed with a **Developer ID** certificate, the grant **persists across reboots** (macOS anchors it to the stable certificate). Ad-hoc signing also works but the grant may need occasional re-approval.

## Install

```sh
git clone https://github.com/penguinboi/snapclip.git
cd snapclip
./build.sh
```

`build.sh` creates `~/Applications/Snapclip.app` (a signed Mach-O applet — Developer ID if you have one, else ad-hoc) and prints the remaining one-time steps:

1. **Bind a hotkey** to run `open "$HOME/Applications/Snapclip.app"` — an Automator Quick Action (Run Shell Script) bound in System Settings → Keyboard → Keyboard Shortcuts → Services works well; so does any launcher.
2. **Trigger it once** → macOS prompts *"Snapclip wants to record the screen"* → **Allow**.

Then: hotkey → drag a region (or press Space to click a window) → the PNG path is on your clipboard.

## Configure

Captures go to `~/Pictures/snapclip` by default. To change it, create `~/.config/snapclip/config`:

```sh
mkdir -p ~/.config/snapclip
echo 'SCREENSHOT_DIR=/some/where/else' > ~/.config/snapclip/config
# RETENTION_DAYS=7   # prune captures older than N days (default 7)
```

## License

MIT — see [LICENSE](LICENSE). Part of [Penguinboi Software](https://penguinboisoftware.com).
