#!/bin/bash
# rec.sh <tag> <szene|regie> [args…] – nimmt eine Szene fürs Short auf: Hochformat 1080x1920, 30 Bilder/s
# (--write-movie, MJPEG-AVI mit Spielton), Musik aus, ohne Lichtteppich, Test-Spielstand.
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
TO="${REC_TIMEOUT:-900}"
AVI="$W/clips/$TAG.avi"
LOG="$W/clips/$TAG.log"
cd "$P" || exit 1
# Fenster im Hochformat, randlos, ohne Fokus; Bildqualität der Aufnahme. Danach wieder weg (export_all.sh bricht sonst ab).
printf '[display]\n\nwindow/size/no_focus=true\nwindow/size/borderless=true\nwindow/size/window_width_override=1080\nwindow/size/window_height_override=1920\n\n[editor]\n\nmovie_writer/mjpeg_quality=0.95\n' > override.cfg
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
rm -f override.cfg
grep -E "SCRIPT ERROR|Parse Error" "$LOG" | head -3
# Größe und Zahl der Bilder (zählt die Pakete: geht auch bei einer Aufnahme ohne Index)
echo "$TAG: $(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$AVI" 2>/dev/null | head -1)," \
	"$(ffprobe -v error -count_packets -select_streams v -show_entries stream=nb_read_packets -of csv=p=0 "$AVI" 2>/dev/null) Bilder"
