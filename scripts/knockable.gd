extends RigidBody3D
## Straßenobjekt (Laterne, Mülltonne, Hydrant, Bake ...): steht fest, bis ein Auto es trifft, dann fliegt es
## physikalisch weg und verstreut Trümmer. Der Stoß wirkt am Treffpunkt (Stoßstangenhöhe): hohe Teile wie Laternen
## knicken unten weg und kippen um, kleine fliegen und überschlagen sich. Bremst das Auto je nach Gewicht
## (slowdown), stoppt es aber nie.

const LAYER := 4  # Physik-Ebene 3
const GROUND := 8  # Ebene 4: Boden nur für umherfliegende Teile

var slowdown := 0.95
var knocked := false
var _hit_at := Vector3.INF


func _init() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = LAYER
	collision_mask = 1 | LAYER | GROUND


func knock(v: Vector3, at := Vector3.INF) -> void:
	if knocked:
		return
	knocked = true
	_hit_at = at
	_launch.call_deferred(v)


func _launch(v: Vector3) -> void:
	freeze = false
	angular_damp = 0.4
	var spd := v.length()
	var h := Vector3(v.x, 0.0, v.z)
	if _hit_at.is_finite():
		# am Treffpunkt angestoßen: die Physik macht daraus Schieben und Kippen
		var off := _hit_at - global_position
		off.y = minf(off.y, 0.8)
		apply_impulse((h * 0.7 + Vector3.UP * spd * 0.12) * mass, Vector3(0.0, off.y, 0.0))
		apply_torque_impulse(Vector3(randf_range(-0.2, 0.2), randf_range(-0.4, 0.4), randf_range(-0.2, 0.2)) * mass * spd * 0.1)
	else:
		apply_central_impulse((v * 0.8 + Vector3.UP * spd * 0.25) * mass)
		apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.3, 0.3), randf_range(-1, 1)) * mass * spd * 0.4)
	for c in get_children():
		if c is Light3D:
			c.queue_free()
	_debris(spd)
	get_tree().create_timer(12.0).timeout.connect(queue_free)


## Kleine Trümmer in der Farbe des Teils
func _debris(spd: float) -> void:
	var col := Color(0.4, 0.4, 0.42)
	for c in get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			col = c.material_override.albedo_color
			break
	var p := CPUParticles3D.new()
	p.amount = 14
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0 + spd * 0.08
	p.initial_velocity_max = 5.0 + spd * 0.18
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var m := BoxMesh.new()
	m.size = Vector3(0.14, 0.1, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	m.material = mat
	p.mesh = m
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 0.6, 0)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
