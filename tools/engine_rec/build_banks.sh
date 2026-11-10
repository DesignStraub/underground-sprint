#!/bin/bash
# Motorklänge aus echten Aufnahmen (ab 2.23). Lädt die Aufnahmen (Lizenzen und Urheber: CREDITS.md), verfolgt die
# Drehzahl, schneidet je Drehzahl eine Schleife unter Gas ("on") und im Schub ("off"), füllt Lücken durch Umtasten
# der nächsten Schleife, glättet und pegelt sie und legt sie nach assets/engine/<aufnahme>/.
# Welches Auto welche Aufnahme nutzt (und in welcher Tonhöhe), steht in scripts/engine_audio.gd (CAR_BANK).
#
#   tools/engine_rec/build_banks.sh <arbeitsordner>     (braucht ffmpeg und einen C-Compiler)
set -e
cd "$(dirname "$0")/../.."
W="${1:?Arbeitsordner angeben}"
mkdir -p "$W/src" "$W/wav" "$W/trk" "$W/loops" "$W/fin"
cc -O2 -o "$W/eng" tools/engine_rec/eng.c -lm
RP=900,1300,1850,2500,3250,4100,5000,6100,7400
UA="EngineSoundResearch/1.0 (game audio project)"
C=https://upload.wikimedia.org/wikipedia/commons

# Bank | Datei | Quelle | Zündungen je Umdrehung | Drehzahlbereich der Spur | Zeitfenster (leer: alles)
BANKS="
i4_turbo|evo6.opus|$C/5/53/Mitsubishi_Lancer_Evolution_VI_-_engine_and_exhaust_sound_%28YouTube_p2UANOqploM%29.opus|2|600 9800|
i4_hoch|s2000.opus|$C/b/bb/Honda_S2000_-_engine_and_exhaust_sound_%28YouTube_aTd8viYxxnU%29.opus|2|600 9800|
i4_sauger|f20c.ogg|$C/0/0d/2002-Honda-F20C.ogg|2|600 9800|
boxer|sti.opus|$C/9/95/Subaru_Impreza_STI_with_modified_exhaust_-_engine_and_exhaust_sound_%28YouTube_7c4BSSRq3bo%29.opus|2|600 9800|
f6|gt3rs.opus|$C/0/0b/Porsche_911_GT3_RS_-_engine_and_exhaust_sound_%28YouTube_hpwTF8TXcaA%29.opus|3|600 9800|12.5-100
i6|supra.opus|$C/f/fe/Toyota_Supra_%28A80%29_-_engine_and_exhaust_sound_%28YouTube_YlRjnMnHRO4%29.opus|3|600 9800|
wankel|rx7.opus|$C/3/35/Mazda_RX-7_-_engine_and_exhaust_sound_%28YouTube_4z0y1H2REvE%29.opus|2|600 9800|
v10|m5e60.opus|$C/3/35/BMW_M5_E60_-_engine_and_exhaust_sound_%28YouTube_lFomO9-3vdM%29.opus|5|600 9800|
v12|aventador.opus|$C/9/9b/Lamborghini_Aventador_-_engine_and_exhaust_sound_%28YouTube_oMKxhIcSmZs%29.opus|6|600 9500|
bus|manbus.ogg|$C/6/69/WWS_CityBusMANSG220engine.ogg|3|450 2800|
"
echo "$BANKS" | while IFS='|' read -r bank file url fpr range win; do
	[ -z "$bank" ] && continue
	[ -s "$W/src/$file" ] || { curl -sSL -A "$UA" -o "$W/src/$file" "$url"; sleep 20; }
	ffmpeg -nostdin -v error -y -i "$W/src/$file" -ac 1 -ar 22050 "$W/wav/$bank.wav"
	"$W/eng" track "$W/wav/$bank.wav" "$W/trk/$bank.csv" "$W/trk/$bank.ppm" "$fpr" $range 2>/dev/null
	mkdir -p "$W/loops/$bank" "$W/fin/$bank"
	"$W/eng" loops "$W/wav/$bank.wav" "$W/trk/$bank.csv" "$W/loops/$bank" $RP fpr="$fpr" oe=0.6 h=0.5 $win 2>/dev/null || true
	# Boxer: die Schub-Schleifen der Aufnahme springen in die halbe Ordnung (klingt eine Oktave tiefer): Gas-Schleifen nehmen
	if [ "$bank" = boxer ]; then
		for r in 1300 1850 2500 3250 4100 5000 6100 7400; do
			[ -f "$W/loops/$bank/on_$r.wav" ] && cp "$W/loops/$bank/on_$r.wav" "$W/loops/$bank/off_$r.wav"
		done
	fi
	"$W/eng" fill "$W/loops/$bank" $RP 2>/dev/null
	"$W/eng" finish "$W/loops/$bank" "$W/fin/$bank" $RP
	echo "$bank: $(ls "$W/fin/$bank" | wc -l | tr -d ' ') Schleifen"
done

# ins Projekt: je Aufnahme ein Ordner; Bus und Verkehr als einzelne Schleifen
for bank in i4_turbo i4_hoch i4_sauger boxer f6 i6 wankel v10 v12; do
	mkdir -p "assets/engine/$bank"
	cp "$W/fin/$bank/"*.wav "assets/engine/$bank/"
done
cp "$W/fin/bus/on_900.wav" assets/engine/traffic_bus_900.wav
# Verkehr (Pkw): Turbo-Vierzylinder im Schub, auf 2100/min umgetastet
mkdir -p "$W/traffic"
cp "$W/fin/i4_turbo/off_1850.wav" "$W/traffic/off_1850.wav"
"$W/eng" fill "$W/traffic" 1850,2100 2>/dev/null
cp "$W/traffic/off_2100.wav" assets/engine/traffic_car_2100.wav
echo fertig
