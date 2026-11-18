#!/bin/bash
# rec_r.sh [tag …] – Aufnahmen für das Reel zu 2.48 (cut_r.py) im Hochformat nach $SHORT3/clips/<tag>.avi.
# Ohne Argumente alle, sonst nur diese Tags. Auto wie in den Shorts (Kagura V10, tools/short2/cfgB.txt), Verfolger weit,
# Oberfläche 1,35-fach (im Hochformat lesbar), Grafik Ultra. Ton aus, Fenster im Hintergrund.
D="$(cd "$(dirname "$0")" && pwd)"
CFG="$(cat "$D/../short2/cfgB.txt")"
C=(--rcam=1 --quality=3 --car=kagura --cfg=$CFG --rui=1.35)
R="$D/rec.sh"
RACE=res://scenes/race.tscn
SELECT=" $* "
rec() {
	local tag="$1"
	shift
	if [ "$SELECT" != "  " ]; then
		case "$SELECT" in *" $tag "*) ;; *) return ;; esac
	fi
	"$R" "$tag" "$@"
}
# Anflug von oben auf Frankfurt am Abend (Titel)
rec r_anflug regie --regie=anflug:0:1500 --zkind=start --tod=18.8 --rquit=8 "${C[@]}"
# Autobahn-Rennen A3 Köln–Frankfurt: blaue Säule, Countdown, Start, Ring mit drei Gegnern im Verkehr
rec r_autobahn regie --regie=frei --hwrace=1 --hwbot --tod=20 --rquit=40 "${C[@]}"
# Drift im Hafen von Hamburg (Stadt 7) nachts: Q, quer durch die engste Kurve, Anzeige links (Spalte 1,4-fach)
rec r_drift regie --regie=modus:7 --nozoom --tod=21.5 --rquit=14 --rfeedk=1.4 "${C[@]}"
# Splitscreen: Innenstadtring Köln, beide Spieler fahren selbst (oben Spieler 1, unten Spieler 2)
rec r_split $RACE --race=4 --split --drive --p2bot --p2car=shiden --quit=26 "${C[@]}"
# gelbes Ortsschild Köln mit Gruß, ohne Anzeigen: Kamera am Bordstein 18 m vor dem Schild, 2,4 m hoch, Bildwinkel 46°
# (30 m davor verdeckt ein Pflanzkübel die Tafel); das Auto startet 100 m davor mit 16 m/s und fährt links vorbei
rec r_schild regie --regie=schild:4 --nozoom --tod=19.5 --rquit=10 --rhud=0 --rvor=100 --rv0=16 --rschild=18:46:2.4 \
	"${C[@]}"
# große Karte: entdeckte Städte, Auswahl wandert über die Städte
rec r_karte regie "--regie=karte:Köln,Aachen,Frankfurt am Main,München,Berlin,Hamburg" --wspawn=ring:10 --nozoom --tod=21 \
	--rquit=6 "${C[@]}"
# ONE HUMANITY: beleuchtete Tafel an der Autobahn (Plakat 12, Herz) in der Abenddämmerung wie die übrigen Bilder,
# feste Kamera, ohne Anzeigen
rec r_plakat regie --regie=frei --wspawn=xy:3741:1470:0 --plakat=12 --tod=19.3 --camat=3741:4:1471:3768.8:7.0:1467.6 \
	--nozoom --rquit=5 --rhud=0 "${C[@]}"
