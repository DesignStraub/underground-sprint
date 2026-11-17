# Überblick-Short (deutsch, stumm): das ganze Spiel in 33 s. Karte, Anflug, Autobahn mit Herausforderer und Duell,
# Fahr-/Drift-Modus mit Q, Rennen (Sprint, Rundkurs, Drift), Golfplatz und Kiesgrube, Tuning und Autowechsel, Endtafel.
# Ohne Ton (nur eine stille AAC-Spur, damit jede Plattform es nimmt): die Texte tragen, jeder knapp 2 s im Bild.
# Schnitte nach Bild, kein Taktraster. Zeiten in den Aufnahmen aus ihren Marken (regie.gd, rec_u.sh).
#
#   python3 tools/short3/cut_u.py    -> release/need_for_geschwindigkeit_short_ueberblick.mp4
import os, sys
sys.dont_write_bytecode = True  # kein __pycache__ im Repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schnitt as S

OUT = os.path.join(S.P, "release", "need_for_geschwindigkeit_short_ueberblick.mp4")
BILD = os.path.join(S.WORK, "short_ueberblick_bild.mp4")


# Szenen in Sekunden (build_video mit "beats" = Sekunden), Texte (png in ov/, von, bis, Einblenden)
def plan():
    m = S.mark
    seg = []
    # die ganze Karte: Auswahl wandert über die Städte
    k0 = m("u_karte", "karte auf")
    seg.append({"clip": "u_karte", "start": k0 + 0.25, "beats": 4.2,
                "ov": [("u_karte1", 0.15, 2.1, 0.2), ("u_karte2", 2.15, None, 0.15)]})
    # Anflug von oben auf Frankfurt bis zur Landung hinter dem Auto
    a0 = m("a_anflug", "anflug beginnt")
    seg.append({"clip": "a_anflug", "start": a0, "beats": 2.8, "ov": [("u_anflug", 0.1, None, 0.15)]})
    # Autobahnring mit Verkehr: der Herausforderer zieht links vorbei (oben "HERAUSFORDERER: … Enter: Duell starten"),
    # Enter, das Duell beginnt (Leiste oben), er setzt sich ab
    # (eine durchgehende Einstellung, der Text wechselt mit Enter)
    vb = m("u_ring", "herausforderer vorbei")
    en = m("u_ring", "enter")
    r0 = vb - 0.9
    seg.append({"clip": "u_ring", "start": r0, "beats": en - r0 + 2.0,
                "ov": [("u_heraus", 0.1, en - r0 - 0.05, 0.15), ("u_duell", en - r0 + 0.05, None, 0.15)]})
    # Q: Drift-Modus (links unten blendet das Spiel DRIFT-MODUS ein, --rfeedk=2), dann quer durch die Kurve, Punkte
    q = m("u_modus", "q")
    dr = m("u_modus", "drift")
    seg.append({"clip": "u_modus", "start": q - 0.3, "beats": 1.9, "ov": [("u_modus", 0.1, None, 0.15)]})
    # quer bis "DRIFT 130" unten in der Mitte (gleich danach streift das Auto die Bande)
    seg.append({"clip": "u_modus", "start": dr + 0.3, "beats": 2.45, "ov": [("u_driftpunkte", 0.1, None, 0.15)]})
    # Rennen: in der Lichtsäule (Farbe der Art) "Enter: Rennen starten", dann der Countdown über drei Rennen weiter:
    # Sprint (3, 2), Rundkurs (2, 1), Drift (1, LOS!, die Gegner fahren los); unter der Zahl jeweils die Art in ihrer
    # Farbe. "rennen los" = LOS! (race.gd: je Zahl 1 s, davor lädt die Strecke)
    seg.append({"clip": "u_sprint", "start": m("u_sprint", "enter") - 1.35, "beats": 1.35,  # bis Enter: danach Ladebild
                "ov": [("u_rennen", 0.1, None, 0.15)]})
    seg.append({"clip": "u_sprint", "start": m("u_sprint", "rennen los") - 2.25, "beats": 1.1,
                "ov": [("u_rennen", 0.0, None, 0.0)]})
    seg.append({"clip": "u_rundkurs", "start": m("u_rundkurs", "rennen los") - 1.15, "beats": 1.0,
                "ov": [("u_rennen", 0.0, None, 0.0)]})
    seg.append({"clip": "u_drift", "start": m("u_drift", "rennen los") - 0.5, "beats": 1.8,
                "ov": [("u_rennen", 0.0, None, 0.0)]})
    # Gelände: Teich-Sprung mit Sprungkamera, Flug über den Kieshaufen
    land = m("a_teich", "flug landung", 2)
    seg.append({"clip": "a_teich", "start": land - 2.1, "beats": 2.0, "ov": [("u_gelaende", 0.1, None, 0.15)]})
    fly = m("a_kies", "flug ab", 1)
    seg.append({"clip": "a_kies", "start": fly + 0.4, "beats": 1.7, "ov": [("u_gelaende", 0.0, None, 0.0)]})
    # Garage: Lack und Felgen durchblättern, dann im Autohaus das nächste Auto
    lk = m("u_tuning", "tuning lack")
    fg = m("u_tuning", "tuning felgen")
    au = m("u_tuning", "tuning auto")
    seg.append({"clip": "u_tuning", "start": lk + 0.75, "beats": 1.4, "ov": [("u_tuning", 0.1, None, 0.15)]})
    seg.append({"clip": "u_tuning", "start": fg + 0.75, "beats": 1.4, "ov": [("u_tuning", 0.0, None, 0.0)]})
    seg.append({"clip": "u_tuning", "start": au - 0.2, "beats": 2.0, "ov": [("u_autos", 0.1, None, 0.15)]})
    # Endtafel über der unscharfen Altstadt von Rostock (die Kamera hebt über der Gasse ab)
    seg.append({"kind": "end", "clip": "a_kreuz", "start": m("a_kreuz", "kran", 1, 24.8) + 3.6, "beats": 3.6,
                "ov": [("u_end", 0.0, None, 0.35)]})
    return seg


def main():
    tot = S.build_video(plan(), 1.0, BILD, fade_out=0.5)
    print("Bild geschnitten: %s (%.2f s)" % (BILD, tot))
    # stumm: das Bild mit einer stillen Tonspur (AAC 48 kHz Stereo)
    S.run(["ffmpeg", "-y", "-loglevel", "error", "-i", BILD, "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-map", "0:v",
           "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-shortest", "-movflags", "+faststart",
           OUT])
    print("Fertig: %s (%.2f s, stumm)" % (OUT, S.dur(OUT)))


if __name__ == "__main__":
    main()
