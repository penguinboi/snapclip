#!/usr/bin/env bash
# ABOUTME: Interactive screenshot, saved to a folder, with the file path copied to the clipboard.
# ABOUTME: Picks the capture and clipboard tools that match the running display server and desktop.

set -uo pipefail

# Save location. Override in ~/.config/snapclip/config with:  SCREENSHOT_DIR=/some/path
SCREENSHOT_DIR="$HOME/Pictures/snapclip"
RETENTION_DAYS=7
CONFIG="$HOME/.config/snapclip/config"
INTRO_MARKER="$HOME/.config/snapclip/.introduced"

has() { command -v "$1" >/dev/null 2>&1; }

is_wayland() { [ -n "${WAYLAND_DISPLAY:-}" ]; }
is_x11()     { [ -n "${DISPLAY:-}" ]; }

# Which desktop we are on decides the capture tool as much as the display server
# does: grim and slurp speak wlr-screencopy, which sway, Hyprland and river
# implement but GNOME and KDE do not. Those two need their own tools.
detect_capture_backend() {
    if is_wayland; then
        case "${XDG_CURRENT_DESKTOP:-}" in
            *GNOME*) has gnome-screenshot && { echo gnome-screenshot; return; } ;;
            *KDE*)   has spectacle        && { echo spectacle;        return; } ;;
        esac
        has grim && has slurp && { echo grim; return; }
        has gnome-screenshot && { echo gnome-screenshot; return; }
        has spectacle        && { echo spectacle;        return; }
    fi

    if is_x11; then
        has maim             && { echo maim;             return; }
        has scrot            && { echo scrot;            return; }
        has gnome-screenshot && { echo gnome-screenshot; return; }
        has spectacle        && { echo spectacle;        return; }
        has import           && { echo import;           return; }
    fi

    echo none
}

detect_clipboard_backend() {
    if is_wayland && has wl-copy; then echo wl-copy; return; fi
    if has xclip; then echo xclip; return; fi
    if has xsel;  then echo xsel;  return; fi
    echo none
}

# Every one of these selects a region interactively and writes a PNG to $2.
# Cancellation is reported inconsistently across them (gnome-screenshot exits 0
# after an escape), so the caller judges success by the file, not the status.
capture_region() {
    local backend="$1" path="$2" geometry
    case "$backend" in
        grim)
            geometry="$(slurp)" || return 1
            grim -g "$geometry" "$path"
            ;;
        maim)             maim --select --hidecursor "$path" ;;
        scrot)            scrot --select --overwrite "$path" ;;
        gnome-screenshot) gnome-screenshot --area --file="$path" ;;
        spectacle)        spectacle --region --background --nonotify --output "$path" ;;
        import)           import "$path" ;;
        *)                return 1 ;;
    esac
}

copy_to_clipboard() {
    local backend="$1" text="$2"
    case "$backend" in
        # xclip and xsel must keep running to serve the X selection, so they
        # background themselves and outlive this script by design.
        wl-copy) printf '%s' "$text" | wl-copy ;;
        xclip)   printf '%s' "$text" | xclip -selection clipboard ;;
        xsel)    printf '%s' "$text" | xsel --input --clipboard ;;
        *)       return 1 ;;
    esac
}

notify() {
    if has notify-send; then
        notify-send --app-name=Snapclip --icon=camera-photo "Snapclip" "$1"
    else
        # The path is already on the clipboard, so a missing notifier is not fatal,
        # but it should still say so rather than vanish.
        printf 'snapclip: %s (install libnotify-bin for desktop notifications)\n' "$1" >&2
    fi
}

report_missing_tools() {
    cat >&2 <<EOF
snapclip: no usable screenshot tool for this session.

  Session: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}  DISPLAY=${DISPLAY:-unset}  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset}

Install one of these, matching your desktop:

  sway, Hyprland, river   sudo apt install grim slurp wl-clipboard
  GNOME (Wayland)         sudo apt install gnome-screenshot wl-clipboard
  KDE (Wayland)           sudo apt install kde-spectacle wl-clipboard
  any X11 desktop         sudo apt install maim xclip
EOF
}

usage() {
    cat <<EOF
Snapclip - capture a screenshot and copy its file path to the clipboard.

The clipboard receives the PATH to the PNG, not the image itself, so it can be
pasted straight into anything that reads files: an AI coding assistant, a chat,
a bug report.

Usage:
  snapclip            capture a region interactively
  snapclip --help     show this

Hotkey:   Ctrl+Shift+1, if you bound one (see install-linux.sh)
Captures: $SCREENSHOT_DIR
Config:   $CONFIG
            SCREENSHOT_DIR=/some/path
            RETENTION_DAYS=$RETENTION_DAYS

This session would use: $(detect_capture_backend) for capture, $(detect_clipboard_backend) for clipboard
EOF
}

# Said once, because "the path, not the image" is the surprising part and there is
# no other moment to explain it.
show_intro_once() {
    [ -f "$INTRO_MARKER" ] && return 1
    mkdir -p "$(dirname "$INTRO_MARKER")"
    : > "$INTRO_MARKER"
    local body="The FILE PATH is on your clipboard, not the image.
Captures are saved to $SCREENSHOT_DIR and deleted after $RETENTION_DAYS days.
Run 'snapclip --help' for more."
    if has notify-send; then
        notify-send --app-name=Snapclip --icon=camera-photo "Snapclip is set up" "$body"
    fi
    printf 'Snapclip is set up.\n%s\n' "$body" >&2
    return 0
}

main() {
    case "${1:-}" in
        --help|-h) usage; return 0 ;;
    esac

    [ -f "$CONFIG" ] && . "$CONFIG"

    local capture_backend clipboard_backend filepath
    capture_backend="$(detect_capture_backend)"
    clipboard_backend="$(detect_clipboard_backend)"

    if [ "$capture_backend" = none ] || [ "$clipboard_backend" = none ]; then
        report_missing_tools
        exit 1
    fi

    mkdir -p "$SCREENSHOT_DIR"

    # Prune old captures so the folder doesn't grow forever.
    find "$SCREENSHOT_DIR" -name 'shot-*.png' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null

    filepath="$SCREENSHOT_DIR/shot-$(date +%Y%m%d-%H%M%S).png"
    capture_region "$capture_backend" "$filepath"

    # A cancelled capture leaves no file, or an empty one. Either way, say nothing
    # and leave the clipboard alone.
    if [ -s "$filepath" ]; then
        copy_to_clipboard "$clipboard_backend" "$filepath"
        show_intro_once || notify "Path copied to clipboard"
        printf '%s\n' "$filepath"
    else
        rm -f "$filepath"
    fi
}

# Sourcing loads the functions for the tests; running the file captures.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
