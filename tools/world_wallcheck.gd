extends Node
## Werkzeug (seit 2.54): Wände auf Fahrbahnen in der ganzen Welt. Baut jede Stadt und jedes Autobahnstück so, wie es
## in der Welt liegt, sammelt alle Wände (Kollision aus Dreiecken) in Weltkoordinaten und prüft jeden Weg jeder
## Strecke gegen die Wände ALLER Strecken. track_map --wallcheck sieht nur die eigenen Wände einer Strecke; die Wand,
## die 2.53 quer auf der Ausfahrt von Frankfurt stand (Startpunkt eines neuen Spiels), kam aber vom Autobahnstück.
## godot --headless --path . res://tools/world_wallcheck.tscn [-- --only=Name] [--eigene]
##   --only=Name   nur Strecken, deren Name das enthält (Wände aller Strecken in der Nähe zählen trotzdem nicht mit)
##   --eigene      auch Wände der eigenen Strecke melden (sonst nur fremde)

const Layout := preload("res://scripts/world_layout.gd")
const Track := preload("res://scripts/track_builder.gd")

const CELL := 10.0
var walls := {}  # Vector2i -> [[a2, b2, ylo, yhi, track, body]]
var samples := []  # [pos2, y, lim, track, path-text]


func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		if a.begins_with("--stitchat="):  # x:z  Nähte um diesen Punkt ausgeben (Weltkoordinaten = Autobahnstücke)
			var xz := a.substr(11).split(":")
			Track.stitch_pts = [Vector3(float(xz[0]), 0, float(xz[1]))]
	var own := OS.get_cmdline_user_args().has("--eigene")
	var w := Layout.build()
	var list := []
	for c in w["cities"]:
		list.append([c["race"], c["xf"]])
	for s in w["segments"]:
		list.append([s["race"], Transform3D.IDENTITY])
	var t0 := Time.get_ticks_msec()
	for it in list:
		var race: Dictionary = it[0]
		var xf: Transform3D = it[1]
		var nm := str(race.get("name", "?"))
		if only != "" and not nm.contains(only):
			continue
		var tr := Track.build(race)
		var root: Node3D = tr["node"]
		_collect(root, xf, nm)
		for p in tr["paths"]:
			var c: Curve3D = p["curve"]
			var L := c.get_baked_length()
			var lim: float = float(p["half_w"]) - 0.3
			var txt := "#%d %s %s" % [p["id"], p["kind"], p.get("street_name", "")]
			var d := 3.0
			while d < L - 3.0:
				var q := c.sample_baked(d)
				q.y = Track.elev_at(c, d) if p["id"] == 0 else q.y
				var wq := xf * q
				samples.append([Vector2(wq.x, wq.z), wq.y, lim, nm, txt, d, only == "" or nm.contains(only)])
				d += 2.0
		root.free()
	print("GEBAUT %d Strecken in %.0f s, %d Wege-Punkte" % [list.size(), (Time.get_ticks_msec() - t0) / 1000.0, samples.size()])
	var bad := 0
	var last := {}
	for s in samples:
		if not s[6]:
			continue
		var q: Vector2 = s[0]
		var k := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		var hit = null
		var hd := 1e9
		for gx in range(k.x - 1, k.x + 2):
			for gz in range(k.y - 1, k.y + 2):
				for wl in walls.get(Vector2i(gx, gz), []):
					if wl[4] == s[3] and not own:
						continue
					if own and wl[4] == s[3] and str(s[4]).contains(" main") and str(wl[5]) == "WallsRoad":
						continue  # Mittelstreifen: der Hauptweg zählt hier als eine Fahrbahn über beide Richtungen
					if float(wl[3]) < float(s[1]) + 0.3 or float(wl[2]) > float(s[1]) + 1.5:
						continue  # über oder unter der Fahrbahn (Brücke, Tunnel)
					var dd := Geometry2D.get_closest_point_to_segment(q, wl[0], wl[1]).distance_to(q)
					if dd < float(s[2]) and dd < hd:
						hit = wl
						hd = dd
		if hit == null:
			continue
		var key := "%s|%s" % [s[3], s[4]]
		if last.has(key) and absf(float(s[5]) - float(last[key])) < 15.0:
			continue
		last[key] = s[5]
		bad += 1
		print("WELTWAND %s %s bei %.0f m (%.0f, %.0f): Wand von %s/%s, %.1f m von der Mitte (halbe Breite %.1f)" % [s[3], s[4], s[5], q.x, q.y, hit[4], hit[5], hd, float(s[2]) + 0.3])
	print("WELTWANDCHECK %d Stellen" % bad)
	get_tree().quit()


func _collect(n: Node, xf: Transform3D, nm: String) -> void:
	for c in n.get_children():
		var cx := xf * (c as Node3D).transform if c is Node3D else xf
		if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
			var body := str(n.name)
			if body.begins_with("WallsRamp"):
				continue  # Rückseite der Rampe am Bahnübergang: gewollt
			var f: PackedVector3Array = ((c as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
			for k in range(0, f.size() - 2, 3):
				var v := [cx * f[k], cx * f[k + 1], cx * f[k + 2]]
				var ylo := minf(v[0].y, minf(v[1].y, v[2].y))
				var yhi := maxf(v[0].y, maxf(v[1].y, v[2].y))
				if yhi - ylo < 0.3:
					continue  # liegend (Boden), keine Wand
				for e in 3:
					var a := Vector2(v[e].x, v[e].z)
					var b := Vector2(v[(e + 1) % 3].x, v[(e + 1) % 3].z)
					if a.distance_to(b) < 0.05 or a.distance_to(b) > 80.0:
						continue
					_add([a, b, ylo, yhi, nm, body])
		if c.get_child_count() > 0:
			_collect(c, cx, nm)


func _add(wl: Array) -> void:
	var a: Vector2 = wl[0]
	var b: Vector2 = wl[1]
	var lo := a.min(b)
	var hi := a.max(b)
	for gx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
		for gz in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			var k := Vector2i(gx, gz)
			if not walls.has(k):
				walls[k] = []
			walls[k].append(wl)
