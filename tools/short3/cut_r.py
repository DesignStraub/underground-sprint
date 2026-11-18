# Reel zum Stand 2.48 (Hochformat, knapp 30 s, mit Musik): Anflug mit Titel, Autobahn-Rennen von Stadt zu Stadt,
# Drift mit Punkten und Boni, Splitscreen, Ortsschild mit Gruß, Karte mit entdeckten Städten, ONE HUMANITY, Endtafel.
# Schnitte auf den Takt von „Drift Phonk“ (zephiramusic, Pixabay, 133 BPM, erster Schlag gleich am Anfang); der
# Spielton (Motor, Reifen) läuft leise darunter, Summe auf -14 LUFS. Einblendungen: promo_overlays --reel48 (ov/r_*.png),
# Aufnahmen: rec_r.sh. Zeiten in den Aufnahmen aus den Marken von regie.gd und aus REEL_ZEITEN (unten, von Hand an den
# Bildern abgelesen, wo es keine Marke gibt).
#
#   SHORT3=<arbeitsordner> python3 tools/short3/cut_r.py    -> release/need_for_geschwindigkeit_reel_2_48.mp4
import os, sys
sys.dont_write_bytecode = True  # kein __pycache__ im Repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schnitt as S

MUSIK = os.path.join(S.P, "music", "zephiramusic-drift-phonk-616472.mp3")
OUT = os.path.join(S.P, "release", "need_for_geschwindigkeit_reel_2_48.mp4")
BILD = os.path.join(S.WORK, "reel_bild.mp4")
BPM = 133.4
ERSTER_SCHLAG = 0.03  # s im Track

# Stellen ohne Regie-Marke (s im Clip), an den Bildern abgelesen
REEL_ZEITEN = {
    "autobahn_los": 4.4,  # „LOS!“ im Autobahn-Rennen (Bild 132)
    "autobahn_ring": 20.5,  # auf dem Ring mit gut 215 km/h, am Ende kommt ein Gegner ins Bild
    "split": 12.0,  # oben Spieler 1 im Rheinufertunnel und hinaus in die Altstadt, unten fährt Spieler 2 hinein
    "schild": 5.2,  # Schild allein, ab 5,9 s fährt das Auto links ins Bild und am Schild vorbei
    "plakat": 1.0,  # beleuchtete Tafel in der Abenddämmerung
}


def plan():
    m = S.mark
    z = REEL_ZEITEN
    seg = []
    # Anflug von oben auf Frankfurt bis hinter das Auto, darüber der Titel
    a0 = m("r_anflug", "anflug beginnt")
    seg.append({"clip": "r_anflug", "start": a0, "beats": 8, "vol": 0.6, "ov": [("r_titel", 0.1, None, 0.25)]})
    # Autobahn-Rennen: Countdown bis LOS!, dann auf dem Ring zwischen den Gegnern
    seg.append({"clip": "r_autobahn", "start": z["autobahn_los"] - 1.6, "beats": 4, "vol": 0.8,
        "ov": [("r_autobahn", 0.05, None, 0.15)]})
    seg.append({"clip": "r_autobahn", "start": z["autobahn_ring"], "beats": 8, "vol": 0.8,
        "ov": [("r_autobahn", 0.0, None, 0.0)]})
    # Drift im Hafen: quer durch die Kurve, links über dem Radar die Drift-Anzeige; endet bei „131 · GROSSER WINKEL ·
    # NAH AM RAND“ (Bild 311/312), ein Bild später streift das Auto die Absperrung („KETTE VERLOREN“)
    dr = m("r_drift", "drift")
    seg.append({"clip": "r_drift", "start": dr + 0.04, "beats": 6, "vol": 0.9, "ov": [("r_drift", 0.1, None, 0.15)]})
    # Splitscreen in Köln: oben Spieler 1, unten Spieler 2
    seg.append({"clip": "r_split", "start": z["split"], "beats": 8, "vol": 0.7, "ov": [("r_split", 0.1, None, 0.15)]})
    # Ortsschild Köln mit „KÖLLE ALAAF!“, das Auto fährt vorbei
    seg.append({"clip": "r_schild", "start": z["schild"], "beats": 6, "vol": 0.7, "ov": [("r_schild", 0.1, None, 0.15)]})
    # Karte: entdeckte Städte, Auswahl wandert
    k0 = m("r_karte", "karte auf")
    seg.append({"clip": "r_karte", "start": k0 + 0.2, "beats": 6, "vol": 0.0, "ov": [("r_karte", 0.1, None, 0.15)]})
    # ONE HUMANITY: beleuchtete Tafel an der Autobahn
    seg.append({"clip": "r_plakat", "start": z["plakat"], "beats": 6, "vol": 0.6, "ov": [("r_plakat", 0.1, None, 0.15)]})
    # Endtafel über dem unscharfen Ring
    seg.append({"kind": "end", "clip": "r_autobahn", "start": z["autobahn_ring"] + 4.0, "beats": 8, "vol": 0.3,
        "ov": [("r_end", 0.0, None, 0.35)]})
    return seg


def main():
    beat = 60.0 / BPM
    tot = S.build_video(plan(), beat, BILD, fade_out=0.6)
    print("Bild geschnitten: %s (%.2f s)" % (BILD, tot))
    tmp = os.path.join(S.WORK, "ton_reel")
    os.makedirs(tmp, exist_ok=True)
    S.with_bed(BILD, MUSIK, OUT, tmp, tot, game_db=-12.0, bed_start=ERSTER_SCHLAG, bed_fade_in=0.0, bed_fade_out=1.2)
    print("Fertig: %s (%.2f s)" % (OUT, S.dur(OUT)))


if __name__ == "__main__":
    main()
