#!/bin/bash
# oeffentlich.sh <zielordner> – den öffentlichen Stand vorbereiten (OPEN_SOURCE.md): alle eingecheckten Dateien von
# HEAD in einen neuen Ordner, dort ein frisches Git-Repo mit einem einzigen Commit, ohne die Geschichte des privaten
# Repos (alte Fassungen, frühere Pfade). Nicht dabei, weil nicht eingecheckt: .claude/, builds/, das Aachen-Lied.
# Autor des Commits ist der des letzten Commits hier (die GitHub-noreply-Adresse), nicht die lokale Git-Einstellung.
# Hochladen danach: git remote add origin <neues Repo>; git push -u origin main
set -e
Z="$1"
[ -z "$Z" ] && { echo "Aufruf: tools/oeffentlich.sh <zielordner>"; exit 1; }
[ -e "$Z" ] && { echo "$Z gibt es schon"; exit 1; }
P="$(cd "$(dirname "$0")/.." && pwd)"
NAME="$(git -C "$P" log -1 --format=%an)"
MAIL="$(git -C "$P" log -1 --format=%ae)"
VER="$(git -C "$P" log --format=%s | grep -m1 -oE '^[0-9]+\.[0-9]+(\.[0-9]+)?')"
mkdir -p "$Z"
git -C "$P" archive HEAD | tar -x -C "$Z"
cd "$Z"
git init -q -b main
git add -A
git -c user.name="$NAME" -c user.email="$MAIL" commit -q -m "Need for Geschwindigkeit $VER als Open Source

Code unter MIT (LICENSE), eigene Inhalte unter CC BY 4.0 (LICENSE-INHALTE.md), fremde Dateien unter ihren
eigenen Lizenzen (CREDITS.md), Kartendaten unter der ODbL. Name und Logo von ONE HUMANITY sind nicht frei
lizenziert.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
echo "Fertig: $Z, $(git ls-files | wc -l | tr -d ' ') Dateien, Git $(du -sh .git | cut -f1), Stand $VER"
