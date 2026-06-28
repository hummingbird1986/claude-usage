#!/bin/zsh
# Build ClaudeUsage.swift into a proper macOS .app bundle and install to ~/Applications/
set -e

SRCDIR="$HOME/.config/claude-usage"
APPNAME="ClaudeUsage"
APPDIR="$HOME/Applications/$APPNAME.app"
BINARY="$APPDIR/Contents/MacOS/$APPNAME"

echo "==> Compiling Swift source..."
swiftc "$SRCDIR/ClaudeUsage.swift" \
    -framework AppKit \
    -O \
    -o "$SRCDIR/$APPNAME"

echo "==> Creating .app bundle at $APPDIR"
mkdir -p "$APPDIR/Contents/MacOS"
mkdir -p "$APPDIR/Contents/Resources"

cp "$SRCDIR/$APPNAME" "$BINARY"

# Copy Claude tray icons from Claude Desktop
CLAUDE_RES="/Applications/Claude.app/Contents/Resources"
for f in TrayIconTemplate.png TrayIconTemplate@2x.png TrayIconTemplate@3x.png; do
  [ -f "$CLAUDE_RES/$f" ] && cp "$CLAUDE_RES/$f" "$APPDIR/Contents/Resources/$f"
done

cat > "$APPDIR/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ClaudeUsage</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Usage</string>
    <key>CFBundleIdentifier</key>
    <string>com.daniel.claude-usage</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeUsage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
EOF

echo "==> Signing with ad-hoc signature..."
codesign --force --deep --sign - "$APPDIR"

echo "==> Done. App installed at $APPDIR"
echo "    To launch: open $APPDIR"
echo "    To auto-start at login: add via System Settings → General → Login Items"
