extends Control
## Streckenkarte: Deutschland im Neon-Look, jede Stadt mit Events als Punkt. Gesperrt grau, frei grün, gewonnen gold,
## die gewählte Stadt pulsiert und trägt ihren Namen. Die Karriere-Route verbindet die freien Städte der Reihe nach.

const MapData := preload("res://scripts/map_data.gd")
const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

const LON := Vector2(5.8, 15.1)
const LAT := Vector2(47.2, 55.1)
const K := 0.63  # cos(51°): Längengrade sind hier kürzer als Breitengrade

var selected := ""  # Eventname
var _t := 0.0
var _font: Font


func _ready() -> void:
	_font = UI.font("cond", 0.12)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(dt: float) -> void:
	_t += dt
	queue_redraw()


func _to_px(lon: float, lat: float) -> Vector2:
	var w := (LON.y - LON.x) * K
	var h := LAT.y - LAT.x
	var s := minf((size.x - 16.0) / w, (size.y - 16.0) / h)
	var off := (size - Vector2(w, h) * s) / 2.0
	return off + Vector2((lon - LON.x) * K, LAT.y - lat) * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.04, 0.82))
	draw_rect(Rect2(Vector2.ZERO, size), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), false, 1.0)
	# Raster
	for g in range(6, 16):
		draw_line(_to_px(g, LAT.x), _to_px(g, LAT.y), Color(0.2, 0.4, 0.6, 0.08), 1.0)
	for g in range(48, 56):
		draw_line(_to_px(LON.x, g), _to_px(LON.y, g), Color(0.2, 0.4, 0.6, 0.08), 1.0)
	for poly in MapData.GERMANY:
		var pts := PackedVector2Array()
		for i in range(0, poly.size(), 2):
			pts.append(_to_px(poly[i], poly[i + 1]))
		if pts.size() >= 3:
			var tri := Geometry2D.triangulate_polygon(pts)
			if not tri.is_empty():
				draw_colored_polygon(pts, Color(0.03, 0.08, 0.12, 0.95))
			pts.append(pts[0])
			draw_polyline(pts, Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.85), 1.4, true)
	# Städte: Stand je Stadt (gewonnen > frei > gesperrt)
	var towns := {}  # Stadt -> [Position, Stand]
	var route := PackedVector2Array()
	for i in Catalog.CAREER.size():
		var r: Dictionary = Catalog.RACES[Catalog.race_index(Catalog.CAREER[i])]
		var p := _to_px(r["geo"].y, r["geo"].x)
		var state := 0
		if GameState.career_unlocked(i):
			state = 2 if r["name"] in GameState.won_events else 1
			route.append(p)
		var town: String = r.get("town", "")
		towns[town] = [p, maxi(state, towns.get(town, [p, 0])[1])]
	if route.size() >= 2:
		draw_polyline(route, Color(UI.GREEN.r, UI.GREEN.g, UI.GREEN.b, 0.35), 1.0, true)
	var sel_town := ""
	var sel_pos := Vector2.ZERO
	if selected != "":
		var sr: Dictionary = Catalog.RACES[Catalog.race_index(selected)]
		sel_town = sr.get("town", "")
		sel_pos = _to_px(sr["geo"].y, sr["geo"].x)
	for town in towns:
		var p: Vector2 = towns[town][0]
		var st: int = towns[town][1]
		var col: Color = [Color(0.45, 0.48, 0.52), UI.GREEN, Color(1.0, 0.8, 0.25)][st]
		draw_circle(p, 2.6, col)
	if sel_town != "":
		var pulse := 0.5 + 0.5 * sin(_t * 5.0)
		draw_arc(sel_pos, 5.0 + pulse * 3.0, 0.0, TAU, 24, Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, 0.9 - pulse * 0.5), 1.5, true)
		draw_circle(sel_pos, 3.2, UI.PINK)
		var label := sel_town.to_upper()
		var fs := 11
		var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lp := sel_pos + Vector2(8, 4)
		if lp.x + tw > size.x - 4.0:
			lp.x = sel_pos.x - 8 - tw
		draw_string_outline(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
		draw_string(_font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
