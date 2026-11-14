extends RefCounted
## Menü-Look angelehnt an NFS Underground: schräge Leisten, Neongrün für die Auswahl, kursive DIN-Schmalschrift,
## dunkle Glasflächen. Gilt für Garage, Pause und Ergebnis.

const GREEN := Color(0.45, 1.0, 0.3)
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GLASS := Color(0.02, 0.03, 0.06, 0.78)
const SKEW := Vector2(0.28, 0.0)
const GOLD := Color(1.0, 0.8, 0.25)
## Farbe je Event-Art: überall gleich (Karriere-Liste, Startkarte, Ziel-Banner), damit man die Art auf einen Blick sieht
const TYPE_COL := {"sprint": CYAN, "circuit": GREEN, "drift": Color(1.0, 0.55, 0.12), "drag": PINK}

static var _theme: Theme
static var _fonts := {}


## Schräggestellte Schrift (leicht kursiv wie die NFS-Menüs). kind: cond, bold, wide. Seit 2.29 D-DIN (datto, OFL):
## die DIN der deutschen Straßenschilder, kühl und eng laufend; cond = D-DIN Condensed Bold, bold/wide = D-DIN Bold.
## Davor Rajdhani (Indian Type
## Foundry, OFL): technisch und schmal wie die alte Saira Condensed (die wirkte rundlich und verspielt), die Menüs passen
## ohne Umbruch. cond und wide = Bold (Überschriften, Knöpfe, große Zahlen; wide mit etwas mehr Abstand), bold =
## SemiBold (Text). Zum Vergleich: --uifont=chakra (Chakra Petch, kantiger, breiter) oder --uifont=saira.
static func font(kind := "cond", slant := 0.2) -> Font:
	var key := "%s_%.2f" % [kind, slant]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font
	var fam := "din"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uifont="):  # Test: Schrift vergleichen (rajdhani, chakra, saira)
			fam = a.substr(9)
	match fam + "/" + kind:
		"din/cond":
			base = load("res://assets/fonts/D-DINCondensed-Bold.otf")
		"din/bold", "din/wide":
			base = load("res://assets/fonts/D-DIN-Bold.otf")
		"rajdhani/bold":
			base = load("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")
		"rajdhani/wide", "rajdhani/cond":
			base = load("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")
		"chakra/bold":
			base = load("res://assets/fonts/chakrapetch/ChakraPetch-SemiBold.ttf")
		"chakra/wide", "chakra/cond":
			base = load("res://assets/fonts/chakrapetch/ChakraPetch-Bold.ttf")
		"saira/wide":
			base = load("res://assets/fonts/saira/SairaCondensed-Black.ttf")
		"saira/bold":
			base = load("res://assets/fonts/saira/SairaCondensed-SemiBold.ttf")
		_:
			base = load("res://assets/fonts/saira/SairaCondensed-ExtraBold.ttf")
	var fv := FontVariation.new()
	fv.base_font = base
	# Pfeile, Mittelpunkt & Co. fehlen in D-DIN: aus Rajdhani nachladen
	fv.fallbacks = [load("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")]
	if fam != "din" and kind == "wide":
		fv.spacing_glyph = 2
	# DIN nur leicht schräg: kühler, weniger Spielzeug-Look
	var sl := slant * (0.55 if fam == "din" else 1.0)
	fv.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-sl, 1.0), Vector2.ZERO)
	_fonts[key] = fv
	return fv


## Zahlen ohne Textformung Zeichen für Zeichen zeichnen (für Anzeigen, die sich jedes Bild ändern: Zeit, Tempo).
## Rechtsbündig bis right_x, gibt die linke Kante zurück.
static func digits_right(ci: CanvasItem, f: Font, right_x: float, base_y: float, text: String, size: int, col: Color) -> float:
	var w := 0.0
	for ch in text:
		w += f.get_char_size(ch.unicode_at(0), size).x
	var x := right_x - w
	var left := x
	var rid := ci.get_canvas_item()
	for ch in text:
		x += f.draw_char(rid, Vector2(x, base_y), ch.unicode_at(0), size, col)
	return left


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
	ls.outline_size = 0
	ls.shadow_color = Color(GREEN.r, GREEN.g, GREEN.b, 0.2)
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


## Abzeichen der Event-Art: schräge Leiste in der Farbe der Art, darin das Wort dunkel; dahinter so viele kleine
## Rauten, wie das Event schwer ist (tier 1–3), bei gewonnenen Events golden. Breite: badge_width().
static func draw_badge(ci: CanvasItem, pos: Vector2, type: String, text: String, size: int, tier := 0, won := false) -> float:
	var col: Color = TYPE_COL.get(type, CYAN)
	var f := font("cond", 0.2)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := size + 3.0
	var w := tw + 8.0
	var sk := h * SKEW.x
	var quad := PackedVector2Array([pos + Vector2(sk, 0), pos + Vector2(w + sk, 0), pos + Vector2(w, h), pos + Vector2(0, h)])
	ci.draw_colored_polygon(quad, col)
	quad.append(quad[0])
	ci.draw_polyline(quad, Color(0, 0, 0, 0.75), 1.0)  # dunkler Rand: auch auf dem grünen Fokus-Knopf sichtbar
	ci.draw_string(f, pos + Vector2(4.0 + sk * 0.5, h - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.02, 0.03, 0.05))
	var x := pos.x + w + sk + 3.0
	for i in tier:
		var c := pos + Vector2(x - pos.x + 3.0 + i * 6.5, h / 2.0)
		var r := 2.4
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			GOLD if won else Color(0.9, 0.93, 1.0, 0.85))
	return w + sk + (3.0 + tier * 6.5 + 2.0 if tier > 0 else 0.0)


static func badge_width(text: String, size: int, tier := 0) -> float:
	var tw := font("cond", 0.2).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := size + 3.0
	return tw + 8.0 + h * SKEW.x + (3.0 + tier * 6.5 + 2.0 if tier > 0 else 0.0)
