extends SceneTree
## Fake-Werbeplakate setzen (seit 2.34): jedes Plakat im Hoch- und im Querformat, mit den Schriften des Spiels, in ein
## Bild (assets/posters/posters.png; Aufteilung scripts/poster_atlas.gd). Braucht ein Fenster (kein --headless):
##   python3 tools/poster_gen.py   (Bildmotive, tools/poster_icons)
##   Godot --path . -s tools/posters.gd [-- --out=/pfad.png]
## Alle Marken, Sprüche und Personen sind ausgedacht; keine Anlehnung an echte Firmen oder Werbung.

const Atlas := preload("res://scripts/poster_atlas.gd")

const POSTERS := [
	{"head": "FUNKLOCH+", "sub": "Jetzt noch weniger Empfang.", "small": "Ab 49,99 € im Monat. 24 Monate Laufzeit. Empfang nicht garantiert.",
		"brand": "NETZNIX", "icon": "phone", "font": "saira",
		"bg": "#b6e600", "head_c": "#141414", "sub_c": "#141414", "small_c": "#33400a", "bar": "#141414", "bar_c": "#b6e600"},
	{"head": "GLASFASER KOMMT!", "sub": "Versprochen. Seit 2009.", "small": "Ausbau in Ihrer Straße voraussichtlich ab 2087.",
		"brand": "NETZNIX", "icon": "snail_cable", "font": "saira",
		"bg": "#14213d", "head_c": "#ffd23f", "sub_c": "#ffffff", "small_c": "#9fb0d0", "bar": "#ffd23f", "bar_c": "#14213d"},
	{"head": "DÖNER FÜR 3,50 €", "sub": "Unvergessen.", "small": "In stiller Trauer: alle, die nachts um zwei noch Hunger haben.",
		"brand": "IMBISS EHRENMANN", "icon": "doener", "font": "din", "style": "frame",
		"bg": "#ffffff", "head_c": "#141414", "sub_c": "#141414", "small_c": "#555555", "bar": "#141414", "bar_c": "#ffffff"},
	{"head": "SOCKEN IN SANDALEN", "sub": "Jetzt auch in Carbon.", "small": "Mehr Grip am Grillplatz. Bis Größe 48.",
		"brand": "SANDALO SPORT", "icon": "sandal", "font": "saira",
		"bg": "#4fc3f7", "head_c": "#0d1b2a", "sub_c": "#ffffff", "small_c": "#0d1b2a", "bar": "#0d1b2a", "bar_c": "#4fc3f7"},
	{"head": "ANTRAG AUF ANTRAGSTELLUNG", "sub": "Formblatt B-12b, bitte in dreifacher Ausfertigung.",
		"small": "Bearbeitungszeit 6 bis 8 Monate. Rückfragen nur schriftlich.",
		"brand": "AMT FÜR ÄMTER", "icon": "doc", "font": "din", "style": "stamp",
		"bg": "#efece3", "head_c": "#222222", "sub_c": "#222222", "small_c": "#666666", "bar": "#3a4a5a", "bar_c": "#ffffff"},
	{"head": "SONNTAG IST RUHETAG.", "sub": "Rasenmähen erst wieder Montag, 7:00 Uhr.", "small": "Ihr Nachbarschaftsverein. Wir sehen alles.",
		"brand": "GARTENZWERG E.V.", "icon": "gnome", "font": "saira",
		"bg": "#2e7d32", "head_c": "#fff8e1", "sub_c": "#c8e6c9", "small_c": "#a5d6a7", "bar": "#fff8e1", "bar_c": "#2e7d32"},
	{"head": "TEMPO 30 GRAND PRIX", "sub": "Spannung pur. Im Schritttempo.", "small": "Live in deiner Wohnstraße. Eintritt frei.",
		"brand": "VERKEHRSBERUHIGT MOTORSPORT", "icon": "snail_racer", "font": "chakra", "style": "checker",
		"bg": "#141414", "head_c": "#ffd600", "sub_c": "#ffffff", "small_c": "#bbbbbb", "bar": "#ffd600", "bar_c": "#141414"},
	{"head": "15:00 UHR.", "sub": "Kaffee und Kuchen. Keine Ausnahmen.", "small": "Sahne extra. Diskussion ausgeschlossen.",
		"brand": "KONDITOREI OMA HILDE", "icon": "cake", "font": "inter",
		"bg": "#fff3e0", "head_c": "#4e342e", "sub_c": "#6d4c41", "small_c": "#8d6e63", "bar": "#4e342e", "bar_c": "#fff3e0"},
	{"head": "ZUG FÄLLT AUS.", "sub": "Heute Ersatzverkehr mit Bus. Morgen mit Pferd.", "small": "Wir bitten um Ihr Verständnis. Wie immer.",
		"brand": "REGIONALVERKEHR IRGENDWO", "icon": "train", "font": "din",
		"bg": "#00897b", "head_c": "#ffffff", "sub_c": "#e0f2f1", "small_c": "#b2dfdb", "bar": "#004d40", "bar_c": "#ffffff"},
	{"head": "SPOILER:", "sub": "Du wirst Zweiter.", "small": "Heckflügel ab 19,99 €. Abtrieb nicht inbegriffen.",
		"brand": "FLÜGELWERK TUNING", "icon": "wing", "font": "chakra", "style": "stripes",
		"bg": "#0a0a0a", "head_c": "#76ff03", "sub_c": "#ffffff", "small_c": "#9e9e9e", "bar": "#76ff03", "bar_c": "#0a0a0a"},
	{"head": "MÜLLTRENNUNG", "sub": "Gelb, Blau, Braun, Grau, Glas weiß, Glas grün, Glas braun. Du schaffst das.",
		"small": "Abholung jeden zweiten Mittwoch. Außer manchmal.",
		"brand": "ABFALLWIRTSCHAFT SORTIERT", "icon": "bins", "font": "saira",
		"bg": "#fafafa", "head_c": "#141414", "sub_c": "#333333", "small_c": "#666666", "bar": "#1e88e5", "bar_c": "#ffffff"},
	{"head": "NUR BARGELD.", "sub": "Kartenzahlung ab 50 €. Vielleicht.", "small": "Kartenlesegerät seit 2016 außer Betrieb.",
		"brand": "KIOSK KLEINGELD", "icon": "coins", "font": "saira",
		"bg": "#ffd600", "head_c": "#141414", "sub_c": "#141414", "small_c": "#3a3a3a", "bar": "#141414", "bar_c": "#ffd600"},
	# seit 2.44 echt: ONE HUMANITY (Texte von der eigenen Website oneplanetonehumanity.com)
	{"head": "ONE PLANET. ONE HUMANITY.", "sub": "Verschiedene Projekte, eine Haltung.", "small": "oneplanetonehumanity.com",
		"brand": "ONE HUMANITY", "icon": "onehumanity_white", "font": "din",
		"bg": "#131313", "head_c": "#ffffff", "sub_c": "#d8d8d8", "small_c": "#9a9a9a", "bar": "#ffffff", "bar_c": "#131313"},
	{"head": "ONE HUMANITY LAB", "sub": "Robotics, Games, Tools und 3D-Design. Aus Aachen.",
		"small": "Offen, lokal und für Menschen gemacht.",
		"brand": "ONE HUMANITY LAB", "icon": "onehumanity_dark", "font": "din",
		"bg": "#f2f0ea", "head_c": "#131313", "sub_c": "#2a2a2a", "small_c": "#5a5a5a", "bar": "#131313", "bar_c": "#f2f0ea"},
	{"head": "oneplanet onehumanity.com", "sub": "Need for Geschwindigkeit ist ein Spiel von ONE HUMANITY.",
		"small": "Robotics, Games, Tools und 3D-Design.",
		"brand": "ONEPLANETONEHUMANITY.COM", "icon": "onehumanity_white", "font": "inter",
		"bg": "#1d3557", "head_c": "#ffffff", "sub_c": "#e0e7f0", "small_c": "#a8b8cc", "bar": "#ffffff", "bar_c": "#1d3557"},
]

const FONTS := {
	"saira": "res://assets/fonts/saira/SairaCondensed-Black.ttf",
	"din": "res://assets/fonts/D-DINCondensed-Bold.otf",
	"chakra": "res://assets/fonts/chakrapetch/ChakraPetch-Bold.ttf",
	"inter": "res://assets/fonts/inter/InterDisplay-Bold.ttf",
}
const BODY := "res://assets/fonts/inter/Inter-SemiBold.ttf"
const BAR := "res://assets/fonts/saira/SairaCondensed-Bold.ttf"

var _icons := {}
var _fonts := {}


func _init() -> void:
	var out := Atlas.TEX_PATH
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	for p in POSTERS:
		var src := FileAccess.get_file_as_string("res://tools/poster_icons/%s.svg" % p["icon"])
		var img := Image.new()
		img.load_svg_from_string(src, 1.0)
		_icons[p["icon"]] = ImageTexture.create_from_image(img)
		if str(p["icon"]).begins_with("onehumanity"):
			# Logo: aus dem Original (226,77 Einheiten) groß genug für 170 px gerendert
			img = Image.new()
			img.load_svg_from_string(src, 1.6)
			_icons[p["icon"]] = ImageTexture.create_from_image(img)
	for k in FONTS:
		_fonts[k] = load(FONTS[k])
	_fonts["body"] = load(BODY)
	_fonts["bar"] = load(BAR)
	var vp := SubViewport.new()
	vp.size = Vector2i(int(Atlas.SIZE), int(Atlas.HEIGHT))
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var c := Control.new()
	c.size = Vector2(Atlas.SIZE, Atlas.HEIGHT)
	c.draw.connect(func(): _draw_all(c))
	vp.add_child(c)
	for i in 4:
		await process_frame
	var shot := vp.get_texture().get_image()
	shot.convert(Image.FORMAT_RGB8)
	shot.save_png(out)
	print("POSTERS ", out)
	quit()


func _draw_all(c: Control) -> void:
	c.draw_rect(Rect2(0, 0, Atlas.SIZE, Atlas.HEIGHT), Color(0.1, 0.1, 0.1))
	for i in POSTERS.size():
		for portrait in [true, false]:
			_poster(c, POSTERS[i], Atlas.rect_px(i, portrait), portrait)


## Schriftgröße, bei der der Text umbrochen in die Fläche passt
func _fit(font: Font, text: String, w: float, max_size: int, max_h: float, min_size := 10) -> int:
	var s := max_size
	while s > min_size and font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w, s).y > max_h:
		s -= 1
	return s


## Überschrift: eigener Umbruch mit engem Zeilenabstand; die Größe passt, bis jedes Wort in die Breite und alle
## Zeilen in die Höhe passen (Godots Umbruch schnitt lange Einzelwörter wie ANTRAGSTELLUNG ab)
func _wrap(font: Font, text: String, w: float, size: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur := ""
	for word in text.split(" "):
		var t := word if cur == "" else cur + " " + word
		if cur != "" and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > w:
			lines.append(cur)
			cur = word
		else:
			cur = t
	if cur != "":
		lines.append(cur)
	return lines


func _head(c: Control, font: Font, text: String, x: float, y: float, w: float, max_size: int, max_h: float, col: Color,
		align: int) -> float:
	var s := max_size
	var lines := _wrap(font, text, w, s)
	while s > 16:
		lines = _wrap(font, text, w, s)
		var widest := 0.0
		for ln in lines:
			widest = maxf(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x)
		if widest <= w and lines.size() * s * 0.98 <= max_h:
			break
		s -= 1
	for k in lines.size():
		c.draw_string(font, Vector2(x, y + s * 0.86 + k * s * 0.98), lines[k], align, w, s, col)
	return y + lines.size() * s * 0.98 + s * 0.08


## Text umbrochen ab Oberkante y; liefert die Unterkante
func _text(c: Control, font: Font, text: String, x: float, y: float, w: float, size: int, col: Color, align: int) -> float:
	c.draw_multiline_string(font, Vector2(x, y + font.get_ascent(size)), text, align, w, size, -1, col)
	return y + font.get_multiline_string_size(text, align, w, size).y


func _poster(c: Control, p: Dictionary, r: Rect2, portrait: bool) -> void:
	var bg := Color(p["bg"])
	c.draw_rect(r, bg)
	var style: String = p.get("style", "")
	var bar_h := 40.0 if portrait else 36.0
	var inner := r
	if style == "frame":
		c.draw_rect(r, Color(0.08, 0.08, 0.08))
		inner = r.grow(-12.0)
		c.draw_rect(inner, bg)
		c.draw_rect(inner.grow(-6.0), Color(0.08, 0.08, 0.08), false, 2.0)
	elif style == "checker":
		var sq := 16.0
		for row in 2:
			for k in int(r.size.x / sq):
				if (k + row) % 2 == 0:
					c.draw_rect(Rect2(r.position.x + k * sq, r.position.y + row * sq, sq, sq), Color("#ffd600"))
		inner = Rect2(r.position + Vector2(0, 2 * sq), r.size - Vector2(0, 2 * sq))
	elif style == "stripes":
		for k in 9:
			var x0 := r.position.x + r.size.x * 0.55 + k * 26.0
			c.draw_line(Vector2(x0, r.position.y), Vector2(x0 - r.size.y * 0.6, r.end.y - bar_h), Color(0.46, 1.0, 0.01, 0.16), 6.0)
	# Leiste unten mit der Marke
	var bar := Rect2(r.position.x, r.end.y - bar_h, r.size.x, bar_h)
	if style == "frame":
		bar = Rect2(inner.position.x, inner.end.y - bar_h, inner.size.x, bar_h)
	c.draw_rect(bar, Color(p["bar"]))
	var bf: Font = _fonts["bar"]
	var bs := _fit(bf, p["brand"], bar.size.x - 24.0, 24, bar_h - 8.0)
	c.draw_string(bf, Vector2(bar.position.x + 12.0, bar.position.y + bar_h / 2.0 + bf.get_ascent(bs) * 0.36), p["brand"],
		HORIZONTAL_ALIGNMENT_CENTER, bar.size.x - 24.0, bs, Color(p["bar_c"]))
	var hf: Font = _fonts[p["font"]]
	var body: Font = _fonts["body"]
	var icon: Texture2D = _icons[p["icon"]]
	if portrait:
		var pad := 18.0
		var x := inner.position.x + pad
		var w := inner.size.x - 2.0 * pad
		var top := inner.position.y + 16.0
		var isz := 170.0
		c.draw_texture_rect(icon, Rect2(inner.position.x + (inner.size.x - isz) / 2.0, top, isz, isz), false)
		if style == "stamp":
			_stamp(c, Vector2(inner.position.x + inner.size.x * 0.66, top + isz * 0.72), 0.9)
		var y := top + isz + 10.0
		y = _head(c, hf, p["head"], x, y, w, 66, 128.0, Color(p["head_c"]), HORIZONTAL_ALIGNMENT_CENTER) + 8.0
		var ss := _fit(body, p["sub"], w, 22, 74.0, 11)
		y = _text(c, body, p["sub"], x, y, w, ss, Color(p["sub_c"]), HORIZONTAL_ALIGNMENT_CENTER)
		var sm := _fit(body, p["small"], w, 12, 34.0, 8)
		var sh := body.get_multiline_string_size(p["small"], HORIZONTAL_ALIGNMENT_CENTER, w, sm).y
		_text(c, body, p["small"], x, bar.position.y - sh - 8.0, w, sm, Color(p["small_c"]), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var top := inner.position.y + 14.0
		var avail := bar.position.y - top - 8.0
		var isz := minf(170.0, avail)
		c.draw_texture_rect(icon, Rect2(inner.position.x + 14.0, top + (avail - isz) / 2.0, isz, isz), false)
		if style == "stamp":
			_stamp(c, Vector2(inner.position.x + 14.0 + isz * 0.68, top + (avail - isz) / 2.0 + isz * 0.72), 0.85)
		var x := inner.position.x + isz + 30.0
		var w := inner.end.x - x - 16.0
		var y := top + 4.0
		y = _head(c, hf, p["head"], x, y, w, 62, 120.0, Color(p["head_c"]), HORIZONTAL_ALIGNMENT_LEFT) + 8.0
		var ss := _fit(body, p["sub"], w, 22, 70.0, 11)
		y = _text(c, body, p["sub"], x, y, w, ss, Color(p["sub_c"]), HORIZONTAL_ALIGNMENT_LEFT)
		var sm := _fit(body, p["small"], w, 12, 32.0, 8)
		var sh := body.get_multiline_string_size(p["small"], HORIZONTAL_ALIGNMENT_LEFT, w, sm).y
		_text(c, body, p["small"], x, bar.position.y - sh - 8.0, w, sm, Color(p["small_c"]), HORIZONTAL_ALIGNMENT_LEFT)


## Roter Stempel "GENEHMIGT", schräg
func _stamp(c: Control, at: Vector2, k: float) -> void:
	var f: Font = _fonts["din"]
	var red := Color(0.82, 0.1, 0.1, 0.9)
	c.draw_set_transform(at, -0.3, Vector2(k, k))
	c.draw_rect(Rect2(-78, -26, 156, 52), red, false, 5.0)
	c.draw_string(f, Vector2(-70, 12), "GENEHMIGT", HORIZONTAL_ALIGNMENT_CENTER, 140, 30, red)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
