#!/usr/bin/env bash
# ABOUTME: Tests for the Linux Snapclip capture script.
# ABOUTME: Stubs the screenshot tools so backend selection and argument building are checked without them installed.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../src/snapclip-linux.sh
. "$SCRIPT_DIR/../src/snapclip-linux.sh"

PASSED=0
FAILED=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASSED=$((PASSED + 1))
        printf '  \033[32mPASS\033[0m  %s\n' "$name"
    else
        FAILED=$((FAILED + 1))
        printf '  \033[31mFAIL\033[0m  %s\n        expected [%s], got [%s]\n' "$name" "$expected" "$actual"
    fi
}

# Pretend a given set of tools is installed, for one call.
with_tools() {
    local available=" $1 " ; shift
    has() { [[ "$available" == *" $1 "* ]]; }
    "$@"
    unset -f has
    has() { command -v "$1" >/dev/null 2>&1; }
}

echo
echo "Capture backend selection"

check 'wlroots session picks grim' grim \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY= XDG_CURRENT_DESKTOP=sway with_tools 'grim slurp' detect_capture_backend)"

check 'GNOME Wayland prefers gnome-screenshot over grim' gnome-screenshot \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY= XDG_CURRENT_DESKTOP=GNOME with_tools 'grim slurp gnome-screenshot' detect_capture_backend)"

check 'KDE Wayland prefers spectacle over grim' spectacle \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY= XDG_CURRENT_DESKTOP=KDE with_tools 'grim slurp spectacle' detect_capture_backend)"

check 'GNOME Wayland falls back to grim when gnome-screenshot is absent' grim \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY= XDG_CURRENT_DESKTOP=GNOME with_tools 'grim slurp' detect_capture_backend)"

check 'grim is not chosen without slurp' none \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY= XDG_CURRENT_DESKTOP=sway with_tools 'grim' detect_capture_backend)"

check 'X11 session picks maim' maim \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools 'maim scrot' detect_capture_backend)"

check 'X11 falls back to scrot without maim' scrot \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools 'scrot' detect_capture_backend)"

check 'X11 falls back to import as a last resort' import \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools 'import' detect_capture_backend)"

check 'no session at all reports none' none \
  "$(WAYLAND_DISPLAY= DISPLAY= with_tools 'maim grim slurp' detect_capture_backend)"

check 'no tools reports none' none \
  "$(WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 with_tools '' detect_capture_backend)"

echo
echo "Clipboard backend selection"

check 'Wayland picks wl-copy' wl-copy \
  "$(WAYLAND_DISPLAY=wayland-0 with_tools 'wl-copy xclip' detect_clipboard_backend)"

check 'X11 picks xclip' xclip \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools 'xclip xsel' detect_clipboard_backend)"

check 'falls back to xsel without xclip' xsel \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools 'xsel' detect_clipboard_backend)"

check 'Wayland without wl-copy falls back to xclip under XWayland' xclip \
  "$(WAYLAND_DISPLAY=wayland-0 with_tools 'xclip' detect_clipboard_backend)"

check 'no clipboard tool reports none' none \
  "$(WAYLAND_DISPLAY= DISPLAY=:0 with_tools '' detect_clipboard_backend)"

echo
echo "Capture invocation (stubbed tools record their arguments)"

STUBS="$(mktemp -d)"
trap 'rm -rf "$STUBS"' EXIT
for tool in grim maim scrot gnome-screenshot spectacle import; do
    cat > "$STUBS/$tool" <<STUB
#!/usr/bin/env bash
printf '%s ' "\$@" > "$STUBS/$tool.args"
for arg in "\$@"; do case "\$arg" in --file=*) printf 'x' > "\${arg#--file=}" ;; *.png) printf 'x' > "\$arg" ;; esac; done
STUB
    chmod +x "$STUBS/$tool"
done
printf '#!/usr/bin/env bash\necho "10,20 300x200"\n' > "$STUBS/slurp"
chmod +x "$STUBS/slurp"
PATH="$STUBS:$PATH"

OUT="$STUBS/shot.png"

capture_region grim "$OUT"
check 'grim receives the geometry slurp reported' '-g 10,20 300x200 '"$OUT"' ' "$(cat "$STUBS/grim.args")"

capture_region maim "$OUT"
check 'maim runs in select mode' '--select --hidecursor '"$OUT"' ' "$(cat "$STUBS/maim.args")"

capture_region scrot "$OUT"
check 'scrot runs in select mode' '--select --overwrite '"$OUT"' ' "$(cat "$STUBS/scrot.args")"

capture_region gnome-screenshot "$OUT"
check 'gnome-screenshot runs in area mode' '--area --file='"$OUT"' ' "$(cat "$STUBS/gnome-screenshot.args")"

capture_region spectacle "$OUT"
check 'spectacle runs in region mode without its own notification' '--region --background --nonotify --output '"$OUT"' ' "$(cat "$STUBS/spectacle.args")"

check 'an unknown backend fails rather than capturing' 1 \
  "$(capture_region nonsense "$OUT" >/dev/null 2>&1; echo $?)"

echo
echo "Cancellation"

printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBS/slurp"
check 'a cancelled slurp selection aborts the capture' 1 \
  "$(capture_region grim "$OUT" >/dev/null 2>&1; echo $?)"

echo
printf '%d passed, %d failed\n\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
