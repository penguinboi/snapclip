#!/bin/bash
# ABOUTME: Builds and installs the Snapclip capture app (macOS) into ~/Applications.
# ABOUTME: Produces a REAL signed Mach-O applet so macOS grants it Screen Recording and the grant persists.
set -euo pipefail

APP_NAME="Snapclip"
BUNDLE_ID="com.penguinboisoftware.snapclip"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)/src"

mkdir -p "$INSTALL_DIR"
rm -rf "$APP"

# --- Build a REAL Mach-O applet (this is the whole trick).
# A .app whose executable is a shell script has no Mach-O of its own — launchd runs
# /bin/bash, which has no grantable identity, so macOS never prompts for Screen
# Recording and silently denies every capture. An osacompile applet is a compiled
# binary that runs our capture script as a child, so TCC attributes the capture to
# THIS app's identity — which can be prompted for, granted, and (when Developer-ID
# signed) remembered across reboots.
AS_TMP="$(mktemp -t snapclip).applescript"
cat > "$AS_TMP" <<'APPLESCRIPT'
on run
	set myPath to POSIX path of (path to me)
	do shell script quoted form of (myPath & "Contents/Resources/snapclip.sh")
end run
APPLESCRIPT
osacompile -o "$APP" "$AS_TMP"
rm -f "$AS_TMP"

# --- Bundle the capture script inside the app (self-contained) ---
cp "$SRC_DIR/snapclip-macos.sh" "$APP/Contents/Resources/snapclip.sh"
chmod +x "$APP/Contents/Resources/snapclip.sh"

# --- Clean bundle id + agent app (no Dock bounce) ---
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace LSUIElement -bool true "$APP/Contents/Info.plist"

# --- Sign. A Developer ID identity makes the Screen Recording grant PERSIST across
# reboots (macOS anchors the TCC grant to the stable certificate). Ad-hoc still
# works (real Mach-O = grantable), but the grant may need re-approving after some
# reboots or macOS updates.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')"
if [ -n "$DEVID" ]; then
  echo "Signing with Developer ID: $DEVID"
  codesign --force --deep --sign "$DEVID" "$APP"
else
  echo "No Developer ID certificate found — signing ad-hoc (grant may need re-approval after reboots)."
  codesign --force --deep --sign - "$APP"
fi

# --- Register with LaunchServices ---
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

cat <<DONE

Installed: $APP
  ($([ -n "$DEVID" ] && echo "Developer ID signed — grant persists across reboots" || echo "ad-hoc signed — grant may need occasional re-approval"))

DONE

# Bind the hotkey. A failure here must not fail the install: the app itself is
# already working, only the shortcut would be missing, and the binder prints the
# manual steps when it cannot set it.
SNAPCLIP_APP="$APP" "$(cd "$(dirname "$0")" && pwd)/bind-hotkey-macos.sh" || true

cat <<DONE

Next step
---------
Trigger Snapclip once. macOS prompts "Snapclip wants to record the screen" -> Allow.
(One-time — the app has a real identity, so the grant sticks.)

Then: Cmd+Shift+1 -> drag a region (or Space to pick a window) -> the PNG path is
on your clipboard, ready to paste. Captures save to ~/Pictures/snapclip by default
(override in ~/.config/snapclip/config with:  SCREENSHOT_DIR=/some/path).
DONE
