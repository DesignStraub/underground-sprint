extends TextureRect
## Rendert die 3D-Welt in eine eigene Auflösung und skaliert sie auf das Fenster hoch.
## Pixel-Look: 540 Zeilen, pixelgenau (nearest). Sonst höchstens so viele Zeilen wie unter "3D-Auflösung" eingestellt,
## weich hochskaliert – auf 4K-Bildschirmen und Tablets spart das die meiste Arbeit. Die Oberfläche bleibt immer scharf.
## Dynamische Auflösung: fällt die Bildrate unter 60, geht die 3D-Auflösung in Stufen bis auf 60 % herunter und
## später wieder hoch. Bringt das Senken nichts (der Prozessor bremst, nicht die Grafik), bleibt sie oben.
## Gemessen wird der Median je Sekunde, einzelne Hänger (Laden, Shader) zählen nicht.
## 3D-Inhalte gehören als Kinder in `world`.

const DYN_MIN := 0.6
const DYN_STEP := 0.1

var world: SubViewport
var dyn_scale := 1.0
var _win: PackedFloat32Array = []  # Messfenster: Bildzeiten (ms)
var _win_ms := 0.0
var _last_drop_ms := 0.0  # Bildzeit vor dem letzten Absenken (bringt es etwas?)
var _hold := 3.0  # Sekunden bis zur nächsten Änderung (am Anfang warten, bis Shader und Strecke geladen sind)
var _cpu_bound := 0.0  # so lange nicht weiter senken
var _calm := 0.0  # wie lange die Bildrate schon im Ziel liegt


func _init() -> void:
	world = SubViewport.new()
	world.own_world_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.audio_listener_enable_3d = true
	add_child(world)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	texture = world.get_texture()
	get_tree().root.size_changed.connect(_resize)
	GameState.graphics_changed.connect(_resize)
	_resize()


func _exit_tree() -> void:
	GameState.render_lines = 0


func _resize() -> void:
	var px := Vector2(DisplayServer.window_get_size())
	if GameState.pixel_look:
		var shrink := maxf(1.0, roundf(px.y / GameState.PIXEL_H))
		world.size = Vector2i(maxi(int(px.x / shrink), 16), maxi(int(px.y / shrink), 16))
		world.msaa_3d = Viewport.MSAA_DISABLED
		world.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		GameState.render_lines = world.size.y
		return
	if not GameState.gv("dynres"):
		dyn_scale = 1.0
	var scale := minf(1.0, GameState.gv("res") / maxf(px.y, 1.0)) * dyn_scale
	world.size = Vector2i(maxi(int(px.x * scale), 16), maxi(int(px.y * scale), 16))
	var aa: String = GameState.gv("aa")
	world.msaa_3d = {"msaa2": Viewport.MSAA_2X, "msaa4": Viewport.MSAA_4X}.get(aa, Viewport.MSAA_DISABLED)
	world.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	GameState.render_lines = world.size.y


func _process(dt: float) -> void:
	if GameState.pixel_look or not GameState.gv("dynres") or get_tree().paused:
		return
	_win_ms += dt * 1000.0
	_win.append(dt * 1000.0)
	_hold -= dt
	_cpu_bound -= dt
	if _win_ms < 1000.0:
		return
	_win.sort()
	var ms: float = _win[_win.size() / 2]
	_win = []
	_win_ms = 0.0
	if _hold > 0.0:
		return
	# Ziel 60 FPS, mit FPS-Limit darunter dessen Bildrate
	var lim: int = GameState.FPS_LIMITS[GameState.fps_limit]
	var budget := 1000.0 / (mini(lim, 60) if lim > 0 else 60)
	if _last_drop_ms > 0.0:
		# letztes Absenken prüfen: kaum schneller geworden -> Prozessor ist der Engpass, Auflösung zurück
		if ms > _last_drop_ms * 0.93:
			_set_scale(dyn_scale + DYN_STEP)
			_cpu_bound = 30.0
		_last_drop_ms = 0.0
		return
	if ms > budget * 1.15 and dyn_scale > DYN_MIN + 0.01 and _cpu_bound <= 0.0:
		_last_drop_ms = ms
		_calm = 0.0
		_set_scale(dyn_scale - DYN_STEP)
	elif ms < budget * 1.05:
		_calm += 1.0
		if _calm >= 6.0 and dyn_scale < 0.999:
			_calm = 0.0
			_set_scale(dyn_scale + DYN_STEP * 0.5)
	else:
		_calm = 0.0


func _set_scale(s: float) -> void:
	dyn_scale = clampf(s, DYN_MIN, 1.0)
	_hold = 1.0
	_resize()
