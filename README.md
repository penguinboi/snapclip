# macshot

A tiny macOS screenshot hotkey that **captures any window** and **copies the file path to your clipboard** — ready to paste into whatever tool you're feeding screenshots to (an AI coding assistant, a chat, a bug report).

It exists to solve one specific, maddening macOS problem: screenshot shortcuts wired through Automator or shell scripts **"sometimes" fail with a Screen Recording permission prompt depending on which app you're pointing at.** macshot fixes that permanently.

## The problem it solves

macOS gates screen capture behind the **Screen Recording** privacy permission. The catch: when a screenshot is triggered from an **Automator Quick Action / Service or a shell script**, macOS attributes the capture to the **frontmost app** — the very app you're trying to screenshot. So Chrome works, but the moment you point at an app that hasn't been granted Screen Recording (a new app, a password manager, a game launcher), the capture is blocked or comes out blank.

There's no single app to grant, because the responsible identity keeps changing to whatever's in front. It's whack-a-mole.

## The fix

Give the capture a **stable app identity**. macshot builds a tiny, ad-hoc-signed `.app` whose only job is to run `screencapture` under **its own** identity. You grant Screen Recording to **that one app, once** — and because Screen Recording permission is about the *capturing* app's right to record (not the captured app's consent), it can now grab **any** window: new apps, password managers, game launchers, anything. No more per-app toggles, no more prompts.

## Install

```sh
git clone https://github.com/penguinboi/macshot.git
cd macshot
./build.sh
```

`build.sh` creates `~/Applications/macshot.app` (self-contained, ad-hoc signed) and prints the two remaining one-time steps:

1. **Grant Screen Recording** to `macshot.app`:
   System Settings → Privacy & Security → Screen Recording & System Audio → **+** → `~/Applications/macshot.app` → toggle **on**.
2. **Bind a hotkey** to run `open "$HOME/Applications/macshot.app"` (an Automator Quick Action bound in System Settings → Keyboard → Keyboard Shortcuts → Services works well; so does any launcher).

Press the hotkey, drag a region (or press Space to click a window). The PNG path lands on your clipboard.

## Configure

Optional. By default captures go to `~/Pictures/macshot`. To change it, create `~/.config/macshot/config`:

```sh
mkdir -p ~/.config/macshot
echo 'SCREENSHOT_DIR=/some/where/else' > ~/.config/macshot/config
# RETENTION_DAYS=7   # prune captures older than N days (default 7)
```

## Why macOS only

Every moving part is Apple-specific: the `screencapture` tool, the TCC Screen Recording permission model, `.app` bundles, and Automator Services. There's no cross-platform equivalent, so this is macOS only by nature.

## License

MIT — see [LICENSE](LICENSE). Part of [Penguinboi Software](https://penguinboisoftware.com).
