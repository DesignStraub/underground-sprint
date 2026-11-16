extends Node3D
## Werkzeug: rendert alle Autos schräg von vorn und schräg von hinten (Karosserie, Radkästen, Neon prüfen).
##   Godot --path . res://tools/car_shots.tscn -- --out=/pfad/prefix [--cars=kaizen,hachi] [--stock] (ab Werk, ohne Tuning)
##   --cfgs="rims:4,rimsize:9;rims:5"  mehrere Ausstattungen nacheinander (Dateiname mit laufender Nummer)
##   --views=seite,felge  nur diese Ansichten (Liste unten in all_views)
##   --label   Auto und Ausstattung oben links ins Bild schreiben (Kontaktbögen)
##   --bench   Kosten der Räder messen statt Bilder: Garage (ein Auto unverschmolzen wie garage._show_car) und Rennen
##             (fünf verschmolzene Autos mit Fernansicht in 6 bis 150 m), Ausgabe "WBENCH ..."

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")

var out := "/tmp/car"
var cars: Array = Catalog.CAR_ORDER
var stock := false
var lights := false  # --lights: mit Scheinwerfern und Lichtteppichen auf dem Boden
var cfgs: Array = []  # --cfgs: je Eintrag ein Bild je Ansicht, Dateiname mit laufender Nummer
var views: Array = []
var spin_v := 0.0  # --spin=m/s: Räder vor dem Bild so lange drehen lassen (Unschärfe testen)
var label_on := false
var bench := false
var _label: Label


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cars="):
			cars = Array(a.substr(7).split(","))
		elif a == "--stock":
			stock = true
		elif a == "--lights":
			lights = true
		elif a == "--label":
			label_on = true
		elif a == "--bench":
			bench = true
		elif a == "--measure":
			_measure()
			get_tree().quit()
			return
		elif a == "--checkfit":
			_checkfit()
			get_tree().quit()
			return
		elif a == "--migtest":
			_migtest()
			get_tree().quit()
			return
		elif a == "--cachetest":
			await _cachetest()
			get_tree().quit()
			return
		elif a == "--rivalsizes":
			_rivalsizes()
			get_tree().quit()
			return
		elif a == "--tricount":
			# je Felgen-Bauart: Dreiecke und Flächen eines Rads in der Nahansicht (Rennen, verschmolzen), ohne Bild
			for r in Catalog.PARTS["rims"]["options"].size():
				var acc := {"meshes": 0, "surfaces": 0, "tris": 0}
				var gacc := {"meshes": 0, "surfaces": 0, "tris": 0}
				for id in ["kaizen", "vortex"]:
					var car := Builder.build(id, {"rims": r}, true, true, true)
					for sp in car.get_meta("spinners"):
						_count(sp, acc)
					car.free()
					var gcar := Builder.build(id, {"rims": r}, false, false, false)
					for sp in gcar.get_meta("spinners"):
						_count((sp as Node3D).get_parent(), gacc)
					gcar.free()
				print("TRI rims:%d %s je Rad: Rennen %d Dreiecke %.1f Flächen, Garage %.1f Meshes %.1f Flächen" % [r,
					Catalog.PARTS["rims"]["options"][r]["style"], acc["tris"] / 8, acc["surfaces"] / 8.0, gacc["meshes"] / 8.0, gacc["surfaces"] / 8.0])
			get_tree().quit()
			return
		elif a.begins_with("--rivals="):
			_rivals(int(a.substr(9)))
			get_tree().quit()
			return
		elif a.begins_with("--cfgs="):
			# mehrere Ausstattungen nacheinander: "rims:4,spoiler:5;rims:5" (fehlende Kategorien = Serie)
			for one in a.substr(7).split(";"):
				var c := {}
				for kv in one.split(","):
					if ":" in kv:
						c[kv.get_slice(":", 0)] = int(kv.get_slice(":", 1))
				cfgs.append(c)
		elif a.begins_with("--spin="):
			spin_v = float(a.substr(7))
		elif a.begins_with("--views="):
			views = Array(a.substr(8).split(","))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Builder.mat(Color(0.12, 0.12, 0.14), 0.0, 0.5)
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.make_current()
	if label_on:
		var cl := CanvasLayer.new()
		add_child(cl)
		_label = Label.new()
		_label.position = Vector2(8, 6)
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		_label.add_theme_constant_override("shadow_offset_x", 1)
		_label.add_theme_constant_override("shadow_offset_y", 1)
		cl.add_child(_label)
	if bench:
		await _bench(cam)
		get_tree().quit()
		return
	var cfg := {"paint": 5, "rims": 2, "spoiler": 2, "bodykit": 1, "vinyl": 0, "neon": 2, "engine": 0, "nitro": 0}
	if stock:
		cfg = {}
		for cat in Catalog.PART_ORDER:
			cfg[cat] = 0
	# rad/felge/reifen: Nahaufnahmen des rechten Vorderrads; stand: genau von vorn auf Radhöhe (Sitz der Räder unter den
	# Kotflügeln); heckrad: rechtes Hinterrad schräg von hinten
	var all_views := [["vorn", Vector3(4.2, 1.6, -5.2)], ["hinten", Vector3(-4.0, 1.5, 5.4)], ["seite", Vector3(8.5, 0.8, 0.0)],
		["jagd", Vector3(0.0, 1.75, 6.2)], ["front", Vector3(0.0, 1.2, -6.0)], ["rad", Vector3(2.6, 0.5, -2.6)], ["felge", Vector3.ZERO], ["oben", Vector3(3.0, 4.2, -4.4)],
		["heck", Vector3.ZERO], ["bug", Vector3.ZERO], ["hoch", Vector3(0.5, 18.0, -2.0)], ["reifen", Vector3.ZERO], ["stand", Vector3.ZERO],
		["heckrad", Vector3.ZERO], ["links", Vector3.ZERO], ["draufsicht", Vector3.ZERO], ["frontal", Vector3.ZERO], ["rueck", Vector3.ZERO], ["verfolger", Vector3.ZERO], ["verfolger12", Vector3.ZERO], ["verfolger22", Vector3.ZERO], ["garA", Vector3.ZERO], ["garB", Vector3.ZERO], ["garC", Vector3.ZERO], ["garD", Vector3.ZERO]]
	if cfgs.is_empty():
		cfgs = [cfg]
	for id in cars:
		for ci in cfgs.size():
			var car := Builder.build(id, cfgs[ci], lights)
			add_child(car)
			var rs := Builder.rim_spec(id, cfgs[ci])
			for view in all_views:
				if (views.is_empty() and (view[0] in ["rad", "felge", "oben", "heck", "bug", "reifen", "stand", "heckrad", "links", "draufsicht", "frontal",
						"verfolger", "verfolger12", "verfolger22", "rueck"] \
						or view[0].begins_with("gar"))) \
						or (not views.is_empty() and not view[0] in views):
					continue
				cam.position = view[1]
				cam.fov = 32.0
				var look := Vector3(0, 0.55, 0)
				var Lh: float = Catalog.CARS[id]["length"] / 2.0
				var Sh: Dictionary = Builder.SHAPES.get(id, {})
				# Mitte des rechten Vorderrads, wie gebaut (Spur, Radgröße und Höherlegung je Ausstattung)
				var wc := Vector3(Catalog.CARS[id]["width"] / 2.0 - 0.1, Builder.wheel_r(Sh), -Lh + Builder.axle(Sh))
				var piv: Array = car.get_meta("front_pivots", [])
				for p in piv:
					if (p as Node3D).position.x > 0.0:
						wc = (p as Node3D).position
				if view[0] == "heck":
					look = Vector3(0, 0.42, Lh - 0.3)
					cam.position = Vector3(-1.9, 1.05, Lh + 2.9)
				elif view[0] == "bug":
					look = Vector3(0, 0.45, -Lh + 0.5)
					cam.position = Vector3(2.0, 1.3, -Lh - 2.9)
				if view[0] == "felge":
					# Felge fast von der Seite, nah
					look = wc + Vector3(0.1, 0.0, 0.0)
					cam.position = look + Vector3(1.05, 0.08, -0.32)
					cam.fov = 30.0
				if view[0] == "rad":
					# vorderes rechtes Rad, schräg von vorn
					look = wc + Vector3(0.1, 0.0, 0.0)
					cam.position = look + Vector3(1.25, 0.12, -0.55)
				if view[0] == "reifen":
					# Reifen schräg von vorn unten: Lauffläche, Schulter und Flanke
					look = wc + Vector3(0.05, -0.05, 0.0)
					cam.position = look + Vector3(0.75, 0.05, -0.95)
					cam.fov = 30.0
				if view[0] == "stand":
					# genau von vorn auf Radhöhe, eng: wie weit die Räder unter den Kotflügeln stehen
					look = Vector3(0.0, 0.5, -Lh + 0.8)
					cam.position = Vector3(0.0, 0.48, -Lh - 5.0)
					cam.fov = 15.0
				# Breiten vergleichen: senkrecht von oben bzw. genau von vorn, orthogonal (alle Autos im gleichen Maßstab, 1 m
				# Raster am Boden fehlt, der Maßstab steht im Bild: Bildhöhe 5 m bzw. 2,4 m)
				cam.projection = Camera3D.PROJECTION_PERSPECTIVE
				if view[0] == "draufsicht":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 5.0
					cam.position = Vector3(0.0, 12.0, 0.0)
					look = Vector3(0.0, 0.0, -0.001)
				if view[0] == "rueck":
					# genau von hinten, orthogonal: stehen Flügel, Endplatten oder Räder über die Karosserie?
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 1.9
					cam.position = Vector3(0.0, 0.8, Lh + 6.0)
					look = Vector3(0.0, 0.8, 0.0)
				if view[0] == "frontal":
					cam.projection = Camera3D.PROJECTION_ORTHOGONAL
					cam.size = 1.7
					cam.position = Vector3(0.0, 0.7, -Lh - 6.0)
					look = Vector3(0.0, 0.7, 0.0)
				if view[0].begins_with("verfolger"):
					# wie die Verfolgerkamera im Rennen (player_car.CHASE[0], im Stand): 4,6 m hinter, 1,95 m über dem Auto,
					# Blick auf 1 m Höhe 7,5 m vor das Auto, Sichtfeld 72°. verfolger12/22: in der Kurve hängt sie um so viel Grad
					# nach (das Auto dreht sich gegen die Kamera)
					var yaw := deg_to_rad(float(view[0].substr(9))) if view[0].length() > 9 else 0.0
					cam.position = Basis(Vector3.UP, yaw) * Vector3(0.0, 1.95, 4.6)
					look = Basis(Vector3.UP, yaw) * Vector3(0.0, 1.0, -7.5)
					cam.fov = 72.0
				if view[0] == "links":
					# linkes Vorderrad schräg von vorn (gespiegelter Reifen: Schrift und Felgenschutz außen?)
					look = Vector3(-wc.x - 0.05, wc.y, wc.z)
					cam.position = look + Vector3(-1.05, 0.1, -0.6)
					cam.fov = 30.0
				if view[0] == "heckrad":
					var rc := Vector3(wc.x, wc.y, Lh - Builder.axle(Sh))
					for p in car.get_meta("spinners", []):
						var pp: Node3D = (p as Node3D).get_parent()
						if pp.position.x > 0.0 and pp.position.z > 0.0:
							rc = pp.position
					look = rc + Vector3(0.05, 0.0, 0.0)
					cam.position = look + Vector3(1.3, 0.25, 0.75)
				if view[0].begins_with("gar"):
					# Kamerapunkte der Garage zum Ausprobieren (fov 50, Leiste unten: Bild etwas nach oben versetzt)
					var W2: float = Catalog.CARS[id]["width"] / 2.0
					var fz: float = -(Lh - Builder.axle(Sh))
					var cands := {"garA": [Vector3(W2 + 0.6, 0.4, fz - 2.0), Vector3(W2 - 0.05, 0.34, fz)],
						"garB": [Vector3(W2 + 0.45, 0.33, fz - 1.6), Vector3(W2 - 0.06, 0.32, fz + 0.1)],
						"garC": [Vector3(W2 + 0.6, 0.4, fz + 2.2), Vector3(W2 - 0.05, 0.34, fz)],
						"garD": [Vector3(W2 + 0.6, 0.4, -fz + 2.0), Vector3(W2 - 0.05, 0.34, -fz)]}
					cam.position = cands[view[0]][0]
					look = cands[view[0]][1]
					cam.fov = 50.0
					cam.v_offset = -0.1 * cam.position.distance_to(look)
				else:
					cam.v_offset = 0.0
				cam.look_at(look)
				if _label:
					var ctext := []
					for k in cfgs[ci]:
						if int(cfgs[ci][k]) != 0:
							ctext.append("%s:%d" % [k, cfgs[ci][k]])
					_label.text = "%s  %s  %d\" %s%s" % [id, " ".join(ctext), rs["inch"], rs.get("tire", ""),
						("  Spur %s" % rs["spur_name"]) if rs.has("spur_name") else ""]
				for i in 8:
					if spin_v != 0.0:
						Builder.animate(car, spin_v, 0.0, 0.0, 0.0, false, 1.0 / 60.0)
					await RenderingServer.frame_post_draw
				var tag: String = id if cfgs.size() == 1 else "%s_%02d" % [id, ci]
				get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [out, tag, view[0]])
			car.queue_free()
			await get_tree().process_frame
	get_tree().quit()


## --measure: Maße je Auto wie gebaut (Serie): Breite der Haut (größte halbe Breite der Querschnitte, ohne Spiegel),
## Spur (Radmitte), Außenkante Reifen, Radstand, Dachhöhe. Zum Vergleich mit den echten Vorbildern.
func _measure() -> void:
	print("MEASURE id L W_cat body_w(max) body_w(vorn) body_w(hinten) spur_aussen radstand dach rad_r")
	for id in cars:
		var S: Dictionary = Builder.SHAPES.get(id, Builder.SHAPES["kaizen"])
		var spec: Dictionary = Catalog.CARS[id]
		var L: float = spec["length"]
		var W: float = spec["width"]
		var mx := 0.0
		var mf := 0.0
		var mr := 0.0
		for i in 401:
			var t := i / 400.0
			var p: PackedVector2Array = Builder._section(S, t, W, L, 0.0)["p"]
			var x := 0.0
			for q in p:
				x = maxf(x, q.x)
			mx = maxf(mx, x)
			if t < 0.5:
				mf = maxf(mf, x)
			else:
				mr = maxf(mr, x)
		var car := Builder.build(id, {}, false, false, false)
		var out_x := 0.0
		for sp in car.get_meta("spinners"):
			var pv: Node3D = (sp as Node3D).get_parent()
			var aabb := AABB()
			var first := true
			for c in (sp as Node3D).get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).visible and (c as MeshInstance3D).mesh:
					var bb: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
					aabb = bb if first else aabb.merge(bb)
					first = false
			out_x = maxf(out_x, pv.position.x + aabb.end.x * pv.scale.x)
		print("MEASURE %s %.2f %.2f %.3f %.3f %.3f %.3f %.3f %.2f %.3f" % [id, L, W, mx * 2.0, mf * 2.0, mr * 2.0, out_x * 2.0,
			L - 2.0 * Builder.axle(S), S["roof"], car.get_meta("wheel_r")])
		car.free()


## --checkfit (headless): Sitz der Räder für alle Autos, Zoll-Größen, Spur, Bodykit und Fahrwerk nachrechnen (Radlauf unter
## der Gürtellinie, Reifen sticht nicht sichtbar durch den Kotflügel, Sattel hinter den Speichen und im Bett), dazu jedes
## Auto mit jeder Felge bauen (Skriptfehler). Ausgabe "FIT ..." je Auffälligkeit, am Ende "FIT fertig".
func _checkfit() -> void:
	var bad := 0
	var combos := 0
	var sizes := [0]
	for i in Catalog.PARTS["rimsize"]["options"].size():
		if Catalog.PARTS["rimsize"]["options"][i].has("abs"):
			sizes.append(i)
	var worst := {"belt": 9.0, "clip": -9.0, "cal": 9.0, "barrel": 9.0}
	for id in cars:
		var spec: Dictionary = Catalog.CARS[id]
		var S: Dictionary = Builder.SHAPES.get(id, Builder.SHAPES["kaizen"])
		var L: float = spec["length"]
		var W: float = spec["width"]
		for rs in sizes:
			for sp in (_parts()["spur"]["options"] as Array).size():
				for kit in [0, 2, 6]:
					for sus in Catalog.PARTS["suspension"]["options"].size():
						var cfg := {"rims": 1, "rimsize": rs, "spur": sp, "bodykit": kit, "suspension": sus}
						var fi: Dictionary = _bcall("fit_info", [id, cfg])
						combos += 1
						var flare := Builder.kit_flare(cfg)
						var drop: float = Catalog.part_of(cfg, "suspension")["drop"] + S.get("drop", 0.0)
						var S2 := S.duplicate()
						S2["arch_r"] = fi["arch_r"]
						var R: float = fi["wheel_r"]
						var c: float = fi["camber"]
						var wo: float = float(fi["tire_w"]) / 2.0 + 0.007
						for ax in 2:
							var t := Builder.axle(S) / L if ax == 0 else 1.0 - Builder.axle(S) / L
							var p: PackedVector2Array = Builder._section(S2, t, W, L, flare)["p"]
							# Radlauf oben (Karosserie-Koordinaten) unter der Gürtellinie
							var arch_top: float = Builder.wheel_r(S) + float(fi["arch_r"])
							var room := p[6].y - arch_top
							var room_fac := p[6].y - (Builder.wheel_r(S) * 2.0 + 0.045)
							worst["belt"] = minf(worst["belt"], room)
							if room < minf(0.05, room_fac) - 0.0005:
								bad += 1
								if bad < 60:
									print("FIT belt %s %s Platz %.3f" % [id, str(cfg), room])
							# Außenkante des Reifens rundum (obere Hälfte, mit Sturz) gegen den Radlauf: sichtbar durch das Blech wäre
							# ein Punkt, der über der Radlaufkante liegt und nicht mindestens 1,7 cm innerhalb der Kotflügelkante
							# (dort sitzt die gerollte Kante des Radlaufs)
							var lip: float = p[4].x + (0.045 if S.get("overfenders", false) else 0.0)
							var xc: float = fi["track_f" if ax == 0 else "track_r"]
							var d: float = float(fi["drop"]) + float(fi["camber_lift"]) - float(fi.get("extra_lift", 0.0))
							var ra: float = fi["arch_r"]
							var clip := -9.0
							for k in 37:
								var ph := deg_to_rad(-90.0 + k * 5.0)
								var yr := R * cos(ph)
								var zr := R * sin(ph)
								var x := xc + wo * cos(c) - yr * sin(c)
								var y := d + yr * cos(c)  # über der Mitte des Radlaufs
								var outside := sqrt(zr * zr + y * y) - (ra - 0.002)
								clip = maxf(clip, minf(outside, x - (lip - 0.017)))
							worst["clip"] = maxf(worst["clip"], clip)
							if clip > 0.0:
								bad += 1
								if bad < 60:
									print("FIT clip %s %s Achse %d: %.3f m (Sturz %.1f°, tiefer %.3f statt %.3f)" % [id, str(cfg), ax, clip,
										rad_to_deg(c), fi["drop"], drop])

	# Bremse in der Felge: Sattel hinter den Speichen und unter dem Bett, je Bauart und Größe (Modellmaße aus den Meshes)
	for id in ["chibi", "kaizen", "tengu", "furia"]:
		for r in Catalog.PARTS["rims"]["options"].size():
			for rs in [0, 6, 11, 17]:
				for sp in [0, 3]:
					var cfg := {"rims": r, "rimsize": rs, "spur": sp, "engine": 1}
					var rim := Builder.rim_spec(id, cfg)
					var tw: float = float(rim["tire_w"]) * float(rim["mu"])
					var wm: Array = _bcall("_wheel_mesh", [rim, tw, true, 1])
					var D: Dictionary = _bcall("_wheel_dims", [rim, tw])
					var dr: float = _bcall("_disc_r", [rim, tw, true])
					var mu: float = rim["mu"]
					var xo: float = float(D["x_rf"]) + 0.022 * mu
					var ri := dr - 0.048 * mu
					var ro := dr + 0.013 * mu
					worst["barrel"] = minf(worst["barrel"], float(D["rb"]) - ro)
					if ro > float(D["rb"]) - 0.003:
						bad += 1
						print("FIT barrel %s %s Sattel %.3f Bett %.3f" % [id, str(cfg), ro, D["rb"]])
					var face := (wm[1] as Array).find("face")
					if face < 0:
						continue
					var verts: PackedVector3Array = (wm[0] as ArrayMesh).surface_get_arrays(face)[Mesh.ARRAY_VERTEX]
					var mx := 9.0
					for v in verts:
						var rad := Vector2(v.y, v.z).length()
						# nur Speichen über dem Sattel (oben hinten, Winkel 0,75 rad um +-45°)
						var ang := atan2(v.z, v.y)
						if rad > ri and rad < ro and absf(ang - 0.75) < 0.8:
							mx = minf(mx, v.x)
					worst["cal"] = minf(worst["cal"], mx - xo)
					if mx - xo < 0.002:
						bad += 1
						print("FIT caliper %s %s Speichen %.3f Sattel %.3f" % [id, str(cfg), mx, xo])
	# Horn und Stufenbett: keine Fläche darf nach hinten zeigen (sie fehlte sonst als Streifen); je Bauart, Größe, Spur
	var backs := 0
	var lips := 0
	for id in ["chibi", "hotaru", "kaizen", "tengu", "furia"]:
		for r in Catalog.PARTS["rims"]["options"].size():
			for rs in [0, 6, 8, 10, 12, 14, 17]:
				for sp in [0, 3, 4]:
					var cfg := {"rims": r, "rimsize": rs, "spur": sp}
					var rim := Builder.rim_spec(id, cfg)
					var tw: float = float(rim["tire_w"]) * float(rim["mu"])
					var wm: Array = _bcall("_wheel_mesh", [rim, tw, false, 1])
					var li := (wm[1] as Array).find("lip")
					if li < 0:
						continue
					var arr: Array = (wm[0] as ArrayMesh).surface_get_arrays(li)
					var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					var n := ix.size() if not ix.is_empty() else vv.size()
					lips += 1
					for k in range(0, n, 3):
						var a: Vector3 = vv[ix[k] if not ix.is_empty() else k]
						var b: Vector3 = vv[ix[k + 1] if not ix.is_empty() else k + 1]
						var c: Vector3 = vv[ix[k + 2] if not ix.is_empty() else k + 2]
						var fn := (c - a).cross(b - a)  # Godot: im Uhrzeigersinn ist vorn
						if fn.length() < 1e-9:
							continue
						fn = fn.normalized()
						var rad := Vector2(a.y + b.y + c.y, a.z + b.z + c.z).length() / 3.0
						# nach hinten (-X) und nicht nach außen gekehrt (die Rolle des Horns zeigt oben nach außen)
						if fn.x < -0.3 and Vector2(fn.y, fn.z).dot(Vector2(a.y + b.y + c.y, a.z + b.z + c.z).normalized()) < 0.5 and rad < float(rim["radius"]) - 0.004:
							backs += 1
							bad += 1
							if backs < 10:
								print("FIT rueckseite %s %s r=%.3f" % [id, str(cfg), rad])
							break
	print("FIT Horn/Stufenbett: %d Felgen geprüft, %d mit Rückseiten" % [lips, backs])
	print("FIT Kombinationen %d, schlechtester Platz Gürtel %.3f m, Reifen außen/oben %.3f m, Sattel-Speiche %.3f, Sattel-Bett %.3f" % [
		combos, worst["belt"], worst["clip"], worst["cal"], worst["barrel"]])
	# jedes Auto mit jeder Felge (Größe, Spur, Bodykit durchgewechselt) bauen: Skriptfehler?
	var n := 0
	var t0 := Time.get_ticks_msec()
	for id in cars:
		for r in Catalog.PARTS["rims"]["options"].size():
			var cfg := {"rims": r, "rimsize": sizes[r % sizes.size()], "spur": r % 4, "bodykit": [0, 2, 6][r % 3], "suspension": r % 4,
				"rimcol": r % Catalog.PARTS["rimcol"]["options"].size(), "engine": r % 2}
			var car := Builder.build(id, cfg, false, false, false)
			if car.get_meta("spinners").size() != 4:
				bad += 1
				print("FIT build %s %s: Räder fehlen" % [id, str(cfg)])
			car.free()
			n += 1
	print("FIT %d Autos gebaut in %d ms, Auffälligkeiten %d" % [n, Time.get_ticks_msec() - t0, bad])
	print("FIT fertig")


## --migtest: alte relative Zoll-Angaben (Spielstand bis 2.36) im Speicher umrechnen lassen und mit der alten Rechnung
## vergleichen (schreibt nichts). Ausgabe "MIG ..."
func _migtest() -> void:
	var keep: Dictionary = GameState.looks.duplicate(true)
	var cases := []
	for id in ["kaizen", "chibi", "hotaru", "kumo", "tengu", "kaido"]:
		for r in [0, 1, 7, 12, 20]:
			for v in range(1, 6):
				cases.append([id, r, v])
	var ok := 0
	for cs in cases:
		var id: String = cs[0]
		GameState.looks = {id: {"rims": cs[1], "rimsize": cs[2]}}
		# alte Rechnung (bis 2.36): Werk + Aufschlag, höchstens 4,5 cm Flanke, dazu die relative Angabe
		var S: Dictionary = Builder.SHAPES.get(id, Builder.SHAPES["kaizen"])
		var max_old := floori((Builder.wheel_r(S) - 0.045) / 0.0127)
		var fac: Array = Catalog.FACTORY_RIMS[id]
		var std_old := mini(int(fac[3]) + int(Catalog.PARTS["rims"]["options"][cs[1]].get("plus", 0)), max_old)
		var want := clampi(std_old + int(Catalog.PARTS["rimsize"]["options"][cs[2]]["inch"]), 13, max_old)
		GameState._migrate_rimsize()
		var idx: int = GameState.looks[id]["rimsize"]
		var got := Builder.rim_spec(id, GameState.looks[id])
		if int(got["inch"]) == want and Catalog.PARTS["rimsize"]["options"][idx].has("abs"):
			ok += 1
		else:
			print("MIG %s rims:%d alt:%d -> %d (%s) %d\" statt %d\"" % [id, cs[1], cs[2], idx, Catalog.PARTS["rimsize"]["options"][idx]["name"], got["inch"], want])
	GameState.looks = keep
	print("MIG %d/%d richtig" % [ok, cases.size()])


## Statische Funktion des Builders zur Laufzeit aufrufen (ältere Stände ohne fit_info usw. kompilieren so auch)
static func _bcall(f: String, args: Array):
	var b: GDScript = Builder
	return b.callv(f, args)


## --cachetest: dieselbe Folge von 87 Garagen-Vorschauen (unverschmolzen wie garage._show_car, je Bild gezeichnet und
## wieder freigegeben: Felgen, Zoll, Spur auf zwei Autos) und der Speicher davor und danach (statisch und Grafikpuffer).
## Ausgabe "CACHE ...". Zum Vergleich der Stände (der Rad-Cache wuchs bis 2.37 ohne Grenze).
func _cachetest() -> void:
	var seq := []
	for id in ["kaizen", "vortex"]:
		seq.append([id, {}])
		for r in 25:
			seq.append([id, {"rims": r}])
		for rs in range(6, 18):
			seq.append([id, {"rims": 1, "rimsize": rs}])
		for sp in 5:
			seq.append([id, {"rims": 1, "spur": sp}])
	seq.append(["tengu", {}])
	# einmal vorweg bauen: Shader, Materialien und die Teile der Karosserie liegen dann schon im Speicher
	var warm := Builder.build("kaizen", {}, false, false, false)
	add_child(warm)
	await RenderingServer.frame_post_draw
	warm.queue_free()
	for i in 3:
		await get_tree().process_frame
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var b0 := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	for it in seq:
		var car := Builder.build(it[0], it[1], false, false, false)
		add_child(car)
		await RenderingServer.frame_post_draw
		car.queue_free()
		await get_tree().process_frame
	for i in 3:
		await get_tree().process_frame
	var m1 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var b1 := Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)
	print("CACHE %d Vorschauen: statisch %.1f -> %.1f MB (%+.1f), Grafikpuffer %.1f -> %.1f MB (%+.1f)" % [seq.size(), m0 / 1048576.0,
		m1 / 1048576.0, (m1 - m0) / 1048576.0, b0 / 1048576.0, b1 / 1048576.0, (b1 - b0) / 1048576.0])


## --rivalsizes: Zoll der Gegner nachrechnen (jede Felge mit jedem gewürfelten Zoll-Platz gleich oft, wie randi() % n),
## alte Regel (ausgeblendete Plätze +5, nur Riesenfelgen auf Standard) gegen neue (Builder.rival_rimsize). Ausgabe je Auto:
## Anteil auf der kleinsten Felge (min_in), auf der Standardgröße, mittlere Größe. "RS ..."
func _rivalsizes() -> void:
	var nopt: int = Catalog.PARTS["rimsize"]["options"].size()
	var tot := [0.0, 0.0, 0.0]
	for id in cars:
		var res := []
		for rule in ["alt", "neu"]:
			var at_min := 0
			var at_std := 0
			var sum := 0.0
			var n := 0
			var hist := {}
			for r in Catalog.PARTS["rims"]["options"].size():
				for k in nopt:
					var cfg := {"rims": r, "rimsize": k}
					if rule == "alt":
						while Catalog.PARTS["rimsize"]["options"][cfg["rimsize"]].get("hidden", false):
							cfg["rimsize"] = (cfg["rimsize"] + 5) % nopt
						if float(Builder.rim_spec(id, cfg)["grow"]) > 0.001:
							cfg["rimsize"] = 0
					else:
						cfg["rimsize"] = _bcall("rival_rimsize", [id, cfg])
					var rs := Builder.rim_spec(id, cfg)
					var inch: int = rs["inch"]
					hist[inch] = hist.get(inch, 0) + 1
					at_min += 1 if inch == int(rs["min_in"]) else 0
					at_std += 1 if inch == int(rs["std_in"]) else 0
					sum += inch
					n += 1
			var keys := hist.keys()
			keys.sort()
			res.append("%s: min %2d%% std %2d%% Schnitt %.1f\" [%s]" % [rule, roundi(100.0 * at_min / n), roundi(100.0 * at_std / n), sum / n,
				" ".join(keys.map(func(kk): return "%d:%d" % [kk, roundi(100.0 * hist[kk] / n)]))])
		print("RS %-9s %s | %s" % [id, res[0], res[1]])


## Katalog-Teile zur Laufzeit (ältere Stände ohne "spur" kompilieren so auch: Indizes in Konstanten prüft der Compiler)
static func _parts() -> Dictionary:
	return Catalog.PARTS


## --rivals=<rennen>: Spieler und Gegner wie race.gd sie würfelt (gleiche Zufallsfolge), je Auto die Dreiecke und Flächen
## der Nahansicht (Räder extra), Ausgabe "RIV ...". Zum Vergleich alter und neuer Stand.
func _rivals(ri: int) -> void:
	var race: Dictionary = Catalog.RACES[ri]
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 31 + GameState.wins
	var tier: int = race.get("tier", 1)
	var diff: int = GameState.difficulty
	var pool: Array = Catalog.CAR_ORDER.filter(func(id): return Catalog.CARS[id]["top_speed"] <= [0.0, 61.0, 70.0, 99.0][mini(tier + (1 if diff == 2 else 0), 3)] \
		and not id in Catalog.EXOTICS)
	var list := [[GameState.current_car, GameState.get_config()]]
	for i in 3:
		var id: String = pool[rng.randi() % pool.size()]
		var cfg := {}
		for cat in Catalog.PART_ORDER:
			if cat != "finish" and cat != "spur":
				cfg[cat] = rng.randi() % Catalog.PARTS[cat]["options"].size()
				while Catalog.PARTS[cat]["options"][cfg[cat]].get("hidden", false):
					cfg[cat] = (cfg[cat] + 5) % Catalog.PARTS[cat]["options"].size()
		cfg["finish"] = (int(race["seed"]) + i * 3 + GameState.wins) % Catalog.PARTS["finish"]["options"].size()
		if _parts().has("spur"):
			cfg["spur"] = (int(race["seed"]) * 7 + i * 5 + GameState.wins) % (_parts()["spur"]["options"] as Array).size()
			if float(Builder.rim_spec(id, cfg).get("grow", 0.0)) > 0.001:
				cfg["rimsize"] = 0
		rng.randf_range(-0.025, 0.025)
		list.append([id, cfg])
	var tot := 0
	var wt := 0
	for it in list:
		var car := Builder.build(it[0], it[1], true, true, true)
		var acc := {"meshes": 0, "surfaces": 0, "tris": 0}
		_count(car, acc)
		var wacc := {"meshes": 0, "surfaces": 0, "tris": 0}
		for sp in car.get_meta("spinners"):
			_count((sp as Node3D).get_parent(), wacc)
		var rs := Builder.rim_spec(it[0], it[1])
		print("RIV %s rims:%d (%s) %d\" Nahansicht %d Dreiecke, %d Flächen, davon Räder %d Dreiecke, %d Flächen" % [it[0], int(it[1].get("rims", 0)),
			rs["style"], rs["inch"], acc["tris"], acc["surfaces"], wacc["tris"], wacc["surfaces"]])
		tot += acc["tris"]
		wt += wacc["tris"]
		car.free()
	print("RIV gesamt %d Dreiecke, Räder %d" % [tot, wt])


## Dreiecke einer Fläche (mit oder ohne Index)
static func _tris(mesh: Mesh, si: int) -> int:
	var a := mesh.surface_get_arrays(si)
	if a[Mesh.ARRAY_INDEX] != null:
		return (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## Meshes, Flächen und Dreiecke unter n (sichtbare und unsichtbare getrennt nicht unterschieden), near: nur Nahansicht
static func _count(n: Node, acc: Dictionary, skip_lod := true) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi := c as MeshInstance3D
			if skip_lod and mi.name == "Lod":
				continue
			acc["meshes"] += 1
			acc["surfaces"] += mi.mesh.get_surface_count()
			for si in mi.mesh.get_surface_count():
				acc["tris"] += _tris(mi.mesh, si)
		_count(c, acc, skip_lod)


func _frames(n: int) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	var rs := RenderingServer
	var sum := {"draws": 0.0, "prims": 0.0, "objs": 0.0, "gpu": 0.0, "frame": 0.0}
	for i in 4:
		await RenderingServer.frame_post_draw
	for i in n:
		var t0 := Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		sum["frame"] += (Time.get_ticks_usec() - t0) / 1000.0
		sum["draws"] += rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		sum["prims"] += rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		sum["objs"] += rs.viewport_get_render_info(vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		sum["gpu"] += rs.viewport_get_measured_render_time_gpu(vp)
	for k in sum:
		sum[k] /= float(n)
	return sum


## --bench: Garage (unverschmolzen, Kamera am Vorderrad und schräg von vorn) und Rennen (verschmolzen, LOD)
func _bench(cam: Camera3D) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if cfgs.is_empty():
		cfgs = [{}]
	var bcars: Array = cars if cars != Catalog.CAR_ORDER else ["kaizen", "chibi", "mirai", "vortex", "kagura", "tengu"]
	cam.position = Vector3(4.2, 1.6, -5.2)
	cam.look_at(Vector3(0, 0.55, 0))
	var empty := await _frames(30)
	print("WBENCH leer draws=%.0f prims=%.0f" % [empty["draws"], empty["prims"]])
	for ci in cfgs.size():
		var g_acc := {"build": 0.0, "draws": 0.0, "prims": 0.0, "meshes": 0, "gpu": 0.0, "wheel_meshes": 0, "wheel_tris": 0}
		var r_acc := {"build": 0.0, "wheel_surf": 0, "wheel_tris": 0, "lod_tris": 0, "car_surf": 0}
		for id in bcars:
			# Garage: wie garage._show_car (ohne Scheinwerfer, ohne LOD, ohne Verschmelzen)
			var t0 := Time.get_ticks_usec()
			var car := Builder.build(id, cfgs[ci], false, false, false)
			g_acc["build"] += (Time.get_ticks_usec() - t0) / 1000.0
			add_child(car)
			var acc := {"meshes": 0, "surfaces": 0, "tris": 0}
			_count(car, acc)
			g_acc["meshes"] += acc["meshes"]
			var wacc := {"meshes": 0, "surfaces": 0, "tris": 0}
			for sp in car.get_meta("spinners"):
				_count((sp as Node3D).get_parent(), wacc)
			g_acc["wheel_meshes"] += wacc["meshes"]
			g_acc["wheel_tris"] += wacc["tris"]
			cam.position = Vector3(4.2, 1.6, -5.2)
			cam.look_at(Vector3(0, 0.55, 0))
			var f := await _frames(30)
			g_acc["draws"] += f["draws"] - empty["draws"]
			g_acc["prims"] += f["prims"] - empty["prims"]
			g_acc["gpu"] += f["gpu"]
			car.queue_free()
			await get_tree().process_frame
			# Rennen: verschmolzen mit Fernansicht
			t0 = Time.get_ticks_usec()
			var rcar := Builder.build(id, cfgs[ci], true, true, true)
			r_acc["build"] += (Time.get_ticks_usec() - t0) / 1000.0
			var racc := {"meshes": 0, "surfaces": 0, "tris": 0}
			for sp in rcar.get_meta("spinners"):
				_count(sp, racc)
			r_acc["wheel_surf"] += racc["surfaces"]
			r_acc["wheel_tris"] += racc["tris"]
			var cacc := {"meshes": 0, "surfaces": 0, "tris": 0}
			_count(rcar, cacc)
			r_acc["car_surf"] += cacc["surfaces"]
			var lod := rcar.get_node_or_null("Lod") as MeshInstance3D
			if lod:
				for si in lod.mesh.get_surface_count():
					r_acc["lod_tris"] += _tris(lod.mesh, si)
			rcar.free()
		var n := float(bcars.size())
		print("WBENCH cfg=%s garage: build=%.1fms meshes=%d wheel_meshes=%d (je Rad %d) wheel_tris=%d (je Rad %d) draws=+%.0f prims=+%.0fk gpu=%.2fms" % [
			str(cfgs[ci]), g_acc["build"] / n, g_acc["meshes"] / n, g_acc["wheel_meshes"] / n, g_acc["wheel_meshes"] / n / 4.0,
			g_acc["wheel_tris"] / n, g_acc["wheel_tris"] / n / 4.0, g_acc["draws"] / n, g_acc["prims"] / n / 1000.0, g_acc["gpu"] / n])
		print("WBENCH cfg=%s rennen: build=%.1fms car_surfaces=%d wheel_surfaces=%d (je Rad %.1f) wheel_tris=%d (je Rad %d) lod_tris=%d" % [
			str(cfgs[ci]), r_acc["build"] / n, r_acc["car_surf"] / n, r_acc["wheel_surf"] / n, r_acc["wheel_surf"] / n / 4.0,
			r_acc["wheel_tris"] / n, r_acc["wheel_tris"] / n / 4.0, r_acc["lod_tris"] / n])
	# Rennszene: fünf Autos hintereinander in 6, 12, 25, 60 und 150 m, Kamera wie die Verfolgerkamera
	var placed := []
	var ids := ["kaizen", "mirai", "vortex", "kagura", "tengu"]
	var dists := [6.0, 12.0, 25.0, 60.0, 150.0]
	for i in 5:
		var c := Builder.build(ids[i], cfgs[0], true, true, true)
		add_child(c)
		c.position = Vector3((i % 2) * 2.0 - 1.0, 0.0, -dists[i])
		c.rotation.y = 0.4 * (i - 2)
		placed.append(c)
	cam.position = Vector3(0, 1.6, 0.0)
	cam.look_at(Vector3(0, 0.6, -20.0))
	var rf := await _frames(120)
	print("WBENCH szene cfg=%s draws=%.0f prims=%.0fk objs=%.0f gpu=%.2fms frame=%.2fms" % [str(cfgs[0]), rf["draws"], rf["prims"] / 1000.0, rf["objs"], rf["gpu"], rf["frame"]])
	for c in placed:
		c.queue_free()
