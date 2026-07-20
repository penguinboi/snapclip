#!/bin/bash
# ABOUTME: Builds and installs the macshot .app (a stable-identity screenshot capturer) into ~/Applications.
# ABOUTME: The app bundles and runs macshot.sh under its OWN identity, so it can capture any window once granted Screen Recording.
set -euo pipefail

APP_NAME="macshot"
BUNDLE_ID="com.penguinboisoftware.macshot"
INSTALL_DIR="$HOME/Applications"
APP="$INSTALL_DIR/$APP_NAME.app"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)/src"

mkdir -p "$INSTALL_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# --- Info.plist (LSUIElement = agent app, no Dock icon) ---
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>launcher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# --- Bundle the capture script + a launcher that runs it from inside the bundle ---
cp "$SRC_DIR/macshot.sh" "$APP/Contents/Resources/macshot.sh"
chmod +x "$APP/Contents/Resources/macshot.sh"
cat > "$APP/Contents/MacOS/launcher" <<'STUB'
#!/bin/bash
DIR="$(cd "$(dirname "$0")/../Resources" && pwd)"
exec "$DIR/macshot.sh"
STUB
chmod +x "$APP/Contents/MacOS/launcher"

# --- Ad-hoc codesign: gives the app a stable identity so its Screen Recording grant sticks ---
codesign --force --sign - "$APP"

# --- Register with LaunchServices so `open` and TCC recognize it ---
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

cat <<DONE

Installed: $APP

Next steps
----------
1. Grant Screen Recording permission to "$APP_NAME" (this is the one-time fix that lets it capture any window):
   System Settings -> Privacy & Security -> Screen Recording & System Audio
   -> click "+" -> Cmd-Shift-G -> ~/Applications -> select "$APP_NAME.app" -> toggle ON

2. Bind a hotkey to launch it. Any launcher works; the command to run is:
       open "$APP"
   e.g. an Automator "Quick Action" (Run Shell Script) bound to a shortcut in
   System Settings -> Keyboard -> Keyboard Shortcuts -> Services.

3. (Optional) choose where captures are saved:
       mkdir -p ~/.config/macshot
       echo 'SCREENSHOT_DIR=$HOME/Pictures/macshot' > ~/.config/macshot/config

Press your hotkey, drag a region (or Space to pick a window). The PNG path is
copied to your clipboard, ready to paste.
DONE
