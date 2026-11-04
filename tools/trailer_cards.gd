extends Node
## Werkzeug: Texttafeln für den Trailer (1280×720 PNG), Titel und Abspann deckend, Einblendungen mit Transparenz.
## Ortsschilder gelb wie an der Ortseinfahrt, Sprüche in DIN-Schrift.
##   Godot --path . res://tools/trailer_cards.tscn -- --out=/pfad/ordner

const SIZE := Vector2i(1280, 720)
const CYAN := Color(0.35, 0.85, 1.0)
const PINK := Color(1.0, 0.25, 0.7)
const GREEN := Color(0.4, 1.0, 0.55)
const BG := Color(0.03, 0.025, 0.07)

## name -> [Zeilen [Text, Schrift, Größe, Farbe, y]] ; deckend = Hintergrund
const SPRUECHE := {
	"nitro": ["ZÜNDE DAS NITRO", "Knapp am Verkehr vorbei füllt den Tank"],
	"drag": ["DRAG-RENNEN", "Handschaltung · im grünen Bereich perfekt schalten"],
	"drift": ["DRIFT-WERTUNG", "Ketten bis x5 · jede Bande kostet"],
	"bahn": ["SPRING ÜBER DIE GLEISE", "Bevor die Schranke unten ist"],
	"staedte": ["ECHTE STÄDTE. ECHTE STRASSEN.", "Kartendaten © OpenStreetMap-Mitwirkende"],
	"tuning": ["TUNE DEIN AUTO", "15 Autos · 8 Tuning-Kategorien · Siege schalten frei"],
}
const ORTE := {
	"aachen": ["Aachen", "Städteregion Aachen"],
	"wuerzburg": ["Würzburg", "Kreisfreie Stadt"],
	"badkissingen": ["Bad Kissingen", "Landkreis Bad Kissingen"],
	"tbb": ["Tauberbischofsheim", "Main-Tauber-Kreis"],
	"hammelburg": ["Hammelburg", "Landkreis Bad Kissingen"],
}

var out := ""
var cond: Font
var wide: Font
var bold: Font
var regular: Font


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	cond = load("res://assets/fonts/D-DINCondensed-Bold.otf")
	wide = load("res://assets/fonts/D-DINExp-Bold.otf")
	bold = load("res://assets/fonts/D-DIN-Bold.otf")
	regular = load("res://assets/fonts/D-DIN.otf")
	await _render(_title_card(), "titel", false)
	await _render(_end_card(), "abspann", false)
	for k in SPRUECHE:
		await _render(_spruch(SPRUECHE[k][0], SPRUECHE[k][1]), "spruch_" + k, true)
	for k in ORTE:
		await _render(_ortsschild(ORTE[k][0], ORTE[k][1]), "ort_" + k, true)
	get_tree().quit()


func _render(root: Control, name: String, transparent: bool) -> void:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	vp.add_child(root)
	for i in 4:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(out.path_join(name + ".png"))
	vp.queue_free()
	await get_tree().process_frame


func _base(opaque: bool) -> Control:
	var root := Control.new()
	root.size = Vector2(SIZE)
	if opaque:
		var bg := ColorRect.new()
		bg.color = BG
		bg.size = Vector2(SIZE)
		root.add_child(bg)
	return root


func _text(parent: Control, text: String, font: Font, size: int, col: Color, rect: Rect2, glow: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(size / 9, 4)
	ls.outline_color = Color(0, 0, 0, 0.9)
	ls.shadow_size = maxi(size / 5, 6)
	ls.shadow_color = Color(glow.r, glow.g, glow.b, 0.75)
	ls.shadow_offset = Vector2.ZERO
	l.label_settings = ls
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = rect.position
	l.size = rect.size
	parent.add_child(l)
	return l


func _title_card() -> Control:
	var r := _base(true)
	_text(r, "NEED FOR", wide, 92, Color.WHITE, Rect2(0, 150, SIZE.x, 120), CYAN)
	_text(r, "GESCHWINDIGKEIT", cond, 172, CYAN, Rect2(0, 250, SIZE.x, 200), PINK)
	_text(r, "ILLEGALE STRASSENRENNEN BEI NACHT", bold, 34, GREEN, Rect2(0, 470, SIZE.x, 60), GREEN)
	return r


func _end_card() -> Control:
	var r := _base(true)
	_text(r, "NEED FOR", wide, 60, Color.WHITE, Rect2(0, 90, SIZE.x, 80), CYAN)
	_text(r, "GESCHWINDIGKEIT", cond, 116, CYAN, Rect2(0, 156, SIZE.x, 140), PINK)
	_text(r, "JETZT KOSTENLOS", wide, 64, GREEN, Rect2(0, 330, SIZE.x, 90), GREEN)
	_text(r, "auf itch.io  ·  im Browser, Windows, Mac, Linux", bold, 34, Color.WHITE, Rect2(0, 420, SIZE.x, 60), CYAN)
	var logo := TextureRect.new()
	var img := Image.new()
	img.load_svg_from_string(FileAccess.get_file_as_string("res://assets/one_humanity_logo.svg").replace("#131313", "#ffffff"), 2.0)
	logo.texture = ImageTexture.create_from_image(img)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size = Vector2(70, 70)
	logo.position = Vector2(SIZE.x / 2.0 - 200, 560)
	r.add_child(logo)
	_text(r, "ONE HUMANITY", wide, 34, Color.WHITE, Rect2(SIZE.x / 2.0 - 120, 560, 360, 70), CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	return r


## Spruch als Band im oberen Drittel (unten rechts sitzt der Drehzahlmesser): große Zeile, kleine darunter
func _spruch(big: String, small: String) -> Control:
	var r := _base(false)
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.55)
	band.position = Vector2(0, 110)
	band.size = Vector2(SIZE.x, 150)
	r.add_child(band)
	_text(r, big, cond, 84, Color.WHITE, Rect2(0, 108, SIZE.x, 100), PINK)
	_text(r, small, bold, 30, CYAN, Rect2(0, 202, SIZE.x, 50), CYAN)
	return r


## Gelbes Ortsschild (Ortstafel) unten links
func _ortsschild(town: String, region: String) -> Control:
	var r := _base(false)
	var w := maxf(330.0, town.length() * 30.0 + 80.0)
	var x := 48.0
	var y := 500.0
	var border := ColorRect.new()
	border.color = Color(0.03, 0.03, 0.03)
	border.position = Vector2(x, y)
	border.size = Vector2(w, 150)
	r.add_child(border)
	var plate := ColorRect.new()
	plate.color = Color(1.0, 0.8, 0.05)
	plate.position = Vector2(x + 8, y + 8)
	plate.size = Vector2(w - 16, 134)
	r.add_child(plate)
	var inner := ColorRect.new()  # dünne schwarze Innenlinie wie auf der echten Tafel
	inner.color = Color(0.03, 0.03, 0.03)
	inner.position = Vector2(x + 16, y + 16)
	inner.size = Vector2(w - 32, 118)
	r.add_child(inner)
	var plate2 := ColorRect.new()
	plate2.color = Color(1.0, 0.8, 0.05)
	plate2.position = Vector2(x + 20, y + 20)
	plate2.size = Vector2(w - 40, 110)
	r.add_child(plate2)
	var big := Label.new()
	big.text = town
	var ls := LabelSettings.new()
	ls.font = bold
	ls.font_size = 62
	ls.font_color = Color(0.03, 0.03, 0.03)
	big.label_settings = ls
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.position = Vector2(x, y + 22)
	big.size = Vector2(w, 70)
	r.add_child(big)
	var sm := Label.new()
	sm.text = region
	var ls2 := LabelSettings.new()
	ls2.font = regular
	ls2.font_size = 26
	ls2.font_color = Color(0.03, 0.03, 0.03)
	sm.label_settings = ls2
	sm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sm.position = Vector2(x, y + 90)
	sm.size = Vector2(w, 34)
	r.add_child(sm)
	return r
