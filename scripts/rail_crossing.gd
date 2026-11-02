extends Node3D
## Bahnübergang mit Bahnhof: zwei Gleise quer zur Straße, Schranken, Andreaskreuz mit Blinklicht, Glocke,
## Oberleitung, daneben ein kleiner Bahnhof (Bahnsteige, Fußgängerbrücke, Empfangsgebäude, Wartende) und ein Zug.
## Der Zug startet, wenn sich der Spieler nähert, so dass er ungefähr gleichzeitig ankommt.
## Er ist ein hartes Hindernis (Gruppe "traffic"). Mit der Rampe auf der rechten Außenspur springt man drüber.

const Builder := preload("res://scripts/car_builder.gd")
const BLINK_SHADER := preload("res://shaders/blink.gdshader")
const TrainBody := preload("res://scripts/train_body.gd")

const People := preload("res://scripts/people.gd")

const SPEED := 32.0
const RAIL_HALF := 560.0
const TRACK_OFF := 2.25  # zwei Gleise, je so weit vor und hinter der Mitte
const PLAT_LEN := 95.0
const STATION_SIDE := -1.0  # Bahnhof links der Straße (in Fahrtrichtung)
const WARN_TIME := 5.0  # so viele Sekunden vor dem Zug gehen die Schranken runter

var d_cross := 0.0
var player: Node3D
var origin := Vector3.ZERO
var axis := Vector3.RIGHT  # Gleisrichtung
var fwd := Vector3.FORWARD  # Straßenrichtung
var train: TrainBody
var train_len := 0.0
var blocked := false
var _t_arrive := -1.0
var _dir := 1.0
var _clock := 0.0
var _triggered := false
var _gates := []
var _gate_angle := deg_to_rad(-85.0)
var _lights := []
var _bell: AudioStreamPlayer
var _rumble: AudioStreamPlayer


func setup(frame: Dictionary, d: float, half_w: float, walk: float, station := "MARKTPLATZ") -> void:
	d_cross = d
	origin = frame["pos"]
	fwd = frame["fwd"]
	axis = frame["right"]
	var right: Vector3 = frame["right"]
	var steel := Builder.mat(Color(0.62, 0.62, 0.66), 0.9, 0.25)
	var gravel := Builder.mat(Color(0.2, 0.19, 0.17), 0.0, 1.0)
	var wood := Builder.mat(Color(0.17, 0.12, 0.08), 0.0, 0.9)
	var rubber := Builder.mat(Color(0.09, 0.09, 0.1), 0.0, 0.8)
	var rail_basis := Basis.looking_at(axis, Vector3.UP)
	var road_edge := half_w + walk + 0.5
	# Zwei Gleise, Schienen über die ganze Länge
	for to in [-TRACK_OFF, TRACK_OFF]:
		for s in [-0.72, 0.72]:
			var r := MeshInstance3D.new()
			r.mesh = Builder.box(Vector3(0.1, 0.14, RAIL_HALF * 2.0))
			r.material_override = steel
			r.transform = Transform3D(rail_basis, origin + fwd * (to + s) + Vector3(0, 0.07, 0))
			add_child(r)
		# Übergang: Gummiplatten zwischen und neben den Schienen über Fahrbahn und Gehweg
		_add_box(Vector3(2.4, 0.05, road_edge * 2.0), rubber, Transform3D(rail_basis, origin + fwd * to + Vector3(0, 0.025, 0)))
	# Schotterbett und Schwellen außerhalb der Straße
	var xs := []
	var x := -RAIL_HALF
	while x < RAIL_HALF:
		if absf(x) > road_edge:
			xs.append(x)
		x += 0.9
	var sleeper_basis := Basis.looking_at(fwd, Vector3.UP)
	var sl := []
	for to in [-TRACK_OFF, TRACK_OFF]:
		for xx in xs:
			sl.append(Transform3D(sleeper_basis, origin + axis * xx + fwd * to + Vector3(0, 0.04, 0)))
	_mm(Builder.box(Vector3(2.5, 0.12, 0.25)), wood, sl)
	for s in [-1.0, 1.0]:
		var seg := RAIL_HALF - road_edge
		_add_box(Vector3(10.0, 0.1, seg), gravel, Transform3D(rail_basis, origin + axis * s * (road_edge + seg / 2.0) + Vector3(0, -0.01, 0)))
	# Andreaskreuz + Schranke je Fahrtrichtung (rechts für uns, links für den Gegenverkehr), vor dem jeweils ersten Gleis
	for s in [1.0, -1.0]:
		var approach: Vector3 = -fwd * s  # von dort kommen die Autos
		var side_dir: Vector3 = right * s
		_cross_sign(origin + approach * (TRACK_OFF + 8.0) + side_dir * (half_w + 1.4), -approach)
		_gate(origin + approach * (TRACK_OFF + 5.0) + side_dir * (half_w + 0.6), -approach, half_w)
	_catenary(road_edge)
	_station(road_edge, station)
	_build_train()
	_bell = Sfx.looping("bell")
	add_child(_bell)
	_rumble = Sfx.looping("rumble")
	add_child(_rumble)


## Punkt in Bahn-Koordinaten: x entlang der Gleise (negativ = Bahnhofsseite), z quer (in Fahrtrichtung der Straße)
func _p(x: float, y: float, z: float) -> Vector3:
	return origin + axis * x + Vector3(0, y, 0) + fwd * z


func _add_box(size: Vector3, m: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Builder.box(size)
	mi.material_override = m
	mi.transform = xf
	add_child(mi)
	return mi


func _mm(mesh: Mesh, m: Material, xfs: Array) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	add_child(mmi)


## Oberleitung: Mittelmasten zwischen den Gleisen mit Querträger, Fahrdraht und Tragseil über beiden Gleisen
func _catenary(road_edge: float) -> void:
	var steel := Builder.mat(Color(0.3, 0.32, 0.34), 0.7, 0.4)
	var wire := Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.4)
	var b := Basis.looking_at(fwd, Vector3.UP)  # lokales X entlang der Gleise
	var masts := []
	var arms := []
	var x := road_edge + 6.0
	while x < RAIL_HALF:
		for s in [-1.0, 1.0]:
			masts.append(Transform3D(b, _p(s * x, 3.3, 0.0)))
			arms.append(Transform3D(b, _p(s * x, 6.35, 0.0)))
		x += 32.0
	_mm(Builder.box(Vector3(0.3, 6.6, 0.3)), steel, masts)
	_mm(Builder.box(Vector3(0.18, 0.18, TRACK_OFF * 2.0 + 1.6)), steel, arms)
	var rb := Basis.looking_at(axis, Vector3.UP)
	for to in [-TRACK_OFF, TRACK_OFF]:
		for h in [5.6, 6.25]:
			_add_box(Vector3(0.03, 0.03, RAIL_HALF * 2.0), wire, Transform3D(rb, origin + fwd * to + Vector3(0, h, 0)))


## Bahnhof neben dem Übergang: zwei Außenbahnsteige mit Dach, Fußgängerbrücke, Empfangsgebäude, Signale, Wartende
func _station(road_edge: float, station: String) -> void:
	var sd := STATION_SIDE
	var x0 := road_edge + 2.0  # Bahnsteiganfang (Abstand von der Straßenmitte)
	var x1 := x0 + PLAT_LEN
	var concrete := Builder.mat(Color(0.45, 0.45, 0.46), 0.0, 0.85)
	var white := Builder.mat(Color(0.9, 0.9, 0.85), 0.0, 0.5, Color(1, 1, 0.9), 0.4)
	var roof := Builder.mat(Color(0.18, 0.2, 0.23), 0.5, 0.5)
	var post := Builder.mat(Color(0.12, 0.3, 0.2), 0.6, 0.4)
	var lamp := Builder.mat(Color(1, 1, 1), 0.0, 0.3, Color(0.85, 0.92, 1.0), 4.0)
	var sign_m := Builder.mat(Color(0.05, 0.25, 0.6), 0.2, 0.4, Color(0.1, 0.35, 0.9), 1.2)
	var glass := Builder.mat(Color(0.5, 0.7, 0.8), 0.3, 0.1, Color(0.4, 0.6, 0.7), 0.5)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.35
	var b := Basis.looking_at(fwd, Vector3.UP)  # lokales X entlang der Gleise, -Z in Straßenrichtung
	var xm := sd * (x0 + x1) / 2.0
	var posts := []
	var strips := []
	var benches := []
	var people := []
	for side in [-1.0, 1.0]:
		var zc: float = side * (TRACK_OFF + 1.6 + 2.0)  # Bahnsteigmitte
		# Bahnsteig mit weißer Kante
		_add_box(Vector3(PLAT_LEN, 0.76, 4.0), concrete, Transform3D(b, _p(xm, 0.38, zc)))
		_add_box(Vector3(PLAT_LEN, 0.02, 0.3), white, Transform3D(b, _p(xm, 0.77, zc - side * 1.75)))
		# Dach über dem mittleren Teil
		var r0 := x0 + 14.0
		var r1 := x0 + 74.0
		_add_box(Vector3(r1 - r0, 0.2, 4.6), roof, Transform3D(b, _p(sd * (r0 + r1) / 2.0, 4.1, zc)))
		var px := r0 + 4.0
		while px < r1:
			posts.append(Transform3D(b, _p(sd * px, 2.43, zc + side * 0.6)))
			strips.append(Transform3D(b, _p(sd * px, 3.95, zc - side * 0.6)))
			if int(px) % 2 == 0:
				benches.append(Transform3D(b, _p(sd * (px + 3.0), 1.0, zc + side * 1.2)))
			px += 10.0
		# Stationsschilder unter dem Dach, zum Gleis
		for sx in [r0 + 10.0, r1 - 12.0]:
			var n := Node3D.new()
			n.transform = Transform3D(Basis.looking_at(fwd * side, Vector3.UP), _p(sd * sx, 3.4, zc - side * 1.5))
			add_child(n)
			Builder._add(n, Builder.box(Vector3(5.0, 0.7, 0.08)), sign_m, Vector3.ZERO)
			_text(n, station, 40, Color(1, 1, 1), Vector3(0, 0, 0.05))
			_text(n, station, 40, Color(1, 1, 1), Vector3(0, 0, -0.05), true)
		# Licht unter dem Dach
		for lx in [r0 + 15.0, r1 - 15.0]:
			var ol := OmniLight3D.new()
			ol.light_color = Color(0.85, 0.92, 1.0)
			ol.light_energy = 1.6
			ol.omni_range = 16.0
			ol.position = _p(sd * lx, 3.6, zc)
			add_child(ol)
		# Wartende am Bahnsteig, Blick zum Gleis
		var k := 0
		while k < 11:
			var wx := randf_range(x0 + 6.0, x1 - 8.0)
			var face: Vector3 = (-fwd * side + axis * randf_range(-0.5, 0.5)).normalized()
			people.append(Transform3D(Basis.looking_at(face, Vector3.UP), _p(sd * wx, 0.76, zc + side * randf_range(0.0, 1.3))))
			k += 1
	_mm(Builder.box(Vector3(0.25, 3.3, 0.25)), post, posts)
	_mm(Builder.box(Vector3(2.8, 0.08, 0.3)), lamp, strips)
	_mm(Builder.box(Vector3(1.8, 0.45, 0.5)), roof, benches)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d_cross)
	People.crowd(self, people, [People.WAIT, People.WAIT, People.PHONE], rng)
	# Fußgängerbrücke zwischen den Bahnsteigen: zwei Treppentürme, verglaster Steg über der Oberleitung
	var fx := sd * (x0 + 8.0)
	for side in [-1.0, 1.0]:
		var zt: float = side * (TRACK_OFF + 1.6 + 2.4)
		_add_box(Vector3(2.6, 7.6, 2.6), roof, Transform3D(b, _p(fx, 0.76 + 3.8, zt)))
		_add_box(Vector3(2.64, 6.0, 2.0), glass, Transform3D(b, _p(fx, 0.76 + 3.6, zt)))
	_add_box(Vector3(2.6, 0.4, (TRACK_OFF + 4.0) * 2.0), roof, Transform3D(b, _p(fx, 7.0, 0.0)))
	_add_box(Vector3(2.62, 1.6, (TRACK_OFF + 4.0) * 2.0), glass, Transform3D(b, _p(fx, 8.0, 0.0)))
	_add_box(Vector3(2.6, 0.15, (TRACK_OFF + 4.0) * 2.0), roof, Transform3D(b, _p(fx, 8.85, 0.0)))
	_add_box(Vector3(0.1, 0.06, (TRACK_OFF + 4.0) * 2.0), lamp, Transform3D(b, _p(fx, 8.7, 0.0)))
	# Empfangsgebäude hinter Bahnsteig 1 mit Uhr und Namen, große Säule mit Schild an der Straße
	var zb := -(TRACK_OFF + 3.6 + 2.0 + 5.2)
	var bx := sd * (x0 + 40.0)
	var brick := Builder.mat(Color(0.32, 0.17, 0.12), 0.0, 0.85)
	var win := Builder.mat(Color(0.1, 0.08, 0.05), 0.2, 0.3, Color(1.0, 0.8, 0.5), 1.4)
	_add_box(Vector3(36.0, 9.0, 10.0), brick, Transform3D(b, _p(bx, 4.5, zb)))
	_add_box(Vector3(14.0, 4.0, 11.0), brick, Transform3D(b, _p(bx, 11.0, zb)))
	for wy in [2.0, 5.6]:
		_add_box(Vector3(32.0, 1.6, 10.1), win, Transform3D(b, _p(bx, wy, zb)))
	var gb := Node3D.new()
	gb.transform = Transform3D(Basis.looking_at(-fwd, Vector3.UP), _p(bx, 11.0, zb + 5.6))
	add_child(gb)
	_text(gb, "BAHNHOF " + station, 64, Color(1.0, 0.9, 0.6), Vector3(0, 0.3, 0))
	var clock := CylinderMesh.new()
	clock.top_radius = 1.0
	clock.bottom_radius = 1.0
	clock.height = 0.15
	clock.radial_segments = 20
	Builder._add(gb, clock, white, Vector3(0, -2.4, 0)).rotation_degrees.x = 90
	# Säule mit "S"-Signet und Stationsnamen am Straßenrand, gut sichtbar beim Anfahren
	var tp := _p(sd * (road_edge + 1.5), 0.0, -(TRACK_OFF + 9.5))
	var totem := Node3D.new()
	totem.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), tp)
	add_child(totem)
	Builder._add(totem, Builder.box(Vector3(0.3, 6.0, 0.3)), roof, Vector3(0, 3.0, 0))
	Builder._add(totem, Builder.box(Vector3(3.6, 1.6, 0.3)), sign_m, Vector3(0, 5.6, 0))
	var green := Builder.mat(Color(0.1, 0.6, 0.25), 0.0, 0.4, Color(0.1, 0.8, 0.3), 2.0)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.36
	disc.radial_segments = 16
	Builder._add(totem, disc, green, Vector3(-1.2, 5.6, 0)).rotation_degrees.x = 90
	for zs in [-1.0, 1.0]:
		_text(totem, "S", 64, Color(1, 1, 1), Vector3(-1.2, 5.6, -0.2 * zs), zs > 0.0)
		_text(totem, station, 30, Color(1, 1, 1), Vector3(0.45, 5.6, -0.17 * zs), zs > 0.0)
	# Signale an den Bahnsteigenden
	var red := Builder.mat(Color(0.9, 0.05, 0.05), 0.0, 0.3, Color(1.0, 0.05, 0.03), 4.0)
	var grn := Builder.mat(Color(0.05, 0.9, 0.2), 0.0, 0.3, Color(0.1, 1.0, 0.3), 4.0)
	for side in [-1.0, 1.0]:
		var sp := _p(sd * (x1 + 4.0), 0.0, side * (TRACK_OFF + 2.2))
		Builder._add(self, Builder.box(Vector3(0.2, 4.0, 0.2)), roof, sp + Vector3(0, 2.0, 0))
		Builder._add(self, Builder.box(Vector3(0.5, 1.1, 0.4)), roof, sp + Vector3(0, 4.3, 0))
		var lm := SphereMesh.new()
		lm.radius = 0.14
		lm.height = 0.28
		Builder._add(self, lm, red if side < 0.0 else grn, sp + Vector3(0, 4.5, 0) - axis * sd * 0.22)


func _text(parent: Node3D, text: String, size: int, col: Color, pos: Vector3, flip := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.012
	l.modulate = col
	l.shaded = false
	l.double_sided = false
	l.position = pos
	if flip:
		l.rotation.y = PI
	parent.add_child(l)


## Schild; `facing` ist die Fahrtrichtung der ankommenden Autos, das Schild schaut ihnen entgegen (+Z)
func _cross_sign(pos: Vector3, facing: Vector3) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(facing, Vector3.UP), pos + Vector3(0, 0.2, 0))
	add_child(n)
	var white := Builder.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4, Color(1, 1, 1), 0.3)
	var red := Builder.mat(Color(0.85, 0.05, 0.05), 0.0, 0.4)
	var grey := Builder.mat(Color(0.3, 0.3, 0.32), 0.6, 0.4)
	Builder._add(n, Builder.box(Vector3(0.12, 3.6, 0.12)), grey, Vector3(0, 1.8, 0))
	_solid_box(n, Vector3(0.25, 2.0, 0.25), Vector3(0, 1.0, 0))
	for a in [45.0, -45.0]:
		Builder._add(n, Builder.box(Vector3(1.9, 0.3, 0.04)), red, Vector3(0, 3.2, 0.06)).rotation_degrees.z = a
		Builder._add(n, Builder.box(Vector3(1.75, 0.18, 0.04)), white, Vector3(0, 3.2, 0.09)).rotation_degrees.z = a
	Builder._add(n, Builder.box(Vector3(1.1, 0.4, 0.1)), Builder.mat(Color(0.05, 0.05, 0.05), 0.3, 0.5), Vector3(0, 2.2, 0.05))
	for k in 2:
		var m := ShaderMaterial.new()
		m.shader = BLINK_SHADER
		m.set_shader_parameter("rate", 1.2)
		m.set_shader_parameter("phase", 0.5 * k)
		m.set_shader_parameter("active", 0.0)
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		var l := Builder._add(n, sm, m, Vector3(-0.3 + k * 0.6, 2.2, 0.14))
		_lights.append(l)


## Feste Kollisionsbox (Schrankenantrieb, Mast des Andreaskreuzes)
func _solid_box(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


## Schranke: Drehpunkt am Straßenrand, Baum ragt zur Fahrbahnmitte (lokal -X)
func _gate(pos: Vector3, facing: Vector3, length: float) -> void:
	var post := Node3D.new()
	post.transform = Transform3D(Basis.looking_at(facing, Vector3.UP), pos)
	add_child(post)
	var white := Builder.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4, Color(1, 1, 1), 0.4)
	var red := Builder.mat(Color(0.9, 0.05, 0.05), 0.0, 0.4, Color(1, 0.05, 0.02), 0.6)
	var grey := Builder.mat(Color(0.35, 0.35, 0.37), 0.6, 0.4)
	Builder._add(post, Builder.box(Vector3(0.45, 1.2, 0.45)), grey, Vector3(0, 0.6, 0))
	_solid_box(post, Vector3(0.5, 1.4, 0.5), Vector3(0, 0.7, 0))  # Schrankenantrieb: fest, man fährt nicht hindurch
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.05, 0)
	post.add_child(pivot)
	var segs := 6
	for i in segs:
		var sl := length / segs
		Builder._add(pivot, Builder.box(Vector3(sl, 0.14, 0.1)), red if i % 2 == 0 else white, Vector3(-sl * (i + 0.5), 0, 0))
	Builder._add(pivot, Builder.box(Vector3(0.8, 0.3, 0.2)), grey, Vector3(0.5, 0, 0))  # Gegengewicht
	_gates.append(pivot)


func _build_train() -> void:
	train = TrainBody.new()
	train.add_to_group("traffic")
	train.collision_layer = 2
	train.collision_mask = 0
	add_child(train)
	var red := Builder.mat(Color(0.7, 0.05, 0.05), 0.4, 0.35)
	var white := Builder.mat(Color(0.85, 0.85, 0.87), 0.3, 0.4)
	var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.5, 0.5)
	var win := Builder.mat(Color(0.05, 0.05, 0.05), 0.5, 0.2, Color(1, 0.85, 0.6), 1.6)
	var head := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 1, 0.9), 6.0)
	var lengths := [16.0, 14.0, 14.0, 14.0, 14.0, 14.0]
	var gap := 1.0
	train_len = 0.0
	for l in lengths:
		train_len += l + gap
	train_len -= gap
	var z := -train_len / 2.0
	for i in lengths.size():
		var l: float = lengths[i]
		var cz := z + l / 2.0
		var car := Node3D.new()
		car.position = Vector3(0, 0, cz)
		train.add_child(car)
		Builder._add(car, Builder.box(Vector3(3.0, 3.1, l)), white, Vector3(0, 2.25, 0))
		Builder._add(car, Builder.box(Vector3(3.02, 0.6, l + 0.02)), red, Vector3(0, 1.05, 0))
		Builder._add(car, Builder.box(Vector3(3.04, 0.9, l - 1.6)), win, Vector3(0, 2.6, 0))
		Builder._add(car, Builder.box(Vector3(2.6, 0.3, l - 0.4)), dark, Vector3(0, 3.95, 0))
		for bz in [-l / 2.0 + 2.2, l / 2.0 - 2.2]:
			Builder._add(car, Builder.box(Vector3(2.4, 0.7, 2.4)), dark, Vector3(0, 0.45, bz))
		if i == 0:
			# Triebkopf vorne (lokal -Z): schräge Front, Scheinwerfer, Stromabnehmer
			Builder._add(car, Builder.tapered_box(Vector2(3.0, 2.0), Vector2(2.6, 0.6), 1.1, 0.5), dark, Vector3(0, 2.6, -l / 2.0 + 1.0))
			for s in [-0.9, 0.9]:
				Builder._add(car, Builder.box(Vector3(0.4, 0.25, 0.05)), head, Vector3(s, 1.4, -l / 2.0 - 0.02))
			Builder._add(car, Builder.box(Vector3(0.1, 1.2, 1.4)), dark, Vector3(0, 4.6, 0)).rotation_degrees.x = 30
			var sp := SpotLight3D.new()
			sp.position = Vector3(0, 1.6, -l / 2.0 - 0.3)
			sp.spot_range = 60.0
			sp.spot_angle = 30.0
			sp.light_energy = 6.0
			car.add_child(sp)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.2, 4.0, l)
		cs.shape = bs
		cs.position = Vector3(0, 0, cz) + Vector3(0, 2.0, 0)
		train.add_child(cs)
		z += l + gap
	train.visible = false
	train.position = origin + Vector3(0, -50, 0)


func is_blocked() -> bool:
	return blocked


func _process(dt: float) -> void:
	_clock += dt
	if player == null:
		return
	var p: float = player.progress
	if p < d_cross - 460.0:
		_triggered = false
	# Zug so starten, dass er mit dem Spieler am Übergang ankommt
	if not _triggered and _t_arrive < 0.0 and p > d_cross - 420.0 and p < d_cross - 200.0:
		_triggered = true
		if randf() < 0.8:
			var spd := maxf(absf(player.speed_fwd), 28.0)
			_t_arrive = _clock + (d_cross - p) / spd
			_dir = 1.0 if randf() < 0.5 else -1.0

	var was_blocked := blocked
	blocked = false
	if _t_arrive > 0.0:
		var x := (_clock - _t_arrive) * SPEED * _dir  # Mitte des Zugs entlang der Gleise
		var front := absf(x) - train_len / 2.0
		var approaching := x * _dir < 0.0
		blocked = (approaching and front < SPEED * WARN_TIME) or (not approaching and front < 12.0)
		train.visible = absf(x) < RAIL_HALF + train_len
		train.global_transform = Transform3D(Basis.looking_at(axis * _dir, Vector3.UP), origin + axis * x - fwd * TRACK_OFF * _dir)
		train.velocity_vec = axis * _dir * SPEED
		var td := player.global_position.distance_to(train.global_position)
		_set_volume(_rumble, clampf(1.0 - td / 380.0, 0.0, 1.0), 2.0)
		if not approaching and front > RAIL_HALF:
			_t_arrive = -1.0
			train.visible = false
			train.position = origin + Vector3(0, -50, 0)
			_rumble.stop()
	if blocked and not was_blocked:
		var dist := player.global_position.distance_to(origin)
		Sfx.play("horn", linear_to_db(clampf(1.0 - dist / 600.0, 0.15, 1.0)))
	for l in _lights:
		l.material_override.set_shader_parameter("active", 1.0 if blocked else 0.0)
	var cd := player.global_position.distance_to(origin)
	_set_volume(_bell, clampf(1.0 - cd / 220.0, 0.0, 1.0) if blocked else 0.0, -4.0)
	# Schranken: runter in ~2 s, rauf etwas langsamer
	var target := 0.0 if blocked else deg_to_rad(-85.0)
	_gate_angle = move_toward(_gate_angle, target, dt * (0.8 if blocked else 0.6))
	for g in _gates:
		g.rotation.z = _gate_angle


func _set_volume(a: AudioStreamPlayer, v: float, base_db: float) -> void:
	if v <= 0.01:
		if a.playing:
			a.stop()
		return
	a.volume_db = base_db + linear_to_db(v)
	if not a.playing:
		a.play()
