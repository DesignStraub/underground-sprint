extends TextureRect
## Rendert die 3D-Welt in eine eigene Auflösung und skaliert sie auf das Fenster hoch.
## Pixel-Look: 540 Zeilen, pixelgenau (nearest). Sonst je nach Grafikstufe höchstens 720/900/1080 Zeilen,
## weich hochskaliert – auf 4K-Bildschirmen spart das die meiste Arbeit. Die Oberfläche bleibt immer scharf.
## 3D-Inhalte gehören als Kinder in `world`.

var world: SubViewport


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


func _resize() -> void:
	var px := Vector2(DisplayServer.window_get_size())
	var q: Dictionary = GameState.q()
	if GameState.pixel_look:
		var shrink := maxf(1.0, roundf(px.y / GameState.PIXEL_H))
		world.size = Vector2i(maxi(int(px.x / shrink), 16), maxi(int(px.y / shrink), 16))
		world.msaa_3d = Viewport.MSAA_DISABLED
		world.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return
	var scale := minf(1.0, q["max_h"] / maxf(px.y, 1.0))
	world.size = Vector2i(maxi(int(px.x * scale), 16), maxi(int(px.y * scale), 16))
	world.msaa_3d = Viewport.MSAA_2X if q["aa"] == "msaa" else Viewport.MSAA_DISABLED
	world.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q["aa"] == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
