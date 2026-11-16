extends "res://scripts/minimap.gd"
## Minikarte der Open World: wie im Rennen (dreht mit der Kamera), aber mit allen Straßen der Welt (Ring, Städte,
## Auffahrten), den Rennen als Punkte in der Farbe ihrer Art (nur in Sicht) und dem auf der großen Karte gewählten
## Ziel als Flagge (außer Sicht am Rand: zeigt die Richtung).


var _areas := []  # Gelände (seit 2.39): [Umriss, Farbe, Name, Teiche]


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


## Gelände als getönte Flächen mit Rand und Teichen unter den Straßen (seit 2.39)
func _draw_world() -> void:
	for ar in _areas:
		var pl: PackedVector2Array = ar[0]
		_world.draw_colored_polygon(pl, ar[1])
		var closed := pl.duplicate()
		closed.append(pl[0])
		_world.draw_polyline(closed, Color(ar[1].r * 1.4, ar[1].g * 1.4, ar[1].b * 1.4, 0.8), 1.2 * PX, true)
		for pd in ar[3]:
			_world.draw_colored_polygon(pd, COL_WATER)
	super()
