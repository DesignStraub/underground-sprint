#!/bin/bash
# rec.sh <tag> <szene|regie> [args…] – nimmt eine Szene auf: Hochformat 1080x1920 (REC_SIZE=1920x1080: Querformat für
# Trailer), 30 Bilder/s (--write-movie, MJPEG-AVI mit Spielton), Musik aus, ohne Lichtteppich, Test-Spielstand.
# Läuft stumm im Hintergrund und nimmt keinen Fokus (open -g, Dummy-Audio, override.cfg mit no_focus).
#   <szene>  res://scenes/world.tscn, res://scenes/garage.tscn … oder "regie" (tools/short3/regie.gd fährt und filmt,
#            Ablauf mit --regie=<name>, siehe dort)
# Ausgabe: $SHORT3/clips/<tag>.avi und <tag>.log. SHORT3 ist der Arbeitsordner (Standard tools/short3/arbeit, steht in
# .gitignore). REC_FPS=24 nimmt mit 24 Bildern/s auf (als 30 abgespielt: Zeitlupe 0,8 ohne doppelte Bilder),
# REC_TIMEOUT (s, Standard 900) beendet hängende Läufe.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/../.." && pwd)"
W="${SHORT3:-$D/arbeit}"
mkdir -p "$W/clips"
TAG="$1"; SC="$2"; shift 2
FPS="${REC_FPS:-30}"
SIZE="${REC_SIZE:-1080x1920}"
RW="${SIZE%x*}"
RH="${SIZE#*x}"
TO="${REC_TIMEOUT:-900}"
AVI="$W/clips/$TAG.avi"
LOG="$W/clips/$TAG.log"
cd "$P" || exit 1
# Fenster in Aufnahmegröße, randlos, ohne Fokus; Bildqualität der Aufnahme. Danach wieder weg (export_all.sh bricht sonst
# ab); lag vorher schon eine override.cfg da (z. B. nur no_focus für andere Testläufe), kommt sie danach zurück
OLD_OVR=""
[ -f override.cfg ] && OLD_OVR="$(cat override.cfg)"
MY_OVR="$(printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/borderless=true\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.95' "$RW" "$RH")"
printf '%s\n' "$MY_OVR" > override.cfg
if [ "$SC" = regie ]; then RUN=(-s res://tools/short3/regie.gd); else RUN=("$SC"); fi
open -g -n -W -a /Applications/Godot.app --args --path "$P" --write-movie "$AVI" --fixed-fps "$FPS" --audio-driver Dummy \
	--log-file "$LOG" "${RUN[@]}" -- --nomusic --nopool --save=test "$@" &
OPID=$!
i=0
e=0
while kill -0 $OPID 2>/dev/null; do
	sleep 1
	i=$((i + 1))
	# Ende gemeldet, Programm hängt aber beim Beenden (Hintergrund-Bau): nach 25 s beenden, die Aufnahme ist vollständig
	# (MJPEG-AVI ohne Index, ffmpeg liest sie trotzdem)
	if grep -q "REGIE ENDE" "$LOG" 2>/dev/null; then
		e=$((e + 1))
		if [ $e -ge 25 ]; then
			pkill -f -- "$LOG"
			echo "$TAG: hing nach dem Ende, beendet"
			break
		fi
	fi
	if [ $i -ge "$TO" ]; then
		pkill -f -- "$LOG"
		echo "$TAG: abgebrochen nach $TO s"
		break
	fi
done
# nur die eigene override.cfg wegräumen (hat sie inzwischen jemand anders geändert, bleibt sie)
if [ -f override.cfg ] && [ "$(cat override.cfg)" = "$MY_OVR" ]; then
	if [ -n "$OLD_OVR" ]; then printf '%s\n' "$OLD_OVR" > override.cfg; else rm -f override.cfg; fi
fi
grep -E "SCRIPT ERROR|Parse Error" "$LOG" | head -3
# Größe, Zahl der Bilder (zählt die Pakete: geht auch bei einer Aufnahme ohne Index) und wie viele davon verschieden
# sind: viel weniger als Bilder heißt, die Engine hat nicht neu gezeichnet (Fenster verdeckt, Bildschirm aus), dann neu
# aufnehmen. Ruhige Bilder (Karte, Halt an der Ampel) wiederholen sich zu Recht.
echo "$TAG: $(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$AVI" 2>/dev/null | head -1)," \
	"$(ffprobe -v error -count_packets -select_streams v -show_entries stream=nb_read_packets -of csv=p=0 "$AVI" 2>/dev/null) Bilder," \
	"$(ffmpeg -v error -i "$AVI" -an -f framemd5 - 2>/dev/null | grep -v '^#' | awk -F, '{print $6}' | sort -u | wc -l | tr -d ' ') verschieden"
