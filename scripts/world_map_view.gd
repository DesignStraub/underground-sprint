extends Control
## Große Karte der Open World (M/Tab, Esc-Menü > Karte). Seit 2.49 neu; bis 2.48 stand die ganze Welt klein und dunkel
## auf einmal da, ohne Zoom. Jetzt Vollbild, beim Öffnen nah um dein Auto:
## - Zoom: Mausrad (zum Mauszeiger hin), Bild↑/↓ oder +/−, Trackpad mit zwei Fingern oder Spreizen, Gamepad-Trigger.
## - Verschieben: WASD, Pfeiltasten, linker Stick oder mit der Maus ziehen. H holt dich zurück in die Mitte.
## - Städte als bebaute Flächen entlang ihrer Straßen, nah mit Häusern (OpenStreetMap bzw. Blöcke der erfundenen Städte);
##   noch nicht entdeckte Städte dunkler. Gelände, Dörfer und Seen als Flächen, die Autobahn kräftig, Stadtstraßen fein.
##   Je näher, desto mehr: einzelne Rennen statt eines Punkts je Stadt, Dorfnamen, Viertel der geladenen Städte.
## - Springen (Leertaste, Doppelklick oder Knopf im Infofeld) geht an jeden Ort, an dem man schon war: Stadteingang,
##   Tor eines Geländes, Start eines Autobahn-Rennens. Q/E (Schultertasten) wechselt den Ort, ein Klick wählt ihn,
##   Enter setzt ihn als Ziel (Flagge auf der Minikarte), M/Esc schließt.
## Zeichnen: Flächen und Straßen einmal in Weltkoordinaten auf einem Node2D, das je Bild nur verschoben und skaliert wird
## (wie die Minikarte); neu gezeichnet nur, wenn sich der Zoom um eine Stufe ändert (Straßenbreiten). Namen, Symbole
## und das Infofeld je Bild in Bildschirmkoordinaten.

const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

signal target_chosen(race_index: int)  # Rennen als Ziel (-1: keins)
signal target_pos_chosen(pos: Vector3, on: bool)  # Ort ohne Rennen als Ziel (Gelände, Autobahn-Rennen)
signal jump(xf: Transform3D)  # Springen: Welt neu laden, Ankunft hier
signal closed

const Z_MAX := 1.2  # HUD-Bildpunkte (Karte 640 breit) je Meter: gut 500 m im Bild
const Z_OPEN := 0.22  # beim Öffnen: knapp 3 km um das Auto
const Z_PINS := 0.075  # ab hier jedes Rennen einzeln
const Z_VILLAGES := 0.05  # Dorfnamen
const Z_DISTRICTS := 0.26  # Viertel der geladenen Städte
const Z_HOUSES := 0.13  # Häuser und Blöcke der Städte
const LOD_STEP := 1.5  # Straßenbreiten je Faktor 1,5 Zoom neu zeichnen
const PAN_SPEED := 280.0  # Bildpunkte je Sekunde (Tasten, Stick)
const WHEEL_K := 1.25  # Zoom je Rastung des Mausrads
const KEY_K := 1.7  # Zoom je Tastendruck

const COL_BG := Color(0.028, 0.034, 0.042)
const COL_LAND := Color(0.064, 0.08, 0.087)
const COL_WATER := Color(0.075, 0.19, 0.33)
const COL_WATER_EDGE := Color(0.22, 0.42, 0.64)
const COL_TOWN := Color(0.155, 0.168, 0.192)  # bebaute Fläche einer entdeckten Stadt
const COL_TOWN_NEW := Color(0.105, 0.115, 0.13)  # noch nicht entdeckt
const COL_HOUSE := Color(0.235, 0.25, 0.28)
const COL_HOUSE_NEW := Color(0.15, 0.16, 0.175)
const COL_VILLAGE := Color(0.115, 0.125, 0.13)
const COL_AB := Color(0.97, 0.7, 0.26)  # Autobahn
const COL_RAMP := Color(0.86, 0.68, 0.4)  # Auffahrten, Verbindungen
const COL_CASE := Color(0.012, 0.015, 0.02)
const COL_ST := [Color(0.88, 0.9, 0.94), Color(0.66, 0.69, 0.76), Color(0.47, 0.5, 0.57)]  # Haupt, Abzweig, Sackgasse
const COL_HW := Color(0.35, 0.62, 1.0)  # Autobahn-Rennen (blaue Säule)
const COL_PLAYER := Color(1.0, 0.85, 0.15)

var player: Node3D
var target := -1  # Rennen als Ziel
var target_pos := Vector3.ZERO  # Ort ohne Rennen als Ziel
var has_target_pos := false
var relief: Texture2D  # Reliefkarte der Landschaft (Landscape.map_texture über relief_lo..relief_hi)
var relief_lo := Vector2.ZERO
var relief_hi := Vector2.ZERO
var villages: Array = []  # [Lage, Name]
var areas: Array = []  # Gelände (world._offroad_map): [Umriss, Farbe, Name, Teiche]
var center_town: Array = []  # [Lage, Name] der Stadt in der Mitte
var lakes: Array = []  # [Mitte, Radius]
var district_fn: Callable  # [[Lage, Name]] der Viertel geladener Städte (world._map_districts), beim Öffnen

var pins: Array = []  # Rennen: {race_index, pos (Vector3), town, phi}
var towns: Array = []  # {name, pins: [Index in pins], pos (Vector3), mid (Vector2)}
var places: Array = []  # Sprungziele: {kind "town"/"area"/"hw", name, key, pos (Vector2), xf, town, hw, akind}
var sel := 0  # gewählter Ort (places)

var _lo := Vector2.ZERO
var _hi := Vector2.ZERO
var _ab: Array = []  # Autobahn (Linienzüge Welt x, z)
var _ramps: Array = []  # Auffahrten, Verbindungen, Zufahrten der Gelände
var _streets: Array = [[], [], []]  # Stadtstraßen je Art
var _cities: Array = []  # je Strecke einer Stadt: {town (Index), lines, houses (PackedVector2Array), blocks (PackedVector3Array)}
var _area_mid: Array = []  # Mitte je Gelände (Name dort)
var _districts: Array = []
var _base: Node2D
var _over: Control
var _ui: Control
var _center := Vector2.ZERO  # Weltpunkt (x, z) in der Bildmitte
var _zoom := Z_OPEN
var _zoom_to := Z_OPEN
var _z_min := 0.02
var _anchor := Vector2.ZERO  # Bildpunkt, der beim weichen Zoomen an seiner Stelle bleibt
var _glide_to := Vector2.ZERO
var _gliding := false
var _lod := -999
var _lod_zoom := 1.0
var _drag := false
var _drag_from := Vector2.ZERO
var _drag_center := Vector2.ZERO
var _moved := false
var _mouse := Vector2(-1000, -1000)
var _hover := -1
var _btns: Array = []  # Knöpfe im Infofeld: [Rect2, Aktion]
var _deny_t := 0.0  # Springen an einen noch nicht entdeckten Ort: Hinweis leuchtet kurz auf
var _f_title: Font
var _f_town: Font
var _f_wide: Font
var _f_small: Font
var _f_body: Font


func setup(layout: Dictionary, player_: Node3D, hw_defs: Array, gate_fn: Callable, area_gate_fn: Callable) -> void:
	player = player_
	_f_title = UI.font("cond", 0.0, 1)
	_f_town = UI.font("wide", 0.0, 2)
	_f_wide = UI.font("wide", 0.0, 1)
	_f_small = UI.font("bold", 0.0, 1)
	_f_body = UI.font("bold", 0.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	clip_contents = true
	# Straßen sortieren: Autobahn, Auffahrten und Verbindungen, Stadtstraßen je Art
	var city_roads := {}
	for c in layout["cities"]:
		for rd in c["roads"]:
			city_roads[rd[0]] = true
	_lo = Vector2(1e9, 1e9)
	_hi = Vector2(-1e9, -1e9)
	for rd in layout["roads"]:
		var pl: PackedVector2Array = rd[0]
		if pl.size() < 2:
			continue
		for q in pl:
			_lo = _lo.min(q)
			_hi = _hi.max(q)
		if city_roads.has(pl):
			continue
		if int(rd[1]) == 0:
			_ab.append(pl)
		else:
			_ramps.append(pl)
	relief_lo = _lo - Vector2(1500, 1500)
	relief_hi = _hi + Vector2(1500, 1500)
	# Rennen, nach Städten gruppiert (Reihenfolge um den Ring)
	for c in layout["cities"]:
		var ri: int = c["race_index"]
		pins.append({"race_index": ri, "pos": c["start_world"], "town": str(Catalog.RACES[ri].get("town", "")),
			"phi": float(c["phi_w"])})
	pins.sort_custom(func(a, b): return a["phi"] < b["phi"])
	for i in pins.size():
		var name: String = pins[i]["town"]
		var t := _town_index(name)
		if t < 0:
			towns.append({"name": name, "pins": [], "pos": pins[i]["pos"]})
			t = towns.size() - 1
		towns[t]["pins"].append(i)
	# Flächen je Strecke: Straßen, Häuser (echte Städte: OpenStreetMap), Blöcke (erfundene Städte)
	for c in layout["cities"]:
		var t := _town_index(str(Catalog.RACES[c["race_index"]].get("town", "")))
		var lines := []
		for rd in c["roads"]:
			var pl: PackedVector2Array = rd[0]
			if pl.size() < 2:
				continue
			lines.append(pl)
			_streets[clampi(int(rd[1]), 0, 2)].append(pl)
		_cities.append({"town": t, "lines": lines, "houses": c.get("bld_world", PackedVector2Array()),
			"blocks": c.get("fill_world", PackedVector3Array())})
		var cen: Vector3 = c["center"]
		if t >= 0 and not towns[t].has("mid"):
			towns[t]["mid"] = Vector2(cen.x, cen.z)
	# Sprungziele: Städte (Eingang), Gelände (Tor), Autobahn-Rennen (Start)
	for k in towns.size():
		var ri: int = travel_race(k)
		places.append({"kind": "town", "name": str(towns[k]["name"]), "key": "", "town": k, "pos": towns[k].get("mid", Vector2.ZERO),
			"xf": gate_fn.call(ri)})
	var offr: Array = layout.get("offroad", [])
	for i in offr.size():
		var a: Dictionary = offr[i]
		var gx: Transform3D = area_gate_fn.call(i)
		places.append({"kind": "area", "name": str(a["name"]), "key": "gelaende:" + str(a["name"]), "town": -1,
			"pos": Vector2(gx.origin.x, gx.origin.z), "xf": gx, "akind": str(a["kind"])})
	for i in hw_defs.size():
		var h: Dictionary = hw_defs[i]
		var sx: Transform3D = h["start_xf"]
		# Ankunft 60 m vor der blauen Säule, in Fahrtrichtung: man sieht den Start vor sich
		var ax := Transform3D(sx.basis, sx.origin + sx.basis.z * 60.0 + Vector3(0, 0.5, 0))
		places.append({"kind": "hw", "name": str(h["name"]), "key": "hw:" + str(h["name"]), "town": -1,
			"pos": Vector2(sx.origin.x, sx.origin.z), "xf": ax, "hw": i})
	# Reihenfolge für Q/E: im Uhrzeigersinn um die Mitte der Welt, oben beginnend
	var mid := (_lo + _hi) / 2.0
	places.sort_custom(func(a, b): return _ang(a["pos"] - mid) < _ang(b["pos"] - mid))
	_base = Node2D.new()
	_base.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # Relief weich statt Pixelblöcke
	_base.draw.connect(_draw_base)
	add_child(_base)
	_over = Control.new()
	_ui = Control.new()
	for c2 in [_over, _ui]:
		(c2 as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		(c2 as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c2)
	_over.draw.connect(_draw_over)
	_ui.draw.connect(_draw_ui)
	mouse_exited.connect(func(): _mouse = Vector2(-1000, -1000))
	if OS.get_cmdline_user_args().has("--worldlog"):
		var n := 0
		for s in _streets:
			n += (s as Array).size()
		var hs := 0
		for cc in _cities:
			hs += (cc["houses"] as PackedVector2Array).size() + (cc["blocks"] as PackedVector3Array).size()
		print("KARTE %d Autobahn, %d Auffahrten, %d Stadtstraßen, %d Häuser/Blöcke, %d Sprungziele, Welt %s .. %s" % [
			_ab.size(), _ramps.size(), n, hs, places.size(), str(_lo), str(_hi)])


## Gelände: Mitte je Gelände (nach dem Setzen von areas)
func _area_mids() -> void:
	_area_mid.clear()
	for ar in areas:
		var m := Vector2.ZERO
		var pl: PackedVector2Array = ar[0]
		for q in pl:
			m += q / float(pl.size())
		_area_mid.append(m)


func _town_index(name: String) -> int:
	for k in towns.size():
		if towns[k]["name"] == name:
			return k
	return -1


static func _ang(d: Vector2) -> float:
	return fposmod(atan2(d.x, -d.y), TAU)  # 0 = Norden, im Uhrzeigersinn


## Stadt, in der Rennen ri liegt (-1: keine)
func town_of(ri: int) -> int:
	for k in towns.size():
		for i in towns[k]["pins"]:
			if pins[i]["race_index"] == ri:
				return k
	return -1


## Rennen, an dessen Eingang das Springen in Stadt k ankommt (das erste der Stadt)
func travel_race(k: int) -> int:
	return pins[towns[k]["pins"][0]]["race_index"]


## Nächstes Ziel in Stadt k: das erste offene, noch nicht gewonnene Rennen, sonst das erste
func target_race(k: int) -> int:
	for i in towns[k]["pins"]:
		var name: String = Catalog.RACES[pins[i]["race_index"]]["name"]
		if GameState.career_open(name) and not name in GameState.won_events:
			return pins[i]["race_index"]
	return travel_race(k)


## Ort i schon entdeckt? Nur dorthin geht das Springen
func known(i: int) -> bool:
	var p: Dictionary = places[i]
	if p["kind"] == "town":
		return GameState.town_known(str(p["name"]))
	return GameState.place_known(str(p["key"]))


## Ort der Stadt mit diesem Namen wählen (Tests)
func select_town(name: String) -> void:
	for i in places.size():
		if places[i]["kind"] == "town" and places[i]["name"] == name:
			sel = i


func open(select := -1) -> void:
	visible = true
	if _area_mid.size() != areas.size():
		_area_mids()
	var ext := relief_hi - relief_lo
	var sz := size if size.x > 10.0 else Vector2(640, 360)
	_z_min = minf((sz.x - 270.0) / ext.x, (sz.y - 80.0) / ext.y)
	_center = Vector2(player.global_position.x, player.global_position.z) if player else (_lo + _hi) / 2.0
	_zoom = Z_OPEN
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wmapzoom="):  # Test: Zoom beim Öffnen (Bildpunkte je Meter, 0 = ganze Welt)
			_zoom = float(a.substr(11))
		elif a.begins_with("--wmapat="):  # Test: Mitte x:z
			var p := a.substr(9).split(":")
			_center = Vector2(float(p[0]), float(p[1]))
	_zoom = clampf(_zoom, _z_min, Z_MAX)
	_zoom_to = _zoom
	_gliding = false
	_drag = false
	_districts = district_fn.call() if district_fn.is_valid() else []
	_add_found_shops()
	# Auswahl: die Stadt des gewählten Rennens, sonst der nächste entdeckte Ort
	sel = 0
	var ts := town_of(select) if select >= 0 else -1
	var best := 1e18
	for i in places.size():
		if ts >= 0:
			if places[i]["kind"] == "town" and places[i]["town"] == ts:
				sel = i
			continue
		var d: float = (places[i]["pos"] as Vector2).distance_squared_to(_center) * (1.0 if known(i) else 4.0) \
			* (1.0 if places[i]["kind"] == "town" else 3.0)
		if d < best:
			best = d
			sel = i
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wmapsel="):  # Test: Ort mit diesem Namen wählen
			for i in places.size():
				if places[i]["name"] == a.substr(10):
					sel = i
	_lod = -999
	_apply_view()


## Gefundene Werkstätten (seit 2.50, GameState.secret_pos) als Sprungziele, Ankunft dort, wo man sie gefunden hat
func _add_found_shops() -> void:
	for key in GameState.secret_pos:
		var k := str(key)
		if not k.begins_with("werkstatt:") or places.any(func(p): return p["key"] == k):
			continue
		var a: Array = GameState.secret_pos[k]
		var xf := Transform3D(Basis(Vector3.UP, float(a[3])), Vector3(float(a[0]), float(a[1]) + 0.5, float(a[2])))
		places.append({"kind": "shop", "name": k.get_slice(":", 1), "key": k, "town": -1,
			"pos": Vector2(float(a[0]), float(a[2])), "xf": xf})


# --- Ansicht ------------------------------------------------------------------------------------------------------

func _w2s(p: Vector2) -> Vector2:
	return (p - _center) * _zoom + size * 0.5


func _s2w(s: Vector2) -> Vector2:
	return (s - size * 0.5) / _zoom + _center


func _apply_view() -> void:
	# ganz herausgezoomt: Welt in der Mitte; sonst darf die Mitte nur so weit, dass noch Welt im Bild ist
	var half := size * 0.5 / _zoom
	var lo := relief_lo + half * 0.6
	var hi := relief_hi - half * 0.6
	var mid := (relief_lo + relief_hi) * 0.5
	# ganz draußen steht die Welt mittig im freien Teil links vom Infofeld
	_center.x = mid.x + 112.0 / _zoom if lo.x > hi.x else clampf(_center.x, lo.x, hi.x)
	_center.y = mid.y if lo.y > hi.y else clampf(_center.y, lo.y, hi.y)
	var lod := int(floor(log(_zoom) / log(LOD_STEP)))
	if lod != _lod:
		_lod = lod
		_lod_zoom = pow(LOD_STEP, float(lod) + 0.5)
		_base.queue_redraw()
	_base.transform = Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, size * 0.5 - _center * _zoom)
	_over.queue_redraw()
	_ui.queue_redraw()


## Zoom weich um den Faktor k ändern; der Weltpunkt unter at bleibt stehen
func _zoom_step(k: float, at: Vector2) -> void:
	_anchor = at
	_zoom_to = clampf(_zoom_to * k, _z_min, Z_MAX)
	_gliding = false


func _process(dt: float) -> void:
	if not visible:
		return
	_deny_t = maxf(_deny_t - dt, 0.0)
	var mv := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if mv.length() > 0.08:
		_center += mv * PAN_SPEED * dt / _zoom
		_gliding = false
	var tz := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) - Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if absf(tz) > 0.12:
		_anchor = size * 0.5
		_zoom_to = clampf(_zoom_to * exp(tz * 1.8 * dt), _z_min, Z_MAX)
	if absf(_zoom_to - _zoom) > _zoom * 0.0005:
		var wp := _s2w(_anchor)
		_zoom = exp(lerpf(log(_zoom), log(_zoom_to), 1.0 - exp(-dt * 14.0)))
		if absf(_zoom_to - _zoom) <= _zoom * 0.0005:
			_zoom = _zoom_to
		_center = wp - (_anchor - size * 0.5) / _zoom
	if _gliding:
		_center = _center.lerp(_glide_to, 1.0 - exp(-dt * 7.0))
		if _center.distance_to(_glide_to) * _zoom < 0.5:
			_gliding = false
	_update_hover()
	_apply_view()


func _update_hover() -> void:
	_hover = -1
	if _mouse.x < -500.0 or _on_ui(_mouse):
		return
	var best := 15.0
	for i in places.size():
		if not _shown(i):
			continue
		var d := _w2s(_marker(i)).distance_to(_mouse)
		if d < best:
			best = d
			_hover = i


## Liegt der Bildpunkt auf Leisten oder Infofeld (dort wählt die Maus keinen Ort)?
func _on_ui(p: Vector2) -> bool:
	return p.y < 40.0 or p.y > size.y - 26.0 or Rect2(size.x - 218.0, 46.0, 206.0, size.y - 80.0).has_point(p)


## Wo der Ort auf der Karte steht (Städte: Mitte, sonst Tor bzw. Start)
func _marker(i: int) -> Vector2:
	return places[i]["pos"]


## Ort i bei diesem Zoom sichtbar (Symbol gezeichnet)?
func _shown(i: int) -> bool:
	return places[i]["kind"] == "town" or _zoom >= Z_VILLAGES


# --- Eingaben -----------------------------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _drag:
			var d := mm.position - _drag_from
			if d.length() > 3.0:
				_moved = true
			if _moved:
				_center = _drag_center - d / _zoom
				_gliding = false
		accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_step(pow(WHEEL_K, maxf(mb.factor, 1.0) if mb.factor > 0.0 else 1.0), mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_step(1.0 / pow(WHEEL_K, maxf(mb.factor, 1.0) if mb.factor > 0.0 else 1.0), mb.position)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					var act := _button_at(mb.position)
					if act != "":
						_do(act)
						accept_event()
						return
					_update_hover()
					if mb.double_click and _hover >= 0:
						sel = _hover
						_jump_sel()
						accept_event()
						return
				_drag = true
				_drag_from = mb.position
				_drag_center = _center
				_moved = false
			else:
				if _drag and not _moved and mb.button_index == MOUSE_BUTTON_LEFT and _hover >= 0 and _hover != sel:
					sel = _hover
					Sfx.ui("move")
				_drag = false
		accept_event()
	elif event is InputEventPanGesture:
		# Trackpad, zwei Finger hoch/runter: zoomen wie das Mausrad
		var pg := event as InputEventPanGesture
		_zoom_step(pow(WHEEL_K, -pg.delta.y * 0.6), pg.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_step(mg.factor, mg.position)
		accept_event()


## Tasten und Gamepad (world._unhandled_input reicht alles weiter, solange die Karte offen ist)
func _handle(event: InputEvent) -> bool:
	if not visible or places.is_empty():
		return false
	if event is InputEventKey and event.pressed:
		var ke := event as InputEventKey
		var k := ke.keycode
		var pk := ke.physical_keycode
		if pk == KEY_PAGEUP or k in [KEY_PLUS, KEY_EQUAL, KEY_KP_ADD]:
			_zoom_step(KEY_K, size * 0.5)
		elif pk == KEY_PAGEDOWN or k in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_zoom_step(1.0 / KEY_K, size * 0.5)
		elif pk == KEY_Q and not ke.echo:
			_cycle(-1)
		elif pk == KEY_E and not ke.echo:
			_cycle(1)
		elif pk == KEY_H and not ke.echo and player:
			_glide_to = Vector2(player.global_position.x, player.global_position.z)
			_gliding = true
		elif event.is_action_pressed("handbrake"):
			# Leertaste: springen. Vor ui_accept: Godots ui_accept enthält die Leertaste auch
			_jump_sel()
			return true
		elif event.is_action_pressed("ui_accept"):
			_do("ziel")
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("map") or event.is_action_pressed("pause"):
			_close()
		else:
			return false
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventJoypadButton and event.pressed:
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
			_cycle(-1)
		elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle(1)
		elif event.is_action_pressed("handbrake"):
			_jump_sel()
			return true
		elif event.is_action_pressed("ui_accept"):
			_do("ziel")
		elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("map") or event.is_action_pressed("pause"):
			_close()
		else:
			return false
		get_viewport().set_input_as_handled()
		return true
	return false


func _cycle(d: int) -> void:
	sel = (sel + d + places.size()) % places.size()
	_glide_to = places[sel]["pos"]
	_gliding = true
	Sfx.ui("move")


func _close() -> void:
	visible = false
	_drag = false
	closed.emit()


func _do(act: String) -> void:
	if act == "springen":
		_jump_sel()
	elif act == "ziel":
		var p: Dictionary = places[sel]
		if p["kind"] == "town":
			var k: int = p["town"]
			target = -1 if town_of(target) == k else target_race(k)
			has_target_pos = false
			target_chosen.emit(target)
		else:
			var pos3 := Vector3(p["pos"].x, 0.0, p["pos"].y)
			has_target_pos = not (has_target_pos and target_pos.distance_to(pos3) < 1.0)
			target_pos = pos3
			if has_target_pos:
				target = -1
			target_pos_chosen.emit(pos3, has_target_pos)
		Sfx.ui("go")


func _jump_sel() -> void:
	# vor dem Signal: der Szenenwechsel nimmt die Karte sofort aus dem Baum (danach gibt es kein Viewport mehr)
	get_viewport().set_input_as_handled()
	if not known(sel):
		Sfx.ui("locked")  # erst hinfahren
		_deny_t = 1.6
		return
	Sfx.ui("go")
	jump.emit(places[sel]["xf"])


func _button_at(p: Vector2) -> String:
	for b in _btns:
		if (b[0] as Rect2).has_point(p):
			return b[1]
	return ""


# --- Zeichnen: Flächen und Straßen (Weltkoordinaten) -------------------------------------------------------------

func _draw_base() -> void:
	var b := _base
	var m := 1.0 / _lod_zoom  # Meter je Bildpunkt bei dieser Stufe
	b.draw_rect(Rect2(relief_lo - Vector2(40000, 40000), relief_hi - relief_lo + Vector2(80000, 80000)), COL_BG)
	b.draw_rect(Rect2(relief_lo, relief_hi - relief_lo), COL_LAND)
	if relief:
		b.draw_texture_rect(relief, Rect2(relief_lo, relief_hi - relief_lo), false, Color(0.95, 1.0, 0.97, 0.5))
	# Seen
	for lk in lakes:
		b.draw_circle(lk[0], float(lk[1]) + 1.5 * m, COL_WATER_EDGE)
		b.draw_circle(lk[0], float(lk[1]), COL_WATER)
	# Dörfer: kleine bebaute Flecken
	for v in villages:
		b.draw_circle(v[0], maxf(110.0, 2.5 * m), COL_VILLAGE)
	# Gelände: getönte Fläche, Teiche
	for ar in areas:
		var col: Color = ar[1]
		b.draw_colored_polygon(ar[0], Color(col.r, col.g, col.b, 0.85))
		var ol: PackedVector2Array = (ar[0] as PackedVector2Array).duplicate()
		ol.append(ol[0])
		b.draw_polyline(ol, Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.6), 1.2 * m, true)
		for pd in ar[3]:
			b.draw_colored_polygon(pd, COL_WATER)
	# Städte: bebaute Fläche als breites Band entlang aller Straßen (folgt der Stadt statt eines Klotzes), nah die
	# Häuser darauf
	for c in _cities:
		var kn: bool = c["town"] >= 0 and GameState.town_known(str(towns[c["town"]]["name"]))
		var col := COL_TOWN if kn else COL_TOWN_NEW
		for pl in c["lines"]:
			b.draw_polyline(pl, col, maxf(120.0, 7.0 * m), false)
	if _lod_zoom >= Z_HOUSES:
		var hs := maxf(11.0, 1.6 * m)
		for c in _cities:
			var kn: bool = c["town"] >= 0 and GameState.town_known(str(towns[c["town"]]["name"]))
			var hc := COL_HOUSE if kn else COL_HOUSE_NEW
			for q in c["houses"]:
				b.draw_rect(Rect2(q - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), hc)
			for q3 in c["blocks"]:
				var s := clampf(q3.z * 0.55, hs, 26.0)
				b.draw_rect(Rect2(Vector2(q3.x, q3.y) - Vector2(s, s) * 0.5, Vector2(s, s)), hc)
	# Straßen: erst alle Ränder, dann die Füllungen (Sackgassen, Abzweige, Hauptstraßen), darüber Auffahrten und Autobahn
	var sw := [maxf(9.0, 1.1 * m), maxf(7.0, 0.85 * m), maxf(5.0, 0.7 * m)]
	for k in 3:
		for pl in _streets[k]:
			b.draw_polyline(pl, COL_CASE, float(sw[k]) + maxf(4.0, 1.0 * m), false)
	for k in [2, 1, 0]:
		for pl in _streets[k]:
			b.draw_polyline(pl, COL_ST[k], sw[k], true)
	var rw := maxf(8.0, 1.4 * m)
	for pl in _ramps:
		b.draw_polyline(pl, COL_CASE, rw + maxf(5.0, 1.3 * m), false)
	for pl in _ramps:
		b.draw_polyline(pl, COL_RAMP, rw, true)
	var aw := maxf(16.0, 2.4 * m)
	for pl in _ab:
		b.draw_polyline(pl, COL_CASE, aw + maxf(7.0, 1.8 * m), false)
	for pl in _ab:
		b.draw_polyline(pl, COL_AB, aw, true)


# --- Zeichnen: Namen und Symbole (Bildschirm) ---------------------------------------------------------------------

func _label(ci: CanvasItem, f: Font, at: Vector2, text: String, fs: int, col: Color, taken: Array, center := true) -> bool:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := at - Vector2(w / 2.0 if center else 0.0, -fs * UI.CAP / 2.0)
	var r := Rect2(p - Vector2(2, fs * UI.CAP + 2), Vector2(w + 4, fs * UI.CAP + 4))
	if not Rect2(Vector2.ZERO, size).intersects(r):
		return false
	for t in taken:
		if (t as Rect2).intersects(r):
			return false
	taken.append(r)
	ci.draw_string_outline(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8 * col.a))
	ci.draw_string(f, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	return true


func _draw_over() -> void:
	var o := _over
	var taken: Array = []
	var t_ms := Time.get_ticks_msec()
	var breathe := 0.5 + 0.5 * sin(t_ms * 0.0035)
	# Reservierte Flächen: Leisten und Infofeld
	taken.append(Rect2(0, 0, size.x, 40))
	taken.append(Rect2(0, size.y - 26, size.x, 26))
	taken.append(Rect2(size.x - 218, 46, 206, size.y - 80))
	# du (oben auf, aber zuerst reserviert: kein Name darüber)
	var pp := Vector2.ZERO
	if player:
		pp = _w2s(Vector2(player.global_position.x, player.global_position.z))
		taken.append(Rect2(pp - Vector2(10, 10), Vector2(20, 20)))
	# Gewählter Ort: atmender Ring; Ort unter der Maus: feiner Ring
	if not places.is_empty():
		var sp := _w2s(_marker(sel))
		o.draw_arc(sp, 13.0 + 2.0 * breathe, 0.0, TAU, 32, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.55 + 0.4 * breathe), 1.6, true)
		if _hover >= 0 and _hover != sel:
			o.draw_arc(_w2s(_marker(_hover)), 12.0, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 1.0, true)
	# Städte: Namen groß (entdeckt hell, sonst grau)
	var order := range(towns.size())
	if not places.is_empty() and places[sel]["kind"] == "town":
		order.erase(places[sel]["town"])
		order.push_front(places[sel]["town"])
	for k in order:
		var kn := GameState.town_known(str(towns[k]["name"]))
		var col := UI.TEXT if kn else Color(UI.FAINT.r, UI.FAINT.g, UI.FAINT.b, 0.95)
		var fs := 9 if _zoom < 0.4 else 11
		_label(o, _f_town, _w2s(towns[k].get("mid", Vector2.ZERO)) + Vector2(0, -14), str(towns[k]["name"]).to_upper(), fs, col, taken)
	if not center_town.is_empty():
		_label(o, _f_town, _w2s(center_town[0]), str(center_town[1]), 8, Color(UI.TEXT.r, UI.TEXT.g, UI.TEXT.b, 0.8), taken)
	# Gelände
	for i in areas.size():
		if i < _area_mid.size():
			var ac: Color = areas[i][1]
			_label(o, _f_wide, _w2s(_area_mid[i]), str(areas[i][2]).to_upper(), 7, Color(0.6 + ac.r * 0.6, 0.6 + ac.g * 0.6, 0.55 + ac.b * 0.5, 0.9), taken)
	# Viertel der geladenen Städte (nah)
	if _zoom >= Z_DISTRICTS:
		for d in _districts:
			_label(o, _f_small, _w2s(d[0]), str(d[1]).to_upper(), 6, Color(0.78, 0.82, 0.9, 0.62), taken)
	# Dörfer
	if _zoom >= Z_VILLAGES:
		for v in villages:
			_label(o, _f_body, _w2s(v[0]), str(v[1]), 7, Color(UI.DIM.r, UI.DIM.g, UI.DIM.b, 0.8), taken)
	# Rennen: nah einzeln in der Farbe ihrer Art (gewonnen goldener Haken, gesperrt grau)
	if _zoom >= Z_PINS:
		for i in pins.size():
			var p: Dictionary = pins[i]
			var race: Dictionary = Catalog.RACES[p["race_index"]]
			var sp := _w2s(Vector2(p["pos"].x, p["pos"].z))
			if not Rect2(Vector2(-10, -10), size + Vector2(20, 20)).has_point(sp):
				continue
			var won: bool = race["name"] in GameState.won_events
			var col: Color = UI.TYPE_COL.get(race.get("type", "sprint"), UI.CYAN) if GameState.career_open(race["name"]) else UI.FAINT
			if won:
				o.draw_circle(sp, 4.6, Color(0, 0, 0, 0.85))
				o.draw_polyline(PackedVector2Array([sp + Vector2(-2.6, 0), sp + Vector2(-0.8, 2.2), sp + Vector2(3, -2.6)]), UI.GOLD, 1.5, true)
			else:
				o.draw_circle(sp, 5.0, Color(0, 0, 0, 0.85))
				o.draw_circle(sp, 3.6, col)
			if p["race_index"] == target:
				_flag(o, sp)
	# Sprungziele ohne Stadt: Gelände (Tor), Autobahn-Rennen (blaue Säule)
	for i in places.size():
		var pl: Dictionary = places[i]
		if pl["kind"] == "town" or not _shown(i):
			continue
		var sp := _w2s(pl["pos"])
		if not Rect2(Vector2(-10, -10), size + Vector2(20, 20)).has_point(sp):
			continue
		var kn := known(i)
		if pl["kind"] == "shop":
			o.draw_circle(sp, 6.0, Color(0, 0, 0, 0.85))
			o.draw_circle(sp, 4.4, Color(1.0, 0.62, 0.16))
			o.draw_string(_f_wide, sp + Vector2(-2.9, 2.6), "W", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.05, 0.03, 0.0))
			continue
		if pl["kind"] == "hw":
			var won: bool = str(pl["name"]) in GameState.highway_won
			var c := COL_HW if kn else Color(0.35, 0.45, 0.6)
			o.draw_rect(Rect2(sp - Vector2(5.5, 5.5), Vector2(11, 11)), Color(0, 0, 0, 0.85))
			o.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), UI.GOLD if won else c)
			o.draw_string(_f_wide, sp + Vector2(-2.4, 2.6), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.02, 0.03, 0.05))
		else:
			var c2 := Color(0.55, 0.85, 0.5) if pl.get("akind", "") == "golf" else Color(0.9, 0.75, 0.5)
			if not kn:
				c2 = c2.darkened(0.45)
			o.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(5, 0), sp + Vector2(0, 6), sp + Vector2(-5, 0)]),
				Color(0, 0, 0, 0.85))
			o.draw_colored_polygon(PackedVector2Array([sp + Vector2(0, -4.2), sp + Vector2(3.6, 0), sp + Vector2(0, 4.2), sp + Vector2(-3.6, 0)]), c2)
	# Ziel ohne Rennen
	if has_target_pos:
		_flag(o, _w2s(Vector2(target_pos.x, target_pos.z)))
	elif target >= 0 and _zoom < Z_PINS:
		var tk := town_of(target)
		if tk >= 0:
			_flag(o, _w2s(towns[tk].get("mid", Vector2.ZERO)) + Vector2(10, -4))
	# du: gelber Pfeil mit Puls (zuletzt, liegt über allem)
	if player:
		var f3: Vector3 = -player.global_basis.z
		var ang := Vector2(f3.x, f3.z).angle() + PI / 2.0
		var r := 8.0 + 10.0 * fmod(t_ms * 0.0007, 1.0)
		o.draw_arc(pp, r, 0.0, TAU, 32, Color(COL_PLAYER.r, COL_PLAYER.g, COL_PLAYER.b, 0.5 * (1.0 - (r - 8.0) / 10.0)), 1.4, true)
		var tri := PackedVector2Array([Vector2(0, -8), Vector2(6, 5.5), Vector2(0, 2.2), Vector2(-6, 5.5)])
		var xf := Transform2D(ang, pp)
		o.draw_colored_polygon(xf * tri, COL_PLAYER)
		o.draw_polyline(xf * PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 1.4, true)


## Zielflagge (Schachbrett) an einem Bildpunkt
func _flag(ci: CanvasItem, p: Vector2) -> void:
	var o := p + Vector2(0, -2)
	ci.draw_line(o, o + Vector2(0, -12), Color(0, 0, 0, 0.9), 2.4)
	ci.draw_line(o, o + Vector2(0, -12), UI.TEXT, 1.0)
	for yy in 2:
		for xx in 3:
			var c := UI.TEXT if (xx + yy) % 2 == 0 else Color(0.05, 0.05, 0.06)
			ci.draw_rect(Rect2(o + Vector2(1 + xx * 2.6, -12 + yy * 2.6), Vector2(2.6, 2.6)), c)


# --- Zeichnen: Leisten und Infofeld ---------------------------------------------------------------------------------

func _draw_ui() -> void:
	var u := _ui
	_btns.clear()
	# Kopfleiste: Titel mit Akzentstrich, rechts was entdeckt ist
	u.draw_rect(Rect2(0, 0, size.x, 40), Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.86))
	u.draw_rect(Rect2(0, 40, size.x, 1), UI.LINE)
	u.draw_string(_f_title, Vector2(20, 27), tr("KARTE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.TEXT)
	u.draw_rect(Rect2(21, 33, 14, 2), UI.ACCENT)
	var nt := 0
	for k in towns.size():
		if GameState.town_known(str(towns[k]["name"])):
			nt += 1
	var na := 0
	var nh := 0
	var ta := 0
	var th := 0
	for i in places.size():
		if places[i]["kind"] == "area":
			ta += 1
			na += 1 if known(i) else 0
		elif places[i]["kind"] == "hw":
			th += 1
			nh += 1 if known(i) else 0
	var ns := 0
	var np := 0
	for k in towns.size():
		var tn := str(towns[k]["name"])
		ns += 1 if GameState.place_known("werkstatt:" + tn) else 0
		np += 1 if GameState.place_known("kennzeichen:" + tn) else 0
	var cnt := tr("STÄDTE %d / %d  ·  GELÄNDE %d / %d  ·  AUTOBAHN %d / %d  ·  WERKSTÄTTEN %d / %d  ·  KENNZEICHEN %d / %d") % [
		nt, towns.size(), na, ta, nh, th, ns, towns.size(), np, towns.size()]
	var cw := _f_wide.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
	u.draw_string(_f_wide, Vector2(size.x - 20.0 - cw, 24), cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, UI.DIM)
	# Fußleiste: Tasten
	u.draw_rect(Rect2(0, size.y - 26, size.x, 26), Color(UI.INK.r, UI.INK.g, UI.INK.b, 0.86))
	u.draw_rect(Rect2(0, size.y - 26, size.x, 1), UI.LINE)
	var x := 16.0
	var y := size.y - 19.0
	for h in [["W A S D", tr("Verschieben")], [tr("MAUSRAD"), tr("Zoom")], [tr("BILD↑ BILD↓"), ""], ["Q E", tr("Ort wechseln")],
			["H", tr("Zu dir")], [tr("LEERTASTE"), tr("Springen")], ["ENTER", tr("Ziel")], ["M", tr("Zurück")]]:
		x += UI.draw_hint(u, Vector2(x, y), h[0], h[1], 6) + (6.0 if h[1] == "" else 12.0)
	# Maßstab unten links
	var lens := [100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]
	var L := 100.0
	for l in lens:
		if l * _zoom <= 110.0:
			L = l
	var bw := L * _zoom
	var bx := Vector2(18, size.y - 40)
	u.draw_rect(Rect2(bx - Vector2(1, 1), Vector2(bw + 2, 4)), Color(0, 0, 0, 0.7))
	u.draw_rect(Rect2(bx, Vector2(bw, 2)), UI.TEXT)
	var lt := ("%d km" % int(L / 1000.0)) if L >= 1000.0 else ("%d m" % int(L))
	u.draw_string_outline(_f_body, bx + Vector2(bw + 6, 4), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, 3, Color(0, 0, 0, 0.8))
	u.draw_string(_f_body, bx + Vector2(bw + 6, 4), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UI.DIM)
	if not places.is_empty():
		_draw_info(u)


func _draw_info(u: Control) -> void:
	var p: Dictionary = places[sel]
	var x := size.x - 214.0
	var w := 198.0
	var ix := x + 14.0
	var iw := w - 28.0
	var y := 66.0
	# Höhe vorab: Städte mit Rennen länger
	var n_r := (towns[p["town"]]["pins"] as Array).size() if p["kind"] == "town" else 0
	var h := (166.0 if p["kind"] == "town" else 128.0) + n_r * 33.0
	u.draw_style_box(UI.panel_box(0.92), Rect2(x, 50, w, h))
	var kind_t: String = {"town": tr("STADT"), "area": tr("GELÄNDE"), "hw": tr("AUTOBAHN-RENNEN"), "shop": tr("VERSTECKTE WERKSTATT")}.get(p["kind"], "")
	u.draw_string(_f_wide, Vector2(ix, y), kind_t, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, UI.FAINT)
	y += 20
	var name := str(p["name"]).to_upper()
	var fs := 18
	while fs > 11 and _f_title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > iw:
		fs -= 1
	if _f_title.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > iw:
		u.draw_multiline_string(_f_title, Vector2(ix, y), name, HORIZONTAL_ALIGNMENT_LEFT, iw, fs, 2, UI.TEXT)
		y += fs + 2
	else:
		u.draw_string(_f_title, Vector2(ix, y), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT)
	u.draw_rect(Rect2(ix, y + 7, 14, 2), UI.ACCENT)
	y += 22
	var km := (p["pos"] as Vector2).distance_to(Vector2(player.global_position.x, player.global_position.z)) / 1000.0 if player else 0.0
	u.draw_string(_f_body, Vector2(ix, y), tr("Luftlinie: %.1f km") % km, HORIZONTAL_ALIGNMENT_LEFT, iw, 8, UI.DIM)
	y += 14
	var sub := ""
	if p["kind"] == "shop":
		sub = tr("Exklusiver Lack in der Garage")
	elif p["kind"] == "area":
		sub = tr("Golfplatz zum Austoben") if p.get("akind", "") == "golf" else tr("Kiesgrube zum Austoben")
	elif p["kind"] == "hw":
		var won: bool = str(p["name"]) in GameState.highway_won
		sub = tr("GEWONNEN") if won else tr("OFFEN")
		if GameState.best_times.has(p["name"]):
			var bt: float = GameState.best_times[p["name"]]
			sub += "  ·  %d:%05.2f" % [int(bt / 60.0), fmod(bt, 60.0)]
	if sub != "":
		u.draw_string(_f_body, Vector2(ix, y), sub, HORIZONTAL_ALIGNMENT_LEFT, iw, 8, UI.DIM)
		y += 14
	var kn := known(sel)
	var tcol: Color = Color(0.45, 1.0, 0.6) if kn else (UI.ACCENT if _deny_t > 0.0 else UI.FAINT)
	u.draw_string(_f_wide, Vector2(ix, y + 2), tr("SPRINGEN: FREI") if kn else tr("SPRINGEN: ERST HINFAHREN"), HORIZONTAL_ALIGNMENT_LEFT, iw, 6, tcol)
	y += 18
	if p["kind"] == "town":
		var tn := str(p["name"])
		var ws := tr("WERKSTATT ✓") if GameState.place_known("werkstatt:" + tn) else tr("WERKSTATT ?")
		var ks := tr("KENNZEICHEN ✓") if GameState.place_known("kennzeichen:" + tn) else tr("KENNZEICHEN ?")
		u.draw_string(_f_wide, Vector2(ix, y), ws + "   " + ks, HORIZONTAL_ALIGNMENT_LEFT, iw, 6, UI.DIM)
		y += 16
	# Rennen der Stadt: Art, Name, Stand, Bestwert
	if p["kind"] == "town":
		for i in towns[p["town"]]["pins"]:
			var race: Dictionary = Catalog.RACES[pins[i]["race_index"]]
			var type: String = race.get("type", "sprint")
			var name_r: String = race["name"]
			var won: bool = name_r in GameState.won_events
			var open_: bool = GameState.career_open(name_r)
			var col: Color = UI.TYPE_COL.get(type, UI.CYAN) if open_ else UI.FAINT
			u.draw_circle(Vector2(ix + 3, y - 3.5), 2.6, UI.GOLD if won else col)
			u.draw_string(_f_title, Vector2(ix + 12, y), tr(name_r).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, iw - 12, 10, UI.TEXT if open_ else UI.DIM)
			y += 12
			var status := tr("GEWONNEN") if won else (tr("OFFEN") if open_ else GameState.lock_text(name_r).to_upper())
			status = tr({"sprint": "SPRINT", "circuit": "RUNDKURS", "drift": "DRIFT"}.get(type, "")) + "  ·  " + status
			if GameState.best_times.has(name_r):
				var t: float = GameState.best_times[name_r]
				status += "  ·  " + ("%d P" % int(t) if type == "drift" else "%d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)])
			u.draw_string(_f_wide, Vector2(ix + 12, y), status, HORIZONTAL_ALIGNMENT_LEFT, iw - 12, 6, UI.GOLD if won else UI.DIM)
			y += 21
	# Knöpfe (auch mit der Maus): Springen, Ziel
	y = 50.0 + h - 24.0
	var bx := ix
	for b in [["springen", tr("LEERTASTE"), tr("Springen")], ["ziel", "ENTER", _target_word()]]:
		if b[0] == "springen" and not kn:
			continue
		var bwid := UI.draw_hint(u, Vector2(bx, y), b[1], b[2], 6)
		var r := Rect2(bx - 3, y - 3, bwid + 6, 17)
		if r.has_point(_mouse):
			u.draw_rect(r, Color(1, 1, 1, 0.08))
		_btns.append([r, b[0]])
		bx += bwid + 14.0


func _target_word() -> String:
	var p: Dictionary = places[sel]
	if p["kind"] == "town":
		return tr("Ziel löschen") if town_of(target) == p["town"] else tr("Als Ziel")
	var on: bool = has_target_pos and target_pos.distance_to(Vector3(p["pos"].x, 0.0, p["pos"].y)) < 1.0
	return tr("Ziel löschen") if on else tr("Als Ziel")
