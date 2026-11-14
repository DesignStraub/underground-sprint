class_name Mist
extends RefCounted
## Gemeinsames Material für Nebelbänke (Landschaft) und Hafennebel über der Straße (Strecken), seit 2.29.
## Die Weltuhr (Landscape.set_daylight) bzw. das Rennen (Stimmung) setzen die Stärke: nachts und morgens kräftig.

const SHADER := preload("res://shaders/fog_bank.gdshader")
static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
	return _mat
