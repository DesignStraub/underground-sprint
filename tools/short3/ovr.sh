#!/bin/bash
# ovr.sh [bild_a.png bild_b.png] – Einblendungen der beiden Shorts zu 2.39 rendern (tools/promo_overlays.tscn mit
# --sketch3 und --sketch4, Schrift Saira wie in den Shorts 13 und 14): $SHORT3/ov/a_*.png und b_*.png.
# Mit zwei Standbildern (Hochformat 1080x1920) dazu die Titelbilder nach release/:
#   need_for_geschwindigkeit_short_239_cover_1080x1920.png, need_for_geschwindigkeit_short_kuenstler_cover_1080x1920.png
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
ov --sketch3
ov --sketch4
if [ $# -ge 2 ]; then
	ov --sketch3 --scover="$1"
	ov --sketch4 --scover="$2"
	cp "$W/ov/short_cover_239_1080x1920.png" "$P/release/need_for_geschwindigkeit_short_239_cover_1080x1920.png"
	cp "$W/ov/short_cover_kuenstler_1080x1920.png" "$P/release/need_for_geschwindigkeit_short_kuenstler_cover_1080x1920.png"
fi
ls "$W/ov"
