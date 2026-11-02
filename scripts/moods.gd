extends RefCounted
## Stimmungen der Strecken: Himmel, Umgebungslicht, Nebel, Mond, Farbfilter, Regen und nasse Straße.
## Jedes Event hat eine ("mood" im Katalog), damit sich nicht jede Strecke gleich anfühlt.

const MOODS := {
	# Lila Neonnacht (Standard)
	"neon": {"top": Color(0.008, 0.01, 0.03), "hor": Color(0.09, 0.05, 0.14), "glow": Color(0.3, 0.14, 0.32), "stars": 1.0,
		"amb": Color(0.25, 0.25, 0.4), "amb_e": 0.26, "fog": Color(0.09, 0.07, 0.16), "fog_d": 0.0045,
		"moon": Color(0.55, 0.6, 1.0), "moon_e": 0.25, "sat": 1.0, "con": 1.0, "bri": 1.0, "rain": false, "wet": 0.0},
	# Klare, kalte Mitternacht: tiefblau, viele Sterne, harter Kontrast
	"mitternacht": {"top": Color(0.002, 0.005, 0.02), "hor": Color(0.02, 0.05, 0.12), "glow": Color(0.05, 0.16, 0.3), "stars": 1.8,
		"amb": Color(0.18, 0.25, 0.44), "amb_e": 0.24, "fog": Color(0.03, 0.06, 0.12), "fog_d": 0.0038,
		"moon": Color(0.6, 0.75, 1.0), "moon_e": 0.34, "sat": 0.9, "con": 1.14, "bri": 0.97, "rain": false, "wet": 0.0},
	# Natriumdampf-Dunst über Industrie und Schnellstraße: orange, staubig
	"natrium": {"top": Color(0.03, 0.015, 0.01), "hor": Color(0.24, 0.11, 0.03), "glow": Color(0.5, 0.24, 0.06), "stars": 0.15,
		"amb": Color(0.42, 0.29, 0.17), "amb_e": 0.28, "fog": Color(0.2, 0.11, 0.05), "fog_d": 0.006,
		"moon": Color(1.0, 0.75, 0.5), "moon_e": 0.14, "sat": 1.12, "con": 1.06, "bri": 1.0, "rain": false, "wet": 0.2},
	# Regen: graublau, kein Mond, Straße glänzt, Tropfen vor der Kamera
	"regen": {"top": Color(0.018, 0.022, 0.03), "hor": Color(0.07, 0.08, 0.1), "glow": Color(0.12, 0.13, 0.17), "stars": 0.0,
		"amb": Color(0.22, 0.26, 0.33), "amb_e": 0.3, "fog": Color(0.08, 0.09, 0.11), "fog_d": 0.0075,
		"moon": Color(0.6, 0.65, 0.75), "moon_e": 0.08, "sat": 0.82, "con": 1.06, "bri": 1.0, "rain": true, "wet": 1.0},
	# Dichter Nebel: Laternen als Lichtkugeln, kurze Sicht
	"nebel": {"top": Color(0.05, 0.05, 0.06), "hor": Color(0.14, 0.14, 0.16), "glow": Color(0.2, 0.2, 0.22), "stars": 0.0,
		"amb": Color(0.3, 0.3, 0.34), "amb_e": 0.3, "fog": Color(0.16, 0.16, 0.18), "fog_d": 0.015,
		"moon": Color(0.7, 0.72, 0.8), "moon_e": 0.08, "sat": 0.85, "con": 0.96, "bri": 1.0, "rain": false, "wet": 0.45},
	# Abenddämmerung: roter Horizont, blauer Himmel darüber, heller
	"daemmerung": {"top": Color(0.03, 0.04, 0.12), "hor": Color(0.5, 0.22, 0.12), "glow": Color(0.7, 0.32, 0.2), "stars": 0.35,
		"amb": Color(0.36, 0.31, 0.44), "amb_e": 0.42, "fog": Color(0.3, 0.17, 0.17), "fog_d": 0.0038,
		"moon": Color(1.0, 0.7, 0.55), "moon_e": 0.36, "sat": 1.1, "con": 1.0, "bri": 1.02, "rain": false, "wet": 0.0},
	# Kiez: Magenta und Cyan, satte Farben
	"kiez": {"top": Color(0.02, 0.005, 0.03), "hor": Color(0.16, 0.03, 0.14), "glow": Color(0.45, 0.08, 0.4), "stars": 0.6,
		"amb": Color(0.3, 0.2, 0.42), "amb_e": 0.28, "fog": Color(0.12, 0.04, 0.14), "fog_d": 0.005,
		"moon": Color(0.8, 0.6, 1.0), "moon_e": 0.2, "sat": 1.22, "con": 1.08, "bri": 1.0, "rain": false, "wet": 0.3},
}


static func get_mood(key: String) -> Dictionary:
	return MOODS.get(key, MOODS["neon"])


## Regen als Partikel, die mit der Kamera wandern (Tropfen fallen schräg gegen die Fahrtrichtung)
static func rain(amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.preprocess = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(14, 1, 16)
	p.position = Vector3(0, 7, -6)
	p.direction = Vector3(0, -1, 0.15)
	p.spread = 4.0
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector3(0, -9.8, 0)
	p.particle_flag_align_y = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.95, 0.35)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.55, 0.012)
	mesh.material = m
	p.mesh = mesh
	return p
