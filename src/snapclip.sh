#!/bin/bash
# ABOUTME: Interactive screenshot, saved to a folder, with the file path copied to the clipboard.
# ABOUTME: Runs inside Snapclip's signed applet so the capture happens under a stable identity (see README).

# Save location. Override in ~/.config/snapclip/config with:  SCREENSHOT_DIR=/some/path
SCREENSHOT_DIR="$HOME/Pictures/snapclip"
RETENTION_DAYS=7
CONFIG="$HOME/.config/snapclip/config"
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
    osascript -e 'display notification "Path copied to clipboard" with title "Snapclip"' 2>/dev/null
fi
