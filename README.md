# Snapclip

A tiny screenshot hotkey that **captures any window** and **copies the file path to your clipboard** — ready to paste into whatever you're feeding screenshots to (an AI coding assistant, a chat, a bug report). One keystroke: capture, saved to a managed folder, path on your clipboard. No Desktop clutter.

Available for **macOS**, **Windows** and **Linux**. Each platform has its own implementation, because the hard part is a different problem on each. They share the capture folder, the `shot-<timestamp>.png` naming, the config file format, and the hotkey.

| Platform | Hotkey | Install | Bound for you |
|---|---|---|---|
| macOS | Cmd+Shift+1 | `./build.sh` | yes, via a Quick Action |
| Windows | Ctrl+Shift+1 | `install.ps1` | yes |
| Linux | Ctrl+Shift+1 | `./install-linux.sh` | no, depends on your desktop |

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

`build.sh` creates `~/Applications/Snapclip.app` (a signed Mach-O applet — Developer ID if you have one, else ad-hoc), binds Cmd+Shift+1 to it, and prints the one remaining step:

1. **Trigger it once** → macOS prompts *"Snapclip wants to record the screen"* → **Allow**.

Then: Cmd+Shift+1 → drag a region (or press Space to click a window) → the PNG path is on your clipboard.

### The hotkey binding

macOS has no way for a one-shot applet to claim a global shortcut, so `build.sh`
installs an Automator Quick Action into `~/Library/Services` and writes the
Cmd+Shift+1 shortcut into `pbs.plist`. It then reads the shortcut back and prints the
manual steps if macOS did not take it. A failed binding never fails the install: the
app still works, only the shortcut is missing.

macOS caches its services list, so a brand new Quick Action sometimes needs a logout
before the shortcut fires. To re-run or check the binding on its own:

```sh
./bind-hotkey-macos.sh            # bind it
./bind-hotkey-macos.sh --dry-run  # generate and lint, installing nothing
./bind-hotkey-macos.sh --verify   # report what is actually set
./bind-hotkey-macos.sh --unbind   # remove the Quick Action and its shortcut
```

If another service already owns Cmd+Shift+1, the binder refuses rather than taking
it: macOS does not arbitrate between two services on one shortcut, it picks a winner
and the loser stops working with no error. Take it deliberately with `--force`, or
put Snapclip somewhere else:

```sh
SNAPCLIP_KEY_EQUIVALENT='@$2' SNAPCLIP_HOTKEY_LABEL='Cmd+Shift+2' ./bind-hotkey-macos.sh
```

(`@` is Command, `$` Shift, `^` Control, `~` Option.)

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

That installs to `%LOCALAPPDATA%\Programs\Snapclip` and creates a Start Menu shortcut carrying a global hotkey. The default is `CTRL+SHIFT+1`, matching Cmd+Shift+1 on macOS (Cmd has no Windows equivalent, so it maps to Ctrl). Unlike the macOS side, this binding is applied for you. Choose your own:

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

## Linux

Linux has no permission gate and its capture tools are synchronous, so this is the
simplest of the three. The only real problem is that "Linux" is not one target.

`grim` and `slurp` speak the `wlr-screencopy` protocol, which sway, Hyprland and
river implement but GNOME and KDE deliberately do not. A Wayland version built only
on grim is broken for most desktop users. So Snapclip detects the display server and
the desktop, then picks a tool that actually works there:

| Session | Tool used |
|---|---|
| Wayland, GNOME | `gnome-screenshot` |
| Wayland, KDE | `spectacle` |
| Wayland, wlroots (sway, Hyprland, river) | `grim` + `slurp` |
| X11, any desktop | `maim`, else `scrot`, else `import` |

Clipboard is `wl-copy` under Wayland, `xclip` or `xsel` under X11. If nothing usable
is found, Snapclip exits with the exact package to install for your desktop rather
than failing quietly.

### Install

```sh
git clone https://github.com/penguinboi/snapclip.git
cd snapclip
./install-linux.sh
```

That installs to `~/.local/bin/snapclip` and prints how to bind Ctrl+Shift+1 for your
desktop. On sway that is one line in your config:

```
bindsym Ctrl+Shift+1 exec ~/.local/bin/snapclip
```

### What is actually verified

Tested in a clean Ubuntu 24.04 container against a real headless wlroots compositor
and a virtual X11 framebuffer:

- **X11 / maim / xclip** — captures a valid PNG, path reaches the clipboard
- **Wayland / grim / slurp / wl-copy** — captures a valid PNG cropped to the selected
  region, path reaches the clipboard
- Pruning removes old `shot-*.png` and leaves other files alone
- A cancelled selection writes no file, changes no clipboard, and exits 0

**Not yet verified on real hardware:** the GNOME (`gnome-screenshot`) and KDE
(`spectacle`) paths. Their invocations are unit-tested against stubs, but nobody has
run them on an actual GNOME or KDE desktop. Reports welcome.

### Tests

```sh
./tests/snapclip-linux.test.sh
```

## Finding your way around

Every platform answers `--help` with where its captures go, where its config lives,
and what the hotkey is:

```sh
snapclip --help                  # macOS, Linux
snapclip.ps1 -Help               # Windows
```

The first successful capture also introduces itself once, because the surprising part
is that the **path** lands on your clipboard rather than the image. After that it goes
back to a one-line confirmation. The marker that tracks this is
`~/.config/snapclip/.introduced`; delete it to see the introduction again.

## Configure

Captures go to `~/Pictures/snapclip` by default, on all three platforms. They read the same config file, `~/.config/snapclip/config` (which on Windows is `%USERPROFILE%\.config\snapclip\config`):

```sh
mkdir -p ~/.config/snapclip
echo 'SCREENSHOT_DIR=/some/where/else' > ~/.config/snapclip/config
# RETENTION_DAYS=7   # prune captures older than N days (default 7)
```

## License

MIT — see [LICENSE](LICENSE). Part of [Penguinboi Software](https://penguinboisoftware.com).
