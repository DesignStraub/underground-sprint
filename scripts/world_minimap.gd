extends "res://scripts/minimap.gd"
## Minikarte der Open World: wie im Rennen (dreht mit der Kamera), aber mit allen Straßen der Welt (Ring, Städte,
## Auffahrten), den Rennen als Punkte in der Farbe ihrer Art (nur in Sicht) und dem auf der großen Karte gewählten
## Ziel als Flagge (außer Sicht am Rand: zeigt die Richtung).


## roads: [[Linienzug (Welt x, z), Art 0 Haupt / 1 Auffahrt / 2 Nebenweg], ...]; pins: Node3D mit meta "hud_col"
func setup_world(roads: Array, player_: Node3D, pins: Array) -> void:
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
