extends Control
## Große Karte der Open World (Tab oder Esc-Menü > Karte): Ring, Auffahrten und alle Straßen der Städte, die Rennen
## als Punkte in der Farbe ihrer Art (gewonnen golden, gesperrt grau), du als Pfeil. Links/rechts wählt ein Rennen,
## Enter setzt es als Ziel (Flagge auf der Minikarte), Tab/Esc schließt.

const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

signal target_chosen(race_index: int)
signal closed

var roads: Array = []  # [[Linienzug Welt x, z], Art]
var pins: Array = []  # {race_index, pos (Vector3), town}
var player: Node3D
var target := -1
var sel := 0

var relief: Texture2D  # Reliefkarte der Landschaft (Landscape.map_texture)
var villages: Array = []  # [Lage, Name]
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _cond: Font
var _wide: Font


func setup(roads_: Array, cities: Array, player_: Node3D) -> void:
	roads = roads_
	player = player_
	_cond = UI.font("cond", 0.2)
	_wide = UI.font("wide", 0.15)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_lo = Vector2(1e9, 1e9)
	_hi = Vector2(-1e9, -1e9)
	for r in roads:
		for q in r[0]:
			_lo = Vector2(minf(_lo.x, q.x), minf(_lo.y, q.y))
			_hi = Vector2(maxf(_hi.x, q.x), maxf(_hi.y, q.y))
	for c in cities:
		pins.append({"race_index": c["race_index"], "pos": c["start_world"], "town": Catalog.RACES[c["race_index"]].get("town", ""),
			"phi": c["phi_w"]})
	pins.sort_custom(func(a, b): return a["phi"] < b["phi"])


## Welt (x, z) -> Bildschirm: Karte füllt die Fläche links (rechts steht das Infofeld), Norden oben
func _to_screen(p: Vector2) -> Vector2:
	var area := Rect2(Vector2(20, 40), Vector2(size.x * 0.68 - 40, size.y - 80))
	var ext := _hi - _lo
	var k := minf(area.size.x / ext.x, area.size.y / ext.y)
	var off := area.position + (area.size - ext * k) / 2.0
	return off + (p - _lo) * k


func open(select := -1) -> void:
	visible = true
	if select >= 0:
		for i in pins.size():
			if pins[i]["race_index"] == select:
				sel = i
	else:
		# nächstes Rennen vorauswählen
		var best := 1e9
		for i in pins.size():
			var d: float = (pins[i]["pos"] as Vector3).distance_to(player.global_position)
			if d < best:
				best = d
				sel = i
	queue_redraw()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _handle(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		sel = (sel + 1) % pins.size()
		Sfx.ui("move")
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		sel = (sel - 1 + pins.size()) % pins.size()
		Sfx.ui("move")
	elif event.is_action_pressed("ui_accept"):
		var ri: int = pins[sel]["race_index"]
		target = -1 if target == ri else ri
		target_chosen.emit(target)
		Sfx.ui("go")
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("map") or event.is_action_pressed("pause"):
		visible = false
		closed.emit()
	else:
		return false
	get_viewport().set_input_as_handled()
	queue_redraw()
	return true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.94))
	draw_rect(Rect2(0, 0, size.x, 2), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.8))
	draw_string(_wide, Vector2(20, 28), tr("KARTE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UI.CYAN)
	if relief:
		var a := _to_screen(_lo)
		var b := _to_screen(_hi)
		draw_texture_rect(relief, Rect2(a, b - a), false, Color(1, 1, 1, 0.85))
	# Dörfer: kleine Punkte mit Namen (klein, grau)
	for v in villages:
		var vp := _to_screen(v[0])
		draw_rect(Rect2(vp - Vector2(2, 2), Vector2(4, 4)), Color(0.75, 0.6, 0.45, 0.8))
		draw_string(_cond, vp + Vector2(5, 3), v[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.7, 0.72, 0.78, 0.55))
	# Straßen: erst Ränder, dann helle Linien (Ring etwas kräftiger)
	for pass_i in 2:
		for r in roads:
			var pts := PackedVector2Array()
			for q in r[0]:
				pts.append(_to_screen(q))
			if pts.size() < 2:
				continue
			var kind: int = r[1]
			if pass_i == 0:
				draw_polyline(pts, Color(0.35, 0.5, 0.7, 0.35), 4.0 if kind == 0 else 3.0, true)
			else:
				var col := Color(0.92, 0.95, 1.0, 0.9) if kind == 0 else (Color(0.78, 0.82, 0.9, 0.75) if kind == 1 else Color(0.6, 0.65, 0.75, 0.4))
				draw_polyline(pts, col, 1.6 if kind == 0 else 1.2, true)
	# Rennen (Ortsnamen nur, wo Platz ist; das gewählte zuerst)
	var taken := []
	var order := range(pins.size())
	order.erase(sel)
	order.push_front(sel)
	var labels := {}
	for i in order:
		var p0: Dictionary = pins[i]
		var lp := _to_screen(Vector2(p0["pos"].x, p0["pos"].z)) + Vector2(10, 4)
		var r := Rect2(lp - Vector2(0, 10), Vector2(_cond.get_string_size(str(p0["town"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x, 12))
		var free := true
		for t in taken:
			if t.intersects(r.grow(2.0)):
				free = false
		if free:
			taken.append(r)
			labels[i] = true
	for i in pins.size():
		var p: Dictionary = pins[i]
		var race: Dictionary = Catalog.RACES[p["race_index"]]
		var sp := _to_screen(Vector2(p["pos"].x, p["pos"].z))
		var won: bool = race["name"] in GameState.won_events
		var open_: bool = GameState.career_open(race["name"])
		var col: Color = UI.TYPE_COL.get(race.get("type", "sprint"), UI.CYAN)
		if not open_:
			col = Color(0.4, 0.42, 0.48)
		if won:
			# erledigt: kleiner goldener Haken statt Punkt (in der Welt gibt es dort keinen Marker mehr)
			draw_circle(sp, 5.0, Color(0, 0, 0, 0.85))
			draw_polyline(PackedVector2Array([sp + Vector2(-3, 0), sp + Vector2(-1, 2.5), sp + Vector2(3.5, -3)]),
				Color(1.0, 0.8, 0.2), 1.8, true)
		else:
			draw_circle(sp, 7.0, Color(0, 0, 0, 0.9))
			draw_circle(sp, 5.2, col)
		if p["race_index"] == target:
			draw_arc(sp, 12.0, 0.0, TAU, 24, Color.WHITE, 1.5, true)
		if i == sel:
			var a := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
			draw_arc(sp, 15.0, 0.0, TAU, 28, Color(col.r, col.g, col.b, a), 2.5, true)
		if labels.has(i):
			draw_string(_cond, sp + Vector2(10, 4), str(p["town"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
				Color(0.85, 0.9, 1.0, 0.95 if i == sel else 0.55))
	# du
	if player:
		var pp := _to_screen(Vector2(player.global_position.x, player.global_position.z))
		var f3: Vector3 = -player.global_basis.z
		var ang := Vector2(f3.x, f3.z).angle() + PI / 2.0
		var tri := PackedVector2Array([Vector2(0, -9), Vector2(6.5, 6), Vector2(0, 2.5), Vector2(-6.5, 6)])
		var xf := Transform2D(ang, pp)
		draw_colored_polygon(xf * tri, Color(1.0, 0.85, 0.15))
		draw_polyline(xf * PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.5, true)
	_draw_info()


func _draw_info() -> void:
	var x := size.x * 0.68
	var w := size.x - x - 20
	draw_rect(Rect2(x, 40, w, size.y - 80), Color(0.03, 0.05, 0.1, 0.8))
	if pins.is_empty():
		return
	var p: Dictionary = pins[sel]
	var race: Dictionary = Catalog.RACES[p["race_index"]]
	var type: String = race.get("type", "sprint")
	var col: Color = UI.TYPE_COL.get(type, UI.CYAN)
	var y := 70.0
	draw_string(_wide, Vector2(x + 12, y), tr({"sprint": "SPRINT", "circuit": "RUNDKURS", "drift": "DRIFT"}.get(type, "")),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	y += 30
	draw_string(_cond, Vector2(x + 12, y), tr(race["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w - 24, 22, Color.WHITE)
	y += 22
	draw_string(_cond, Vector2(x + 12, y), str(race.get("town", "")), HORIZONTAL_ALIGNMENT_LEFT, w - 24, 14, UI.CYAN)
	y += 30
	var name: String = race["name"]
	var status := ""
	if name in GameState.won_events:
		status = tr("GEWONNEN")
	elif not GameState.career_open(name):
		var s := Catalog.stage_of(name)
		status = tr("GESPERRT: %d Siege in Stufe „%s“") % [Catalog.stage_need(s - 1), tr(Catalog.STAGES[s - 1]["name"])] if s > 0 else tr("GESPERRT")
	else:
		status = tr("OFFEN")
	draw_string(_cond, Vector2(x + 12, y), status, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 13,
		Color(1.0, 0.8, 0.2) if name in GameState.won_events else Color(0.85, 0.9, 1.0))
	y += 22
	if GameState.best_times.has(name) and type != "drift":
		var t: float = GameState.best_times[name]
		draw_string(_cond, Vector2(x + 12, y), tr("Bestzeit: ") + "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)],
			HORIZONTAL_ALIGNMENT_LEFT, w - 24, 13, Color(0.85, 0.9, 1.0))
	y += 22
	var km := (p["pos"] as Vector3).distance_to(player.global_position) / 1000.0 if player else 0.0
	draw_string(_cond, Vector2(x + 12, y), tr("Luftlinie: %.1f km") % km, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 13, Color(0.7, 0.75, 0.85))
	var hint := tr("←/→ Rennen wählen\nEnter: als Ziel setzen (Flagge auf der Minikarte)\nM / Esc: zurück")
	if target == p["race_index"]:
		hint = tr("Ziel gesetzt. Enter: Ziel löschen\nM / Esc: zurück")
	var yy := size.y - 110
	for line in hint.split("\n"):
		draw_string(_cond, Vector2(x + 12, yy), line, HORIZONTAL_ALIGNMENT_LEFT, w - 24, 11, Color(0.75, 0.8, 0.9, 0.85))
		yy += 16
