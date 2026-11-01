extends Node
## Kurze Soundeffekte (assets/sfx, erzeugt von tools/make_sfx.py).
## Sfx.play("thud") für einmalige Effekte, Sfx.looping("rumble") für Dauer-Sounds.

const NAMES := ["horn", "bell", "rumble", "thud", "whoosh", "splash", "clang", "tunnel", "crowd"]

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
