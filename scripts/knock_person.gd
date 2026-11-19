extends "res://scripts/knockable.gd"
## Passant auf dem Gehweg (seit 2.52): steht unsichtbar als Körper an der Stelle einer Figur im MultiMesh der Gruppe
## (people.gd, gebündelt gezeichnet). Fährt man ihn an, verschwindet die Figur aus dem Bündel und fliegt als einzelne
## Figur davon wie eine Laterne (knockable.gd), mit Staub statt Trümmern. Kostet kaum Tempo.

const People := preload("res://scripts/people.gd")

var slots: Array = []  # [MultiMesh, Index] in allen Fassungen (nah, fern)
var shirt := Color(0.5, 0.5, 0.5)
var custom := Color(0.5, 0.5, 0.0, 0.5)


func _enter_tree() -> void:
	add_to_group("knock_person")


func knock(v: Vector3, at := Vector3.INF) -> void:
	if knocked:
		return
	# aus dem Bündel nehmen (Größe 0) und als einzelne Figur mitfliegen lassen
	var xf: Transform3D = Transform3D()
	for s in slots:
		var mm: MultiMesh = s[0]
		var i: int = s[1]
		if is_instance_valid(mm) and i < mm.instance_count:
			xf = mm.get_instance_transform(i)
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), xf.origin))
	var mi := People.single(self, 0, People.RUN, shirt, custom.r, custom.g)
	mi.transform = Transform3D(xf.basis, Vector3.ZERO)  # Körper steht am Fuß der Figur
	super.knock(v, at)


## keine Splitter: nur etwas Staub
func _debris(_spd: float) -> void:
	TireFx.dust_puff(get_parent(), global_position + Vector3(0, 0.3, 0), 3, 0.6)
