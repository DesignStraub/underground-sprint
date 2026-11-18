extends Node
## Werkzeug: plant die Open World (scripts/world_layout.gd), gibt die Lage aus und zeichnet eine Draufsicht
## (Ring, Auffahrten, alle Wege jeder Stadt) als PNG.
## godot --path . res://tools/world_map.tscn -- --worldlog [--png=/pfad.png]

const Layout := preload("res://scripts/world_layout.gd")
const Track := preload("res://scripts/track_builder.gd")
const Catalog := preload("res://scripts/catalog.gd")


func _ready() -> void:
	var w := Layout.build()
	if OS.get_cmdline_user_args().has("--worldlog"):
		# Auffahrten und Verbindungen (für world.tscn -- --wspawn=rline:j:m)
		for j in w["ramp_lines"].size():
			var rl: PackedVector2Array = w["ramp_lines"][j]
			var L := 0.0
			for k in rl.size() - 1:
				L += rl[k].distance_to(rl[k + 1])
			print("RAMPE %2d  %5.0f m  von (%.0f, %.0f) bis (%.0f, %.0f)" % [j, L, rl[0].x, rl[0].y, rl[rl.size() - 1].x, rl[rl.size() - 1].y])
		# Autobahn-Rennen (seit 2.43): Richtung (Städte rechts), Länge, Start
		var hw: Array = load("res://scripts/highway_race.gd").plan(w)
		for i in hw.size():
			var df: Dictionary = hw[i]
			print("AUTOBAHNRENNEN %d  %-28s %5.0f m  Ring %+d  Start (%.0f, %.0f)" % [i, df["name"], df["length"], df["dirk"],
				(df["start_xf"] as Transform3D).origin.x, (df["start_xf"] as Transform3D).origin.z])
		# Städte (seit 2.42): Rennen, Ort, Stadteingang (Ausfahrt) für --wstart / --wspawn=xy
		for c in w["cities"]:
			var ex: Vector3 = c["exit_world"]
			print("STADT %2d  %-20s Ausfahrt (%.0f, %.1f, %.0f)  Winkel %.3f" % [c["race_index"],
				str(Catalog.RACES[c["race_index"]].get("town", "")), ex.x, ex.y, ex.z, c["phi_w"]])
	if OS.get_cmdline_user_args().has("--hoehen"):
		_probe_heights(w)
	if OS.get_cmdline_user_args().has("--mitte"):
		# Mittelstreifen je Autobahnstück (seit 2.40): Art und Lage (für world.tscn -- --wspawn=seg:ring:stück:meter)
		var cnt := {}
		var per_ring := {}
		for sg in w["segments"]:
			if sg["race"].get("type", "") != "autobahn":
				continue
			var ri: int = sg.get("ring", 0)
			var si: int = per_ring.get(ri, 0)
			per_ring[ri] = si + 1
			var job := Track.begin(sg["race"])
			(job["root"] as Node).free()
			var tr: Dictionary = job["track"]
			var parts := []
			var last := ""
			for md in tr["medians"]:
				var s: String = md.get("style", "gruen")
				if s != last:
					parts.append("%s@%d" % [s, int(md["from"])])
				last = s
			# Anteile auf dem Stück selbst (alle 10 m), "offen" = ohne Mittelstreifen
			var dm := 5.0
			while dm < float(tr["length"]):
				var sm := Track.median_style_at(tr, dm)
				if sm == "":
					sm = "offen"
				cnt[sm] = cnt.get(sm, 0.0) + 0.01
				dm += 10.0
			print("MITTE seg:%d:%d L=%d  %s" % [ri, si, int(tr["length"]), " ".join(parts)])
			var hl := ""
			var dd := 0.0
			while dd < float(tr["length"]):
				hl += "%d " % int(round(Track.elev_at(tr["curve"], dd)))
				dd += 200.0
			print("HOEHE seg:%d:%d alle 200 m: %s" % [ri, si, hl])
			if tr.has("posts") and not (tr["posts"] as Array).is_empty():
				print("BRUECKEN seg:%d:%d Schilderbrücken bei %s" % [ri, si, str((tr["posts"] as Array).map(func(x): return int(x)))])
			for tt in tr["tunnels"]:
				if tt.get("land", false):
					print("TUNNEL seg:%d:%d %s von %d bis %d" % [ri, si, tt["name"], int(tt["from"]), int(tt["to"])])
		print("MITTE Summe (km) ", cnt)
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


## --hoehen: natürliche Geländehöhe (landscape.raw_height) entlang jedes Autobahnstücks, alle 240 m
func _probe_heights(w: Dictionary) -> void:
	var land := preload("res://scripts/landscape.gd").new()
	land.layout = w
	land._hill.seed = 2029
	land._hill.frequency = 1.0 / 1900.0
	land._hill.fractal_octaves = 3
	land._detail.seed = 77
	land._detail.frequency = 1.0 / 420.0
	land._detail.fractal_octaves = 2
	for sg in w["segments"]:
		var r: Dictionary = sg["race"]
		if r.get("type", "") != "autobahn":
			continue
		var pts: Array = r["pts"]
		var line := ""
		var hmax := -1e9
		for k in pts.size():
			var q: Vector3 = pts[k]
			var h: float = land.raw_height(Vector2(q.x, q.z))
			hmax = maxf(hmax, h)
			if k % 3 == 0:
				line += "%d " % int(round(h))
		var seq: Array = r.get("district_seq", [])
		print("SEG ring=%d %-11s land=%d/%d max=%.0f crests=%d via=%d | %s" % [sg.get("ring", 0), r["name"], seq.count("land"),
			seq.size(), hmax, (r.get("crests", []) as Array).size(), (r.get("viaducts", []) as Array).size(), line])
	land.free()


func _dot(img: Image, p: Vector2i, c: Color, r: int) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var q := p + Vector2i(x, y)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				img.set_pixelv(q, c)
