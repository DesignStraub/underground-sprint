extends RefCounted
## Verstecktes in den Städten (seit 2.50): je Stadt eine Hinterhof-Werkstatt und ein Kennzeichen.
## - Werkstatt: an einer Gasse oder einem Abzweig abseits der Rennlinie (sonst am Rand der Hauptstraße), ein Rolltor mit
##   Leuchtschrift. Wie die versteckten Läden in Underground 2 verrät sie farbiges Licht (Bernstein), das man von der
##   Straße aus sieht. Vorbeifahren entdeckt sie: exklusiver Lack der Stadt (Catalog, find "werkstatt:<Stadt>"), XP,
##   danach ein Sprungziel auf der Karte.
## - Kennzeichen: ein großes, leuchtendes Schild mit dem Unterscheidungszeichen der Stadt schwebt über der Fahrbahn an
##   einer anderen Stelle; durchfahren sammelt es ein (find "kennzeichen:<Stadt>"), in der Garage unter Optik > Kennzeichen.
## Lage nur aus der Strecke und ihrem Seed: jedes Laden der Stadt gibt dieselben Stellen.

const Track := preload("res://scripts/track_builder.gd")
const UI := preload("res://scripts/ui_style.gd")

const SHOP_R := 11.0  # so nah muss man an der Werkstatt vorbei (m)
const PLATE_R := 3.6  # durch das Schild fahren
const AMBER := Color(1.0, 0.62, 0.16)


## Stellen in Streckenkoordinaten: {"shop": {p, door, face}, "plate": {p}}
static func plan(tr: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 4099 + 77
	var cand := []
	for p in tr["paths"]:
		if int(p["id"]) == 0 or str(p["kind"]) in ["main", "spur", "ramp"] or p.get("closed", false):
			continue
		if float(p.get("length", (p["curve"] as Curve3D).get_baked_length())) > 60.0:
			cand.append(p)
	var out := {}
	var shop_path := -1
	if not cand.is_empty():
		var p: Dictionary = cand[rng.randi() % cand.size()]
		shop_path = int(p["id"])
		var c: Curve3D = p["curve"]
		var d := c.get_baked_length() * rng.randf_range(0.4, 0.65)
		out["shop"] = _side_spot(c, d, float(p["half_w"]) + 2.2, 1.0 if rng.randf() < 0.5 else -1.0)
	else:
		var c0: Curve3D = tr["curve"]
		var d0 := c0.get_baked_length() * rng.randf_range(0.3, 0.8)
		out["shop"] = _side_spot(c0, d0, Track.hw(tr, d0) + Track.WALK * 0.85, 1.0 if rng.randf() < 0.5 else -1.0)
	# Kennzeichen: auf einem anderen Nebenweg, sonst auf der Hauptstraße am Fahrbahnrand
	var others := cand.filter(func(q): return int(q["id"]) != shop_path)
	var pc: Curve3D
	var half := 3.0
	var dp := 0.0
	if not others.is_empty():
		var q: Dictionary = others[rng.randi() % others.size()]
		pc = q["curve"]
		half = float(q["half_w"])
		dp = pc.get_baked_length() * rng.randf_range(0.3, 0.7)
	else:
		pc = tr["curve"]
		dp = pc.get_baked_length() * rng.randf_range(0.15, 0.85)
		half = Track.hw(tr, dp)
	var f := Track.frame_at(pc, dp)
	var lat := rng.randf_range(-0.55, 0.55) * half
	out["plate"] = {"p": (f["pos"] as Vector3) + (f["right"] as Vector3) * lat + Vector3(0, float(f["y"]) + 1.35, 0),
		"fwd": f["fwd"]}
	return out


static func _side_spot(c: Curve3D, d: float, off: float, side: float) -> Dictionary:
	var f := Track.frame_at(c, d)
	var pos: Vector3 = (f["pos"] as Vector3) + Vector3(0, float(f["y"]), 0)
	var r: Vector3 = f["right"]
	return {"p": pos, "door": pos + r * side * off, "face": -r * side}


## Werkstatt: Rolltor, Leuchtschrift, bernsteinfarbenes Licht (Knoten in Streckenkoordinaten)
static func build_shop(s: Dictionary, found: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Werkstatt"
	var face: Vector3 = s["face"]
	root.transform = Transform3D(Basis.looking_at(face, Vector3.UP), s["door"])  # -Z der Werkstatt zeigt zur Straße
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(8.0, 5.0, 0.4)
	wall.mesh = wm
	wall.position = Vector3(0, 2.5, 0.3)
	wall.material_override = _mat(Color(0.14, 0.13, 0.13), 0.0)
	root.add_child(wall)
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(4.6, 3.3, 0.1)
	door.mesh = dm
	door.position = Vector3(0, 1.65, 0.05)
	door.material_override = _mat(Color(0.32, 0.33, 0.35), 0.0)
	root.add_child(door)
	for i in 8:  # Lamellen des Rolltors
		var sl := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(4.6, 0.04, 0.02)
		sl.mesh = sm
		sl.position = Vector3(0, 0.25 + i * 0.4, -0.01)
		sl.material_override = _mat(Color(0.2, 0.2, 0.22), 0.0)
		root.add_child(sl)
	var strip := MeshInstance3D.new()
	var stm := BoxMesh.new()
	stm.size = Vector3(5.2, 0.07, 0.07)
	strip.mesh = stm
	strip.position = Vector3(0, 3.45, -0.05)
	strip.material_override = _mat(AMBER, 2.2 if not found else 0.9)
	root.add_child(strip)
	var sign := Label3D.new()
	sign.text = "WERKSTATT"
	sign.font = UI.font("wide", 0.0, 3)
	sign.font_size = 72
	sign.pixel_size = 0.006
	sign.modulate = AMBER
	sign.outline_size = 0
	sign.shaded = false
	sign.position = Vector3(0, 4.05, -0.12)
	sign.rotation.y = PI  # Schrift zur Straße (-Z)
	root.add_child(sign)
	var light := OmniLight3D.new()
	light.light_color = AMBER
	light.light_energy = 2.4 if not found else 1.0
	light.omni_range = 16.0
	light.position = Vector3(0, 3.2, -2.5)
	root.add_child(light)
	return root


## Kennzeichen: großes Schild, leuchtet weiß, dreht sich langsam (Knoten in Streckenkoordinaten)
static func build_plate(s: Dictionary, code: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Kennzeichen"
	root.position = s["p"]
	var spin := Node3D.new()
	spin.name = "Spin"
	root.add_child(spin)
	var plate := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(1.9, 0.44, 0.05)
	plate.mesh = pm
	plate.material_override = _mat(Color(0.95, 0.95, 0.92), 0.55)
	spin.add_child(plate)
	var band := MeshInstance3D.new()  # blaues EU-Feld links
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.44, 0.06)
	band.mesh = bm
	band.position = Vector3(-0.85, 0, 0)
	band.material_override = _mat(Color(0.05, 0.2, 0.75), 0.4)
	spin.add_child(band)
	for side in [1.0, -1.0]:
		var t := Label3D.new()
		t.text = code + "-NG"
		t.font = UI.font("cond", 0.0, 1)
		t.font_size = 96
		t.pixel_size = 0.0034
		t.modulate = Color(0.04, 0.04, 0.05)
		t.outline_size = 0
		t.shaded = false
		t.position = Vector3(0.08, -0.01, 0.035 * side)
		if side < 0.0:
			t.rotation.y = PI
		spin.add_child(t)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.85, 0.9, 1.0)
	glow.light_energy = 0.8
	glow.omni_range = 6.0
	root.add_child(glow)
	return root


static func _mat(c: Color, emit: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	return m
