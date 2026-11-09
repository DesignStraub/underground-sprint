extends CanvasLayer
## Ladebildschirm vor dem Rennen (wie in NFS Underground): Eventname groß, Art als Abzeichen, Ort und Ziel, dein
## Auto, ein Tipp und unten ein Fortschrittsbalken. Die Garage zeigt ihn sofort beim Klick, das Rennen übernimmt ihn
## in seinem ersten Bild (gleiches Aussehen) und füllt den Balken, während es die Strecke in Schritten baut.

const Catalog := preload("res://scripts/catalog.gd")
const UI := preload("res://scripts/ui_style.gd")

## Tipps wie auf den Ladebildschirmen von NFS Underground (auch oben rechts in der Garage)
const TIPS := [
	"Zu schwer? Einstellungen > Schwierigkeit: Leicht. Dann lernst du die Strecken in Ruhe kennen.",
	"Gib kurz vor LOS Gas: Drehzahl im grünen Bereich gibt einen perfekten Start.",
	"Knapp am Verkehr vorbei gibt Punkte und füllt dein Nitro ein Stück.",
	"Im Drag im grünen Bereich schalten: perfekter Schaltvorgang, mehr Schub.",
	"Abkürzungen sparen Zeit, aber dort kommt dir Verkehr entgegen.",
	"Handbremse und Lenken stellen das Auto quer. Drift-Ketten bringen Multiplikator.",
	"Siege schalten neue Teile und Autos frei.",
	"Spar dir Nitro für die letzte Gerade.",
	"Über die Rampe am Bahnübergang springst du über die Gleise.",
	"Motor-Tuning steigert Beschleunigung und Höchstgeschwindigkeit.",
	"Im Drag nicht im Begrenzer bleiben: der Motor überhitzt.",
	"Im Drag schaltest du von Hand: S hoch, X runter. A/D wechselt die Spur.",
	"Tuningteile passen auf alle deine Autos: einmal einbauen, überall dran.",
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
	var col: Color = UI.TYPE_COL.get(rt, UI.CYAN)
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.014, 0.03))
	# schräge Leuchtbänder rechts im Hintergrund in der Farbe der Event-Art
	for i in 6:
		var x0 := sz.x * 0.52 + i * 46.0
		var w := 18.0 + 10.0 * (i % 3)
		var a := 0.05 + 0.025 * ((i * 7) % 4)
		var quad := PackedVector2Array([Vector2(x0 + 120.0, 0), Vector2(x0 + 120.0 + w, 0), Vector2(x0 + w, sz.y), Vector2(x0, sz.y)])
		c.draw_colored_polygon(quad, Color(col.r, col.g, col.b, a))
	c.draw_rect(Rect2(0, 0, sz.x, 2), Color(col.r, col.g, col.b, 0.8))

	# Logo oben links
	var wide := UI.font("wide", 0.15)
	var cond := UI.font("cond", 0.2)
	var bold := UI.font("bold", 0.12)
	_text(wide, Vector2(14, 16), "NEED FOR", 9, Color(0.9, 0.93, 1.0))
	_text(cond, Vector2(13, 33), "GESCHWINDIGKEIT", 17, UI.CYAN)

	# Event: Art als Abzeichen, Name groß, Ort, Ziel
	var y := sz.y * 0.36
	var laps: int = _race.get("laps", 1)
	var kind := {"sprint": tr("SPRINT"), "circuit": tr("RUNDKURS · %d RUNDEN") % laps, "drift": tr("DRIFT · %d RUNDEN") % laps,
		"drag": tr("DRAG")}
	var tier: int = _race.get("tier", 1)
	UI.draw_badge(c, Vector2(28, y - 34), rt, kind.get(rt, "SPRINT"), 11, tier, _race.get("name", "") in GameState.won_events)
	_text(cond, Vector2(26, y + 4), tr(_race.get("name", "")).to_upper(), 34, Color.WHITE, 4)
	c.draw_rect(Rect2(28, y + 12, 210, 2), col)
	c.draw_rect(Rect2(242, y + 12, 44, 2), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.6))
	var town: String = _race.get("town", "")
	if town != "":
		_text(bold, Vector2(30, y + 30), town.to_upper(), 11, UI.CYAN)
	var goal := tr(Catalog.EVENT_TYPES[rt]["goal"])
	if rt == "circuit":
		goal = goal % laps
	elif rt == "drift":
		var tg: Array = Catalog.drift_targets(_race, GameState.difficulty)
		goal = tr("%d Punkte für Platz 1 (Platz 3 ab %d).") % [tg[2], tg[0]]
	_text(bold, Vector2(30, y + 46), (tr("ZIEL: ") + goal).to_upper().trim_suffix("."), 9, Color(0.85, 0.9, 1.0), 3, sz.x * 0.55)

	# dein Auto
	if Catalog.CARS.has(_car):
		var spec: Dictionary = Catalog.CARS[_car]
		_text(bold, Vector2(30, y + 74), tr("DEIN AUTO"), 8, Color(0.6, 0.66, 0.75))
		_text(cond, Vector2(30, y + 92), str(spec["name"]).to_upper() + "   ·   " + tr("KLASSE %s") % spec.get("class", "-"), 15, UI.GREEN)

	# unten: Tipp und Fortschritt
	var by := sz.y - 34.0
	_text(bold, Vector2(28, by - 12), tr("TIPP: ") + tr(TIPS[maxi(tip_i, 0)]), 9, UI.CYAN, 3, sz.x - 56.0)
	var bw := sz.x - 56.0
	c.draw_rect(Rect2(28, by, bw, 5), Color(1, 1, 1, 0.08))
	c.draw_rect(Rect2(28, by - 1, bw * _shown, 7), Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, 0.25))
	c.draw_rect(Rect2(28, by, bw * _shown, 5), UI.PINK)
	var pct := "%s  %d %%" % [tr("LÄDT"), roundi(_shown * 100.0)]
	var pw := cond.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(cond, Vector2(28 + bw - pw, by + 20), pct, 12, Color(0.9, 0.93, 1.0))


func _text(f: Font, pos: Vector2, s: String, size: int, col: Color, outline := 3, width := -1.0) -> void:
	_canvas.draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, outline, Color(0, 0, 0, 0.9))
	_canvas.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, width, size, col)
