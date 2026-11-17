# Short "Neu in 2.39" (deutsch, Lied aus ElevenLabs Music): 18 Takte bei 140 BPM = 30,86 s, jede Szene auf den Takt
# (Schnittplan und Liedtext: release/SHORTS.md Nr. 15). Keine Stimme von uns, knappe Texte in Kleinschrift,
# Spielton leise unter dem Lied, -14 LUFS.
#
#   python3 tools/short3/cut_a.py                      Bild neu schneiden (braucht $SHORT3/clips und $SHORT3/ov), dazu
#                                                      die Vorschau (nur Spielton) und die Fassung mit Metronom-Klick
#   python3 tools/short3/cut_a.py --musik lied.mp3     fertiges Short mit dem Lied (nimmt das geschnittene Bild, sonst
#                                                      die Vorschau aus release/): need_for_geschwindigkeit_short_239.mp4
#        [--versatz s]  so viele Sekunden des Lieds vor Takt 1 überspringen (negativ: Stille davor). Standard: gemessen
#                       (erster Schlag des Lieds), ohne Messung 0
#        [--bpm b]      Tempo des Lieds, wenn es nicht genau 140 hat (wird auf 140 gestreckt). Standard: gemessen,
#                       nur übernommen, wenn es zwischen 137 und 143 liegt
#        [--spielton d] Spielton so viele dB unter der Musik (Standard 13)
#        [--ohne-messung] Versatz 0 und 140 BPM annehmen
#        [--out datei.mp4] anderer Name für das fertige Short
#   python3 tools/short3/cut_a.py --nur-ton           Vorschau und Klick neu, ohne das Bild neu zu schneiden
import os, sys, tempfile
sys.dont_write_bytecode = True  # kein __pycache__ im Repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schnitt as S

BPM = 140.0
BEAT = 60.0 / BPM  # 0,4286 s, ein Takt 1,714 s
REL = os.path.join(S.P, "release")
OUT_VOR = os.path.join(REL, "need_for_geschwindigkeit_short_239_vorschau.mp4")
OUT_KLICK = os.path.join(REL, "need_for_geschwindigkeit_short_239_klick.mp4")
OUT_FERTIG = os.path.join(REL, "need_for_geschwindigkeit_short_239.mp4")
BILD = os.path.join(S.WORK, "short_239_bild.mp4")  # geschnittenes Bild mit rohem Spielton

# Szenen (Schläge; 4 = ein Takt). Die Zeiten in den Aufnahmen kommen aus deren Marken (regie.gd schreibt
# "REGIE MARKE ..." ins Log: Anflug, Ampel, Halt, Weiter, Kran, Wegweiser, Gelände, Drift, Sprungkamera, Flug ...),
# nach einer neuen Aufnahme (rec_a.sh) passt der Schnitt also von selbst. Texte: (png in ov/, von, bis, Einblenden).
def plan():
    m = S.mark
    B = BEAT
    seg = []
    # Takt 1-4: Anflug von oben über Frankfurt, oben 0,67 s stehen lassen: die Landung trifft Takt 3 (Hook), danach
    # losfahren, oben blendet das Spiel den Ortsnamen ein
    t0 = m("a_anflug", "anflug beginnt")
    seg.append({"clip": "a_anflug", "start": t0, "freeze": 0.67, "beats": 16, "vol": 0.8,
                "ov": [("a_intro", 0.35, 3.25, 0.25)]})
    # Takt 5-6: Rostock, Kreuzung: Ampel nah (Rot), Auto wartet, Ampel springt auf Grün, Auto fährt los über die
    # Hauptstraße in die Gasse. Zwei Aufnahmen desselben Ablaufs (gleiche Zeiten), hin und her geschnitten
    go = m("a_kreuz", "weiter")
    green = max(x for x in S.marks("a_kreuz", "ampel licht=grün") if x < go)
    kz = [("a_kreuzung", 0.0, None, 0.0)]
    seg.append({"clip": "a_ampel", "start": green - 2.45, "beats": 2, "ov": [("a_kreuzung", 0.1, None, 0.15)]})
    seg.append({"clip": "a_kreuz", "start": green - 2.45 + 2 * B, "beats": 2, "ov": kz})
    seg.append({"clip": "a_ampel", "start": green - 0.3, "beats": 1, "ov": kz})
    seg.append({"clip": "a_kreuz", "start": go - 0.12, "beats": 3, "ov": kz})
    # Takt 7-8: Gasse mit Kopfsteinpflaster (durchgehend weiter), dann hebt die Kamera ab
    seg.append({"clip": "a_kreuz", "start": go - 0.12 + 3 * B, "beats": 4, "ov": [("a_gasse", 0.1, None, 0.15)]})
    # (Aufnahmen vor der Marke "kran": die Kamera hebt gut 2 s nach der Einfahrt in die Gasse ab)
    kran = m("a_kreuz", "kran", 1, m("a_kreuz", "weg lane", 2) + 2.0)
    seg.append({"clip": "a_kreuz", "start": kran + 0.5, "beats": 4, "ov": [("a_hinterland", 0.25, None, 0.2)]})
    # Takt 9-10: Querspange, Wegweiser "Ausfahrt Golfplatz", Tor (oben der Name des Platzes), Fairway, quer (Staub)
    ww = m("a_golf", "wegweiser")
    rein = m("a_golf", "gelaende rein")
    drift = m("a_golf", "drift")
    seg.append({"clip": "a_golf", "start": ww - 1.35, "beats": 2})
    seg.append({"clip": "a_golf", "start": rein - 0.35, "beats": 2, "ov": [("a_golf", 0.0, None, 0.15)]})
    seg.append({"clip": "a_golf", "start": drift - 0.15, "beats": 4, "ov": [("a_golf", 0.0, None, 0.0)]})
    # Takt 11-12: Stahlrampe über den kleinen Teich (zweite Rampe): Anlauf, Sprungkamera mit Zeitlupe, die Landung
    # trifft Takt 13
    land = m("a_teich", "flug landung", 2)
    seg.append({"clip": "a_teich", "start": land - 8 * B + 0.03, "beats": 8})
    # Takt 13-14: Kiesgrube am Morgen: das Auto kommt über die Spitze des Kieshaufens geflogen, landet vor der Kamera
    fly = m("a_kies", "flug ab", 1)
    seg.append({"clip": "a_kies", "start": max(fly - 0.55, 0.0), "beats": 8, "ov": [("a_kies", 0.35, 2.9, 0.15)]})
    # Takt 15-16: Garage: das Auto fährt in der Halle (das Band ist unsichtbar), das nächste fährt herein
    sw = m("a_garage", "autowechsel", 1, 2.5)
    seg.append({"clip": "a_garage", "start": sw - 4 * B + 0.1, "beats": 8, "zoom": (1.45, 700, 930),
                "ov": [("a_autos", 0.25, None, 0.2)]})
    # Takt 17-18: Endtafel über der unscharfen Stadt von oben (Ende der Kranfahrt)
    seg.append({"kind": "end", "clip": "a_kreuz", "start": kran + 3.6, "beats": 8, "vol": 0.5,
                "ov": [("a_end", 0.0, None, 0.35)]})
    return seg


def bild():
    tot = S.build_video(plan(), BEAT, BILD)
    print("Bild geschnitten: %s (%.3f s)" % (BILD, tot))
    return tot


def main():
    a = sys.argv[1:]
    musik = a[a.index("--musik") + 1] if "--musik" in a else ""
    tmp = tempfile.mkdtemp(prefix="short239_")
    if not musik:
        tot = S.dur(BILD) if "--nur-ton" in a and os.path.exists(BILD) else bild()
        S.game_only(BILD, OUT_VOR, tmp)
        print("Vorschau (nur Spielton):", OUT_VOR)
        klick = os.path.join(tmp, "klick.wav")
        S.click_track(klick, tot, BEAT)
        S.with_bed(BILD, klick, OUT_KLICK, tmp, tot, game_db=-9.0, bed_fade_out=0.0, bed_lufs=-16.0)
        print("Mit Klick auf jedem Schlag (Takt-Eins höher):", OUT_KLICK)
        for f in (OUT_VOR, OUT_KLICK):
            i, tp, _ = S.loudness(f)
            print("  %s: %.1f LUFS, Spitze %.1f dBTP" % (os.path.basename(f), i, tp))
        return
    src = BILD if os.path.exists(BILD) else OUT_VOR
    tot = S.dur(src)
    versatz = 0.0
    tempo = BPM
    if "--ohne-messung" not in a and ("--versatz" not in a or "--bpm" not in a):
        b, first = S.tempo(musik, 128.0, 152.0, 0.3, 30.0)
        print("Lied gemessen: %.2f BPM, erster Schlag bei %.3f s" % (b, first))
        if 137.0 <= b <= 143.0:
            tempo = b
        else:
            print("  Tempo weit weg von 140: nehme 140 an (mit --bpm angeben)")
        versatz = first
    if "--versatz" in a:
        versatz = float(a[a.index("--versatz") + 1])
    if "--bpm" in a:
        tempo = float(a[a.index("--bpm") + 1])
    game_db = -float(a[a.index("--spielton") + 1]) if "--spielton" in a else -13.0
    out = a[a.index("--out") + 1] if "--out" in a else OUT_FERTIG
    # Versatz gilt in Lied-Sekunden; nach dem Strecken auf 140 BPM liegt er bei versatz * tempo / 140
    print("Lied: Versatz %.3f s, %.2f BPM (gestreckt um %.4f), Spielton %.0f dB" % (versatz, tempo, BPM / tempo, game_db))
    S.with_bed(src, musik, out, tmp, tot, game_db=game_db, bed_start=versatz, bed_tempo=BPM / tempo,
               bed_fade_in=0.0, bed_fade_out=0.25, bed_lufs=-15.0)
    i, tp, _ = S.loudness(out)
    print("Fertig: %s (%.1f LUFS, Spitze %.1f dBTP)" % (out, i, tp))


if __name__ == "__main__":
    main()
