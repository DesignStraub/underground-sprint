#!/bin/bash
# rec_b.sh – alle Aufnahmen für das Short "Aufruf an Künstler" (cut_b.py), nacheinander nach $SHORT3/clips/b_*.avi.
# Gleiches Auto und gleiche Kamera wie rec_a.sh. Stadt-Einfahrten: auf der Auffahrt 45 m vor der Stadt, oben blendet
# das Spiel den Ortsnamen ein; in Aachen dazu unten Titel und Künstler des Stadt-Tracks ("AC", --nomusic: stumm,
# vergrößert mit --rtoastk). Dauer gut 8 Minuten.
D="$(cd "$(dirname "$0")" && pwd)"
CFG="$(cat "$D/../short2/cfgB.txt")"
C=(--rcam=1 --quality=3 --car=kagura --cfg=$CFG)
R="$D/rec.sh"
E=(--nozoom --rvor=45 --rv0=13 --rquit=11 --rtoastk=2.2)
"$R" b_einfahrt15 regie --regie=einfahrt:15 --tod=19.8 "${E[@]}" "${C[@]}"
"$R" b_dom regie --regie=dom --nozoom --rvor=100 --tod=19.8 --rquit=14 "${C[@]}"
"$R" b_einfahrt16 regie --regie=einfahrt:16 --tod=19.3 "${E[@]}" "${C[@]}"
"$R" b_einfahrt20 regie --regie=einfahrt:20 --tod=22 "${E[@]}" "${C[@]}"
"$R" b_einfahrt2 regie --regie=einfahrt:2 --tod=20.4 "${E[@]}" "${C[@]}"
"$R" b_einfahrt4 regie --regie=einfahrt:4 --tod=21.5 "${E[@]}" "${C[@]}"
"$R" b_einfahrt1 regie --regie=einfahrt:1 --tod=19.0 "${E[@]}" "${C[@]}"
# Kreuzberg nachts unter der Hochbahn (U1 zwischen Kottbusser Tor und Schlesischem Tor)
"$R" b_fahrt20 regie --regie=fahrt:20:4300:600 --nozoom --tod=22.3 --rquit=16 "${C[@]}"
