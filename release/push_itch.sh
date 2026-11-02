#!/bin/bash
# Lädt die Builds per butler auf itch.io hoch (als Ordner, damit Updates nur Änderungen übertragen).
# Kanäle: windows, macos, linux und – falls builds/web existiert – html5 (im Browser spielbar).
# Aufruf:  release/push_itch.sh <itch-benutzername> [version] [projekt-adresse]
# Voraussetzung: einmal `butler login`, die Projektseite existiert. projekt-adresse ist der letzte Teil der URL
# (benutzer.itch.io/<adresse>), Standard "need-for-geschwindigkeit"; die alte Seite hieß "underground-sprint".
set -e
USER="$1"
VERSION="${2:-1.0.0}"
GAME="${3:-need-for-geschwindigkeit}"
BUTLER="${BUTLER:-$HOME/.butler/bin/butler}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$USER" ]; then
	echo "Aufruf: $0 <itch-benutzername> [version] [projekt-adresse]"
	exit 1
fi
# Ein Ordner pro Plattform
STAGE="$ROOT/builds/itch"
rm -rf "$STAGE"
mkdir -p "$STAGE/windows" "$STAGE/linux" "$STAGE/macos"
cp "$ROOT/builds/windows/NeedForGeschwindigkeit.exe" "$STAGE/windows/"
cp "$ROOT/builds/linux/NeedForGeschwindigkeit.x86_64" "$STAGE/linux/"
ditto -x -k "$ROOT/builds/macos/NeedForGeschwindigkeit.zip" "$STAGE/macos"
for channel in windows macos linux; do
	echo "== $channel"
	"$BUTLER" push "$STAGE/$channel" "$USER/$GAME:$channel" --userversion "$VERSION"
done
if [ -f "$ROOT/builds/web/index.html" ]; then
	echo "== html5"
	"$BUTLER" push "$ROOT/builds/web" "$USER/$GAME:html5" --userversion "$VERSION"
fi
"$BUTLER" status "$USER/$GAME"
