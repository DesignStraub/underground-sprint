extends Node
## Werkzeug: rendert die Text-Overlays (1080x1920, transparent) und die Endkarte für das Release-Short.
## Aufruf: Godot --path . res://tools/short_overlays.tscn -- --out=/pfad

const LOGO := preload("res://assets/one_humanity_logo.svg")
const GLOW := preload("res://shaders/logo_glow.gdshader")
const SIZE := Vector2i(1080, 1920)

const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GREEN := Color(0.4, 1.0, 0.5)

var out := "."
var heavy: SystemFont
var light: SystemFont


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	heavy = SystemFont.new()
	heavy.font_names = PackedStringArray(["Impact", "Arial Black"])
	light = SystemFont.new()
	light.font_names = PackedStringArray(["Avenir Next", "Helvetica Neue"])
	light.font_weight = 600

	var shots := [
		["o1", "UNDERGROUND\nSPRINT", CYAN, "NEU", "Street-Racing bei Nacht"],
		["o2", "TUNE DEIN\nAUTO", PINK, "", "Teile freischalten durch Siege"],
		["o3", "SPRINTS DURCH\nDIE STADT", CYAN, "", "3 Gegner · Verkehr · Baustellen"],
		["o4", "NITRO.\nDRIFT. SPEED.", PINK, "", "Ein Crash kostet dich das Rennen"],
	]
	for s in shots:
		await _render(_overlay(s[1], s[2], s[3], s[4]), s[0], true)
	await _render(_end_card(), "end", false)
	get_tree().quit()


func _label(parent: Node, text: String, font: Font, size: int, col: Color, y: float, outline := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.85)
	ls.shadow_size = 18
	ls.shadow_color = Color(col.r, col.g, col.b, 0.45)
	ls.line_spacing = -size * 0.12
	l.label_settings = ls
	l.position = Vector2(0, y)
	l.size = Vector2(SIZE.x, 10)
	parent.add_child(l)
	return l


func _overlay(title: String, col: Color, tag: String, sub: String) -> Control:
	var root := Control.new()
	root.size = SIZE
	if tag != "":
		var pill := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = GREEN
		sb.set_corner_radius_all(14)
		pill.add_theme_stylebox_override("panel", sb)
		pill.position = Vector2(SIZE.x / 2.0 - 80, 230)
		pill.size = Vector2(160, 66)
		root.add_child(pill)
		var t := _label(root, tag, heavy, 52, Color(0.02, 0.05, 0.02), 232, 0)
		t.label_settings.shadow_size = 0
	_label(root, title, heavy, 150, Color.WHITE, 310).label_settings.shadow_color = Color(col.r, col.g, col.b, 0.8)
	_label(root, sub, light, 56, col, 1330, 10)
	return root


func _end_card() -> Control:
	var root := Control.new()
	root.size = SIZE
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.size = SIZE
	root.add_child(bg)
	var halo := ColorRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.55, 1.0, 0.45))
	grad.set_color(1, Color(0.15, 0.55, 1.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var h := TextureRect.new()
	h.texture = gt
	h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.size = Vector2(900, 900)
	h.position = Vector2(90, 120)
	root.add_child(h)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(440, 440)
	logo.position = Vector2(320, 350)
	var m := ShaderMaterial.new()
	m.shader = GLOW
	logo.material = m
	root.add_child(logo)
	_label(root, "UNDERGROUND SPRINT", heavy, 96, Color.WHITE, 880).label_settings.shadow_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.8)
	_label(root, "JETZT KOSTENLOS", heavy, 120, GREEN, 1080)
	_label(root, "auf itch.io", light, 84, Color.WHITE, 1240)
	_label(root, "Windows · Mac · Linux", light, 48, Color(0.7, 0.75, 0.85), 1380, 6)
	_label(root, "ONE HUMANITY", light, 44, CYAN, 1700, 6)
	return root


func _render(content: Control, name: String, transparent: bool) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(content)
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	vp.queue_free()
