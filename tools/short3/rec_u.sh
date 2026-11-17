#!/bin/bash
# rec_u.sh [tag …] – Aufnahmen für den stummen Überblick-Short (cut_u.py), nacheinander nach $SHORT3/clips/<tag>.avi.
# Ohne Argumente: alle u_*-Aufnahmen, dazu die vier a_*-Aufnahmen (Anflug, Kreuzung, Teich, Kiesgrube), falls sie noch
# fehlen. Mit Argumenten nur diese Tags (z. B. rec_u.sh u_ring u_tuning).
# Auto: Kagura V10 mit der Optik aus tools/short2/cfgB.txt (weiß, Unterbodenlicht) wie in den Shorts 13 bis 16,
# Kamera "Verfolger weit", Grafik Ultra. Dauer gut 10 Minuten (Ton aus, Fenster im Hintergrund).
D="$(cd "$(dirname "$0")" && pwd)"
W="${SHORT3:-$D/arbeit}"
CFG="$(cat "$D/../short2/cfgB.txt")"
C=(--rcam=1 --quality=3 --car=kagura --cfg=$CFG)
R="$D/rec.sh"
ALL=1
[ $# -gt 0 ] && ALL=0
# rec <tag> <0|1: nur wenn die Aufnahme fehlt> <args …>
rec() {
	local tag="$1" ifmissing="$2"
	shift 2
	if [ $ALL = 1 ]; then
		[ "$ifmissing" = 1 ] && [ -s "$W/clips/$tag.avi" ] && return
	else
		case " $SELECT " in *" $tag "*) ;; *) return ;; esac
	fi
	"$R" "$tag" "$@"
}
SELECT=" $* "
# große Karte (M) im Hochformat: beide Ringe, Spangen, alle Städte; die Auswahl wandert über sieben Städte
rec u_karte 0 regie --regie=karte --wspawn=ring:10 --nozoom --tod=21 --rquit=6 "${C[@]}"
# innerer Ring, Stück 1 (nach Westen, ohne Ausfahrten) am späten Abend: rechte Spur mit 86 km/h wie die Lastwagen,
# nach 3 s der Herausforderer, er holt auf der mittleren Spur auf und zieht links vorbei; 18 m vor dem Auto Enter:
# Duell. Nicht bei Tag (über dem Horizont schweben dann graue Kegel, siehe SHORTS.md) und nicht später als 20 Uhr
# (dann ist er im Dunkeln beim Überholen kaum zu sehen). Lack und Felgen des Herausforderers wechseln von Aufnahme zu
# Aufnahme (Zufall des Verkehrs).
rec u_ring 0 regie --regie=autobahn:1 --nozoom --rv0=24 --tod=20 --rquit=45 "${C[@]}"
# dasselbe ohne Anzeigen fürs Titelbild: Bild "herausforderer vorbei" + 25 (film=, er fährt links vor dem Auto), z. B.
#   ffmpeg -i $SHORT3/clips/c_ring.avi -vf "select='eq(n\,705)'" -frames:v 1 c_ring.png; tools/short3/ovr.sh $PWD/c_ring.png
rec c_ring 0 regie --regie=autobahn:1 --nozoom --rv0=24 --tod=20 --rquit=30 --rhud=0 "${C[@]}"
# Hafen-Drift (Stadt 7) nachts: nach 1 s Q, links unten groß "DRIFT-MODUS", dann quer durch die engste Kurve
rec u_modus 0 regie --regie=modus:7 --nozoom --tod=21.5 --rquit=14 --rfeedk=2 "${C[@]}"
# Rennen: zur Lichtsäule am Start, darin halten, Enter: Ladebild mit der Karte des Rennens, Countdown (unter der Zahl
# die Art in ihrer Farbe), Start
rec u_sprint 0 regie --regie=rennen:12 --nozoom --tod=20.5 --rquit=24 "${C[@]}"
rec u_rundkurs 0 regie --regie=rennen:15 --nozoom --tod=18.5 --rquit=24 "${C[@]}"
rec u_drift 0 regie --regie=rennen:8 --nozoom --tod=21.5 --rquit=24 "${C[@]}"
# Garage: Tuning, Lack durchblättern, Felgen durchblättern, Autohaus, nächstes Auto
rec u_tuning 0 regie --regie=tuning --rquit=10 --quality=3 --car=kagura --cfg=$CFG
# aus dem ersten Entwurf (Lied-Fassung, verworfen), im Überblick weiter benutzt
# Anflug von oben über Frankfurt (Prachtallee/Main, Brücke, Häuserblöcke), Abend
rec a_anflug 1 regie --regie=anflug:0:1500 --zkind=start --tod=18.8 --rquit=8 "${C[@]}"
# Rostock nachts: Kreuzung, Gasse, Kamera hebt ab (Hintergrund der Endtafel)
rec a_kreuz 1 regie --regie=kreuzung --nozoom --rkran=2.6 --tod=21 --rquit=45 "${C[@]}"
# Golfplatz: drei Rampen (Erde, Stahl über den kleinen Teich, Holz) mit Sprungkamera (offroad_test, rampen:0)
rec a_teich 1 regie --regie=frei --wspawn=gelaende:0 --otest=rampen:0 --nozoom --tod=19.6 --rquit=80 "${C[@]}"
# Kiesgrube am Morgen: über den großen Kieshaufen, Kamera hinter der Landestelle schaut dem Auto nach
rec a_kies 1 regie --regie=kies:1 --nozoom --tod=6.7 --rquit=9 "${C[@]}"
