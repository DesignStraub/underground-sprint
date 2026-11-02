extends CanvasLayer
## Bildschirmknöpfe für Handy und Tablet (Browser): links Lenken, rechts Gas, Bremse, Nitro, Handbremse,
## oben rechts Pause. Im Drag statt Bremse/Handbremse Hoch- und Runterschalten, Links/Rechts wechselt die Spur.
## TouchScreenButton löst dieselben Aktionen aus wie die Tastatur und kann mehrere Finger gleichzeitig.

const UI := preload("res://scripts/ui_style.gd")

var drag := false
var _btns := []  # [Knopf, Beschriftung, Mittelpunkt-Funktion, Radius]


func _ready() -> void:
	layer = 3
	var steer_l := _make("<", "steer_left", 44, UI.CYAN, true)
	var steer_r := _make(">", "steer_right", 44, UI.CYAN, true)
	var gas := _make(tr("GAS"), "accelerate", 54, UI.GREEN, false)
	var nitro := _make(tr("NITRO"), "nitro", 34, Color(0.3, 0.55, 1.0), false)
	var pause := _make("II", "pause", 18, Color(0.85, 0.85, 0.9), false)
	_place(steer_l, func(s: Vector2): return Vector2(72, s.y - 72))
	_place(steer_r, func(s: Vector2): return Vector2(178, s.y - 72))
	_place(gas, func(s: Vector2): return Vector2(s.x - 72, s.y - 82))
	_place(nitro, func(s: Vector2): return Vector2(s.x - 72, s.y - 196))
	_place(pause, func(s: Vector2): return Vector2(s.x / 2.0, 40))
	if drag:
		_place(_make("E +", "shift_up", 40, UI.GREEN, false), func(s: Vector2): return Vector2(s.x - 186, s.y - 64))
		_place(_make("Q -", "shift_down", 30, Color(1.0, 0.75, 0.3), false), func(s: Vector2): return Vector2(s.x - 186, s.y - 156))
	else:
		_place(_make(tr("BREMSE"), "brake", 38, Color(1.0, 0.3, 0.25), false), func(s: Vector2): return Vector2(s.x - 186, s.y - 60))
		_place(_make(tr("HAND"), "handbrake", 30, Color(1.0, 0.75, 0.3), false), func(s: Vector2): return Vector2(s.x - 186, s.y - 154))
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make(text: String, action: String, radius: float, col: Color, passby: bool) -> Array:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle(radius, col, 0.22)
	b.texture_pressed = _circle(radius, col, 0.55)
	var cs := CircleShape2D.new()
	cs.radius = radius
	b.shape = cs
	b.action = action
	b.passby_press = passby  # Daumen von Links nach Rechts schieben, ohne abzusetzen
	add_child(b)
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = UI.font("cond", 0.15)
	ls.font_size = int(clampf(radius * 0.42, 10.0, 20.0))
	ls.font_color = Color(1, 1, 1, 0.9)
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.8)
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(radius * 2.0, radius * 2.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return [b, l, radius]


func _place(entry: Array, center: Callable) -> void:
	_btns.append([entry[0], entry[1], center, entry[2]])


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	for e in _btns:
		var c: Vector2 = e[2].call(s)
		var r: float = e[3]
		(e[0] as TouchScreenButton).position = c - Vector2(r, r)
		(e[1] as Label).position = c - Vector2(r, r)


## Halbtransparenter Kreis mit hellem Rand
static func _circle(r: float, col: Color, fill: float) -> ImageTexture:
	var n := int(ceil(r * 2.0))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := 0.0
			if d < r - 2.5:
				a = fill
			if d >= r - 3.0 and d < r:
				a = 0.85
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
