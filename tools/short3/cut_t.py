# Trailer zu 2.39 im Querformat (1920x1080, 30 Bilder/s): das ganze Spiel im Überblick, Schnitte auf den Schlag.
# Musik: artissizm „Drift Phonk“ aus dem Spiel-Soundtrack (Pixabay, music/artissizm-drift-phonk-200108.mp3), gemessen
# 103,96 BPM (ein Schlag 0,5771 s, erster Schlag bei 0,006 s, die Eins jedes Takts auf den Schlägen 0, 4, 8 …). Der
# Ausschnitt beginnt mit Takt 9 (Schlag 32, 18,47 s im Lied): acht Takte Aufbau für Karte, Anflug und Städte, dann der
# Drop (Takt 17, 36,94 s im Lied) auf die Autobahn. 100 Schläge = 57,7 s, die Musik blendet über der Endtafel aus.
# Spielton und Motor bleiben weg (nur die Musik), -14 LUFS.
#
#   python3 tools/short3/cut_t.py            -> release/need_for_geschwindigkeit_trailer_239.mp4 (deutsch)
#   python3 tools/short3/cut_t.py --en       -> release/need_for_geschwindigkeit_trailer_239_en.mp4 (Einblendungen englisch)
#   python3 tools/short3/cut_t.py --beide    -> beide
# Aufnahmen: tools/short3/rec_t.sh, Einblendungen: promo_overlays.tscn -- --trailer (td_*.png, te_*.png in $SHORT3/ov).
import os, sys, tempfile
sys.dont_write_bytecode = True  # kein __pycache__ im Repo
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import schnitt as S

S.W, S.H = 1920, 1080
BPM = 103.96
BEAT = 60.0 / BPM
FIRST = 0.0055  # erster Schlag im Lied (s)
START_BEAT = 32  # Takt 9
MUSIK = os.path.join(S.P, "music", "artissizm-drift-phonk-200108.mp3")
OUT_DE = os.path.join(S.P, "release", "need_for_geschwindigkeit_trailer_239.mp4")
OUT_EN = os.path.join(S.P, "release", "need_for_geschwindigkeit_trailer_239_en.mp4")


def plan(lang):
    """Szenen in Schlägen; Texte (png, von, bis, Einblenden) in Sekunden ab Szenenbeginn. Zeiten in den Welt-Aufnahmen aus
    ihren Marken (regie.gd), in den Rennszenen (r_*, debug_shot.gd ohne Marken) feste Sekunden im Clip"""
    m = S.mark
    t = lambda name: ("td_" if lang == "de" else "te_") + name
    seg = []
    # --- Aufbau (Takt 9-16): Karte, Anflug, Städte bei Tag und Nacht, Regen und Nebel
    seg.append({"clip": "t_karte", "start": m("t_karte", "karte auf") + 0.2, "beats": 8, "ov": [(t("karte"), 0.3, None, 0.3)]})
    seg.append({"clip": "t_anflug", "start": m("t_anflug", "anflug beginnt"), "beats": 8,
                "ov": [(t("staedte"), 0.4, None, 0.3)]})
    # Würzburg bei Tag am Main, Kreuzberg nachts unter der U1
    seg.append({"clip": "t_wue", "start": m("t_wue", "start") + 10.5, "beats": 4, "ov": [(t("tagnacht"), 0.2, None, 0.25)]})
    seg.append({"clip": "t_xberg", "start": m("t_xberg", "start") + 4.0, "beats": 4, "ov": [(t("tagnacht"), 0.0, None, 0.0)]})
    # Aachen im Regen (Grabenring, Autopilot mit gut 230 km/h), Hamburger Hafen im Nebel (Nitro)
    seg.append({"clip": "r_aachen", "start": 8.0, "beats": 4, "ov": [(t("wetter"), 0.2, None, 0.25)]})
    seg.append({"clip": "r_hafen", "start": 6.0, "beats": 4, "ov": [(t("wetter"), 0.0, None, 0.0)]})
    # --- Drop (Takt 17): Autobahn, knapp an einem Lastwagen vorbei ("KNAPP VORBEI +610"), danach Nitro
    vb = m("t_raser", "vorbei", 2)
    seg.append({"clip": "t_raser", "start": vb - 2.6, "beats": 8, "ov": [(t("knapp"), 0.15, None, 0.2)]})
    # Herausforderer: zieht links vorbei, Enter, Duell (eine Einstellung)
    seg.append({"clip": "t_duell", "start": m("t_duell", "herausforderer vorbei") - 0.9, "beats": 8,
                "ov": [(t("duell"), 0.15, None, 0.2)]})
    # Q: Drift-Modus, dann quer durch die Kurve bis "DRIFT 130", dann ein Drift im Nebel am Hafen (Rennen Hafen-Drift)
    seg.append({"clip": "t_modus", "start": m("t_modus", "q") - 0.3, "beats": 4, "ov": [(t("drift"), 0.15, None, 0.2)]})
    seg.append({"clip": "t_modus", "start": m("t_modus", "drift") + 0.3, "beats": 4, "ov": [(t("drift"), 0.0, None, 0.0)]})
    seg.append({"clip": "r_hafen", "start": 9.35, "beats": 4})
    # --- Rennen (Pause im Lied): Kameraflug mit der Startkarte, dann der Countdown über drei Rennen bis LOS
    seg.append({"clip": "t_sprint", "start": m("t_sprint", "rennen startkarte") + 1.0, "beats": 4,
                "ov": [(t("rennen"), 0.15, None, 0.2)]})
    # (der Text nur über der Startkarte: im Countdown stünde er auf der Zahl)
    seg.append({"clip": "t_rundkurs", "start": m("t_rundkurs", "rennen los") - 2.3, "beats": 2})
    seg.append({"clip": "t_drift", "start": m("t_drift", "rennen los") - 1.15, "beats": 2})
    seg.append({"clip": "t_sprint", "start": m("t_sprint", "rennen los") - 0.3, "beats": 4})
    # --- Gelände: Teich-Sprung mit Sprungkamera, Flug über den Kieshaufen
    seg.append({"clip": "t_teich", "start": m("t_teich", "flug landung", 2) - 2.1, "beats": 4,
                "ov": [(t("gelaende"), 0.15, None, 0.2)]})
    seg.append({"clip": "t_kies", "start": m("t_kies", "flug ab", 1) + 0.2, "beats": 4, "ov": [(t("gelaende"), 0.0, None, 0.0)]})
    # --- Garage: Lack und Felgen durchblättern, Autohaus mit dem nächsten Auto
    seg.append({"clip": "t_tuning", "start": m("t_tuning", "tuning lack") + 0.7, "beats": 2, "ov": [(t("tuning"), 0.15, None, 0.2)]})
    seg.append({"clip": "t_tuning", "start": m("t_tuning", "tuning felgen") + 0.8, "beats": 2, "ov": [(t("tuning"), 0.0, None, 0.0)]})
    seg.append({"clip": "t_tuning", "start": m("t_tuning", "tuning auto") - 0.3, "beats": 4, "ov": [(t("tuning"), 0.0, None, 0.0)]})
    # --- Frankfurt nachts im Rennen mit Nitro durch die Neon-Schlucht, dann die Endtafel über der unscharfen Fahrt
    seg.append({"clip": "r_frankfurt", "start": 8.0, "beats": 4})
    seg.append({"kind": "end", "clip": "r_frankfurt", "start": 10.4, "beats": 8, "ov": [(t("end"), 0.0, None, 0.4)]})
    return seg


def musik(total, path):
    """Ausschnitt der Musik ab START_BEAT, am Ende über zwei Schläge ausgeblendet, auf -14 LUFS"""
    tmp = os.path.dirname(path)
    raw = os.path.join(tmp, "musik_roh.wav")
    t0 = FIRST + START_BEAT * BEAT
    fade = 2.2
    S.to_wav(MUSIK, raw, f"atrim=duration={total:.4f},afade=t=in:d=0.02,afade=t=out:st={total - fade:.4f}:d={fade}",
             ["-ss", f"{t0:.4f}"])
    return raw


def build(lang, tmp):
    bild = os.path.join(S.WORK, "trailer_239_bild_%s.mp4" % lang)
    tot = S.build_video(plan(lang), BEAT, bild, fade_out=0.6)
    print("Bild geschnitten: %s (%.2f s)" % (bild, tot))
    out = OUT_DE if lang == "de" else OUT_EN
    mus = musik(tot, os.path.join(tmp, "x"))
    S.master(bild, mus, out, tmp)
    i, tp, _ = S.loudness(out)
    print("Fertig: %s (%.2f s, %.1f LUFS, %.1f dBTP)" % (out, S.dur(out), i, tp))


def main():
    langs = ["de"]
    if "--en" in sys.argv:
        langs = ["en"]
    if "--beide" in sys.argv:
        langs = ["de", "en"]
    tmp = tempfile.mkdtemp(prefix="trailer239_", dir=S.WORK)
    for lang in langs:
        build(lang, tmp)


if __name__ == "__main__":
    main()
