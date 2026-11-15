extends RefCounted
## Menü-Look (seit 2.35): ruhig und aus einem Guss wie die Menüs von NFS Underground. Dunkle, neutrale Flächen mit
## Haarlinien, Weiß in drei Stufen (TEXT, DIM, FAINT) und genau EIN Akzent: das Grün des Spiels, nur als dünner
## Strich, kleine Schrift oder Füllung schmaler Balken. Gold nur für Gewonnenes. Keine Schrägen, kein Leuchten.
## Bewegung: die Auswahl wächst als Strich mit hellem Verlauf ein (FocusFx), Maus = Tastaturfokus, Übergänge ~0,2 s.
## Gilt für Garage, Lade- und Kartenansicht; Pause und Ergebnis (world.gd, race.gd) bekommen ihn über theme().

## Altbestand: HUD, Tacho, Minikarte und Musik-Blase nutzen diese Farben weiter
const GREEN := Color(0.45, 1.0, 0.3)
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GLASS := Color(0.02, 0.03, 0.06, 0.78)
const SKEW := Vector2(0.28, 0.0)
const GOLD := Color(1.0, 0.8, 0.25)
## Farbe je Event-Art: überall gleich (Abzeichen, Karte, Ziel-Banner), damit man die Art auf einen Blick sieht
const TYPE_COL := {"sprint": CYAN, "circuit": GREEN, "drift": Color(1.0, 0.55, 0.12), "drag": PINK}

## Menüs (seit 2.35)
const ACCENT := Color(0.52, 0.95, 0.36)  # der eine Akzent: Grün des Spiels, eine Spur ruhiger
const INK := Color(0.026, 0.029, 0.036)  # Grund (Lade- und Kartenansicht)
const PANEL := Color(0.036, 0.041, 0.05, 0.88)  # Flächen
const LINE := Color(1.0, 1.0, 1.0, 0.09)  # Haarlinien
const LINE_HI := Color(1.0, 1.0, 1.0, 0.2)
const TEXT := Color(0.94, 0.95, 0.97)
const DIM := Color(0.66, 0.69, 0.74)
const FAINT := Color(0.42, 0.45, 0.5)
const LOSS := Color(0.93, 0.38, 0.33)  # Verlust in der Tuning-Vorschau, sonst nirgends
const CAP := 0.727  # Versalhöhe von Inter (zum Zentrieren von Großbuchstaben)

static var _theme: Theme
static var _fonts := {}


## Schrift der Menüs und Anzeigen. kind: cond (Überschriften, Knöpfe, große Zahlen), bold (Text), wide (kleine
## Titel, Zahlen). Seit 2.30 Inter (Rasmus Andersson, OFL): schlicht und technisch, gerade, eng gesetzt;
## cond = Inter Display Bold, wide = Inter Bold, bold = Inter SemiBold. slant wird bei Inter ignoriert.
## spacing: Laufweite in Pixeln (kleine Versalien wie LEVEL 17 brauchen 1).
## 2.29 D-DIN (leicht schräg), davor Rajdhani (Indian Type
## Foundry, OFL): technisch und schmal wie die alte Saira Condensed (die wirkte rundlich und verspielt), die Menüs passen
## ohne Umbruch. cond und wide = Bold (Überschriften, Knöpfe, große Zahlen; wide mit etwas mehr Abstand), bold =
## SemiBold (Text). Zum Vergleich: --uifont=chakra (Chakra Petch, kantiger, breiter) oder --uifont=saira.
static func font(kind := "cond", slant := 0.2, spacing := 0) -> Font:
	var key := "%s_%.2f_%d" % [kind, slant, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var base: Font
	var fam := "inter"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uifont="):  # Test: Schrift vergleichen (rajdhani, chakra, saira)
			fam = a.substr(9)
	match fam + "/" + kind:
		"inter/cond":
			base = load("res://assets/fonts/inter/InterDisplay-Bold.ttf")
		"inter/wide":
			base = load("res://assets/fonts/inter/Inter-Bold.ttf")
		"inter/bold":
			base = load("res://assets/fonts/inter/Inter-SemiBold.ttf")
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
	if fam == "din":
		# Pfeile, Mittelpunkt & Co. fehlen in D-DIN: aus Rajdhani nachladen
		fv.fallbacks = [load("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")]
	if fam != "din" and fam != "inter" and kind == "wide":
		fv.spacing_glyph = 2
	if spacing != 0:
		fv.spacing_glyph = spacing
	# Inter steht gerade (seit 2.30), DIN nur leicht schräg, die alten Schriften kursiv wie in NFS
	var sl := slant * (0.55 if fam == "din" else (0.0 if fam == "inter" else 1.0))
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


## Fläche mit Haarlinie (alle Panels, Kacheln, Tasten)
static func flat(bg: Color, border := Color(0, 0, 0, 0), bw := 0, radius := 2, mx := 12.0, my := 3.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = radius > 0
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


static func _empty(mx := 12.0, my := 3.0) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


## Glasfläche der Menüs: dunkel, Haarlinie, weicher Schatten
static func panel_box(alpha := 0.88) -> StyleBoxFlat:
	var sb := flat(Color(PANEL.r, PANEL.g, PANEL.b, alpha), LINE, 1, 2, 12.0, 9.0)
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font("bold")
	t.default_font_size = 10
	# Knöpfe (Pause, Ergebnis): dunkle Leiste mit Haarlinie; Fokus legt einen hellen Schleier und den Akzentstrich
	# darüber (Godot zeichnet "focus" über den Zustand), Maus darüber hellt nur auf
	t.set_font("font", "Button", font("cond", 0.0))
	t.set_font_size("font_size", "Button", 12)
	t.set_stylebox("normal", "Button", flat(Color(0.03, 0.034, 0.042, 0.84), Color(1, 1, 1, 0.07), 1, 1))
	t.set_stylebox("hover", "Button", flat(Color(0.065, 0.072, 0.086, 0.9), Color(1, 1, 1, 0.13), 1, 1))
	t.set_stylebox("pressed", "Button", flat(Color(ACCENT.r * 0.3, ACCENT.g * 0.3, ACCENT.b * 0.3, 0.92), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5), 1, 1))
	t.set_stylebox("hover_pressed", "Button", t.get_stylebox("pressed", "Button"))
	t.set_stylebox("disabled", "Button", flat(Color(0.03, 0.034, 0.042, 0.55), Color(1, 1, 1, 0.04), 1, 1))
	var focus := flat(Color(1, 1, 1, 0.07), ACCENT, 0, 1)
	focus.border_width_left = 2
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color(0.8, 0.82, 0.86))
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_hover_pressed_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", FAINT)
	t.set_constant("outline_size", "Button", 0)
	# Listeneintrag der Garage: ohne Fläche, die Auswahl zeichnet FocusFx (Strich + Verlauf, wächst ein)
	t.set_type_variation("MenuItem", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "MenuItem", _empty(12.0, 3.0))
	t.set_font("font", "MenuItem", font("cond", 0.0, 1))
	t.set_font_size("font_size", "MenuItem", 11)
	t.set_color("font_color", "MenuItem", Color(0.74, 0.77, 0.82))
	# Kachel der Tuning-Leiste: Fläche mit Haarlinie, Fokus = Akzentrahmen (+ Strich oben von FocusFx)
	t.set_type_variation("Tile", "Button")
	var tile := flat(Color(0.03, 0.034, 0.042, 0.86), Color(1, 1, 1, 0.08), 1, 2, 6.0, 4.0)
	for st in ["normal", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "Tile", tile)
	t.set_stylebox("hover", "Tile", flat(Color(0.05, 0.056, 0.068, 0.9), Color(1, 1, 1, 0.2), 1, 2, 6.0, 4.0))
	t.set_stylebox("focus", "Tile", flat(Color(1, 1, 1, 0.045), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.75), 1, 2))
	# Farbfeld im Raster: Haarlinie, Fokus = weißer Ring außen (Akzent würde mit den Farben streiten)
	t.set_type_variation("Swatch", "Button")
	var sw := flat(Color(0, 0, 0, 0), Color(1, 1, 1, 0.1), 1, 2, 0.0, 0.0)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "Swatch", sw)
	var ring := flat(Color(0, 0, 0, 0), TEXT, 1, 3, 0.0, 0.0)
	ring.set_expand_margin_all(2.0)
	t.set_stylebox("focus", "Swatch", ring)
	# kleiner flacher Knopf (Zurück über dem Farbraster)
	t.set_type_variation("Ghost", "Button")
	for st in ["normal", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "Ghost", _empty(6.0, 2.0))
	t.set_stylebox("hover", "Ghost", flat(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 1, 6.0, 2.0))
	t.set_stylebox("focus", "Ghost", StyleBoxEmpty.new())
	t.set_font_size("font_size", "Ghost", 9)
	t.set_color("font_color", "Ghost", DIM)
	# Tastenkappe in der Hinweisleiste
	t.set_type_variation("Keycap", "PanelContainer")
	t.set_stylebox("panel", "Keycap", keycap_box())
	# Flächen (Ergebnis, Infofeld, Werte)
	t.set_stylebox("panel", "PanelContainer", panel_box())
	t.set_color("font_color", "Label", TEXT)
	_theme = t
	return t


static func keycap_box() -> StyleBoxFlat:
	var sb := flat(Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.3), 1, 2, 3.0, 0.0)
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 0.0
	return sb


## LabelSettings für Menütexte: keine Kontur (wirkt billig), nur ein leiser Schatten für Lesbarkeit über dem Auto
static func text_settings(size: int, kind := "bold", col := TEXT, spacing := 0) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = font(kind, 0.0, spacing)
	ls.font_size = size
	ls.font_color = col
	ls.shadow_color = Color(0, 0, 0, 0.45)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2(0, 1)
	return ls


static func label(parent: Node, size: int, kind := "bold", col := TEXT, spacing := 0, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.label_settings = text_settings(size, kind, col, spacing)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## Abschnittstitel (GARAGE, TUNING …): weiß, darunter ein kurzer Akzentstrich, der in eine Haarlinie übergeht
static func section(parent: Control, pos: Vector2) -> Label:
	var l := label(parent, 20, "cond", TEXT, 1)
	l.position = pos
	var acc := ColorRect.new()
	acc.color = ACCENT
	acc.position = pos + Vector2(1, 29)
	acc.size = Vector2(14, 2)
	acc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(acc)
	var line := ColorRect.new()
	line.color = LINE
	line.position = pos + Vector2(18, 29.5)
	line.size = Vector2(208, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)
	l.set_meta("lines", [acc, line])
	return l


## Verlauf (Abdunklung hinter Menü, Leiste, Kopf); horizontal: links -> rechts, sonst oben -> unten
static func fade_rect(parent: Control, col: Color, horizontal := true) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC  # weicher Auslauf, keine sichtbare Kante
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 128
	gt.height = 128
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if horizontal else Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	return tr


## Weiche Vignette über der 3D-Ansicht (Ecken dunkler, das Auto bleibt der hellste Punkt)
static func vignette(parent: Control, strength := 0.55) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, strength * 0.25), Color(0, 0, 0, strength)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.08, 1.08)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return tr


## Abzeichen der Event-Art: schmale Marke mit Haarrahmen in der Farbe der Art, das Wort in derselben Farbe, die Fläche
## nur angehaucht; dahinter so viele kleine Rauten, wie das Event schwer ist (tier 1–3), bei gewonnenen Events golden.
## Breite: badge_width().
static func draw_badge(ci: CanvasItem, pos: Vector2, type: String, text: String, size: int, tier := 0, won := false) -> float:
	var col: Color = TYPE_COL.get(type, CYAN)
	var f := font("wide", 0.0, 1)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := size + 4.0
	var w := tw + 9.0
	var sb := flat(Color(col.r, col.g, col.b, 0.13), Color(col.r, col.g, col.b, 0.7), 1, 2, 0.0, 0.0)
	ci.draw_style_box(sb, Rect2(pos, Vector2(w, h)))
	var base := pos.y + (h + size * CAP) / 2.0
	ci.draw_string(f, Vector2(pos.x + 4.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col.lerp(Color.WHITE, 0.3))
	for i in tier:
		var c := Vector2(pos.x + w + 6.0 + i * 6.0, pos.y + h / 2.0)
		var r := 2.2
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
			GOLD if won else Color(DIM.r, DIM.g, DIM.b, 0.9))
	return w + (4.0 + tier * 6.0 if tier > 0 else 0.0)


static func badge_width(text: String, size: int, tier := 0) -> float:
	var tw := font("wide", 0.0, 1).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return tw + 9.0 + (4.0 + tier * 6.0 if tier > 0 else 0.0)


## Tastenhinweise aus einem übersetzten Text "ENTER  Auswählen      ESC  Zurück": abwechselnd Taste und Wort,
## getrennt durch mindestens zwei Leerzeichen -> [[Taste, Wort], …]
static func parse_hints(text: String) -> Array:
	var re := RegEx.new()
	re.compile("\\s{2,}")
	var parts := re.sub(text.strip_edges(), "\t", true).split("\t", false)
	var out := []
	for i in range(0, parts.size() - 1, 2):
		out.append([parts[i], parts[i + 1]])
	return out


## Tastenkappe zeichnen (Karten- und Ladeansicht): Haarrahmen, Taste in Weiß; gibt die Breite zurück
static func draw_keycap(ci: CanvasItem, pos: Vector2, key: String, size := 7) -> float:
	var f := font("wide", 0.0, 0)
	var tw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := size + 5.0
	var w := maxf(tw + 7.0, h)
	ci.draw_style_box(keycap_box(), Rect2(pos, Vector2(w, h)))
	ci.draw_string(f, Vector2(pos.x + (w - tw) / 2.0, pos.y + (h + size * CAP) / 2.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)
	return w


## Taste + Wort; gibt die Breite zurück
static func draw_hint(ci: CanvasItem, pos: Vector2, key: String, text: String, size := 7) -> float:
	var x := pos.x
	for k in key.split(" ", false):
		x += draw_keycap(ci, Vector2(x, pos.y), k, size) + 2.0
	var f := font("bold", 0.0, 0)
	var ts := size + 1
	ci.draw_string(f, Vector2(x + 2.0, pos.y + (size + 5.0 + ts * CAP) / 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, DIM)
	return x + 2.0 + f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x - pos.x


## Hinweisleiste als Controls (Garage): Kappen und Wörter in einer Reihe
static func hint_bar(box: HBoxContainer, text: String) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	for pair in parse_hints(text):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		box.add_child(hb)
		for k in str(pair[0]).split(" ", false):
			var cap := PanelContainer.new()
			cap.theme_type_variation = "Keycap"
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(cap)
			var kl := label(cap, 7, "wide", TEXT, 0, HORIZONTAL_ALIGNMENT_CENTER)
			kl.label_settings.shadow_color = Color(0, 0, 0, 0)
			kl.text = k
			kl.custom_minimum_size.x = 6.0
		var l := label(hb, 8, "bold", DIM)
		l.text = pair[1]


## Auswahl-Effekt für Knöpfe: Akzentstrich wächst ein (links bei Listen, oben bei Kacheln), dahinter ein heller
## Verlauf. hover_focus: Maus darüber = Fokus (nur bei echter Mausbewegung, damit eine Liste, die dem Fokus nach-
## scrollt, nicht unter der ruhenden Maus weiterwandert). Kann auch für die Pause-Knöpfe in world.gd/race.gd
## benutzt werden: UI.menu_fx(b).
static func menu_fx(b: Button, edge := "left", hover_focus := true) -> FocusFx:
	var fx := FocusFx.new()
	fx.edge = edge
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(fx)
	b.focus_entered.connect(fx.set_on.bind(true))
	b.focus_exited.connect(fx.set_on.bind(false))
	if hover_focus:
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseMotion and b.focus_mode != Control.FOCUS_NONE and not b.has_focus():
				b.grab_focus())
	b.set_meta("fx", fx)
	return fx


class FocusFx extends Control:
	var edge := "left"
	var a := 0.0
	var _tw: Tween

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		show_behind_parent = edge == "left"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if get_parent() is Control and (get_parent() as Control).has_focus():
			a = 1.0

	func set_on(on: bool) -> void:
		if _tw:
			_tw.kill()
		if not is_inside_tree():
			a = 1.0 if on else 0.0
			return
		_tw = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tw.tween_method(_set_a, a, 1.0 if on else 0.0, 0.2 if on else 0.14)

	func _set_a(v: float) -> void:
		a = v
		queue_redraw()

	func _draw() -> void:
		if a <= 0.002:
			return
		var s := size
		var acc := Color(ACCENT.r, ACCENT.g, ACCENT.b, a)
		if edge == "left":
			var w := s.x * lerpf(0.45, 1.0, a)
			var a0 := 0.1 * a
			draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, s.y), Vector2(0, s.y)]),
				PackedColorArray([Color(1, 1, 1, a0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, a0)]))
			var h := s.y * lerpf(0.2, 1.0, a)
			draw_rect(Rect2(0, (s.y - h) / 2.0, 2.0, h), acc)
		else:
			var w := (s.x - 2.0) * lerpf(0.15, 1.0, a)
			draw_rect(Rect2((s.x - w) / 2.0, 0, w, 2.0), acc)
