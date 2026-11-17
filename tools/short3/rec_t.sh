#!/bin/bash
# rec_t.sh [tag …] – Aufnahmen für den Trailer zu 2.39 im Querformat 1920x1080 (cut_t.py), nacheinander nach
# $SHORT3/clips/<tag>.avi (SHORT3 wie bei rec_u.sh; der Trailer nimmt einen eigenen Arbeitsordner). Ohne Argumente
# alle, sonst nur die genannten Tags. Welt-Abläufe über regie.gd (t_*), Rennszenen über debug_shot.gd (r_*: --drive
# fährt mit Autopilot, --at setzt das Auto an eine Stelle, --drifty driftet vor Kurven).
# Auto: Kagura V10 mit der Optik aus tools/short2/cfgB.txt (weiß, Unterbodenlicht), Grafik Ultra. Dauer gut 20 Minuten.
# Weite Blicke übers Land nicht bei Tag (dann schweben über dem Horizont graue Kegel, siehe SHORTS.md Nr. 15): Autobahn
# und Gelände abends.
D="$(cd "$(dirname "$0")" && pwd)"
CFG="$(cat "$D/../short2/cfgB.txt")"
C=(--quality=3 --car=kagura --cfg=$CFG)
R="$D/rec.sh"
export REC_SIZE=1920x1080
SELECT=" $* "
rec() {
	local tag="$1"
	shift
	if [ "$SELECT" != "  " ]; then
		case "$SELECT" in *" $tag "*) ;; *) return ;; esac
	fi
	"$R" "$tag" "$@"
}
RACE=res://scenes/race.tscn
# große Karte (M) wie im Spiel: Karte links, rechts das Infofeld zur Stadt; die Auswahl wandert über acht Städte
rec t_karte regie "--regie=karte:Aachen,Köln,Frankfurt am Main,Würzburg,München,Berlin,Hamburg,Rostock" --wspawn=ring:10 \
	--nozoom --tod=21 --rquit=7 "${C[@]}"
# Anflug von oben auf Frankfurt am Abend, Landung hinter dem Auto
rec t_anflug regie --regie=anflug:0:1500 --zkind=start --tod=18.8 --rquit=8 "${C[@]}"
# Würzburg bei Tag: Hauptstraße am Main zur Alten Mainbrücke, die Festung auf dem Berg (in der Stadt: keine weiten Blicke)
rec t_wue regie --regie=fahrt:16:3480:520 --nozoom --tod=13.5 --rquit=16 "${C[@]}"
# Berlin-Kreuzberg nachts an der Hochbahn der U1
rec t_xberg regie --regie=fahrt:20:4300:600 --nozoom --tod=22.3 --rquit=14 "${C[@]}"
# Aachen im Regen (Rennstrecke Grabenring, Stimmung "regen"): am Elisenbrunnen vorbei, Autopilot
rec r_aachen $RACE --race=15 --drive --at=d:2120 --quit=16 "${C[@]}"
# Hamburger Hafen im Nebel (Hafen-Drift, Stimmung "nebel"): Autopilot driftet vor den Kurven
rec r_hafen $RACE --race=7 --drive --drifty --quit=28 "${C[@]}"
# Autobahn um 20 Uhr: schnell auf der mittleren Spur, dicht an Lastwagen vorbei (KNAPP VORBEI), Nitro auf freier Bahn
rec t_raser regie --regie=autobahn:1:6.75:46:raser --nozoom --rv0=40 --tod=20 --rquit=40 "${C[@]}"
# Herausforderer: holt auf, zieht links vorbei, Enter, Duell (wie im Überblick-Short)
rec t_duell regie --regie=autobahn:1 --nozoom --rv0=24 --tod=20 --rquit=45 "${C[@]}"
# Hafen nachts: Q, "DRIFT-MODUS", quer durch die engste Kurve
rec t_modus regie --regie=modus:7 --nozoom --tod=21.5 --rquit=14 --rfeedk=1.5 "${C[@]}"
# Rennen: zur Lichtsäule, Enter, Kameraflug mit Startkarte (--intro), Countdown, Start; danach fährt der Autopilot
# (--drive, debug_shot.gd: wirkt erst in der Rennszene)
rec t_sprint regie --regie=rennen:12 --nozoom --tod=20.5 --rquit=34 --intro --drive "${C[@]}"
rec t_rundkurs regie --regie=rennen:15 --nozoom --tod=18.5 --rquit=34 --intro --drive "${C[@]}"
rec t_drift regie --regie=rennen:8 --nozoom --tod=21.5 --rquit=34 --intro --drive "${C[@]}"
# Frankfurt nachts im Rennen (Neon): Autopilot mit Nitro durch den Verkehr
rec r_frankfurt $RACE --race=0 --drive --quit=26 "${C[@]}"
# Golfplatz am Abend: drei Rampen mit Sprungkamera (Gelände-Test rampen:0)
rec t_teich regie --regie=frei --wspawn=gelaende:0 --otest=rampen:0 --nozoom --tod=19.6 --rquit=80 "${C[@]}"
# Kiesgrube: über den großen Kieshaufen, Kamera hinter der Landestelle
rec t_kies regie --regie=kies:1 --nozoom --tod=6.7 --rquit=9 "${C[@]}"
# Garage: Lack, Felgen, Autohaus, nächstes Auto (Kopfzeile mit Level aus)
rec t_tuning regie --regie=tuning --rquit=10 "${C[@]}"
