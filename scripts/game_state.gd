extends Node
## Spielstand: Siege, aktuelles Auto, Tuning pro Auto. Kein Geld, nur Freischalten über Siege.

const Catalog := preload("res://scripts/catalog.gd")
const SAVE_PATH := "user://save.json"
## Pixel-Look: Höhe der 3D-Auflösung, auf die heruntergerechnet wird
const PIXEL_MODES := [
	{"name": "Stark", "height": 360.0},
	{"name": "Mittel", "height": 540.0},
	{"name": "Leicht", "height": 720.0},
	{"name": "Aus", "height": 100000.0},
]

signal graphics_changed

var pixel_mode := 1 if OS.has_feature("web") else 2  # im Browser ohne Kantenglättung (spart viel)

var wins := 0
var current_car := "kaizen"
var race_index := 0
var best_times := {}  # Rennname -> Sekunden
var car_configs := {}  # car_id -> {category: option_index}


func _ready() -> void:
	_setup_input()
	load_game()
	_init_window()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			race_index = clampi(int(a.substr(7)), 0, Catalog.RACES.size() - 1)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot=") or a.begins_with("--at=") or a.begins_with("--quit=") or a in ["--drive", "--demo"]:
			add_child(preload("res://scripts/debug_shot.gd").new())
			break


func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP], [],[JOY_AXIS_TRIGGER_RIGHT, 1.0])
	_add_action("brake", [KEY_S, KEY_DOWN], [], [JOY_AXIS_TRIGGER_LEFT, 1.0])
	_add_action("steer_left", [KEY_A, KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0])
	_add_action("steer_right", [KEY_D, KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0])
	_add_action("handbrake", [KEY_SPACE], [JOY_BUTTON_B], [])
	_add_action("nitro", [KEY_SHIFT, KEY_N], [JOY_BUTTON_A], [])
	_add_action("camera", [KEY_C], [JOY_BUTTON_Y], [])
	_add_action("reset_car", [KEY_R], [JOY_BUTTON_BACK], [])
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_add_action("next_track", [KEY_M], [], [])
	_add_action("fullscreen", [KEY_F11, KEY_F], [], [])  # F: auf dem Mac ist F11 "Schreibtisch anzeigen"
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	InputMap.action_add_event("fullscreen", alt_enter)


## Startet im Fenster, ca. 75 % der Bildschirmgröße in 16:9, zentriert.
func _init_window() -> void:
	if DisplayServer.get_name() == "headless" or Engine.get_write_movie_path() != "" or OS.has_feature("web"):
		return
	var scr := DisplayServer.screen_get_usable_rect()
	var w := int(scr.size.x * 0.75)
	var h := int(w * 9.0 / 16.0)
	if h > scr.size.y * 0.85:
		h = int(scr.size.y * 0.85)
		w = int(h * 16.0 / 9.0)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_position(scr.position + (scr.size - Vector2i(w, h)) / 2)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## Vollbild an/aus. Muss aus einer Eingabe heraus aufgerufen werden (Taste, Knopf), sonst blockiert der Browser.
func toggle_fullscreen() -> void:
	if OS.has_feature("web"):
		# Direkt über die Seite: funktioniert auch in Safari (mit webkit-Präfix) und schluckt Ablehnungen
		JavaScriptBridge.eval("""(function () {
			try {
				var d = document, e = d.documentElement;
				if (d.fullscreenElement || d.webkitFullscreenElement) {
					(d.exitFullscreen || d.webkitExitFullscreen).call(d);
				} else {
					var r = (e.requestFullscreen || e.webkitRequestFullscreen).call(e);
					if (r && r.catch) r.catch(function () {});
				}
			} catch (x) {}
		})()""", true)
		return
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func cycle_pixel_mode() -> void:
	pixel_mode = (pixel_mode + 1) % PIXEL_MODES.size()
	graphics_changed.emit()
	save_game()


func _add_action(action: String, keys: Array, buttons: Array, axis: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.15)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	if axis.size() == 2:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axis[0]
		jm.axis_value = axis[1]
		InputMap.action_add_event(action, jm)


# --- Freischalten ---------------------------------------------------------

func is_car_unlocked(car_id: String) -> bool:
	return wins >= Catalog.CARS[car_id]["wins"]


func is_part_unlocked(category: String, index: int) -> bool:
	return wins >= Catalog.PARTS[category]["options"][index]["wins"]


func is_race_unlocked(index: int) -> bool:
	return wins >= Catalog.RACES[index]["wins"]


func get_config(car_id: String) -> Dictionary:
	if not car_configs.has(car_id):
		var cfg := {}
		for cat in Catalog.PART_ORDER:
			cfg[cat] = 0
		car_configs[car_id] = cfg
	var c: Dictionary = car_configs[car_id]
	for cat in Catalog.PART_ORDER:
		if not c.has(cat):
			c[cat] = 0
	return c


func part(car_id: String, category: String) -> Dictionary:
	return Catalog.PARTS[category]["options"][get_config(car_id)[category]]


## Liefert eine Liste von Texten, was durch den neuen Sieg freigeschaltet wurde.
func register_win() -> Array:
	var before := wins
	wins += 1
	var unlocked := []
	for car_id in Catalog.CAR_ORDER:
		var w: int = Catalog.CARS[car_id]["wins"]
		if w > before and w <= wins:
			unlocked.append("Auto: " + Catalog.CARS[car_id]["name"])
	for i in Catalog.RACES.size():
		var w: int = Catalog.RACES[i]["wins"]
		if w > before and w <= wins:
			unlocked.append("Rennen: " + Catalog.RACES[i]["name"])
	for cat in Catalog.PART_ORDER:
		for opt in Catalog.PARTS[cat]["options"]:
			if opt["wins"] > before and opt["wins"] <= wins:
				unlocked.append(Catalog.PARTS[cat]["label"] + ": " + opt["name"])
	save_game()
	return unlocked


# --- Speichern ------------------------------------------------------------

func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"wins": wins, "current_car": current_car, "race_index": race_index,
		"best_times": best_times, "car_configs": car_configs, "pixel_mode_v2": pixel_mode,
	}, "\t"))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	wins = int(data.get("wins", 0))
	current_car = str(data.get("current_car", "kaizen"))
	if not Catalog.CARS.has(current_car):
		current_car = "kaizen"
	race_index = clampi(int(data.get("race_index", 0)), 0, Catalog.RACES.size() - 1)
	best_times = data.get("best_times", {})
	pixel_mode = clampi(int(data.get("pixel_mode_v2", pixel_mode)), 0, PIXEL_MODES.size() - 1)
	car_configs = {}
	var cc: Dictionary = data.get("car_configs", {})
	for car_id in cc:
		if not Catalog.CARS.has(car_id):
			continue
		var cfg := {}
		for cat in Catalog.PART_ORDER:
			var n: int = Catalog.PARTS[cat]["options"].size()
			cfg[cat] = clampi(int(cc[car_id].get(cat, 0)), 0, n - 1)
		car_configs[car_id] = cfg


func reset_progress() -> void:
	wins = 0
	current_car = "kaizen"
	race_index = 0
	best_times = {}
	car_configs = {}
	save_game()
