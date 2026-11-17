#!/bin/bash
# ovr.sh [bild_u.png [bild_b.png]] – Einblendungen der Shorts zu 2.39 rendern (tools/promo_overlays.tscn, Schrift Saira
# wie in den Shorts 13 und 14): Überblick (--sketch5, $SHORT3/ov/u_*.png) und Aufruf an Künstler (--sketch4, b_*.png).
# Mit Standbildern (Hochformat 1080x1920, absolute Pfade) dazu die Titelbilder nach release/:
#   bild_u.png -> need_for_geschwindigkeit_short_ueberblick_cover_1080x1920.png
#   bild_b.png -> need_for_geschwindigkeit_short_kuenstler_cover_1080x1920.png
# Läuft im Hintergrund ohne Fokus und ohne Ton (open -g, Dummy-Audio).
set -u
D="$(cd "$(dirname "$0")" && pwd)"
P="$(cd "$D/../.." && pwd)"
W="${SHORT3:-$D/arbeit}"
mkdir -p "$W/ov"
ov() {
	open -g -n -W -a /Applications/Godot.app --args --path "$P" --audio-driver Dummy res://tools/promo_overlays.tscn -- \
		--out="$W/ov" --uifont=saira "$@"
}
ov --sketch5
ov --sketch4
if [ $# -ge 1 ]; then
	ov --sketch5 --scover="$1"
	cp "$W/ov/short_cover_ueberblick_1080x1920.png" "$P/release/need_for_geschwindigkeit_short_ueberblick_cover_1080x1920.png"
fi
if [ $# -ge 2 ]; then
	ov --sketch4 --scover="$2"
	cp "$W/ov/short_cover_kuenstler_1080x1920.png" "$P/release/need_for_geschwindigkeit_short_kuenstler_cover_1080x1920.png"
fi
ls "$W/ov"
