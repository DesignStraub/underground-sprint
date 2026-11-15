extends Control
## Streckenkarte: Deutschland als ruhige Umrisskarte in einer Glasfläche (seit 2.35 im Menü-Look: Haarlinien statt
## Neon), jede Stadt mit Events als Punkt. Gesperrt grau, frei weiß, gewonnen gold; die gewählte Stadt trägt einen
## Ring im Akzent, der langsam atmet, und ihren Namen.
## Die Karte selbst zeichnet ein Kind-Element nur bei Größenänderung neu (die Umrisse sind teuer zu zerlegen),
## jedes Bild nur der Ring.

const MapData := preload("res://scripts/map_data.gd")
const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

const LON := Vector2(5.8, 15.1)
const LAT := Vector2(47.2, 55.1)
const K := 0.63  # cos(51°): Längengrade sind hier kürzer als Breitengrade

var selected := "":  # Eventname
	set(v):
		if v != selected:
			selected = v
			_sel_t = 0.0
var _t := 0.0
var _sel_t := 0.0  # seit wann die Stadt gewählt ist (Ring zieht sich beim Wechsel kurz zusammen)
var _font: Font
var _map: Control


func _ready() -> void:
	_font = UI.font("wide", 0.0, 1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map = Control.new()
	_map.show_behind_parent = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.draw.connect(_draw_map)
	add_child(_map)
	visibility_changed.connect(_map.queue_redraw)


func _process(dt: float) -> void:
	_t += dt
	_sel_t += dt
	if is_visible_in_tree():
		queue_redraw()


func _to_px(lon: float, lat: float) -> Vector2:
	var w := (LON.y - LON.x) * K
	var h := LAT.y - LAT.x
	var s := minf((size.x - 20.0) / w, (size.y - 20.0) / h)
	var off := (size - Vector2(w, h) * s) / 2.0
	return off + Vector2((lon - LON.x) * K, LAT.y - lat) * s


func _draw_map() -> void:
	var m := _map
	m.draw_style_box(UI.panel_box(0.86), Rect2(Vector2.ZERO, size))
	for poly in MapData.GERMANY:
		var pts := PackedVector2Array()
		for i in range(0, poly.size(), 2):
			pts.append(_to_px(poly[i], poly[i + 1]))
		if pts.size() >= 3:
			var tri := Geometry2D.triangulate_polygon(pts)
			if not tri.is_empty():
				m.draw_colored_polygon(pts, Color(1, 1, 1, 0.035))
			pts.append(pts[0])
			m.draw_polyline(pts, Color(1, 1, 1, 0.34), 1.0, true)
	# Städte: Stand je Stadt (gewonnen > frei > gesperrt)
	var towns := {}  # Stadt -> [Position, Stand]
	for ev in Catalog.CAREER:
		var r: Dictionary = Catalog.RACES[Catalog.race_index(ev)]
		var p := _to_px(r["geo"].y, r["geo"].x)
		var state := 0
		if GameState.career_open(ev):
			state = 2 if r["name"] in GameState.won_events else 1
		var town: String = r.get("town", "")
		towns[town] = [p, maxi(state, towns.get(town, [p, 0])[1])]
	for town in towns:
		var p: Vector2 = towns[town][0]
		var st: int = towns[town][1]
		var col: Color = [UI.FAINT, Color(0.86, 0.88, 0.92), UI.GOLD][st]
		m.draw_circle(p, 3.2, Color(0, 0, 0, 0.6))
		m.draw_circle(p, 2.2, col)


func _draw() -> void:
	var sel_town := ""
	var sel_pos := Vector2.ZERO
	if selected != "":
		var sr: Dictionary = Catalog.RACES[Catalog.race_index(selected)]
		sel_town = sr.get("town", "")
		sel_pos = _to_px(sr["geo"].y, sr["geo"].x)
	if sel_town == "":
		return
	# Ring zieht sich beim Wechsel von groß auf seine Größe zusammen, danach atmet er langsam (kein Blinken)
	var k := 1.0 - pow(1.0 - clampf(_sel_t / 0.3, 0.0, 1.0), 3.0)
	var breathe := 0.5 + 0.5 * sin(_t * 2.2)
	var r := lerpf(14.0, 6.0, k) + breathe * 0.8
	draw_arc(sel_pos, r, 0.0, TAU, 32, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, (0.65 + 0.3 * breathe) * k), 1.2, true)
	draw_circle(sel_pos, 2.6, UI.TEXT)
	var label := sel_town.to_upper()
	var fs := 7
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var lp := sel_pos + Vector2(11, -6)
	if lp.x + tw + 8.0 > size.x - 4.0:
		lp.x = sel_pos.x - 11.0 - tw - 8.0
	var box := Rect2(lp, Vector2(tw + 8.0, fs + 6.0))
	draw_style_box(UI.flat(Color(0.02, 0.023, 0.03, 0.9), UI.LINE_HI, 1, 2), box)
	draw_string(_font, Vector2(box.position.x + 4.0, box.position.y + (box.size.y + fs * UI.CAP) / 2.0), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, k))
