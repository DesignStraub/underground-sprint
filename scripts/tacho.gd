extends Control
## Runder Drehzahlmesser im NFSU-Stil: Nadel + leuchtender Bogen, roter Bereich,
## digitale Geschwindigkeit und Gang in der Mitte, Nitro-Bogen unten in der Lücke.

const R := 62.0
const MAX_RPM := 8000.0
const REDLINE := 7000.0
const A0 := 135.0  # Startwinkel (links unten), Uhrzeigersinn über oben nach rechts unten
const SWEEP := 270.0

var rpm := 0.0
var speed_kmh := 0
var gear := "N"
var nitro := 1.0
var nitro_on := false
var _needle := 0.0


func _process(delta: float) -> void:
	_needle = lerpf(_needle, clampf(rpm / MAX_RPM, 0.0, 1.0), minf(delta * 18.0, 1.0))
	queue_redraw()


func _ang(frac: float) -> float:
	return deg_to_rad(A0 + SWEEP * frac)


func _draw() -> void:
	var c := size / 2.0
	var font := get_theme_default_font()
	var shift_light := rpm > REDLINE + 300.0

	draw_circle(c, R + 8.0, Color(0.0, 0.0, 0.03, 0.7))
	draw_arc(c, R + 8.0, 0.0, TAU, 64, Color(1, 0.15, 0.1) if shift_light else Color(0.2, 0.7, 1.0, 0.8), 2.0, true)

	# Leuchtbogen bis zur Nadel
	var red_frac := REDLINE / MAX_RPM
	draw_arc(c, R - 4.0, _ang(0.0), _ang(1.0), 48, Color(1, 1, 1, 0.08), 6.0, true)
	draw_arc(c, R - 4.0, _ang(red_frac), _ang(1.0), 16, Color(0.6, 0.0, 0.0, 0.7), 6.0, true)
	if _needle > 0.005:
		var col := Color(1.0, 0.25, 0.1) if _needle > red_frac else Color(1.0, 0.6, 0.15)
		draw_arc(c, R - 4.0, _ang(0.0), _ang(_needle), 48, col, 6.0, true)

	# Skala 0..8
	for i in 17:
		var f := i / 16.0
		var d := Vector2.from_angle(_ang(f))
		var major := i % 2 == 0
		var tick_col := Color(1, 0.3, 0.25) if f >= red_frac else Color(0.9, 0.9, 1.0)
		draw_line(c + d * (R - (13.0 if major else 9.0)), c + d * (R - 8.0), tick_col, 1.5 if major else 1.0, true)
		if major:
			var lp := c + d * (R - 21.0)
			draw_string(font, lp + Vector2(-6, 4), str(i / 2), HORIZONTAL_ALIGNMENT_CENTER, 12, 9, tick_col)

	# Nadel
	var nd := Vector2.from_angle(_ang(_needle))
	draw_line(c - nd * 6.0, c + nd * (R - 6.0), Color(1, 0.2, 0.1), 2.5, true)
	draw_circle(c, 4.0, Color(0.15, 0.15, 0.18))

	# Digitale Anzeige
	draw_string(font, c + Vector2(-40, 30), str(speed_kmh), HORIZONTAL_ALIGNMENT_CENTER, 80, 22, Color.WHITE)
	draw_string(font, c + Vector2(-20, 41), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 40, 8, Color(0.7, 0.75, 0.85))
	draw_string(font, c + Vector2(-20, -16), "x1000 rpm", HORIZONTAL_ALIGNMENT_CENTER, 40, 6, Color(0.6, 0.65, 0.75))
	var gb := Rect2(c + Vector2(18, -8), Vector2(16, 18))
	draw_rect(gb, Color(0, 0, 0, 0.6))
	draw_rect(gb, Color(1, 0.6, 0.15), false, 1.0)
	draw_string(font, gb.position + Vector2(0, 14), gear, HORIZONTAL_ALIGNMENT_CENTER, 16, 13, Color(1, 0.7, 0.2))

	# Nitro im unteren Spalt
	var n0 := deg_to_rad(122.0)
	var n1 := deg_to_rad(58.0)
	draw_arc(c, R + 1.0, n0, n1, 16, Color(1, 1, 1, 0.1), 5.0, true)
	if nitro > 0.01:
		var ncol := Color(0.5, 0.85, 1.0) if nitro_on else Color(0.15, 0.5, 1.0)
		draw_arc(c, R + 1.0, n0, lerpf(n0, n1, nitro), 16, ncol, 5.0, true)
	draw_string(font, c + Vector2(-15, R + 16.0), "NOS", HORIZONTAL_ALIGNMENT_CENTER, 30, 8, Color(0.4, 0.7, 1.0))
