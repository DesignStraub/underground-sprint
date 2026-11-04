extends Control
## Renn-Anzeigen im Underground-Stil (schräge dunkle Glasleisten, kursive DIN-Schrift, Neongrün und Cyan):
## oben links Platz groß mit „/4“ (leuchtet bei Platzwechsel grün oder rot auf), darunter Zeit, Runde und Rennname;
## oben mittig ein Fortschrittsbalken mit allen Fahrern (du als gelbes Dreieck, Gegner in Lackfarbe, Ziel kariert).
## Drift: statt Platz die Punkte.
##
## Damit im Browser kaum Zeichenarbeit je Bild anfällt: Leisten und Beschriftungen werden einmal gezeichnet, Werte
## nur bei Änderung, die Fahrer auf dem Balken sind einmal gezeichnete Marken, die nur verschoben werden.

const UI := preload("res://scripts/ui_style.gd")
const SK := 0.28  # Schräge der Leisten (wie die Menü-Knöpfe)
const BAR_W := 210.0
const BAR_Y := 11.0
const X := 8.0
const Y := 8.0
const PLACE_H := 44.0
const PLACE_W := 116.0
const ROW_W := 104.0
const TIME_Y := Y + PLACE_H + 4.0

var place := 1
var racers := 4
var drift := false
var points := 0
var time_text := "0:00.00"
var lap := 0  # 0: Sprint ohne Runden
var laps := 1
var title := ""
var show_bar := true
var bar_player := 0.0  # Fortschritt 0..1
var bar_cars := []  # [Fortschritt 0..1, Farbe]
var bar_laps := 1

var _last_place := 0
var _pulse := 0.0
var _pulse_col := UI.GREEN
var _wide: Font
var _cond: Font
var _vals: Control
var _time: Control
var _vals_key := ""
var _shown_time := ""
var _has_lap := false
var _fill: ColorRect
var _dots := []
var _me: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wide = UI.font("wide", 0.2)
	_cond = UI.font("cond", 0.2)
	_vals = _layer(_draw_vals)
	_time = _layer(_draw_time)
	resized.connect(queue_redraw)
	_fill = ColorRect.new()
	_fill.color = Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.85)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.size = Vector2(0, 3)
	add_child(_fill)
	_me = _layer(_draw_me)


func _layer(fn: Callable) -> Control:
	var l := Control.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.draw.connect(fn.bind(l))
	add_child(l)
	return l


func _process(delta: float) -> void:
	if _last_place != 0 and place != _last_place and not drift:
		_pulse = 1.0
		_pulse_col = UI.GREEN if place < _last_place else Color(1.0, 0.3, 0.3)
	_last_place = place
	_pulse = move_toward(_pulse, 0.0, delta * 1.5)
	if (lap > 0) != _has_lap:
		_has_lap = lap > 0
		queue_redraw()
	var key := "%d|%d|%d|%.2f" % [place, points, lap, _pulse]
	if key != _vals_key:
		_vals_key = key
		_vals.queue_redraw()
	if time_text != _shown_time:
		_shown_time = time_text
		_time.queue_redraw()

	_fill.visible = show_bar
	_me.visible = show_bar
	if not show_bar:
		return
	# Fahrer auf dem Balken: Marken nur verschieben
	while _dots.size() < bar_cars.size():
		var col: Color = bar_cars[_dots.size()][1]
		var dot := Control.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.draw.connect(func():
			dot.draw_circle(Vector2.ZERO, 3.6, Color(0, 0, 0, 0.85))
			dot.draw_circle(Vector2.ZERO, 2.6, col))
		add_child(dot)
		move_child(dot, _me.get_index())
		_dots.append(dot)
	var x0 := size.x / 2.0 - BAR_W / 2.0
	for i in bar_cars.size():
		_dots[i].position = Vector2(x0 + BAR_W * clampf(bar_cars[i][0], 0.0, 1.0), BAR_Y + 1.5)
	var px := BAR_W * clampf(bar_player, 0.0, 1.0)
	_fill.position = Vector2(x0, BAR_Y)
	_fill.size.x = px
	_me.position = Vector2(x0 + px, BAR_Y)


## Schräge Leiste: unten links bei pos, oben um SK * h nach rechts versetzt
static func _slab(ci: CanvasItem, pos: Vector2, w: float, h: float, col: Color) -> void:
	var s := SK * h
	ci.draw_colored_polygon(PackedVector2Array([pos + Vector2(s, 0), pos + Vector2(w + s, 0), pos + Vector2(w, h), pos + Vector2(0, h)]), col)


## Leisten, Beschriftungen, Rennname, Grund des Fortschrittsbalkens
func _draw() -> void:
	var y := Y
	_slab(self, Vector2(X, y), PLACE_W, PLACE_H, UI.GLASS)
	_slab(self, Vector2(X, y), 3.0, PLACE_H, UI.GREEN)
	draw_line(Vector2(X + SK * PLACE_H + 3.0, y), Vector2(X + SK * PLACE_H + PLACE_W, y), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.5), 1.0)
	if drift:
		draw_string(_cond, Vector2(X + 18, y + 13), tr("PUNKTE"), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.GREEN)
	else:
		draw_string(_cond, Vector2(X + PLACE_W - 52, y + 15), tr("PLATZ"), HORIZONTAL_ALIGNMENT_RIGHT, 44, 10, UI.GREEN)
	y = TIME_Y
	_row(Vector2(X, y), tr("ZEIT"))
	y += 21.0
	if lap > 0:
		_row(Vector2(X, y), tr("RUNDE"))
		y += 21.0
	draw_string(_cond, Vector2(X + 4, y + 10), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.8, 0.9, 0.85))

	if show_bar:
		var x0 := size.x / 2.0 - BAR_W / 2.0
		_slab(self, Vector2(x0 - 4.0, BAR_Y - 3.0), BAR_W + 8.0, 9.0, UI.GLASS)
		draw_rect(Rect2(x0, BAR_Y, BAR_W, 3.0), Color(1, 1, 1, 0.12))
		for i in range(1, bar_laps):
			var lx := x0 + BAR_W * float(i) / bar_laps
			draw_line(Vector2(lx, BAR_Y - 2.0), Vector2(lx, BAR_Y + 5.0), Color(1, 1, 1, 0.45), 1.0)
		var fx := x0 + BAR_W + 3.0
		for yy in 3:
			for xx in 2:
				draw_rect(Rect2(fx + xx * 2.5, BAR_Y - 2.5 + yy * 2.5, 2.5, 2.5), Color.WHITE if (xx + yy) % 2 == 0 else Color(0.1, 0.1, 0.1))


func _row(pos: Vector2, cap: String) -> void:
	_slab(self, pos, ROW_W, 17.0, UI.GLASS)
	_slab(self, pos, 2.0, 17.0, UI.CYAN)
	draw_string(_cond, pos + Vector2(10, 12.5), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UI.CYAN)


## Platz (oder Punkte) und Runde; kurzes Aufleuchten beim Platzwechsel
func _draw_vals(l: Control) -> void:
	if _pulse > 0.0:
		_slab(l, Vector2(X, Y), PLACE_W, PLACE_H, Color(_pulse_col, 0.35 * _pulse))
	if drift:
		l.draw_string(_wide, Vector2(X + 14, Y + 39), str(points), HORIZONTAL_ALIGNMENT_LEFT, PLACE_W - 14, 25, Color.WHITE)
	else:
		var big := str(place)
		var bw := _wide.get_string_size(big, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
		l.draw_string(_wide, Vector2(X + 18, Y + 40), big, HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color.WHITE)
		l.draw_string(_wide, Vector2(X + 20 + bw, Y + 40), "/%d" % racers, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.65, 0.75, 0.88))
	if lap > 0:
		l.draw_string(_wide, Vector2(X + 10, TIME_Y + 34.5), "%d/%d" % [lap, laps], HORIZONTAL_ALIGNMENT_RIGHT, ROW_W - 6.0, 13, Color.WHITE)


func _draw_time(l: Control) -> void:
	UI.digits_right(l, _wide, X + ROW_W + 4.0, TIME_Y + 13.5, time_text, 13, Color.WHITE)


## Du auf dem Balken: gelbes Dreieck (Spitze am Ursprung)
func _draw_me(l: Control) -> void:
	l.draw_colored_polygon(PackedVector2Array([Vector2(-6.0, -7.0), Vector2(6.0, -7.0), Vector2(0, 2.5)]), Color(0, 0, 0, 0.9))
	l.draw_colored_polygon(PackedVector2Array([Vector2(-4.5, -6.0), Vector2(4.5, -6.0), Vector2(0, 1.0)]), Color(1.0, 0.85, 0.15))
