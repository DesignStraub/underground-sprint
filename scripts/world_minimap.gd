extends "res://scripts/minimap.gd"
## Minikarte der Open World: wie im Rennen (dreht mit der Kamera), aber mit allen Straßen der Welt (Ring, Städte,
## Auffahrten), den Rennen als Punkte in der Farbe ihrer Art (nur in Sicht) und dem auf der großen Karte gewählten
## Ziel als Flagge (außer Sicht am Rand: zeigt die Richtung).


var _areas := []  # Gelände (seit 2.39): [Umriss, Farbe, Name, Teiche]
var _route := PackedVector2Array()  # Strecke des laufenden Autobahn-Rennens (seit 2.43), über den Straßen
var _zones := {}  # Driftzonen (seit 2.45): Schlüssel -> Linienzug, orange über den Straßen


## roads: [[Linienzug (Welt x, z), Art 0 Haupt / 1 Auffahrt / 2 Nebenweg], ...]; pins: Node3D mit meta "hud_col";
## areas: Gelände (world._offroad_map) als Flächen unter den Straßen
func setup_world(roads: Array, player_: Node3D, pins: Array, areas := []) -> void:
	_areas = areas
	player = player_
	cars = pins
	edge_dots = false
	show_flag = false
	view_range = Vector2(220.0, 520.0)
	_font = UI.font("cond", 0.2)
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in roads:
		_roads[r[1]].append(r[0])
	_build_layers()


func set_target(p: Vector3, on: bool) -> void:
	_finish = Vector2(p.x, p.z)
	show_flag = on


## Driftzone einzeichnen (einmal je Zone; die Lage ändert sich nicht)
func add_zone(key: String, pts: PackedVector2Array) -> void:
	if _zones.has(key):
		return
	_zones[key] = pts
	if _top:
		_top.queue_redraw()


## Strecke eines Autobahn-Rennens hervorheben (leer: keine)
func set_route(pts: PackedVector2Array) -> void:
	_route = pts
	if _top:
		_top.queue_redraw()


## Seit 2.53 in Kacheln (TILE): bis 2.52 zeichnete die Minikarte jedes Bild alle Straßen der ganzen Welt, gut 4000
## 2D-Zeichenaufrufe, obwohl der Kreis nur ein paar hundert Meter zeigt. Jetzt hat jede Kachel ihre Stücke (unten
## Gelände, Wasser und Ränder, oben die hellen Linien) und ist nur sichtbar, wenn sie den Kreis berührt.
const TILE := 1200.0
const CHUNK := 48  # Punkte je Stück eines Linienzugs
var _tiles := []  # [Node2D, Rect2]
var _top: Node2D


func _build_layers() -> void:
	super()
	var under := {}
	var over := {}
	var put := func(dict: Dictionary, pts: PackedVector2Array, item: Array) -> void:
		var r := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			r = r.expand(q)
		var key := Vector2i(floori(r.get_center().x / TILE), floori(r.get_center().y / TILE))
		if not dict.has(key):
			dict[key] = [[], Rect2(r)]
		dict[key][0].append(item)
		dict[key][1] = (dict[key][1] as Rect2).merge(r)
	var pieces := func(pts: PackedVector2Array) -> Array:
		var out := []
		var i := 0
		while i < pts.size() - 1:
			out.append(pts.slice(i, mini(i + CHUNK + 1, pts.size())))
			i += CHUNK
		return out
	for ar in _areas:
		var pl: PackedVector2Array = ar[0]
		var closed := pl.duplicate()
		closed.append(pl[0])
		put.call(under, pl, ["poly", pl, ar[1]])
		put.call(under, pl, ["line", closed, Color(ar[1].r * 1.4, ar[1].g * 1.4, ar[1].b * 1.4, 0.8), 1.2 * PX])
		for pd in ar[3]:
			put.call(under, pd, ["poly", pd, COL_WATER])
	for lk in _lakes:
		put.call(under, lk, ["poly", lk, COL_WATER])
	for rv in _rivers:
		for pc in pieces.call(rv[0]):
			put.call(under, pc, ["line", pc, COL_WATER, rv[1]])
	for pts in _roads[2]:
		for pc in pieces.call(pts):
			put.call(under, pc, ["line", pc, COL_SPUR, 3.0 * PX])
	for pts in _roads[1]:
		for pc in pieces.call(pts):
			put.call(under, pc, ["line", pc, COL_EDGE, 5.0 * PX])
			put.call(over, pc, ["line", pc, COL_ALT, 2.2 * PX])
	for pts in _roads[0]:
		for pc in pieces.call(pts):
			put.call(under, pc, ["line", pc, COL_EDGE, 6.0 * PX])
	for pts in _roads[0]:
		for pc in pieces.call(pts):
			put.call(over, pc, ["line", pc, COL_MAIN, 2.6 * PX])
	for dict in [under, over]:
		for key in dict:
			var nd := Node2D.new()
			nd.use_parent_material = true
			var items: Array = dict[key][0]
			nd.draw.connect(func():
				for it in items:
					if it[0] == "poly":
						nd.draw_colored_polygon(it[1], it[2])
					else:
						nd.draw_polyline(it[1], it[2], it[3], true))
			_world.add_child(nd)
			_tiles.append([nd, (dict[key][1] as Rect2).grow(12.0)])
	_top = Node2D.new()
	_top.use_parent_material = true
	_top.draw.connect(_draw_top)
	_world.add_child(_top)


func _process(delta: float) -> void:
	super(delta)
	if player == null or _tiles.is_empty():
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var reach := view_m * RC / R + 20.0
	var view := Rect2(pp - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
	for t in _tiles:
		(t[0] as Node2D).visible = (t[1] as Rect2).intersects(view)


## Die eigentliche Welt-Ebene zeichnet nichts mehr selbst (alles in den Kacheln)
func _draw_world() -> void:
	pass


## Driftzonen und Autobahn-Rennen über den Straßen (wenige Linien, ohne Kacheln)
func _draw_top() -> void:
	for pl in _zones.values():
		if (pl as PackedVector2Array).size() > 1:
			_top.draw_polyline(pl, Color(1.0, 0.55, 0.12, 0.9), 2.6 * PX, true)
	if _route.size() > 1:
		_top.draw_polyline(_route, Color(0.25, 0.52, 1.0, 0.95), 3.2 * PX, true)
