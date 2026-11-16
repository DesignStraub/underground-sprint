extends Node3D
## Reifenqualm und Reifenspuren (seit 2.35), hängt am Spielerauto. Stärke aus dem Reifenrutschen (player_car: dieselbe
## Größe wie das Quietschen): ab gut der Hälfte zeichnen die Hinterräder dunkle Spuren auf den Boden, im Drift, beim
## Durchdrehen und bei der Handbremse qualmen sie dazu. Dezent: heller, halb durchsichtiger Qualm, der aufsteigt und
## vergeht; Spuren verblassen langsam (frei fahren 45 s, im Drift-Event 150 s: die Spur der letzten Runde liegt noch da).
## Spuren sind ein MultiMesh (ein Zeichenaufruf, je Takt und Rad ein neues Stück), Qualm zwei CPUParticles3D.
## Seit 2.36 sieht der Qualm nach Rauch aus statt nach Kästen: weiche Wolken aus Rauschen (vier Formen in einem Bild),
## zufällig gedreht, langsam drehend, wachsend und vergehend, leicht treibend. Der eigene Shader blendet die Wolken weich
## aus, wo sie Boden oder Auto schneiden (vorher harte gerade Kanten) und dicht vor der Kamera; die Wolken sind rund
## schattiert (Kugel-Normale), Laternen beleuchten sie, und die Lichtkarte der Straße hellt sie unter Laternen auf.
## Eigene Sichtebene (SMOKE_LAYER): Unterbodenneon, Lichtteppiche und Scheinwerfer der Autos (car_builder) lassen sie
## aus; bis 2.35 färbte das Neon den Qualm in einem scharf begrenzten Kasten (Decal) ein.

const Builder := preload("res://scripts/car_builder.gd")

const SEG_MAX := 2000  # Teilstücke je Rad (Ringpuffer, das älteste wird überschrieben)
const SEG_LEN := 0.8  # m je Teilstück
const MARK_W := 0.24
const MARK_FROM := 0.5  # ab dieser Rutsch-Stärke Spuren
const SMOKE_FROM := 0.62  # ab hier Qualm
const SKID_SHADER := preload("res://shaders/skid.gdshader")
const PUFF_CELL := 96  # Bildpunkte je Wolke im 2x2-Bild

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
var _street_tex: Texture2D = null  # zuletzt gesetzte Lichtkarte (Open World wechselt sie je Strecke)
var _street_set := false
var _smoking := false  # der Stoff ist geteilt: beim ersten Takt immer setzen (sonst bliebe die Karte des letzten Rennens)

static var _puff: Texture2D
static var _smoke_mat: ShaderMaterial


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
	# Qualm: je Hinterrad eine Quelle knapp über der Aufstandsfläche, die Wolken bleiben in der Welt zurück
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = smoke_material()
	for w in _wheels:
		var p := CPUParticles3D.new()
		p.name = "Qualm"
		p.amount = 60
		p.lifetime = 2.4
		p.local_coords = false
		p.emitting = false
		p.position = w + Vector3(0.0, 0.22, 0.12)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.22
		p.direction = Vector3(0, 0.45, 1)  # nach hinten und etwas nach oben aus dem Radkasten
		p.spread = 60.0
		p.initial_velocity_min = 0.8
		p.initial_velocity_max = 2.2
		p.gravity = Vector3(0.1, 0.38, 0.0)  # warmer Qualm steigt, ein Hauch Wind
		p.damping_min = 1.0
		p.damping_max = 2.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -26.0
		p.angular_velocity_max = 26.0
		p.anim_offset_min = 0.0
		p.anim_offset_max = 1.0  # welche der vier Wolken (Shader)
		p.scale_amount_min = 1.0
		p.scale_amount_max = 1.5
		var grow := Curve.new()
		grow.max_value = 4.0
		grow.add_point(Vector2(0.0, 0.6))
		grow.add_point(Vector2(0.2, 1.6))
		grow.add_point(Vector2(1.0, 3.6))
		p.scale_amount_curve = grow
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.9, 0.9, 0.92, 0.0))
		ramp.set_color(1, Color(0.84, 0.84, 0.86, 0.0))
		ramp.add_point(0.05, Color(0.9, 0.9, 0.92, 0.5))
		ramp.add_point(0.3, Color(0.88, 0.88, 0.9, 0.36))
		ramp.add_point(0.7, Color(0.86, 0.86, 0.88, 0.13))
		p.color_ramp = ramp
		p.mesh = q
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.layers = Builder.SMOKE_LAYER
		add_child(p)
		_smoke.append(p)


## Staubwolke (Unfall, umgefahrene Teile, seit 2.36): ein paar Qualmwolken auf einmal an einer Stelle, dezent, räumt
## sich selbst auf. Derselbe Stoff wie der Reifenqualm (weich, ohne Kästen), eigene Sichtebene wie dieser.
static func dust_puff(parent: Node, at: Vector3, amount := 6, size := 1.0, col := Color(0.6, 0.58, 0.55)) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = smoke_material()
	var p := CPUParticles3D.new()
	p.name = "Staub"
	p.amount = amount
	p.lifetime = 1.7
	p.one_shot = true
	p.explosiveness = 0.85
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.45 * size
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0.0, 0.2, 0.0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -20.0
	p.angular_velocity_max = 20.0
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.scale_amount_min = 0.8 * size
	p.scale_amount_max = 1.3 * size
	var grow := Curve.new()
	grow.max_value = 4.0
	grow.add_point(Vector2(0.0, 0.7))
	grow.add_point(Vector2(0.3, 1.5))
	grow.add_point(Vector2(1.0, 2.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col, 0.0))
	ramp.set_color(1, Color(col, 0.0))
	ramp.add_point(0.06, Color(col, 0.4))
	ramp.add_point(0.45, Color(col, 0.2))
	p.color_ramp = ramp
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.layers = Builder.SMOKE_LAYER
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)


## Splitter für Unfälle und umgefahrene Teile (seit 2.36 statt Kästchen): dünne, ungleichmäßige Dreiecke, die sich
## im Flug drehen. Gibt den Partikel-Knoten zurück (Menge, Tempo, Ort setzt der Aufrufer).
static func shards(mat: Material, size := 0.16) -> CPUParticles3D:
	var m := PrismMesh.new()
	m.size = Vector3(size, size * 0.8, size * 0.15)
	m.left_to_right = randf_range(0.1, 0.9)
	m.material = mat
	var p := CPUParticles3D.new()
	p.mesh = m
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3.UP
	p.spread = 75.0
	p.particle_flag_rotate_y = true
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 1.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


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


## Qualm-Stoff: Billboard mit zufälliger Drehung (INSTANCE_CUSTOM.x), eine von vier Wolken (INSTANCE_CUSTOM.z),
## beleuchtet wie eine Kugel (Normale aus der Lage im Billboard, weich umlaufend), weich an Boden und Wänden (Tiefe)
## und vor der Kamera, unter Laternen etwas aufgehellt (Lichtkarte der Straße). Ohne Glanz, ohne Schatten.
static func smoke_material() -> ShaderMaterial:
	if _smoke_mat:
		return _smoke_mat
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled;
// Reifenqualm (tire_fx.gd)
uniform sampler2D puff : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float soft_dist = 0.55;
uniform sampler2D street_light : hint_default_black, filter_linear, repeat_disable;
uniform vec4 street_rect = vec4(0.0);
uniform float street_gain = 0.0;
varying vec3 cv;
varying float rv;
varying float frame;
varying vec3 wpos;
void vertex() {
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	mw = mw * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	float sc = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mw * mat4(vec4(sc, 0.0, 0.0, 0.0), vec4(0.0, sc, 0.0, 0.0), vec4(0.0, 0.0, sc, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	cv = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	rv = max(sc * 0.5, 0.01);
	frame = floor(clamp(INSTANCE_CUSTOM.z, 0.0, 0.999) * 4.0);
	wpos = MODEL_MATRIX[3].xyz;
}
void fragment() {
	vec2 cell = vec2(mod(frame, 2.0), floor(frame / 2.0)) * 0.5;
	vec4 tx = texture(puff, cell + UV * 0.5);
	float a = tx.a * COLOR.a;
	// weich, wo die Wolke Boden, Auto oder Wand schneidet
	float d = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
#endif
	vec4 sv = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_z = sv.z / sv.w;
	a *= clamp((VERTEX.z - scene_z) / soft_dist, 0.0, 1.0);
	// dicht vor der Kamera ausblenden (sonst eine große flache Fläche vor dem Bild)
	a *= smoothstep(0.4, 2.2, -VERTEX.z);
	vec2 dd = (VERTEX.xy - cv.xy) / rv;
	NORMAL = normalize(vec3(dd * 0.65, max(sqrt(max(1.0 - dot(dd, dd), 0.0)), 0.35)));
	ALBEDO = COLOR.rgb * tx.rgb;
	// ein Hauch Eigenlicht, damit Qualm auch auf dunkler Landstraße zu ahnen ist (im Browser-Renderer fällt das
	// Umgebungslicht auf durchsichtigen Flächen schwächer aus); unter Laternen die Lichtkarte
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	EMISSION = ALBEDO * 0.3;
#else
	EMISSION = ALBEDO * 0.07;
#endif
	if (street_gain > 0.0) {
		vec3 sl = texture(street_light, (wpos.xz - street_rect.xy) * street_rect.zw).rgb * street_gain;
		EMISSION += ALBEDO * sl * 0.12;
	}
	ALPHA = a;
}
"""
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = sh
	_smoke_mat.set_shader_parameter("puff", _puff_texture())
	_smoke_mat.render_priority = 1  # nach Lichtteppich und Leuchthöfen zeichnen: die liegen hinter dem Qualm
	return _smoke_mat


## Vier weiche Wolken aus Rauschen in einem 2x2-Bild: je Wolke drei überlappende Ballen mit fraktalem Rauschen, zum Rand
## ganz durchsichtig (keine Kante, keine Ecke), innen etwas dunkler (wirkt dicht). Einmal gebaut, mit Mipmaps.
static func _puff_texture() -> Texture2D:
	if _puff:
		return _puff
	var n := PUFF_CELL
	var size := n * 2
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for c in 4:
		# Rauschen in C++ als Bild (grob und fein), danach nur noch Rechnen je Bildpunkt
		noise.seed = 11 + c * 17
		noise.frequency = 0.022 * 128.0 / n
		var coarse := noise.get_image(n, n).get_data()
		noise.seed = 101 + c * 23
		noise.frequency = 0.05 * 128.0 / n
		var fine := noise.get_image(n, n).get_data()
		var ox := (c % 2) * n
		var oy := (c / 2) * n
		# drei Ballen je Wolke: Mitte und Radius (in Teilen der Zelle)
		var bc := []
		var br := []
		for b in 3:
			var ang := rng.randf() * TAU
			var off := 0.0 if b == 0 else rng.randf_range(0.08, 0.14)
			bc.append(Vector2(0.5, 0.5) + Vector2(cos(ang), sin(ang)) * off)
			br.append(rng.randf_range(0.27, 0.33) if b > 0 else 0.37)
		for y in n:
			for x in n:
				var uv := Vector2((x + 0.5) / n, (y + 0.5) / n)
				var body := 0.0
				for b in 3:
					var q: float = uv.distance_to(bc[b]) / float(br[b])
					body += exp(-q * q * 2.2) * (1.0 if b == 0 else 0.7)
				var nz := coarse[y * n + x] / 255.0
				var nz2 := fine[y * n + x] / 255.0
				# Dichte: Ballen mal Rauschen, Ränder zerfranst; zum Zellrand sicher null
				# weich auslaufend (keine Kontrastkurve: sonst wirken die Wolken wie Wattebäusche), das Rauschen zerfranst
				var edge := 1.0 - smoothstep(0.3, 0.49, uv.distance_to(Vector2(0.5, 0.5)))
				var dens := clampf(minf(body, 1.0) * (0.5 + (nz - 0.5) * 1.1 + (nz2 - 0.5) * 0.4) * 1.25, 0.0, 1.0) * edge
				var lum := clampf(0.9 + (nz2 - 0.5) * 0.22, 0.0, 1.0)
				var i := ((oy + y) * size + ox + x) * 4
				data[i] = int(lum * 255.0)
				data[i + 1] = data[i]
				data[i + 2] = data[i]
				data[i + 3] = int(dens * 255.0)
	var img := Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	_puff = ImageTexture.create_from_image(img)
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
	_sync_street()
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
	# mit etwas Nachlauf (erst unter SMOKE_FROM - 0.12 wieder aus): kein Stottern der Wolke um die Schwelle herum
	var smoking := on_ground and speed > 3.0 and (slip > SMOKE_FROM or (_smoking and slip > SMOKE_FROM - 0.12))
	_smoking = smoking
	for p in _smoke:
		if (p as CPUParticles3D).emitting != smoking:
			p.emitting = smoking


## Lichtkarte der Straße (car_builder.street, von track_builder gesetzt) an den Qualm-Stoff geben, wenn sie wechselt
func _sync_street() -> void:
	var st: Dictionary = Builder.street
	var tex: Texture2D = st.get("tex", null)
	if tex == _street_tex and _street_set:
		return
	_street_tex = tex
	_street_set = true
	var m := smoke_material()
	if tex == null:
		m.set_shader_parameter("street_gain", 0.0)
		return
	m.set_shader_parameter("street_light", tex)
	m.set_shader_parameter("street_rect", st["rect"])
	m.set_shader_parameter("street_gain", float(st["gain"]))


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
