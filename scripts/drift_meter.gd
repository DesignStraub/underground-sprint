extends Control
## Drift-Wertung mit Anzeige (seit 2.45, Fahrplan Punkt 5 „Driften süchtiger“), für die freie Fahrt (world.gd) und die
## Rennen ohne Drift-Wertung (race.gd). Querfahren füllt die Kette: (Winkel - 10°) x Tempo, erst ab 12° und 35 km/h.
## Boni während des Drifts: GROSSER WINKEL (über 38°) x1,3, SCHNELL (über 110 km/h) x1,25, NAH AM RAND (höchstens
## 1,8 m bis zur Kante der Fahrbahn) x1,5; KNAPP VORBEI im Drift gibt Extrapunkte (add_bonus). Der Multiplikator wächst
## mit der Driftzeit der Kette (alle mult_every Sekunden +1, bis x5). Nach grace Sekunden ohne Drift wird die Kette
## gutgeschrieben (banked), Wand oder Crash kosten sie (lost).
## Anzeige links über dem Radar wie im Rennen (seit 2.48; 2.45 stand sie oben in der Mitte im Sichtfeld): „DRIFT“,
## die Zahl in der Farbe des Multiplikators, Abzeichen „x3“, darunter ein schmaler Balken (beim Driften: Weg zur
## nächsten Stufe; danach: die Frist, die abläuft), die aktiven Boni und eine Zeile für die Driftzone. Linksbündig,
## klein, weicher Schatten statt Kontur. Kein eigener Ton (Effekte dezent, keine künstlichen Klänge).

const UI := preload("res://scripts/ui_style.gd")
const MULT_COL := [Color(0.94, 0.95, 0.97), Color(0.45, 1.0, 0.3), Color(0.35, 0.85, 1.0), Color(1.0, 0.25, 0.7),
	Color(1.0, 0.8, 0.25)]

signal banked(points: int, raw: float, mult: int)
signal lost(points: int)

var player: Node
var grace := 0.9  # s ohne Drift bis zur Gutschrift
var mult_every := 3.0  # s Driftzeit je Stufe
var chain := 0.0  # Punkte der laufenden Kette (ohne Multiplikator)
var chain_t := 0.0
var idle := 0.0
var zone_text := ""  # Zeile unter dem Balken (Driftzone: Stand und Ziel)
var drift_rate := 0.0  # Punkte je s im Moment (für Nitro im Rennen)
var _tags := {}  # Bonus -> Restzeit der Einblendung
var _shown := 0.0
var _flash_t := 0.0  # nach der Gutschrift: „+1.234“ kurz stehen lassen
var _flash_pts := 0
var _crashes := -1
var _walls := -1
var _num: Font
var _lab: Font


func _ready() -> void:
	_num = UI.font("cond", 0.0)
	_lab = UI.font("bold", 0.0, 1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(230, 0)


func mult() -> int:
	return clampi(1 + int(chain_t / mult_every), 1, 5)


## Punkte der laufenden Kette mit Multiplikator (auf 10 gerundet)
func value() -> int:
	return int(chain * mult() / 10.0) * 10


## Extrapunkte in die laufende Kette (knapp vorbei im Drift); hält die Kette offen
func add_bonus(pts: float, tag: String) -> void:
	if chain <= 0.0:
		return
	chain += pts
	idle = 0.0
	_tags[tag] = 1.4


## Kette sofort gutschreiben (Ende einer Driftzone)
func bank_now() -> void:
	if chain > 0.0:
		_bank()


func reset() -> void:
	chain = 0.0
	chain_t = 0.0
	idle = 0.0


func step(dt: float) -> void:
	if player == null:
		return
	if OS.get_cmdline_user_args().has("--metertest"):  # Test: laufende Kette vortäuschen (Bilder der Anzeige)
		chain = maxf(chain, 1260.0)
		chain_t = maxf(chain_t, 7.4)
		idle = 0.0
		_tags["NAH AM RAND"] = 1.0
		_tags["GROSSER WINKEL"] = 1.0
	if _crashes < 0:
		_crashes = player.crashes
		_walls = player.wall_hits
	if player.crashes != _crashes or player.wall_hits != _walls:
		_crashes = player.crashes
		_walls = player.wall_hits
		if chain >= 15.0:
			lost.emit(value())
		reset()
	var kmh: float = player.velocity.length() * 3.6
	drift_rate = 0.0
	if player.drifting and player.drift_angle >= 12.0 and kmh > 35.0 and not player.airborne:
		var ang := clampf(player.drift_angle, 0.0, 60.0)
		var k := 1.0
		if ang > 38.0:
			k *= 1.3
			_tags["GROSSER WINKEL"] = 0.6
		if kmh > 110.0:
			k *= 1.25
			_tags["SCHNELL"] = 0.6
		if _near_edge():
			k *= 1.5
			_tags["NAH AM RAND"] = 0.6
		drift_rate = (ang - 10.0) * kmh / 100.0 * 10.0 * k
		chain += drift_rate * dt
		chain_t += dt
		idle = 0.0
	else:
		idle += dt
		if chain > 0.0 and idle > grace:
			_bank()
	for t in _tags.keys():
		_tags[t] -= dt
		if _tags[t] <= 0.0:
			_tags.erase(t)
	var target := float(value()) if chain > 0.0 else float(_flash_pts)
	_shown = target if absf(target - _shown) < 5.0 else lerpf(_shown, target, minf(dt * 12.0, 1.0))
	_flash_t = maxf(_flash_t - dt, 0.0)
	visible = chain >= 3.0 or _flash_t > 0.0 or zone_text != ""
	# Höhe nach Inhalt (die Spalte links rückt nach): Zahlzeile, Boni, Driftzone
	var h := (26.0 if value() >= 10 or (chain <= 0.0 and _flash_t > 0.0) else 0.0) + (11.0 if not _tags.is_empty() else 0.0) \
		+ (11.0 if zone_text != "" else 0.0)
	if absf(custom_minimum_size.y - h) > 0.5:
		custom_minimum_size = Vector2(230, h)
	queue_redraw()


func _bank() -> void:
	var m := mult()
	var pts := value()
	var raw := chain
	reset()
	if pts >= 50:
		_flash_pts = pts
		_flash_t = 0.9
		banked.emit(pts, raw, m)


## Höchstens 1,8 m bis zur Kante der Fahrbahn (Bordstein, Bande, Wand), innerhalb der Fahrbahn
func _near_edge() -> bool:
	var loc: Dictionary = player.loc
	if loc.is_empty() or not player.offroad.is_empty():
		return false
	var s := float(loc.get("score", 1.0))
	if int((loc["path"] as Dictionary)["id"]) != 0:
		s -= 0.5  # Nebenwege: Aufschlag aus Track.locate wieder abziehen
	return s > -1.8 and s < -0.1


func _draw() -> void:
	var m := mult()
	var col: Color = MULT_COL[m - 1]
	var drifting := chain > 0.0 and idle < 0.05
	var y := 0.0
	if value() >= 10 or (chain <= 0.0 and _flash_t > 0.0):
		var a := 1.0 if chain > 0.0 else clampf(_flash_t / 0.3, 0.0, 1.0)
		var txt := fmt(int(_shown))
		if chain <= 0.0:
			txt = "+" + txt
			col = UI.GOLD
		_text(_lab, Vector2(0, 14), tr("DRIFT"), 8, Color(1, 1, 1, 0.72 * a))
		var x := _lab.get_string_size(tr("DRIFT"), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 6.0
		_text(_num, Vector2(x, 16), txt, 16, Color(col.r, col.g, col.b, a))
		x += _num.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 6.0
		if chain > 0.0 and m > 1:
			draw_rect(Rect2(x, 4, 20, 13), Color(0, 0, 0, 0.45))
			draw_rect(Rect2(x, 4, 20, 13), col, false, 1.0)
			draw_string(_lab, Vector2(x + 3, 14), "x%d" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		if chain > 0.0:
			# Balken: beim Driften der Weg zur nächsten Stufe, danach die ablaufende Frist
			var bw := 110.0
			draw_rect(Rect2(0, 21, bw, 2), Color(0, 0, 0, 0.45))
			var k := (fmod(chain_t, mult_every) / mult_every if m < 5 else 1.0) if drifting else clampf(1.0 - idle / grace, 0.0, 1.0)
			draw_rect(Rect2(0, 21, bw * k, 2), col if drifting else Color(1, 1, 1, 0.8))
		y = 26.0
	if not _tags.is_empty():
		_text(_lab, Vector2(0, y + 8), " · ".join(_tags.keys().map(func(t): return tr(t))), 7, Color(1.0, 0.85, 0.3, 0.95))
		y += 11.0
	if zone_text != "":
		_text(_lab, Vector2(0, y + 8), zone_text, 7, Color(1.0, 0.62, 0.22, 0.95))


## Schrift mit weichem Schatten (wie die Menüs, statt dicker Kontur)
func _text(f: Font, pos: Vector2, t: String, sz: int, col: Color) -> void:
	draw_string(f, pos + Vector2(0.8, 0.8), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6 * col.a))
	draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## 12345 -> „12.345“ (deutsch) bzw. „12,345“ (englisch)
static func fmt(n: int) -> String:
	var s := str(absi(n))
	var sep := "." if TranslationServer.get_locale().begins_with("de") else ","
	var out := ""
	while s.length() > 3:
		out = sep + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
