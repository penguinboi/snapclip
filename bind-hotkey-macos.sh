#!/usr/bin/env bash
# ABOUTME: Binds Cmd+Shift+1 to Snapclip by installing a Quick Action and assigning its shortcut.
# ABOUTME: Checks what it wrote and prints manual steps when macOS has not taken the binding.
set -uo pipefail

SERVICE_NAME="Snapclip"
APP="${SNAPCLIP_APP:-$HOME/Applications/Snapclip.app}"
SERVICES_DIR="$HOME/Library/Services"
WORKFLOW="$SERVICES_DIR/$SERVICE_NAME.workflow"

# pbs encodes modifiers as symbols: @ Command, $ Shift, ^ Control, ~ Option.
KEY_EQUIVALENT="${SNAPCLIP_KEY_EQUIVALENT:-@\$1}"
HOTKEY_LABEL="${SNAPCLIP_HOTKEY_LABEL:-Cmd+Shift+1}"

# pbs keys services by this exact triple. A mismatch here is silently ignored,
# which is why the shortcut is read back afterwards rather than assumed.
SERVICE_KEY="(null) - $SERVICE_NAME - runWorkflowAsService"

write_workflow() {
    mkdir -p "$WORKFLOW/Contents"

    cat > "$WORKFLOW/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSServices</key>
	<array>
		<dict>
			<key>NSMenuItem</key>
			<dict>
				<key>default</key>
				<string>$SERVICE_NAME</string>
			</dict>
			<key>NSMessage</key>
			<string>runWorkflowAsService</string>
			<key>NSSendTypes</key>
			<array/>
		</dict>
	</array>
</dict>
</plist>
PLIST

    # "Receives no input in any application" is what makes the shortcut fire
    # everywhere instead of only where a selection exists.
    cat > "$WORKFLOW/Contents/document.wflow" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AMApplicationBuild</key>
	<string>521</string>
	<key>AMApplicationVersion</key>
	<string>2.10</string>
	<key>AMDocumentVersion</key>
	<string>2</string>
	<key>actions</key>
	<array>
		<dict>
			<key>action</key>
			<dict>
				<key>AMActionVersion</key>
				<string>2.0.3</string>
				<key>ActionBundlePath</key>
				<string>/System/Library/Automator/Run Shell Script.action</string>
				<key>ActionName</key>
				<string>Run Shell Script</string>
				<key>ActionParameters</key>
				<dict>
					<key>COMMAND_STRING</key>
					<string>open "$APP"</string>
					<key>CheckedForUserDefaultShell</key>
					<true/>
					<key>inputMethod</key>
					<integer>0</integer>
					<key>shell</key>
					<string>/bin/bash</string>
					<key>source</key>
					<string></string>
				</dict>
				<key>BundleIdentifier</key>
				<string>com.apple.RunShellScript</string>
				<key>CFBundleVersion</key>
				<string>2.0.3</string>
				<key>CanShowSelectedItemsWhenRun</key>
				<false/>
				<key>CanShowWhenRun</key>
				<true/>
				<key>Category</key>
				<array>
					<string>AMCategoryUtilities</string>
				</array>
				<key>Class Name</key>
				<string>RunShellScriptAction</string>
				<key>InputUUID</key>
				<string>$(uuidgen)</string>
				<key>Keywords</key>
				<array>
					<string>Shell</string>
					<string>Script</string>
					<string>Command</string>
				</array>
				<key>OutputUUID</key>
				<string>$(uuidgen)</string>
				<key>UUID</key>
				<string>$(uuidgen)</string>
				<key>UnlocalizedApplications</key>
				<array>
					<string>Automator</string>
				</array>
				<key>isViewVisible</key>
				<integer>1</integer>
			</dict>
		</dict>
	</array>
	<key>workflowMetaData</key>
	<dict>
		<key>presentationMode</key>
		<integer>11</integer>
		<key>processesInput</key>
		<integer>0</integer>
		<key>serviceInputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceOutputTypeIdentifier</key>
		<string>com.apple.Automator.nothing</string>
		<key>serviceProcessesInput</key>
		<integer>0</integer>
		<key>workflowTypeIdentifier</key>
		<string>com.apple.Automator.servicesMenu</string>
	</dict>
</dict>
</plist>
PLIST
}

assign_shortcut() {
    # Every pbs service key starts with "(null) - ", and defaults reads a leading
    # "(" as the start of a plist array literal and rejects the key. It has to
    # arrive already quoted. defaults exits 0 on that failure, so the shortcut is
    # read back afterwards rather than trusted.
    defaults write pbs NSServicesStatus -dict-add "\"$SERVICE_KEY\"" \
        "{ key_equivalent = \"$KEY_EQUIVALENT\"; enabled_context_menu = 1; enabled_services_menu = 1; }"
    /System/Library/CoreServices/pbs -flush 2>/dev/null
    /System/Library/CoreServices/pbs -update 2>/dev/null
}

read_shortcut() {
    # Quoting differs across macOS versions, so normalise it away before matching.
    defaults read pbs NSServicesStatus 2>/dev/null |
        tr -d '"' |
        tr -d '\n' |
        grep -o "$SERVICE_KEY[^}]*}" |
        grep -o 'key_equivalent = [^;]*' |
        sed 's/^key_equivalent = //'
}

verify() {
    local ok=0

    if [ -f "$WORKFLOW/Contents/document.wflow" ]; then
        echo "  Quick Action installed : $WORKFLOW"
    else
        echo "  Quick Action MISSING   : $WORKFLOW"; ok=1
    fi

    if plutil -lint "$WORKFLOW/Contents/Info.plist" >/dev/null 2>&1 &&
       plutil -lint "$WORKFLOW/Contents/document.wflow" >/dev/null 2>&1; then
        echo "  Property lists         : valid"
    else
        echo "  Property lists         : INVALID"; ok=1
    fi

    check_applet_is_macho || ok=1

    local current; current="$(read_shortcut)"
    if [ "$current" = "$KEY_EQUIVALENT" ]; then
        echo "  Shortcut recorded      : $HOTKEY_LABEL"
    else
        echo "  Shortcut NOT recorded  : got [${current:-nothing}], wanted [$KEY_EQUIVALENT]"; ok=1
    fi

    return $ok
}

# macOS does not arbitrate between two services claiming one shortcut; it picks a
# winner and the loser silently stops working. Never take a key without saying so.
warn_on_shortcut_conflict() {
    local dump others
    dump="$(defaults read pbs NSServicesStatus 2>/dev/null)" || return 0

    # `defaults read` quotes keys inconsistently across macOS versions, so compare
    # with every quote stripped instead of guessing which form this machine emits.
    others="$(printf '%s\n' "$dump" |
        tr -d '"' |
        grep -B6 -F "key_equivalent = $KEY_EQUIVALENT;" |
        grep -F '(null)' |
        grep -vF "$SERVICE_KEY" |
        sed 's/^[[:space:]]*//; s/[[:space:]]*=.*$//')"

    [ -n "$others" ] || return 0

    cat >&2 <<EOF

WARNING: $HOTKEY_LABEL already belongs to another service:
$others

macOS will pick one of them and the other stops working, with no error either way.
Free the key first, or give Snapclip a different one:

    SNAPCLIP_KEY_EQUIVALENT='@\$2' SNAPCLIP_HOTKEY_LABEL='Cmd+Shift+2' ./bind-hotkey-macos.sh

EOF
    return 1
}

# A bundle whose executable is a shell script has no Mach-O of its own, so launchd
# runs /bin/bash and TCC attributes the capture to an identity it cannot grant.
# Signing does not fix it, and the symptom is silence rather than an error.
check_applet_is_macho() {
    local exe
    exe="$(defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null)"
    [ -n "$exe" ] || { echo "  Applet executable      : cannot read Info.plist"; return 1; }

    local kind; kind="$(file -b "$APP/Contents/MacOS/$exe" 2>/dev/null)"
    case "$kind" in
        *Mach-O*) echo "  Applet executable      : Mach-O ($exe)" ;;
        *)        echo "  Applet executable      : NOT Mach-O -> $kind"
                  echo "                           captures will fail silently; rebuild with build.sh"
                  return 1 ;;
    esac
}

manual_steps() {
    cat <<EOF

Set it by hand instead:
  1. System Settings -> Keyboard -> Keyboard Shortcuts -> Services
  2. Find "$SERVICE_NAME" under General
  3. Click it and press $HOTKEY_LABEL
EOF
}

# Generates into a throwaway directory and lints, touching neither ~/Library/Services
# nor pbs. Lets the binding be checked on a Mac without installing anything.
if [ "${1:-}" = "--unbind" ]; then
    rm -rf "$WORKFLOW"
    # Leaving the pbs key behind when the workflow is gone is what produces the
    # orphaned entries that accumulate across renames.
    /usr/libexec/PlistBuddy -c "Delete :NSServicesStatus:$SERVICE_KEY" \
        "$HOME/Library/Preferences/pbs.plist" >/dev/null 2>&1
    /System/Library/CoreServices/pbs -flush 2>/dev/null

    if [ -n "$(read_shortcut)" ] || [ -d "$WORKFLOW" ]; then
        echo "Could not fully remove the binding." >&2
        echo "  workflow : $([ -d "$WORKFLOW" ] && echo "still at $WORKFLOW" || echo removed)" >&2
        echo "  pbs key  : $([ -n "$(read_shortcut)" ] && echo "still set" || echo removed)" >&2
        exit 1
    fi
    echo "Removed the Snapclip Quick Action and its shortcut."
    exit 0
fi

if [ "${1:-}" = "--dry-run" ]; then
    WORKFLOW="$(mktemp -d)/$SERVICE_NAME.workflow"
    write_workflow
    echo "Generated (nothing installed): $WORKFLOW"
    for plist in Info.plist document.wflow; do
        if plutil -lint "$WORKFLOW/Contents/$plist" >/dev/null 2>&1; then
            echo "  $plist: valid"
        else
            echo "  $plist: INVALID"
            plutil -lint "$WORKFLOW/Contents/$plist"
        fi
    done
    echo "  service key would be : $SERVICE_KEY"
    echo "  shortcut would be    : $KEY_EQUIVALENT ($HOTKEY_LABEL)"
    echo "  command would be     : open \"$APP\""
    exit 0
fi

if [ "${1:-}" = "--verify" ]; then
    echo "Snapclip hotkey binding:"
    verify || manual_steps
    exit $?
fi

if [ "$(uname)" != "Darwin" ]; then
    echo "bind-hotkey-macos.sh: macOS only (this is $(uname))." >&2
    exit 1
fi

if ! warn_on_shortcut_conflict && [ "${1:-}" != "--force" ]; then
    cat >&2 <<EOF
Refusing to take $HOTKEY_LABEL from another service. Nothing was changed.
Re-run with --force to take it anyway, knowing the other one will stop working.
EOF
    exit 1
fi

write_workflow
assign_shortcut

echo "Binding $HOTKEY_LABEL to Snapclip:"
if verify; then
    cat <<EOF

Press $HOTKEY_LABEL to capture. If nothing happens, log out and back in: macOS
caches the services list, and a newly installed Quick Action is not always picked
up until the session restarts.
EOF
else
    echo
    echo "The automatic binding did not take."
    manual_steps
fi
