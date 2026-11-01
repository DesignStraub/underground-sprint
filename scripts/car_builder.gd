extends RefCounted
## Baut ein Low-Poly-Auto abhängig von Auto-Typ und Tuning. Die Karosserie ist ein Seitenprofil mit
## Radausschnitten, quer extrudiert (Bug/Heck/Schultern eingezogen); darauf die Kabine. Silhouetten nach
## 2000er-JDM-Vorbild: "hatch" (Fließheck), "coupe" (lange Haube), "sedan" (Stufenheck, hohes Heck).
## Vorne ist -Z. Wichtige Knoten landen als Meta-Daten am Wurzelknoten.

const Catalog := preload("res://scripts/catalog.gd")

const WHEEL_R := 0.33
const CLEARANCE := 0.18


static func build(car_id: String, cfg: Dictionary, headlights := true) -> Node3D:
	var spec: Dictionary = Catalog.CARS[car_id]
	var P: Dictionary = Catalog.PARTS
	var paint_c: Color = P["paint"]["options"][cfg["paint"]]["color"]
	var rim: Dictionary = P["rims"]["options"][cfg["rims"]]
	var kit: int = cfg["bodykit"]
	var L: float = spec["length"]
	var W: float = spec["width"] + (0.12 if kit == 2 else 0.0)
	var H: float = spec["height"]
	var body_top := CLEARANCE + H

	var root := Node3D.new()
	root.name = "Car"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint := mat(paint_c, 0.55, 0.22)
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dark := mat(Color(0.04, 0.04, 0.05), 0.2, 0.6)
	var glass := mat(Color(0.03, 0.05, 0.09), 0.8, 0.08)

	# Karosserie mit Radkästen, darauf die Kabine (Windschutzscheibe und Heckscheibe schräg)
	var style: String = spec.get("style", "coupe")
	var prof := _body_profile(style, W, L, H)
	_add(body, prof["mesh"], paint, Vector3.ZERO)
	var ch: float = spec["cabin_h"]
	var cf: float = prof["cab_front"]
	var cr: float = prof["cab_rear"]
	var cl := cr - cf
	var roof_len: float = cl * (0.42 if style == "coupe" else 0.5)
	var roof_off: float = cl * (0.12 if style == "hatch" else 0.06)  # Dach nach hinten versetzt
	var cab_top := Vector2(W - 0.55, roof_len)
	_add(body, tapered_box(Vector2(W - 0.24, cl), cab_top, ch, roof_off), glass, Vector3(0, body_top - 0.01, (cf + cr) / 2.0))
	_add(body, tapered_box(cab_top + Vector2(0.02, 0.02), cab_top - Vector2(0.06, 0.1), 0.05, 0.0), paint,
		Vector3(0, body_top - 0.01 + ch, (cf + cr) / 2.0 + roof_off))
	if style == "hatch":
		# Fließheck: Heckscheibe läuft bis fast ans Ende, Hutze auf der Haube
		_add(body, tapered_box(Vector2(0.5, 0.35), Vector2(0.36, 0.22), 0.06, 0.04), dark, Vector3(0, body_top - 0.035, cf - 0.35))

	# Lichter (vorn schmale Streifen, hinten je nach Stil; Vortex mit runden Doppel-Rückleuchten)
	var head_m := mat(Color(1, 1, 0.95), 0, 0.3, Color(1, 1, 0.9), 3.0)
	var tail_m := mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 2.5)
	var hy: float = prof["head_y"]
	var ty: float = prof["tail_y"]
	for s in [-1, 1]:
		_add(body, box(Vector3(0.42, 0.09, 0.05)), head_m, Vector3(s * (W / 2 - 0.3), hy, -L / 2 - 0.006))
		if style == "sedan":
			for k in 2:
				var tl := CylinderMesh.new()
				tl.top_radius = 0.075
				tl.bottom_radius = 0.075
				tl.height = 0.04
				tl.radial_segments = 12
				_add(body, tl, tail_m, Vector3(s * (W / 2 - 0.2 - k * 0.2), ty, L / 2 + 0.006)).rotation_degrees.x = 90
		else:
			_add(body, box(Vector3(0.48, 0.09, 0.05)), tail_m, Vector3(s * (W / 2 - 0.3), ty, L / 2 + 0.006))
	_add(body, box(Vector3(W * 0.5, 0.11, 0.04)), dark, Vector3(0, CLEARANCE + H * 0.38, -L / 2 - 0.006))  # Kühlergrill
	if headlights:
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, hy, -L / 2 - 0.1)
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.light_energy = 4.0
		spot.light_color = Color(1, 0.97, 0.88)
		spot.rotation_degrees.x = -4.0
		body.add_child(spot)

	# Bodykit
	if kit >= 1:
		for s in [-1, 1]:
			_add(body, box(Vector3(0.08, 0.14, L * 0.45)), paint, Vector3(s * (W / 2 + 0.02), CLEARANCE + 0.03, 0))
		_add(body, box(Vector3(W - 0.1, 0.06, 0.25)), dark, Vector3(0, CLEARANCE - 0.02, -L / 2 + 0.05))
	if kit == 2:
		# Widebody: Kotflügelverbreiterungen als Bogen über den Rädern
		for s in [-1, 1]:
			for z in [-1, 1]:
				var flare := TorusMesh.new()
				flare.inner_radius = WHEEL_R + 0.04
				flare.outer_radius = WHEEL_R + 0.14
				flare.rings = 14
				flare.ring_segments = 4
				var fm := _add(body, flare, paint, Vector3(s * (W / 2 - 0.02), WHEEL_R, z * (L / 2 - 0.78)))
				fm.rotation_degrees.z = 90
				fm.scale = Vector3(1, 0.5, 1)

	# Spoiler
	var sp: int = cfg["spoiler"]
	if sp == 1:
		_add(body, box(Vector3(W - 0.35, 0.06, 0.22)), paint, Vector3(0, body_top + 0.02, L / 2 - 0.2))
	elif sp >= 2:
		var hgt := 0.25 if sp == 2 else 0.45
		var ww := W - 0.1 if sp == 2 else W + 0.05
		for s in [-1, 1]:
			_add(body, box(Vector3(0.05, hgt, 0.1)), dark, Vector3(s * (W / 2 - 0.35), body_top + hgt / 2, L / 2 - 0.25))
			_add(body, box(Vector3(0.04, 0.2, 0.45)), paint, Vector3(s * ww / 2, body_top + hgt + 0.02, L / 2 - 0.25))
		_add(body, box(Vector3(ww, 0.05, 0.42)), paint, Vector3(0, body_top + hgt, L / 2 - 0.25))
		if sp == 3:
			_add(body, box(Vector3(ww, 0.04, 0.22)), dark, Vector3(0, body_top + hgt + 0.1, L / 2 - 0.15))

	# Vinyl
	var stripe_c := Color(0.95, 0.95, 0.95) if paint_c.get_luminance() < 0.5 else Color(0.05, 0.05, 0.05)
	var stripe := mat(stripe_c, 0.3, 0.3)
	if cfg["vinyl"] == 1:
		for s in [-1, 1]:
			_add(body, box(Vector3(0.16, 0.012, L - 0.4)), stripe, Vector3(s * 0.14, body_top + 0.003, 0))
	elif cfg["vinyl"] == 2:
		for s in [-1, 1]:
			_add(body, box(Vector3(0.012, 0.1, L * 0.8)), stripe, Vector3(s * (W / 2 - 0.02), CLEARANCE + H * 0.45, 0))

	# Unterbodenneon
	var neon: Dictionary = P["neon"]["options"][cfg["neon"]]
	if neon.has("color"):
		var nc: Color = neon["color"]
		var tube := mat(nc, 0, 0.5, nc, 5.0)
		# Leuchtröhren an beiden Schwellern und vorn/hinten: von jeder Seite sichtbar
		for s in [-1, 1]:
			_add(body, box(Vector3(0.04, 0.04, L - 0.7)), tube, Vector3(s * (W / 2 - 0.12), CLEARANCE - 0.02, 0))
			_add(body, box(Vector3(W - 0.4, 0.04, 0.04)), tube, Vector3(0, CLEARANCE - 0.02, s * (L / 2 - 0.4)))
		# Weicher Lichtteppich auf der Straße unter dem ganzen Auto
		var grad := Gradient.new()
		grad.set_color(0, Color(nc.r, nc.g, nc.b, 1.0))
		grad.set_color(1, Color(0, 0, 0, 1.0))
		grad.add_point(0.55, Color(nc.r * 0.55, nc.g * 0.55, nc.b * 0.55, 1.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		glow.albedo_texture = gt
		glow.albedo_color = Color(1.4, 1.4, 1.4)
		var pm := PlaneMesh.new()
		pm.size = Vector2(W + 1.2, L + 1.0)
		_add(root, pm, glow, Vector3(0, 0.025, 0))
		for z in [-1, 1]:
			var ol := OmniLight3D.new()
			ol.light_color = nc
			ol.light_energy = 1.8
			ol.omni_range = 3.2
			ol.position = Vector3(0, 0.15, z * L * 0.28)
			body.add_child(ol)

	# Auspuff + Nitroflammen
	var flames := []
	var flame_m := mat(Color(0.3, 0.6, 1), 0, 0.5, Color(0.3, 0.6, 1.0), 6.0)
	flame_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_m.albedo_color.a = 0.8
	for s in [-1, 1]:
		var pipe := CylinderMesh.new()
		pipe.top_radius = 0.05
		pipe.bottom_radius = 0.05
		pipe.height = 0.15
		var p := _add(body, pipe, mat(Color(0.6, 0.6, 0.6), 0.9, 0.2), Vector3(s * 0.35, CLEARANCE + 0.08, L / 2))
		p.rotation_degrees.x = 90
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.7
		var f := _add(body, cone, flame_m, Vector3(s * 0.35, CLEARANCE + 0.08, L / 2 + 0.4))
		f.rotation_degrees.x = 90
		f.visible = false
		flames.append(f)

	# Räder
	var tire_m := mat(Color(0.05, 0.05, 0.05), 0, 0.9)
	var rim_m := mat(rim["color"], 0.9, 0.2)
	var front := []
	var spinners := []
	var track := W / 2 - 0.15 + (0.05 if kit == 2 else 0.0)  # bündig unter dem Kotflügel
	for zi in [-1, 1]:
		for s in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * track, WHEEL_R, zi * (L / 2 - 0.78))
			root.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var tire := CylinderMesh.new()
			tire.top_radius = WHEEL_R
			tire.bottom_radius = WHEEL_R
			tire.height = 0.24
			tire.radial_segments = 12
			_add(spin, tire, tire_m, Vector3.ZERO).rotation_degrees.z = 90
			var disc := CylinderMesh.new()
			disc.top_radius = rim["radius"]
			disc.bottom_radius = rim["radius"]
			disc.height = 0.02
			disc.radial_segments = 12
			var rim_dark := mat(Color(0.1, 0.1, 0.1), 0.5, 0.5) if rim["spokes"] > 0 else rim_m
			# Schichten mit klarem Abstand (Reifen bis 0.12, Scheibe bis 0.132, Speichen bis 0.145): kein Flackern
			_add(spin, disc, rim_dark, Vector3(s * 0.122, 0, 0)).rotation_degrees.z = 90
			var n: int = rim["spokes"]
			var rr: float = rim["radius"]
			for k in n:
				var a := TAU * k / n
				var sk := _add(spin, box(Vector3(0.012, rr * 0.95, 0.05)), rim_m,
					Vector3(s * 0.139, cos(a) * rr * 0.5, sin(a) * rr * 0.5))
				sk.rotation.x = a
			if n > 0:  # Felgenhorn als Ring
				var lip := TorusMesh.new()
				lip.inner_radius = rr * 0.86
				lip.outer_radius = rr
				lip.rings = 16
				lip.ring_segments = 6
				var lm := _add(spin, lip, rim_m, Vector3(s * 0.136, 0, 0))
				lm.rotation_degrees.z = 90
				lm.scale = Vector3(1, 0.35, 1)
			spinners.append(spin)
			if zi == -1:
				front.append(pivot)

	root.set_meta("body", body)
	root.set_meta("front_pivots", front)
	root.set_meta("spinners", spinners)
	root.set_meta("flames", flames)
	root.set_meta("length", L)
	root.set_meta("width", W)
	return root


## Seitenprofil (z nach hinten, y nach oben) mit Radausschnitten, quer extrudiert. Vorn/hinten und an der
## Schulter eingezogen. Liefert das Mesh und wo Kabine und Lichter sitzen.
static func _body_profile(style: String, W: float, L: float, H: float) -> Dictionary:
	var C := CLEARANCE
	var top := C + H
	var zf := -L / 2.0
	var zr := L / 2.0
	var hood := 1.4 if style == "coupe" else (0.95 if style == "hatch" else 1.25)
	var deck := 0.9 if style == "sedan" else (0.75 if style == "coupe" else 0.28)
	var rear_top := top + (0.03 if style == "sedan" else 0.0)
	var nose := C + H * 0.68
	var pts := PackedVector2Array()
	# Unterkante von vorn nach hinten, mit Bögen über beiden Rädern
	pts.append(Vector2(zf + 0.12, C + 0.03))
	var ra := WHEEL_R + 0.06
	for wz in [zf + 0.78, zr - 0.78]:
		var a0 := asin((C - WHEEL_R) / ra)
		for k in 11:
			var ph: float = (PI - a0) + (2.0 * a0 - PI) * k / 10.0  # von vorn unten über oben nach hinten unten
			pts.append(Vector2(wz + ra * cos(ph), WHEEL_R + ra * sin(ph)))
	pts.append(Vector2(zr - 0.1, C + 0.03))
	# Heck hoch, Oberkante nach vorn, Bug runter
	pts.append(Vector2(zr, C + 0.14))
	pts.append(Vector2(zr + 0.01, rear_top - 0.1))
	pts.append(Vector2(zr - 0.06, rear_top))
	pts.append(Vector2(zr - deck, top))
	pts.append(Vector2(zf + hood, top - 0.01))
	pts.append(Vector2(zf + 0.3, top - 0.07))
	pts.append(Vector2(zf + 0.04, nose))
	pts.append(Vector2(zf, C + H * 0.42))
	pts.append(Vector2(zf + 0.03, C + 0.1))
	var tris := Geometry2D.triangulate_polygon(pts)
	var half := func(p: Vector2) -> float:
		var inset := 0.11 * clampf((absf(p.x) - (L / 2.0 - 0.4)) / 0.4, 0.0, 1.0)
		inset += maxf(p.y - (top - 0.14), 0.0) * 0.55  # Schulter
		return W / 2.0 - inset
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		for i in tris.size():
			var p: Vector2 = pts[tris[i]]
			st.add_vertex(Vector3(side * half.call(p), p.y, p.x))
	var n := pts.size()
	for i in n:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % n]
		var al := Vector3(-half.call(a), a.y, a.x)
		var ar := Vector3(half.call(a), a.y, a.x)
		var bl := Vector3(-half.call(b), b.y, b.x)
		var br := Vector3(half.call(b), b.y, b.x)
		for v in [al, bl, br, al, br, ar]:
			st.add_vertex(v)
	st.generate_normals()
	return {"mesh": st.commit(), "cab_front": zf + hood, "cab_rear": zr - deck, "head_y": nose - 0.08,
		"tail_y": rear_top - 0.13}


## Animiert Räder, Lenkung, Karosserie-Neigung und Nitroflammen.
static func animate(car: Node3D, speed: float, steer: float, roll: float, pitch: float, nitro_on: bool, delta: float) -> void:
	for p in car.get_meta("front_pivots"):
		p.rotation.y = -steer * 0.5
	for s in car.get_meta("spinners"):
		s.rotation.x -= speed / WHEEL_R * delta
	var body: Node3D = car.get_meta("body")
	body.rotation.z = lerpf(body.rotation.z, roll, 8.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, pitch, 6.0 * delta)
	for f in car.get_meta("flames"):
		f.visible = nitro_on
		if nitro_on:
			f.scale = Vector3.ONE * randf_range(0.7, 1.3)


static func mat(c: Color, metal := 0.0, rough := 0.5, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	return m


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _add(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Quader, dessen Oberseite kleiner ist (bottom/top = Breite, Länge). top_z verschiebt die Oberseite nach hinten.
static func tapered_box(bottom: Vector2, top: Vector2, h: float, top_z: float) -> ArrayMesh:
	var bfl := Vector3(-bottom.x / 2, 0, -bottom.y / 2)
	var bfr := Vector3(bottom.x / 2, 0, -bottom.y / 2)
	var brr := Vector3(bottom.x / 2, 0, bottom.y / 2)
	var brl := Vector3(-bottom.x / 2, 0, bottom.y / 2)
	var tfl := Vector3(-top.x / 2, h, top_z - top.y / 2)
	var tfr := Vector3(top.x / 2, h, top_z - top.y / 2)
	var trr := Vector3(top.x / 2, h, top_z + top.y / 2)
	var trl := Vector3(-top.x / 2, h, top_z + top.y / 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [[tfl, trl, trr, tfr], [bfl, bfr, brr, brl], [bfr, bfl, tfl, tfr],
			[brl, brr, trr, trl], [bfr, tfr, trr, brr], [brl, trl, tfl, bfl]]:
		_quad(st, q[0], q[1], q[2], q[3])
	return st.commit()


## Quad gegen den Uhrzeigersinn von außen gesehen; Godot erwartet Dreiecke im Uhrzeigersinn.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.add_vertex(v)
