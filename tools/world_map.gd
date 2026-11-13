extends Node
## Werkzeug: plant die Open World (scripts/world_layout.gd), gibt die Lage aus und zeichnet eine Draufsicht
## (Ring, Auffahrten, alle Wege jeder Stadt) als PNG.
## godot --path . res://tools/world_map.tscn -- --worldlog [--png=/pfad.png]

const Layout := preload("res://scripts/world_layout.gd")
const Track := preload("res://scripts/track_builder.gd")


func _ready() -> void:
	var w := Layout.build()
	var png := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
	if png != "":
		var R: float = w["ring_r"]
		var ext := R + 4600.0
		var S := 2000
		var img := Image.create(S, S, false, Image.FORMAT_RGB8)
		img.fill(Color(0.05, 0.05, 0.07))
		var px := func(p: Vector3) -> Vector2i:
			return Vector2i(int((p.x + ext) / (2.0 * ext) * S), int((p.z + ext) / (2.0 * ext) * S))
		for rk in ["ring", "oring"]:
			var rg: Array = w.get(rk, [])
			for k in rg.size():
				var a: Vector3 = rg[k]
				var b: Vector3 = rg[(k + 1) % rg.size()]
				for j in 8:
					_dot(img, px.call(a.lerp(b, j / 8.0)), Color(1, 0.8, 0.2), 2)
		# Mitte: Kreisel und Diagonalen (Autobahnstücke ab Ring 2)
		for sg in w["segments"]:
			if sg.get("ring", 0) >= 2:
				var sp: Array = sg["race"]["pts"]
				for k in sp.size() - 1:
					for j in 8:
						_dot(img, px.call((sp[k] as Vector3).lerp(sp[k + 1], j / 8.0)), Color(1, 0.8, 0.2), 2)
		# Auffahrten (gerade und Bögen zu den Ziel-Ausfahrten)
		for rd in w["roads"]:
			if rd[1] == 1:
				var pl: PackedVector2Array = rd[0]
				for k in pl.size() - 1:
					for j in 10:
						var q2 := pl[k].lerp(pl[k + 1], j / 10.0)
						_dot(img, px.call(Vector3(q2.x, 0, q2.y)), Color(1, 1, 1), 1)
		var cols := [Color(0.3, 0.9, 1), Color(0.4, 1, 0.5), Color(1, 0.5, 0.2), Color(1, 0.4, 0.8)]
		var ci := 0
		for c in w["cities"]:
			var job := Track.begin(c["race"])
			var tr: Dictionary = job["track"]
			(job["root"] as Node).free()
			var xf: Transform3D = c["xf"]
			for p in tr["paths"]:
				for q in (p["curve"] as Curve3D).get_baked_points():
					_dot(img, px.call(xf * q), cols[ci % 4], 1)
			_dot(img, px.call(c["exit_world"]), Color.WHITE, 4)
			_dot(img, px.call(c["start_world"]), Color.RED, 4)
			ci += 1
		img.save_png(png)
	get_tree().quit()


func _dot(img: Image, p: Vector2i, c: Color, r: int) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var q := p + Vector2i(x, y)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				img.set_pixelv(q, c)
