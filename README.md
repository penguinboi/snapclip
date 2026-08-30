# Snapclip

A tiny screenshot hotkey that **captures any window** and **copies the file path to your clipboard** — ready to paste into whatever you're feeding screenshots to (an AI coding assistant, a chat, a bug report). One keystroke: capture, saved to a managed folder, path on your clipboard. No Desktop clutter.

Available for **macOS** and **Windows**. Each platform has its own implementation, because the hard part is a different problem on each. They share the capture folder, the `shot-<timestamp>.png` naming, and the config file format.

## macOS

macOS gates screen capture behind the **Screen Recording** permission, and wiring a screenshot to a hotkey the obvious way is a trap:

- Trigger `screencapture` from an **Automator Quick Action or a shell script**, and macOS attributes the capture to the **frontmost app** — the very window you're shooting. So it works on apps you've granted and silently fails on ones you haven't. Whack-a-mole.
- Try to fix that with a wrapper **`.app` whose executable is a shell script**, and it's *worse*: that app has no compiled binary of its own, so the running process is `/bin/bash` — a generic system interpreter with no grantable identity. macOS **never even prompts**, and every capture is silently denied.

### The fix

Snapclip builds a **real, compiled applet** (a Mach-O binary via `osacompile`), code-signed, whose only job is to run `screencapture` under **its own stable identity**. Because it's a genuine app:

- macOS **prompts** for Screen Recording the first time, and you grant it **once**.
- Screen Recording permission is about the *capturing* app's right to record — not the captured window's consent — so it can then grab **any** window: new apps, password managers, game launchers, anything.
- Signed with a **Developer ID** certificate, the grant **persists across reboots** (macOS anchors it to the stable certificate). Ad-hoc signing also works but the grant may need occasional re-approval.

### Install

```sh
git clone https://github.com/penguinboi/snapclip.git
cd snapclip
./build.sh
```

`build.sh` creates `~/Applications/Snapclip.app` (a signed Mach-O applet — Developer ID if you have one, else ad-hoc) and prints the remaining one-time steps:

1. **Bind a hotkey** to run `open "$HOME/Applications/Snapclip.app"` — an Automator Quick Action (Run Shell Script) bound in System Settings → Keyboard → Keyboard Shortcuts → Services works well; so does any launcher.
2. **Trigger it once** → macOS prompts *"Snapclip wants to record the screen"* → **Allow**.

Then: hotkey → drag a region (or press Space to click a window) → the PNG path is on your clipboard.

## Windows

Windows puts no permission gate on screen capture, so none of the applet and signing machinery above is needed here. The hard part is a different one.

The built-in snip overlay (`ms-screenclip:`, what Win+Shift+S opens) is good, and reusing it beats drawing our own. But it returns its result through the **clipboard**, asynchronously: no exit code, no signal that you pressed Escape, and no way to tell its image apart from one that was already sitting there.

So Snapclip records the **clipboard sequence number** before opening the overlay and watches for it to change. That distinguishes a real capture from a cancelled one, and from text you happened to copy on the way. It then saves the image itself and swaps the clipboard over to the path. Cancel the snip and your clipboard is left exactly as it was.

### Install

```powershell
git clone https://github.com/penguinboi/snapclip.git
cd snapclip
pwsh -ExecutionPolicy Bypass -File .\install.ps1
```

That installs to `%LOCALAPPDATA%\Programs\Snapclip` and creates a Start Menu shortcut carrying a global hotkey, `CTRL+ALT+S` by default. Choose your own:

```powershell
pwsh -ExecutionPolicy Bypass -File .\install.ps1 -Hotkey "CTRL+SHIFT+4"
```

Then: hotkey → drag a region (or pick a whole window from the overlay toolbar) → the PNG path is on your clipboard. There is no permission prompt and nothing to grant.

Two things worth knowing:

- Turn **off** Snipping Tool's "Automatically save original screenshots" (Snipping Tool → Settings). Otherwise every capture is stored twice, once by Windows in `Pictures\Screenshots` and once by Snapclip. Duplicate clutter is the thing this tool exists to prevent.
- The shortcut launches through `wscript.exe` rather than calling PowerShell directly. That is what stops a console window flashing on screen every time you take a shot.

Uninstall by deleting `%LOCALAPPDATA%\Programs\Snapclip` and the `Snapclip` shortcut in the Start Menu.

### Tests

```powershell
pwsh -STA -ExecutionPolicy Bypass -File .\tests\snapclip.tests.ps1
```

Note that the clipboard tests use the real clipboard, so they overwrite whatever is currently on it.

## Configure

Captures go to `~/Pictures/snapclip` by default, on both platforms. Both read the same config file, `~/.config/snapclip/config` (which on Windows is `%USERPROFILE%\.config\snapclip\config`):

```sh
mkdir -p ~/.config/snapclip
echo 'SCREENSHOT_DIR=/some/where/else' > ~/.config/snapclip/config
# RETENTION_DAYS=7   # prune captures older than N days (default 7)
```

## License

MIT — see [LICENSE](LICENSE). Part of [Penguinboi Software](https://penguinboisoftware.com).
