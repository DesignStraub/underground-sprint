extends RigidBody3D
## Leichtes Straßenobjekt (Laterne, Mülltonne, Hütchen ...): steht fest, bis ein Auto es trifft,
## dann fliegt es physikalisch weg. Bremst das Auto nur leicht.

const LAYER := 4  # Physik-Ebene 3
const GROUND := 8  # Ebene 4: Boden nur für umherfliegende Teile

var slowdown := 0.95
var knocked := false


func _init() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = LAYER
	collision_mask = 1 | LAYER | GROUND


func knock(v: Vector3) -> void:
	if knocked:
		return
	knocked = true
	_launch.call_deferred(v)


func _launch(v: Vector3) -> void:
	freeze = false
	var spd := v.length()
	apply_central_impulse((v * 0.8 + Vector3.UP * spd * 0.25) * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * mass * spd * 0.4)
	for c in get_children():
		if c is Light3D:
			c.queue_free()
	get_tree().create_timer(12.0).timeout.connect(queue_free)
