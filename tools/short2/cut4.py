# Zweites Short (Überholen, Abkürzung, Tunnel, U1). Grundlage: Skizzen-Trailer (Variante A): keine Stimme, Spielmusik "Drift Phonk" (96 BPM, Drop bei 10,03 s im Stück) und Spielton,
# Schnitte auf die Schläge (ein Schlag = 0,625 s), kaum Text. Aufnahmen ohne Lichtteppich (--nopool).
import subprocess, sys, os
D = os.path.dirname(os.path.abspath(__file__)); O = D + "/ov"
OUTF = sys.argv[1]; MUSIC = sys.argv[2]; FPS = 30
BEAT = 0.625; MUS_START = 10.03 - 4 * BEAT  # Drop fällt auf den Start ("GO!")
# (art, datei, start im clip, schläge, overlays [(png, von, bis|None, fade)])
SEG = [
 ("black", None, 0, 4, [("t_intro", 0.3, 2.35, 0.3)]),
 ("portrait", "clips/fra2", 6.15, 4, [("t_four", 0.7, None, 0.15)]),
 ("portrait", "clips/ov4", 16.0, 4, [("t_pass", 0.3, None, 0.12)]),
 ("portrait", "clips/ov16", 25.0, 3, [("t_sign_wue", 0, None, 0.0)]),
 ("portrait", "clips/fra2", 19.9, 3, [("t_back", 0.2, None, 0.12)]),
 ("portrait", "clips/fra2", 26.4, 4, [("t_short", 0.2, None, 0.12)]),
 ("portrait", "clips/tun2", 9.0, 3, [("t_tunnel", 0.2, None, 0.12)]),
 ("portrait", "clips/xel3", 14.5, 3, [("t_sign_xberg", 0, None, 0.0)]),
 ("portrait", "clips/stad0", 6.6, 2, []),
 ("end", "clips/xel3", 17.0, 7, [("t_end", 0, None, 0.4)]),
]
args = ["ffmpeg", "-y", "-loglevel", "error"]; n = 0
def inp(a):
    global n
    args.extend(a); n += 1; return n - 1
F = []; cat = ""; beat = 0
for k, (kind, clip, st, nb, ovs) in enumerate(SEG):
    f0 = round(beat * BEAT * FPS); f1 = round((beat + nb) * BEAT * FPS); beat += nb
    dur = (f1 - f0) / FPS
    if kind == "black":
        vi = inp(["-f", "lavfi", "-t", f"{dur:.5f}", "-i", f"color=c=black:s=1080x1920:r={FPS}"])
        ai = inp(["-f", "lavfi", "-t", f"{dur:.5f}", "-i", "anullsrc=r=48000:cl=stereo"])
        F.append(f"[{vi}:v]setsar=1[base{k}]")
        F.append(f"[{ai}:a]anull[A{k}]")
    else:
        vi = inp(["-i", f"{D}/{clip}.avi"])
        tr = f"trim=start={st}:duration={dur:.5f},setpts=PTS-STARTPTS,fps={FPS}"
        if kind == "portrait":
            F.append(f"[{vi}:v]{tr},setsar=1[base{k}]")
        elif kind == "browser":
            F.append(f"[{vi}:v]{tr},split[a{k}][b{k}]")
            F.append(f"[a{k}]scale=-2:1920,crop=1080:1920,gblur=sigma=30,eq=brightness=-0.3:saturation=1.2[bg{k}]")
            F.append(f"[b{k}]scale=1000:563[fg{k}]")
            F.append(f"[bg{k}][fg{k}]overlay=40:700,setsar=1[base{k}]")
        else:
            F.append(f"[{vi}:v]{tr},gblur=sigma=24,eq=brightness=-0.12,setsar=1[base{k}]")
        vol = 0.5 if kind == "end" else 1.0
        F.append(f"[{vi}:a]atrim=start={st}:duration={dur:.5f},asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,volume={vol},afade=t=in:d=0.01,afade=t=out:st={dur - 0.01:.4f}:d=0.01[A{k}]")
    cur = f"base{k}"
    for j, (png, t0, t1, fade) in enumerate(ovs):
        t1 = dur if t1 is None else t1
        oi = inp(["-loop", "1", "-framerate", str(FPS), "-i", f"{O}/{png}.png"])
        fd = f",fade=in:st=0:d={fade}:alpha=1" if fade > 0 else ""
        F.append(f"[{oi}:v]trim=duration={t1:.5f},format=rgba{fd},setpts=PTS-STARTPTS+{t0:.5f}/TB[o{k}_{j}]")
        F.append(f"[{cur}][o{k}_{j}]overlay=0:0:enable='between(t,{t0:.4f},{t1 - 0.001:.4f})':eof_action=pass[v{k}_{j}]")
        cur = f"v{k}_{j}"
    F.append(f"[{cur}]trim=duration={dur:.5f},setpts=PTS-STARTPTS[V{k}]")
    cat += f"[V{k}][A{k}]"
total = round(beat * BEAT * FPS) / FPS
F.append(f"{cat}concat=n={len(SEG)}:v=1:a=1[vc][g0]")
F.append(f"[vc]fade=t=out:st={total - 0.4:.3f}:d=0.4[v]")
mi = inp(["-i", MUSIC])
F.append(f"[{mi}:a]atrim=start={MUS_START:.4f}:duration={total:.4f},asetpts=PTS-STARTPTS,aresample=48000,aformat=channel_layouts=stereo,loudnorm=I=-15:TP=-2,afade=t=out:st={total - 1.6:.3f}:d=1.6[mus]")
F.append("[g0]loudnorm=I=-23:TP=-4[game]")
F.append(f"[mus][game]amix=inputs=2:normalize=0,alimiter=limit=0.89,afade=t=out:st={total - 0.5:.3f}:d=0.5[a]")
args += ["-filter_complex", ";".join(F), "-map", "[v]", "-map", "[a]", "-c:v", "libx264", "-preset", "slow", "-crf", "17",
         "-pix_fmt", "yuv420p", "-r", str(FPS), "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-movflags", "+faststart", "-t", f"{total:.4f}", OUTF]
subprocess.run(args, check=True)
print("fertig", OUTF, f"{total:.3f}s")
