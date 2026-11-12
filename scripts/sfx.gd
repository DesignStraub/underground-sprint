extends Node
## Kurze Soundeffekte (assets/sfx, erzeugt von tools/make_sfx.py).
## Sfx.play("thud") für einmalige Effekte, Sfx.looping("rumble") für Dauer-Sounds.

const NAMES := ["horn", "bell", "rumble", "thud", "whoosh", "splash", "clang", "tunnel", "crowd", "skid", "scrub", "nitro",
	"nitro_on", "nitro_off", "backfire", "bov", "flutter", "scrape", "road", "wind", "beep", "beep_go", "turbo", "whine",
	"ui_move", "ui_change", "ui_select", "ui_back", "ui_install", "ui_locked", "ui_go"]
## Menü-Töne: Lautstärke je Art (dB). Ganz leise und kurz, damit Durchscrollen nicht nervt.
const UI_DB := {"move": -17.0, "change": -15.0, "select": -12.0, "back": -14.0, "install": -9.0, "locked": -12.0, "go": -8.0}

var streams := {}


func _ready() -> void:
	for n in NAMES:
		var p := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(p):
			streams[n] = load(p)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if not streams.has(sound):
		return null
	var a := AudioStreamPlayer.new()
	a.stream = streams[sound]
	a.volume_db = volume_db
	a.pitch_scale = pitch
	_route(a)
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)
	return a


## Menü-Ton (move, change, select, back, install, locked, go): ohne Hall, läuft auch im Pausemenü. Gleiche Töne
## kurz hintereinander (Taste gehalten) nur einmal je 45 ms.
var _ui_last := {}


func ui(kind: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_ui_last.get(kind, -1000)) < 45:
		return
	_ui_last[kind] = now
	var a := play("ui_" + kind, UI_DB.get(kind, -14.0), randf_range(0.985, 1.015))
	if a:
		a.bus = "Master"
		a.process_mode = Node.PROCESS_MODE_ALWAYS


## Endlos-Player; der Aufrufer hängt ihn ein und steuert Lautstärke/Start.
func looping(sound: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	if streams.has(sound):
		var s: AudioStreamWAV = streams[sound].duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		a.stream = s
	_route(a)
	return a


## Über den Hall-Bus (im Tunnel hallt es), falls das Rennen ihn angelegt hat
func _route(a: AudioStreamPlayer) -> void:
	if AudioServer.get_bus_index("Hall") >= 0:
		a.bus = "Hall"
