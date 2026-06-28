#!/bin/zsh
# Build ClaudeUsage.app and wrap it into a .pkg installer.
# Output: ~/Desktop/ClaudeUsage-1.0.pkg
set -e

SRCDIR="$HOME/.config/claude-usage"
APPNAME="ClaudeUsage"
VERSION="1.0"
PAYLOAD="$SRCDIR/.pkg_payload"
PKG_OUT="$HOME/Desktop/${APPNAME}-${VERSION}.pkg"

# 1. Compile and bundle the .app
echo "==> Building app..."
bash "$SRCDIR/build.sh"

# 2. Stage payload: pkg installs to /Applications
echo "==> Staging payload..."
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD/Applications"
cp -r "$HOME/Applications/$APPNAME.app" "$PAYLOAD/Applications/"

# 3. Build the .pkg
echo "==> Creating $PKG_OUT ..."
pkgbuild \
  --root "$PAYLOAD" \
  --install-location "/" \
  --identifier "com.github.claude-usage" \
  --version "$VERSION" \
  "$PKG_OUT"

rm -rf "$PAYLOAD"
echo "==> Done: $PKG_OUT"
echo "    Double-click to install → /Applications/ClaudeUsage.app"
