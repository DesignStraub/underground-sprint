# Need for Geschwindigkeit

Nächtliches Straßenrennen im Stil der frühen 2000er (früher „Underground Sprint“), Low-Poly-3D mit Pixel-Look (Godot 4.7).

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
| Shift / N | A | Nitro (leer ist leer: erst loslassen, dann lädt es nach) |
| E / Q | RB / LB | Drag: hoch-/runterschalten (A/D wechselt dort die Spur) |
| C | Y | Kamera: Verfolger (Standard) / Stoßstange / Motorhaube |
| R | Back | Auto auf die Straße zurücksetzen |
| M | | Nächster Musiktrack |
| Esc | Start | Pause |
| F11 / Alt+Enter | | Vollbild an/aus |

Nitro lädt sich langsam von selbst auf und schneller beim Driften.

## Events
Alles ist von Anfang an frei wählbar (Garage → Rennen fahren → Art → Event):
- **Sprint** (7): von A nach B gegen 3 Gegner.
- **Rundkurs** (5): 2–3 Runden gegen 3 Gegner.
- **Drag** (3): geradeaus gegen 3 Gegner, wie in Underground. Gelenkt wird automatisch, A/D wechselt die Spur,
  geschaltet wird von Hand (E/Q). Großer Drehzahlmesser mit grünem Schaltbereich und Schaltlicht: dort schalten ist
  „perfekt“ (kaum Zugkraftunterbrechung, kleiner Schub), zu früh kostet Zug, wer im Begrenzer bleibt, überhitzt den
  Motor (Temperaturbalken) bis zum Motorschaden. Auffahren oder frontal in den Verkehr ist Totalschaden. Start im
  grünen Drehzahlbereich = perfekter Start, Nitro und Near Miss wie sonst. Entfernungstafeln alle 200 m, Viertelmeile.
- **Drift** (3): allein auf kleinen, rundum abgesperrten Kursen. Eigenes Fahrverhalten: ist das Auto
  quer, hält Gas den Winkel, Lenken steuert ihn, Gas weg richtet es auf. Querfahren ab 12° gibt Punkte
  (Winkel × Tempo, nah an der Bande ×1,6), verkettete Drifts steigern den Multiplikator bis x5,
  jede Bandenberührung kostet die laufende Kette. Zielpunkte für Platz 3/2/1 stehen im HUD.
- **Städte** (5): echte Strecken durch Aachen, Würzburg, Bad Kissingen, Tauberbischofsheim und Hammelburg
  (eigene Rubrik im Menü, siehe unten).
- **Wie in Underground:** Near Miss am Verkehr gibt Nitro; wer kurz vor GO Gas gibt (Drehzahl im grünen
  Bereich), schafft einen perfekten Start. Kleinteile am Straßenrand fliegen weg und kosten Tempo statt zu stoppen.

**Start und Ziel wie in Underground:** Vor dem Countdown fliegt die Kamera übers Startfeld (Gas/Enter überspringt),
links und rechts jubelt Publikum auf den Gehwegen, zwischen den Autos steht die Starterin: Arme hoch beim Countdown,
bei GO runter. Im Ziel bleibt das Auto stehen, die Kamera kreist, Fans laufen auf die Straße und tanzen (nach einem
Sieg) oder klatschen. Sonst steht niemand an der Strecke.

**Freischalten:** Rennsiege (Sprint + Rundkurs) und Driftsiege werden getrennt gezählt. Driftautos (Sakura D2,
Ronin DR) gibt es für Driftsiege, schnelle Autos für Rennsiege, Teile für Siege insgesamt.

## Städte (echte Orte)
Die Strecken folgen echten Straßen, die Wahrzeichen stehen an ihrem Platz, die Häuser hinter der Straßenfront
haben die echten Grundrisse. Kartendaten © OpenStreetMap-Mitwirkende (ODbL, openstreetmap.org/copyright).
- **Aachen Grabenring** (Rundkurs, 2 Runden, 2,8 km): Templergraben am SuperC der RWTH vorbei, Seilgraben,
  Friedrich-Wilhelm-Platz am Elisenbrunnen, Theater, Kapuzinergraben, Löhergraben, Karlsgraben. In der Mitte Dom
  (Oktogon mit Faltkuppel, gläserne Chorhalle, Westturm) und Rathaus mit Granusturm, Marktturm und Karlsbrunnen.
- **Würzburg Mainufer** (Sprint, 5,4 km): Röntgenring, Rennweg an der Residenz (Ehrenhof, Frankoniabrunnen) vorbei,
  Friedrich-Ebert-Ring, Sanderring, über die Ludwigsbrücke, unter der Festung Marienberg (angestrahlt, auf dem
  Weinberg) entlang, über die Friedensbrücke zurück und den Main entlang zum Alten Kranen. Dazwischen Dom St. Kilian,
  Marienkapelle, Käppele und die Alte Mainbrücke mit zwölf Heiligenfiguren und Leuten beim Brückenschoppen.
- **Bad Kissingen Kurmeile** (Sprint, 2,9 km): am Regentenbau und Arkadenbau vorbei, Spielbank im Luitpoldpark,
  über die Fränkische Saale durch die Stadt und am Fluss entlang zum Gradierbau der Oberen Saline.
- **Tauberbischofsheim Altstadt** (Rundkurs, 3 Runden, 1,8 km): Schmiederstraße, Vitryallee, Hauptstraße rund um die
  Altstadt mit Türmersturm und Kurmainzischem Schloss, neugotischem Rathaus und St. Martin.
- **Hammelburg Saaleck** (Sprint, 2,5 km): Berliner Straße mit Bahnübergang dort, wo die Strecke Gemünden–Bad Kissingen
  kreuzt (in echt führt die Straße auf einer Brücke darüber, im Spiel kommt der Zug ebenerdig), am
  Renaissance-Rathaus mit Treppenturm und Marktbrunnen vorbei, über die Saale und den Schlossberg hinauf, oben auf dem
  Weinberg Schloss Saaleck.

Dazu: gelbes Ortsschild am Start, Straßenschilder, der echte Straßenname wird beim Abbiegen eingeblendet, Flüsse mit
Ufermauern und Steinbrücken, Hügel mit Weinbergen, Fachwerk, Putzfassaden, Ziegel- und Schieferdächer, Läden der
Stadt (Printen, Bocksbeutel, Kurcafé, Fechtclub, Häckerwirtschaft …). Die Straßen sind breiter als in echt
(vier Spuren), enge Ecken sind auf mindestens 38 m Radius abgerundet, die Wahrzeichen rücken bei Bedarf ein Stück
von der Straße weg. Neu erzeugen: `python3 tools/osm_city.py <ordner-mit-overpass-json>` (Abfragen und Wegpunkte im
Skript), schreibt `scripts/city_data.gd`.

## Strecken
- Jede Strecke führt durch mehrere Stadtviertel mit eigenem Stil (Name wird beim Reinfahren eingeblendet):
  - **Bankenviertel:** Glastürme, LED-Videowände, Schilderbrücken
  - **Marktviertel:** Läden, Markisen, Lichterketten über der Straße, Hochbahn
  - **Altstadt:** Backstein, Feuertreppen, Bäume, alte Laternen
  - **Hafen:** Hallen, Containerkräne über der Straße, Schornsteine, Natriumdampf-Licht
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

## Menüs
Im Stil von NFS Underground (`scripts/ui_style.gd`): schräge Leisten, Neongrün für die Auswahl, kursive
DIN-Schmalschrift, große Abschnittstitel (GARAGE, RENNEN, TUNING, AUTOHAUS), Leistungsbalken des Autos (mit
Motor-Tuning), Tastenleiste unten, wechselnde Tipps oben rechts. Pause und Ergebnis im gleichen Look.

## Tuning wie in NFS
Garage → Tuning → **Optik** (Lack, Felgen, Spoiler, Bodykit, Folierung, Unterbodenneon, Scheiben) oder **Leistung**
(Motor, Turbo, Nitro, Fahrwerk, Reifen) → Teil wählen: die Kamera fährt an das Teil (Felge, Heck, Unterboden …),
beim Motor und Turbo geht die Haube auf (Ventildeckel in der Farbe der Stufe, Pilzfilter, Turbolader, Domstrebe),
beim Nitro der Kofferraum (Flaschen je nach Stufe). Vorschau beim Auswählen, Einbauen mit Enter, gesperrte Teile
zeigen die nötigen Siege. Leistungsteile wirken wirklich (`Catalog.stats`): Motor und Turbo auf Schub und Endtempo,
Fahrwerk und Reifen auf Grip und Lenkung, das Fahrwerk legt das Auto tiefer; die Balken zeigen Gewinn (cyan) und
Verlust (rot) gegenüber dem eingebauten Teil. Ab Werk: Bremsscheiben mit Sätteln (rot ab der ersten Leistungsstufe),
Frontlippe, Diffusor, Chrom-Endrohre (größer ab Motor+Turbo 2), Ladeluftkühler im Einlass mit Turbo, Haubenschlitze
mit Motor Stufe 3.

## Handy und Tablet (Browser)
Auf Touchgeräten erscheinen Knöpfe: links Lenken (Daumen kann rüberrutschen), rechts Gas, Bremse, Handbremse, Nitro,
im Drag Hoch-/Runterschalten statt Bremse; Pause oben in der Mitte, Drehzahlmesser klein oben rechts. Hochkant kommt
ein Hinweis zum Drehen. Auf Handys werden in den Städten nur die Häuser nahe der Strecke gebaut, Grafik startet
niedrig. Zum Testen am Rechner: `-- --touch`.

## Sprachen
Englisch und Deutsch: Beim ersten Start fragt das Spiel (Englisch vorausgewählt), später unter Einstellungen → Sprache.
Übersetzungen in `scripts/i18n.gd` (Schlüssel sind die deutschen Texte, `tr()`); Titel, Ortsnamen, Läden und Schilder
in der Welt bleiben deutsch.

## Schrift und Texte
Alles auf Deutsch, im Ton von NFS Underground (KNAPP VORBEI +NITRO, DRIFT +NITRO, SPRUNG, Tuning-Marken auf den
Dächern, Ladetipps im Menü). Schrift überall im Stil der deutschen Straßenschilder (DIN 1451):
D-DIN von Datto, SIL Open Font License 1.1 (`assets/fonts/COPYING.txt`). Alte englische Eventnamen werden im
Spielstand automatisch umgeschrieben, der Spielstand aus „Underground Sprint“ wird beim ersten Start übernommen.

## Grafik
Garage → Einstellungen (wird gespeichert):
- **Grafik Niedrig / Mittel / Hoch:** 3D-Auflösung höchstens 720/900/1080 Zeilen (auf 4K-Bildschirmen wird
  hochskaliert – spart sehr viel), Kantenglättung, Spiegelungen auf nasser Straße (ab Mittel), Schatten in Ecken
  (Hoch), Sichtweite und Detailstufen. Gemessen bei 2560×1440: Niedrig ~140, Mittel/Hoch ~95 fps.
- **Pixel-Look An/Aus**, **V-Sync**, **FPS-Limit**, **Vollbild**.
- Verkehr nach Schwierigkeit: 1 Stern ohne, 2 Sterne wenig, 3 Sterne voller Verkehr.
- **Tempo-Stufe:** am Anfang fahren alle (auch Gegner) mit 72 % Höchsttempo, mit jedem Sieg mehr, ab 20 Siegen volles Tempo.
- **Fahrgefühl:** alle Autos mit Heckantrieb; mit Gas in der Kurve schiebt das Heck raus, im Drift dreht das Auto
  um die Vorderachse. Gas setzt weich ein, Drehmoment folgt der Drehzahl, das Getriebe schaltet mit Hysterese (kein
  Pendeln an Gangwechseln). Langsam begrenzt der Wendekreis (5,2 m), bei Tempo die Querbeschleunigung (2,1–2,7 g je
  Auto, bei Topspeed etwas weniger). Kurven kosten kein Tempo, an der Haftgrenze rutscht das Auto sichtbar ein paar
  Grad; Rutschen radiert etwas ab, würgt das Tempo aber nicht ab. Anbremsen in die Kurve lässt das Heck leicht kommen,
  Handbremse dreht bei 80 km/h in 0,8 s um gut 90°. Bremsen ~2,4 g, Gegenlenken geht schneller als Einlenken.
  Karosserie wankt nach der echten Querbeschleunigung, taucht beim Bremsen ein; die Verfolgerkamera dreht leicht
  verzögert mit und bleibt nah am Auto (im Stand 4,7 m, bei Tempo knapp 7 m, Blickwinkel 58°–80°). Messwerte aller Autos: `tools/handling_lab.tscn`.
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
- `scripts/city_builder.gd` – Wahrzeichen der Städte-Strecken (Dom, Residenz, Festung, Gradierbau, Türmersturm …)
- `scripts/city_data.gd` – Straßenverläufe, Flüsse, Gebäude und Wahrzeichen-Positionen (erzeugt von `tools/osm_city.py`)
- `scripts/people.gd` + `shaders/people.gdshader` – Figuren (Publikum, Starterin, Fans, Wartende), Bewegung im Shader
- `scripts/race_show.gd` – Kameraflug, Publikum und Starterin am Start, Zielszene
- `scripts/elevated_rail.gd` – Hochbahn-Zug, `scripts/ambient_sound.gd` – ortsfeste Geräusche (Stadion)
- `tools/track_stats.tscn` – baut alle Strecken und zeigt Kennzahlen
- `tools/handling_lab.tscn` – Fahrphysik-Messlabor (0–100, Bremsweg, Kurvenradius, Querbeschleunigung, Schräglauf,
  Lenkansprechen, Handbremse) auf leerer Fläche: `--headless --fixed-fps 60 … -- --cars=kaizen,kaze`
- `tools/overview.tscn` – Bilder aus erhöhter Sicht auf Tunnel, Hochbahn, Stadion, Viertel (`-- --race=1 --out=pfad`)
- `scripts/debug_shot.gd` – nur für Tests/Videos (`-- --drive`, `--demo`, `--at=lake|crossing|alley|fork|tunnel|el|stadium|<viertel>|d:<m>`,
  `--race=n`, `--trace`, `--shot=pfad`, `--times=…`, `--quit=s`, `--intro` (Kameraflug auch im Test),
  `--view=weg:d:quer:höhe:ziel_d:ziel_quer:ziel_höhe` (feste Kamera ohne HUD), `--look=wahrzeichen:höhe:blickhöhe:abstand[:d]`
  (Kamera auf ein Wahrzeichen der Städte-Strecken), `--racelog` (Rennverlauf alle 3 s), `--tune=engine` (Garage direkt
  in einer Tuning-Kategorie), `--touch` (Touch-Knöpfe am Rechner); im Drag schaltet der Autopilot im
  grünen Bereich, `--lateshift` erst im Begrenzer, `--noshift` gar nicht, `--nolanes` ohne Spurwechsel, `--dragcrash`
  setzt Verkehr vor das Auto)
- `tools/short_overlays.gd` – rendert Texttafeln fürs Release-Short
- `tools/trailer_cards.tscn` – Texttafeln für den Trailer (Titel, Abspann, Sprüche, gelbe Ortsschilder): `-- --out=ordner`
