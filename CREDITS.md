# Quellen und Lizenzen

## Motorklänge (seit 2.23)
Die Schleifen in `assets/engine/` sind aus echten Aufnahmen geschnitten (`tools/engine_rec/build_banks.sh`):
Drehzahl verfolgt, Abschnitte auf feste Drehzahlen geglättet, zu nahtlosen Schleifen zusammengesetzt, gefiltert und
im Pegel angeglichen. Es sind also bearbeitete Fassungen der Originale. Alle Originale liegen auf Wikimedia Commons.

| Ordner | Aufnahme | Urheber | Lizenz |
|---|---|---|---|
| `i4_turbo` | [Mitsubishi Lancer Evolution VI – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Mitsubishi_Lancer_Evolution_VI_-_engine_and_exhaust_sound_(YouTube_p2UANOqploM).opus) | prone (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `i4_hoch` | [Honda S2000 – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Honda_S2000_-_engine_and_exhaust_sound_(YouTube_aTd8viYxxnU).opus) | Y Racing (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `i4_sauger` | [2002 Honda F20C](https://commons.wikimedia.org/wiki/File:2002-Honda-F20C.ogg) | Tyler Riddle | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `boxer` | [Subaru Impreza STI with modified exhaust – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Subaru_Impreza_STI_with_modified_exhaust_-_engine_and_exhaust_sound_(YouTube_7c4BSSRq3bo).opus) | Great Explorer (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `f6` | [Porsche 911 GT3 RS – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Porsche_911_GT3_RS_-_engine_and_exhaust_sound_(YouTube_hpwTF8TXcaA).opus) | NEW CARS 2015 Official (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `i6` | [Toyota Supra (A80) – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Toyota_Supra_(A80)_-_engine_and_exhaust_sound_(YouTube_YlRjnMnHRO4).opus) | Fabio Rojas Pichardo (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `wankel` | [Mazda RX-7 – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Mazda_RX-7_-_engine_and_exhaust_sound_(YouTube_4z0y1H2REvE).opus) | Taz Ringer (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `v10` | [BMW M5 E60 – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:BMW_M5_E60_-_engine_and_exhaust_sound_(YouTube_lFomO9-3vdM).opus) | asTUBE (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `v12` | [Lamborghini Aventador – engine and exhaust sound](https://commons.wikimedia.org/wiki/File:Lamborghini_Aventador_-_engine_and_exhaust_sound_(YouTube_oMKxhIcSmZs).opus) | Super Cars for you (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |
| `traffic_bus_900.wav` | [City Bus MAN SG 220 – engine](https://commons.wikimedia.org/wiki/File:WWS_CityBusMANSG220engine.ogg) | Work With Sounds / Technical Museum of Slovenia | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `traffic_car_2100.wav` | aus `i4_turbo` (siehe oben) | prone (YouTube) | [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) |

Die Autos im Spiel sind erfunden; welche Aufnahme ein Auto nutzt, steht in `scripts/engine_audio.gd` (`CAR_BANK`).

## Reifenquietschen (seit 2.23)
`assets/sfx/skid.wav`: Ausschnitt aus [Screeching Tires #1](https://bigsoundbank.com/sound-2368-crissement-de-pneus-1.html)
von Joseph Sardin, BigSoundBank, [CC0](https://creativecommons.org/publicdomain/zero/1.0/) (gemeinfrei), als nahtlose
Schleife geschnitten.

## Bahnübergang (seit 2.24)
| Datei | Aufnahme | Urheber | Lizenz |
|---|---|---|---|
| `assets/sfx/bell.wav` | [BÜ DE, Schrankensignal, 5](https://commons.wikimedia.org/wiki/File:B%C3%9C_DE,_Schrankensignal,_5.ogg) (Warnton beim Schließen der Schranken, zwei Töne als Schleife) | Renardo la vulpo | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |
| `assets/sfx/horn.wav` | [WWS Signalhorn (train horn)](https://commons.wikimedia.org/wiki/File:WWS_Signalhorntrainhorn.ogg) (erster Ton, gekürzt) | Work With Sounds / Konrad Gutkowski | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| `assets/sfx/rumble.wav` | [Freight train passes Phelan, startles Canadian geese](https://commons.wikimedia.org/wiki/File:Freight_train_passes_Phelan,_startles_Canadian_geese.flac) (4 s Rollen als Schleife, auch für die Hochbahn) | Extemporalist | [CC0](https://creativecommons.org/publicdomain/zero/1.0/) |

## Musik
Tracks in `music/` und der Intro-Sound: Pixabay ([Pixabay Content License](https://pixabay.com/service/license-summary/),
frei auch für kommerzielle Nutzung, ohne Namensnennung). Der Dateiname nennt Künstler, Titel und Pixabay-Nummer
(`pixabay.com/music/…-<Nummer>/`).

| Liste | Tracks |
|---|---|
| Fahrt (Phonk, Trap) | absolutesound „Hard Phonk“, Artissizm „Hard Drift Phonk“, Sub_Clair „Drift Phonk“, „Phonk Hard“, alexzavesa „Dark Trap – Most Dangerous“, „Devil Forces“, Kulakovka „Phonk Reel“, „Gym Phonk“ |
| Garage (Hip-Hop) | kontraa „Goldn – UK Drill“, AudioDollar „Rap Beat“, agerabeatz „Spray“, AtlasAudio „90s Hip Hop“, SolarFLEX „Hip-Hop Boom Bap“, SoundSurfer „Street Hip-Hop“, Sub_Clair „Hip Hop Instrumental“ |
| Beide (West Coast, G-Funk) | HarmonixHub „G Funk I“, 99Instrumentals „G-Funk Old School Hip-Hop“, Colt_Fingaz „Lowrider Gang“, catch22music „Cruising West Coast Hip Hop“, TouchProRecords „California (West Coast Hip Hop Instrumental)“, -SunSet- „West Coast Beat“ |
| Garage (West Coast, dunkel) | YuraSoop „West Coast Beats“, ArtIssizm „West Coast“, CNABeatsAfrica „West Coast Rap Beat“, Colt_Fingaz „Hip Hop West Coast Type Beat“, mastermath „West Coast Hip Hop Type Beat“, kond1 „DS Tales“, 5xBeatz „Dope West Coast Type Beat“, vaitsez „Gangster – Gangsta Beat“, „Mafia Gangster Criminal Beat“, KrissMcMass „Gangsta Music Theme“ |

## Schrift
Menüs und Anzeigen seit 2.27: Saira Condensed von Omnibus-Type (The Saira Project Authors), SIL Open Font License 1.1
(`assets/fonts/saira/OFL.txt`), von Google Fonts. Ladenschilder und Kennzeichen: D-DIN von Datto, SIL Open Font
License 1.1 (`assets/fonts/COPYING.txt`).

## Kartendaten
Straßen und Gebäude der Städte-Strecken: © OpenStreetMap-Mitwirkende, ODbL (openstreetmap.org/copyright).

## Alle anderen Klänge
Synthetisch erzeugt (`tools/make_sfx.py`).
