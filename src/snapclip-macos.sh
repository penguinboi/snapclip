#!/bin/bash
# ABOUTME: Interactive screenshot, saved to a folder, with the file path copied to the clipboard.
# ABOUTME: Runs inside Snapclip's signed applet so the capture happens under a stable identity (see README).

# Save location. Override in ~/.config/snapclip/config with:  SCREENSHOT_DIR=/some/path
SCREENSHOT_DIR="$HOME/Pictures/snapclip"
RETENTION_DAYS=7
CONFIG="$HOME/.config/snapclip/config"
INTRO_MARKER="$HOME/.config/snapclip/.introduced"

usage() {
    cat <<EOF
Snapclip - capture a screenshot and copy its file path to the clipboard.

The clipboard receives the PATH to the PNG, not the image itself, so it can be
pasted straight into anything that reads files: an AI coding assistant, a chat,
a bug report.

Usage:
  snapclip            capture a region, or press Space to pick a window
  snapclip --help     show this

Hotkey:   Cmd+Shift+1
Captures: $SCREENSHOT_DIR
Config:   $CONFIG
            SCREENSHOT_DIR=/some/path
            RETENTION_DAYS=$RETENTION_DAYS

Rebind the hotkey with ./bind-hotkey-macos.sh, or check it with
./bind-hotkey-macos.sh --verify
EOF
}

# The applet has no terminal, so a one-time dialog is the only way a new user
# learns that it is the path on the clipboard rather than the image.
show_intro_once() {
    [ -f "$INTRO_MARKER" ] && return
    mkdir -p "$(dirname "$INTRO_MARKER")"
    : > "$INTRO_MARKER"
    osascript -e "display dialog \"Snapclip is set up.

The FILE PATH is now on your clipboard, not the image. Paste it anywhere that reads files.

Captures are saved to:
$SCREENSHOT_DIR

They are deleted after $RETENTION_DAYS days.\" with title \"Snapclip\" buttons {\"Got it\"} default button 1 with icon note" >/dev/null 2>&1
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac

[ -f "$CONFIG" ] && . "$CONFIG"

mkdir -p "$SCREENSHOT_DIR"

# Prune old captures so the folder doesn't grow forever.
find "$SCREENSHOT_DIR" -name 'shot-*.png' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null

FILEPATH="$SCREENSHOT_DIR/shot-$(date +%Y%m%d-%H%M%S).png"

# -i = interactive: drag a region, or press Space to click a window.
screencapture -i "$FILEPATH"

# Only act if a capture happened (user didn't press Escape).
if [ -f "$FILEPATH" ]; then
    printf '%s' "$FILEPATH" | pbcopy
    if [ -f "$INTRO_MARKER" ]; then
        osascript -e 'display notification "Path copied to clipboard" with title "Snapclip"' 2>/dev/null
    else
        show_intro_once
    fi
fi
