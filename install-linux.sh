#!/usr/bin/env bash
# ABOUTME: Installs the Linux Snapclip capture script into ~/.local/bin.
# ABOUTME: Checks the tools the running session needs, then prints hotkey steps for the detected desktop.
set -uo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)/src"
INSTALL_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
TARGET="$INSTALL_DIR/snapclip"

mkdir -p "$INSTALL_DIR"
install -m 755 "$SRC_DIR/snapclip-linux.sh" "$TARGET"
echo "Installed: $TARGET"

# Reuse the script's own detection so the installer and the tool always agree.
. "$SRC_DIR/snapclip-linux.sh"

capture="$(detect_capture_backend)"
clipboard="$(detect_clipboard_backend)"
echo "Capture tool: $capture"
echo "Clipboard tool: $clipboard"

if [ "$capture" = none ] || [ "$clipboard" = none ]; then
    echo
    report_missing_tools
    exit 1
fi

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) echo; echo "Note: $INSTALL_DIR is not on your PATH. Add it to your shell profile." ;;
esac

cat <<EOF

Next step: bind a hotkey to run
    $TARGET

Cmd+Shift+1 on macOS and Ctrl+Shift+1 on Windows, so Ctrl+Shift+1 keeps things
consistent. Where you set it depends on your desktop:

  GNOME     Settings -> Keyboard -> View and Customize Shortcuts -> Custom Shortcuts
            or: gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings ...
  KDE       System Settings -> Shortcuts -> Add Command
  sway      bindsym Ctrl+Shift+1 exec $TARGET
  Hyprland  bind = CTRL SHIFT, 1, exec, $TARGET
  XFCE      Settings -> Keyboard -> Application Shortcuts
  i3        bindsym Ctrl+Shift+1 exec --no-startup-id $TARGET

Captures save to \$HOME/Pictures/snapclip by default.
Override in ~/.config/snapclip/config with:  SCREENSHOT_DIR=/some/path
EOF
