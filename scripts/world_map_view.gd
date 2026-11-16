extends Control
## Große Karte der Open World (Tab oder Esc-Menü > Karte): Ring, Auffahrten und alle Straßen der Städte, die Rennen
## als Punkte in der Farbe ihrer Art (gewonnen golden, gesperrt grau), du als Pfeil. Links/rechts wählt eine Stadt,
## Leertaste reist dorthin (an den Stadteingang, nicht an ein Rennen: seit 2.33), Enter setzt das nächste offene Rennen
## der Stadt als Ziel (Flagge auf der Minikarte), Tab/Esc schließt.

const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

signal target_chosen(race_index: int)
signal fast_travel(race_index: int)
signal closed

var roads: Array = []  # [[Linienzug Welt x, z], Art]
var pins: Array = []  # {race_index, pos (Vector3), town}
var towns: Array = []  # {name, pins: [Index in pins], pos (Vector3)}; Auswahl und Schnellreise gehen nach Städten
var player: Node3D
var target := -1
var sel := 0  # gewählte Stadt (towns)

var relief: Texture2D  # Reliefkarte der Landschaft (Landscape.map_texture)
var villages: Array = []  # [Lage, Name]
var areas: Array = []  # Gelände (seit 2.39, world._offroad_map): [Umriss, Farbe, Name, Teiche]
var center_town: Array = []  # [Lage, Name] der Stadt in der Mitte
var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _cond: Font
var _wide: Font
var _title_font: Font
var _small: Font
var _small_spaced: Font
var _body: Font


func setup(roads_: Array, cities: Array, player_: Node3D) -> void:
	roads = roads_
	player = player_
	_cond = UI.font("cond", 0.0, 1)
	_wide = UI.font("wide", 0.0, 1)
	_title_font = UI.font("cond", 0.0, 1)
	_small = UI.font("bold", 0.0)
	_small_spaced = UI.font("wide", 0.0, 1)
	_body = UI.font("bold", 0.0)
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
	for i in pins.size():
		var name: String = pins[i]["town"]
		var t := -1
		for k in towns.size():
			if towns[k]["name"] == name:
				t = k
		if t < 0:
			towns.append({"name": name, "pins": [], "pos": pins[i]["pos"]})
			t = towns.size() - 1
		towns[t]["pins"].append(i)


## Stadt, in der Rennen ri liegt (-1: keine)
func town_of(ri: int) -> int:
	for k in towns.size():
		for i in towns[k]["pins"]:
			if pins[i]["race_index"] == ri:
				return k
	return -1


## Rennen, an dessen Ausfahrt die Schnellreise in Stadt k ankommt (das erste der Stadt)
func travel_race(k: int) -> int:
	return pins[towns[k]["pins"][0]]["race_index"]


## Nächstes Ziel in Stadt k: das erste offene, noch nicht gewonnene Rennen, sonst das erste
func target_race(k: int) -> int:
	for i in towns[k]["pins"]:
		var name: String = Catalog.RACES[pins[i]["race_index"]]["name"]
		if GameState.career_open(name) and not name in GameState.won_events:
			return pins[i]["race_index"]
	return travel_race(k)


## Welt (x, z) -> Bildschirm: Karte füllt die Fläche links (rechts steht das Infofeld), Norden oben
func _to_screen(p: Vector2) -> Vector2:
	var area := Rect2(Vector2(28, 54), Vector2(size.x * 0.68 - 56, size.y - 102))
	var ext := _hi - _lo
	var k := minf(area.size.x / ext.x, area.size.y / ext.y)
	var off := area.position + (area.size - ext * k) / 2.0
	return off + (p - _lo) * k


func open(select := -1) -> void:
	visible = true
	if select >= 0 and town_of(select) >= 0:
		sel = town_of(select)
	else:
		# nächste Stadt vorauswählen
		var best := 1e9
		for k in towns.size():
			var d: float = (towns[k]["pos"] as Vector3).distance_to(player.global_position)
			if d < best:
				best = d
				sel = k
	queue_redraw()


func _process(_dt: float) -> void:
	if visible:
		queue_redraw()


func _handle(event: InputEvent) -> bool:
	if not visible:
		return false
	if towns.is_empty():
		return false
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		sel = (sel + 1) % towns.size()
		Sfx.ui("move")
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		sel = (sel - 1 + towns.size()) % towns.size()
		Sfx.ui("move")
	elif event.is_action_pressed("handbrake"):
		# Leertaste: Schnellreise an den Eingang dieser Stadt (seit 2.31). Muss vor ui_accept stehen: Godots ui_accept
		# enthält die Leertaste auch, bis 2.31 schaltete sie deshalb nur das Ziel um und die Schnellreise kam nie dran.
		# vor dem Signal: der Szenenwechsel nimmt die Karte sofort aus dem Baum (danach gibt es kein Viewport mehr)
		get_viewport().set_input_as_handled()
		Sfx.ui("go")
		fast_travel.emit(travel_race(sel))
		return true
	elif event.is_action_pressed("ui_accept"):
		var ri := target_race(sel)
		target = -1 if town_of(target) == sel else ri
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
	# seit 2.35 im Menü-Look: deckender dunkler Grund (das HUD schimmert nicht durch), Titel mit Akzentstrich,
	# Karte und Infofeld als Glasflächen mit Haarlinie
	draw_rect(Rect2(Vector2.ZERO, size), UI.INK)
	draw_string(_title_font, Vector2(20, 30), tr("KARTE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.TEXT)
	draw_rect(Rect2(21, 37, 14, 2), UI.ACCENT)
	draw_rect(Rect2(38, 37.5, size.x * 0.68 - 58.0, 1), UI.LINE)
	var area := Rect2(Vector2(20, 46), Vector2(size.x * 0.68 - 40, size.y - 86))
	draw_style_box(UI.panel_box(0.6), area)
	if relief:
		var a := _to_screen(_lo)
		var b := _to_screen(_hi)
		draw_texture_rect(relief, Rect2(a, b - a), false, Color(0.72, 0.75, 0.82, 0.7))
	# Dörfer: kleine Punkte mit Namen (klein, grau)
	for v in villages:
		var vp := _to_screen(v[0])
		draw_rect(Rect2(vp - Vector2(1.5, 1.5), Vector2(3, 3)), Color(UI.DIM.r, UI.DIM.g, UI.DIM.b, 0.6))
		draw_string(_small, vp + Vector2(5, 3), v[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(UI.DIM.r, UI.DIM.g, UI.DIM.b, 0.55))
	# Gelände: getönte Fläche mit Namen (wie die Dörfer, etwas heller)
	for ar in areas:
		var pl := PackedVector2Array()
		var mid := Vector2.ZERO
		for q in ar[0]:
			pl.append(_to_screen(q))
			mid += q / float((ar[0] as PackedVector2Array).size())
		draw_colored_polygon(pl, ar[1])
		for pd in ar[3]:
			var pp := PackedVector2Array()
			for q in pd:
				pp.append(_to_screen(q))
			draw_colored_polygon(pp, Color(0.12, 0.35, 0.75, 0.75))
		var mp := _to_screen(mid)
		draw_string(_small, mp + Vector2(8, 3), str(ar[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.7))
	if not center_town.is_empty():
		var cp := _to_screen(center_town[0])
		draw_circle(cp, 18.0, Color(1, 1, 1, 0.05))
		draw_string(_wide, cp + Vector2(22, -10), center_town[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.75))
	# Straßen: erst dunkle Ränder, dann helle Linien (Ring etwas kräftiger)
	for pass_i in 2:
		for r in roads:
			var pts := PackedVector2Array()
			for q in r[0]:
				pts.append(_to_screen(q))
			if pts.size() < 2:
				continue
			var kind: int = r[1]
			if pass_i == 0:
				draw_polyline(pts, Color(0, 0, 0, 0.45), 4.0 if kind == 0 else 3.0, true)
			else:
				var col := Color(0.9, 0.92, 0.96, 0.9) if kind == 0 else (Color(0.78, 0.81, 0.87, 0.7) if kind == 1 else Color(0.62, 0.66, 0.73, 0.4))
				draw_polyline(pts, col, 1.5 if kind == 0 else 1.1, true)
	# Rennen (Ortsnamen je Stadt nur, wo Platz ist; die gewählte zuerst)
	var taken := []
	var order := range(towns.size())
	order.erase(sel)
	order.push_front(sel)
	var labels := {}
	for k in order:
		var tp: Vector3 = towns[k]["pos"]
		var lp := _to_screen(Vector2(tp.x, tp.z)) + Vector2(10, 4)
		var r := Rect2(lp - Vector2(0, 9), Vector2(_wide.get_string_size(str(towns[k]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x, 11))
		var free := true
		for t in taken:
			if t.intersects(r.grow(2.0)):
				free = false
		if free:
			taken.append(r)
			labels[towns[k]["pins"][0]] = true
	var sel_pins: Array = towns[sel]["pins"] if not towns.is_empty() else []
	var breathe := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0022)
	for i in pins.size():
		var p: Dictionary = pins[i]
		var race: Dictionary = Catalog.RACES[p["race_index"]]
		var sp := _to_screen(Vector2(p["pos"].x, p["pos"].z))
		var won: bool = race["name"] in GameState.won_events
		var open_: bool = GameState.career_open(race["name"])
		var col: Color = UI.TYPE_COL.get(race.get("type", "sprint"), UI.CYAN)
		if not open_:
			col = UI.FAINT
		if won:
			# erledigt: kleiner goldener Haken statt Punkt (in der Welt gibt es dort keinen Marker mehr)
			draw_circle(sp, 4.5, Color(0, 0, 0, 0.8))
			draw_polyline(PackedVector2Array([sp + Vector2(-2.6, 0), sp + Vector2(-0.8, 2.2), sp + Vector2(3, -2.6)]),
				UI.GOLD, 1.5, true)
		else:
			draw_circle(sp, 5.2, Color(0, 0, 0, 0.85))
			draw_circle(sp, 3.8, col)
		if p["race_index"] == target:
			draw_arc(sp, 10.0, 0.0, TAU, 24, UI.TEXT, 1.2, true)
		if i in sel_pins:
			draw_arc(sp, 13.0 + breathe, 0.0, TAU, 28, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.6 + 0.35 * breathe), 1.5, true)
		if labels.has(i):
			draw_string(_wide, sp + Vector2(10, 4), str(p["town"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 7,
				Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.95 if i in sel_pins else 0.5))
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
	draw_style_box(UI.panel_box(0.9), Rect2(x, 46, w, size.y - 86))
	if towns.is_empty():
		return
	var town: Dictionary = towns[sel]
	var y := 66.0
	var ix := x + 14.0
	var iw := w - 28.0
	draw_string(_small_spaced, Vector2(ix, y), tr("STADT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 6, UI.FAINT)
	y += 20
	# Name passt immer: erst kleiner, sonst zweizeilig (bis 2.34 wurde "FRANKFURT AM MAIN" abgeschnitten)
	var name := str(town["name"]).to_upper()
	var fs := 18
	while fs > 12 and _title_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > iw:
		fs -= 1
	if _title_font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > iw:
		draw_multiline_string(_title_font, Vector2(ix, y), name, HORIZONTAL_ALIGNMENT_LEFT, iw, fs, 2, UI.TEXT)
		y += fs + 2
	else:
		draw_string(_title_font, Vector2(ix, y), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT)
	draw_rect(Rect2(ix, y + 7, 14, 2), UI.ACCENT)
	y += 22
	var km := (town["pos"] as Vector3).distance_to(player.global_position) / 1000.0 if player else 0.0
	draw_string(_body, Vector2(ix, y), tr("Luftlinie: %.1f km") % km, HORIZONTAL_ALIGNMENT_LEFT, iw, 8, UI.DIM)
	y += 26
	# Rennen der Stadt: Art, Name, Stand (gewonnen, offen, ab Level n), Bestwert
	for i in town["pins"]:
		var race: Dictionary = Catalog.RACES[pins[i]["race_index"]]
		var type: String = race.get("type", "sprint")
		var name_r: String = race["name"]
		var won: bool = name_r in GameState.won_events
		var open_: bool = GameState.career_open(name_r)
		var col: Color = UI.TYPE_COL.get(type, UI.CYAN) if open_ else UI.FAINT
		draw_circle(Vector2(ix + 3, y - 3.5), 2.6, UI.GOLD if won else col)
		draw_string(_cond, Vector2(ix + 12, y), tr(name_r).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, iw - 12, 10,
			UI.TEXT if open_ else UI.DIM)
		y += 13
		var status := tr("GEWONNEN") if won else (tr("OFFEN") if open_ else GameState.lock_text(name_r).to_upper())
		status = tr({"sprint": "SPRINT", "circuit": "RUNDKURS", "drift": "DRIFT"}.get(type, "")) + "  ·  " + status
		if GameState.best_times.has(name_r):
			var t: float = GameState.best_times[name_r]
			status += "  ·  " + ("%d P" % int(t) if type == "drift" else "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)])
		draw_string(_small_spaced, Vector2(ix + 12, y), status, HORIZONTAL_ALIGNMENT_LEFT, iw - 12, 6,
			UI.GOLD if won else UI.DIM)
		y += 20
	# Tasten als Kappen (aus dem übersetzten Hinweistext: "Taste: Wort" bzw. "←/→ Wort")
	var hint := tr("←/→ Stadt wählen\nLeertaste: Schnellreise\nEnter: Rennen als Ziel\nM / Esc: zurück")
	if town_of(target) == sel:
		hint = tr("Ziel gesetzt. Enter: Ziel löschen\nLeertaste: Schnellreise\nM / Esc: zurück")
	var lines := hint.split("\n")
	var yy := size.y - 46.0 - lines.size() * 15.0
	draw_rect(Rect2(ix, yy - 9, iw, 1), UI.LINE)
	for line in lines:
		var key := ""
		var word := line
		var c := line.find(": ")
		if c >= 0:
			key = line.substr(0, c)
			word = line.substr(c + 2)
		elif line.begins_with("←/→ "):
			key = "←/→"
			word = line.substr(4)
		if key.contains(". "):
			# "Ziel gesetzt. Enter" -> Satz vorn als Text, Taste dahinter
			var dot := key.rfind(". ")
			draw_string(_body, Vector2(ix, yy + 9), key.substr(0, dot + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 8, UI.TEXT)
			var pre := _body.get_string_size(key.substr(0, dot + 2), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
			UI.draw_hint(self, Vector2(ix + pre + 2.0, yy), key.substr(dot + 2).to_upper(), word, 6)
		elif key != "":
			UI.draw_hint(self, Vector2(ix, yy), key.to_upper().replace(" / ", " "), word, 6)
		else:
			draw_string(_body, Vector2(ix, yy + 9), line, HORIZONTAL_ALIGNMENT_LEFT, iw, 8, UI.DIM)
		yy += 15.0
