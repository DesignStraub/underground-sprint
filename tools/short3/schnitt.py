# Schnitt-Bausteine für die Shorts zu 2.39 (tools/short3): Szenen auf ein Taktraster legen, Texte einblenden,
# Spielton je Szene, dazu Musik (mit Versatz und Tempo-Angleich) oder ein Metronom-Klick, Lautheit auf -14 LUFS.
# Nur ffmpeg, kein numpy. Benutzt von cut_u.py (Überblick) und cut_b.py (Aufruf an Künstler).
import json, math, os, struct, subprocess, sys

FPS = 30
W, H = 1080, 1920
D = os.path.dirname(os.path.abspath(__file__))
P = os.path.dirname(os.path.dirname(D))
WORK = os.environ.get("SHORT3", os.path.join(D, "arbeit"))  # Aufnahmen (clips/) und Einblendungen (ov/)
CLIPS = os.path.join(WORK, "clips")
OV = os.path.join(WORK, "ov")
LUFS = -14.0


def run(args):
    subprocess.run(args, check=True)


def dur(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    return float(out)


def build_video(segs, beat, out_path, fade_out=0.4):
    """Szenen der Reihe nach auf das Raster (beat Sekunden je Schlag) legen; Ergebnis: Bild + Spielton (roh).
    Szene: dict mit kind ("clip", "black", "end"), clip, start (s im Clip), beats, ov [(png, von, bis|None, einblenden)],
    vol (Spielton), speed (0.8: mit 24 Bildern/s aufgenommen, ohne doppelte Bilder 0,8-fach), zoom (k, cx, cy: Ausschnitt
    um die Mitte cx, cy in Bildpunkten, k-fach vergrößert), freeze (s: erstes Bild so lange stehen lassen),
    fadein (s aus Schwarz), blur (Endtafel: Unschärfe)."""
    args = ["ffmpeg", "-y", "-loglevel", "error"]
    n = [0]

    def inp(a):
        args.extend(a)
        n[0] += 1
        return n[0] - 1

    F = []
    cat = ""
    pos = 0.0  # Schläge bis hier
    for k, s in enumerate(segs):
        f0 = round(pos * beat * FPS)
        pos += s["beats"]
        f1 = round(pos * beat * FPS)
        d = (f1 - f0) / FPS
        kind = s.get("kind", "clip")
        if kind == "black":
            vi = inp(["-f", "lavfi", "-t", f"{d:.5f}", "-i", f"color=c=black:s={W}x{H}:r={FPS}"])
            ai = inp(["-f", "lavfi", "-t", f"{d:.5f}", "-i", "anullsrc=r=48000:cl=stereo"])
            F.append(f"[{vi}:v]setsar=1,format=yuv420p[base{k}]")
            F.append(f"[{ai}:a]anull[A{k}]")
        else:
            vi = inp(["-i", os.path.join(CLIPS, s["clip"] + ".avi")])
            sp = s.get("speed", 1.0)
            fr = s.get("freeze", 0.0)
            st = s["start"]
            src = (d - fr) * sp  # so viel Clip wird gebraucht
            v = f"[{vi}:v]trim=start={st:.4f}:duration={src + 0.2:.4f},setpts=(PTS-STARTPTS)/{sp},fps={FPS}"
            if fr > 0:
                v += f",tpad=start_duration={fr:.4f}:start_mode=clone"
            z = s.get("zoom")
            if z:
                zk, cx, cy = z
                cw, ch = int(W / zk) // 2 * 2, int(H / zk) // 2 * 2
                x0 = int(min(max(cx - cw / 2, 0), W - cw))
                y0 = int(min(max(cy - ch / 2, 0), H - ch))
                v += f",crop={cw}:{ch}:{x0}:{y0},scale={W}:{H}:flags=lanczos"
            if kind == "end":
                v += f",gblur=sigma={s.get('blur', 22)},eq=brightness=-0.1"
            if s.get("fadein", 0) > 0:
                v += f",fade=t=in:st=0:d={s['fadein']}"
            F.append(f"{v},trim=duration={d:.5f},setsar=1,format=yuv420p[base{k}]")
            vol = s.get("vol", 1.0)
            a = f"[{vi}:a]atrim=start={st:.4f}:duration={src + 0.2:.4f},asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo"
            if sp != 1.0:
                a += f",atempo={sp}"
            if fr > 0:
                a += f",adelay={int(fr * 1000)}:all=1"
            a += f",atrim=duration={d:.5f},volume={vol},afade=t=in:d=0.012,afade=t=out:st={max(d - 0.012, 0):.4f}:d=0.012"
            F.append(a + f",apad=whole_dur={d:.5f}[A{k}]")
        cur = f"base{k}"
        for j, ov in enumerate(s.get("ov", [])):
            png, t0, t1, fade = (list(ov) + [0.15])[:4]
            t1 = d if t1 is None else min(t1, d)
            oi = inp(["-loop", "1", "-framerate", str(FPS), "-t", f"{d:.5f}", "-i", os.path.join(OV, png + ".png")])
            fd = f",fade=t=in:st=0:d={fade}:alpha=1" if fade > 0 else ""
            F.append(f"[{oi}:v]format=rgba,trim=duration={t1 - t0:.5f}{fd},setpts=PTS-STARTPTS+{t0:.5f}/TB[o{k}_{j}]")
            F.append(f"[{cur}][o{k}_{j}]overlay=0:0:eof_action=pass[v{k}_{j}]")
            cur = f"v{k}_{j}"
        F.append(f"[{cur}]trim=duration={d:.5f},setpts=PTS-STARTPTS[V{k}]")
        cat += f"[V{k}][A{k}]"
    total = round(pos * beat * FPS) / FPS
    F.append(f"{cat}concat=n={len(segs)}:v=1:a=1[vc][ac]")
    F.append(f"[vc]fade=t=out:st={total - fade_out:.4f}:d={fade_out}[v]")
    F.append(f"[ac]afade=t=out:st={total - 0.5:.4f}:d=0.5[a]")
    args += ["-filter_complex", ";".join(F), "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "16",
             "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "pcm_s16le", "-ar", "48000", "-t", f"{total:.4f}", out_path]
    run(args)
    return total


def marks(clip, what):
    """Alle Zeiten (s im Video) der Marken "REGIE MARKE <what> t=..." in clips/<clip>.log (von regie.gd geschrieben)"""
    out = []
    with open(os.path.join(CLIPS, clip + ".log"), errors="ignore") as f:
        for line in f:
            if line.startswith("REGIE MARKE " + what + " t="):
                # Bild im Video: film = Durchläufe der Hauptschleife seit dem ersten Bild (je Durchlauf schreibt
                # --write-movie ein Bild, auch ein nicht neu gezeichnetes). Ältere Logs: bild = Engine.get_frames_drawn()
                # zählt eins weiter als die Bilder der Aufnahme (stimmt nur, solange jedes Bild gezeichnet wurde);
                # ohne Bildnummer die Spielzeit t
                if " film=" in line:
                    out.append(int(line.split(" film=")[1].split()[0]) / FPS)
                elif " bild=" in line:
                    out.append((int(line.split(" bild=")[1].split()[0]) - 1) / FPS)
                else:
                    out.append(float(line.split(" t=")[1].split()[0]))
    return out


def mark(clip, what, n=1, default=None):
    """n-te Marke (1 = erste, -1 = letzte); fehlt sie, default (oder Abbruch mit Hinweis)"""
    m = marks(clip, what)
    if len(m) >= abs(n):
        return m[n - 1] if n > 0 else m[n]
    if default is not None:
        print("  Hinweis: Marke '%s' (%d.) fehlt in %s.log, nehme %.2f s" % (what, n, clip, default))
        return default
    sys.exit("Marke '%s' (%d.) fehlt in %s.log: Aufnahme neu machen (rec_u.sh / rec_b.sh)" % (what, n, clip))


def loudness(path):
    """Integrierte Lautheit (LUFS) und True Peak (dBTP) einer Audio- oder Videodatei"""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "loudnorm=I=-14:TP=-1.5:print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True).stderr
    j = json.loads(r[r.rfind("{"):r.rfind("}") + 1])
    return float(j["input_i"]), float(j["input_tp"]), j


def to_wav(src, dst, af=None, pre=None):
    """Ton als 32-bit-float-WAV (kein Übersteuern zwischen den Schritten), 48 kHz Stereo"""
    a = ["ffmpeg", "-y", "-loglevel", "error"] + (pre or []) + ["-i", src, "-vn"]
    if af:
        a += ["-af", af]
    run(a + ["-ac", "2", "-ar", "48000", "-c:a", "pcm_f32le", dst])


def gain_to(src, dst, target):
    """Nur Verstärkung (keine Dynamik), bis die integrierte Lautheit target LUFS ist"""
    i, _, _ = loudness(src)
    to_wav(src, dst, f"volume={target - i:.3f}dB")


def finalize(src, dst, target=LUFS, ceiling_db=-2.0):
    """Auf target LUFS mit Begrenzer (Spitzen bis ceiling_db, vierfach überabgetastet, damit auch die Spitzen zwischen
    den Abtastwerten und nach AAC unter 0 dBTP bleiben): Verstärkung, Begrenzer, nachmessen, bis es passt"""
    i, _, _ = loudness(src)
    g = target - i
    lim = 10 ** (ceiling_db / 20.0)
    for _ in range(4):
        run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-af",
             f"volume={g:.3f}dB,aresample=192000,alimiter=limit={lim:.4f}:attack=2:release=60:level=false,aresample=48000",
             "-ac", "2", "-c:a", "pcm_s16le", dst])
        i2, _, _ = loudness(dst)
        if abs(i2 - target) < 0.12:
            break
        g += target - i2


def mux(video_src, audio_wav, out_path):
    """Bild aus video_src (ohne neu zu kodieren) mit neuem Ton (AAC 192k) als fertiges Short"""
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", video_src, "-i", audio_wav, "-map", "0:v", "-map", "1:a", "-c:v", "copy",
         "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", "-shortest", out_path])


def master(video_src, src_wav, out_path, tmp_dir):
    """Ton fertig machen und anlegen; AAC verschiebt die Lautheit um ein, zwei Zehntel: einmal nachmessen und angleichen"""
    fin = os.path.join(tmp_dir, "fertig.wav")
    finalize(src_wav, fin)
    mux(video_src, fin, out_path)
    i, _, _ = loudness(out_path)
    if abs(i - LUFS) > 0.08:
        finalize(src_wav, fin, LUFS + (LUFS - i))
        mux(video_src, fin, out_path)


def game_only(video_src, out_path, tmp_dir):
    """Vorschau nur mit Spielton, auf -14 LUFS"""
    wav = os.path.join(tmp_dir, "spielton.wav")
    to_wav(video_src, wav)
    master(video_src, wav, out_path, tmp_dir)


def with_bed(video_src, bed, out_path, tmp_dir, total, game_db=-13.0, bed_start=0.0, bed_tempo=1.0, bed_fade_in=0.0,
             bed_fade_out=0.8, bed_lufs=-15.0):
    """Musik (oder Klick) unter das Bild: bed ab bed_start Sekunden (negativ: so lange Stille davor), Tempo-Angleich
    bed_tempo (atempo), weich ein- und ausgeblendet; Spielton game_db unter der Musik (beide vorher nur verstärkt bzw.
    abgeschwächt auf feste Lautheit), Summe auf -14 LUFS mit Begrenzer"""
    game = os.path.join(tmp_dir, "spielton.wav")
    to_wav(video_src, game)
    gl = os.path.join(tmp_dir, "spielton_l.wav")
    gain_to(game, gl, bed_lufs + game_db)
    # Musik: Ausschnitt, Tempo, Blenden
    mus = os.path.join(tmp_dir, "musik.wav")
    af = []
    pre = []
    if bed_start >= 0:
        pre = ["-ss", f"{bed_start:.4f}"]
    if bed_tempo != 1.0:
        af.append(f"atempo={bed_tempo:.6f}")
    if bed_start < 0:
        af.append(f"adelay={int(-bed_start * 1000)}:all=1")
    af.append(f"apad=whole_dur={total:.4f}")
    af.append(f"atrim=duration={total:.4f}")
    if bed_fade_in > 0:
        af.append(f"afade=t=in:d={bed_fade_in}")
    if bed_fade_out > 0:
        af.append(f"afade=t=out:st={total - bed_fade_out:.4f}:d={bed_fade_out}")
    to_wav(bed, mus, ",".join(af), pre)
    ml = os.path.join(tmp_dir, "musik_l.wav")
    gain_to(mus, ml, bed_lufs)
    mix = os.path.join(tmp_dir, "mix.wav")
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", ml, "-i", gl, "-filter_complex",
         f"[0:a][1:a]amix=inputs=2:normalize=0:duration=first,atrim=duration={total:.4f}[m]", "-map", "[m]", "-ar", "48000",
         "-c:a", "pcm_f32le", mix])
    master(video_src, mix, out_path, tmp_dir)


def click_track(path, total, beat, beats_per_bar=4):
    """Metronom zum Prüfen des Schnitts (kein Spielklang, nur fürs Gegenhören): jeder Schlag ein kurzer Ton,
    der erste Schlag im Takt höher"""
    bar = beat * beats_per_bar
    m = f"mod(t+0.0005,{beat:.6f})"
    expr = (f"0.5*sin(2*PI*if(lt(mod(t+0.0005,{bar:.6f}),0.03),1760,1100)*t)*min(1,{m}*400)*exp(-60*{m})"
            f"*lt({m},0.08)")
    run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", f"aevalsrc=exprs='{expr}|{expr}':s=48000:d={total:.4f}",
         "-c:a", "pcm_s16le", path])


# --- Taktmessung (ohne numpy): Einsätze je 10 ms, Autokorrelation, Phase mit Kammfilter ------------------------------

def _onsets(path, sr=11025, hop=110, af="anull"):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr), "-af", af, "-f", "s16le", "-"],
                         capture_output=True).stdout
    nn = len(raw) // 2
    smp = struct.unpack("<%dh" % nn, raw)
    env = []
    for i in range(0, nn - hop, hop):
        acc = 0
        for x in smp[i:i + hop]:
            acc += x * x
        env.append(math.log(1e-6 + acc / hop))
    on = [0.0] + [max(0.0, env[i] - env[i - 1]) for i in range(1, len(env))]
    return on, sr / hop


def tempo(path, lo=120.0, hi=160.0, t0=0.5, t1=None):
    """Tempo (BPM) und Lage des ersten Schlags (s) einer Aufnahme; sucht zwischen lo und hi BPM"""
    on, fps = _onsets(path)
    n = len(on)
    if t1 is None:
        t1 = n / fps - 0.5

    def val(x):
        i = int(x)
        f = x - i
        return on[i] * (1 - f) + on[i + 1] * f if 0 <= i < n - 1 else 0.0

    def comb(P, ph):
        s = 0.0
        k = 0
        x = ph
        while x / fps < t0:
            x += P
        while x / fps < t1:
            s += max(val(x + dd) for dd in (-1, 0, 1))
            k += 1
            x += P
        return s / max(k, 1)

    best = (0.0, 0.0, 0.0)
    b = lo
    while b <= hi:
        P = 60.0 / b * fps
        ph = 0.0
        while ph < P:
            c = comb(P, ph)
            if c > best[0]:
                best = (c, b, ph)
            ph += 0.5
        b += 0.1
    c, bpm, ph = best
    return bpm, ph / fps


if __name__ == "__main__":
    # python3 schnitt.py takt <datei> [lo hi]: Tempo und ersten Schlag ausgeben
    if len(sys.argv) > 2 and sys.argv[1] == "takt":
        lo = float(sys.argv[3]) if len(sys.argv) > 3 else 120.0
        hi = float(sys.argv[4]) if len(sys.argv) > 4 else 160.0
        bpm, first = tempo(sys.argv[2], lo, hi)
        print("Tempo %.2f BPM, erster Schlag bei %.3f s (ein Schlag %.4f s)" % (bpm, first, 60.0 / bpm))
