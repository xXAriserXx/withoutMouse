#!/bin/bash
# Install (or uninstall) WhiteWindow as a launchd LaunchAgent so it runs
# in the background, survives terminal close, starts at login, and is
# restarted automatically if it crashes.
#
# Usage:
#   ./install.sh             build, install and start the agent
#   ./install.sh uninstall   stop the agent and remove installed files
set -euo pipefail

LABEL="com.james.whitewindow"
INSTALL_DIR="$HOME/Library/Application Support/WhiteWindow"
BINARY="$INSTALL_DIR/WhiteWindow"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/WhiteWindow.log"
DOMAIN="gui/$(id -u)"

if [[ "${1:-}" == "uninstall" ]]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$BINARY"
    echo "WhiteWindow uninstalled."
    exit 0
fi

cd "$(dirname "$0")"

echo "Building release binary..."
swift build -c release

echo "Installing to $BINARY"
mkdir -p "$INSTALL_DIR"
# Stop the running agent (if any) before replacing the binary
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
cp .build/release/WhiteWindow "$BINARY"

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
echo "NOTE: the installed binary is a new path — macOS will ask you to grant"
echo "Accessibility permission again (System Settings > Privacy & Security >"
echo "Accessibility). Re-run this script after code changes to update it."
