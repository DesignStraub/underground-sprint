extends Node3D
## Ortsfester Dauer-Sound (z. B. Stadion-Publikum). Lautstärke nach Abstand zum Spieler (race.gd setzt target).

var sound := ""
var radius := 200.0
var base_db := -8.0
var pitch := 1.0
var target: Node3D
var _a: AudioStreamPlayer


func _ready() -> void:
	add_to_group("ambient")
	_a = Sfx.looping(sound)
	_a.pitch_scale = pitch
	_a.volume_db = -80.0
	add_child(_a)


func _process(_dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var k := clampf(1.0 - global_position.distance_to(target.global_position) / radius, 0.0, 1.0)
	if k <= 0.0:
		if _a.playing:
			_a.stop()
		return
	if not _a.playing:
		_a.play()
	_a.volume_db = base_db + linear_to_db(k * k)
