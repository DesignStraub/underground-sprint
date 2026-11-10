extends Node
## Werkzeug: Overlays (1080x1920, transparent) für das Browser-Short (seit 2.27): Browserfenster mit Adresszeile,
## Texteinblendungen in der Spielschrift (Saira, schräg, Neon) und die Endtafel "Play free in your browser".
## Aufruf: Godot --path . res://tools/promo_overlays.tscn -- --out=/pfad
## Das Fenster lässt den Inhalt frei (transparent): darunter legt ffmpeg das Querformat-Video (1000x563 bei x 40, y 700).

const UiStyle := preload("res://scripts/ui_style.gd")
const LOGO_WHITE := "res://release/itch_seite/onehumanity_logo_weiss_1024.png"
const SIZE := Vector2i(1080, 1920)
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GREEN := Color(0.4, 1.0, 0.5)
const URL := "onehumanity.itch.io/need-for-geschwindigkeit"
## Browserfenster: Inhalt (Video) liegt genau hier
const WIN := Rect2(40, 600, 1000, 663)
const CONTENT := Rect2(40, 700, 1000, 563)

var out := "."


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	# Einstieg im Browser: erst "NO DOWNLOAD.", im zweiten Takt "JUST PLAY." dazu
	await _render(_hook(false), "o_hook1")
	await _render(_hook(true), "o_hook2")
	await _render(_caption("NEED FOR\nGESCHWINDIGKEIT", "STREET RACING AFTER DARK", CYAN, 118), "o_title")
	await _render(_city("WÜRZBURG"), "o_city1")
	await _render(_city("BERLIN-KREUZBERG"), "o_city2")
	await _render(_caption("NITRO", "", PINK, 190), "o_nitro")
	await _render(_caption("DRIFT", "", CYAN, 190), "o_drift")
	await _render(_caption("BEAT THE\nTRAIN", "", PINK, 160), "o_train")
	await _render(_tune(), "o_tune")
	await _render(_end_card(), "o_end")
	get_tree().quit()


func _label(parent: Node, text: String, kind: String, size: int, col: Color, y: float, glow: Color, outline := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = UiStyle.font(kind, 0.2)
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = outline
	ls.outline_color = Color(0, 0, 0, 0.9)
	ls.shadow_size = 22
	ls.shadow_color = Color(glow.r, glow.g, glow.b, 0.7)
	ls.shadow_offset = Vector2.ZERO
	ls.line_spacing = -size * 0.36
	l.label_settings = ls
	l.position = Vector2(0, y)
	l.size = Vector2(SIZE.x, 10)
	parent.add_child(l)
	return l


## schräge Neonleiste wie in den Menüs des Spiels
func _bar(parent: Node, cx: float, y: float, w: float, col: Color, h := 10.0) -> void:
	var p := Polygon2D.new()
	var s := h * 1.4
	p.polygon = PackedVector2Array([Vector2(cx - w / 2 + s, y), Vector2(cx + w / 2 + s, y), Vector2(cx + w / 2 - s, y + h), Vector2(cx - w / 2 - s, y + h)])
	p.color = col
	parent.add_child(p)
	var g := Polygon2D.new()  # weicher Schein darunter
	g.polygon = PackedVector2Array([Vector2(cx - w / 2 + s, y - 6), Vector2(cx + w / 2 + s, y - 6), Vector2(cx + w / 2 - s, y + h + 6), Vector2(cx - w / 2 - s, y + h + 6)])
	g.color = Color(col.r, col.g, col.b, 0.25)
	parent.add_child(g)
	parent.move_child(g, p.get_index())


## Überschrift über dem Spielbild (zwischen Platzanzeige oben und Auto unten)
func _caption(title: String, sub: String, col: Color, size: int) -> Control:
	var root := Control.new()
	root.size = SIZE
	var y := 330.0
	var tl := _label(root, title, "wide", size, Color.WHITE, y, col, 16)
	var by := y + tl.get_minimum_size().y + 6.0
	_bar(root, SIZE.x / 2.0, by, 520.0, col)
	root.set_meta("bottom", by + 16.0)
	if sub != "":
		var sl := _label(root, sub, "cond", 54, col, by + 26.0, Color(0, 0, 0), 10)
		sl.label_settings.shadow_size = 0
		root.set_meta("bottom", by + 26.0 + sl.get_minimum_size().y)
	return root


## Ortsschild wie an der Ortseinfahrt: gelb, schwarzer Rand, schwarze Schrift
func _city(name: String) -> Control:
	var root := _caption("REAL GERMAN\nCITIES", "", GREEN, 132)
	var w := 120.0 + name.length() * 42.0
	var sign := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.8, 0.05)
	sb.border_color = Color(0.05, 0.05, 0.05)
	sb.set_border_width_all(7)
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	sign.add_theme_stylebox_override("panel", sb)
	sign.position = Vector2(SIZE.x / 2.0 - w / 2.0, float(root.get_meta("bottom")) + 34.0)
	sign.size = Vector2(w, 104)
	root.add_child(sign)
	var t := Label.new()
	t.text = name
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font = load("res://assets/fonts/D-DIN-Bold.otf")  # wie die echten Schilder (DIN)
	ls.font_size = 64
	ls.font_color = Color(0.03, 0.03, 0.03)
	t.label_settings = ls
	t.position = sign.position
	t.size = sign.size
	root.add_child(t)
	return root


## Browserfenster (neutral, keine echte Marke): Titelleiste mit Tab, Adresszeile mit Schloss, Inhalt frei
func _browser(root: Control) -> void:
	var chrome := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17)
	sb.corner_radius_top_left = 22
	sb.corner_radius_top_right = 22
	chrome.add_theme_stylebox_override("panel", sb)
	chrome.position = WIN.position
	chrome.size = Vector2(WIN.size.x, CONTENT.position.y - WIN.position.y)
	root.add_child(chrome)
	# Rahmen um den Inhalt (Inhalt selbst bleibt durchsichtig)
	for r in [Rect2(WIN.position.x - 3, CONTENT.position.y, 3, CONTENT.size.y + 3), Rect2(WIN.end.x, CONTENT.position.y, 3, CONTENT.size.y + 3),
			Rect2(WIN.position.x - 3, CONTENT.end.y, WIN.size.x + 6, 3)]:
		var b := ColorRect.new()
		b.color = Color(0.13, 0.14, 0.17)
		b.position = r.position
		b.size = r.size
		root.add_child(b)
	# Neon-Schein ums ganze Fenster
	var glow := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.draw_center = false
	gs.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
	gs.set_border_width_all(3)
	gs.corner_radius_top_left = 24
	gs.corner_radius_top_right = 24
	glow.add_theme_stylebox_override("panel", gs)
	glow.position = WIN.position - Vector2(5, 5)
	glow.size = WIN.size + Vector2(10, 10)
	root.add_child(glow)
	# drei Fensterpunkte
	for i in 3:
		var d := Panel.new()
		var ds := StyleBoxFlat.new()
		ds.bg_color = [Color(0.95, 0.35, 0.35), Color(0.95, 0.75, 0.25), Color(0.35, 0.85, 0.45)][i]
		ds.set_corner_radius_all(8)
		d.add_theme_stylebox_override("panel", ds)
		d.position = WIN.position + Vector2(26 + i * 26, 14)
		d.size = Vector2(16, 16)
		root.add_child(d)
	# Tab
	var tab := Panel.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.22, 0.23, 0.27)
	ts.corner_radius_top_left = 12
	ts.corner_radius_top_right = 12
	tab.add_theme_stylebox_override("panel", ts)
	tab.position = WIN.position + Vector2(118, 6)
	tab.size = Vector2(430, 40)
	root.add_child(tab)
	var tl := Label.new()
	tl.text = "Need for Geschwindigkeit"
	var tls := LabelSettings.new()
	tls.font = UiStyle.font("bold", 0.0)
	tls.font_size = 24
	tls.font_color = Color(0.9, 0.92, 0.96)
	tl.label_settings = tls
	tl.position = tab.position + Vector2(44, 5)
	root.add_child(tl)
	var fav := Panel.new()  # kleines Symbol im Tab
	var fs := StyleBoxFlat.new()
	fs.bg_color = PINK
	fs.set_corner_radius_all(4)
	fav.add_theme_stylebox_override("panel", fs)
	fav.position = tab.position + Vector2(14, 12)
	fav.size = Vector2(18, 18)
	root.add_child(fav)
	# Adresszeile
	var bar := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.07, 0.075, 0.09)
	bs.set_corner_radius_all(17)
	bar.add_theme_stylebox_override("panel", bs)
	bar.position = WIN.position + Vector2(110, 54)
	bar.size = Vector2(WIN.size.x - 130, 36)
	root.add_child(bar)
	for i in 2:  # zurück / vor
		var ar := Label.new()
		ar.text = ["‹", "›"][i]
		var als := LabelSettings.new()
		als.font = UiStyle.font("bold", 0.0)
		als.font_size = 40
		als.font_color = Color(0.6, 0.63, 0.7)
		ar.label_settings = als
		ar.position = WIN.position + Vector2(30 + i * 36, 42)
		root.add_child(ar)
	_lock(root, bar.position + Vector2(18, 8))
	var ul := Label.new()
	ul.text = URL
	var uls := LabelSettings.new()
	uls.font = UiStyle.font("bold", 0.0)
	uls.font_size = 25
	uls.font_color = Color(0.92, 0.94, 0.98)
	ul.label_settings = uls
	ul.position = bar.position + Vector2(46, 1)
	root.add_child(ul)


func _lock(root: Control, at: Vector2) -> void:
	var body := Panel.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.75, 0.78, 0.84)
	s.set_corner_radius_all(3)
	body.add_theme_stylebox_override("panel", s)
	body.position = at + Vector2(0, 8)
	body.size = Vector2(18, 13)
	root.add_child(body)
	var shackle := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.draw_center = false
	ss.border_color = Color(0.75, 0.78, 0.84)
	ss.set_border_width_all(3)
	ss.corner_radius_top_left = 7
	ss.corner_radius_top_right = 7
	shackle.add_theme_stylebox_override("panel", ss)
	shackle.position = at + Vector2(3, 0)
	shackle.size = Vector2(12, 12)
	root.add_child(shackle)


func _hook(second: bool) -> Control:
	var root := Control.new()
	root.size = SIZE
	_browser(root)
	var tl := _label(root, "NO DOWNLOAD.", "wide", 150, Color.WHITE, 300, CYAN, 16)
	_bar(root, SIZE.x / 2.0, 300 + tl.get_minimum_size().y + 4.0, 560.0, CYAN)
	if second:
		_label(root, "JUST PLAY.", "wide", 150, GREEN, 1330, GREEN, 16)
		_label(root, "right in your browser", "cond", 56, Color.WHITE, 1530, Color(0, 0, 0), 10)
	return root


func _tune() -> Control:
	var root := Control.new()
	root.size = SIZE
	_browser(root)
	var tl := _label(root, "TUNE YOUR\nRIDE", "wide", 132, Color.WHITE, 170, PINK, 16)
	_bar(root, SIZE.x / 2.0, 170 + tl.get_minimum_size().y + 4.0, 520.0, PINK)
	_label(root, "23 CARS", "wide", 110, PINK, 1330, PINK, 14)
	_label(root, "paint · rims · neon · body kits", "cond", 54, Color.WHITE, 1480, Color(0, 0, 0), 10)
	return root


func _end_card() -> Control:
	var root := Control.new()
	root.size = SIZE
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.02, 0.62)
	dim.size = SIZE
	root.add_child(dim)
	var logo := TextureRect.new()
	logo.texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path(LOGO_WHITE)))
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(190, 190)
	logo.position = Vector2(SIZE.x / 2.0 - 95, 230)
	root.add_child(logo)
	var tl := _label(root, "NEED FOR\nGESCHWINDIGKEIT", "wide", 112, Color.WHITE, 470, CYAN, 14)
	var by := 470 + tl.get_minimum_size().y + 4.0
	_bar(root, SIZE.x / 2.0, by, 600.0, CYAN)
	var pf := _label(root, "PLAY FREE", "wide", 176, GREEN, by + 40.0, GREEN, 18)
	var ry := by + 40.0 + pf.get_minimum_size().y - 10.0
	var rl := _label(root, "RIGHT IN YOUR BROWSER", "wide", 70, Color.WHITE, ry, PINK, 10)
	var py := ry + rl.get_minimum_size().y + 40.0
	# Adresse wie in der Adresszeile
	var pill := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.075, 0.09, 0.95)
	ps.border_color = CYAN
	ps.set_border_width_all(3)
	ps.set_corner_radius_all(40)
	pill.add_theme_stylebox_override("panel", ps)
	pill.position = Vector2(110, py)
	pill.size = Vector2(860, 96)
	root.add_child(pill)
	_lock(root, pill.position + Vector2(48, 32))
	var u := Label.new()
	u.text = "onehumanity.itch.io"
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	u.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var us := LabelSettings.new()
	us.font = UiStyle.font("wide", 0.0)
	us.font_size = 62
	us.font_color = CYAN
	u.label_settings = us
	u.position = pill.position + Vector2(20, 0)
	u.size = pill.size
	root.add_child(u)
	_label(root, "no download · no install", "cond", 54, Color.WHITE, py + 140.0, Color(0, 0, 0), 10)
	_label(root, "also on Windows · Mac · Linux", "cond", 46, Color(0.72, 0.77, 0.88), py + 215.0, Color(0, 0, 0), 8)
	return root


func _render(content: Control, name: String) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(content)
	for i in 3:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	vp.queue_free()
