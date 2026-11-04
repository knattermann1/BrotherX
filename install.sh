#!/bin/bash
# Baut "Einzugscan.app" und installiert sie nach ~/Applications (oder in den als
# erstes Argument übergebenen Ordner). Installiert außerdem den Befehl
# "einzugscan" für das Terminal nach ~/.local/bin.
set -euo pipefail

cd "$(dirname "$0")"
DEST="${1:-$HOME/Applications}"
APP="$DEST/Einzugscan.app"

if ! command -v osacompile >/dev/null 2>&1; then
    echo "Fehler: osacompile nicht gefunden – dieses Skript muss auf einem Mac laufen." >&2
    exit 1
fi

mkdir -p "$DEST"
rm -rf "$APP"
osacompile -o "$APP" app/Einzugscan.applescript
cp einzugscan.sh "$APP/Contents/Resources/einzugscan.sh"
chmod +x "$APP/Contents/Resources/einzugscan.sh"

# Eigene Bundle-ID, damit macOS die Freigabe "Lokales Netzwerk" zuordnen kann
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string de.brotherx.einzugscan" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier de.brotherx.einzugscan" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSLocalNetworkUsageDescription string 'Einzugscan verbindet sich mit deinem Scanner im lokalen Netzwerk.'" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices array" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSBonjourServices:0 string _uscan._tcp" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

mkdir -p "$HOME/.local/bin"
cp einzugscan.sh "$HOME/.local/bin/einzugscan"
chmod +x "$HOME/.local/bin/einzugscan"

echo "Installiert:"
echo "  App:      $APP"
echo "  Terminal: $HOME/.local/bin/einzugscan   (ggf. ~/.local/bin zum PATH hinzufügen)"
