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

## Events
Alles ist von Anfang an frei wählbar (Garage → Rennen fahren → Art → Event):
- **Sprint** (5): von A nach B gegen 3 Gegner.
- **Rundkurs** (3): 2 Runden gegen 3 Gegner.
- **Drift** (3): allein auf der Strecke. Querfahren ab 12° gibt Punkte (Winkel × Tempo), verkettete Drifts
  steigern den Multiplikator bis x5, ein Crash kostet die laufende Kette. Zielpunkte für Platz 3/2/1 stehen im HUD.

**Freischalten:** Rennsiege (Sprint + Rundkurs) und Driftsiege werden getrennt gezählt. Driftautos (Sakura D2,
Ronin DR) gibt es für Driftsiege, schnelle Autos für Rennsiege, Teile für Siege insgesamt.

## Strecken
- Jede Strecke führt durch mehrere Stadtviertel mit eigenem Stil (Name wird beim Reinfahren eingeblendet):
  - **Downtown:** Glastürme, LED-Videowände, Schilderbrücken
  - **Marktviertel:** Läden, Markisen, Lichterketten über der Straße, Hochbahn
  - **Altstadt:** Backstein, Feuertreppen, Bäume, alte Laternen
  - **Docks:** Hallen, Containerkräne über der Straße, Schornsteine, Natriumdampf-Licht
  - **Chinatown:** Tor, Lampionketten, geschwungene Dächer, senkrechte Leuchtschilder
  - **Schnellstraße:** Lärmschutzwände mit Graffiti, Wegweiser-Brücken, Straßenbrücken
- **Tunnel** unter Häuserblocks (Kacheln, Lichtbänder, Hall im Sound), **Hochbahn** mit Zug über der Außenspur,
  **Stadion** mit Flutlicht und Publikum.
- **Abkürzungen:** kurvige Gassen (Kopfsteinpflaster, Lichterketten) und ein Seesprung über eine Schanze. Sie sparen 100–150 m, sind aber enger bzw. brauchen Tempo (ab ca. 120 km/h über den See, sonst Platsch).
- **Bahnübergang:** Kommt der Zug, gehen Schranken runter. Wer drauf zufährt, crasht. Auf der rechten Außenspur steht eine Rampe, mit genug Tempo springt man über den Zug.
- **Sprünge:** In der Luft kann man nicht lenken, Nitro schiebt aber weiter.
- **Gabelungen:** Vor der Teilung zeigt ein Wegweiser beide Wege. Die Altstadt-Route ist kürzer, aber zweispurig
  mit Gegenverkehr; außen herum geht ein breiter Boulevard. Wer sich nicht entscheidet, landet auf der Verkehrsinsel.
- **Boulevards:** breite Straßen mit bepflanztem Mittelstreifen (auf der Schnellstraße mit Betonleitwand).
- Kreuzungen mit Ampeln, Baustellen, Verkehr in beide Richtungen. Laternen, Mülltonnen, Zeitungsboxen, Parkuhren
  und Schilder fliegen weg; Hydranten, Poller, Telefonzellen, Container und Betonleitwände nicht.

## Fortschritt
Kein Geld: Jeder 1. Platz zählt als Sieg. Siege schalten Autos, Strecken und Tuningteile frei
(Werte in `scripts/catalog.gd`). Gesperrte Teile kann man in der Garage als Vorschau ansehen.

## Musik und Sounds
Musik (`music/`) und Intro-Sound (`assets/intro_sound.mp3`) sind lizenzfreie Tracks von Pixabay.
Weitere mp3/ogg-Dateien in `music/` laufen automatisch mit, in zufälliger Reihenfolge.

Motorsound, Reifen, Nitro und Crashs werden im Spiel erzeugt. Zug, Glocke, Landung, Platschen, Tunnel, Stadion usw.
sind synthetisch erzeugte WAVs in `assets/sfx/` (`python3 tools/make_sfx.py`).

## Grafik
Pixel-Look in der Garage einstellbar: Stark / Mittel / Leicht (Standard) / Aus.

## Export
Vorlagen für Windows, macOS, Linux und Web stehen in `export_presets.cfg` (Godot-Exportvorlagen 4.7.1 nötig).

**Im Browser:** Die Web-Version (`builds/web`, ohne Threads, läuft auf itch.io ohne Sondereinstellungen) nutzt den
einfacheren WebGL-Renderer: keine Spiegelungen auf der Straße, entfernte Kleinteile werden ausgeblendet,
Pixel-Look startet auf „Mittel“. Deshalb gibt es keine Shader-Werte pro Objekt (Häuser sind zu Meshes je
Stadtzelle zusammengefasst, ihre Werte stehen in den Vertexdaten). Lokal testen:
`python3 -m http.server 8060 --directory builds/web`.
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
- `scripts/elevated_rail.gd` – Hochbahn-Zug, `scripts/ambient_sound.gd` – ortsfeste Geräusche (Stadion)
- `tools/track_stats.tscn` – baut alle Strecken und zeigt Kennzahlen
- `tools/overview.tscn` – Bilder aus erhöhter Sicht auf Tunnel, Hochbahn, Stadion, Viertel (`-- --race=1 --out=pfad`)
- `scripts/debug_shot.gd` – nur für Tests/Videos (`-- --drive`, `--demo`, `--at=lake|crossing|alley|tunnel|el|stadium|<viertel>`, `--race=n`, `--trace`, `--shot=pfad`, `--times=…`, `--quit=s`)
- `tools/short_overlays.gd` – rendert Texttafeln fürs Release-Short
