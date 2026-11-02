extends Node
## Werkzeug: Bilder für die itch.io-Seiten (ONE HUMANITY und Need for Geschwindigkeit) nach release/itch_seite/.
## Hintergründe sind echte Szenen aus dem Spiel (volle Auflösung), Schrift und Logo kommen als Neon-Ebene darüber.
##   Godot --path . res://tools/itch_art.tscn

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const Builder := preload("res://scripts/car_builder.gd")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const GLOW := preload("res://shaders/logo_glow.gdshader")
const OUT := "res://release/itch_seite/"
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GREEN := Color(0.4, 1.0, 0.5)
const CAR_CFG := {"paint": 5, "rims": 2, "spoiler": 2, "bodykit": 2, "vinyl": 1, "neon": 2, "engine": 3, "nitro": 2}

var heavy: Font
var cond: Font
var light: Font
var wide: FontVariation
var logo_img: Image  # Logo als Bild (dunkel; der Glow-Shader färbt es um)
var logo_white: ImageTexture


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)  # Musik und Geräusche der Szenen stummschalten
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# DIN-Schrift wie auf deutschen Straßenschildern (D-DIN, SIL OFL)
	heavy = load("res://assets/fonts/D-DINExp-Bold.otf")
	cond = load("res://assets/fonts/D-DINCondensed-Bold.otf")
	var sf: Font = load("res://assets/fonts/D-DIN-Bold.otf")
	light = sf
	wide = FontVariation.new()
	wide.base_font = sf
	wide.spacing_glyph = 6
	var svg := FileAccess.get_file_as_string("res://assets/one_humanity_logo.svg")
	logo_img = Image.new()
	logo_img.load_svg_from_string(svg, 5.0)
	var white := Image.new()
	white.load_svg_from_string(svg.replace("#131313", "#ffffff"), 5.0)
	logo_white = ImageTexture.create_from_image(white)
	await _run()
	get_tree().quit()


func _run() -> void:
	# Spielszenen
	var street := await _render_3d(Vector2i(1920, 1440), 0, _shot_car_chinatown)
	var skyline := await _render_3d(Vector2i(1920, 800), 0, _shot_skyline)
	var lanterns := await _render_3d(Vector2i(1920, 1080), 0, _shot_lanterns)
	var street_t := ImageTexture.create_from_image(street)
	var skyline_t := ImageTexture.create_from_image(skyline)
	var lanterns_t := ImageTexture.create_from_image(lanterns)

	# --- Need for Geschwindigkeit ---
	var cover := await _compose(Vector2i(1260, 1000), false, func(r: Control, s: Vector2): _cover(r, s, street_t))
	_save(cover, "need_for_geschwindigkeit_cover_1260x1000.png")
	cover.resize(630, 500, Image.INTERPOLATE_LANCZOS)
	_save(cover, "need_for_geschwindigkeit_cover_630x500.png")
	_save(await _compose(Vector2i(960, 260), true, _title), "need_for_geschwindigkeit_titel_960x260.png")
	_save(await _compose(Vector2i(960, 320), false, func(r: Control, s: Vector2): _banner(r, s, street_t)), "need_for_geschwindigkeit_banner_960x320.png")
	_save(await _compose(Vector2i(1920, 1080), false, func(r: Control, s: Vector2): _background(r, s, lanterns_t, 0.55)), "need_for_geschwindigkeit_hintergrund_1920x1080.jpg")

	# --- ONE HUMANITY ---
	_save(await _compose(Vector2i(512, 512), false, _profile), "onehumanity_profilbild_512.png")
	_save(await _compose(Vector2i(1024, 1024), true, _logo_transparent.bind(true)), "onehumanity_logo_weiss_1024.png")
	_save(await _compose(Vector2i(1024, 1024), true, _logo_transparent.bind(false)), "onehumanity_logo_dunkel_1024.png")
	_save(await _compose(Vector2i(960, 300), false, func(r: Control, s: Vector2): _header(r, s, skyline_t)), "onehumanity_header_960x300.png")
	_save(await _compose(Vector2i(1920, 1080), false, func(r: Control, s: Vector2): _background(r, s, skyline_t, 0.6)), "onehumanity_hintergrund_1920x1080.jpg")


func _save(img: Image, file: String) -> void:
	var p := ProjectSettings.globalize_path(OUT + file)
	if file.ends_with(".jpg"):
		img.convert(Image.FORMAT_RGB8)
		img.save_jpg(p, 0.92)
	else:
		img.save_png(p)
	print("gespeichert: ", file, "  ", img.get_size())


# --- 3D ---------------------------------------------------------------------------

func _render_3d(size: Vector2i, race_i: int, setup: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_8X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var t := Track.build(Catalog.RACES[race_i])
	vp.add_child(t["node"])
	_env(vp)
	var cam := Camera3D.new()
	cam.far = 1500.0
	vp.add_child(cam)
	cam.current = true
	setup.call(t, vp, cam)
	for i in 40:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	await get_tree().process_frame
	return img


func _env(vp: SubViewport) -> void:
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.4)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.07, 0.16)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.15
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 1.0)
	moon.light_energy = 0.3
	moon.rotation_degrees = Vector3(-50, 30, 0)
	vp.add_child(moon)


func _at(t: Dictionary, d: float, lat: float, h: float) -> Vector3:
	var f := Track.frame_at(t["curve"], d)
	return f["pos"] + f["right"] * lat + Vector3(0, h, 0)


## Erstes Stück eines Viertels auf der Hauptstraße
func _district_d(t: Dictionary, key: String) -> float:
	var i: int = t["districts"].find(key)
	return maxf(i, 0) * Track.DISTRICT_LEN


## Getuntes Auto unter Lampions, Kamera schräg von vorn
func _shot_car_chinatown(t: Dictionary, vp: SubViewport, cam: Camera3D) -> void:
	var d := _district_d(t, "chinatown") + 105.0
	var car := Builder.build("vortex", CAR_CFG)
	vp.add_child(car)
	car.global_transform = Track.xform_at(t["curve"], d, Track.LANES[2])
	cam.fov = 40.0
	cam.global_position = _at(t, d + 9.0, 7.4, 1.25)
	cam.look_at(_at(t, d - 1.0, 1.4, 1.55), Vector3.UP)


## Blick über Downtown von oben
func _shot_skyline(t: Dictionary, _vp: SubViewport, cam: Camera3D) -> void:
	var d := _district_d(t, "downtown") + 90.0
	cam.fov = 60.0
	cam.global_position = _at(t, d, 0.0, 26.0)
	cam.look_at(_at(t, d + 300.0, 0.0, 22.0), Vector3.UP)


## Lampionketten von oben, für den Seitenhintergrund
func _shot_lanterns(t: Dictionary, _vp: SubViewport, cam: Camera3D) -> void:
	var d := _district_d(t, "chinatown") + 30.0
	cam.fov = 65.0
	cam.global_position = _at(t, d, 0.0, 13.0)
	cam.look_at(_at(t, d + 120.0, 0.0, 5.0), Vector3.UP)


# --- 2D ---------------------------------------------------------------------------

func _compose(size: Vector2i, transparent: bool, build: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(size)
	vp.add_child(root)
	build.call(root, Vector2(size))
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	await get_tree().process_frame
	return img


func _image(parent: Control, tex: Texture2D, rect: Rect2, cover := true) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.position = rect.position
	tr.size = rect.size
	parent.add_child(tr)
	return tr


## Verlauf über die ganze Fläche: from/to in 0..1 (senkrecht), Farbe oben/unten
func _shade(parent: Control, size: Vector2, top: Color, bottom: Color, from := 0.0, to := 1.0) -> void:
	var grad := Gradient.new()
	grad.set_color(0, top)
	grad.set_color(1, bottom)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, from)
	gt.fill_to = Vector2(0.5, to)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.size = size
	parent.add_child(tr)


func _label(parent: Control, text: String, font: Font, px: int, col: Color, rect: Rect2, align := HORIZONTAL_ALIGNMENT_CENTER,
		outline := 0, outline_col := Color.BLACK) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = px
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = outline_col
	l.label_settings = ls
	l.position = rect.position
	l.size = rect.size
	parent.add_child(l)
	return l


## Neon-Schrift: weiche Leuchthülle aus gestapelten, halbtransparenten Umrissen, darüber die Schrift
func _neon(parent: Control, text: String, font: Font, px: int, col: Color, glow: Color, rect: Rect2,
		align := HORIZONTAL_ALIGNMENT_CENTER, spread := 1.0) -> void:
	for st in [[0.42, 0.05], [0.3, 0.07], [0.2, 0.1], [0.12, 0.16], [0.06, 0.28]]:
		_label(parent, text, font, px, Color(0, 0, 0, 0), rect, align, int(px * st[0] * spread), Color(glow.r, glow.g, glow.b, st[1]))
	_label(parent, text, font, px, col, rect, align, maxi(2, int(px * 0.025)), Color(glow.r * 0.5, glow.g * 0.5, glow.b * 0.5, 1.0))


## Logo mit Neon-Schein (Shader aus dem Intro)
func _logo(parent: Control, rect: Rect2, glow := 1.0) -> void:
	# Rand lassen, damit der Schein nicht abgeschnitten wird
	var pad := Image.create(logo_img.get_width() + 160, logo_img.get_height() + 160, false, Image.FORMAT_RGBA8)
	pad.blit_rect(logo_img, Rect2i(Vector2i.ZERO, logo_img.get_size()), Vector2i(80, 80))
	var tr := _image(parent, ImageTexture.create_from_image(pad), rect, false)
	var m := ShaderMaterial.new()
	m.shader = GLOW
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("radius", 0.02)
	tr.material = m


func _brand(parent: Control, pos: Vector2, logo_px: float, text_px: int) -> void:
	_logo(parent, Rect2(pos, Vector2(logo_px, logo_px)), 0.8)
	_label(parent, "ONE HUMANITY", wide, text_px, Color(0.92, 0.95, 1.0), Rect2(pos + Vector2(logo_px * 0.92, 0), Vector2(600, logo_px)),
		HORIZONTAL_ALIGNMENT_LEFT, 4, Color(0, 0, 0, 0.7))


# --- Motive -----------------------------------------------------------------------

func _cover(r: Control, s: Vector2, bg: Texture2D) -> void:
	_image(r, bg, Rect2(Vector2.ZERO, s))
	_shade(r, s, Color(0.02, 0.01, 0.06, 0.88), Color(0, 0, 0, 0), 0.0, 0.42)
	_shade(r, s, Color(0, 0, 0, 0), Color(0.02, 0.01, 0.05, 0.7), 0.72, 1.0)
	_neon(r, "NEED FOR", heavy, 104, Color.WHITE, CYAN, Rect2(0, 30, s.x, 130))
	_neon(r, "GESCHWINDIGKEIT", cond, 168, CYAN, PINK, Rect2(0, 140, s.x, 200))
	_neon(r, "STRASSENRENNEN BEI NACHT  ·  KOSTENLOS  ·  OHNE TÜV", wide, 30, GREEN, GREEN, Rect2(0, 346, s.x, 50), HORIZONTAL_ALIGNMENT_CENTER, 0.6)
	_brand(r, Vector2(s.x - 420, s.y - 104), 84, 30)


func _title(r: Control, s: Vector2) -> void:
	var f := FontVariation.new()
	f.base_font = heavy
	f.variation_transform = Transform2D(Vector2(1.0, 0.2), Vector2(0.0, 1.0), Vector2.ZERO)  # leicht schräg wie Tempo
	var fc := FontVariation.new()
	fc.base_font = cond
	fc.variation_transform = f.variation_transform
	_neon(r, "NEED FOR", f, 54, Color.WHITE, CYAN, Rect2(0, 8, s.x, 70))
	_neon(r, "GESCHWINDIGKEIT", fc, 112, CYAN, PINK, Rect2(0, 52, s.x, 130))
	_neon(r, "STRASSENRENNEN BEI NACHT  ·  ONE HUMANITY", wide, 24, GREEN, GREEN, Rect2(0, 182, s.x, 50), HORIZONTAL_ALIGNMENT_CENTER, 0.6)


func _banner(r: Control, s: Vector2, bg: Texture2D) -> void:
	var tr := _image(r, bg, Rect2(Vector2(0, -260), Vector2(s.x, s.x * 0.75)))
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	r.add_child(_dim(s, 0.45))
	_shade(r, s, Color(0, 0, 0, 0), Color(0.02, 0.01, 0.05, 0.85), 0.55, 1.0)
	_title(r, s)


func _background(r: Control, s: Vector2, bg: Texture2D, dim: float) -> void:
	_image(r, bg, Rect2(Vector2.ZERO, s))
	r.add_child(_dim(s, dim))
	# Mitte dunkler: dort liegt auf itch.io die Textspalte
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.015, 0.05, 0.75))
	grad.set_color(1, Color(0.02, 0.015, 0.05, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.85, 0.5)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.size = s
	r.add_child(tr)


func _dim(s: Vector2, a: float) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.02, 0.015, 0.05, a)
	c.size = s
	return c


func _profile(r: Control, s: Vector2) -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.07, 0.14, 0.28))
	grad.set_color(1, Color(0.015, 0.015, 0.04))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.05, 0.45)
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.size = s
	r.add_child(bg)
	_logo(r, Rect2(s * 0.08, s * 0.84), 1.0)


## Logo mit Schriftzug auf transparentem Grund: weiß für dunkle, dunkel für helle Hintergründe
func _logo_transparent(r: Control, s: Vector2, white: bool) -> void:
	var tex: Texture2D = logo_white if white else ImageTexture.create_from_image(logo_img)
	var col := Color.WHITE if white else Color(0.075, 0.075, 0.075)
	_image(r, tex, Rect2(Vector2(s.x * 0.18, 40), Vector2(s.x * 0.64, s.x * 0.64)), false)
	_label(r, "ONE HUMANITY", wide, 92, col, Rect2(0, s.y - 290, s.x, 140))
	_label(r, "GAMES", wide, 44, Color(col.r, col.g, col.b, 0.75), Rect2(0, s.y - 170, s.x, 80))


func _header(r: Control, s: Vector2, bg: Texture2D) -> void:
	var tr := _image(r, bg, Rect2(Vector2(0, -60), Vector2(s.x, s.x * 800.0 / 1920.0)))
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	r.add_child(_dim(s, 0.35))
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.015, 0.05, 0.92))
	grad.set_color(1, Color(0.02, 0.015, 0.05, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.0, 0.5)
	gt.fill_to = Vector2(0.75, 0.5)
	var sh := TextureRect.new()
	sh.texture = gt
	sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sh.size = s
	r.add_child(sh)
	_logo(r, Rect2(36, 42, 216, 216), 1.0)
	_neon(r, "ONE HUMANITY", wide, 58, Color.WHITE, CYAN, Rect2(262, 88, 680, 80), HORIZONTAL_ALIGNMENT_LEFT, 0.7)
	_label(r, "INDIE GAMES  ·  NIGHT STREET RACING", wide, 20, Color(0.75, 0.85, 1.0, 0.9), Rect2(266, 166, 680, 40), HORIZONTAL_ALIGNMENT_LEFT)
