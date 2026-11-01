#!/bin/bash
# Lädt die drei Builds per butler auf itch.io hoch (als Ordner, damit Updates nur Änderungen übertragen).
# Aufruf:  release/push_itch.sh <itch-benutzername> [version]
# Voraussetzung: einmal `butler login`, Projektseite "underground-sprint" existiert.
set -e
USER="$1"
VERSION="${2:-1.0.0}"
BUTLER="${BUTLER:-$HOME/.butler/bin/butler}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$USER" ]; then
	echo "Aufruf: $0 <itch-benutzername> [version]"
	exit 1
fi
# Ein Ordner pro Plattform
STAGE="$ROOT/builds/itch"
rm -rf "$STAGE"
mkdir -p "$STAGE/windows" "$STAGE/linux" "$STAGE/macos"
cp "$ROOT/builds/windows/UndergroundSprint.exe" "$STAGE/windows/"
cp "$ROOT/builds/linux/UndergroundSprint.x86_64" "$STAGE/linux/"
ditto -x -k "$ROOT/builds/macos/UndergroundSprint.zip" "$STAGE/macos"
for channel in windows macos linux; do
	echo "== $channel"
	"$BUTLER" push "$STAGE/$channel" "$USER/underground-sprint:$channel" --userversion "$VERSION"
done
"$BUTLER" status "$USER/underground-sprint"
