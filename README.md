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
- **Drift** (3): allein auf kleinen, rundum abgesperrten Kursen. Eigenes Fahrverhalten: ist das Auto
  quer, hält Gas den Winkel, Lenken steuert ihn, Gas weg richtet es auf. Querfahren ab 12° gibt Punkte
  (Winkel × Tempo, nah an der Bande ×1,6), verkettete Drifts steigern den Multiplikator bis x5,
  jede Bandenberührung kostet die laufende Kette. Zielpunkte für Platz 3/2/1 stehen im HUD.
- **Wie in Underground:** Near Miss am Verkehr gibt Nitro; wer kurz vor GO Gas gibt (Drehzahl im grünen
  Bereich), schafft einen perfekten Start. Kleinteile am Straßenrand fliegen weg und kosten Tempo statt zu stoppen.

**Start und Ziel wie in Underground:** Vor dem Countdown fliegt die Kamera übers Startfeld (Gas/Enter überspringt),
links und rechts jubelt Publikum auf den Gehwegen, zwischen den Autos steht die Starterin: Arme hoch beim Countdown,
bei GO runter. Im Ziel bleibt das Auto stehen, die Kamera kreist, Fans laufen auf die Straße und tanzen (nach einem
Sieg) oder klatschen. Sonst steht niemand an der Strecke.

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
- **Tunnel** unter Häuserblocks (Kacheln, Lichtbänder, Hall im Sound): Die Fahrbahn taucht vorher in einem offenen
  Betontrog gut 6 m ab (Leitlichter in der Mauer, oben läuft der Gehweg der Stadt weiter) und kommt dahinter wieder hoch.
  **Hochbahn** mit Zug über der Außenspur, **Stadion** mit Flutlicht.
- **Höhen:** Die Altstadt-Route der Gabelungen zweigt nach oben ab und führt als Bergstraße über eine Kuppe (gut 5 m,
  Häuser stehen am Hang, Stützmauern). Mit viel Tempo hebt man an der Kuppe kurz ab. Bergauf zieht es etwas, bergab
  schiebt es. Viele Seitenstraßen steigen hinter ihrer Absperrung sichtbar den Hang hinauf.
- **Abkürzungen:** kurvige Gassen (Kopfsteinpflaster, Lichterketten) und ein Seesprung über eine Schanze. Sie sparen 100–150 m, sind aber enger bzw. brauchen Tempo (ab ca. 120 km/h über den See, sonst Platsch).
- **Bahnübergang mit Bahnhof:** zweigleisig mit Oberleitung, daneben ein kleiner Bahnhof (Bahnsteige mit Dach und
  Stationsschildern, Wartende, Fußgängerbrücke, Empfangsgebäude mit Uhr, S-Bahn-Säule an der Straße, Signale).
  Kommt der Zug, gehen Schranken runter. Wer drauf zufährt, crasht. Auf der rechten Außenspur steht eine Rampe, mit
  genug Tempo springt man über den Zug.
- **Sprünge:** In der Luft kann man nicht lenken, Nitro schiebt aber weiter.
- **Gabelungen:** Vor der Teilung zeigt ein Wegweiser beide Wege. Die Altstadt-Route ist kürzer, aber zweispurig
  mit Gegenverkehr; außen herum geht ein breiter Boulevard. Wer sich nicht entscheidet, landet auf der Verkehrsinsel.
- **Boulevards:** breite Straßen mit bepflanztem Mittelstreifen (auf der Schnellstraße mit Betonleitwand).
- Kreuzungen mit Ampeln, Baustellen, Verkehr in beide Richtungen. Laternen, Mülltonnen, Zeitungsboxen, Parkuhren,
  Schilder, Büsche und Container fliegen weg und kosten etwas Tempo. Sackgassen sind an der Einmündung abgesperrt,
  vor den Trögen lenkt eine schräge Leitwand hinein.
- **Anecken wie in NFSU:** An Wänden und Banden schrammt man entlang und wird parallel gestellt; je flacher der
  Winkel, desto weniger Tempo kostet es (15° ≈ 12 %, 45° ≈ 45 %), nur frontal prallt man ab. Verkehr bestraft härter:
  seitlich abprallen, frontal oder beim Auffahren Dreher und kurz keine Kontrolle. Mittelstreifen laufen spitz aus.

## Fortschritt
Kein Geld: Jeder 1. Platz zählt als Sieg. Siege schalten Autos, Strecken und Tuningteile frei
(Werte in `scripts/catalog.gd`). Gesperrte Teile kann man in der Garage als Vorschau ansehen.

## Musik und Sounds
Musik (`music/`) und Intro-Sound (`assets/intro_sound.mp3`) sind lizenzfreie Tracks von Pixabay.
Weitere mp3/ogg-Dateien in `music/` laufen automatisch mit, in zufälliger Reihenfolge.

Motorsound, Reifen, Nitro und Crashs werden im Spiel erzeugt. Zug, Glocke, Landung, Platschen, Tunnel, Stadion usw.
sind synthetisch erzeugte WAVs in `assets/sfx/` (`python3 tools/make_sfx.py`).

## Grafik
Garage → Einstellungen (wird gespeichert):
- **Grafik Niedrig / Mittel / Hoch:** 3D-Auflösung höchstens 720/900/1080 Zeilen (auf 4K-Bildschirmen wird
  hochskaliert – spart sehr viel), Kantenglättung, Spiegelungen auf nasser Straße (ab Mittel), Schatten in Ecken
  (Hoch), Sichtweite und Detailstufen. Gemessen bei 2560×1440: Niedrig ~140, Mittel/Hoch ~95 fps.
- **Pixel-Look An/Aus**, **V-Sync**, **FPS-Limit**, **Vollbild**.
- Verkehr nach Schwierigkeit: 1 Stern ohne, 2 Sterne wenig, 3 Sterne voller Verkehr.
- **Tempo-Stufe:** am Anfang fahren alle (auch Gegner) mit 72 % Höchsttempo, mit jedem Sieg mehr, ab 20 Siegen volles Tempo.
- **Fahrgefühl:** alle Autos mit Heckantrieb; mit Gas in der Kurve schiebt das Heck raus, im Drift dreht das Auto
  um die Vorderachse. Gas setzt weich ein, Drehmoment folgt der Drehzahl. Bei Tempo ist die Drehrate durch die
  Querbeschleunigung begrenzt (kein Zappeln), Kurven kosten kein Tempo, Rutschen radiert etwas ab. Der Rutschzustand
  ist stufenlos, die Kamera wackelt nur bei Einschlägen.
- **Autos** (9) sind aus Querschnitten gebaut (Radhäuser, Kotflügel-Buckel, Hüften, eingezogenes Glashaus), lose
  angelehnt an RX-7, 350Z, Celica, Silvia, Skyline, AE86, S2000/MX-5, Lancer Evo/Impreza und Supra. Front- und
  Heckschürze sind eigene Teile, Scheinwerfer und Rückleuchten sitzen in der Haut, Türfugen, Spiegel, Griffe,
  Kennzeichen. Unterbodenneon ist ein Lichtteppich auf der Straße.
- **Straße** matt mit vereinzelten Pfützen. Wo kein Haus die Streckenbegrenzung verdeckt, steht ein Zaun.

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
- `scripts/rail_crossing.gd` – Bahnübergang mit Bahnhof und Zug
- `scripts/people.gd` + `shaders/people.gdshader` – Figuren (Publikum, Starterin, Fans, Wartende), Bewegung im Shader
- `scripts/race_show.gd` – Kameraflug, Publikum und Starterin am Start, Zielszene
- `scripts/elevated_rail.gd` – Hochbahn-Zug, `scripts/ambient_sound.gd` – ortsfeste Geräusche (Stadion)
- `tools/track_stats.tscn` – baut alle Strecken und zeigt Kennzahlen
- `tools/overview.tscn` – Bilder aus erhöhter Sicht auf Tunnel, Hochbahn, Stadion, Viertel (`-- --race=1 --out=pfad`)
- `scripts/debug_shot.gd` – nur für Tests/Videos (`-- --drive`, `--demo`, `--at=lake|crossing|alley|fork|tunnel|el|stadium|<viertel>|d:<m>`,
  `--race=n`, `--trace`, `--shot=pfad`, `--times=…`, `--quit=s`, `--intro` (Kameraflug auch im Test),
  `--view=weg:d:quer:höhe:ziel_d:ziel_quer:ziel_höhe` (feste Kamera ohne HUD))
- `tools/short_overlays.gd` – rendert Texttafeln fürs Release-Short
