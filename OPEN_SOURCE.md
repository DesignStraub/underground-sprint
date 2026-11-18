# Open-Source-Freigabe

Need for Geschwindigkeit wird nicht verkauft, sondern als Open Source freigegeben: wer Lust hat, baut daran weiter.
Diese Liste hält fest, was vor der Freigabe geprüft ist und was noch zu tun ist. Quellen und Lizenzen aller fremden
Dateien stehen in [`CREDITS.md`](CREDITS.md).

## Geprüft (18. November 2026, Stand 2.47)

- **Keine privaten Daten in der Git-Geschichte:** alle 141 Commits laufen über die GitHub-Adresse
  `…@users.noreply.github.com`; keine private E-Mail.
- **Keine Geheimnisse:** keine Passwörter, Schlüssel, Signatur- oder Notarisierungsdaten in `export_presets.cfg` oder
  in Skripten; das itch-Upload-Skript nutzt das lokale butler-Login.
- **Keine lokalen Pfade mehr:** die zwei Aufnahme-Skripte der Shorts (`tools/short2/rec.sh`, `ovr.sh`) fanden den
  Projektordner über einen festen Pfad mit Benutzernamen, jetzt relativ zum Skript. Die Testwerkzeuge von Claude Code
  (`.claude/`) liegen nicht im Repo und stehen jetzt in `.gitignore`.
- **Aachen-Lied:** war nie eingecheckt (`music/staedte/` steht in `.gitignore`), es bleibt nur im Spiel.
- **Motorklänge und Geräusche:** echte Aufnahmen von Wikimedia Commons und BigSoundBank unter CC BY 3.0/4.0 und CC0,
  alle mit Namensnennung in `CREDITS.md`; die übrigen Geräusche sind synthetisch erzeugt (`tools/make_sfx.py`).
- **Schriften:** Inter, D-DIN, Saira Condensed, Chakra Petch, Rajdhani, alle SIL Open Font License, Lizenztexte liegen
  bei.
- **Grafik:** Vinyls, Plakate, Piktogramme und Texturen sind im Code erzeugt; Autos, Verkehr, Menschen, Häuser und
  Strecken werden im Code gebaut, es gibt keine fremden 3D-Modelle.
- **Autos und Marken:** alle Autos, Marken und Sprüche sind ausgedacht, kein Hersteller wird genannt. Einzelne
  Bestandteile erinnern an echte Modelle (Mirai, GT-R, 2000GT); als Hommage üblich, bei Bedarf leicht umzubenennen.

## Entschieden (18. November 2026)

1. **Code:** MIT ([`LICENSE`](LICENSE)), Copyright ONE HUMANITY.
2. **Eigene Inhalte:** CC BY 4.0 ([`LICENSE-INHALTE.md`](LICENSE-INHALTE.md)); Name, Logo und die drei echten Plakate
   von ONE HUMANITY sind ausgenommen.
3. **Musik von Pixabay:** bleibt im Repo (bewusste Entscheidung). Die Pixabay-Lizenz erlaubt die Nutzung im Spiel,
   aber nicht, die Dateien unverändert einzeln weiterzugeben; das Risiko ist bekannt. Ausweg, falls Pixabay oder ein
   Urheber sich meldet: die MP3s aus dem öffentlichen Repo nehmen und eine Liste mit Links beilegen, oder durch Musik
   mit freier Lizenz (CC0/CC BY) ersetzen.
4. **Git-Geschichte:** ein neues öffentliches Repo nur mit dem heutigen Stand (ein Commit, klein, ohne alte Fassungen
   und Pfade); die ganze Geschichte bleibt im privaten Repo `underground-sprint`. Vorbereitet mit
   `tools/oeffentlich.sh`.

## Pflichten, die in jedem Fall gelten

- **OpenStreetMap:** die abgeleiteten Daten in `scripts/city_data.gd` stehen unter der ODbL 1.0 und müssen auch so
  weitergegeben werden (in `CREDITS.md` und im LICENSE-Hinweis vermerkt).
- **Namensnennung** der CC-BY-Aufnahmen bleibt in `CREDITS.md` und im Spiel (Einstellungen > Quellen & Lizenzen).
- **Godot** (MIT): die Lizenz der Engine liegt jedem Export bei.

## Danach

1. ✓ LICENSE-Dateien angelegt, README mit Abschnitt „Open Source“ (Lizenzen, Bauen mit Godot 4.7).
2. ✓ Öffentlichen Stand vorbereiten: `tools/oeffentlich.sh <Zielordner>` legt einen sauberen Ordner mit einem
   einzigen Commit an (nur die heute eingecheckten Dateien, ohne `.claude/`, Builds und das Aachen-Lied).
3. ✓ Öffentlich seit 18. November 2026: [github.com/DesignStraub/need-for-geschwindigkeit](https://github.com/DesignStraub/need-for-geschwindigkeit) (erst Stand 2.47 als ein Commit, am selben Tag 2.48 nachgezogen; die Geschichte bleibt im privaten Repo).
   Spätere Stände: das öffentliche Repo klonen, dort alle Dateien durch `git archive HEAD` des privaten Repos
   ersetzen und als neuen Commit „Need for Geschwindigkeit <Version>“ hochladen (nur eingecheckte Dateien, also ohne
   `.claude/`, Builds und das Aachen-Lied).
4. itch-Seite: Link zum Repo und den Lizenzen ergänzen (Text steht in `release/ITCH_PAGE.md`, einfügen macht der User).
5. ✓ Reel zum Stand 2.48 (18. November 2026): `release/need_for_geschwindigkeit_reel_2_48.mp4` (nicht im Repo, `*.mp4`
   ist ausgenommen), Aufnahmen und Schnitt mit `tools/short3/rec_r.sh` und `cut_r.py`.
