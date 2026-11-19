extends Control
## Werkzeug: Strecke von oben als Plan. Grau Hauptstraße, Farbe je Nebenweg (Gabelung, Gasse, Sackgasse),
## rot Wände, gelb Umfahrbares, grün Rampen, blau Seen, orange Baustellen, weiße Punkte Lampen mit Reichweite.
## godot --path . res://tools/track_map.tscn -- --race=8 --out=/pfad/karte.png [--zoom=d0:d1] [--world]
## --world: Strecke wie in der freien Fahrt (Straßennetz, Querstraßen, Ausfahrten), dazu die Häuser echter Städte

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const Layout := preload("res://scripts/world_layout.gd")
const Streets := preload("res://scripts/street_net.gd")

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
var leak_pts: Array = []  # --leakcheck: Lücken (cyan Ringe)


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
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stitchat="):  # x:z[,x:z...]
			for pt in a.substr(11).split(","):
				var xz := pt.split(":")
				Track.stitch_pts.append(Vector3(float(xz[0]), 0, float(xz[1])))
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
	if OS.get_cmdline_user_args().has("--leakcheck"):
		_leakcheck()
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
				if absf((b - a).cross(e - a).normalized().y) > 0.7:
					continue  # Boden, keine Wand
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
		if DisplayServer.get_name() != "headless":  # ohne Fenster gibt es kein Bild, nur die Prüfungen
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
	for q in leak_pts:
		draw_arc(_px(q), 14.0, 0, TAU, 24, Color(0.2, 1.0, 1.0), 3.0)

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
		var lim: float = float(p["half_w"]) - 0.3  # seit 2.52 bis an den Fahrbahnrand (vorher 70 % der halben Breite)
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
	print("ENDENCHECK startet")
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
	# Ränder (Zaun, Hecke, Mauer): ragt ein Stück (1,5 m nach vorn und hinten) in die Fahrbahn eines Weges?
	var pg := {}
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var d := 0.0
		while d <= L:
			var q3 := c.sample_baked(d)
			var k := Vector2i(floori(q3.x / 10.0), floori(q3.z / 10.0))
			if not pg.has(k):
				pg[k] = []
			pg[k].append([Vector2(q3.x, q3.z), float(p["half_w"]), p])
			d += 1.0
	var nb := 0
	var seen := {}
	print("RANDCHECK prüft %d Randstücke" % Track.border_dbg.size())
	for e in Track.border_dbg:
		var xf: Transform3D = e[1]
		for o in [-1.5, 0.0, 1.5]:
			var q3: Vector3 = xf.origin - xf.basis.z * o  # gekürzte Stücke: Basis längs gestaucht
			var q := Vector2(q3.x, q3.z)
			var k := Vector2i(floori(q.x / 10.0), floori(q.y / 10.0))
			var hit: Dictionary = {}
			var depth := 0.0
			for gx in range(k.x - 2, k.x + 3):
				for gz in range(k.y - 2, k.y + 3):
					for s in pg.get(Vector2i(gx, gz), []):
						var dd: float = s[1] - (s[0] as Vector2).distance_to(q)
						if dd > 0.35 and dd > depth:
							depth = dd
							hit = s[2]
			if not hit.is_empty():
				var key := Vector2i(floori(q.x / 12.0), floori(q.y / 12.0))
				if not seen.has(key):
					seen[key] = true
					var own := []
					var bd := 1e9
					for ow in Track.border_own:
						var dd2: float = Vector2((ow[0] as Vector3).x, (ow[0] as Vector3).z).distance_to(Vector2(xf.origin.x, xf.origin.z))
						if dd2 < bd:
							bd = dd2
							own = ow
					var op: Dictionary = track["paths"][0]
					for pp in track["paths"]:
						if not own.is_empty() and int(pp["id"]) == int(own[1]):
							op = pp
					print("RAND AUF WEG %s %.1f m in #%d %s %s (%.0f, %.0f), gehört zu #%d %s Seite %d bei %.0f m" % [e[0], depth, hit["id"], hit["kind"],
						hit.get("street_name", ""), q.x, q.y, op["id"], op.get("street_name", op["kind"]), int(own[2]) if own else 0, float(own[3]) if own else 0.0])
					nb += 1
				break
	print("RANDCHECK %d Stellen" % nb)



## --leakcheck: kommt man irgendwo von den Straßen weg ins Freie? Raster 0,5 m, Wände sperren. Die Straßenzone reicht je
## Seite genau bis zur Wandlinie (+0,4 m): Fahrbahn, Park-/Grünstreifen, Gehweg. Von der Hauptstraße aus nur innerhalb
## der Zone füllen; jede Zelle außerhalb, die man ohne Wand dazwischen erreicht, ist eine Lücke (je 8 m eine gemeldet).
func _leakcheck() -> void:
	const CS := 0.5
	var r := rect.grow(40.0)
	var W := int(r.size.x / CS) + 1
	var H := int(r.size.y / CS) + 1
	var cell := PackedByteArray()
	cell.resize(W * H)  # Bit 1 Wand, Bit 2 Straßenzone, Bit 4 besucht
	var idx := func(q: Vector2) -> int:
		var x := int((q.x - r.position.x) / CS)
		var y := int((q.y - r.position.y) / CS)
		return -1 if x < 0 or y < 0 or x >= W or y >= H else y * W + x
	var starts := []
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var main: bool = int(p["id"]) == 0
		var d := 0.0
		while d <= L:
			var f := Track.frame_at(c, d)
			var o: Vector3 = f["pos"]
			var rr: Vector3 = f["right"]
			for sd in [-1.0, 1.0]:
				var ext: float = (Track.hw(track, d) + Track.WALK + 2.6 if main else Streets.edge(p, sd) + (3.5 if p["kind"] == "ramp" else 0.0)) + 0.4
				var t := 0.0
				while t <= ext:
					var i: int = idx.call(Vector2(o.x + rr.x * sd * t, o.z + rr.z * sd * t))
					if i >= 0:
						cell[i] |= 2
					t += CS * 0.4
			if main:
				starts.append(Vector2(o.x, o.z))
			d += CS * 0.4
		if p["kind"] == "ramp":
			var f2 := Track.frame_at(c, minf(40.0, L))
			var o2: Vector3 = f2["pos"]
			var r2: Vector3 = f2["right"]
			walls.append([Vector2(o2.x - r2.x * 30.0, o2.z - r2.z * 30.0), Vector2(o2.x + r2.x * 30.0, o2.z + r2.z * 30.0)])
	for w in walls:
		var a: Vector2 = w[0]
		var b: Vector2 = w[1]
		var n := int(ceil(a.distance_to(b) / (CS * 0.4))) + 1
		for k in n + 1:
			var i: int = idx.call(a.lerp(b, float(k) / float(n)))
			if i >= 0:
				cell[i] |= 1
	var queue := PackedInt32Array()
	for q in starts:
		var i: int = idx.call(q)
		if i >= 0 and (cell[i] & 5) == 0:
			cell[i] |= 4
			queue.append(i)
	var head := 0
	var gaps := []
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % W
		var y := i / W
		for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
			var nx: int = x + o[0]
			var ny: int = y + o[1]
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var j := ny * W + nx
			if cell[j] & 5:
				continue
			cell[j] |= 4
			if (cell[j] & 2) == 0:
				# dahinter weiterfüllen (bis 2000 Zellen = 500 m²): ringsum geschlossene Streifen zwischen Zone und Wand sind
				# keine Lücke
				var sub := PackedInt32Array([j])
				var sh := 0
				while sh < sub.size() and sub.size() < 2000:
					var si := sub[sh]
					sh += 1
					var sx := si % W
					var sy := si / W
					for so in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
						var tx: int = sx + so[0]
						var ty: int = sy + so[1]
						if tx < 0 or ty < 0 or tx >= W or ty >= H:
							continue
						var tj := ty * W + tx
						if cell[tj] & 7:
							continue
						cell[tj] |= 4
						sub.append(tj)
				if sub.size() < 2000:
					continue
				var q := Vector2(nx, ny) * CS + r.position
				var dup := false
				for g in gaps:
					if (g as Vector2).distance_to(q) < 8.0:
						dup = true
						break
				if not dup:
					gaps.append(q)
				continue
			queue.append(j)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			var xz := a.substr(8).split(":")
			var c0: int = idx.call(Vector2(float(xz[0]), float(xz[1])))
			var cx0 := c0 % W
			var cy0 := c0 / W
			for yy in range(cy0 - 8, cy0 + 9):
				var row := ""
				for xx in range(cx0 - 12, cx0 + 13):
					var v := cell[yy * W + xx]
					row += "#" if v & 1 else ("o" if (v & 6) == 6 else ("." if v & 2 else ("X" if v & 4 else " ")))
				print("PROBE |" + row + "|")
	var pts := []
	for q in gaps:
		var best := 1e9
		var nm := ""
		for p in track["paths"]:
			var cp := (p["curve"] as Curve3D).get_closest_point(Vector3(q.x, 0, q.y))
			var dd := Vector2(cp.x, cp.z).distance_to(q)
			if dd < best:
				best = dd
				nm = "%s@%.0f" % [p.get("street_name", "") if p.get("street_name", "") != "" else p["kind"], (p["curve"] as Curve3D).get_closest_offset(Vector3(q.x, 0, q.y))]
		var mc: Curve3D = track["paths"][0]["curve"]
		var md := mc.get_closest_offset(Vector3(q.x, 0, q.y))
		var mp := mc.sample_baked(md)
		leak_pts.append(q)
		print("LÜCKE (%.0f, %.0f) %s  [%.1f m von der Mitte der Hauptstraße, hw %.1f]" % [q.x, q.y, nm, Vector2(mp.x, mp.z).distance_to(q), Track.hw(track, md)])
		pts.append("%.0f:%.0f" % [q.x, q.y])
	print("LECKPUNKTE ", ",".join(pts))
	print("NAHTSTELLEN %d geschlossen" % Track.stitch_dbg)
	print("LECKCHECK %d Lücken" % gaps.size())
