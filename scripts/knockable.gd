extends RigidBody3D
## Leichtes Straßenobjekt (Laterne, Mülltonne, Leitkegel, Zeitungsbox, Schild ...): steht fest, bis ein Auto es trifft,
## dann fliegt es weg und verstreut Trümmer. Schweres und fest Verankertes (Hydrant, Poller, Haltestelle, Bäume ...)
## ist kein Knockable, sondern hart (track_builder._build_props).
## Seit 2.35: kinematisch eingefroren (der Fühler des Autos sah statisch eingefrorene Teile mit Jolt nie, man fuhr durch
## alles hindurch); fliegt schneller als das Auto und zur Seite davon (vorher mit 0,7-fachem Tempo geradeaus: das Auto
## holte es ein). Laternen kippen von der Straße weg und blenden kurz nach der Landung aus, alles andere nach ein paar
## Sekunden (vorher verschwand es nach 12 s schlagartig). Bremst das Auto je nach Gewicht (slowdown,
## player_car._on_prop_hit; Laterne gut 94 % Tempo bleiben), stoppt es aber nie.

const TireFx := preload("res://scripts/tire_fx.gd")

const LAYER := 4  # Physik-Ebene 3
const GROUND := 8  # Ebene 4: Boden nur für umherfliegende Teile
const FADE := 0.7  # s zum Ausblenden

var slowdown := 0.95
var knocked := false
var lamp := false  # Laterne: hoch und schwer, kippt weg und verschwindet bald nach der Landung
var _hit_at := Vector3.INF
var _t := 0.0  # s seit dem Treffer
var _fade := -1.0  # >= 0: blendet aus
var _calm := 0.0  # s, die das Teil schon fast still liegt
var _floor := -INF  # Fahrbahnhöhe am Standort (Welt-y): darunter fällt das Teil nicht (_integrate_forces)


func _init() -> void:
	freeze = true
	# kinematisch eingefroren, nicht statisch: der Fühler des Autos (Area3D, player_car) bemerkt mit Jolt (Standard seit
	# Godot 4.6) keine statischen Körper. Bis 2.34 fuhr man deshalb durch Laternen, Mülleimer und Leitkegel hindurch.
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = LAYER
	collision_mask = 1 | LAYER | GROUND


## Godot schaltet _physics_process beim Eintritt in den Baum von selbst ein: erst nach dem Treffer gebraucht
func _ready() -> void:
	set_physics_process(knocked)


func knock(v: Vector3, at := Vector3.INF) -> void:
	if knocked:
		return
	knocked = true
	_hit_at = at
	_launch.call_deferred(v)


func _launch(v: Vector3) -> void:
	if not is_inside_tree():
		return
	freeze = false
	linear_damp = 0.35  # Luftwiderstand: fliegt nicht hunderte Meter weit
	angular_damp = 0.6
	# Boden auf Fahrbahnhöhe (Teile stehen auf dem Gehweg): auf Kuppen und Dämmen läge die Bodenebene der Strecke tiefer,
	# und mit Jolt reicht sie nur 1 km um den Ursprung der Strecke (physics/jolt_physics_3d/limits/world_boundary_shape_size)
	_floor = global_position.y - 0.2
	var spd := v.length()
	var fwd := Vector3(v.x, 0.0, v.z)
	if fwd.length() < 0.5:
		fwd = -global_basis.z
		fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	# zur Seite, auf der das Teil neben der Fahrzeugmitte stand (mittig getroffen: zufällig, aber nie geradeaus,
	# sonst führe das Auto hinterher hindurch)
	var lat := 0.0
	if _hit_at.is_finite():
		lat = clampf((global_position - _hit_at).dot(right) / 0.9, -1.0, 1.0)
	if absf(lat) < 0.4:
		var sg := signf(lat) if absf(lat) > 0.05 else (1.0 if randf() < 0.5 else -1.0)
		lat = sg * randf_range(0.4, 0.6)
	var out := (fwd + right * lat * 0.6).normalized()
	if lamp:
		# Mast wird am Fuß weggerissen und kippt von der Straße weg, der Fuß bleibt vor dem Auto
		linear_velocity = out * spd * 1.08 + Vector3.UP * (2.0 + spd * 0.05)
		angular_velocity = Vector3.UP.cross(out).normalized() * clampf(0.8 + spd * 0.03, 1.0, 2.4) \
			+ Vector3.UP * randf_range(-0.5, 0.5)
	else:
		# leichte Teile fliegen deutlich schneller als das Auto davon, schwerere knapp; sie überschlagen sich dabei
		var k := clampf(1.3 - mass / 150.0, 1.05, 1.25)
		linear_velocity = out * spd * k + Vector3.UP * (2.0 + spd * 0.11)
		angular_velocity = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * clampf(spd * 0.25, 2.0, 12.0)
	for c in get_children():
		if c is Light3D:
			c.queue_free()
	_debris(spd)
	set_physics_process(true)


## Boden auf Fahrbahnhöhe: das Teil bleibt auf der Straße liegen, statt (an Kuppen, weit vom Ursprung der Strecke)
## hindurchzufallen
func _integrate_forces(st: PhysicsDirectBodyState3D) -> void:
	if _floor == -INF:
		return
	var com: Vector3 = st.transform.origin + st.center_of_mass
	var low := _floor + 0.18
	if com.y >= low:
		return
	var xf := st.transform
	xf.origin.y += low - com.y
	st.transform = xf
	var lv := st.linear_velocity
	if lv.y < 0.0:
		lv.y = -lv.y * 0.2
	lv.x *= 0.96
	lv.z *= 0.96
	st.linear_velocity = lv
	st.angular_velocity *= 0.95


func _physics_process(dt: float) -> void:
	if not knocked:
		set_physics_process(false)
		return
	_t += dt
	if _fade >= 0.0:
		_fade += dt
		var a := clampf(_fade / FADE, 0.0, 1.0)
		for c in get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).transparency = a
		if _fade >= FADE:
			queue_free()
		return
	# liegt es (fast) still? Laterne: kurz danach ausblenden; Kleinkram darf ein paar Sekunden liegen bleiben
	if _t > 0.6 and linear_velocity.length() < 2.5:
		_calm += dt
	else:
		_calm = 0.0
	if _calm > (0.8 if lamp else 5.0) or _t > (4.0 if lamp else 9.0):
		_fade = 0.0


## Kleine Trümmer in der Farbe des Teils: Splitter, die sich drehen, und etwas Staub (bis 2.35 starre Kästchen)
func _debris(spd: float) -> void:
	var col := Color(0.4, 0.4, 0.42)
	for c in get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			col = c.material_override.albedo_color
			break
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.7
	var p := TireFx.shards(mat, 0.17)
	p.amount = 12
	p.lifetime = 1.4
	p.initial_velocity_min = 2.0 + spd * 0.08
	p.initial_velocity_max = 5.0 + spd * 0.18
	get_parent().add_child(p)
	p.global_position = global_position + Vector3(0, 0.6, 0)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	TireFx.dust_puff(get_parent(), global_position + Vector3(0, 0.4, 0), 4, 0.8)
