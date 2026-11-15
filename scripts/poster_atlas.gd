extends RefCounted
## Fake-Werbeplakate (seit 2.34): ein Bild (assets/posters/posters.png, 2048 x 2048) mit allen Plakaten, oben
## Hochformat (City-Light an Haltestellen, 6 x 2), unten Querformat (Großfläche, Autobahntafel, 4 x 3). Inhalt und
## Aufteilung: tools/posters.gd. Alle Marken und Sprüche sind ausgedacht.

const N := 12
const SIZE := 2048.0
const TEX_PATH := "res://assets/posters/posters.png"


## Feld von Plakat i im Bild (Pixel): Hochformat 336 x 504, Querformat 504 x 330, mit Rand gegen Mipmap-Bluten
static func rect_px(i: int, portrait: bool) -> Rect2:
	if portrait:
		return Rect2(4 + (i % 6) * 340, 3 + (i / 6) * 510, 332, 500)
	return Rect2(4 + (i % 4) * 512, 1027 + (i / 4) * 336, 504, 330)


## Dasselbe als UV (0..1)
static func uv(i: int, portrait: bool) -> Rect2:
	var r := rect_px(i, portrait)
	return Rect2(r.position / SIZE, r.size / SIZE)


static var _mat: StandardMaterial3D


## Gemeinsamer Stoff aller Plakate: gedruckt, hinterleuchtet wie ein City-Light (nachts lesbar), kaum Spiegelung
static func material() -> StandardMaterial3D:
	if _mat == null and ResourceLoader.exists(TEX_PATH):
		var tex: Texture2D = load(TEX_PATH)
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = tex
		_mat.roughness = 0.85
		_mat.metallic_specular = 0.2  # Papier hinter Glas: kaum Glanz (sonst lag ein grauer Schleier aus dem Himmel darauf)
		_mat.emission_enabled = true
		_mat.emission_texture = tex
		# Multiplizieren: Godot addiert das Leuchtbild sonst auf die Leuchtfarbe, dann lag Weiß über allen Farben
		_mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_mat.emission = Color(1, 1, 1)
		_mat.emission_energy_multiplier = 0.55
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _mat
