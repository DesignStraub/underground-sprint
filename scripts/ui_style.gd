extends RefCounted
## Menü-Look angelehnt an NFS Underground: schräge Leisten, Neongrün für die Auswahl, kursive DIN-Schmalschrift,
## dunkle Glasflächen. Gilt für Garage, Pause und Ergebnis.

const GREEN := Color(0.45, 1.0, 0.3)
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GLASS := Color(0.02, 0.03, 0.06, 0.78)
const SKEW := Vector2(0.28, 0.0)

static var _theme: Theme
static var _fonts := {}


## Schräggestellte Schrift (kursiv wie die NFS-Menüs). kind: cond, bold, wide
static func font(kind := "cond", slant := 0.2) -> Font:
	var key := "%s_%.2f" % [kind, slant]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font
	match kind:
		"wide":
			base = load("res://assets/fonts/D-DINExp-Bold.otf")
		"bold":
			base = load("res://assets/fonts/D-DIN-Bold.otf")
		_:
			base = load("res://assets/fonts/D-DINCondensed-Bold.otf")
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-slant, 1.0), Vector2.ZERO)
	_fonts[key] = fv
	return fv


static func _box(bg: Color, border := Color(0, 0, 0, 0), left := 0, glow := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.skew = SKEW
	sb.border_color = border
	sb.border_width_left = left
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	if glow.a > 0.0:
		sb.shadow_color = glow
		sb.shadow_size = 6
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.set_font("font", "Button", font("cond", 0.2))
	t.set_font_size("font_size", "Button", 14)
	t.set_stylebox("normal", "Button", _box(Color(0.0, 0.0, 0.0, 0.42), Color(CYAN.r, CYAN.g, CYAN.b, 0.5), 2))
	t.set_stylebox("hover", "Button", _box(Color(0.1, 0.25, 0.12, 0.7), GREEN, 3))
	t.set_stylebox("focus", "Button", _box(Color(GREEN.r, GREEN.g, GREEN.b, 0.92), Color.WHITE, 3, Color(GREEN.r, GREEN.g, GREEN.b, 0.45)))
	t.set_stylebox("pressed", "Button", _box(Color(1.0, 1.0, 1.0, 0.95), GREEN, 3))
	t.set_stylebox("disabled", "Button", _box(Color(0.0, 0.0, 0.0, 0.3), Color(0.4, 0.4, 0.4, 0.4), 2))
	t.set_color("font_color", "Button", Color(0.92, 0.95, 1.0))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color(0.02, 0.05, 0.02))
	t.set_color("font_hover_pressed_color", "Button", Color(0.02, 0.05, 0.02))
	t.set_color("font_pressed_color", "Button", Color(0.02, 0.05, 0.02))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.55))
	t.set_constant("outline_size", "Button", 0)
	var panel := StyleBoxFlat.new()
	panel.bg_color = GLASS
	panel.skew = Vector2(0.12, 0.0)
	panel.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.7)
	panel.border_width_left = 3
	panel.border_width_top = 1
	panel.set_content_margin_all(10)
	panel.content_margin_left = 16
	t.set_stylebox("panel", "PanelContainer", panel)
	_theme = t
	return t


## Großer Abschnittstitel mit Leuchtlinie darunter (GARAGE, RENNEN …)
static func section(parent: Control, pos: Vector2) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = font("cond", 0.22)
	ls.font_size = 30
	ls.font_color = GREEN
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.9)
	ls.shadow_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.35)
	ls.shadow_size = 6
	ls.shadow_offset = Vector2.ZERO
	l.label_settings = ls
	l.position = pos
	parent.add_child(l)
	var line := ColorRect.new()
	line.color = GREEN
	line.position = pos + Vector2(2, 36)
	line.size = Vector2(190, 2)
	parent.add_child(line)
	var line2 := ColorRect.new()
	line2.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.6)
	line2.position = pos + Vector2(196, 36)
	line2.size = Vector2(40, 2)
	parent.add_child(line2)
	return l


## Waagerechter Verlauf (für Abdunklung hinter dem Menü)
static func fade_rect(parent: Control, col: Color, horizontal := true) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr
