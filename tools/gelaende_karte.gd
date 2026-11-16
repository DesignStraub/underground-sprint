extends Node
## Werkzeug (seit 2.39): Draufsicht eines Geländes (scripts/offroad.gd) mit Höhen (Schummerung), Untergrund, Teichen,
## Rampen, Bäumen, Gebäuden und Zaun, dazu Prüfungen ("GK ..."): Rampen auf ebenem Grund, steilste Stelle, kleinste
## Bodenhöhe, Abstand zu fremden Straßen, Dörfern, Seen, Windparks, Masten.
## godot --headless --path . res://tools/gelaende_karte.tscn -- --png=/pfad.png [--area=0] [--px=1.0]

const Layout := preload("res://scripts/world_layout.gd")
const Offroad := preload("res://scripts/offroad.gd")

const COLS := {"gras": Color(0.16, 0.3, 0.1), "rasen": Color(0.34, 0.56, 0.2), "gruen": Color(0.45, 0.72, 0.28),
	"sand": Color(0.86, 0.78, 0.55), "kies": Color(0.62, 0.6, 0.55), "erde": Color(0.45, 0.33, 0.2),
	"schotter": Color(0.5, 0.49, 0.47), "asphalt": Color(0.2, 0.2, 0.22)}


func _ready() -> void:
	var w := Layout.build()
	var png := ""
	var only := -1
	var ppm := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--png="):
			png = a.substr(6)
		if a.begins_with("--area="):
			only = int(a.substr(7))
		if a.begins_with("--px="):
			ppm = float(a.substr(5))
	var list: Array = w.get("offroad", [])
	print("GK %d Flächen" % list.size())
	var land = null
	if OS.get_cmdline_user_args().has("--land"):
		land = load("res://scripts/landscape.gd").new()
		land.setup(w)
	for i in list.size():
		if only >= 0 and i != only:
			continue
		var a: Dictionary = list[i]
		_check(a, w, land)
		if png != "":
			_draw(a, png.replace(".png", "_%d.png" % i), ppm)
	if land:
		land.free()
	get_tree().quit()


func _check(a: Dictionary, w: Dictionary, land) -> void:
	print("GK %s Tor bei (%.0f, %.0f), Ausfahrt d=%.0f, Bäume %d, Rampen %d, Teiche %d" % [a["name"], a["o"].x + a["u"].x * a["gate_s"],
		a["o"].y + a["u"].y * a["gate_s"], a["exit_d"], a["tree_list"].size(), a["ramps"].size(), a["ponds"].size()])
	print("GK   Boden am Tor %.2f, Mitte (%.0f, %.0f)" % [Offroad.base_h(a, Vector2(a["gate_s"], 0.0)), a["mid"].x, a["mid"].y])
	for r in a["ramps"]:
		var lo := 1e9
		var hi := -1e9
		for k in 12:
			for j in 5:
				var l: Vector2 = r["c"] + r["d"] * (-6.0 + (r["l"] + 6.0) * k / 11.0) + r["x"] * (r["w"] / 2.0) * (j / 2.0 - 1.0)
				var h := Offroad.base_h(a, l)
				lo = minf(lo, h)
				hi = maxf(hi, h)
		print("GK   Rampe %s bei (%.0f, %.0f) h=%.1f l=%.0f: Boden %.2f..%.2f %s" % [r["look"], r["c"].x, r["c"].y, r["h"], r["l"], lo, hi,
			"OK" if hi - lo < 0.06 else "UNEBEN"])
	# steilste Stelle und kleinste Höhe (ohne Teiche) auf der befahrbaren Fläche
	var smax := 0.0
	var sp := Vector2.ZERO
	var hmin := 1e9
	var hp := Vector2.ZERO
	var t := 1.0
	while t < float(a["d"]):
		var s := -float(a["w"]) / 2.0
		while s < float(a["w"]) / 2.0:
			var l := Vector2(s, t)
			if Offroad.area_sd(a, l) < 0.0 and Offroad.pond_at(a, l).is_empty():
				var g := Offroad.gradient(a, Offroad.world(a, l)).length()
				if g > smax:
					smax = g
					sp = l
				var h := Offroad.base_h(a, l)
				if h < hmin:
					hmin = h
					hp = l
			s += 3.0
		t += 3.0
	print("GK   steilste Stelle %.2f (%.0f°) bei (%.0f, %.0f), tiefste %.2f bei (%.0f, %.0f)" % [smax, rad_to_deg(atan(smax)), sp.x, sp.y,
		hmin, hp.x, hp.y])
	# Abstand zu fremden Straßen (Umriss plus Rand)
	var best := 1e9
	var bw := ""
	for rd in w["roads"]:
		var pl: PackedVector2Array = rd[0]
		if pl == a["access"]:
			continue
		for k in pl.size() - 1:
			for q in a["outline"]:
				var d := Geometry2D.get_closest_point_to_segment(q, pl[k], pl[k + 1]).distance_to(q)
				if d < best:
					best = d
					bw = "Straße Art %d bei (%.0f, %.0f)" % [rd[1], pl[k].x, pl[k].y]
	print("GK   nächste fremde Straße %.0f m vom Zaun (%s)" % [best, bw])
	if land:
		for v in land._villages:
			_near(a, "Dorf " + v["name"], v["pos"], v["r"])
		for lk in land._lakes:
			_near(a, "See", lk["pos"], lk["r"])
		for pk in land._parks:
			_near(a, "Windpark", pk["pos"], 900.0)
		for m in land._marks:
			_near(a, "Wahrzeichen " + m["kind"], m["pos"], 200.0)
		for li in land._lines:
			for q in li:
				_near(a, "Mast", q, 10.0)


func _near(a: Dictionary, what: String, p: Vector2, r: float) -> void:
	var d := 1e9
	for q in a["outline"]:
		d = minf(d, q.distance_to(p) - r)
	if d < 80.0:
		print("GK   NAH: %s %.0f m vom Zaun" % [what, d])


func _draw(a: Dictionary, path: String, ppm: float) -> void:
	var m := Offroad.SKIRT + 8.0
	var s0 := -float(a["w"]) / 2.0 - m
	var t0 := -m
	var W := int((float(a["w"]) + 2.0 * m) * ppm)
	var H := int((float(a["d"]) + 2.0 * m) * ppm)
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for j in H:
		for i in W:
			# Bild: oben die Straßenseite? nein: t wächst nach oben (Straße unten)
			var l := Vector2(s0 + (i + 0.5) / ppm, t0 + (H - j - 0.5) / ppm)
			var sd := Offroad.area_sd(a, l)
			var c := Color(0.08, 0.08, 0.09)
			if sd < Offroad.SKIRT:
				var h := Offroad.base_h(a, l)
				var gx := Offroad.base_h(a, l + Vector2(1.0, 0.0)) - h
				var gy := Offroad.base_h(a, l + Vector2(0.0, 1.0)) - h
				var shade := clampf(0.75 - gx * 0.9 + gy * 0.9, 0.25, 1.3)
				c = COLS.get(Offroad.surf_at(a, l), Color.MAGENTA) * shade
				if not Offroad.pond_at(a, l, h).is_empty():
					c = Color(0.15, 0.3, 0.6)
				if sd > 0.0:
					c = c.lerp(Color(0.12, 0.14, 0.1), 0.6)
				# Höhenlinien alle 2 m
				if fposmod(h, 2.0) < 0.12 * maxf(1.0, (absf(gx) + absf(gy)) * 4.0):
					c = c.lerp(Color.BLACK, 0.25)
			img.set_pixel(i, j, c)
	var px := func(l: Vector2) -> Vector2i: return Vector2i(int((l.x - s0) * ppm), H - 1 - int((l.y - t0) * ppm))
	for l in a["outline_l"]:
		var q: Vector2i = px.call(l)
		img.fill_rect(Rect2i(q.x - 1, q.y - 1, 3, 3), Color.WHITE)
	for r in a["ramps"]:
		for k in 20:
			for side in [-1.0, 1.0]:
				var l: Vector2 = r["c"] + r["d"] * float(r["l"]) * k / 19.0 + r["x"] * side * float(r["w"]) / 2.0
				var q: Vector2i = px.call(l)
				img.fill_rect(Rect2i(q.x - 1, q.y - 1, 2, 2), Color(1, 0.2, 0.1))
		var tip: Vector2i = px.call(r["c"] + r["d"] * float(r["l"]))
		img.fill_rect(Rect2i(tip.x - 2, tip.y - 2, 5, 5), Color(1, 1, 0))
	for tr in a["tree_list"]:
		var q: Vector2i = px.call(tr[0])
		img.fill_rect(Rect2i(q.x - 2, q.y - 2, 5, 5), Color(0.02, 0.12, 0.02))
	for b in a["builds"]:
		var q: Vector2i = px.call(b["c"])
		img.fill_rect(Rect2i(q.x - 4, q.y - 4, 9, 9), Color(0.8, 0.8, 0.85))
	for k in a["knock"]:
		var q: Vector2i = px.call(k["c"])
		img.fill_rect(Rect2i(q.x - 1, q.y - 1, 3, 3), Color(1, 0.2, 1))
	for r in a["rocks"]:
		var q: Vector2i = px.call(r[0])
		img.fill_rect(Rect2i(q.x - 2, q.y - 2, 5, 5), Color(0.4, 0.4, 0.4))
	var g: Vector2i = px.call(Vector2(a["gate_s"], 0.0))
	img.fill_rect(Rect2i(g.x - 5, g.y - 3, 11, 6), Color(0.1, 0.8, 1.0))
	img.save_png(path)
	print("GK   Bild %s (%dx%d)" % [path, W, H])
