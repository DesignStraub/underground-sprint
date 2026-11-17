extends RefCounted
## Modelle des Verkehrs (seit 2.41; Rückmeldung zu 2.40: "der Verkehr sollte auch mehr Details bekommen"). Bis 2.40
## war ein Pkw zwei runde Quader (Karosserie und dunkle Kabine) mit Lichtern und Rädern. Jetzt:
## - Pkw: Karosserie aus Querschnitten (Bug, Motorhaube, Flanke mit Schulter, Heck), darauf eine Kabine aus Glas mit
##   Dach und A-, B- und C-Säulen; Scheinwerfer, Kühlergrill, Lufteinlass, Rückleuchten, Nummernschilder, Außenspiegel,
##   Türfugen und Griffe, Schweller, Radläufe, Felgen. Formen: Limousine, Kombi, Kleinwagen, SUV.
## - Taxi hellelfenbein mit TAXI-Dachschild, Transporter mit Hochdach, Seitenscheiben vorn und Aufschrift (Handwerker),
##   Linienbus mit Fensterband, Türen, Zierstreifen und Zielanzeige, Sattelzug mit Fahrerhaus (Scheiben, Grill, Spiegel,
##   Dachspoiler, Tanks) und Auflieger mit Hecktüren und Unterfahrschutz.
## Lokal: vorn ist -Z, rechts +X, Boden y = 0. Gebaut wird je Art, Form und Farbe einmal (traffic_car._model); alle
## Teile gleichen Materials verschmelzen danach zu einem Draw Call (car_builder.merge_static).

const Builder := preload("res://scripts/car_builder.gd")

## Pkw-Formen: L Länge, W Breite, clear Unterkante der Karosserie, r Radradius, wb Radstand, belt Gürtellinie (Unterkante
## der Scheiben), nose/hood/deck/tail Höhe von Bug, Haube (am Scheibenfuß), Kofferraum und Heck, ws Fuß der Frontscheibe,
## r0/r1 Dach von/bis, rw Fuß der Heckscheibe (alle z ab Wagenmitte, vorn negativ), roof Dachhöhe
const CARS := {
	"limousine": {"L": 4.66, "W": 1.82, "clear": 0.2, "r": 0.32, "wb": 2.76, "belt": 0.93, "nose": 0.64, "hood": 0.9,
		"deck": 0.97, "tail": 0.9, "ws": -0.92, "r0": -0.22, "r1": 0.82, "rw": 1.42, "roof": 1.45, "doors": 4},
	"kombi": {"L": 4.74, "W": 1.82, "clear": 0.2, "r": 0.32, "wb": 2.8, "belt": 0.93, "nose": 0.64, "hood": 0.9,
		"deck": 0.98, "tail": 0.98, "ws": -0.95, "r0": -0.25, "r1": 1.88, "rw": 2.22, "roof": 1.48, "doors": 4},
	"kleinwagen": {"L": 3.96, "W": 1.74, "clear": 0.2, "r": 0.3, "wb": 2.5, "belt": 0.95, "nose": 0.66, "hood": 0.92,
		"deck": 1.0, "tail": 1.0, "ws": -0.82, "r0": -0.16, "r1": 1.18, "rw": 1.84, "roof": 1.5, "doors": 2},
	"suv": {"L": 4.72, "W": 1.9, "clear": 0.32, "r": 0.38, "wb": 2.82, "belt": 1.12, "nose": 0.86, "hood": 1.08,
		"deck": 1.14, "tail": 1.12, "ws": -0.98, "r0": -0.3, "r1": 1.82, "rw": 2.2, "roof": 1.74, "doors": 4},
}
const FORMS := ["limousine", "limousine", "kombi", "kleinwagen", "kleinwagen", "suv"]
const TAXI_IVORY := Color(0.93, 0.89, 0.72)  # Hellelfenbein (RAL 1015), wie die Taxis in Deutschland
const HANDWERK := ["ELEKTRO MÜLLER", "BÄCKEREI SCHMITT", "MALERMEISTER KLEIN", "SANITÄR HOFMANN", "GARTENBAU LINDNER",
	"KURIER EXPRESS", "UMZÜGE BECKER", "DACHDECKEREI WOLF", "FLIESEN KAYA", "PARTYSERVICE NOWAK"]
const LINIEN := ["7 HAUPTBAHNHOF", "12 MESSE", "3 ALTSTADT", "N4 STADION", "21 KLINIKUM", "5 HAFEN", "9 UNIVERSITÄT",
	"16 RATHAUS"]
const PLATES := ["B-RS 4271", "M-AK 382", "F-NG 2039", "K-LX 715", "HH-TR 991", "S-UR 6604", "AC-DC 112", "WÜ-MB 53",
	"KA-ZE 808", "HD-GT 240"]

static var _mats := {}


## Gemeinsame Materialien (einmal angelegt; je Lackfarbe ein eigenes)
static func _m(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"glass":
			m = Builder.mat(Color(0.04, 0.05, 0.07), 0.75, 0.08)
		"trim":
			m = Builder.mat(Color(0.05, 0.05, 0.055), 0.2, 0.75)
		"chrome":
			m = Builder.mat(Color(0.75, 0.76, 0.78), 0.9, 0.18)
		"rim":
			m = Builder.mat(Color(0.62, 0.63, 0.65), 0.75, 0.3)
		"tire":
			m = Builder.mat(Color(0.045, 0.045, 0.045), 0.0, 0.9)
		"head":
			m = Builder.mat(Color(1.0, 1.0, 0.92), 0.0, 0.25, Color(1.0, 0.96, 0.82), 4.0)
		"tail":
			m = Builder.mat(Color(0.55, 0.0, 0.0), 0.0, 0.3, Color(1.0, 0.05, 0.02), 3.0)
		"ind":
			m = Builder.mat(Color(1.0, 0.55, 0.05), 0.0, 0.3, Color(1.0, 0.5, 0.05), 1.0)
		"plate":
			m = Builder.mat(Color(0.92, 0.92, 0.9), 0.0, 0.5)
		"ink":
			m = Builder.mat(Color(0.03, 0.03, 0.03), 0.0, 0.6)
		"eu":
			m = Builder.mat(Color(0.05, 0.15, 0.6), 0.0, 0.5)
		"grey":
			m = Builder.mat(Color(0.35, 0.36, 0.38), 0.4, 0.5)
		"sign":
			m = Builder.mat(Color(1.0, 0.95, 0.55), 0.0, 0.4, Color(1.0, 0.92, 0.5), 1.6)
		"led":
			m = Builder.mat(Color(0.05, 0.03, 0.0), 0.0, 0.5)
		"white":
			m = Builder.mat(Color(0.9, 0.9, 0.88), 0.1, 0.55)
		_:
			m = Builder.mat(Color.MAGENTA)
	_mats[key] = m
	return m


static func _paint(c: Color) -> Material:
	var key := "paint_" + c.to_html(false)
	if not _mats.has(key):
		_mats[key] = Builder.gloss_mat(c, 0.3, 0.4)
	return _mats[key]


# --- Bausteine ----------------------------------------------------------------------------------------------------

## Dreieck so ausgeben, dass es von außen (Richtung out) die Vorderseite zeigt (Godot: im Uhrzeigersinn)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	if (b - a).cross(c - a).dot(out) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


## Querschnitt einer Karosserie bei z: unten y0 (Unterkante), oben y1, halbe Breite an der Schulter hw, oben ht, Rundung r.
## Punkte von unten links über oben nach unten rechts (10 Stück)
static func _section(z: float, y0: float, y1: float, hw: float, ht: float, r: float) -> Array:
	var h := maxf(y1 - y0, 0.02)
	var rr := minf(r, h * 0.45)
	return [Vector3(-hw * 0.95, y0, z), Vector3(-hw, y0 + h * 0.22, z), Vector3(-hw, y0 + h * 0.62, z),
		Vector3(-lerpf(hw, ht, 0.7), y1 - rr * 0.45, z), Vector3(-ht + rr * 0.35, y1, z),
		Vector3(ht - rr * 0.35, y1, z), Vector3(lerpf(hw, ht, 0.7), y1 - rr * 0.45, z), Vector3(hw, y0 + h * 0.62, z),
		Vector3(hw, y0 + h * 0.22, z), Vector3(hw * 0.95, y0, z)]


## Körper aus Querschnitten [z, y0, y1, hw, ht, r] (von vorn nach hinten): Mantel weich schattiert, Enden flach zu
static func _loft(n: Node3D, secs: Array, mat: Material, caps := true) -> void:
	var rings := []
	for s in secs:
		rings.append(_section(s[0], s[1], s[2], s[3], s[4], s[5]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var np: int = rings[0].size()
	for i in rings.size() - 1:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var cy: float = (float(secs[i][1]) + float(secs[i][2])) * 0.5
		for k in np:
			var k2 := (k + 1) % np
			var mid: Vector3 = (a[k] + a[k2] + b[k] + b[k2]) / 4.0
			var out := mid - Vector3(0, cy, mid.z)
			_tri(st, a[k], a[k2], b[k2], out)
			_tri(st, a[k], b[k2], b[k], out)
	st.index()
	st.generate_normals()
	Builder._add(n, st.commit(), mat, Vector3.ZERO)
	if caps:
		var cs := SurfaceTool.new()
		cs.begin(Mesh.PRIMITIVE_TRIANGLES)
		for e in [0, rings.size() - 1]:
			var ring: Array = rings[e]
			var c := Vector3.ZERO
			for p in ring:
				c += p / float(np)
			var out := Vector3(0, 0, -1) if e == 0 else Vector3(0, 0, 1)
			for k in np:
				_tri(cs, c, ring[k], ring[(k + 1) % np], out)
		cs.generate_normals()
		Builder._add(n, cs.commit(), mat, Vector3.ZERO)


## Quader zwischen zwei Punkten (Säulen, Streben): Dicke t quer, d in der dritten Richtung
static func _strut(n: Node3D, a: Vector3, b: Vector3, t: float, d: float, mat: Material) -> void:
	var len := a.distance_to(b)
	if len < 0.01:
		return
	var fwd := (b - a) / len
	var side := fwd.cross(Vector3.RIGHT if absf(fwd.x) < 0.9 else Vector3.FORWARD).normalized()
	var up := side.cross(fwd).normalized()
	var mi := Builder._add(n, Builder.box(Vector3(t, d, len)), mat, (a + b) / 2.0)
	mi.basis = Basis(side, up, -fwd).orthonormalized()


## Rad: Reifen, Felge mit fünf Speichen und Nabe, dahinter ein dunkler Radlauf auf der Flanke (xs: Seite, xf: Flanke)
static func _wheel(n: Node3D, x: float, y: float, z: float, r: float, w: float, side: float, flank: float) -> void:
	var tire := CylinderMesh.new()
	tire.top_radius = r
	tire.bottom_radius = r
	tire.height = w
	tire.radial_segments = 18
	tire.rings = 1
	Builder._add(n, tire, _m("tire"), Vector3(x, y, z)).rotation_degrees.z = 90.0
	var arch := Builder._disc(r + 0.075, 0.006)
	Builder._add(n, arch, _m("trim"), Vector3(side * (flank + 0.004), y + 0.02, z)).rotation_degrees.z = 90.0
	var face := x + side * (w / 2.0 + 0.004)
	Builder._add(n, Builder._disc(r * 0.64, 0.012), _m("rim"), Vector3(face, y, z)).rotation_degrees.z = 90.0
	Builder._add(n, Builder._disc(r * 0.2, 0.03), _m("chrome"), Vector3(face + side * 0.012, y, z)).rotation_degrees.z = 90.0
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		var sp := Builder._add(n, Builder.box(Vector3(0.016, r * 0.42, 0.055)), _m("trim"),
			Vector3(face + side * 0.008, y + sin(a) * r * 0.36, z + cos(a) * r * 0.36))
		sp.rotation = Vector3(-a + PI / 2.0, 0, 0)


## Nummernschild (weiß, blaues EU-Feld, schwarze Schrift) mit +Z oder -Z nach außen
static func _plate(n: Node3D, pos: Vector3, out_z: float, text: String) -> void:
	var pm := Builder._add(n, Builder.rbox(Vector3(0.52, 0.115, 0.02), 0.008), _m("plate"), pos)
	pm.rotation.y = 0.0 if out_z > 0.0 else PI
	Builder._add(n, Builder.box(Vector3(0.05, 0.1, 0.022)), _m("eu"), pos + Vector3(-0.23 * out_z, 0, 0.001 * out_z))
	var tm := Builder._add(n, Builder._plate_text(text), _m("ink"), pos + Vector3(0.025 * out_z, -0.001, 0.012 * out_z))
	tm.rotation.y = 0.0 if out_z > 0.0 else PI


# --- Pkw -----------------------------------------------------------------------------------------------------------

static func car(n: Node3D, form: String, col: Color, tag: int, taxi := false) -> void:
	var S: Dictionary = CARS[form]
	var L: float = S["L"]
	var W: float = S["W"]
	var hw := W / 2.0
	var cl: float = S["clear"]
	var belt: float = S["belt"]
	var roof: float = S["roof"]
	var ws: float = S["ws"]
	var r0: float = S["r0"]
	var r1: float = S["r1"]
	var rw: float = S["rw"]
	var paint := _paint(col)
	var z0 := -L / 2.0
	var z1 := L / 2.0
	# Karosserie: Bug, Haube bis zum Scheibenfuß, Flanke bis zur Heckscheibe, Kofferraum, Heck
	var hood_mid: float = lerpf(float(S["nose"]) + 0.1, float(S["hood"]), 0.5)
	_loft(n, [
		[z0, cl + 0.16, S["nose"], hw - 0.16, hw - 0.3, 0.1],
		[z0 + 0.1, cl + 0.07, float(S["nose"]) + 0.09, hw - 0.04, hw - 0.18, 0.1],
		[z0 + 0.42, cl, hood_mid, hw, hw - 0.12, 0.12],
		[ws, cl, belt, hw, hw - 0.1, 0.12],
		[lerpf(ws, rw, 0.5), cl, belt + 0.01, hw, hw - 0.1, 0.12],
		[rw, cl, S["deck"], hw, hw - 0.1, 0.12],
		[z1 - 0.32, cl, float(S["deck"]) - 0.02, hw - 0.01, hw - 0.12, 0.12],
		[z1 - 0.08, cl + 0.07, float(S["tail"]) + 0.04, hw - 0.05, hw - 0.18, 0.1],
		[z1, cl + 0.16, S["tail"], hw - 0.14, hw - 0.28, 0.1]], paint)
	# Kabine aus Glas: Frontscheibe, Seitenscheiben, Heckscheibe; schmaler nach oben
	var gb := belt - 0.04
	var gw := hw - 0.1
	_loft(n, [
		[ws + 0.02, gb, belt + 0.03, gw, gw - 0.04, 0.02],
		[lerpf(ws, r0, 0.45), gb, lerpf(belt, roof, 0.58), gw, gw - 0.17, 0.05],
		[r0, gb, roof - 0.03, gw - 0.01, gw - 0.27, 0.07],
		[lerpf(r0, r1, 0.5), gb, roof, gw - 0.01, gw - 0.28, 0.07],
		[r1, gb, roof - 0.04, gw - 0.01, gw - 0.27, 0.07],
		[lerpf(r1, rw, 0.55), gb, lerpf(belt, roof, 0.55), gw, gw - 0.16, 0.05],
		[rw - 0.02, gb, float(S["deck"]) + 0.03, gw, gw - 0.05, 0.02]], _m("glass"))
	# Dach (Lack) über dem Glas, Säulen A, B, C (bei Zweitürern keine B-Säule mitten in der Scheibe)
	_loft(n, [[r0 + 0.04, roof - 0.045, roof + 0.012, gw - 0.25, gw - 0.29, 0.03],
		[r1 - 0.04, roof - 0.045, roof + 0.012, gw - 0.25, gw - 0.29, 0.03]], paint)
	var bz := lerpf(r0, r1, 0.42) if int(S["doors"]) == 4 else lerpf(r0, r1, 0.78)
	for s in [-1.0, 1.0]:
		_strut(n, Vector3(s * (gw - 0.01), belt + 0.01, ws + 0.04), Vector3(s * (gw - 0.25), roof - 0.02, r0 + 0.03), 0.07, 0.06, paint)
		_strut(n, Vector3(s * (gw + 0.005), belt - 0.02, bz), Vector3(s * (gw - 0.26), roof - 0.02, bz + 0.04), 0.06, 0.09, _m("trim"))
		_strut(n, Vector3(s * (gw - 0.25), roof - 0.02, r1 - 0.03), Vector3(s * (gw - 0.01), float(S["deck"]) + 0.02, rw - 0.05), 0.08, 0.1, paint)
	# Front: Scheinwerfer, Grill mit Chromleiste, Lufteinlass, Blinker; Heck: Rückleuchten, Schild
	var ny: float = S["nose"]
	for s in [-1.0, 1.0]:
		# Scheinwerfer ragen ein paar Zentimeter aus dem runden Bug (weiter innen steckten sie ganz in der Karosserie)
		var hl := Builder._add(n, Builder.rbox(Vector3(0.42, 0.13, 0.13), 0.035), _m("head"), Vector3(s * (hw - 0.29), ny - 0.07, z0 + 0.03))
		hl.rotation.y = -s * 0.18
		Builder._add(n, Builder.rbox(Vector3(0.1, 0.05, 0.06), 0.015), _m("ind"), Vector3(s * (hw - 0.12), ny - 0.08, z0 + 0.13))
		var tl := Builder._add(n, Builder.rbox(Vector3(0.4, 0.13, 0.1), 0.03), _m("tail"), Vector3(s * (hw - 0.27), float(S["tail"]) - 0.1, z1 - 0.02))
		tl.rotation.y = s * 0.15
	Builder._add(n, Builder.rbox(Vector3(W - 0.98, 0.13, 0.06), 0.03), _m("trim"), Vector3(0, ny - 0.1, z0 + 0.02))
	Builder._add(n, Builder.box(Vector3(W - 1.02, 0.018, 0.07)), _m("chrome"), Vector3(0, ny - 0.04, z0 + 0.02))
	Builder._add(n, Builder.rbox(Vector3(W * 0.5, 0.07, 0.05), 0.02), _m("trim"), Vector3(0, cl + 0.24, z0 + 0.14))
	var plate: String = PLATES[tag % PLATES.size()]
	_plate(n, Vector3(0, cl + 0.33, z0 + 0.05), -1.0, plate)
	_plate(n, Vector3(0, float(S["tail"]) - 0.3, z1 + 0.005), 1.0, plate)
	# Flanke: Türfugen, Griffe, Schweller, Außenspiegel
	var dz := [ws + 0.12, bz, lerpf(r1, rw, 0.3)] if int(S["doors"]) == 4 else [ws + 0.12, bz]
	for s in [-1.0, 1.0]:
		for z in dz:
			Builder._add(n, Builder.box(Vector3(0.006, belt - cl - 0.16, 0.012)), _m("trim"), Vector3(s * (hw + 0.002), (belt + cl) / 2.0 + 0.04, z))
		for k in dz.size() - 1:
			Builder._add(n, Builder.rbox(Vector3(0.03, 0.03, 0.15), 0.012), _m("chrome"), Vector3(s * (hw + 0.012), belt - 0.13, float(dz[k + 1]) - 0.2))
		Builder._add(n, Builder.box(Vector3(0.03, 0.1, float(S["wb"]) - 2.0 * float(S["r"]) - 0.2)), _m("trim"), Vector3(s * (hw + 0.006), cl + 0.06, 0.0))
		Builder._add(n, Builder.rbox(Vector3(0.2, 0.12, 0.09), 0.035), paint, Vector3(s * (hw + 0.08), belt + 0.1, ws + 0.16))
		Builder._add(n, Builder.box(Vector3(0.16, 0.02, 0.03)), _m("trim"), Vector3(s * (hw + 0.01), belt + 0.06, ws + 0.16))
	# Räder: leicht über die Flanke, mit dunklem Radlauf dahinter
	var r: float = S["r"]
	var wbz: float = S["wb"] / 2.0
	var off := -0.06 if form == "kleinwagen" else -0.02
	for s in [-1.0, 1.0]:
		for z in [-wbz + off, wbz + off]:
			_wheel(n, s * (hw - 0.09), r, z, r, 0.22, s, hw)
	if taxi:
		var tz := lerpf(r0, r1, 0.5)
		Builder._add(n, Builder.rbox(Vector3(0.62, 0.17, 0.24), 0.04), _m("sign"), Vector3(0, roof + 0.1, tz))
		Builder._add(n, Builder.box(Vector3(0.66, 0.035, 0.28)), _m("trim"), Vector3(0, roof + 0.02, tz))
		for sz in [-1.0, 1.0]:
			var l := Label3D.new()
			l.text = "TAXI"
			l.font_size = 64
			l.pixel_size = 0.0028
			l.modulate = Color(0.05, 0.05, 0.05)
			l.shaded = true
			l.double_sided = false
			l.position = Vector3(0, roof + 0.1, tz + sz * 0.125)
			l.rotation.y = 0.0 if sz > 0.0 else PI
			n.add_child(l)


# --- Transporter ---------------------------------------------------------------------------------------------------

static func van(n: Node3D, col: Color, tag: int) -> void:
	var L := 5.6
	var W := 2.02
	var hw := W / 2.0
	var cl := 0.24
	var belt := 1.18
	var roof := 2.48
	var paint := _paint(col)
	var z0 := -L / 2.0
	var z1 := L / 2.0
	var ws := z0 + 0.72  # Scheibenfuß
	var wt := z0 + 1.42  # Scheibe oben
	# Unterteil bis zur Gürtellinie, kurze schräge Haube
	_loft(n, [
		[z0, cl + 0.18, 0.78, hw - 0.14, hw - 0.26, 0.1],
		[z0 + 0.12, cl + 0.08, 0.9, hw - 0.04, hw - 0.14, 0.1],
		[ws, cl, belt, hw, hw - 0.06, 0.1],
		[z1 - 0.1, cl, belt, hw, hw - 0.04, 0.08],
		[z1, cl + 0.08, belt - 0.04, hw - 0.04, hw - 0.08, 0.06]], paint)
	# Kabine (Glas) vorn, Kastenaufbau dahinter bis unters Hochdach
	_loft(n, [
		[ws + 0.02, belt - 0.04, belt + 0.03, hw - 0.06, hw - 0.08, 0.02],
		[lerpf(ws, wt, 0.5), belt - 0.04, lerpf(belt, roof, 0.55), hw - 0.06, hw - 0.12, 0.04],
		[wt, belt - 0.04, roof - 0.04, hw - 0.06, hw - 0.14, 0.05],
		[wt + 0.62, belt - 0.04, roof - 0.04, hw - 0.06, hw - 0.14, 0.05]], _m("glass"))
	_loft(n, [
		[wt + 0.06, belt - 0.03, roof + 0.02, hw - 0.02, hw - 0.1, 0.1],
		[z1, belt - 0.03, roof + 0.02, hw - 0.02, hw - 0.1, 0.1]], paint)
	_loft(n, [[wt - 0.02, roof - 0.05, roof + 0.01, hw - 0.12, hw - 0.16, 0.03],
		[wt + 0.1, roof - 0.05, roof + 0.01, hw - 0.12, hw - 0.16, 0.03]], paint)
	for s in [-1.0, 1.0]:
		_strut(n, Vector3(s * (hw - 0.05), belt, ws + 0.04), Vector3(s * (hw - 0.13), roof - 0.03, wt + 0.02), 0.07, 0.07, paint)
		# Aufschrift (Handwerker) an beiden Seiten des Kastens
		var l := Label3D.new()
		l.text = HANDWERK[tag % HANDWERK.size()]
		l.font_size = 64
		l.pixel_size = 0.0065
		l.modulate = Color(0.08, 0.1, 0.18) if col.get_luminance() > 0.5 else Color(0.95, 0.95, 0.9)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(s * (hw - 0.015), 1.75, 0.75)
		l.rotation.y = s * PI / 2.0
		n.add_child(l)
		# Fugen: Fahrertür, Schiebetür (rechts), Griffe
		for z in [ws + 0.1, wt + 0.58]:
			Builder._add(n, Builder.box(Vector3(0.006, belt - cl - 0.12, 0.012)), _m("trim"), Vector3(s * (hw + 0.002), (belt + cl) / 2.0 + 0.04, z))
		if s > 0.0:
			for z in [wt + 0.62, wt + 1.95]:
				Builder._add(n, Builder.box(Vector3(0.006, roof - cl - 0.3, 0.012)), _m("trim"), Vector3(s * (hw - 0.012), (roof + cl) / 2.0, z))
			Builder._add(n, Builder.box(Vector3(0.02, 0.04, 1.4)), _m("trim"), Vector3(s * (hw - 0.01), roof - 0.18, wt + 1.3))
		Builder._add(n, Builder.rbox(Vector3(0.12, 0.26, 0.1), 0.03), _m("trim"), Vector3(s * (hw + 0.1), belt + 0.2, ws + 0.2))
	# Front und Heck
	for s in [-1.0, 1.0]:
		Builder._add(n, Builder.rbox(Vector3(0.34, 0.16, 0.08), 0.03), _m("head"), Vector3(s * (hw - 0.3), 0.74, z0 + 0.07))
		Builder._add(n, Builder.rbox(Vector3(0.14, 0.42, 0.06), 0.03), _m("tail"), Vector3(s * (hw - 0.1), 1.0, z1 + 0.005))
		Builder._add(n, Builder.box(Vector3(0.006, roof - belt - 0.2, 0.3)), _m("glass"), Vector3(s * 0.48, (roof + belt) / 2.0 + 0.1, z1 + 0.004))
	Builder._add(n, Builder.rbox(Vector3(W - 0.9, 0.24, 0.06), 0.04), _m("trim"), Vector3(0, 0.6, z0 + 0.03))
	Builder._add(n, Builder.rbox(Vector3(W - 0.1, 0.18, 0.12), 0.05), _m("trim"), Vector3(0, cl + 0.12, z0 + 0.06))
	Builder._add(n, Builder.rbox(Vector3(W - 0.1, 0.18, 0.12), 0.05), _m("trim"), Vector3(0, cl + 0.12, z1 - 0.04))
	Builder._add(n, Builder.box(Vector3(0.012, roof - cl - 0.25, 0.01)), _m("trim"), Vector3(0, (roof + cl) / 2.0, z1 + 0.006))
	var plate: String = PLATES[(tag + 3) % PLATES.size()]
	_plate(n, Vector3(0, cl + 0.35, z0 + 0.13), -1.0, plate)
	_plate(n, Vector3(0, 0.55, z1 + 0.008), 1.0, plate)
	for s in [-1.0, 1.0]:
		for z in [z0 + 0.95, z1 - 1.1]:
			_wheel(n, s * (hw - 0.12), 0.35, z, 0.35, 0.24, s, hw)


# --- Linienbus -----------------------------------------------------------------------------------------------------

static func bus(n: Node3D, col: Color, tag: int) -> void:
	var L := 11.6
	var W := 2.55
	var hw := W / 2.0
	var H := 3.1
	var paint := _paint(col)
	var z0 := -L / 2.0
	var z1 := L / 2.0
	_loft(n, [
		[z0, 0.32, H - 0.12, hw - 0.08, hw - 0.18, 0.18],
		[z0 + 0.2, 0.28, H, hw, hw - 0.1, 0.2],
		[z1 - 0.15, 0.28, H, hw, hw - 0.1, 0.2],
		[z1, 0.32, H - 0.08, hw - 0.06, hw - 0.16, 0.18]], paint)
	# Fensterband mit Säulen, Zierstreifen darunter, Frontscheibe mit Zielanzeige, Heckscheibe
	var stripe := Builder.mat(Color(0.75, 0.08, 0.08) if col.get_luminance() > 0.6 else Color(0.08, 0.2, 0.55), 0.1, 0.5)
	for s in [-1.0, 1.0]:
		Builder._add(n, Builder.box(Vector3(0.02, 1.2, L - 1.6)), _m("glass"), Vector3(s * (hw + 0.004), 2.05, 0.35))
		Builder._add(n, Builder.box(Vector3(0.022, 0.12, L - 0.8)), stripe, Vector3(s * (hw + 0.006), 1.3, 0.0))
		var z := z0 + 1.2
		while z < z1 - 0.6:
			Builder._add(n, Builder.box(Vector3(0.03, 1.22, 0.1)), paint, Vector3(s * (hw + 0.008), 2.05, z))
			z += 1.45
	# Türen rechts (vorn, Mitte, hinten): Glas bis unten, Mittelfuge
	for dz in [z0 + 0.75, -0.6, z1 - 2.6]:
		Builder._add(n, Builder.box(Vector3(0.024, 2.3, 1.2)), _m("glass"), Vector3(hw + 0.01, 1.5, dz))
		Builder._add(n, Builder.box(Vector3(0.03, 2.3, 0.03)), _m("trim"), Vector3(hw + 0.02, 1.5, dz))
	Builder._add(n, Builder.box(Vector3(W - 0.3, 1.55, 0.03)), _m("glass"), Vector3(0, 1.85, z0 - 0.002))
	Builder._add(n, Builder.box(Vector3(W - 0.5, 0.28, 0.04)), _m("led"), Vector3(0, 2.82, z0 - 0.005))
	var ziel := Label3D.new()
	ziel.text = LINIEN[tag % LINIEN.size()]
	ziel.font_size = 64
	ziel.pixel_size = 0.0045
	ziel.modulate = Color(1.0, 0.6, 0.1)
	ziel.shaded = false
	ziel.double_sided = false
	ziel.position = Vector3(0, 2.82, z0 - 0.03)
	ziel.rotation.y = PI
	n.add_child(ziel)
	Builder._add(n, Builder.box(Vector3(W - 0.5, 0.9, 0.03)), _m("glass"), Vector3(0, 2.2, z1 + 0.002))
	for s in [-1.0, 1.0]:
		Builder._add(n, Builder.rbox(Vector3(0.3, 0.14, 0.06), 0.03), _m("head"), Vector3(s * (hw - 0.35), 0.62, z0 - 0.01))
		Builder._add(n, Builder.rbox(Vector3(0.16, 0.5, 0.05), 0.03), _m("tail"), Vector3(s * (hw - 0.18), 0.9, z1 + 0.01))
		# Spiegel an Bügeln vorn
		_strut(n, Vector3(s * (hw - 0.05), 2.5, z0 + 0.15), Vector3(s * (hw + 0.28), 2.55, z0 - 0.25), 0.04, 0.04, _m("trim"))
		Builder._add(n, Builder.rbox(Vector3(0.1, 0.42, 0.2), 0.03), _m("trim"), Vector3(s * (hw + 0.3), 2.35, z0 - 0.28))
	Builder._add(n, Builder.rbox(Vector3(W - 0.2, 0.3, 0.1), 0.05), _m("trim"), Vector3(0, 0.45, z0 - 0.01))
	_plate(n, Vector3(0, 0.62, z1 + 0.01), 1.0, PLATES[(tag + 5) % PLATES.size()])
	for s in [-1.0, 1.0]:
		for z in [z0 + 2.6, z1 - 3.0]:
			_wheel(n, s * (hw - 0.2), 0.5, z, 0.5, 0.3, s, hw)


# --- Sattelzug -----------------------------------------------------------------------------------------------------

static func lkw(n: Node3D, col: Color, spedition: String) -> void:
	var paint := _paint(col)
	var white := _m("white")
	var dark := _m("trim")
	# Fahrerhaus (vorn bei z = -8,25), Fahrgestell, Auflieger
	var cz0 := -8.25
	_loft(n, [
		[cz0, 0.95, 3.3, 1.2, 1.1, 0.16],
		[cz0 + 0.25, 0.9, 3.55, 1.25, 1.15, 0.2],
		[cz0 + 2.3, 0.9, 3.55, 1.25, 1.15, 0.2]], paint)
	Builder._add(n, Builder.rtapered_box(Vector2(2.4, 1.6), Vector2(2.2, 1.2), 0.75, 0.15, 0.12), paint, Vector3(0, 3.55, cz0 + 1.45))
	Builder._add(n, Builder.box(Vector3(2.25, 1.0, 0.04)), _m("glass"), Vector3(0, 2.75, cz0 - 0.004))
	Builder._add(n, Builder.box(Vector3(2.3, 0.08, 0.32)), dark, Vector3(0, 3.32, cz0 - 0.1))
	for s in [-1.0, 1.0]:
		Builder._add(n, Builder.box(Vector3(0.03, 0.75, 0.9)), _m("glass"), Vector3(s * 1.255, 2.75, cz0 + 0.65))
		Builder._add(n, Builder.box(Vector3(0.012, 1.7, 0.012)), dark, Vector3(s * 1.258, 2.0, cz0 + 1.2))
		_strut(n, Vector3(s * 1.2, 2.95, cz0 + 0.2), Vector3(s * 1.55, 3.0, cz0 - 0.15), 0.05, 0.05, dark)
		Builder._add(n, Builder.rbox(Vector3(0.1, 0.55, 0.24), 0.03), dark, Vector3(s * 1.58, 2.7, cz0 - 0.18))
		Builder._add(n, Builder.rbox(Vector3(0.38, 0.18, 0.06), 0.03), _m("head"), Vector3(s * 0.85, 1.15, cz0 - 0.02))
		var tank := CylinderMesh.new()
		tank.top_radius = 0.3
		tank.bottom_radius = 0.3
		tank.height = 1.2
		tank.radial_segments = 12
		tank.rings = 1
		Builder._add(n, tank, _m("chrome"), Vector3(s * 1.0, 0.75, cz0 + 3.2)).rotation_degrees.x = 90.0
	# Grill mit Querstreben, Stoßfänger
	Builder._add(n, Builder.box(Vector3(1.3, 0.8, 0.04)), dark, Vector3(0, 1.75, cz0 - 0.01))
	for k in 5:
		Builder._add(n, Builder.box(Vector3(1.32, 0.04, 0.03)), _m("chrome"), Vector3(0, 1.45 + k * 0.15, cz0 - 0.03))
	Builder._add(n, Builder.rbox(Vector3(2.45, 0.35, 0.25), 0.06), dark, Vector3(0, 0.75, cz0 + 0.05))
	Builder._add(n, Builder.box(Vector3(1.0, 0.35, 5.2)), dark, Vector3(0, 0.7, cz0 + 4.8))
	# Auflieger: weißer Koffer mit Spedition, Hecktüren, Unterfahrschutz
	Builder._add(n, Builder.rbox(Vector3(2.55, 3.0, 13.4), 0.06), white, Vector3(0, 2.4, 1.5))
	Builder._add(n, Builder.box(Vector3(2.5, 0.5, 13.0)), dark, Vector3(0, 0.65, 1.5))
	Builder._add(n, Builder.box(Vector3(0.015, 2.85, 0.01)), dark, Vector3(0, 2.4, 8.205))
	for s in [-1.0, 1.0]:
		for hy in [1.4, 2.4, 3.4]:
			Builder._add(n, Builder.box(Vector3(0.12, 0.06, 0.02)), _m("grey"), Vector3(s * 1.15, hy, 8.21))
		Builder._add(n, Builder.box(Vector3(0.02, 0.06, 6.0)), _m("grey"), Vector3(s * 1.2, 0.55, 2.0))
		Builder._add(n, Builder.box(Vector3(0.02, 0.06, 6.0)), _m("grey"), Vector3(s * 1.2, 0.85, 2.0))
		Builder._add(n, Builder.rbox(Vector3(0.36, 0.16, 0.05), 0.03), _m("tail"), Vector3(s * 1.0, 0.95, 8.22))
		var l := Label3D.new()
		l.text = spedition
		l.font_size = 64
		l.pixel_size = 0.016
		l.modulate = col if col.get_luminance() < 0.8 else Color(0.1, 0.2, 0.5)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(s * 1.29, 2.6, 1.5)
		l.rotation.y = s * PI / 2.0
		n.add_child(l)
		for wz in [cz0 + 0.65, cz0 + 3.65]:
			_wheel(n, s * 1.05, 0.5, wz, 0.5, 0.32, s, 1.25)
		for wz in [4.4, 5.8, 7.2]:
			_wheel(n, s * 1.05, 0.5, wz, 0.5, 0.32, s, 1.27)
	Builder._add(n, Builder.box(Vector3(2.3, 0.12, 0.12)), _m("grey"), Vector3(0, 0.55, 8.15))
	_plate(n, Vector3(0, 0.75, 8.23), 1.0, PLATES[spedition.length() % PLATES.size()])
