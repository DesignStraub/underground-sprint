extends CanvasLayer
## Ladebildschirm vor dem Rennen (wie in NFS Underground): Eventname groß, Art als Abzeichen, Ort und Ziel, dein
## Auto, ein Tipp und unten eine dünne Fortschrittslinie (seit 2.35 im ruhigen Menü-Look der Garage). Die Garage zeigt ihn sofort beim Klick, das Rennen übernimmt ihn
## in seinem ersten Bild (gleiches Aussehen) und füllt den Balken, während es die Strecke in Schritten baut.

const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

## Tipps wie auf den Ladebildschirmen von NFS Underground (auch oben rechts in der Garage)
const TIPS := [
	"Zu schwer? Einstellungen > Schwierigkeit: Leicht. Dann lernst du die Strecken in Ruhe kennen.",
	"Gib kurz vor LOS Gas: Drehzahl im grünen Bereich gibt einen perfekten Start.",
	"Knapp am Verkehr vorbei gibt Punkte und füllt dein Nitro ein Stück.",
	"Abkürzungen sparen Zeit, aber dort kommt dir Verkehr entgegen.",
	"Handbremse und Lenken stellen das Auto quer. Drift-Ketten bringen Multiplikator.",
	"Jedes Fahrer-Level schaltet etwas frei: Autos, Teile, Vinyls, Titel. Die Liste steht in der Garage unter Fahrer.",
	"Spar dir Nitro für die letzte Gerade.",
	"Bahnübergang: Blinkt es schon, kommst du mit Vollgas noch knapp vor dem Zug drüber.",
	"Motor-Tuning steigert Beschleunigung und Höchstgeschwindigkeit.",
	"Leistungsteile passen auf alle deine Autos, und deine Optik nimmst du beim Autowechsel mit.",
	"Driften, knapp vorbei und Sprünge geben Punkte, die Nitro etwas nachfüllen.",
	"Nitro brennt nach dem Zünden ein kurzes Stück und braucht danach einen Moment, bis es wieder zündet.",
]

## Gleicher Tipp in Garage und Rennen (der Wechsel der Szene soll nicht springen)
static var tip_i := -1

var progress := 0.0:
	set(v):
		progress = clampf(v, progress, 1.0)  # nie rückwärts
		if _canvas:
			_canvas.queue_redraw()
var _race: Dictionary
var _car := ""
var _canvas: Control
var _shown := 0.0  # gezeichneter Fortschritt (läuft weich hinterher)


func _init(race: Dictionary, car_id: String) -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_race = race
	_car = car_id
	if tip_i < 0:
		tip_i = randi() % TIPS.size()


func _ready() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP  # Klicks gehen nicht ins Menü dahinter
	_canvas.draw.connect(_draw)
	add_child(_canvas)


## Nächstes Rennen bekommt einen neuen Tipp
static func next_tip() -> void:
	tip_i = (tip_i + 1) % TIPS.size() if tip_i >= 0 else randi() % TIPS.size()


func _process(dt: float) -> void:
	if _shown < progress:
		_shown = minf(progress, _shown + dt * 2.5)
		_canvas.queue_redraw()


## Ausblenden und weg (das Rennen ruft das nach dem Laden auf)
func finish(time := 0.35) -> void:
	_shown = 1.0
	progress = 1.0
	var tw := create_tween()
	tw.tween_property(_canvas, "modulate:a", 0.0, time)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var c := _canvas
	var sz := c.size
	var rt: String = _race.get("type", "sprint")
	# ruhiger dunkler Grund mit einem weichen Lichtschein rechts oben wie in der Garage, unten etwas dunkler
	# (seit 2.35 ohne schräge Leuchtbänder)
	c.draw_rect(Rect2(Vector2.ZERO, sz), UI.INK)
	c.draw_texture_rect(_glow_tex(), Rect2(Vector2(sz.x * 0.25, -sz.y * 0.45), Vector2(sz.x * 1.1, sz.y * 1.3)), false)
	c.draw_polygon(PackedVector2Array([Vector2(0, sz.y * 0.55), Vector2(sz.x, sz.y * 0.55), sz, Vector2(0, sz.y)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)]))

	# Wortmarke oben links wie in der Garage
	var wide := UI.font("wide", 0.0, 1)
	var cond := UI.font("cond", 0.0, 1)
	var bold := UI.font("bold", 0.0)
	_text(UI.font("wide", 0.0, 3), Vector2(14.5, 15), "NEED FOR", 6, UI.ACCENT)
	_text(cond, Vector2(14, 28), "GESCHWINDIGKEIT", 12, UI.TEXT)

	# Event: Art als Abzeichen, Name groß, Akzentstrich, Ort, Ziel
	var x := 28.0
	var y := sz.y * 0.36
	var laps: int = _race.get("laps", 1)
	var kind := {"sprint": tr("SPRINT"), "circuit": tr("RUNDKURS · %d RUNDEN") % laps, "drift": tr("DRIFT · %d RUNDEN") % laps,
		"drag": tr("DRAG")}
	var tier: int = _race.get("tier", 1)
	UI.draw_badge(c, Vector2(x, y - 34), rt, kind.get(rt, "SPRINT"), 8, tier, _race.get("name", "") in GameState.won_events)
	_text(cond, Vector2(x - 1, y + 4), tr(_race.get("name", "")).to_upper(), 30, UI.TEXT, sz.x - x * 2.0)
	c.draw_rect(Rect2(x, y + 13, 14, 2), UI.ACCENT)
	c.draw_rect(Rect2(x + 17, y + 13.5, 200, 1), UI.LINE)
	var town: String = _race.get("town", "")
	if town != "":
		_text(wide, Vector2(x, y + 32), town.to_upper(), 9, UI.TEXT)
	var goal := tr(Catalog.EVENT_TYPES[rt]["goal"])
	if rt == "circuit":
		goal = goal % laps
	elif rt == "drift":
		var tg: Array = Catalog.drift_targets(_race, GameState.difficulty)
		goal = tr("%d Punkte für Platz 1 (Platz 3 ab %d).") % [tg[2], tg[0]]
	_text(bold, Vector2(x, y + 47), tr("Ziel: ") + goal, 9, UI.DIM, sz.x * 0.6)

	# dein Auto
	if Catalog.CARS.has(_car):
		var spec: Dictionary = Catalog.CARS[_car]
		_text(wide, Vector2(x, y + 76), tr("DEIN AUTO"), 6, UI.FAINT)
		_text(cond, Vector2(x, y + 93), str(spec["name"]).to_upper(), 14, UI.TEXT)
		var nw := cond.get_string_size(str(spec["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text(wide, Vector2(x + nw + 10.0, y + 92), tr("KLASSE %s") % spec.get("class", "-"), 7, UI.DIM)

	# unten: Tipp und Fortschritt (dünne Linie im Akzent)
	var by := sz.y - 30.0
	var bw := sz.x - x * 2.0
	# Tipp links über der Linie (bei Bedarf zweizeilig, die letzte Zeile auf der Höhe der Prozentzahl rechts)
	var tl := tr("TIPP: ").strip_edges().trim_suffix(":")
	var tlw := wide.get_string_size(tl, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
	var tip_w := minf(bw - tlw - 100.0, 400.0)
	var tip := tr(TIPS[maxi(tip_i, 0)])
	var two := bold.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > tip_w
	var ty := by - (22.0 if two else 11.0)
	_text(wide, Vector2(x, ty), tl, 6, UI.FAINT)
	c.draw_multiline_string(bold, Vector2(x + tlw + 8.0, ty), tip, HORIZONTAL_ALIGNMENT_LEFT, tip_w, 8, 2, UI.DIM)
	c.draw_rect(Rect2(x, by, bw, 1), UI.LINE_HI)
	c.draw_rect(Rect2(x, by - 0.5, bw * _shown, 2), UI.ACCENT)
	var pct := "%s  %d %%" % [tr("LÄDT"), roundi(_shown * 100.0)]
	var pw := wide.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
	_text(wide, Vector2(x + bw - pw, by - 11), pct, 7, UI.TEXT)


## weicher runder Lichtschein (einmal erzeugt)
static var _glow: GradientTexture2D


static func _glow_tex() -> GradientTexture2D:
	if _glow == null:
		var g := Gradient.new()
		g.set_color(0, Color(0.75, 0.82, 1.0, 0.07))
		g.set_color(1, Color(0.75, 0.82, 1.0, 0.0))
		g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		_glow = GradientTexture2D.new()
		_glow.gradient = g
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(1.0, 0.5)
		_glow.width = 256
		_glow.height = 256
	return _glow


func _text(f: Font, pos: Vector2, s: String, size: int, col: Color, width := -1.0) -> void:
	if width > 0.0:
		_canvas.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col, TextServer.JUSTIFICATION_NONE)
		return
	_canvas.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
