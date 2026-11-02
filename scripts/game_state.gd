extends Node
## Spielstand: Siege, aktuelles Auto, Tuning pro Auto. Kein Geld, nur Freischalten über Siege.

const Catalog := preload("res://scripts/catalog.gd")
const I18n := preload("res://scripts/i18n.gd")
const SAVE_PATH := "user://save.json"
## D-DIN (Datto, SIL Open Font License 1.1, siehe assets/fonts/COPYING.txt)
const FONT := preload("res://assets/fonts/D-DIN-Bold.otf")
const FONT_WIDE := preload("res://assets/fonts/D-DINExp-Bold.otf")
## Grafikstufen. max_h: höchste 3D-Auflösung (Zeilen), darüber wird hochskaliert – bei diesem Stil sieht man den
## Unterschied zu 4K kaum, die Grafikkarte aber sehr. aa: Kantenglättung, ssr: Spiegelungen auf nasser Straße,
## ssao: Schatten in Ecken, far: Sichtweite, lod: ab welcher Entfernung Kleinteile/Lampen ausgeblendet werden.
const QUALITY := [
	{"name": "Niedrig", "max_h": 720.0, "aa": "aus", "ssr": 0, "ssao": false, "far": 650.0, "lod": [140.0, 280.0, 120.0], "steam": false},
	{"name": "Mittel", "max_h": 900.0, "aa": "fxaa", "ssr": 16, "ssao": false, "far": 900.0, "lod": [220.0, 420.0, 170.0], "steam": true},
	{"name": "Hoch", "max_h": 1080.0, "aa": "msaa", "ssr": 32, "ssao": true, "far": 1200.0, "lod": [320.0, 650.0, 240.0], "steam": true},
]
const PIXEL_H := 540.0  # Pixel-Look: 3D in 540 Zeilen, pixelgenau hochskaliert
const FPS_LIMITS := [0, 30, 60, 120]

signal graphics_changed

## Grafik-Einstellungen (werden gespeichert)
var quality := 0 if OS.has_feature("web") else 1  # im Browser (und auf dem Handy) erst einmal niedrig
var pixel_look := false
## "" = noch nicht gewählt (beim ersten Start fragt die Garage), sonst "en" oder "de"
var language := ""
var vsync := true
var fps_limit := 0
var fullscreen := false

var wins := 0  # Rennsiege (Sprint + Rundkurs)
var drift_wins := 0
var current_car := "kaizen"
var race_index := 0
var best_times := {}  # Rennname -> Sekunden
var car_configs := {}  # car_id -> {category: option_index}


func _ready() -> void:
	# Schrift im Stil der deutschen Straßenschilder (DIN 1451) für alles: Menü, HUD, Schilder in der Welt
	ThemeDB.fallback_font = FONT
	_setup_input()
	load_game()
	I18n.setup(language if language != "" else "en")
	_build_rotate_hint()
	_init_window()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			race_index = clampi(int(a.substr(7)), 0, Catalog.RACES.size() - 1)
		elif a.begins_with("--quality="):  # nur für Tests, wird nicht gespeichert
			quality = clampi(int(a.substr(10)), 0, QUALITY.size() - 1)
		elif a.begins_with("--pixel="):
			pixel_look = a.substr(8) == "1"
	apply_display()
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
	_add_action("shift_up", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [])  # Drag: hochschalten
	_add_action("shift_down", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
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
	fullscreen = not fs
	save_game()


func q() -> Dictionary:
	return QUALITY[quality]


## V-Sync, FPS-Limit und Vollbild auf das Fenster anwenden
func apply_display() -> void:
	Engine.max_fps = FPS_LIMITS[fps_limit]
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Eine Einstellung weiterschalten, anwenden und speichern
func cycle_setting(key: String) -> void:
	match key:
		"quality":
			quality = (quality + 1) % QUALITY.size()
		"pixel":
			pixel_look = not pixel_look
		"vsync":
			vsync = not vsync
		"fps":
			fps_limit = (fps_limit + 1) % FPS_LIMITS.size()
	apply_display()
	graphics_changed.emit()
	save_game()


## Handy/Tablet im Browser (oder nativ): kleinere Welt, Grafik niedrig
func is_mobile() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios")


## Bildschirmknöpfe zeigen (Touchscreen vorhanden; --touch erzwingt sie zum Testen)
func touch_ui() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.get_cmdline_user_args().has("--touch")


func set_language(lang: String) -> void:
	language = lang
	I18n.setup(lang)
	save_game()


func setting_text(key: String) -> String:
	match key:
		"quality":
			return tr("Grafik: ") + tr(q()["name"])
		"pixel":
			return tr("Pixel-Look: ") + tr("An" if pixel_look else "Aus")
		"vsync":
			return tr("V-Sync: ") + tr("An" if vsync else "Aus")
		"fps":
			return tr("FPS-Limit: ") + (str(FPS_LIMITS[fps_limit]) if FPS_LIMITS[fps_limit] > 0 else tr("Aus"))
		"fullscreen":
			return tr("Vollbild: ") + tr("An" if fullscreen else "Aus")
		"language":
			return tr("Sprache: ") + I18n.NAMES.get(language if language != "" else "en", "English")
	return key


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

func total_wins() -> int:
	return wins + drift_wins


## Tempo-Stufe: am Anfang fahren alle langsamer (72 %), mit jedem Sieg etwas schneller, ab 20 Siegen volles Tempo
func pace() -> float:
	return 0.72 + 0.28 * clampf(total_wins() / 20.0, 0.0, 1.0)


func is_car_unlocked(car_id: String, race_w := -1, drift_w := -1) -> bool:
	var req: Dictionary = Catalog.CARS[car_id]["unlock"]
	if req.is_empty():
		return true
	var rw := wins if race_w < 0 else race_w
	var dw := drift_wins if drift_w < 0 else drift_w
	return (req.has("race") and rw >= req["race"]) or (req.has("drift") and dw >= req["drift"])


## "2 Rennsiege oder 1 Driftsieg"
func unlock_text(car_id: String) -> String:
	var req: Dictionary = Catalog.CARS[car_id]["unlock"]
	var parts := []
	if req.has("race"):
		parts.append(tr("%d Rennsieg" if req["race"] == 1 else "%d Rennsiege") % req["race"])
	if req.has("drift"):
		parts.append(tr("%d Driftsieg" if req["drift"] == 1 else "%d Driftsiege") % req["drift"])
	return tr(" oder ").join(parts)


func is_part_unlocked(category: String, index: int) -> bool:
	return total_wins() >= Catalog.PARTS[category]["options"][index]["wins"]


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


## Sieg zählen (Drift-Events als Driftsieg, sonst Rennsieg).
## Liefert eine Liste von Texten, was dadurch freigeschaltet wurde.
func register_win(event_type: String) -> Array:
	var rw0 := wins
	var dw0 := drift_wins
	var before := total_wins()
	if event_type == "drift":
		drift_wins += 1
	else:
		wins += 1
	var unlocked := []
	for car_id in Catalog.CAR_ORDER:
		if not is_car_unlocked(car_id, rw0, dw0) and is_car_unlocked(car_id):
			unlocked.append(tr("Auto: ") + Catalog.CARS[car_id]["name"])
	for cat in Catalog.PART_ORDER:
		for opt in Catalog.PARTS[cat]["options"]:
			if opt["wins"] > before and opt["wins"] <= total_wins():
				unlocked.append(tr(Catalog.PARTS[cat]["label"]) + ": " + tr(opt["name"]))
	save_game()
	return unlocked


# --- Speichern ------------------------------------------------------------

## Das Spiel hieß früher "Underground Sprint": Godot legt user:// nach dem Spielnamen an. Gibt es im neuen Ordner
## noch keinen Spielstand, wird der alte einmal herüberkopiert (der alte bleibt liegen).
func _migrate_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join("Underground Sprint").path_join("save.json")
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(SAVE_PATH))


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"wins": wins, "drift_wins": drift_wins, "current_car": current_car, "race_index": race_index,
		"best_times": best_times, "car_configs": car_configs,
		"gfx": {"quality": quality, "pixel": pixel_look, "vsync": vsync, "fps": fps_limit, "fullscreen": fullscreen},
		"language": language,
	}, "\t"))


func load_game() -> void:
	_migrate_save()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	wins = int(data.get("wins", 0))
	drift_wins = int(data.get("drift_wins", 0))
	current_car = str(data.get("current_car", "kaizen"))
	if not Catalog.CARS.has(current_car):
		current_car = "kaizen"
	race_index = clampi(int(data.get("race_index", 0)), 0, Catalog.RACES.size() - 1)
	best_times = data.get("best_times", {})
	for old in Catalog.RENAMED:
		if best_times.has(old):
			best_times[Catalog.RENAMED[old]] = best_times[old]
			best_times.erase(old)
	var gfx: Dictionary = data.get("gfx", {})
	quality = clampi(int(gfx.get("quality", quality)), 0, QUALITY.size() - 1)
	# alter Spielstand: Pixel-Stufe Stark/Mittel = Pixel-Look an
	pixel_look = bool(gfx.get("pixel", int(data.get("pixel_mode_v2", 2)) <= 1))
	language = str(data.get("language", ""))
	vsync = bool(gfx.get("vsync", true))
	fps_limit = clampi(int(gfx.get("fps", 0)), 0, FPS_LIMITS.size() - 1)
	fullscreen = bool(gfx.get("fullscreen", false))
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
	drift_wins = 0
	current_car = "kaizen"
	race_index = 0
	best_times = {}
	car_configs = {}
	save_game()


## Hochkant auf dem Handy: Hinweis zum Drehen (das Spiel ist für Querformat gebaut)
var _rotate_layer: CanvasLayer


func _build_rotate_hint() -> void:
	_rotate_layer = CanvasLayer.new()
	_rotate_layer.layer = 100
	_rotate_layer.visible = false
	add_child(_rotate_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rotate_layer.add_child(bg)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var ls := LabelSettings.new()
	ls.font_size = 22
	ls.font_color = Color(0.45, 1.0, 0.3)
	l.label_settings = ls
	l.text = "Bitte das Gerät quer halten"
	_rotate_layer.add_child(l)
	get_viewport().size_changed.connect(_check_rotate)
	_check_rotate()


func _check_rotate() -> void:
	var s := get_viewport().get_visible_rect().size
	_rotate_layer.visible = touch_ui() and s.y > s.x
