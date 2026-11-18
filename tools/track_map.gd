extends Control
## Werkzeug: Strecke von oben als Plan. Grau Hauptstraße, Farbe je Nebenweg (Gabelung, Gasse, Sackgasse),
## rot Wände, gelb Umfahrbares, grün Rampen, blau Seen, orange Baustellen, weiße Punkte Lampen mit Reichweite.
## godot --path . res://tools/track_map.tscn -- --race=8 --out=/pfad/karte.png [--zoom=d0:d1] [--world]
## --world: Strecke wie in der freien Fahrt (Straßennetz, Querstraßen, Ausfahrten), dazu die Häuser echter Städte

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const Layout := preload("res://scripts/world_layout.gd")

const KIND_COL := {"main": Color(0.45, 0.45, 0.5), "fork": Color(0.2, 0.8, 1.0), "alley": Color(1.0, 0.4, 0.9),
	"spur": Color(0.6, 0.5, 1.0), "lake": Color(0.3, 1.0, 0.6)}

var track: Dictionary
var walls: Array = []  # [a, b] in XZ
var props: Array = []
var lights: Array = []  # [pos, range]
var out := "/tmp/track_map.png"
var rect := Rect2()
var fixed := Rect2()
var _frames := 0


func _ready() -> void:
	var race_i := 0
	var zoom := Vector2(-1, -1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			race_i = int(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--rect="):  # Ausschnitt x0:z0:x1:z1 (Streckenkoordinaten)
			var r := a.substr(7).split(":")
			fixed = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
		elif a.begins_with("--zoom="):
			var z := a.substr(7).split(":")
			zoom = Vector2(float(z[0]), float(z[1]))
	track = Track.build(Layout.world_race(race_i) if OS.get_cmdline_user_args().has("--world") else Catalog.RACES[race_i])
	var root: Node3D = track["node"]
	add_child(root)  # nur für globale Lagen, wird nicht gezeichnet (kein Kamera-Viewport)
	_collect(root)
	var pts := PackedVector2Array()
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var d := 0.0
		while d <= L:
			if zoom.x < 0.0 or p["id"] != 0 or (d >= zoom.x and d <= zoom.y):
				var q := c.sample_baked(d)
				if zoom.x < 0.0 or p["id"] == 0:
					pts.append(Vector2(q.x, q.z))
			d += 10.0
	rect = Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		rect = rect.expand(q)
	rect = rect.grow(40.0)
	if fixed.size.x > 0.0:
		rect = fixed
	if OS.get_cmdline_user_args().has("--wallcheck"):
		_wallcheck()
	print("Karte: %s, %.0f x %.0f m, %d Wandstücke, %d Lampen" % [Catalog.RACES[race_i]["name"], rect.size.x, rect.size.y, walls.size(), lights.size()])


func _collect(n: Node) -> void:
	for c in n.get_children():
		if c is CollisionShape3D and c.shape is ConcavePolygonShape3D and c.get_parent() is StaticBody3D:
			var f: PackedVector3Array = (c.shape as ConcavePolygonShape3D).get_faces()
			var xf: Transform3D = (c as Node3D).global_transform
			for i in range(0, f.size(), 3):
				var a: Vector3 = xf * f[i]
				var b: Vector3 = xf * f[i + 1]
				var e: Vector3 = xf * f[i + 2]
				# senkrechte Wand: zwei Ecken unten, eine oben; als Strecke die weiteste Ausdehnung in XZ
				var seg := [Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(e.x, e.z)]
				var best := [seg[0], seg[1]]
				for p in [[0, 1], [1, 2], [0, 2]]:
					if seg[p[0]].distance_to(seg[p[1]]) > best[0].distance_to(best[1]):
						best = [seg[p[0]], seg[p[1]]]
				walls.append(best)
		elif c is CollisionShape3D and c.shape is BoxShape3D and c.get_parent() is StaticBody3D:
			var xf: Transform3D = (c as Node3D).global_transform
			var s: Vector3 = (c.shape as BoxShape3D).size / 2.0
			var corners := [Vector3(-s.x, 0, -s.z), Vector3(s.x, 0, -s.z), Vector3(s.x, 0, s.z), Vector3(-s.x, 0, s.z)]
			for i in 4:
				var a: Vector3 = xf * corners[i]
				var b: Vector3 = xf * corners[(i + 1) % 4]
				walls.append([Vector2(a.x, a.z), Vector2(b.x, b.z)])
		if c is Knockable:
			var p: Vector3 = (c as Node3D).global_position
			props.append(Vector2(p.x, p.z))
		elif c is OmniLight3D:
			var p: Vector3 = (c as Node3D).global_position
			lights.append([Vector2(p.x, p.z), (c as OmniLight3D).omni_range])
		elif c is SpotLight3D:
			var p: Vector3 = (c as Node3D).global_position
			lights.append([Vector2(p.x, p.z), (c as SpotLight3D).spot_range * 0.5])
		_collect(c)


func _px(p: Vector2) -> Vector2:
	var s := minf(size.x / rect.size.x, size.y / rect.size.y)
	return (p - rect.position) * s + (size - rect.size * s) / 2.0


func _process(_dt: float) -> void:
	queue_redraw()
	_frames += 1
	if _frames == 4:
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.05))
	var s := minf(size.x / rect.size.x, size.y / rect.size.y)
	for l in lights:
		draw_circle(_px(l[0]), l[1] * s, Color(1.0, 0.9, 0.6, 0.06))
	for lk in track["lakes"]:
		var c: Vector3 = lk["center"]
		var au: Vector3 = lk["au"] * lk["hu"]
		var av: Vector3 = lk["av"] * lk["hv"]
		var poly := PackedVector2Array()
		for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			var q: Vector3 = c + au * k[0] + av * k[1]
			poly.append(_px(Vector2(q.x, q.z)))
		draw_colored_polygon(poly, Color(0.1, 0.25, 0.6, 0.8))
	var bd: Array = track["city"].get("buildings", []) if track["city"] is Dictionary else []
	for i in range(0, bd.size(), 6):
		var bc := _px(Vector2(bd[i], bd[i + 1]))
		var bs := Vector2(bd[i + 2], bd[i + 3]) * s
		draw_set_transform(bc, float(bd[i + 4]))
		draw_rect(Rect2(-bs / 2.0, bs), Color(0.35, 0.3, 0.25, 0.5))
		draw_set_transform(Vector2.ZERO)
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var line := PackedVector2Array()
		var L := c.get_baked_length()
		var d := 0.0
		while d <= L:
			var q := c.sample_baked(d)
			line.append(_px(Vector2(q.x, q.z)))
			d += 4.0
		var col: Color = KIND_COL.get(p["kind"], Color.WHITE)
		draw_polyline(line, Color(col.r, col.g, col.b, 0.35), maxf(p["half_w"] * 2.0 * s, 1.0))
		draw_polyline(line, col, 1.0)
		if p["id"] != 0:
			draw_string(ThemeDB.fallback_font, line[line.size() / 2] + Vector2(6, 0), "%s #%d" % [p["kind"], p["id"]],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	for r in track["ramps"]:
		var c: Curve3D = track["paths"][r["path"]]["curve"]
		for d in [r["d0"], r["d1"]]:
			var f := Track.frame_at(c, d)
			var a: Vector3 = f["pos"] + f["right"] * r["lat0"]
			var b: Vector3 = f["pos"] + f["right"] * r["lat1"]
			draw_line(_px(Vector2(a.x, a.z)), _px(Vector2(b.x, b.z)), Color(0.3, 1.0, 0.3), 2.0)
	for b in track["blocks"]:
		var f := Track.frame_at(track["curve"], (b["from"] + b["to"]) / 2.0)
		var q: Vector3 = f["pos"] + f["right"] * b["lane"]
		draw_circle(_px(Vector2(q.x, q.z)), 4.0, Color(1.0, 0.55, 0.1))
	for w in walls:
		draw_line(_px(w[0]), _px(w[1]), Color(1.0, 0.2, 0.2, 0.9), 1.0)
	for p in props:
		draw_circle(_px(p), 1.6, Color(1.0, 0.9, 0.2))
	for l in lights:
		draw_circle(_px(l[0]), 1.2, Color(1, 1, 1))
	# Start und alle 250 m eine Marke
	var c0: Curve3D = track["curve"]
	var d := 0.0
	while d < track["length"]:
		var q := c0.sample_baked(d)
		draw_string(ThemeDB.fallback_font, _px(Vector2(q.x, q.z)) + Vector2(4, -4), str(int(d)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.7, 0.7, 0.7))
		d += 250.0
	var st := c0.sample_baked(track["start"])
	draw_circle(_px(Vector2(st.x, st.z)), 5.0, Color(0.2, 1.0, 0.4))


## --wallcheck: steht irgendwo eine Wand auf der Fahrbahn eines Weges? (Mittellinie alle 2 m gegen alle Wandstücke)
func _wallcheck() -> void:
	var g := {}
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		if a.distance_to(b) > 60.0:
			continue
		var lo := a.min(b)
		var hi := a.max(b)
		for gx in range(floori(lo.x / 10.0), floori(hi.x / 10.0) + 1):
			for gz in range(floori(lo.y / 10.0), floori(hi.y / 10.0) + 1):
				var k := Vector2i(gx, gz)
				if not g.has(k):
					g[k] = []
				g[k].append(w)
	var bad := 0
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var lim: float = float(p["half_w"]) * 0.7
		var d := 3.0
		var last := -100.0
		while d < L - 3.0:
			var q3 := c.sample_baked(d)
			var q := Vector2(q3.x, q3.z)
			var k := Vector2i(floori(q.x / 10.0), floori(q.y / 10.0))
			var hit := false
			for gx in range(k.x - 1, k.x + 2):
				for gz in range(k.y - 1, k.y + 2):
					for w in g.get(Vector2i(gx, gz), []):
						if Geometry2D.get_closest_point_to_segment(q, w[0], w[1]).distance_to(q) < lim:
							hit = true
			if hit and d - last > 15.0:
				print("WAND AUF WEG #%d %s %s bei %.0f m (%.0f, %.0f)" % [p["id"], p["kind"], p.get("street_name", ""), d, q.x, q.y])
				bad += 1
				last = d
			d += 2.0
	print("WANDCHECK %d Stellen" % bad)
	# offene Enden: Anfang oder Ende eines Nebenweges, das an keinem anderen Weg liegt (Sackgasse)
	var open := 0
	for p in track["paths"]:
		if p["id"] == 0 or p["kind"] in ["platz", "ramp"]:
			continue
		var c: Curve3D = p["curve"]
		for q3 in [c.sample_baked(0.0), c.sample_baked(c.get_baked_length())]:
			var best := 1e9
			for o in track["paths"]:
				if o["id"] == p["id"]:
					continue
				best = minf(best, Track._flat(q3 - (o["curve"] as Curve3D).get_closest_point(q3)).length())
			if best > 3.0:
				print("OFFENES ENDE #%d %s %s bei (%.0f, %.0f), %.0f m vom nächsten Weg" % [p["id"], p["kind"], p.get("street_name", ""), q3.x, q3.z, best])
				open += 1
	print("ENDENCHECK %d offene Enden" % open)

