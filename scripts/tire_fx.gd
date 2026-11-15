extends Node3D
## Reifenqualm und Reifenspuren (seit 2.35), hängt am Spielerauto. Stärke aus dem Reifenrutschen (player_car: dieselbe
## Größe wie das Quietschen): ab gut der Hälfte zeichnen die Hinterräder dunkle Spuren auf den Boden, im Drift, beim
## Durchdrehen und bei der Handbremse qualmen sie dazu. Dezent: heller, halb durchsichtiger Qualm, der aufsteigt und
## vergeht; Spuren verblassen langsam (frei fahren 45 s, im Drift-Event 150 s: die Spur der letzten Runde liegt noch da).
## Spuren sind ein MultiMesh (ein Zeichenaufruf, je Takt und Rad ein neues Stück), Qualm zwei CPUParticles3D.

const SEG_MAX := 2000  # Teilstücke je Rad (Ringpuffer, das älteste wird überschrieben)
const SEG_LEN := 0.8  # m je Teilstück
const MARK_W := 0.24
const MARK_FROM := 0.5  # ab dieser Rutsch-Stärke Spuren
const SMOKE_FROM := 0.62  # ab hier Qualm
const SKID_SHADER := preload("res://shaders/skid.gdshader")

var car: CharacterBody3D
var life := 45.0
var _mm: MultiMesh
var _mat: ShaderMaterial
var _next := 0
var _used := 0
var _last: Array = [Vector3.INF, Vector3.INF]
var _prev_pos := Vector3.INF
var _now := 0.0
var _smoke: Array = []
var _wheels: Array = []  # Hinterräder im Auto (x, z)


func setup(c: CharacterBody3D, half_w: float, rear_z: float) -> void:
	car = c
	_wheels = [Vector3(-(half_w - 0.2), 0.0, rear_z), Vector3(half_w - 0.2, 0.0, rear_z)]
	# Spuren
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SKID_SHADER
	_mat.set_shader_parameter("life", life)
	plane.material = _mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = plane
	_mm.instance_count = SEG_MAX * 2
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Reifenspuren"
	mmi.multimesh = _mm
	mmi.top_level = true
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))  # Stücke liegen überall in der Welt
	add_child(mmi)
	# ein unsichtbares Stück von Anfang an: der Shader wird beim Laden übersetzt, nicht beim ersten Rutschen (Ruckler)
	_mm.set_instance_transform(0, Transform3D(Basis().scaled(Vector3(0.01, 0.01, 0.01)), car.global_position))
	_mm.set_instance_custom_data(0, Color(-1000.0, 0.0, 0.0, 0.0))
	_next = 1
	_used = 1
	_mm.visible_instance_count = 1
	# Qualm
	for w in _wheels:
		var p := CPUParticles3D.new()
		p.name = "Qualm"
		p.amount = 40
		p.lifetime = 1.7
		p.local_coords = false
		p.emitting = false
		p.position = w + Vector3(0.0, 0.25, 0.1)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.2
		p.direction = Vector3(0, 1, 0)
		p.spread = 35.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 1.6
		p.gravity = Vector3(0, 0.7, 0)
		p.damping_min = 0.6
		p.damping_max = 1.2
		p.scale_amount_min = 0.9
		p.scale_amount_max = 1.3
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.5))
		grow.add_point(Vector2(1.0, 3.2))
		p.scale_amount_curve = grow
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.8, 0.8, 0.82, 0.0))
		ramp.set_color(1, Color(0.74, 0.74, 0.76, 0.0))
		ramp.add_point(0.1, Color(0.82, 0.82, 0.84, 0.5))
		ramp.add_point(0.5, Color(0.78, 0.78, 0.8, 0.26))
		p.color_ramp = ramp
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		var sm := StandardMaterial3D.new()
		sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.vertex_color_use_as_albedo = true
		sm.albedo_texture = _puff_texture()
		sm.roughness = 1.0
		sm.disable_receive_shadows = true
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		q.material = sm
		p.mesh = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_smoke.append(p)


static var _puff: Texture2D


## Qualm-Stoff beim Laden übersetzen: ein winziger Qualm vor der Kamera, ein paar Sekunden lang (sonst hakte es beim
## ersten Durchdrehen am Start gut 250 ms)
func warm(cam: Camera3D) -> void:
	if _smoke.is_empty():
		return
	var w: CPUParticles3D = (_smoke[0] as CPUParticles3D).duplicate()
	w.local_coords = true
	w.position = Vector3(0, 0, -1.0)
	w.scale_amount_min = 0.002
	w.scale_amount_max = 0.002
	w.scale_amount_curve = null
	w.amount = 2
	w.emitting = true
	cam.add_child(w)
	get_tree().create_timer(3.0).timeout.connect(w.queue_free)


## Weicher runder Fleck (Qualmwolke)
static func _puff_texture() -> Texture2D:
	if _puff == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_puff = t
	return _puff


## Je Physik-Takt vom Auto: Rutsch-Stärke 0..1 (wie das Quietschen), am Boden?
func step(dt: float, slip: float, on_ground: bool, speed: float) -> void:
	if _now == 0.0:
		# Drift-Event (race.gd setzt drift_mode erst nach setup): die Spur der letzten Runde soll noch zu sehen sein
		var scene := get_tree().current_scene
		if scene and scene.scene_file_path.ends_with("race.tscn") and car.get("drift_mode"):
			life = 150.0
			_mat.set_shader_parameter("life", life)
	_now += dt
	_mat.set_shader_parameter("now", _now)
	var pos := car.global_position
	if _prev_pos.is_finite() and pos.distance_to(_prev_pos) > 4.0:
		_last = [Vector3.INF, Vector3.INF]  # zurückgesetzt oder versetzt: Spur nicht quer durchs Bild ziehen
	_prev_pos = pos
	var marking := on_ground and slip > MARK_FROM and speed > 2.0
	for i in 2:
		var wp: Vector3 = car.global_transform * _wheels[i]
		wp.y = pos.y + 0.03
		if not marking:
			_last[i] = Vector3.INF
			continue
		if not (_last[i] as Vector3).is_finite():
			_last[i] = wp
			continue
		var seg: Vector3 = wp - _last[i]
		if seg.length() < SEG_LEN:
			continue
		_add_segment(_last[i], wp, clampf((slip - MARK_FROM) / 0.3, 0.25, 1.0))
		_last[i] = wp
	var smoking := on_ground and slip > SMOKE_FROM and speed > 3.0
	for p in _smoke:
		if (p as CPUParticles3D).emitting != smoking:
			p.emitting = smoking


func _add_segment(a: Vector3, b: Vector3, k: float) -> void:
	var along := b - a
	var ln := along.length()
	var z := along / ln
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var xf := Transform3D(Basis(x * MARK_W, y, z * (ln + 0.04)), (a + b) * 0.5)
	_mm.set_instance_transform(_next, xf)
	_mm.set_instance_custom_data(_next, Color(_now, k, 0.0, 0.0))
	_next = (_next + 1) % _mm.instance_count
	_used = mini(_used + 1, _mm.instance_count)
	_mm.visible_instance_count = _used
