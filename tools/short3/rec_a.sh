#!/bin/bash
# rec_a.sh – alle Aufnahmen für das Short "Neu in 2.39" (cut_a.py), nacheinander nach $SHORT3/clips/a_*.avi.
# Auto: Kagura V10 mit der Optik aus tools/short2/cfgB.txt (weiß, Unterbodenlicht) wie in den Shorts 13 und 14,
# Kamera "Verfolger weit", Grafik Ultra. Dauer gut 10 Minuten (Ton aus, Fenster im Hintergrund).
D="$(cd "$(dirname "$0")" && pwd)"
CFG="$(cat "$D/../short2/cfgB.txt")"
C=(--rcam=1 --quality=3 --car=kagura --cfg=$CFG)
R="$D/rec.sh"
# Anflug von oben über Frankfurt (Prachtallee/Main, Brücke, Häuserblöcke), Abend
"$R" a_anflug regie --regie=anflug:0:1500 --zkind=start --tod=18.8 --rquit=8 "${C[@]}"
# Rostock nachts: zur Kreuzung, Rot, Grün, über die Hauptstraße in die Gasse, Kamera hebt ab (zweimal derselbe Ablauf:
# einmal hinter dem Auto, einmal fest vor der Ampel der Querstraße)
"$R" a_kreuz regie --regie=kreuzung --nozoom --rkran=2.6 --tod=21 --rquit=45 "${C[@]}"
"$R" a_ampel regie --regie=kreuzung --nozoom --rkam=ampel --tod=21 --rquit=26 "${C[@]}"
# Querspange in der Dämmerung: Wegweiser, Ausfahrt Golfplatz, Tor, Fairway, quer
"$R" a_golf regie --regie=golf --nozoom --rv0=22 --tod=18.7 --rquit=40 "${C[@]}"
# Golfplatz: drei Rampen (Erde, Stahl über den kleinen Teich, Holz) mit Sprungkamera (offroad_test, rampen:0)
"$R" a_teich regie --regie=frei --wspawn=gelaende:0 --otest=rampen:0 --nozoom --tod=19.6 --rquit=80 "${C[@]}"
# Kiesgrube am Morgen: über den großen Kieshaufen, Kamera hinter der Landestelle schaut dem Auto nach
"$R" a_kies regie --regie=kies:1 --nozoom --tod=6.7 --rquit=9 "${C[@]}"
# Garage, Autohaus: Kagura fährt auf dem Band, nach 2,2 s fährt der Falke herein
"$R" a_garage regie --regie=garage:2.2 --rquit=7 --quality=3 --car=kagura --cfg=$CFG
