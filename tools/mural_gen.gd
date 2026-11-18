extends SceneTree
## Wandbild-Maske (seit 2.44): das ONE-HUMANITY-Herz (assets/one_humanity_logo.svg) weiß auf transparent, für die
## Lärmschutzwände (shaders/panel_wall.gdshader). Godot --headless --path . -s tools/mural_gen.gd


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://assets/one_humanity_logo.svg").replace("fill: #131313;", "fill: #ffffff;")
	var img := Image.new()
	img.load_svg_from_string(src, 512.0 / 226.77)
	img.convert(Image.FORMAT_LA8)
	img.save_png("res://assets/murals/onehumanity_heart.png")
	print("MURAL ", img.get_width(), "x", img.get_height())
	quit()
