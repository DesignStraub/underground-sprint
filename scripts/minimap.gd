extends Control
## Radar-Minimap unten links: Die Karte dreht sich mit der Kamera (oben ist da, wo du hinschaust), du bist der
## gelbe Pfeil in der Mitte, Gegner sind Punkte in ihrer Lackfarbe (außer Sicht am Rand), Abkürzungen orange,
## gesperrte Seitenstraßen grau, Flüsse und Seen blau, das Ziel eine Schachbrettflagge (außer Sicht am Rand,
## zeigt so die Richtung). Weiter raus gezoomt, je schneller du fährst.
##
## Ebenen: Hintergrund und Rand werden einmal gezeichnet, die Straßen einmal in Weltkoordinaten (x, z) auf einem
## Node2D, das je Bild nur verschoben, gedreht und skaliert wird; ein Shader blendet alles außerhalb des Kreises
## aus. Nordzeiger, Ziel, Gegner und Pfeil sind ebenfalls einmal gezeichnet und werden nur bewegt und gedreht.

const UI := preload("res://scripts/ui_style.gd")
const CLIP := preload("res://shaders/minimap_clip.gdshader")
const R := 50.0  # Radius in HUD-Pixeln
const SIZE := R * 2.0 + 8.0
const C := Vector2(SIZE, SIZE) / 2.0  # Mittelpunkt
const RC := R - 1.0  # bis hierhin reicht die Karte
const STEP := 8.0  # Abstand der Kartenpunkte in Metern
const PX := 180.0 / R  # Meter je Pixel bei mittlerem Zoom (Linienbreiten in Metern)
const COL_MAIN := Color(0.93, 0.96, 1.0)
const COL_EDGE := Color(0.45, 0.6, 0.8, 0.55)
const COL_ALT := Color(1.0, 0.62, 0.15)
const COL_SPUR := Color(0.6, 0.65, 0.75, 0.45)
const COL_WATER := Color(0.12, 0.35, 0.75, 0.75)

var track: Dictionary
var player: Node3D
var cars: Array = []  # Gegner (Node3D), Farbe in meta "hud_col"
var view_m := 150.0  # Sichtweite (Radius) in Metern

var _xf := Transform2D.IDENTITY  # Welt (x, z) -> Kartenpixel
var _roads := [[], [], []]  # je Art (Haupt, Abkürzung, Sackgasse): Linienzüge in Welt (x, z)
var _rivers := []  # [Linienzug, Breite m]
var _lakes := []  # Vierecke
var _finish := Vector2.ZERO
var _font: Font
var _world: Node2D
var _mat: ShaderMaterial
var _north: Control
var _flag: Control
var _dots := []  # je Gegner ein Punkt
var _glow: Control
var _arrow: Control


func setup(track_: Dictionary, player_: Node3D, cars_: Array) -> void:
	track = track_
	player = player_
	cars = cars_
	_font = UI.font("cond", 0.2)
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for p in track["paths"]:
		var kind: String = p["kind"]
		var c: Curve3D = p["curve"]
		var plen: float = c.get_baked_length()
		var pts := PackedVector2Array()
		for i in maxi(int(ceil(plen / STEP)), 1) + 1:
			var v := c.sample_baked(minf(i * STEP, plen))
			pts.append(Vector2(v.x, v.z))
		if kind == "main" and track["loop"]:
			pts.append(pts[0])
		_roads[0 if kind == "main" else (2 if kind == "spur" else 1)].append(pts)
	for rv in track["rivers"]:
		var rp := PackedVector2Array()
		for v in rv["pts"]:
			rp.append(Vector2(v.x, v.y) if v is Vector2 else Vector2(v.x, v.z))
		if rp.size() >= 2:
			_rivers.append([rp, maxf(float(rv["half"]) * 2.0, 3.0 * PX)])
	for lk in track["lakes"]:
		var ct: Vector3 = lk["center"]
		var au: Vector3 = lk["au"] * float(lk["hu"])
		var av: Vector3 = lk["av"] * float(lk["hv"])
		var c2 := Vector2(ct.x, ct.z)
		var u := Vector2(au.x, au.z)
		var w := Vector2(av.x, av.z)
		_lakes.append(PackedVector2Array([c2 - u - w, c2 + u - w, c2 + u + w, c2 - u + w]))
	var curve: Curve3D = track["curve"]
	var fd: float = fposmod(track["finish"], track["length"]) if track["loop"] else track["finish"]
	var fp := curve.sample_baked(fd)
	_finish = Vector2(fp.x, fp.z)

	_layer(_draw_bg)
	_world = Node2D.new()
	_mat = ShaderMaterial.new()
	_mat.shader = CLIP
	_world.material = _mat
	_world.draw.connect(_draw_world)
	add_child(_world)
	_layer(_draw_rim)
	_north = _layer(_draw_north)
	_flag = _layer(_draw_flag)
	for car in cars:
		var col: Color = car.get_meta("hud_col", Color(1.0, 0.3, 0.25))
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func(): _draw_dot(dot, col))
		add_child(dot)
		_dots.append(dot)
	_glow = _layer(func(l: Control): l.draw_circle(Vector2.ZERO, 9.0, Color(1.0, 0.85, 0.2)))
	_glow.position = C
	_arrow = _layer(_draw_arrow)
	_arrow.position = C


## Kind-Control, das einmal mit fn gezeichnet wird (Marken zeichnen um ihren Ursprung)
func _layer(fn: Callable) -> Control:
	var l := Control.new()
	l.size = size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.draw.connect(fn.bind(l))
	add_child(l)
	return l


func _process(delta: float) -> void:
	if player == null or not is_visible_in_tree():
		return
	var cam: Camera3D = player.get("cam")
	var f3: Vector3 = -cam.global_basis.z if cam else -player.global_basis.z
	var f := Vector2(f3.x, f3.z)
	if f.length() < 0.1:
		f3 = -player.global_basis.z
		f = Vector2(f3.x, f3.z)
	f = f.normalized()
	var v: float = player.velocity.length() if "velocity" in player else 0.0
	view_m = lerpf(view_m, lerpf(130.0, 230.0, clampf(v / 60.0, 0.0, 1.0)), minf(delta * 1.5, 1.0))
	var k := R / view_m
	var right := Vector2(-f.y, f.x)
	# Bildschirm-x = Anteil nach rechts, Bildschirm-y = minus Anteil nach vorn
	var xa := Vector2(right.x, -f.x) * k
	var ya := Vector2(right.y, -f.y) * k
	var pp := Vector2(player.global_position.x, player.global_position.z)
	_xf = Transform2D(xa, ya, C - xa * pp.x - ya * pp.y)
	_world.transform = _xf
	_mat.set_shader_parameter("center", pp)
	_mat.set_shader_parameter("radius", RC / k)
	_mat.set_shader_parameter("feather", 1.5 / k)

	# Norden am Rand, Ziel (außer Sicht am Rand: zeigt die Richtung), Gegner (außer Sicht kleiner am Rand)
	_north.position = C + _xf.basis_xform(Vector2(0, -1)).normalized() * (R + 0.5)
	var fpos := _xf * _finish
	var fin_out := (fpos - C).length() > R - 6.0
	_flag.position = C + (fpos - C).normalized() * (R - 6.0) if fin_out else fpos
	_flag.modulate.a = 0.75 if fin_out else 1.0
	for i in cars.size():
		var car: Node3D = cars[i]
		var dot: Control = _dots[i]
		dot.visible = is_instance_valid(car)
		if not dot.visible:
			continue
		var gp := car.global_position
		var off := _xf * Vector2(gp.x, gp.z) - C
		var out := off.length() > R - 4.0
		dot.position = C + (off.normalized() * (R - 4.0) if out else off)
		dot.scale = Vector2(0.75, 0.75) if out else Vector2.ONE
	# Du: Pfeil in Fahrtrichtung (beim Driften schräg zur Blickrichtung), Schein pulsiert
	var cf3: Vector3 = -player.global_basis.z
	var dir := _xf.basis_xform(Vector2(cf3.x, cf3.z))
	if dir.length() > 0.001:
		_arrow.rotation = dir.angle() + PI / 2.0
	_glow.modulate.a = (0.25 + 0.1 * sin(Time.get_ticks_msec() * 0.006)) * 0.5


## Dunkler Grund mit feinen Radarringen und Sichtkegel nach vorn (einmal)
func _draw_bg(l: Control) -> void:
	l.draw_circle(C, R, Color(0.02, 0.035, 0.07, 0.78))
	l.draw_arc(C, R * 0.5, 0.0, TAU, 40, Color(0.35, 0.85, 1.0, 0.07), 1.0, true)
	l.draw_line(C - Vector2(RC, 0), C + Vector2(RC, 0), Color(0.35, 0.85, 1.0, 0.05), 1.0)
	l.draw_line(C - Vector2(0, RC), C + Vector2(0, RC), Color(0.35, 0.85, 1.0, 0.05), 1.0)
	l.draw_colored_polygon(PackedVector2Array([C, C + Vector2.from_angle(deg_to_rad(-121.0)) * RC,
		C + Vector2.from_angle(deg_to_rad(-90.0)) * RC, C + Vector2.from_angle(deg_to_rad(-59.0)) * RC]), Color(0.35, 0.85, 1.0, 0.06))


## Straßen, Flüsse und Seen in Weltkoordinaten (einmal); erst alle Ränder, dann die hellen Linien
func _draw_world() -> void:
	var w := _world
	for lk in _lakes:
		w.draw_colored_polygon(lk, COL_WATER)
	for rv in _rivers:
		w.draw_polyline(rv[0], COL_WATER, rv[1], true)
	for pts in _roads[2]:
		w.draw_polyline(pts, COL_SPUR, 3.0 * PX, true)
	for pts in _roads[1]:
		w.draw_polyline(pts, COL_EDGE, 5.0 * PX, true)
	for pts in _roads[0]:
		w.draw_polyline(pts, COL_EDGE, 6.0 * PX, true)
	for pts in _roads[1]:
		w.draw_polyline(pts, COL_ALT, 2.2 * PX, true)
	for pts in _roads[0]:
		w.draw_polyline(pts, COL_MAIN, 2.6 * PX, true)


## Rand: dunkler Verlauf nach innen, heller Ring (einmal)
func _draw_rim(l: Control) -> void:
	l.draw_arc(C, R - 2.0, 0.0, TAU, 56, Color(0, 0, 0, 0.35), 4.0, true)
	l.draw_arc(C, R, 0.0, TAU, 64, Color(0, 0, 0, 0.6), 4.5, true)
	l.draw_arc(C, R, 0.0, TAU, 64, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.9), 1.6, true)


func _draw_north(l: Control) -> void:
	l.draw_circle(Vector2.ZERO, 5.0, Color(0.02, 0.03, 0.06, 0.95))
	l.draw_arc(Vector2.ZERO, 5.0, 0.0, TAU, 16, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.8), 1.0, true)
	l.draw_string(_font, Vector2(-5, 3.2), "N", HORIZONTAL_ALIGNMENT_CENTER, 10, 9, Color.WHITE)


## Kleine Schachbrettflagge (4 x 3 Felder)
func _draw_flag(l: Control) -> void:
	var s := 2.2
	var o := -Vector2(2.0 * s, 1.5 * s)
	l.draw_rect(Rect2(o - Vector2(1, 1), Vector2(4.0 * s + 2.0, 3.0 * s + 2.0)), Color(0, 0, 0, 0.9))
	for y in 3:
		for x in 4:
			l.draw_rect(Rect2(o + Vector2(x * s, y * s), Vector2(s, s)), Color.WHITE if (x + y) % 2 == 0 else Color(0.1, 0.1, 0.1))


func _draw_dot(l: Control, col: Color) -> void:
	l.draw_circle(Vector2.ZERO, 4.4, Color(0, 0, 0, 0.85))
	l.draw_circle(Vector2.ZERO, 3.3, col)
	l.draw_arc(Vector2.ZERO, 3.3, 0.0, TAU, 12, Color(1, 1, 1, 0.5), 0.8, true)


## Pfeil nach oben; die Ebene wird je Bild gedreht
func _draw_arrow(l: Control) -> void:
	l.draw_colored_polygon(PackedVector2Array([Vector2(0, -9.2), Vector2(6.6, 5.8), Vector2(0, 2.0), Vector2(-6.6, 5.8)]), Color(0, 0, 0, 0.9))
	l.draw_colored_polygon(PackedVector2Array([Vector2(0, -7.0), Vector2(5.0, 4.5), Vector2(0, 2.0), Vector2(-5.0, 4.5)]), Color(1.0, 0.85, 0.15))
