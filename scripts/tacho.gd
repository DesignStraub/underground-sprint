extends Control
## Drehzahlmesser im Underground-Stil: LED-Bogen aus Segmenten (Cyan, Weiß, Orange, im roten Bereich Rot) mit
## Leuchtschein, kursive Ziffern, spitze Nadel mit Glühen, Gang in der Nabe (neongrün), Tempo groß und kursiv in
## einem dunklen Feld mit blassen führenden Nullen, Nitro als Segmentbogen unten in der Lücke. Am Begrenzer blinkt
## der Rand rot, mit Nitro leuchtet er blau und das Instrument zittert leicht.
## Drag: grüner Schaltbereich auf dem Bogen, Schaltlicht und Motortemperatur.
##
## Ebenen, damit im Browser kaum Zeichenarbeit je Bild anfällt: Gehäuse und Skala einmal, die Nadel einmal
## (je Bild nur gedreht), leuchtende Segmente, Ziffern und Nitro/Rand nur, wenn sich dort etwas ändert.

const UI := preload("res://scripts/ui_style.gd")
const SIZE := 170.0
const C := Vector2(SIZE, SIZE) / 2.0
const R := 66.0  # Außenkante des LED-Bogens
const BAND := 11.0  # Breite des LED-Bogens
const MID := R - BAND / 2.0
const SEGS := 40
const NITRO_SEGS := 8
const MAX_RPM := 8000.0
const REDLINE := 7000.0
const A0 := 150.0  # Startwinkel (links unten), im Uhrzeigersinn über oben nach rechts unten
const SWEEP := 240.0
const PERFECT := Vector2(7100.0, 7650.0)
const LAMP := Vector2(0, -26)
const LAMP_OFF := Color(0.15, 0.15, 0.18)

var rpm := 0.0
var speed_kmh := 0
var gear := "N"
var nitro := 1.0
var nitro_on := false
## Drag: grüner Schaltbereich auf der Skala, Schaltlicht, Motortemperatur
var drag := false:
	set(v):
		drag = v
		for l in [_bg, _band]:
			if l:
				l.queue_redraw()
var heat := 0.0
var _needle := 0.0
var _wide: Font
var _cond: Font
var _root: Control  # alle Ebenen (zittert mit Nitro)
var _bg: Control
var _band: Control
var _needle_n: Control
var _text: Control
var _state: Control
var _lit := -1
var _text_key := ""
var _state_key := ""


func _ready() -> void:
	size = Vector2(SIZE, SIZE)
	_wide = UI.font("wide", 0.2)
	_cond = UI.font("cond", 0.2)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bg = _layer(_draw_static)
	_band = _layer(_draw_band)
	_needle_n = _layer(_draw_needle)
	_needle_n.pivot_offset = C
	_layer(_draw_hub)
	_text = _layer(_draw_text)
	_state = _layer(_draw_state)


func _layer(fn: Callable) -> Control:
	var l := Control.new()
	l.size = size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.draw.connect(fn.bind(l))
	_root.add_child(l)
	return l


func _process(delta: float) -> void:
	_needle = lerpf(_needle, clampf(rpm / MAX_RPM, 0.0, 1.0), minf(delta * 18.0, 1.0))
	var t := Time.get_ticks_msec() / 1000.0
	_root.position = Vector2(sin(t * 61.0), cos(t * 47.0)) * 0.7 if nitro_on else Vector2.ZERO
	_needle_n.rotation = _ang(_needle)
	var lit := mini(int(ceil(_needle * SEGS)), SEGS)
	if lit != _lit:
		_lit = lit
		_band.queue_redraw()
	var tk := "%d|%s" % [speed_kmh, gear]
	if tk != _text_key:
		_text_key = tk
		_text.queue_redraw()
	var limiter := rpm > (PERFECT.y if drag else REDLINE + 200.0)
	var sk := "%d|%d|%d|%d" % [int(nitro * NITRO_SEGS + 0.5), int(t / 0.08) if nitro_on or limiter else -1,
		_lamp_state() if drag else 0, int(heat * 10.0 + 0.5) if drag else 0]
	if sk != _state_key:
		_state_key = sk
		_state.queue_redraw()


func _ang(frac: float) -> float:
	return deg_to_rad(A0 + SWEEP * frac)


func _seg_angles(i: int) -> Vector2:
	var seg := SWEEP / SEGS
	return Vector2(deg_to_rad(A0 + seg * i + seg * 0.14), deg_to_rad(A0 + seg * (i + 1) - seg * 0.14))


func _green(i: int) -> bool:
	var r_mid := (i + 0.5) / SEGS * MAX_RPM
	return drag and r_mid >= PERFECT.x and r_mid <= PERFECT.y


func _led(f: float) -> Color:
	var red := REDLINE / MAX_RPM
	if f >= red:
		return Color(1.0, 0.16, 0.12)
	if f < 0.5:
		return UI.CYAN.lerp(Color(0.8, 0.96, 1.0), f / 0.5)
	return Color(0.8, 0.96, 1.0).lerp(Color(1.0, 0.55, 0.1), (f - 0.5) / (red - 0.5))


func _unlit(i: int) -> Color:
	if _green(i):
		return Color(0.1, 0.8, 0.3, 0.4)
	if (i + 0.5) / SEGS >= REDLINE / MAX_RPM:
		return Color(0.75, 0.05, 0.04, 0.45)
	return Color(1, 1, 1, 0.09)


func _lit_col(i: int) -> Color:
	return Color(0.3, 1.0, 0.4) if _green(i) else _led((i + 0.5) / SEGS)


## 0 aus, 1 grün (perfekt schalten), 2 rot (zu spät)
func _lamp_state() -> int:
	if rpm > PERFECT.y:
		return 2
	return 1 if rpm >= PERFECT.x else 0


## Segmente 0..n-1 als Sehnen (eine Zeichenanweisung für alle), Farbe je Segment
func _segments(l: CanvasItem, n: int, col: Callable) -> void:
	if n <= 0:
		return
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in n:
		var a := _seg_angles(i)
		pts.append(C + Vector2.from_angle(a.x) * MID)
		pts.append(C + Vector2.from_angle(a.y) * MID)
		cols.append(col.call(i))
	l.draw_multiline_colors(pts, cols, BAND)


## Nitro-Segmente 0..n-1 unten in der Lücke (von links nach rechts)
func _nitro(l: CanvasItem, n: int, col: Color) -> void:
	if n <= 0:
		return
	var n0 := deg_to_rad(128.0)
	var n1 := deg_to_rad(52.0)
	var pts := PackedVector2Array()
	for i in mini(n, NITRO_SEGS):
		var f := float(i) / NITRO_SEGS
		for a in [lerpf(n0, n1, f + 0.012), lerpf(n0, n1, f + 1.0 / NITRO_SEGS - 0.012)]:
			pts.append(C + Vector2.from_angle(a) * (R + 1.5))
	l.draw_multiline(pts, col, 6.0)


func _heat_rect(i: int) -> Rect2:
	return Rect2(Vector2(2.0, C.y + 26.0 - i * 6.0), Vector2(7.0, 4.5))


## Gehäuse, Skala, dunkle Segmente, Tempofeld, Beschriftungen
func _draw_static(l: Control) -> void:
	var c := C
	var red_frac := REDLINE / MAX_RPM
	l.draw_circle(c, R + 8.0, Color(0.0, 0.0, 0.0, 0.35))
	l.draw_circle(c, R + 6.5, Color(0.01, 0.015, 0.035, 0.84))
	l.draw_arc(c, R + 3.5, deg_to_rad(205.0), deg_to_rad(335.0), 32, Color(1, 1, 1, 0.1), 2.0, true)
	l.draw_arc(c, R - BAND - 2.5, _ang(0.0), _ang(1.0), 48, Color(1, 1, 1, 0.08), 1.0, true)
	_segments(l, SEGS, _unlit)
	# Striche und kursive Ziffern 0..8
	for i in 9:
		var f := i / 8.0
		var d := Vector2.from_angle(_ang(f))
		var tick_col := Color(1, 0.35, 0.3) if f >= red_frac else Color(0.9, 0.93, 1.0)
		l.draw_line(c + d * (R - BAND - 3.0), c + d * (R - BAND - 7.0), tick_col, 1.5, true)
		l.draw_string(_wide, c + d * (R - BAND - 14.0) + Vector2(-8, 4.5), str(i), HORIZONTAL_ALIGNMENT_CENTER, 16, 12, tick_col)
	if not drag:
		l.draw_string(_cond, c + Vector2(-30, -24), tr("x1000 U/min").to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 60, 7, Color(0.6, 0.7, 0.85))
	# Tempofeld (schräg) und Beschriftungen
	var box := PackedVector2Array([c + Vector2(-27, 24), c + Vector2(33, 24), c + Vector2(28, 46), c + Vector2(-32, 46)])
	l.draw_colored_polygon(box, Color(0.0, 0.0, 0.0, 0.75))
	l.draw_polyline(PackedVector2Array([box[0], box[1], box[2], box[3], box[0]]), Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.35), 1.0, true)
	l.draw_string(_cond, c + Vector2(-20, 56), "KM/H", HORIZONTAL_ALIGNMENT_CENTER, 40, 9, UI.CYAN)
	_nitro(l, NITRO_SEGS, Color(1, 1, 1, 0.1))
	l.draw_string(_cond, c + Vector2(-25, R + 17.0), "NITRO", HORIZONTAL_ALIGNMENT_CENTER, 50, 9, Color(0.45, 0.75, 1.0))
	if drag:
		# Schaltlicht (aus) über der Nabe, Temperaturleiste links neben dem Instrument
		l.draw_circle(c + LAMP, 6.0, Color(0, 0, 0, 0.8))
		l.draw_circle(c + LAMP, 4.5, LAMP_OFF)
		for i in 10:
			var r := _heat_rect(i)
			l.draw_rect(r.grow(1.0), Color(0, 0, 0, 0.7))
			l.draw_rect(r, Color(1, 1, 1, 0.1))
		l.draw_string(_cond, Vector2(-2, c.y + 42.0), "TEMP", HORIZONTAL_ALIGNMENT_CENTER, 16, 7, Color(1, 0.6, 0.4))


## Leuchtende Segmente bis zur Nadel mit Schein darunter
func _draw_band(l: Control) -> void:
	if _lit <= 0:
		return
	var f := float(_lit) / SEGS
	l.draw_arc(C, MID, _ang(0.0), _ang(f), 32, Color(_led(f - 0.5 / SEGS), 0.16), BAND + 7.0)
	_segments(l, _lit, _lit_col)


## Nadel nach rechts (Winkel 0); die Ebene wird je Bild um die Mitte gedreht
func _draw_needle(l: Control) -> void:
	var tip := C + Vector2(R - 1.0, 0)
	var base := C - Vector2(8.0, 0)
	l.draw_colored_polygon(PackedVector2Array([base + Vector2(0, 4.5), tip + Vector2(0, 1.2), tip - Vector2(0, 1.2), base - Vector2(0, 4.5)]), Color(1.0, 0.25, 0.1, 0.25))
	l.draw_colored_polygon(PackedVector2Array([base + Vector2(0, 2.4), tip, base - Vector2(0, 2.4)]), Color(1.0, 0.3, 0.12))
	l.draw_line(C, tip, Color(1.0, 0.85, 0.7, 0.7), 0.8, true)


func _draw_hub(l: Control) -> void:
	l.draw_circle(C, 15.0, Color(0.0, 0.0, 0.0, 0.9))
	l.draw_arc(C, 15.0, 0.0, TAU, 32, Color(0.4, 0.45, 0.55), 1.5, true)


## Gang in der Nabe, Tempo mit blassen führenden Nullen (Ziffern sind gleich breit)
func _draw_text(l: Control) -> void:
	var gcol := UI.GREEN
	if gear == "R":
		gcol = Color(1.0, 0.35, 0.3)
	elif gear == "N":
		gcol = Color(0.8, 0.85, 0.9)
	l.draw_char(_wide, C + Vector2(-_wide.get_char_size(gear.unicode_at(0), 21).x / 2.0 + 1.0, 7.5), gear, 21, gcol)
	var txt := "%03d" % clampi(speed_kmh, 0, 999)
	var lead := 0
	while lead < 2 and txt[lead] == "0":
		lead += 1
	var right := C.x + _wide.get_char_size(48, 23).x * 1.5 + 1.0
	var left := UI.digits_right(l, _wide, right, C.y + 43.5, txt.substr(lead), 23, Color.WHITE)
	if lead > 0:
		UI.digits_right(l, _wide, left, C.y + 43.5, txt.substr(0, lead), 23, Color(1, 1, 1, 0.13))


## Rand (blinkt rot am Begrenzer, blau mit Nitro), Nitro-Segmente, Schaltlicht und Temperatur
func _draw_state(l: Control) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var c := C
	var limiter := rpm > (PERFECT.y if drag else REDLINE + 200.0)
	var rim := Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.75)
	if nitro_on:
		rim = Color(0.55, 0.85, 1.0)
		l.draw_arc(c, R + 6.5, 0.0, TAU, 48, Color(0.3, 0.6, 1.0, 0.35), 7.0)
	if limiter and fmod(t, 0.16) < 0.08:
		rim = Color(1.0, 0.15, 0.1)
		l.draw_arc(c, R + 6.5, 0.0, TAU, 48, Color(1.0, 0.1, 0.05, 0.35), 7.0)
	l.draw_arc(c, R + 6.5, 0.0, TAU, 72, rim, 2.0, true)
	_nitro(l, int(nitro * NITRO_SEGS + 0.5), Color(0.6, 0.9, 1.0) if nitro_on and fmod(t, 0.2) < 0.1 else Color(0.2, 0.55, 1.0))
	if drag:
		var ls := _lamp_state()
		if ls > 0:
			var lc := Color(0.2, 1.0, 0.35) if ls == 1 else Color(1.0, 0.15, 0.1)
			l.draw_circle(c + LAMP, 9.0, Color(lc, 0.3))
			l.draw_circle(c + LAMP, 4.5, lc)
		var hk := clampf(heat, 0.0, 1.0)
		for i in 10:
			if hk > i / 10.0 + 0.05:
				l.draw_rect(_heat_rect(i), Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.15, 0.1), i / 10.0))
