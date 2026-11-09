extends Node
## Werkzeug: rechnet die Motorklänge aller Autos vor -> assets/engine/<auto>/on_<U/min>.wav (Last) und
## off_<U/min>.wav (Schiebebetrieb), dazu traffic_car.wav und traffic_bus.wav für den Verkehr.
## Aufruf: godot --headless --path . res://tools/make_engine_sounds.tscn [-- kaze ronin ...]
##
## Wie in großen Rennspielen: kurze, nahtlose Schleifen bei festen Drehzahlen (engine_audio.RPMS), getrennt für Gas
## und Schub. engine_audio.gd blendet im Spiel zwischen den beiden nächsten Drehzahlen und zwischen Gas und Schub
## über und zieht die Tonhöhe auf die echte Drehzahl.
##
## Der Klang kommt aus einem einfachen physikalischen Modell statt aus Sinustönen (die klangen nach Orgel):
##  - Druckstöße: je Zylinder und Arbeitsspiel (720° Kurbelwinkel) ein Stoß, wenn das Auslassventil öffnet: steil
##    an, über gut 100° abklingend. Jeder Stoß ist etwas anders stark und kommt minimal früher oder später, jeder
##    Zylinder ist ein wenig stärker oder schwächer (das gibt das Bollern). Zündabstände je Bauart; ungleich lange
##    Krümmer (Boxer) versetzen die Stöße einer Bank, das gibt das typische Blubbern.
##  - Verbrennungsknacken: kurzer Rauschstoß am Anfang jedes Stoßes (Rasseln, Diesel: Nageln).
##  - Strömungsrauschen: das Abgas strömt stoßweise und verwirbelt; Rauschen im Takt der Stöße, unter Last und mit
##    Drehzahl stärker (ohne das klingen die Obertöne zu glatt, wie ein Synthesizer).
##  - Auspuff: Rohr als Laufzeitleitung mit Reflexion am offenen Ende (Rohrresonanzen, die beim Hochdrehen
##    durchlaufen), Schalldämpfer (Tiefpass) mit Brummresonanz, ein Teil geht ungedämpft durch (Sportauspuff),
##    Abstrahlung am Endrohr (Hochpass), leichte Sättigung unter Last.
##  - Ansaugen (nur Saugmotoren, unter Last): Rauschen im Takt der Ansaughübe.
##  - Schub: schwache, unruhige Stöße, dumpferer Dämpfer, ab und zu ein Blubbern im Auspuff.

const Catalog := preload("res://scripts/catalog.gd")
const EA := preload("res://scripts/engine_audio.gd")

const FS := 22050.0
const OUT := "res://assets/engine/"

## Bauart je Auto (Vorbild in Klammern)
const TYPES := {
	"kaizen": "i4", "hachi": "i4", "sakura": "i4", "hayate": "i4", "kitsune": "i4", "tsubame": "i4", "mirai": "i4",
	"tenshi": "i4", "raijin": "b4", "chibi": "i3", "hotaru": "i3", "tanuki": "i3", "kumo": "i6", "vortex": "i6",
	"kaze": "i6", "kaido": "i6", "hakone": "i6", "ryujin": "v6", "shiden": "v6", "falke": "f6", "ronin": "rot",
	"kagura": "v10", "furia": "v12",
}

## Zündabstände (Grad Kurbelwinkel im Arbeitsspiel), Bank je Zylinder, Laufzeitunterschied der Bänke (ms),
## Länge des Druckstoßes (Grad), Anstieg (Anteil), Knacken, Grundunruhe
const KINDS := {
	"i3": {"fire": [0, 240, 480], "bank": [0, 0, 0], "bank_ms": 0.0, "pulse": 130.0, "attack": 0.07, "crack": 0.0, "lope": 1.3},
	"i4": {"fire": [0, 180, 360, 540], "bank": [0, 0, 0, 0], "bank_ms": 0.0, "pulse": 120.0, "attack": 0.065, "crack": 0.0, "lope": 1.0},
	"b4": {"fire": [0, 180, 360, 540], "bank": [0, 1, 0, 1], "bank_ms": 1.4, "pulse": 125.0, "attack": 0.07, "crack": 0.05, "lope": 1.4},
	"i6": {"fire": [0, 120, 240, 360, 480, 600], "bank": [0, 0, 0, 0, 0, 0], "bank_ms": 0.0, "pulse": 115.0, "attack": 0.06, "crack": 0.0, "lope": 0.8},
	"v6": {"fire": [0, 120, 240, 360, 480, 600], "bank": [0, 1, 0, 1, 0, 1], "bank_ms": 0.35, "pulse": 115.0, "attack": 0.06, "crack": 0.0, "lope": 0.9},
	"f6": {"fire": [0, 120, 240, 360, 480, 600], "bank": [0, 1, 0, 1, 0, 1], "bank_ms": 0.75, "pulse": 118.0, "attack": 0.06, "crack": 0.05, "lope": 1.0},
	"rot": {"fire": [0, 180, 360, 540], "bank": [0, 1, 0, 1], "bank_ms": 0.0, "pulse": 80.0, "attack": 0.03, "crack": 0.25, "lope": 2.2},
	"v10": {"fire": [0, 72, 144, 216, 288, 360, 432, 504, 576, 648], "bank": [0, 1, 0, 1, 0, 1, 0, 1, 0, 1], "bank_ms": 0.3,
		"pulse": 105.0, "attack": 0.05, "crack": 0.05, "lope": 0.6},
	"v12": {"fire": [0, 60, 120, 180, 240, 300, 360, 420, 480, 540, 600, 660], "bank": [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
		"bank_ms": 0.25, "pulse": 100.0, "attack": 0.05, "crack": 0.0, "lope": 0.5},
	"d6": {"fire": [0, 120, 240, 360, 480, 600], "bank": [0, 0, 0, 0, 0, 0], "bank_ms": 0.0, "pulse": 90.0, "attack": 0.02, "crack": 0.9, "lope": 1.2},
}


func _ready() -> void:
	var only := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	for id in Catalog.CAR_ORDER:
		if only.is_empty() or id in only:
			_make_car(id, _profile(id, TYPES.get(id, "i4"), Catalog.CARS[id]["sound"]))
	if only.is_empty() or "traffic" in only:
		_make_traffic()
	print("fertig in %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()


## Klangwerte aus dem Katalog (sub: Bollern/tiefes Rohr, harm: Helligkeit, rough: Unruhe, turbo: Lader dämpft)
func _profile(id: String, kind: String, snd: Dictionary) -> Dictionary:
	var K: Dictionary = KINDS[kind]
	var harm: Array = snd.get("harm", [1.0, 0.45, 0.2, 0.08])
	var s: float = snd.get("sub", 0.3)
	var b := clampf((float(harm[1]) + float(harm[2]) + float(harm[3])) / 1.1, 0.4, 1.3)
	var ro: float = snd.get("rough", 0.25)
	var tu: float = snd.get("turbo", 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var fire: Array = K["fire"]
	var cylg := []
	var runner := []
	var imb := 0.03 + 0.12 * s
	for z in fire.size():
		cylg.append(maxf(1.0 + rng.randfn(0.0, 1.0) * imb, 0.6))
		runner.append(float(K["bank"][z]) * K["bank_ms"] * FS / 1000.0 + rng.randf() * 0.12 * FS / 1000.0)
	return {
		"kind": kind, "fire": fire, "cylg": cylg, "runner": runner,
		"pulse": K["pulse"], "attack": K["attack"] * (1.15 - 0.3 * b),
		"jitter": (0.04 + 0.1 * ro) * K["lope"], "tjit": (0.002 + 0.005 * ro) * K["lope"],
		"crack": K["crack"] + 0.1 + 0.25 * ro,
		"pipe_len": 1.5 + 2.0 * s, "pipe_g": 0.45 + 0.3 * s, "pipe_lp": 2600.0 - 900.0 * s,
		"muffler": (800.0 + 1300.0 * b) * (1.0 - 0.22 * tu) + (350.0 if kind == "rot" else 0.0),
		"direct": (0.06 + 0.22 * b) * (1.0 - 0.5 * tu) + (0.12 if kind == "rot" else 0.0),
		"drone_f": 65.0 + 70.0 * (1.0 - s), "drone_g": 0.2 + 0.7 * s,
		"drive": 1.0 + 2.2 * ro, "intake": 0.0 if tu > 0.0 else 0.35 * b, "burble": 0.02 + 0.08 * ro,
		"flow": 0.35 + 0.35 * ro + 0.2 * b + (0.25 if kind == "rot" else 0.0),
		"seed": hash(id),
	}


func _make_car(id: String, P: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + id))
	var loops := {}
	var peak := 0.0001
	for r in EA.RPMS:
		for ld in ([1.0] if r == EA.RPMS[0] else [1.0, 0.0]):
			var secs := 1.4 if r == EA.RPMS[0] else (0.9 if r < 2000.0 else 0.75)
			var x := _render(P, r, ld, secs, int(P["seed"]) + int(r) * 7 + int(ld * 3.0))
			loops["%s_%d" % ["on" if ld > 0.5 else "off", int(r)]] = x
			for v in x:
				peak = maxf(peak, absf(v))
	var g := 0.92 / peak
	for name in loops:
		_save(OUT + id + "/" + name + ".wav", loops[name], g)
	print("%s (%s): %d Schleifen, %d ms" % [id, P["kind"], loops.size(), Time.get_ticks_msec() - t0])


## Verkehr: ein mittelgroßer Vierzylinder bei Stadttempo und ein Diesel-Bus, je mit Abrollgeräusch
func _make_traffic() -> void:
	var car := _profile("traffic_car", "i4", {"harm": [1.0, 0.4, 0.18, 0.06], "sub": 0.25, "rough": 0.15, "turbo": 0.0})
	var bus := _profile("traffic_bus", "d6", {"harm": [1.0, 0.62, 0.36, 0.16], "sub": 0.55, "rough": 0.5, "turbo": 0.5})
	for job in [["traffic_car", car, 2100.0, 0.45], ["traffic_bus", bus, 1300.0, 0.55]]:
		var x := _render(job[1], job[2], job[3], 1.0, int(job[1]["seed"]), 0.9)
		var peak := 0.0001
		for v in x:
			peak = maxf(peak, absf(v))
		_save(OUT + job[0] + "_%d.wav" % int(job[2]), x, 0.9 / peak)
		print(job[0])


## Eine nahtlose Schleife bei Drehzahl rpm_nom (wird auf eine ganze Zahl Samples je Arbeitsspiel gerundet:
## engine_audio.exact_rpm), Last ld (1 = Vollgas, 0 = Schub), etwa secs lang. tire: Abrollgeräusch dazu (Verkehr).
func _render(P: Dictionary, rpm_nom: float, ld: float, secs: float, seed: int, tire := 0.0) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cyc := int(round(FS * 120.0 / rpm_nom))  # Samples je Arbeitsspiel (zwei Umdrehungen)
	var rpm := FS * 120.0 / cyc
	var rn := clampf((rpm - 900.0) / 6500.0, 0.0, 1.0)
	var k := maxi(int(round(secs * FS / cyc)), 2)
	var n := k * cyc
	var warm_c := int(ceil(0.3 * FS / cyc))
	var warm := warm_c * cyc
	var xf := mini(int(0.06 * FS), n / 3)
	var total := warm + n + xf
	var src := PackedFloat32Array()
	src.resize(total + cyc)
	var ind := PackedFloat32Array()  # Hüllkurve der Ansaughübe
	ind.resize(total + cyc)
	var fire: Array = P["fire"]
	var cylg: Array = P["cylg"]
	var runner: Array = P["runner"]
	var plen := maxi(int(float(P["pulse"]) / 720.0 * cyc), 4)
	var ilen := maxi(int(200.0 / 720.0 * cyc), 4)
	var amp := lerpf(0.16, 1.0, ld) * (0.8 + 0.2 * rn)
	var jit: float = float(P["jitter"]) * lerpf(2.2, 1.0, ld) * lerpf(1.5, 0.7, rn)
	var tj: float = float(P["tjit"]) * cyc * lerpf(1.6, 1.0, ld) * (1.0 - 0.75 * rn)
	var crack: float = float(P["crack"]) * lerpf(0.4, 1.0, ld)
	var intake: float = float(P["intake"]) * ld * (0.4 + 0.6 * rn)
	# Anstieg höchstens ~0,6 ms: das Ventil öffnet auch im Leerlauf schlagartig (sonst klingt er dort nur dumpf)
	var att0: float = minf(float(P["attack"]), 13.0 / plen)
	var flow: float = float(P["flow"]) * lerpf(0.35, 1.0, ld) * (0.5 + 0.7 * rn)
	var cycles := warm_c + k + int(ceil(float(xf) / cyc)) + 2
	for c in cycles:
		for z in fire.size():
			var t0: float = (c * 720.0 + float(fire[z])) / 720.0 * cyc + float(runner[z]) + rng.randfn(0.0, 1.0) * tj
			var a: float = amp * float(cylg[z]) * maxf(1.0 + rng.randfn(0.0, 1.0) * jit, 0.15)
			var att := att0
			var pl := plen
			if ld < 0.5 and rng.randf() < float(P["burble"]) * (1.0 - ld):
				# Schub: unverbranntes Gemisch blubbert im Auspuff nach
				a *= rng.randf_range(2.0, 4.0)
				att *= 0.5
				pl = int(pl * 0.6)
			_stamp(src, t0, pl, att, a)
			# Verbrennungsknacken: kurzer, abklingender Rauschstoß am Anfang des Stoßes
			var i0 := int(t0)
			var ca := crack * a
			for j in 20:
				var idx := i0 + j
				if idx >= 0 and idx < src.size():
					src[idx] += ca * rng.randf_range(-1.0, 1.0) * exp(-j / 5.0)
			if intake > 0.0:
				_stamp(ind, t0 + cyc * 0.5, ilen, 0.4, intake)

	# Auspuff: Rohr (Laufzeit hin und zurück, Reflexion am offenen Ende), Dämpfer, Brummen, Endrohr
	var D := maxi(int(2.0 * float(P["pipe_len"]) / 480.0 * FS), 8)
	var ring := PackedFloat32Array()
	ring.resize(D)
	var w := 0
	var pg: float = P["pipe_g"]
	var a_pl := 1.0 - exp(-TAU * float(P["pipe_lp"]) / FS)
	var a_m := 1.0 - exp(-TAU * float(P["muffler"]) * lerpf(0.7, 1.0, ld) / FS)
	var direct: float = float(P["direct"]) * lerpf(0.5, 1.0, ld)
	var dg: float = P["drone_g"]
	var drive: float = float(P["drive"]) * lerpf(0.6, 1.0, ld)
	var bd := _bandpass(float(P["drone_f"]), 3.0)
	var bi := _bandpass(900.0, 0.8)
	var bt := _bandpass(650.0, 0.6)
	var lpl := 0.0
	var m1 := 0.0
	var m2 := 0.0
	var dx1 := 0.0
	var dx2 := 0.0
	var dy1 := 0.0
	var dy2 := 0.0
	var ix1 := 0.0
	var ix2 := 0.0
	var iy1 := 0.0
	var iy2 := 0.0
	var tx1 := 0.0
	var tx2 := 0.0
	var ty1 := 0.0
	var ty2 := 0.0
	var prev := 0.0
	var dc_x := 0.0
	var dc_y := 0.0
	var tmp := PackedFloat32Array()
	tmp.resize(total)
	var fl_lp := 0.0
	var a_fl := 1.0 - exp(-TAU * 2500.0 / FS)
	for i in total:
		var nz := rng.randf_range(-1.0, 1.0)
		fl_lp += a_fl * (nz - fl_lp)
		var x := src[i] * (1.0 + flow * fl_lp * 2.2)
		lpl += a_pl * (ring[w] - lpl)
		var y := x - pg * lpl
		ring[w] = y
		w = (w + 1) % D
		m1 += a_m * (y - m1)
		m2 += a_m * (m1 - m2)
		var d: float = bd[0] * y + bd[2] * dx2 - bd[3] * dy1 - bd[4] * dy2
		dx2 = dx1
		dx1 = y
		dy2 = dy1
		dy1 = d
		var mf := m2 + dg * d + direct * (y - m2)
		var r := mf - 0.9 * prev
		prev = mf
		var o := r * drive / (1.0 + absf(r * drive)) / drive * 1.6
		if intake > 0.0:
			var e := ind[i] * nz
			var iv: float = bi[0] * e + bi[2] * ix2 - bi[3] * iy1 - bi[4] * iy2
			ix2 = ix1
			ix1 = e
			iy2 = iy1
			iy1 = iv
			o += iv * 0.6
		if tire > 0.0:
			var tv: float = bt[0] * nz + bt[2] * tx2 - bt[3] * ty1 - bt[4] * ty2
			tx2 = tx1
			tx1 = nz
			ty2 = ty1
			ty1 = tv
			o += tv * tire * 0.25
		# Gleichanteil weg
		dc_y = o - dc_x + 0.995 * dc_y
		dc_x = o
		tmp[i] = dc_y
	# Schleife: Ende linear in den Anfang überblenden (der regelmäßige Teil ist dort gleich, nur der Zufall nicht)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = tmp[warm + i]
	for i in xf:
		var t := float(i) / xf
		out[i] = out[i] * t + tmp[warm + n + i] * (1.0 - t)
	return out


## Druckstoß ab Zeitpunkt t0 (Samples, mit Bruchteil): Viertelsinus hoch (Anteil att), dann quadratisch abklingend
static func _stamp(buf: PackedFloat32Array, t0: float, L: int, att: float, a: float) -> void:
	var i0 := int(floor(t0))
	var fr := t0 - i0
	var n := buf.size()
	for j in L + 1:
		var u := (j - fr) / L
		if u < 0.0 or u > 1.0:
			continue
		var idx := i0 + j
		if idx < 0 or idx >= n:
			continue
		var v := sin(u / att * PI * 0.5) if u < att else pow(1.0 - (u - att) / (1.0 - att), 2.0)
		buf[idx] += a * v


## Bandpass (RBJ, Spitze 0 dB): [b0, b1, b2, a1, a2] normiert, b1 = 0
static func _bandpass(f: float, q: float) -> Array:
	var w0 := TAU * f / FS
	var al := sin(w0) / (2.0 * q)
	var a0 := 1.0 + al
	return [al / a0, 0.0, -al / a0, -2.0 * cos(w0) / a0, (1.0 - al) / a0]


func _save(path: String, x: PackedFloat32Array, g: float) -> void:
	var data := PackedByteArray()
	data.resize(x.size() * 2)
	for i in x.size():
		data.encode_s16(i * 2, int(clampf(x[i] * g, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = int(FS)
	s.stereo = false
	s.data = data
	s.save_to_wav(ProjectSettings.globalize_path(path))
