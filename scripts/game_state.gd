extends Node
## Spielstand: Siege, aktuelles Auto, Tuning. Kein Geld, nur Freischalten über Siege.
## Leistungsteile gelten für alle eigenen Autos (ein Satz für die ganze Garage). Die Optik (Lack, Felgen, Folie, Bodykit
## usw.) steht je Auto im Spielstand (looks, seit 2.25) und kommt seit 2.38 beim Autowechsel mit wie in NFS Underground:
## das neue Auto übernimmt die Optik des Autos, von dem man kommt (switch_car). 2.25 bis 2.37 war ein neu gewähltes Auto
## blank (ab Werk); bis 2.24 galt die Optik für alle Autos zugleich.

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
## Rajdhani (Indian Type Foundry, SIL Open Font License 1.1, siehe assets/fonts/rajdhani/OFL.txt), seit 2.28 statt Saira
const FONT := preload("res://assets/fonts/D-DIN-Bold.otf")
const FONT_WIDE := preload("res://assets/fonts/D-DINCondensed-Bold.otf")
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
var world_drift := false  # Open World: Drift-Modus (Q), bleibt über Rennen und Garage hinweg
## Open World (seit 2.42): letzter sicherer Ort [x, y, z, Blickrichtung], dort geht es beim Losfahren weiter (leer: noch
## nie gefahren, Start in Frankfurt). Die Welt merkt ihn alle paar Sekunden, auf einer Fahrbahn oder im Gelände.
var world_pos: Array = []
## Entdeckte Städte (seit 2.42): Schnellreise geht nur dorthin. Ältere Spielstände: Städte, in denen man schon ein Rennen
## gewonnen oder eine Bestzeit hat, gelten als entdeckt.
var towns_known: Array = []
## Entdeckte Orte außer Städten (seit 2.49): "gelaende:<Name>", "hw:<Name>" (Start eines Autobahn-Rennens); die große
## Karte springt nur dorthin, wo man schon war
var places_known: Array = []
var last_town := ""  # zuletzt erreichte Stadt: Start an ihrem Eingang, falls der gemerkte Ort nicht mehr befahrbar ist
var highway_won: Array = []  # gewonnene Autobahn-Rennen (seit 2.43, highway_race.gd): Name; Bestzeiten in best_times
var drift_best := {}  # Driftzonen (seit 2.45): Zone ("Ort#Rennen") -> beste Punktzahl
var world_menu := ""  # Open World > Esc > Tuning/Autohaus: Garage öffnet dort, "Fertig" führt zurück in die Welt
var in_world := false  # Rennen aus der Open World gestartet: danach zurück in die Welt (nicht gespeichert)
var split := false  # Splitscreen für zwei (seit 2.47, nur am Rechner): das nächste Rennen mit Spieler 2
var p2_car := ""  # Auto von Spieler 2 im Splitscreen
var best_times := {}  # Rennname -> Sekunden
var outruns := 0  # Open World: abgehängte Herausforderer (Duelle auf der Autobahn)
var xp := 0  # Fahrer-Erfahrung (seit 2.32): Stilpunkte aus Driften, knapp vorbei, Sprüngen, Duellen und Rennen
var xp_dirty := false  # XP seit dem letzten Speichern (die Welt speichert gesammelt, nicht bei jedem Punkt)
signal level_up(lvl: int, lines: Array)
var won_events: Array = []  # gewonnene Events (Karriere: genug Siege in einer Stufe öffnen die nächste)
var test_cfg := {}  # --cfg (nur Tests)
var tuning := {}  # Leistungsteile: category -> option_index, für alle Autos gemeinsam
var looks := {}  # Optik je Auto: car_id -> {category: option_index}; fehlt ein Wert, gilt 0 (ab Werk). Beim Autowechsel
# übernimmt das neue Auto die Optik des alten (switch_car, seit 2.38)
var kept_cars: Array = []  # schon mit den alten Schwellen (bis 2.10, Siege bis 2.32) freigeschaltete Autos bleiben frei
var kept_parts: Array = []  # "cat:index": bis 2.32 mit Siegen freigeschaltete Teile bleiben frei
var kept_stages: Array = []  # bis 2.32 mit Siegen geöffnete Karriere-Stufen bleiben offen
var title := 0  # gewählter Fahrer-Titel (Catalog.TITLES), muss frei sein
const PROG := 2  # Fortschritts-Stand: 2 = alles über das Fahrer-Level (seit 2.33)


func _ready() -> void:
	# Schrift im Stil der deutschen Straßenschilder (DIN 1451) für alles: Menü, HUD, Schilder in der Welt
	ThemeDB.fallback_font = FONT
	SignIcons.warm()  # Laden-Piktogramme im Hauptthread anlegen (die Welt baut in Hintergrund-Threads)
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
	_add_action("map", [KEY_M, KEY_TAB], [JOY_BUTTON_LEFT_STICK], [])  # Open World: große Karte
	# Menü mit Esc (im Browser-Vollbild beendet Esc nur das Vollbild: dort P); Enter bestätigt nur
	_add_action("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_add_action("next_track", [KEY_PERIOD], [], [])  # nächster Musiktitel (M ist seit der Open World die Karte)
	_add_action("radio", [KEY_COMMA], [], [])  # nächster Radiosender
	_add_action("drift_toggle", [KEY_Q], [JOY_BUTTON_X], [])  # Open World: Fahr- und Drift-Modus umschalten
	_add_action("ban_track", [KEY_SLASH], [], [])  # Track aussortieren (deutsche Tastatur: "-")
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


## Stufe s ist offen ab ihrem Fahrer-Level (seit 2.33), oder sie war mit Siegen schon offen (bis 2.32)
func stage_open(s: int) -> bool:
	return s <= 0 or level() >= int(Catalog.STAGES[s]["level"]) or s in kept_stages


## Bis 2.32: Stufe offen, wenn die vorige offen ist und darin genug Siege stehen (nur noch für alte Spielstände)
func _stage_open_wins(s: int) -> bool:
	if s <= 0:
		return true
	return _stage_open_wins(s - 1) and stage_wins(s - 1) >= Catalog.stage_need(s - 1)


## Gesperrtes Karriere-Event: "ab Level 7", sonst ""
func lock_text(event_name: String) -> String:
	if career_open(event_name):
		return ""
	var s := Catalog.stage_of(event_name)
	return tr("ab Level %d") % int(Catalog.STAGES[s]["level"]) if s > 0 else tr("gesperrt")


## Karriere-Event frei: seine Stufe ist offen, oder es war nach der alten Kette (bis 2.15) schon offen
func career_open(event_name: String) -> bool:
	var ri := Catalog.race_index(event_name)
	if ri >= 0 and Catalog.RACES[ri].get("free", false):
		return true  # außerhalb der Karriere, immer offen (Driftberg)
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


## Splitscreen (seit 2.47): Spieler 1 fährt mit WASD, Leertaste, linker Umschalttaste und dem ersten Gamepad, Spieler 2
## mit den Pfeiltasten, rechter Umschalttaste (Handbremse), Enter (Nitro), Rücktaste (zurücksetzen) und dem zweiten
## Gamepad. on=false stellt die normale Belegung wieder her.
const SPLIT_P1 := ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "nitro", "shift_up", "shift_down", "reset_car"]
var _split_saved := {}


func split_input(on: bool) -> void:
	if on and _split_saved.is_empty():
		for a in SPLIT_P1:
			_split_saved[a] = InputMap.action_get_events(a)
			InputMap.action_erase_events(a)
			for ev in _split_saved[a]:
				if ev is InputEventKey and (ev as InputEventKey).physical_keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
					continue  # Pfeiltasten gehören Spieler 2
				var e2: InputEvent = ev.duplicate()
				if e2 is InputEventKey and (e2 as InputEventKey).physical_keycode == KEY_SHIFT:
					(e2 as InputEventKey).location = KEY_LOCATION_LEFT
				if e2 is InputEventJoypadButton or e2 is InputEventJoypadMotion:
					e2.device = 0
				InputMap.action_add_event(a, e2)
		var p2 := {"accelerate": [[KEY_UP], [], [JOY_AXIS_TRIGGER_RIGHT, 1.0]], "brake": [[KEY_DOWN], [], [JOY_AXIS_TRIGGER_LEFT, 1.0]],
			"steer_left": [[KEY_LEFT], [], [JOY_AXIS_LEFT_X, -1.0]], "steer_right": [[KEY_RIGHT], [], [JOY_AXIS_LEFT_X, 1.0]],
			"handbrake": [[KEY_SHIFT], [JOY_BUTTON_B], []], "nitro": [[KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_A], []],
			"shift_up": [[KEY_PAGEUP], [JOY_BUTTON_RIGHT_SHOULDER], []], "shift_down": [[KEY_PAGEDOWN], [JOY_BUTTON_LEFT_SHOULDER], []],
			"reset_car": [[KEY_BACKSPACE], [JOY_BUTTON_BACK], []]}
		for a in p2:
			var name: String = "p2_" + str(a)
			if InputMap.has_action(name):
				InputMap.erase_action(name)
			InputMap.add_action(name, 0.15)
			for k in p2[a][0]:
				var ev := InputEventKey.new()
				ev.physical_keycode = k
				if k == KEY_SHIFT:
					ev.location = KEY_LOCATION_RIGHT
				InputMap.action_add_event(name, ev)
			for b in p2[a][1]:
				var jb := InputEventJoypadButton.new()
				jb.button_index = b
				jb.device = 1
				InputMap.action_add_event(name, jb)
			if p2[a][2].size() == 2:
				var jm := InputEventJoypadMotion.new()
				jm.axis = p2[a][2][0]
				jm.axis_value = p2[a][2][1]
				jm.device = 1
				InputMap.action_add_event(name, jm)
	elif not on and not _split_saved.is_empty():
		for a in _split_saved:
			InputMap.action_erase_events(a)
			for ev in _split_saved[a]:
				InputMap.action_add_event(a, ev)
		_split_saved = {}


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


## Tempo-Stufe: am Anfang fahren alle langsamer, mit jedem Sieg etwas schneller, ab 20 Siegen das volle Tempo. Seit
## 2.49 ruhiger (vorher 72 % bis 100 %): Grundtempo war zu hoch. Underground holte das Tempogefühl aus Unschärfe,
## Lichtspuren und Kamera, nicht aus mehr km/h; enge Stadtstraßen wirken schon bei 160 km/h schnell.
func pace() -> float:
	return 0.66 + 0.24 * clampf(total_wins() / 20.0, 0.0, 1.0)


## Anteil der Beschleunigung zur Tempo-Stufe (für alle gleich: Spieler, Gegner, Spieler 2). Seit 2.49 etwas weniger
## Schub (vorher 0,8 + 0,2 · pace): Anfahren und Durchzug wirkten zu spritzig.
func accel_k() -> float:
	return 0.74 + 0.2 * pace()


# --- Fahrer-Level (seit 2.32) ------------------------------------------------
## Wie in einem Rollenspiel: Stilpunkte (Driften, knapp vorbei, Sprünge, Duelle, Rennen) sind Erfahrung, jedes Level
## braucht etwas mehr als das vorige. Seit 2.33 schaltet das Level alles frei (Stufen, Autos, Teile, Vinyls, Titel),
## die Kurve ist dafür flacher: Level 10 nach gut 25 000 XP, Level 20 nach gut 110 000, Level 30 nach knapp 280 000.
## Kein oberes Ende (bis 99).
static func xp_need(lvl: int) -> int:
	return int(round((1000.0 + 300.0 * pow(float(maxi(lvl - 1, 0)), 1.25)) / 50.0)) * 50


## {level, into (XP im aktuellen Level), need (XP für das nächste)}
func level_info(total := -1) -> Dictionary:
	var rest := xp if total < 0 else total
	var lvl := 1
	while lvl < 99 and rest >= xp_need(lvl):
		rest -= xp_need(lvl)
		lvl += 1
	return {"level": lvl, "into": rest, "need": xp_need(lvl)}


func level() -> int:
	return level_info()["level"]


## XP gutschreiben. Liefert für jedes neue Level eine Zeile und was es freischaltet; meldet es auch über level_up.
## save: sofort speichern (Rennen); die Welt sammelt (xp_dirty) und speichert alle paar Sekunden.
func add_xp(n: int, save := true) -> Array:
	if n <= 0:
		return []
	var l0 := level()
	xp += n
	xp_dirty = true
	var l1 := level()
	var lines := []
	for l in range(l0 + 1, l1 + 1):
		lines.append(tr("LEVEL %d") % l)
		for r in Catalog.level_rewards(l):
			if not (r["kind"] == "car" and r["id"] in kept_cars) and not (r["kind"] == "stage" and r["index"] in kept_stages) \
					and not (r["kind"] in ["part", "vinyl"] and "%s:%d" % [r["cat"], r["index"]] in kept_parts):
				lines.append(reward_text(r))
	if save or l1 > l0:
		save_game()
	if l1 > l0:
		level_up.emit(l1, lines)
	return lines


## "Auto: Kaido 2000GT", "Stufe 3: Hafen und Altstadt", "Vinyl: Sakura", "Motor: Stufe 1", "Titel: Phantom"
func reward_text(r: Dictionary) -> String:
	match r["kind"]:
		"car":
			return tr("Auto: ") + str(r["name"])
		"stage":
			return tr("STUFE %d: %s") % [int(r["index"]) + 1, tr(str(r["name"]))]
		"title":
			return tr("Titel: ") + tr(str(r["name"]))
		"vinyl":
			return tr("Vinyl: ") + tr(str(r["name"]))
	return tr(Catalog.PARTS[r["cat"]]["label"]) + ": " + tr(str(r["name"]))


func is_car_unlocked(car_id: String) -> bool:
	var req: Dictionary = Catalog.CARS[car_id]["unlock"]
	return req.is_empty() or car_id in kept_cars or level() >= int(req.get("level", 0))


## Bis 2.32: Auto mit Siegen frei (für den Umstieg alter Spielstände)
static func _car_by_wins(car_id: String, rw: int, dw: int) -> bool:
	var req: Dictionary = Catalog.WIN_UNLOCK.get(car_id, {})
	return (req.has("race") and rw >= req["race"]) or (req.has("drift") and dw >= req["drift"])


## Spielstand von vor 2.11: was nach den alten Schwellen schon frei war, bleibt frei
static func legacy_cars(race_w: int, drift_w: int) -> Array:
	var out := []
	for id in Catalog.LEGACY_UNLOCK:
		var req: Dictionary = Catalog.LEGACY_UNLOCK[id]
		if (req.has("race") and race_w >= req["race"]) or (req.has("drift") and drift_w >= req["drift"]):
			out.append(id)
	return out


## "Fahrer-Level 12"
func unlock_text(car_id: String) -> String:
	return tr("Fahrer-Level %d") % int(Catalog.CARS[car_id]["unlock"].get("level", 1))


func is_part_unlocked(category: String, index: int) -> bool:
	return level() >= int(Catalog.PARTS[category]["options"][index].get("level", 0)) or "%s:%d" % [category, index] in kept_parts


## Titel t (Catalog.TITLES) ist frei
func title_unlocked(t: int) -> bool:
	return t >= 0 and t < Catalog.TITLES.size() and level() >= int(Catalog.TITLES[t]["level"])


func title_name() -> String:
	return tr(Catalog.TITLES[title if title_unlocked(title) else 0]["name"])



## Eingebautes Tuning eines Autos (neues Dictionary): Leistung für alle gleich, Optik je Auto (fehlt: ab Werk)
func get_config(car_id := "") -> Dictionary:
	var id := car_id if car_id != "" else current_car
	return _config_with(looks.get(id, {}))


## Tuning, das das Auto to_id nach einem Wechsel vom jetzigen Auto hätte (Vorschau im Autohaus): Leistung wie immer,
## Optik vom jetzigen Auto mitgenommen (carried_looks)
func switch_config(to_id: String) -> Dictionary:
	return _config_with(carried_looks(current_car, to_id))


## Autowechsel (seit 2.38 wie in NFS Underground): was man angebaut hat, ist auch am neuen Auto dran. Das neue Auto
## übernimmt die Optik des bisherigen (seine eigene, gespeicherte wird dabei ersetzt), Leistungsteile gelten ohnehin für
## alle Autos.
func switch_car(to_id: String) -> void:
	if to_id == current_car or not Catalog.CARS.has(to_id):
		return
	var lk := carried_looks(current_car, to_id)
	if lk.is_empty():
		looks.erase(to_id)
	else:
		looks[to_id] = lk
	current_car = to_id


## Optik, die das Auto to_id beim Wechsel vom Auto from_id bekommt. Dieselben Nummern: "Serie" (Platz 0) heißt am neuen
## Auto dessen eigenes Werksteil (Werkslack, Werksfelge, Serien-Haube …). Feste Zoll-Größen (13" bis 24") rücken um den
## Unterschied der Werksfelgen beider Autos (2 Zoll über Werk bleiben 2 Zoll über Werk), höchstens 24" und nicht unter
## das, was am neuen Auto über die Bremse passt; "Standard" bleibt Standard. Ausgeblendete Motive (alte Vinyls ohne Bild)
## und noch gesperrte Teile kommen nicht mit (Serie). Kommt vom bisherigen Auto nichts mit (alles Serie, oder nur eine
## Folienfarbe ohne Motiv, ein ausgeblendetes altes Motiv), behält das neue seine eigene Optik. Sonst ersetzt die
## mitgenommene Optik die gespeicherte des neuen Autos (Spielstände von 2.25 bis 2.37 mit je Auto gestalteter Optik:
## so gewollt, wie in Underground).
func carried_looks(from_id: String, to_id: String) -> Dictionary:
	var src := _carry_src(from_id) if from_id != to_id else {}
	if src.is_empty():
		return (looks.get(to_id, {}) as Dictionary).duplicate()  # bleibt, wie es ist
	var out := {}
	for cat in src:
		var v: int = src[cat]
		if cat == "rimsize":
			v = carry_rimsize(v, from_id, to_id)
		if v != 0:
			out[cat] = v
	return out


## Was von diesem Auto beim Wechsel mitkäme (Zoll noch nicht umgerechnet): ohne Serie, ausgeblendete alte Motive und
## gesperrte Teile, die Folienfarbe nur mit einem Motiv (allein sieht man sie nicht)
func _carry_src(car_id: String) -> Dictionary:
	var src: Dictionary = looks.get(car_id, {})
	var out := {}
	for cat in Catalog.PART_GROUPS["optik"]:
		var opts: Array = Catalog.PARTS[cat]["options"]
		var v := clampi(int(src.get(cat, 0)), 0, opts.size() - 1)
		if v == 0:
			continue
		if cat == "vinyl" and opts[v].get("hidden", false):
			continue
		if not is_part_unlocked(cat, v):
			continue
		out[cat] = v
	if not out.has("vinyl"):
		out.erase("vinylcol")
	return out


## Käme von diesem Auto beim Wechsel etwas mit (sichtbar angebaut, nicht alles Serie)? Gleiche Regel wie carried_looks,
## damit der Hinweis im Autohaus stimmt.
func has_looks(car_id: String) -> bool:
	return not _carry_src(car_id).is_empty()


## Feste Felgengröße beim Autowechsel: gleicher Abstand zur Werksgröße (Catalog.FACTORY_RIMS), in den Grenzen des neuen
## Autos (13" bis 24", mindestens min_in aus car_builder.rim_spec). Standard und die alten relativen Größen (bis 2.36,
## gelten ohnehin relativ zur Felge) bleiben, wie sie sind.
static func carry_rimsize(idx: int, from_id: String, to_id: String) -> int:
	var opts: Array = Catalog.PARTS["rimsize"]["options"]
	if idx <= 0 or idx >= opts.size() or not opts[idx].has("abs"):
		return idx
	var fallback := ["std", 7, Color(0.62, 0.63, 0.66), 16, 5]
	var d := int(Catalog.FACTORY_RIMS.get(to_id, fallback)[3]) - int(Catalog.FACTORY_RIMS.get(from_id, fallback)[3])
	# car_builder erst hier laden (hängt selbst an GameState, siehe _migrate_rimsize)
	var builder: GDScript = load("res://scripts/car_builder.gd")
	var lo := maxi(13, int(builder.rim_spec(to_id, {})["min_in"]))
	var inch := clampi(int(opts[idx]["abs"]) + d, lo, 24)
	return maxi(Catalog.rimsize_index(inch), 0)


func _config_with(lk: Dictionary) -> Dictionary:
	var cfg := {}
	for cat in Catalog.PART_ORDER:
		cfg[cat] = int((tuning if cat in Catalog.PART_GROUPS["leistung"] else lk).get(cat, 0))
		# Leistungsteile kommen mit Siegen: ist ein eingebautes (noch) gesperrt, gilt die beste freie Stufe darunter
		if cat in Catalog.PART_GROUPS["leistung"]:
			while cfg[cat] > 0 and not is_part_unlocked(cat, cfg[cat]):
				cfg[cat] -= 1
	return cfg


## Teil einbauen: Leistung für alle Autos, Optik an diesem Auto (beim Autowechsel kommt sie mit, switch_car)
func set_part(car_id: String, cat: String, idx: int) -> void:
	if cat in Catalog.PART_GROUPS["leistung"]:
		tuning[cat] = idx
	else:
		if not looks.has(car_id):
			looks[car_id] = {}
		looks[car_id][cat] = idx


func part(car_id: String, category: String) -> Dictionary:
	return Catalog.PARTS[category]["options"][get_config(car_id)[category]]


## Sieg zählen (Drift-Events als Driftsieg, sonst Rennsieg). Freigeschaltet wird seit 2.33 nur noch über das Level
## (add_xp), die Siege zählen für das Tempo der Gegner (pace) und die Statistik.
func register_win(event_type: String) -> void:
	if event_type == "drift":
		drift_wins += 1
	else:
		wins += 1
	save_game()


## Umstieg auf das Fahrer-Level (Spielstand von vor 2.33): was mit Siegen schon frei war, bleibt frei, und die
## gewonnenen Events zählen als Erfahrung nach der neuen Rechnung (Catalog.race_xp mit Erstsieg), falls das mehr ist
func _migrate_prog() -> void:
	for id in Catalog.CAR_ORDER:
		if not id in kept_cars and _car_by_wins(id, wins, drift_wins):
			kept_cars.append(id)
	for cat in Catalog.PART_ORDER:
		var opts: Array = Catalog.PARTS[cat]["options"]
		for i in opts.size():
			var key := "%s:%d" % [cat, i]
			if int(opts[i]["wins"]) > 0 and total_wins() >= int(opts[i]["wins"]) and not key in kept_parts:
				kept_parts.append(key)
	for s in range(1, Catalog.STAGES.size()):
		if _stage_open_wins(s) and not s in kept_stages:
			kept_stages.append(s)
	var floor_xp := 0
	for ev in won_events:
		var ri := Catalog.race_index(str(ev))
		if ri >= 0:
			floor_xp += Catalog.race_xp(int(Catalog.RACES[ri].get("tier", 1)), 1, true)
	xp = maxi(xp, floor_xp)


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
	xp_dirty = false
	var text := JSON.stringify({
		"wins": wins, "drift_wins": drift_wins, "current_car": current_car, "race_index": race_index,
		"best_times": best_times, "tuning": tuning, "looks": looks, "won_events": won_events, "kept_cars": kept_cars, "outruns": outruns, "xp": xp,
		"kept_parts": kept_parts, "kept_stages": kept_stages, "prog": PROG, "title": title,
		"gfx": {"preset": preset, "opts": gfx, "pixel": pixel_look, "vsync": vsync, "fps": fps_limit, "fullscreen": fullscreen,
			"touch": touch_mode, "show_fps": show_fps, "jump_cam": jump_cam, "motion_blur": motion_blur,
			"speed_fov": speed_fov, "cam_shake": cam_shake, "cam": cam_mode},
		"language": language, "difficulty": difficulty,
		"world_pos": world_pos, "towns_known": towns_known, "last_town": last_town, "highway_won": highway_won,
		"drift_best": drift_best, "places_known": places_known,
	}, "\t")
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
	# Browser: zusätzlich im localStorage ablegen (manche Browser halten das Dateisystem eines eingebetteten Spiels
	# nicht dauerhaft, den localStorage aber schon)
	if OS.has_feature("web") and save_path == SAVE_PATH:
		JavaScriptBridge.eval("try { localStorage.setItem('%s', %s); } catch (e) {}" % [WEB_KEY, JSON.stringify(text)], true)


## Stadt entdeckt? (Schnellreise dorthin frei)
func town_known(town: String) -> bool:
	return town in towns_known


## Ort (Gelände, Autobahn-Rennen …) schon entdeckt? Schlüssel "<art>:<Name>" (seit 2.49)
func place_known(key: String) -> bool:
	return key in places_known


## Ort erreicht: true, wenn er neu ist (dann ein Sprungziel auf der Karte)
func reach_place(key: String) -> bool:
	if key == "" or key in places_known:
		return false
	places_known.append(key)
	return true


## Stadt erreicht: merkt sie als letzte; true, wenn sie neu entdeckt ist (dann frei für die Schnellreise)
func reach_town(town: String) -> bool:
	if town == "":
		return false
	last_town = town
	if town in towns_known:
		return false
	towns_known.append(town)
	return true


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
	outruns = int(data.get("outruns", 0))
	# Spielstand von vor 2.32 (ohne XP): bisherige Siege und Duelle zählen als Erfahrung, niemand fängt bei Level 1 an
	xp = int(data.get("xp", (int(data.get("wins", 0)) + int(data.get("drift_wins", 0))) * 1200 + outruns * 600))
	kept_parts = Array(data.get("kept_parts", [])).map(func(k): return str(k))
	kept_stages = Array(data.get("kept_stages", [])).map(func(k): return int(k))
	title = int(data.get("title", 0))
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
	world_pos = []
	var wp = data.get("world_pos", [])
	if typeof(wp) == TYPE_ARRAY and wp.size() == 4:
		world_pos = Array(wp).map(func(v): return float(v))
	last_town = str(data.get("last_town", ""))
	highway_won = Array(data.get("highway_won", [])).map(func(n): return str(n))
	drift_best = {}
	var db = data.get("drift_best", {})
	if typeof(db) == TYPE_DICTIONARY:
		for k in db:
			drift_best[str(k)] = int(db[k])
	places_known = Array(data.get("places_known", [])).map(func(t): return str(t))
	if data.has("towns_known"):
		towns_known = Array(data["towns_known"]).map(func(t): return str(t))
	else:
		towns_known = []
		for r in Catalog.RACES:
			var t: String = r.get("town", "")
			if t != "" and not t in towns_known and (r["name"] in won_events or best_times.has(r["name"])):
				towns_known.append(t)
	if int(data.get("prog", 1)) < PROG:
		_migrate_prog()
	# Bis 2.12 hatte jedes Auto sein eigenes Tuning: übernommen wird das des zuletzt gefahrenen Autos
	var src: Dictionary = data.get("tuning", {})
	if src.is_empty():
		src = data.get("car_configs", {}).get(current_car, {})
	tuning = {}
	for cat in Catalog.PART_GROUPS["leistung"]:
		var n: int = Catalog.PARTS[cat]["options"].size()
		tuning[cat] = clampi(int(src.get(cat, 0)), 0, n - 1)
	# Optik je Auto (seit 2.25). Ältere Spielstände: die gemeinsame Optik bleibt am zuletzt gefahrenen Auto (seit 2.38
	# kommt sie von dort beim Autowechsel mit)
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
	_migrate_rimsize()


## Zoll bis 2.36 relativ zur Standardgröße der Felge (Plätze 1–5: -1, +1 … +4 Zoll): umrechnen auf die feste Größe, die das
## Auto damit hatte (alte Rechnung: Werk + Aufschlag der Felge, höchstens so groß, dass 4,5 cm Flanke blieben). Die alten
## Plätze stehen ausgeblendet im Katalog und gelten weiter (Gegner, Tests), die Garage zeigt sie nicht mehr. car_builder
## (Radgrößen der Autos) erst hier laden, er hängt selbst an GameState.
func _migrate_rimsize() -> void:
	var builder: GDScript = null
	for id in looks:
		var v := int(looks[id].get("rimsize", 0))
		if v < 1 or v > 5:
			continue
		if builder == null:
			builder = load("res://scripts/car_builder.gd")
		var shape: Dictionary = builder.SHAPES.get(id, builder.SHAPES["kaizen"])
		var max_old := floori((float(shape.get("wheel_r", 0.32)) - 0.045) / 0.0127)
		var fac: Array = Catalog.FACTORY_RIMS.get(id, ["std", 7, Color(0.62, 0.63, 0.66), 16, 5])
		var rim := Catalog.part_of(looks[id], "rims")
		var std_old := mini(int(fac[3]) + int(rim.get("plus", 0)), max_old)
		var inch := clampi(std_old + int(Catalog.PARTS["rimsize"]["options"][v]["inch"]), 13, max_old)
		looks[id]["rimsize"] = maxi(Catalog.rimsize_index(inch), 0)


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
	kept_parts = []
	kept_stages = []
	title = 0
	xp = 0
	world_pos = []
	towns_known = []
	places_known = []
	last_town = ""
	highway_won = []
	drift_best = {}
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
