extends Node
## Werkzeug: prüft alle Strecken auf Baufehler. Zu enge Kurven (Radius kleiner als halbe Breite plus Gehweg: dort
## überschneiden sich Fahrbahnrand und Wände) und Wände, die in eine Fahrbahn ragen (unsichtbare Hindernisse).
## godot --path . res://tools/track_check.tscn [-- --race=8]

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")


func _ready() -> void:
	var only := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			only = int(a.substr(7))
	var bad := 0
	for i in Catalog.RACES.size():
		if only >= 0 and i != only:
			continue
		var r: Dictionary = Catalog.RACES[i]
		var t := Track.build(r)
		add_child(t["node"])
		var msgs := []
		for p in t["paths"]:
			msgs.append_array(_tight(t, p))
		msgs.append_array(_walls_in_road(t))
		print("%2d %s: %s" % [i, r["name"], "ok" if msgs.is_empty() else "\n     " + "\n     ".join(msgs)])
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
