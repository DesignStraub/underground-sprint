extends "res://scripts/challenger_car.gd"
## Gegner im Autobahn-Rennen (seit 2.43, highway_race.gd). Fährt wie der Herausforderer (Spurwechsel um den Verkehr,
## kein Wrack beim Rempeln), aber eine feste Route aus Abschnitten (legs): die Auffahrt der Startstadt hinunter, auf den
## Ring (Stück für Stück, wie der Verkehr), an der Ausfahrt der Zielstadt ab bis ins Ziel.
## Beim Wechsel des Wegs (Auffahrt -> Ring, Ring -> Ausfahrt) wird die Lage auf den neuen Weg umgerechnet, die Drehung
## zwischen altem und neuem Weg baut _yaw_off weich ab (sonst stünde er schlagartig quer). Vor beiden Abbiegungen bremst
## er auf Kurventempo, vor der Ausfahrt wechselt er rechtzeitig nach rechts. Hinter dem Ziel rollt er aus und bleibt
## am Rand der Ausfahrt stehen, bis highway_race.gd aufräumt.

const TURN_V := 15.0  # m/s in den Abbiegungen (54 km/h)
const BRAKE := 7.5  # m/s² zum Planen der Bremsung (er bremst mit 10)
const EXIT_LANE_AT := 360.0  # so weit vor der Ausfahrt auf die rechte Spur
const SWITCH_D := 12.0  # Auffahrt: so weit vor der Mittellinie des Rings auf den Ring wechseln (äußere Fahrbahn)

var race: Node  # highway_race.gd
var legs: Array = []  # {e (Welt-Eintrag des Autobahnstücks), kind ("ramp"/"main"), dir, ramp (Rampe aus der Planung)}
var leg := -1
var top := 50.0  # Wunschtempo auf dem Ring (m/s): Schwierigkeit und Gummiband (highway_race.gd)
var holding := true  # vor dem Start
var finished := false
var finish_d := 0.0  # Ziel auf der Ausfahrt (Meter auf ihrem Weg)
var route_d := 0.0  # Meter auf der Route (highway_race.gd, gleiche Rechnung wie beim Spieler)
var waiting := false  # nächstes Stück noch nicht gebaut: stehen bleiben, bis es da ist
var _jd := -1.0  # Ring: Meter der Ausfahrt auf diesem Stück (-1: keine)
var _park := false


## Abschnitt i beginnen. project: Lage aus der Weltlage auf den neuen Weg umrechnen (Wechsel Auffahrt <-> Ring);
## sonst am Anfang des nächsten Ringstücks weiter (Spur bleibt). false: Stück noch nicht gebaut.
func enter_leg(i: int, project: bool) -> bool:
	var lg: Dictionary = legs[i]
	var e: Dictionary = lg["e"]
	if e["state"] != "ready" or (e["track"] as Dictionary).is_empty():
		return false
	var tr: Dictionary = e["track"]
	var path: Dictionary = tr["paths"][0]
	if lg["kind"] == "ramp":
		path = find_ramp(tr, lg["ramp"])
		if path.is_empty():
			return false
	var gpos := global_position if is_inside_tree() else Vector3.ZERO
	var gfwd := -global_basis.z if is_inside_tree() else Vector3.FORWARD
	var node: Node = tr["node"]
	if get_parent() != node:
		if get_parent():
			get_parent().remove_child(self)
		node.add_child(self)
	set_meta("e", e)
	track = tr
	curve = path["curve"]
	path_id = path["id"]
	track_length = path["length"]
	blocks = tr["blocks"] if path_id == 0 else []
	parent_basis = (e["xf"] as Transform3D).basis
	dir = lg["dir"]
	_jd = -1.0
	if path_id == 0:
		lane = 6.75 * dir
		if i == legs.size() - 2:  # letztes Ringstück: hier liegt die Ausfahrt
			var rb := find_ramp(tr, legs[i + 1]["ramp"])
			if not rb.is_empty():
				_jd = rb["from"]
	else:
		lane = 2.25 * dir
		if i == legs.size() - 1:
			finish_d = track_length - float(get_meta("finish_in", 26.0))
	if project:
		var lp := (e["xf"] as Transform3D).affine_inverse() * gpos
		progress = curve.get_closest_offset(lp)
		var f := Track.frame_at(curve, progress)
		var lat: float = (lp - f["pos"]).dot(f["right"])
		_lane_cur = Track.logical_lat(tr, progress, lat) if path_id == 0 else lat
		var nf: Vector3 = parent_basis * (f["fwd"] as Vector3) * dir
		_yaw_off = Vector3(nf.x, 0.0, nf.z).signed_angle_to(Vector3(gfwd.x, 0.0, gfwd.z), Vector3.UP)
	else:
		progress = 1.5 if dir > 0.0 else track_length - 1.5
	leg = i
	waiting = false
	_handing = false
	return true


## Weg der Rampe im Autobahnstück (Ende an der Stadt wie in der Planung)
static func find_ramp(tr: Dictionary, ramp: Dictionary) -> Dictionary:
	var end: Vector3 = ramp["end"]
	var xf: Transform3D = tr.get("xf", Transform3D.IDENTITY)
	for p in tr["paths"]:
		if p["kind"] != "ramp":
			continue
		var c: Curve3D = p["curve"]
		var q: Vector3 = xf * c.sample_baked(c.get_baked_length())
		if Vector2(q.x - end.x, q.z - end.z).length() < 3.0:
			return p
	return {}


func _physics_process(dt: float) -> void:
	if leg < 0:
		return
	if waiting:
		_next_leg(legs[leg]["kind"] != "main" or _jd >= 0.0)
		if waiting:
			speed = 0.0
			return
	base_speed = 0.0 if holding else _want()
	# Drehung nach dem Wechsel des Wegs weich abbauen (je schneller, desto zügiger)
	_yaw_off = move_toward(_yaw_off, 0.0, dt * clampf(0.6 + speed * 0.12, 1.4, 4.0))
	super(dt)
	if not holding and not _park:
		_check_leg()


## Wunschtempo: Grundtempo, vor den Abbiegungen so, dass er sie mit TURN_V nimmt; hinter dem Ziel ausrollen
func _want() -> float:
	if _park:
		return 0.0
	var v := top
	var lg: Dictionary = legs[leg]
	if lg["kind"] == "ramp" and leg == 0:
		v = minf(v, sqrt(TURN_V * TURN_V + 2.0 * BRAKE * maxf(progress - SWITCH_D, 0.0)))
	elif lg["kind"] == "main" and _jd >= 0.0:
		var dist := (_jd - progress) * dir
		if dist < EXIT_LANE_AT:
			lane = 11.25 * dir  # rechtzeitig nach rechts
		v = minf(v, sqrt(TURN_V * TURN_V + 2.0 * BRAKE * maxf(dist, 0.0)))
	elif lg["kind"] == "ramp" and finished:
		v = minf(v, 9.0)
	return v


## Kein Spurwechsel nach innen kurz vor der Ausfahrt
func _change_lane() -> void:
	if _jd >= 0.0 and (_jd - progress) * dir < EXIT_LANE_AT:
		return
	super()


func _check_leg() -> void:
	var lg: Dictionary = legs[leg]
	if lg["kind"] == "ramp" and leg == 0:
		if progress <= SWITCH_D:
			_next_leg(true)
	elif lg["kind"] == "main":
		if _jd >= 0.0 and (progress - _jd) * dir >= 0.0:
			_next_leg(true)
		elif (dir > 0.0 and progress >= track_length - 2.0) or (dir < 0.0 and progress <= 2.0):
			_next_leg(false)
	else:
		if not finished and progress >= finish_d:
			finished = true
			if race:
				race.ai_finished(self)
		if finished and progress >= track_length - 14.0:
			_park = true  # am Ende der Ausfahrt am Rand stehen bleiben
			lane = 6.75


func _next_leg(project: bool) -> void:
	if leg + 1 >= legs.size():
		return
	if not enter_leg(leg + 1, project):
		waiting = true  # nächstes Stück noch nicht gebaut (weit vor dem Spieler): warten


## Am Ende eines Abschnitts (Sicherheitsnetz der Grundklasse, eigentlich wechselt _check_leg vorher)
func route_end(_t: Node) -> void:
	_handing = false
	if leg >= 0 and legs[leg]["kind"] == "main" and _jd < 0.0:
		_next_leg(false)
