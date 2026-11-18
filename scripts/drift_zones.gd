extends RefCounted
## Driftzonen in der offenen Welt (seit 2.45, Fahrplan Punkt 5): in jeder Stadt der kurvigste Abschnitt der Hauptstraße
## (bis 650 m, nicht über dem Start des Rennens), Anfang und Ende als orange Linie quer über die Fahrbahn mit zwei
## kleinen Pfosten, am Anfang ein Schild mit der Bestleistung. world.gd zählt die Drift-Punkte zwischen den Linien
## (Fahrtrichtung der Hauptstraße) und vergibt Bronze, Silber, Gold.

const Track := preload("res://scripts/track_builder.gd")

const W := 650.0  # Länge der Zone (höchstens 60 % der Strecke)
const STEP := 10.0
const COL := Color(1.0, 0.55, 0.12)
## Ziele je Meter Zone (Bronze, Silber, Gold): bei 650 m 3.000, 7.000, 12.000 Punkte
const PER_M := [4.6, 10.8, 18.5]
const STARS := ["BRONZE", "SILBER", "GOLD"]


## Zone auf der Hauptstraße einer gebauten Stadtstrecke: {d0, d1}; leer, wenn die Strecke zu kurz ist
static func plan(track: Dictionary) -> Dictionary:
	var c: Curve3D = track["curve"]
	var L: float = track["length"]
	var w := minf(W, L * 0.6)
	if w < 250.0:
		return {}
	var n := int(L / STEP)
	var turns := PackedFloat32Array()
	for i in n:
		var f0: Vector3 = Track.frame_at(c, i * STEP)["fwd"]
		var f1: Vector3 = Track.frame_at(c, minf((i + 1) * STEP, L))["fwd"]
		turns.append(absf(Vector3(f0.x, 0, f0.z).signed_angle_to(Vector3(f1.x, 0, f1.z), Vector3.UP)))
	var k := int(w / STEP)
	var start: float = track.get("start", 0.0)
	var best := -1.0
	var d0 := -1.0
	var sum := 0.0
	for i in n:
		sum += turns[i]
		if i >= k:
			sum -= turns[i - k]
		if i < k - 1:
			continue
		var a := (i - k + 1) * STEP
		if a < 30.0 or a + w > L - 30.0:
			continue
		if start > a - 60.0 and start < a + w + 60.0:
			continue  # nicht über den Start des Rennens (dort steht sein Marker)
		if sum > best:
			best = sum
			d0 = a
	if d0 < 0.0:
		return {}
	return {"d0": d0, "d1": d0 + w, "turn": best}


static func targets(z: Dictionary) -> Array:
	var w: float = z["d1"] - z["d0"]
	return PER_M.map(func(k): return int(round(w * k / 50.0)) * 50)


static func stars(score: int, tg: Array) -> int:
	var s := 0
	for t in tg:
		if score >= t:
			s += 1
	return s


## Linien, Pfosten und Schild als Kinder der Strecke (verschwinden mit ihr); Schild: Name und Bestleistung
static func build_gates(track: Dictionary, z: Dictionary, title: String, best_line: String) -> Label3D:
	var root: Node3D = track["node"]
	var c: Curve3D = track["curve"]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = COL
	mat.emission_enabled = true
	mat.emission = COL
	mat.emission_energy_multiplier = 1.6
	var label: Label3D = null
	for d in [float(z["d0"]), float(z["d1"])]:
		var f := Track.frame_at(c, d)
		var hw := Track.hw(track, d)
		var y := Track.elev_at(c, d)
		var g := Node3D.new()
		g.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + Vector3(0, y, 0))
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(hw * 2.0, 0.03, 0.55)
		strip.mesh = bm
		strip.material_override = mat
		strip.position.y = 0.03
		g.add_child(strip)
		for sd in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.18, 1.4, 0.18)
			post.mesh = pm
			post.material_override = mat
			post.position = Vector3(sd * (hw + 0.6), 0.7, 0.0)
			g.add_child(post)
		if d == float(z["d0"]):
			label = Label3D.new()
			label.text = title + ("\n" + best_line if best_line != "" else "")
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 64
			label.pixel_size = 0.018
			label.modulate = COL
			label.outline_size = 10
			label.outline_modulate = Color(0, 0, 0, 0.8)
			label.position = Vector3(hw + 0.6, 3.0, 0.0)
			g.add_child(label)
		root.add_child(g)
	return label


## Linienzug der Zone in Weltkoordinaten (x, z) für die Minikarte
static func polyline(track: Dictionary, z: Dictionary, xf: Transform3D) -> PackedVector2Array:
	var c: Curve3D = track["curve"]
	var out := PackedVector2Array()
	var d: float = z["d0"]
	while d <= float(z["d1"]):
		var q: Vector3 = xf * c.sample_baked(d)
		out.append(Vector2(q.x, q.z))
		d += 10.0
	return out
