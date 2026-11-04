extends Node
## Werkzeug: prüft alle Strecken auf Baufehler. Zu enge Kurven (Radius kleiner als halbe Breite plus Gehweg: dort
## überschneiden sich Fahrbahnrand und Wände) und Wände, die in eine Fahrbahn ragen (unsichtbare Hindernisse).
## Mit --ghosts zusätzlich: sichtbare Dinge auf Fahrbahn und Gehweg ohne Kollision (man fährt hindurch); braucht
## --nobatch, damit die Einzelteile noch einzeln da sind.
## Mit --buildings: Häuser, die in Fahrbahn, Gehweg, Nebenstraßen, Flüsse, Seen, Bahngelände, Wahrzeichen oder
## ineinander ragen.
## godot --path . res://tools/track_check.tscn [-- --race=8] [--ghosts --nobatch] [--buildings]

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")


const City := preload("res://scripts/city_builder.gd")


func _ready() -> void:
	var ghosts := OS.get_cmdline_user_args().has("--ghosts")
	var houses := OS.get_cmdline_user_args().has("--buildings")
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			only = int(a.substr(7))
	var bad := 0
	for i in Catalog.RACES.size():
		if only >= 0 and i != only:
			continue
		var r: Dictionary = Catalog.RACES[i]
		if houses:
			Track.box_log = []
		var t0 := Time.get_ticks_msec()
		var t := Track.build(r)
		var build_ms := Time.get_ticks_msec() - t0
		add_child(t["node"])
		var msgs := []
		for p in t["paths"]:
			msgs.append_array(_tight(t, p))
		msgs.append_array(_walls_in_road(t))
		if houses:
			msgs.append_array(_houses(t, Track.box_log))
			Track.box_log = null
		if ghosts:
			await get_tree().physics_frame
			await get_tree().physics_frame
			msgs.append_array(_ghosts(t))
		print("%2d %s (%d ms): %s" % [i, r["name"], build_ms, "ok" if msgs.is_empty() else "\n     " + "\n     ".join(msgs)])
		bad += 1 if not msgs.is_empty() else 0
		t["node"].free()
	print("FERTIG: %d Strecken mit Befund" % bad)
	get_tree().quit()


## Kurvenradius aus drei Punkten im Abstand 6 m; zu eng, wenn kleiner als der Abstand der inneren Wand
func _tight(t: Dictionary, p: Dictionary) -> Array:
	var c: Curve3D = p["curve"]
	var L := c.get_baked_length()
	var out := []
	var d := 6.0
	var run := []
	while d < L - 6.0:
		var a := c.sample_baked(d - 6.0)
		var b := c.sample_baked(d)
		var e := c.sample_baked(d + 6.0)
		var rad := _radius(Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(e.x, e.z))
		var need: float = (Track.hw(t, d) if p["id"] == 0 else p["half_w"]) + (1.5 if t["type"] == "drift" else 3.0)
		if rad < need:
			if run.is_empty() or d - run[-1][0] > 10.0:
				run.append([d, rad])
			elif rad < run[-1][1]:
				run[-1] = [run[-1][0], rad]
		d += 2.0
	for x in run:
		out.append("%s #%d: Kurve bei %.0f m Radius %.1f m (zu eng)" % [p["kind"], p["id"], x[0], x[1]])
	return out


func _radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ca := c.distance_to(a)
	var area := absf((b - a).cross(c - a)) / 2.0
	return 1e9 if area < 1e-4 else ab * bc * ca / (4.0 * area)


## Wandflächen (Kollision der Randmauern) mitten in einer Fahrbahn
func _walls_in_road(t: Dictionary) -> Array:
	var hits := {}
	var stack: Array = [t["node"]]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is CollisionShape3D and n.get_parent() is StaticBody3D and n.shape is ConcavePolygonShape3D):
			continue
		var f: PackedVector3Array = (n.shape as ConcavePolygonShape3D).get_faces()
		var xf: Transform3D = (n as Node3D).global_transform
		for i in range(0, f.size(), 3):
			var m: Vector3 = xf * ((f[i] + f[i + 1] + f[i + 2]) / 3.0)
			if m.y > 3.0:
				continue  # Tunneldecken, Brückengeländer oben
			var loc := Track.locate(t, m)
			var p: Dictionary = loc["path"]
			var half: float = (Track.hw(t, loc["d"]) if p["id"] == 0 else p["half_w"]) - 1.0
			var med: float = Track.median_at(t, loc["d"]) + 0.6 if p["id"] == 0 else 0.0  # Mittelstreifen-Mauer gehört dahin
			if absf(loc["lat"]) < half and absf(loc["lat"]) > med:
				var key := "%s #%d bei %d m" % [p["kind"], p["id"], int(loc["d"] / 10.0) * 10]
				hits[key] = hits.get(key, 0) + 1
	var out := []
	for k in hits:
		out.append("Wand in der Fahrbahn: %s (%d Flächen)" % [k, hits[k]])
	return out


## Sichtbares über 0,6 m Höhe, unten auf Fahrbahn- oder Gehweghöhe, im erreichbaren Bereich (bis zur Randmauer),
## das weder selbst ein Körper ist noch von einer Kollisionsform abgedeckt wird
func _ghosts(t: Dictionary) -> Array:
	var space := get_viewport().find_world_3d().direct_space_state
	var found := {}
	var stack: Array = [t["node"]]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is PhysicsBody3D:
			continue  # Umfahrbares, Züge: haben eigene Körper
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D or n is MultiMeshInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var boxes := []  # [AABB in Welt, Name]
		if n is MeshInstance3D:
			boxes.append([(n as MeshInstance3D).global_transform * (n as MeshInstance3D).get_aabb(), (n as MeshInstance3D).mesh.get_class()])
		else:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			for k in mm.instance_count:
				boxes.append([(n as Node3D).global_transform * mm.get_instance_transform(k) * mm.mesh.get_aabb(), "Multi:" + mm.mesh.get_class()])
		for bx in boxes:
			_ghost_test(t, space, bx[0], "%s/%s" % [n.get_parent().name.left(18), bx[1]], found)
	var out := []
	for k in found:
		out.append("ohne Kollision: %s bei %s" % [k, found[k].slice(0, 6)])
	return out


func _ghost_test(t: Dictionary, space: PhysicsDirectSpaceState3D, bb: AABB, label: String, found: Dictionary) -> void:
	if bb.size.y < 0.6 or bb.position.y > 1.2 or bb.size.x > 30.0 or bb.size.z > 30.0:
		return
	var c := bb.get_center()
	var loc := Track.locate(t, Vector3(c.x, 0.0, c.z))
	var p: Dictionary = loc["path"]
	var reach: float = (Track.hw(t, loc["d"]) + Track.WALK if p["id"] == 0 else p["half_w"] + (3.0 if p["kind"] == "fork" else 0.0)) + 0.2
	if absf(loc["lat"]) > reach:
		return
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(bb.size.x * 0.8, 0.1), 0.6, maxf(bb.size.z * 0.8, 0.1))
	q.shape = box
	q.transform = Transform3D(Basis(), Vector3(c.x, bb.position.y + 0.6, c.z))
	q.collision_mask = 0xFFFFFFFF
	if space.intersect_shape(q, 1).is_empty():
		var what := "%s %.1fx%.1fx%.1f" % [label, bb.size.x, bb.size.y, bb.size.z]
		if not found.has(what):
			found[what] = []
		found[what].append(int(loc["d"]))


## Häuserquader prüfen: Grundriss (4 Ecken, Kantenmitten) gegen Straßen, Wasser, Gleise; Grundrisse gegeneinander
func _houses(t: Dictionary, log: Array) -> Array:
	var out := []
	var counts := {}
	var examples := {}
	var add := func(kind: String, d: float, info: String) -> void:
		counts[kind] = counts.get(kind, 0) + 1
		if not examples.has(kind):
			examples[kind] = []
		if examples[kind].size() < 6:
			examples[kind].append("%d m %s" % [int(d), info])
	var curve: Curve3D = t["curve"]
	var feet := []  # je Quader: [Mitte 2D, Achse u, Achse v, halbe Länge u, halbe Länge v, Haus-Nr., Art, Höhe unten]
	for e in log:
		var xf: Transform3D = e[0]
		var bu: Vector3 = xf.basis.x
		var bv: Vector3 = xf.basis.z
		var u := Vector2(bu.x, bu.z)
		var v := Vector2(bv.x, bv.z)
		feet.append([Vector2(xf.origin.x, xf.origin.z), u.normalized(), v.normalized(), u.length() / 2.0, v.length() / 2.0,
			e[1], e[2], xf.origin.y - xf.basis.y.length() / 2.0])
	var seen := {}
	for f in feet:
		if seen.has(f[5]):
			continue  # Sockel, Turm, Krone eines Hauses: Grundriss des größten reicht (erster Quader)
		seen[f[5]] = true
		var c: Vector2 = f[0]
		var worst := {}
		for su in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for sv in [-1.0, -0.5, 0.0, 0.5, 1.0]:
				if absf(su) < 1.0 and absf(sv) < 1.0:
					continue  # nur der Rand
				var q2: Vector2 = c + f[1] * f[3] * su + f[2] * f[4] * sv
				var q := Vector3(q2.x, 0, q2.y)
				var mc := Track._main_clearance(t, q)
				if mc < Track.WALK - 0.3:
					var kind := "Fahrbahn" if mc < 0.0 else "Gehweg"
					worst[kind] = minf(worst.get(kind, 99.0), mc)
				for p in t["paths"]:
					if p["id"] == 0:
						continue
					var need: float = {"fork": 3.0, "spur": 1.0}.get(p["kind"], 0.3)
					var bc: float = Track._flat(q - (p["curve"] as Curve3D).get_closest_point(q)).length() - p["half_w"]
					if bc < need - 0.3:
						worst["Nebenstraße " + p["kind"]] = minf(worst.get("Nebenstraße " + p["kind"], 99.0), bc)
				if Track._in_river(t, q, 0.0):
					worst["Fluss"] = minf(worst.get("Fluss", 99.0), Track._river_clearance(t, q))
				if Track._in_lake(t, q, 0.0):
					worst["See"] = 0.0
					if OS.get_cmdline_user_args().has("--verbose-lake"):
						print("  See: Haus %d Mitte %s Punkt %s halb %.1f/%.1f y=%.1f" % [f[5], c, q, f[3], f[4], f[7]])
				if Track._rail_clearance(t, q) < 0.0:
					worst["Bahn"] = minf(worst.get("Bahn", 99.0), Track._rail_clearance(t, q))
		var d := curve.get_closest_offset(Vector3(c.x, 0, c.y))
		for k in worst:
			add.call("%s im %s" % [f[6], k], d, "%.1f" % worst[k])
	# Grundrisse gegeneinander (verschiedene Häuser): Überlappung in m entlang der trennschwächsten Achse
	var firsts := {}
	for f in feet:
		if not firsts.has(f[5]):
			firsts[f[5]] = f
	feet = firsts.values()
	var grid := {}
	for i in feet.size():
		var key := Vector2i(floori(feet[i][0].x / 40.0), floori(feet[i][0].y / 40.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	for i in feet.size():
		var a: Array = feet[i]
		var key := Vector2i(floori(a[0].x / 40.0), floori(a[0].y / 40.0))
		for gx in range(key.x - 2, key.x + 3):
			for gz in range(key.y - 2, key.y + 3):
				for j in grid.get(Vector2i(gx, gz), []):
					if j <= i or feet[j][5] == a[5]:
						continue
					var pen := _obb_pen(a, feet[j])
					# echte Grundrisse (OSM) dürfen sich bis 2,5 m überlappen (Winkelbauten im Häuserblock, siehe Track)
					if pen > (2.6 if a[6] == "osm" and feet[j][6] == "osm" else 0.5):
						add.call("Haus in Haus (%s/%s)" % [a[6], feet[j][6]], curve.get_closest_offset(Vector3(a[0].x, 0, a[0].y)), "%.1f m" % pen)
	# Hochbahn-Endblöcke (Häuser über dem Gehweg, in die die Bahn hineinfährt)
	for eb in t.get("el_blocks", []):
		for f in feet:
			var pen := _obb_pen(eb, f)
			if pen > 0.5:
				add.call("Haus in Hochbahn-Endblock", curve.get_closest_offset(Vector3(eb[0].x, 0, eb[0].y)), "%.1f m" % pen)
	# Wahrzeichen der Orts-Strecken: Grundriss aus City.INFO
	for lm in (t["node"] as Node3D).get_children():
		if not City.INFO.has(lm.name) or City.INFO[lm.name].get("hill", false) or lm.name in ["mainbruecke", "oberbaumbruecke", "fernsehturm"]:
			continue
		var info: Dictionary = City.INFO[lm.name]
		var b: Basis = (lm as Node3D).global_basis
		var lu := Vector2(b.x.x, b.x.z).normalized()
		var lv := Vector2(b.z.x, b.z.z).normalized()
		var lf := [Vector2(lm.global_position.x, lm.global_position.z), lu, lv, info["hl"] * b.x.length(), info["hd"] * b.z.length(), -1, "wz", 0.0]
		for f in feet:
			var pen := _obb_pen(lf, f)
			if pen > 1.0:
				add.call("Haus in Wahrzeichen %s" % lm.name, curve.get_closest_offset(lm.global_position), "%.1f m" % pen)
	for k in counts:
		out.append("%s: %d  %s" % [k, counts[k], examples[k]])
	return out


## Eindringtiefe zweier gedrehter Rechtecke (Trennachsen-Test), 0 wenn getrennt
func _obb_pen(a: Array, b: Array) -> float:
	var best := 1e9
	for ax in [a[1], a[2], b[1], b[2]]:
		var ra: float = a[3] * absf(ax.dot(a[1])) + a[4] * absf(ax.dot(a[2]))
		var rb: float = b[3] * absf(ax.dot(b[1])) + b[4] * absf(ax.dot(b[2]))
		var dist: float = absf((b[0] - a[0]).dot(ax))
		var pen: float = ra + rb - dist
		if pen <= 0.0:
			return 0.0
		best = minf(best, pen)
	return best
