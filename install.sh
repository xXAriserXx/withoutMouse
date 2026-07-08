#!/bin/bash
# Install (or uninstall) WhiteWindow as a launchd LaunchAgent so it runs
# in the background, survives terminal close, starts at login, and is
# restarted automatically if it crashes.
#
# The binary is packaged as a minimal .app bundle in ~/Applications —
# macOS's Accessibility pane silently rejects bare Unix executables,
# but accepts app bundles.
#
# Usage:
#   ./install.sh             build, install and start the agent
#   ./install.sh uninstall   stop the agent and remove installed files
set -euo pipefail

LABEL="com.james.whitewindow"
APP_DIR="$HOME/Applications/WhiteWindow.app"
BINARY="$APP_DIR/Contents/MacOS/WhiteWindow"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/WhiteWindow.log"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "uninstall" ]]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    rm -rf "$APP_DIR"
    echo "WhiteWindow uninstalled."
    exit 0
fi

cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

echo "Assembling app bundle at $APP_DIR"
# Stop the running agent (if any) before replacing the binary
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$APP_DIR/Contents/MacOS"
cp .build/release/WhiteWindow "$BINARY"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$LABEL</string>
    <key>CFBundleName</key>
    <string>WhiteWindow</string>
    <key>CFBundleExecutable</key>
    <string>WhiteWindow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "Signing (ad-hoc)..."
codesign --force --sign - "$APP_DIR"

echo "Writing LaunchAgent $PLIST"
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

# Clean up the old bare-binary install location if present
rm -rf "$HOME/Library/Application Support/WhiteWindow"

echo "Starting agent..."
launchctl bootstrap "$DOMAIN" "$PLIST"

echo
echo "WhiteWindow is running in the background (log: $LOG)."
echo "It will start automatically at login and restart if it crashes."
echo
echo "Useful commands:"
echo "  launchctl kickstart -k $DOMAIN/$LABEL   # restart (e.g. after reinstall)"
echo "  launchctl bootout $DOMAIN/$LABEL        # stop until next login"
echo "  ./install.sh uninstall                  # remove completely"
echo
echo "Grant Accessibility permission to $APP_DIR"
echo "(System Settings > Privacy & Security > Accessibility), then restart"
echo "the agent. Re-run this script after code changes to deploy them."
