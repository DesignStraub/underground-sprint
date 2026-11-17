# Short "Aufruf an Künstler" (deutsch): in Aachen läuft "AC" von Bruder Jakob x Jonas Platin, jede Stadt soll ihren
# Sound haben, Künstler schreiben Stadt und Song in die Kommentare (release/SHORTS.md Nr. 16).
# Musik: Ausschnitt aus "AC" (168 BPM gemessen, ein Schlag 0,357 s; erster Schlag bei 0,076 s): vom 12. Schlag an
# (4,36 s, kurz vor dem Einsatz bei 5,79 s) knapp 30 s, weich ein- und ausgeblendet. Schnitte auf die Schläge.
#
#   python3 tools/short3/cut_b.py [--musik datei.mp3]   -> release/need_for_geschwindigkeit_short_kuenstler.mp4
# Standard für --musik: music/staedte/aachen-Bruder_Jakob_x_Jonas_Platin-AC.mp3 (nicht im Repo, mit Erlaubnis im Spiel)
import os, sys, tempfile
sys.dont_write_bytecode = True  # kein __pycache__ im Repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schnitt as S

BPM = 168.0
BEAT = 60.0 / BPM
FIRST = 0.076  # erster Schlag im Lied (s)
START_BEAT = 12  # Ausschnitt beginnt mit diesem Schlag des Lieds (Einsatz der Musik: Schlag 16)
MUSIK = os.path.join(S.P, "music", "staedte", "aachen-Bruder_Jakob_x_Jonas_Platin-AC.mp3")
OUT = os.path.join(S.P, "release", "need_for_geschwindigkeit_short_kuenstler.mp4")
BILD = os.path.join(S.WORK, "short_kuenstler_bild.mp4")

FREI = ("b_frei", 0.0, None, 0.0)
# Stadt-Einfahrten: Clip, Name des Rennens (Marke "aktiv <Name>" = der Ortsname erscheint oben)
STAEDTE = [("b_einfahrt16", "Würzburg Mainufer"), ("b_einfahrt20", "Berlin Kreuzberg"), ("b_einfahrt2", "Hafenrunde"),
           ("b_einfahrt4", "Innenstadtring"), ("b_einfahrt1", "Prachtallee-Sprint")]


# Szenen in Schlägen (0,357 s), Zeiten in den Aufnahmen aus deren Marken (regie.gd), Texte (png, von, bis, Einblenden)
def plan():
    m = S.mark
    B = BEAT
    seg = []
    t_in = m("b_einfahrt15", "aktiv Aachen Grabenring")
    # Schlag 0-4 (leises Intro des Lieds): auf der Auffahrt nach Aachen
    seg.append({"clip": "b_einfahrt15", "start": t_in - 4 * B, "beats": 4, "fadein": 0.25})
    # Einsatz der Musik: in Aachen, oben der Ortsname, unten Titel und Künstler des Stadt-Tracks (blendet das Spiel ein)
    seg.append({"clip": "b_einfahrt15", "start": t_in, "beats": 12,
                "ov": [("b_aachen1", 2 * B, 5 * B, 0.15), ("b_aachen2", 5 * B, None, 0.0)]})
    # Grabenring: vorn das Auto, dahinter Dom, Rathaus und Elisenbrunnen (Dom ab knapp 2 s im Bild)
    d0 = m("b_dom", "start") + 1.9
    seg.append({"clip": "b_dom", "start": d0, "beats": 12})
    # weiter durch Aachen: jede Stadt soll ihren Sound haben (über die Pause im Bass hinweg)
    seg.append({"clip": "b_dom", "start": d0 + 12 * B, "beats": 11, "ov": [("b_sound", 0.1, None, 0.2)]})
    # andere Städte, je mit ihrem Ortsnamen (vom Spiel eingeblendet): noch frei
    for clip, name in STAEDTE:
        t = m(clip, "aktiv " + name)
        seg.append({"clip": clip, "start": t - 0.08, "beats": 4, "ov": [("b_frei", 0.25, None, 0.1)]})
    # Aufruf über Kreuzberg unter der Hochbahn
    f0 = m("b_fahrt20", "start")
    seg.append({"clip": "b_fahrt20", "start": f0 + 1.0, "beats": 8, "ov": [("b_musik", 0.15, None, 0.2)]})
    seg.append({"clip": "b_fahrt20", "start": f0 + 1.0 + 8 * B, "beats": 8, "ov": [("b_kommentare", 0.0, None, 0.2)]})
    # Endtafel
    seg.append({"kind": "end", "clip": "b_fahrt20", "start": f0 + 1.0 + 16 * B, "beats": 8, "vol": 0.5,
                "ov": [("b_end", 0.0, None, 0.35)]})
    return seg


def main():
    a = sys.argv[1:]
    musik = a[a.index("--musik") + 1] if "--musik" in a else MUSIK
    if not os.path.exists(musik):
        sys.exit("Musik fehlt: %s (gitignored, aus dem eigenen Klon kopieren)" % musik)
    tmp = tempfile.mkdtemp(prefix="short_kuenstler_")
    tot = S.build_video(plan(), BEAT, BILD, fade_out=0.5)
    print("Bild geschnitten: %s (%.3f s)" % (BILD, tot))
    start = FIRST + START_BEAT * BEAT
    S.with_bed(BILD, musik, OUT, tmp, tot, game_db=-14.0, bed_start=start, bed_fade_in=0.3, bed_fade_out=2.2, bed_lufs=-15.0)
    i, tp, _ = S.loudness(OUT)
    print("Fertig: %s (%.2f s, Musik ab %.3f s, %.1f LUFS, Spitze %.1f dBTP)" % (OUT, tot, start, i, tp))


if __name__ == "__main__":
    main()
