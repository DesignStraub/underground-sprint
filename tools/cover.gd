extends Node
## Werkzeug: baut das itch.io-Coverbild aus der Garage (getuntes Auto, Neon) plus Titel und Logo.
## Aufnahme per Movie Maker, siehe release/README im Commit-Verlauf:
##   Godot --path . --write-movie /pfad/cover.png --fixed-fps 10 res://tools/cover.tscn

const LOGO := preload("res://assets/one_humanity_logo.svg")
const GLOW := preload("res://shaders/logo_glow.gdshader")
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GREEN := Color(0.4, 1.0, 0.5)

var garage: Node3D
var _t := 0.0


func _ready() -> void:
	GameState.pixel_mode = 2  # scharf rendern, ohne zu speichern
	garage = preload("res://scenes/garage.tscn").instantiate()
	add_child(garage)
	garage.set_process(false)
	for c in garage.get_children():
		if c is CanvasLayer and c.layer != -1:
			c.visible = false
	var cfg := {"paint": 5, "rims": 2, "spoiler": 2, "bodykit": 2, "vinyl": 1, "neon": 2, "engine": 3, "nitro": 2}
	garage._show_car("vortex", cfg)
	garage.turntable.rotation_degrees.y = 215.0
	garage.cam.fov = 38.0
	garage.cam.position = Vector3(5.6, 1.7, 6.4)
	garage.cam.look_at(Vector3(0.0, 1.15, 0.0))
	_build_overlay()


func _label(parent: Control, text: String, font: Font, size: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	ls.shadow_size = 10
	ls.shadow_color = Color(col.r, col.g, col.b, 0.5)
	l.label_settings = ls
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.position.y = y
	parent.add_child(l)
	return l


func _build_overlay() -> void:
	var heavy := SystemFont.new()
	heavy.font_names = PackedStringArray(["Impact", "Arial Black"])
	var light := SystemFont.new()
	light.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue"])
	light.font_weight = 600
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	# Abdunkeln oben, damit der Titel lesbar bleibt
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.85))
	grad.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_preset(Control.PRESET_TOP_WIDE)
	shade.size.y = 220
	root.add_child(shade)
	_label(root, "UNDERGROUND", heavy, 78, Color.WHITE, 14).label_settings.shadow_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.8)
	_label(root, "SPRINT", heavy, 78, CYAN, 92).label_settings.shadow_color = Color(PINK.r, PINK.g, PINK.b, 0.7)
	_label(root, "FREE  ·  NIGHT STREET RACING", light, 18, GREEN, 186)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	logo.size = Vector2(44, 44)
	logo.position = Vector2(-178, -58)
	var m := ShaderMaterial.new()
	m.shader = GLOW
	logo.material = m
	root.add_child(logo)
	var brand := Label.new()
	brand.text = "ONE HUMANITY"
	var bs := LabelSettings.new()
	bs.font = light
	bs.font_size = 13
	bs.font_color = Color(0.9, 0.95, 1.0)
	bs.outline_size = 4
	bs.outline_color = Color(0, 0, 0, 0.8)
	brand.label_settings = bs
	brand.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	brand.position = Vector2(-130, -46)
	root.add_child(brand)


func _process(dt: float) -> void:
	_t += dt
	if _t > 1.5:
		get_tree().quit()
