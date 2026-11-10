extends Node
## Spielstand: Siege, aktuelles Auto, Tuning. Kein Geld, nur Freischalten über Siege.
## Leistungsteile gelten für alle eigenen Autos (ein Satz für die ganze Garage). Die Optik (Lack, Felgen, Folie, Bodykit
## usw.) hat seit 2.25 jedes Auto für sich: ein Auto, das man zum ersten Mal wählt, ist blank (ab Werk, einfarbig).
## Bis 2.24 galt auch die Optik für alle Autos, eine einmal angebrachte Folie tauchte so auf jedem Auto auf.

const Catalog := preload("res://scripts/catalog.gd")
const I18n := preload("res://scripts/i18n.gd")
const SAVE_PATH := "user://save.json"
## Testläufe (Start mit Argumenten nach "--", z. B. --race=2 --drive) speichern in eine eigene Datei. Bis 2.22 schrieben
## sie in den echten Spielstand, und die Testskripte kopierten danach eine alte Sicherung zurück: dabei ging der
## Fortschritt verloren, und ein frischer Spielstand hatte Tuning aus den Tests (z. B. eine Folierung).
const TEST_SAVE_PATH := "user://save_test.json"
var save_path := SAVE_PATH
## Im Browser: Schlüssel der Kopie im localStorage (falls der Browser das Dateisystem im Rahmen nicht dauerhaft hält)
const WEB_KEY := "nfg_save"
## D-DIN (Datto, SIL Open Font License 1.1, siehe assets/fonts/COPYING.txt)
const FONT := preload("res://assets/fonts/D-DIN-Bold.otf")
const FONT_WIDE := preload("res://assets/fonts/D-DINExp-Bold.otf")
## Grafik wie in großen PC-Spielen: eine Voreinstellung (Niedrig bis Ultra) setzt alle Einzeloptionen, jede lässt
## sich danach einzeln verstellen (dann "Benutzerdefiniert"). Je Option: Stufen, Werte je Stufe, Stufe je Voreinstellung.
##   res: höchste 3D-Auflösung (Zeilen), darüber wird weich hochskaliert. dynres: senkt sie, wenn die Bildrate fällt.
##   view: Sichtweite (m). detail: ab welcher Entfernung Kleinteile / mittlere Teile verschwinden und Autos auf die
##   Fernansicht wechseln. lights: ab wann Laternen ausblenden. fx: Partikel (Regen, Dampf).
##   tex: Texturdetails. Normal: Straße mit 4-facher anisotroper Filterung, Lichtkarte der Laternen bis 1024 Pixel.
##   Hoch: 16-fach (Asphalt bleibt bis weit nach vorn scharf), Lichtkarte bis 2048 Pixel (feinere Lichtkreise).
const PRESETS := ["Niedrig", "Mittel", "Hoch", "Ultra"]
const GFX := {
	"res": {"label": "3D-Auflösung", "levels": ["540p", "720p", "900p", "1080p", "1440p"], "values": [540.0, 720.0, 900.0, 1080.0, 1440.0], "preset": [1, 2, 3, 4]},
	"dynres": {"label": "Dynamische Auflösung", "levels": ["Aus", "An"], "values": [false, true], "preset": [1, 1, 0, 0]},
	"view": {"label": "Sichtweite", "levels": ["Niedrig", "Mittel", "Hoch", "Ultra"], "values": [600.0, 850.0, 1100.0, 1400.0], "preset": [0, 1, 2, 3]},
	"detail": {"label": "Detaildichte", "levels": ["Niedrig", "Mittel", "Hoch", "Ultra"],
		"values": [[110.0, 230.0, 25.0], [170.0, 340.0, 35.0], [260.0, 520.0, 50.0], [380.0, 800.0, 80.0]], "preset": [0, 1, 2, 3]},
	"tex": {"label": "Texturdetails", "levels": ["Normal", "Hoch"], "values": [0, 1], "preset": [0, 0, 1, 1]},
	"lights": {"label": "Lichter", "levels": ["Niedrig", "Mittel", "Hoch", "Ultra"], "values": [80.0, 120.0, 170.0, 250.0], "preset": [0, 1, 2, 3]},
	"aa": {"label": "Kantenglättung", "levels": ["Aus", "FXAA", "MSAA 2x", "MSAA 4x"], "values": ["aus", "fxaa", "msaa2", "msaa4"], "preset": [0, 1, 2, 3]},
	"bloom": {"label": "Glühen", "levels": ["Aus", "An"], "values": [false, true], "preset": [1, 1, 1, 1]},
	"ssr": {"label": "Spiegelungen", "levels": ["Aus", "Niedrig", "Hoch"], "values": [0, 16, 32], "preset": [0, 1, 2, 2], "desktop": true},
	"ssao": {"label": "Umgebungsverdeckung", "levels": ["Aus", "An"], "values": [false, true], "preset": [0, 0, 1, 1], "desktop": true},
	"fx": {"label": "Effekte", "levels": ["Niedrig", "Mittel", "Hoch"], "values": [0, 1, 2], "preset": [0, 1, 2, 2]},
}
const GFX_ORDER := ["res", "dynres", "view", "detail", "tex", "lights", "aa", "bloom", "ssr", "ssao", "fx"]
const PIXEL_H := 540.0  # Pixel-Look: 3D in 540 Zeilen, pixelgenau hochskaliert
const FPS_LIMITS := [0, 30, 60, 120]

signal graphics_changed

## Grafik-Einstellungen (werden gespeichert). preset -1 = Benutzerdefiniert
var preset := -1
var gfx := {}
var show_fps := false
var pixel_look := false
## Touch-Knöpfe im Rennen: 0 Auto (nur Handy/Tablet), 1 immer, 2 nie
var touch_mode := 0
## Sprungkamera bei hohen Sprüngen: 0 an (mit Zeitlupe), 1 ohne Zeitlupe, 2 aus
var jump_cam := 0
const JUMP_CAM_NAMES := ["An", "Ohne Zeitlupe", "Aus"]
## Tempogefühl (Einstellungen > Kamera & Tempo), alles abschaltbar: Bewegungsunschärfe 0 Aus, 1 Dezent, 2 Normal,
## 3 Stark (mit Nitro-Schimmer); Tempo-Zoom (Sichtfeld wird mit dem Tempo weiter); Kamerawackeln (Stöße bei
## Einschlägen und Landungen, Neigen beim Lenken)
var motion_blur := 2
const MOTION_BLUR_NAMES := ["Aus", "Dezent", "Normal", "Stark"]
var speed_fov := true
var cam_shake := true
## Kamera im Rennen (PlayerCar.CAM_NAMES), wird gespeichert
var cam_mode := 0
## Schwierigkeit: wie stark die Gegner fahren (und wie viele Driftpunkte es braucht). 0 Leicht, 1 Normal, 2 Schwer
var difficulty := 1
const DIFFICULTY_NAMES := ["Leicht", "Normal", "Schwer"]
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
var won_events: Array = []  # gewonnene Events (Karriere: genug Siege in einer Stufe öffnen die nächste)
var test_cfg := {}  # --cfg (nur Tests)
var tuning := {}  # Leistungsteile: category -> option_index, für alle Autos gemeinsam
var looks := {}  # Optik je Auto: car_id -> {category: option_index}; fehlt ein Wert, gilt 0 (ab Werk)
var kept_cars: Array = []  # schon mit den alten Schwellen (bis 2.10) freigeschaltete Autos bleiben frei


func _ready() -> void:
	# Schrift im Stil der deutschen Straßenschilder (DIN 1451) für alles: Menü, HUD, Schilder in der Welt
	ThemeDB.fallback_font = FONT
	# Hauptausgang mit hartem Limiter: Motor, Nitro, Reifen, Gegner, Verkehr und Musik zusammen übersteuerten bis 2.22
	# in gut einem Drittel der Sekunden (Spitzen über 0 dB klingen kratzig); der Limiter fängt die Spitzen ab.
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.8
	AudioServer.add_bus_effect(0, lim)
	_setup_input()
	apply_preset(_default_preset())
	if not OS.get_cmdline_user_args().is_empty():
		save_path = TEST_SAVE_PATH
	load_game()
	I18n.setup(language if language != "" else "en")
	_build_rotate_hint()
	_init_window()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			race_index = clampi(int(a.substr(7)), 0, Catalog.RACES.size() - 1)
		elif a.begins_with("--quality="):  # nur für Tests, wird nicht gespeichert
			apply_preset(clampi(int(a.substr(10)), 0, PRESETS.size() - 1))
		elif a.begins_with("--gfx="):  # nur für Tests: einzelne Optionen, z. B. --gfx=res:0,ssr:0
			for kv in a.substr(6).split(","):
				var p := kv.split(":")
				if p.size() == 2 and GFX.has(p[0]):
					gfx[p[0]] = clampi(int(p[1]), 0, GFX[p[0]]["levels"].size() - 1)
					preset = -1
				elif p.size() == 2 and p[0] == "blur":
					motion_blur = clampi(int(p[1]), 0, 3)
		elif a.begins_with("--pixel="):
			pixel_look = a.substr(8) == "1"
		elif a.begins_with("--car=") and Catalog.CARS.has(a.substr(6)):  # nur für Tests: mit diesem Auto fahren
			current_car = a.substr(6)
		elif a.begins_with("--cfg="):  # nur für Tests: Tuning setzen, z. B. --cfg=paint:5,finish:2 (gilt für --car)
			for kv in a.substr(6).split(","):
				if ":" in kv and Catalog.PARTS.has(kv.get_slice(":", 0)):
					test_cfg[kv.get_slice(":", 0)] = int(kv.get_slice(":", 1))
		elif a.begins_with("--lang="):  # nur für Tests und Bilder: Sprache (de/en)
			language = a.substr(7)
			I18n.setup(language)
	for cat in test_cfg:
		set_part(current_car, cat, test_cfg[cat])
	apply_display()
	_build_fps_overlay()
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
	# Drag: hochschalten S (im Drag wird nicht gebremst), runter X; auf deutscher und englischer Tastatur gleich.
	# E/Q gehen weiterhin.
	_add_action("shift_up", [KEY_S, KEY_E], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add_action("shift_down", [KEY_X, KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
	_add_action("camera", [KEY_C], [JOY_BUTTON_Y], [])
	_add_action("reset_car", [KEY_R], [JOY_BUTTON_BACK], [])
	# Pause auch mit Enter: im Browser beendet Esc im Vollbild nur das Vollbild und kommt nicht im Spiel an
	_add_action("pause", [KEY_ESCAPE, KEY_P, KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START], [])
	_add_action("next_track", [KEY_M], [], [])
	_add_action("fullscreen", [KEY_F11, KEY_F], [], [])  # F: auf dem Mac ist F11 "Schreibtisch anzeigen"
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	InputMap.action_add_event("fullscreen", alt_enter)
	# Menüs auch mit W/A/S/D wie beim Fahren; Zurück auch mit der Rücktaste (Esc siehe oben)
	for pair in [["ui_up", KEY_W], ["ui_down", KEY_S], ["ui_left", KEY_A], ["ui_right", KEY_D], ["ui_cancel", KEY_BACKSPACE]]:
		var ev := InputEventKey.new()
		ev.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], ev)


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


## Erststart: Handy/Tablet Niedrig, Browser am Rechner und alle anderen Mittel (beide mit dynamischer Auflösung)
func _default_preset() -> int:
	return 0 if is_mobile() else 1


func apply_preset(i: int) -> void:
	preset = i
	for k in GFX:
		gfx[k] = GFX[k]["preset"][i]


## Wert einer Grafikoption in der eingestellten Stufe
func gv(key: String):
	return GFX[key]["values"][gfx[key]]


## Optionen, die es nur mit dem vollen Renderer gibt (im Browser nicht)
func gfx_available(key: String) -> bool:
	return not GFX[key].get("desktop", false) or RenderingServer.get_current_rendering_method() != "gl_compatibility"


func view_distance() -> float:
	return gv("view")


## [Kleinteile, mittlere Teile, Lampen] für Track.apply_lod
func lod_ranges() -> Array:
	var d: Array = gv("detail")
	return [d[0], d[1], gv("lights")]


func car_lod_distance() -> float:
	return gv("detail")[2]


## V-Sync, FPS-Limit und Vollbild auf das Fenster anwenden
func apply_display() -> void:
	Engine.max_fps = FPS_LIMITS[fps_limit]
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


## Eine Einstellung weiterschalten (dir -1: zurück), anwenden und speichern
func cycle_setting(key: String, dir := 1) -> void:
	if GFX.has(key):
		var n: int = GFX[key]["levels"].size()
		gfx[key] = posmod(gfx[key] + dir, n)
		preset = -1
		for i in PRESETS.size():
			if GFX_ORDER.all(func(k): return gfx[k] == GFX[k]["preset"][i]):
				preset = i
		apply_display()
		graphics_changed.emit()
		save_game()
		return
	if key == "preset" and dir < 0:
		apply_preset(posmod((preset if preset >= 0 else 0) - 1, PRESETS.size()))
		apply_display()
		graphics_changed.emit()
		save_game()
		return
	match key:
		"preset":
			apply_preset((maxi(preset, -1) + 1) % PRESETS.size())
		"pixel":
			pixel_look = not pixel_look
		"vsync":
			vsync = not vsync
		"fps":
			fps_limit = (fps_limit + 1) % FPS_LIMITS.size()
		"touch":
			touch_mode = (touch_mode + 1) % 3
		"jumpcam":
			jump_cam = posmod(jump_cam + dir, 3)
		"motion_blur":
			motion_blur = posmod(motion_blur + dir, 4)
		"speed_fov":
			speed_fov = not speed_fov
		"cam_shake":
			cam_shake = not cam_shake
		"difficulty":
			difficulty = posmod(difficulty + dir, 3)
		"show_fps":
			show_fps = not show_fps
	apply_display()
	graphics_changed.emit()
	save_game()


## Handy/Tablet im Browser (oder nativ): kleinere Welt, Grafik niedrig. iPads melden sich als Mac, daher die
## Prüfung im Browser über Gerätename und Touchpunkte (Laptops mit Touchscreen zählen nicht).
var _mobile := -1


func is_mobile() -> bool:
	if _mobile < 0:
		_mobile = 1 if (OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("android") or OS.has_feature("ios")) else 0
		if _mobile == 0 and OS.has_feature("web"):
			var js = JavaScriptBridge.eval("(/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(navigator.userAgent))", true)
			_mobile = 1 if js == true else 0
	return _mobile == 1


## Bildschirmknöpfe zeigen: Auto = nur auf Handy/Tablet, sonst wie eingestellt; --touch erzwingt sie zum Testen
func touch_ui() -> bool:
	if OS.get_cmdline_user_args().has("--touch"):
		return true
	match touch_mode:
		1:
			return true
		2:
			return false
	return is_mobile()


## Siege in Stufe s
func stage_wins(s: int) -> int:
	var n := 0
	for ev in Catalog.STAGES[s]["events"]:
		if ev in won_events:
			n += 1
	return n


## Stufe s ist offen, wenn die vorige offen ist und darin genug Siege stehen
func stage_open(s: int) -> bool:
	if s <= 0:
		return true
	return stage_open(s - 1) and stage_wins(s - 1) >= Catalog.stage_need(s - 1)


## Karriere-Event frei: seine Stufe ist offen, oder es war nach der alten Kette (bis 2.15) schon offen
func career_open(event_name: String) -> bool:
	var s := Catalog.stage_of(event_name)
	if s >= 0 and stage_open(s):
		return true
	var i := Catalog.CAREER_V1.find(event_name)
	return i == 0 or (i > 0 and Catalog.CAREER_V1[i - 1] in won_events)


func mark_won(event_name: String) -> void:
	if not event_name in won_events:
		won_events.append(event_name)
	save_game()


func set_language(lang: String) -> void:
	language = lang
	I18n.setup(lang)
	save_game()


func setting_text(key: String) -> String:
	match key:
		"preset":
			return tr("Voreinstellung: ") + tr(PRESETS[preset] if preset >= 0 else "Benutzerdefiniert")
		"show_fps":
			return tr("FPS anzeigen: ") + tr("An" if show_fps else "Aus")
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
		"touch":
			return tr("Touch-Steuerung: ") + tr(["Auto", "An", "Aus"][touch_mode])
		"jumpcam":
			return tr("Sprungkamera: ") + tr(JUMP_CAM_NAMES[jump_cam])
		"motion_blur":
			return tr("Bewegungsunschärfe: ") + tr(MOTION_BLUR_NAMES[motion_blur])
		"speed_fov":
			return tr("Tempo-Zoom: ") + tr("An" if speed_fov else "Aus")
		"cam_shake":
			return tr("Kamerawackeln: ") + tr("An" if cam_shake else "Aus")
		"difficulty":
			return tr("Schwierigkeit: ") + tr(DIFFICULTY_NAMES[difficulty])
	if GFX.has(key):
		return tr(GFX[key]["label"]) + ": " + tr(GFX[key]["levels"][gfx[key]])
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
	if req.is_empty() or car_id in kept_cars:
		return true
	var rw := wins if race_w < 0 else race_w
	var dw := drift_wins if drift_w < 0 else drift_w
	return (req.has("race") and rw >= req["race"]) or (req.has("drift") and dw >= req["drift"])


## Spielstand von vor 2.11: was nach den alten Schwellen schon frei war, bleibt frei
static func legacy_cars(race_w: int, drift_w: int) -> Array:
	var out := []
	for id in Catalog.LEGACY_UNLOCK:
		var req: Dictionary = Catalog.LEGACY_UNLOCK[id]
		if (req.has("race") and race_w >= req["race"]) or (req.has("drift") and drift_w >= req["drift"]):
			out.append(id)
	return out


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


## Eingebautes Tuning eines Autos (neues Dictionary): Leistung für alle gleich, Optik je Auto (fehlt: ab Werk)
func get_config(car_id := "") -> Dictionary:
	var id := car_id if car_id != "" else current_car
	var lk: Dictionary = looks.get(id, {})
	var cfg := {}
	for cat in Catalog.PART_ORDER:
		cfg[cat] = int((tuning if cat in Catalog.PART_GROUPS["leistung"] else lk).get(cat, 0))
	return cfg


## Teil einbauen: Leistung für alle Autos, Optik nur für dieses Auto
func set_part(car_id: String, cat: String, idx: int) -> void:
	if cat in Catalog.PART_GROUPS["leistung"]:
		tuning[cat] = idx
	else:
		if not looks.has(car_id):
			looks[car_id] = {}
		looks[car_id][cat] = idx


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
	# je Kategorie eine Zeile ("Felgen: Turbine, Gitter Gold"), sonst wird die Liste nach einem Sieg zu lang
	for cat in Catalog.PART_ORDER:
		var names := []
		for opt in Catalog.PARTS[cat]["options"]:
			if opt["wins"] > before and opt["wins"] <= total_wins():
				names.append(tr(opt["name"]))
		if not names.is_empty():
			unlocked.append(tr(Catalog.PARTS[cat]["label"]) + ": " + ", ".join(names))
	save_game()
	return unlocked


# --- Speichern ------------------------------------------------------------

## Das Spiel hieß früher "Underground Sprint": Godot legt user:// nach dem Spielnamen an. Gibt es im neuen Ordner
## noch keinen Spielstand, wird der alte einmal herüberkopiert (der alte bleibt liegen).
func _migrate_save() -> void:
	if save_path != SAVE_PATH or FileAccess.file_exists(SAVE_PATH):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join("Underground Sprint").path_join("save.json")
	if FileAccess.file_exists(old):
		DirAccess.copy_absolute(old, ProjectSettings.globalize_path(SAVE_PATH))


func save_game() -> void:
	var text := JSON.stringify({
		"wins": wins, "drift_wins": drift_wins, "current_car": current_car, "race_index": race_index,
		"best_times": best_times, "tuning": tuning, "looks": looks, "won_events": won_events, "kept_cars": kept_cars,
		"gfx": {"preset": preset, "opts": gfx, "pixel": pixel_look, "vsync": vsync, "fps": fps_limit, "fullscreen": fullscreen,
			"touch": touch_mode, "show_fps": show_fps, "jump_cam": jump_cam, "motion_blur": motion_blur,
			"speed_fov": speed_fov, "cam_shake": cam_shake, "cam": cam_mode},
		"language": language, "difficulty": difficulty,
	}, "\t")
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	# Browser: zusätzlich im localStorage ablegen (manche Browser halten das Dateisystem eines eingebetteten Spiels
	# nicht dauerhaft, den localStorage aber schon)
	if OS.has_feature("web") and save_path == SAVE_PATH:
		JavaScriptBridge.eval("try { localStorage.setItem('%s', %s); } catch (e) {}" % [WEB_KEY, JSON.stringify(text)], true)


## Im Browser: bleibt der Spielstand erhalten? (false: das Spiel läuft in einem Rahmen, dessen Speicher der Browser
## blockiert oder beim Schließen löscht; dann hilft es, das Spiel in einem eigenen Tab zu öffnen)
func save_persistent() -> bool:
	if not OS.has_feature("web"):
		return true
	if OS.is_userfs_persistent():
		return true
	var ok = JavaScriptBridge.eval("(function () { try { localStorage.setItem('nfg_probe', '1'); localStorage.removeItem('nfg_probe'); return true; } catch (e) { return false; } })()", true)
	return ok == true


func load_game() -> void:
	_migrate_save()
	var text := ""
	if FileAccess.file_exists(save_path):
		text = FileAccess.get_file_as_string(save_path)
	elif OS.has_feature("web") and save_path == SAVE_PATH:
		var v = JavaScriptBridge.eval("(function () { try { return localStorage.getItem('%s') || ''; } catch (e) { return ''; } })()" % WEB_KEY, true)
		text = str(v) if v != null else ""
	if text == "":
		return
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	wins = int(data.get("wins", 0))
	drift_wins = int(data.get("drift_wins", 0))
	if data.has("kept_cars"):
		kept_cars = Array(data["kept_cars"]).filter(func(id): return Catalog.CARS.has(id))
	else:
		kept_cars = legacy_cars(wins, drift_wins)
	current_car = str(data.get("current_car", "kaizen"))
	if not Catalog.CARS.has(current_car):
		current_car = "kaizen"
	race_index = clampi(int(data.get("race_index", 0)), 0, Catalog.RACES.size() - 1)
	best_times = data.get("best_times", {})
	for old in Catalog.RENAMED:
		if best_times.has(old):
			best_times[Catalog.RENAMED[old]] = best_times[old]
			best_times.erase(old)
	var g: Dictionary = data.get("gfx", {})
	if g.has("opts"):
		preset = clampi(int(g.get("preset", -1)), -1, PRESETS.size() - 1)
		for k in GFX:
			gfx[k] = clampi(int(g["opts"].get(k, gfx[k])), 0, GFX[k]["levels"].size() - 1)
	elif g.has("quality"):
		apply_preset(clampi(int(g["quality"]), 0, 2))  # alter Spielstand: Niedrig/Mittel/Hoch
	show_fps = bool(g.get("show_fps", false))
	# alter Spielstand: Pixel-Stufe Stark/Mittel = Pixel-Look an
	pixel_look = bool(g.get("pixel", int(data.get("pixel_mode_v2", 2)) <= 1))
	language = str(data.get("language", ""))
	if data.has("won_events"):
		won_events = Array(data["won_events"])
	else:
		# ältere Spielstände: so viele Karriere-Events gelten als gewonnen, wie es Siege gibt
		won_events = []
		for i in mini(wins + drift_wins, Catalog.CAREER_V1.size()):
			won_events.append(Catalog.CAREER_V1[i])
	vsync = bool(g.get("vsync", true))
	fps_limit = clampi(int(g.get("fps", 0)), 0, FPS_LIMITS.size() - 1)
	fullscreen = bool(g.get("fullscreen", false))
	touch_mode = clampi(int(g.get("touch", 0)), 0, 2)
	jump_cam = clampi(int(g.get("jump_cam", 0)), 0, 2)
	motion_blur = clampi(int(g.get("motion_blur", 2)), 0, 3)
	speed_fov = bool(g.get("speed_fov", true))
	cam_shake = bool(g.get("cam_shake", true))
	cam_mode = clampi(int(g.get("cam", 0)), 0, 3)
	difficulty = clampi(int(data.get("difficulty", 1)), 0, 2)
	# Bis 2.12 hatte jedes Auto sein eigenes Tuning: übernommen wird das des zuletzt gefahrenen Autos
	var src: Dictionary = data.get("tuning", {})
	if src.is_empty():
		src = data.get("car_configs", {}).get(current_car, {})
	tuning = {}
	for cat in Catalog.PART_GROUPS["leistung"]:
		var n: int = Catalog.PARTS[cat]["options"].size()
		tuning[cat] = clampi(int(src.get(cat, 0)), 0, n - 1)
	# Optik je Auto (seit 2.25). Ältere Spielstände: die gemeinsame Optik bleibt am zuletzt gefahrenen Auto, alle
	# anderen Autos sind blank
	looks = {}
	var lsrc: Dictionary = data.get("looks", {})
	if not data.has("looks"):
		lsrc = {current_car: src}
	for id in lsrc:
		if not Catalog.CARS.has(id):
			continue
		var one := {}
		for cat in Catalog.PART_GROUPS["optik"]:
			var n: int = Catalog.PARTS[cat]["options"].size()
			var v := clampi(int(lsrc[id].get(cat, 0)), 0, n - 1)
			if v != 0:
				one[cat] = v
		if not one.is_empty():
			looks[id] = one


func reset_progress() -> void:
	wins = 0
	drift_wins = 0
	current_car = "kaizen"
	race_index = 0
	best_times = {}
	tuning = {}
	looks = {}
	won_events = []
	kept_cars = []
	save_game()


## FPS-Anzeige oben in der Mitte (Einstellung "FPS anzeigen"), dazu die aktuelle 3D-Auflösung. Dort ist in der
## Garage und im Rennen frei (Siege und Auto stehen rechts, Platz und Zeit links).
var _fps_label: Label
var _fps_t := 0.0
var render_lines := 0  # aktuelle 3D-Auflösung (Zeilen), setzt PixelView


func _build_fps_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 99
	add_child(cl)
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.offset_left = -50.0
	_fps_label.offset_right = 50.0
	_fps_label.offset_top = 2.0
	_fps_label.offset_bottom = 15.0
	_fps_label.add_theme_font_size_override("font_size", 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	_fps_label.add_theme_stylebox_override("normal", bg)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fps_label)


func _process(dt: float) -> void:
	if _fps_label == null:
		return
	_fps_label.visible = show_fps
	_fps_t -= dt
	if show_fps and _fps_t <= 0.0:
		_fps_t = 0.5
		var fps := Engine.get_frames_per_second()
		_fps_label.text = "%d FPS" % fps + ("  ·  %dp" % render_lines if render_lines > 0 else "")
		_fps_label.modulate = Color(0.4, 1.0, 0.5) if fps >= 55 else (Color(1.0, 0.85, 0.3) if fps >= 30 else Color(1.0, 0.35, 0.3))


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
