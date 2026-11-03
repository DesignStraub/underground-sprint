extends Node
## Werkzeug: erzeugt die nahtlosen Bodentexturen (1024², deckt 8 x 8 m) unter assets/textures:
##   asphalt.png    R Körnung (Splitt, Poren), G Flecken (groß, mittel), B Risse und Teerfugen, A Glanz-Unterschiede
##   asphalt_n.png  Normal-Map aus Splitt, Körnung und Rissen (Lichtreflexe brechen auf dem Asphalt auf)
## Fahrbahn und Gehweg (road.gdshader, pavement.gdshader) färben die Kanäle selbst ein.
## godot --path . res://tools/gen_ground_tex.tscn

const SIZE := 1024


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var fine := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.18, 2, 1)
	var stone_d := _cell(0.2, FastNoiseLite.RETURN_DISTANCE, 2)
	var stone_v := _cell(0.2, FastNoiseLite.RETURN_CELL_VALUE, 2)
	var medium := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.02, 3, 3)
	var blotch := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.004, 4, 4)
	var crack := _crack(0.0055, 5)
	var crack_mask := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0035, 2, 6)
	var gloss := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 3, 7)
	var n := SIZE * SIZE
	var out := PackedByteArray()
	out.resize(n * 4)
	var height := PackedFloat32Array()
	height.resize(n)
	for i in n:
		var s := 1.0 - stone_d[i] / 255.0
		var stone := smoothstep(0.42, 0.62, s)  # Splittkörner: runde Flecken mit weichem Rand
		var v := stone_v[i] / 255.0
		var f := fine[i] / 255.0
		var grain := clampf(0.5 + (f - 0.5) * 0.55 + stone * (v - 0.4) * 0.8 - (1.0 - stone) * 0.1, 0.0, 1.0)
		var line := (1.0 - smoothstep(0.0, 0.05, crack[i] / 255.0)) * smoothstep(0.56, 0.68, crack_mask[i] / 255.0)
		out[i * 4] = int(grain * 255.0)
		out[i * 4 + 1] = int(clampf(blotch[i] / 255.0 * 0.7 + medium[i] / 255.0 * 0.3, 0.0, 1.0) * 255.0)
		out[i * 4 + 2] = int(line * 255.0)
		out[i * 4 + 3] = gloss[i]
		height[i] = stone * (0.55 + 0.45 * v) + f * 0.3 - line * 0.7
	_save(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, out), "asphalt")
	# Normalen aus der Höhe (zentrale Differenzen, über den Rand hinweg, damit die Kachel nahtlos bleibt)
	var nb := PackedByteArray()
	nb.resize(n * 3)
	var k := 2.2
	for y in SIZE:
		for x in SIZE:
			var dx := height[y * SIZE + (x + 1) % SIZE] - height[y * SIZE + (x + SIZE - 1) % SIZE]
			var dy := height[((y + 1) % SIZE) * SIZE + x] - height[((y + SIZE - 1) % SIZE) * SIZE + x]
			var nv := Vector3(-dx * k, dy * k, 1.0).normalized()
			var i := (y * SIZE + x) * 3
			nb[i] = int((nv.x * 0.5 + 0.5) * 255.0)
			nb[i + 1] = int((nv.y * 0.5 + 0.5) * 255.0)
			nb[i + 2] = int((nv.z * 0.5 + 0.5) * 255.0)
	_save(Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, nb), "asphalt_n")
	print("FERTIG in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	get_tree().quit()


func _noise(type: int, freq: float, octaves: int, seed: int) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.noise_type = type
	fn.frequency = freq
	fn.fractal_octaves = octaves
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	fn.seed = seed
	return _bytes(fn)


func _cell(freq: float, ret: int, seed: int) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	fn.cellular_return_type = ret
	fn.cellular_jitter = 0.9
	fn.seed = seed
	return _bytes(fn)


## Zellränder als Risslinien, durch Domain-Warp gewunden wie echte Risse und Teerfugen
func _crack(freq: float, seed: int) -> PackedByteArray:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_CELLULAR
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_NONE
	fn.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	fn.domain_warp_enabled = true
	fn.domain_warp_amplitude = 40.0
	fn.domain_warp_frequency = 0.012
	fn.domain_warp_fractal_octaves = 3
	fn.seed = seed
	return _bytes(fn)


func _bytes(fn: FastNoiseLite) -> PackedByteArray:
	var img := fn.get_seamless_image(SIZE, SIZE, false, false, 0.15, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/textures")
	img.save_png("res://assets/textures/%s.png" % name)
