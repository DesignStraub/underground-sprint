# Underground Sprint

Nächtliches Straßenrennen im Stil von NFS Underground, Low-Poly-3D mit Pixel-Look (Godot 4.7).

Ein Spiel von **ONE HUMANITY** – kostenlos auf itch.io.

## Starten
Ordner in Godot 4.7 öffnen (Import), dann F5. Das Spiel startet mit dem ONE-HUMANITY-Intro (überspringbar) und dann in der Garage.

## Steuerung
| Taste | Gamepad | Funktion |
|---|---|---|
| W / ↑ | RT | Gas (auch beim Countdown zum Hochdrehen) |
| S / ↓ | LT | Bremse / Rückwärts |
| A D / ← → | linker Stick | Lenken |
| Leertaste | B | Handbremse (Drift) |
| Shift / N | A | Nitro |
| C | Y | Kamera: Verfolger (Standard) / Stoßstange / Motorhaube |
| R | Back | Auto auf die Straße zurücksetzen |
| M | | Nächster Musiktrack |
| Esc | Start | Pause |
| F11 / Alt+Enter | | Vollbild an/aus |

Nitro lädt sich langsam von selbst auf und schneller beim Driften.

## Strecken
- Jede Strecke führt durch mehrere Stadtviertel (Downtown, Läden, Wohnviertel, Industrie) mit eigenem Baustil.
- **Abkürzungen:** kurvige Gassen (Kopfsteinpflaster, Lichterketten) und ein Seesprung über eine Schanze. Sie sparen 100–150 m, sind aber enger bzw. brauchen Tempo (ab ca. 120 km/h über den See, sonst Platsch).
- **Bahnübergang:** Kommt der Zug, gehen Schranken runter. Wer drauf zufährt, crasht. Auf der rechten Außenspur steht eine Rampe, mit genug Tempo springt man über den Zug.
- **Sprünge:** In der Luft kann man nicht lenken, Nitro schiebt aber weiter.
- Kreuzungen mit Ampeln, Baustellen, Verkehr in beide Richtungen, Laternen und Mülltonnen, die wegfliegen.

## Fortschritt
Kein Geld: Jeder 1. Platz zählt als Sieg. Siege schalten Autos, Strecken und Tuningteile frei
(Werte in `scripts/catalog.gd`). Gesperrte Teile kann man in der Garage als Vorschau ansehen.

## Musik und Sounds
Musik (`music/`) und Intro-Sound (`assets/intro_sound.mp3`) sind lizenzfreie Tracks von Pixabay.
Weitere mp3/ogg-Dateien in `music/` laufen automatisch mit, in zufälliger Reihenfolge.

Motorsound, Reifen, Nitro und Crashs werden im Spiel erzeugt. Zug, Glocke, Landung, Platschen usw.
sind synthetisch erzeugte WAVs in `assets/sfx/` (`python3 tools/make_sfx.py`).

## Grafik
Pixel-Look in der Garage einstellbar: Stark / Mittel / Leicht (Standard) / Aus.

## Export
Vorlagen für Windows, macOS und Linux stehen in `export_presets.cfg` (Godot-Exportvorlagen 4.7.1 nötig).
Texte, Cover und Screenshots für die itch.io-Seite: `release/`.

## Aufbau
- `scripts/catalog.gd` – Autos, Teile, Rennen
- `scripts/player_car.gd` – Fahrphysik, Kamera, Geschwindigkeitsgefühl
- `scripts/engine_audio.gd` – synthetischer Motorsound (Turbo, Blow-off, Reifen, Wind)
- `scripts/track_builder.gd` – prozedurale Stadtstrecke
- `scripts/ai_car.gd` – Gegner
- `scripts/garage.gd` / `scripts/race.gd` – Menü und Rennen
- `scripts/intro.gd` – Studio-Intro
- `scripts/traffic_car.gd` – Verkehr
- `scripts/rail_crossing.gd` – Bahnübergang mit Zug
- `tools/track_stats.tscn` – baut alle Strecken und zeigt Kennzahlen
- `scripts/debug_shot.gd` – nur für Tests/Videos (`-- --drive`, `--demo`, `--at=lake|crossing|alley`, `--shot=pfad`, `--times=…`, `--quit=s`)
- `tools/short_overlays.gd` – rendert Texttafeln fürs Release-Short
