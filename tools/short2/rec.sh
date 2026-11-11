#!/bin/bash
# rec.sh <tag> <scene> [args…] – Szene als AVI (30 fps, Musik aus). Fenstergröße kommt aus override.cfg (batch.sh)
P="/Users/marcello/Projekte/Need for Geschwindigkeit"; D="$(cd "$(dirname "$0")" && pwd)"
G=/Applications/Godot.app/Contents/MacOS/Godot
TAG="$1"; SC="$2"; shift 2
cd "$P"
perl -e 'alarm shift; exec @ARGV' 900 "$G" --path . --write-movie "$D/clips/$TAG.avi" --fixed-fps 30 "$SC" -- --nomusic "$@" > "$D/clips/$TAG.log" 2>&1
grep -E "SCRIPT ERROR|Parse Error" "$D/clips/$TAG.log" | head -3
echo "$TAG: $(ffprobe -v error -show_entries format=duration:stream=width,height -of csv=p=0 "$D/clips/$TAG.avi" | tr '\n' ' ')"
