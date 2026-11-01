extends TextureRect
## Rendert die 3D-Welt in eine eigene, kleinere Auflösung und skaliert sie pixelgenau hoch.
## Passt sich an Fenstergröße und Monitor an (720p bis 4K); die Oberfläche bleibt dabei scharf.
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
	var target: float = GameState.PIXEL_MODES[GameState.pixel_mode]["height"]
	var shrink := maxf(1.0, roundf(px.y / target))
	world.size = Vector2i(maxi(int(px.x / shrink), 16), maxi(int(px.y / shrink), 16))
