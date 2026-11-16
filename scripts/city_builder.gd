extends RefCounted
## Wahrzeichen der Städte-Strecken, aus einfachen Körpern zusammengesetzt und je Material zu einem Mesh gebacken.
## Nachts angestrahlt: Steinflächen leuchten schwach selbst (spart Scheinwerfer, die im Browser teuer sind).
## Lokale Koordinaten: -Z zeigt zur Straße, X läuft parallel zur Straße, y = 0 ist der Boden.

const Builder := preload("res://scripts/car_builder.gd")
const People := preload("res://scripts/people.gd")

## Grundfläche: halbe Tiefe (quer zur Straße) und halbe Länge (entlang). hill: steht auf einem Hügel (Sockelmauer).
const INFO := {
	"aachen_dom": {"hd": 22.0, "hl": 46.0},
	"aachen_rathaus": {"hd": 16.0, "hl": 32.0},
	"elisenbrunnen": {"hd": 10.0, "hl": 30.0},
	"super_c": {"hd": 13.0, "hl": 28.0},
	"theater": {"hd": 18.0, "hl": 18.0},
	"residenz": {"hd": 48.0, "hl": 86.0},
	"festung": {"hd": 60.0, "hl": 110.0, "hill": true},
	"mainbruecke": {"hd": 5.0, "hl": 10.0},
	"kiliansdom": {"hd": 16.0, "hl": 50.0},
	"kaeppele": {"hd": 16.0, "hl": 20.0, "hill": true},
	"marienkapelle": {"hd": 10.0, "hl": 26.0},
	"alter_kranen": {"hd": 6.0, "hl": 8.0},
	"regentenbau": {"hd": 17.0, "hl": 56.0},
	"arkadenbau": {"hd": 7.0, "hl": 100.0},
	"spielbank": {"hd": 12.0, "hl": 22.0},
	"gradierbau": {"hd": 6.0, "hl": 62.0},
	"altes_rathaus": {"hd": 8.0, "hl": 12.0},
	"tuermersturm": {"hd": 14.0, "hl": 22.0},
	"tbb_rathaus": {"hd": 9.0, "hl": 14.0},
	"st_martin": {"hd": 11.0, "hl": 24.0},
	"hammelburg_rathaus": {"hd": 16.0, "hl": 15.0},
	"saaleck": {"hd": 22.0, "hl": 30.0, "hill": true},
	"oberbaumbruecke": {"hd": 4.0, "hl": 30.0},
	"fernsehturm": {"hd": 20.0, "hl": 20.0},
	"nkz": {"hd": 12.0, "hl": 55.0},
	# entworfene Städte (track_design.gd, seit 2.36)
	"koelner_dom": {"hd": 26.0, "hl": 52.0},
	"hohenzollernbruecke": {"hd": 8.0, "hl": 12.0},
	"roland": {"hd": 22.0, "hl": 30.0},
	"stuttgart_turm": {"hd": 12.0, "hl": 12.0},
	"elbphilharmonie": {"hd": 24.0, "hl": 56.0},
	"messeturm": {"hd": 22.0, "hl": 22.0},
	"roemer": {"hd": 12.0, "hl": 30.0},
	"siegestor": {"hd": 6.0, "hl": 20.0},
	"friedensengel": {"hd": 16.0, "hl": 16.0},
	"frauenkirche": {"hd": 22.0, "hl": 46.0},
	"landungsbruecken": {"hd": 14.0, "hl": 60.0},
	"michel": {"hd": 16.0, "hl": 24.0},
	"kaiserburg": {"hd": 40.0, "hl": 60.0, "hill": true},
	"stadttor": {"hd": 9.0, "hl": 34.0},
	"hochofen": {"hd": 26.0, "hl": 30.0},
	"foerderturm": {"hd": 14.0, "hl": 14.0},
	"heidelberger_schloss": {"hd": 36.0, "hl": 60.0, "hill": true},
	"brueckentor": {"hd": 6.0, "hl": 20.0},
	"backsteintor": {"hd": 7.0, "hl": 22.0},
	"marienkirche": {"hd": 18.0, "hl": 40.0},
	"leuchtturm": {"hd": 14.0, "hl": 30.0},
}

## Weithin sichtbar (angestrahlt, vom Nachtnebel ausgenommen): Burgen auf den Hügeln und hohe Kirchtürme
const FAR := ["festung", "kaeppele", "saaleck", "aachen_dom", "kiliansdom", "marienkapelle", "st_martin", "tuermersturm", "fernsehturm",
	"koelner_dom", "stuttgart_turm", "elbphilharmonie", "messeturm", "frauenkirche", "michel", "kaiserburg", "hochofen",
	"heidelberger_schloss", "marienkirche", "leuchtturm"]

static var _mats := {}
static var _far_mats := {}
static var _far_night := true  # Fernwirkung ohne Nebel gerade an (set_far_daytime)

var n: Node3D
var g := {}


static func m(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var lit := func(c: Color, e: float) -> StandardMaterial3D: return Builder.mat(c, 0.0, 0.85, c, e)
	var res: StandardMaterial3D
	match key:
		"sand": res = lit.call(Color(0.6, 0.52, 0.38), 0.32)
		"redsand": res = lit.call(Color(0.52, 0.26, 0.18), 0.3)
		"redsand_dk": res = Builder.mat(Color(0.3, 0.14, 0.1), 0.0, 0.9)
		"grey": res = lit.call(Color(0.52, 0.5, 0.46), 0.3)
		"white": res = lit.call(Color(0.46, 0.44, 0.4), 0.12)
		"ochre": res = lit.call(Color(0.66, 0.5, 0.28), 0.22)
		"cream": res = lit.call(Color(0.64, 0.57, 0.42), 0.18)
		"dimstone": res = Builder.mat(Color(0.3, 0.28, 0.25), 0.0, 0.9)
		"slate": res = Builder.mat(Color(0.12, 0.13, 0.16), 0.3, 0.6)
		"tile": res = Builder.mat(Color(0.36, 0.13, 0.08), 0.0, 0.8)
		"copper": res = Builder.mat(Color(0.25, 0.48, 0.4), 0.4, 0.5, Color(0.25, 0.48, 0.4), 0.15)
		"gold": res = Builder.mat(Color(1.0, 0.8, 0.3), 0.8, 0.3, Color(1.0, 0.75, 0.3), 2.5)
		"win": res = Builder.mat(Color(1.0, 0.75, 0.4), 0.0, 0.4, Color(1.0, 0.7, 0.35), 1.6)
		"win_cool": res = Builder.mat(Color(0.75, 0.88, 1.0), 0.0, 0.3, Color(0.7, 0.85, 1.0), 1.4)
		"glass": res = Builder.mat(Color(0.3, 0.45, 1.0), 0.0, 0.3, Color(0.35, 0.5, 1.0), 1.8)
		"glass_gold": res = Builder.mat(Color(1.0, 0.7, 0.3), 0.0, 0.3, Color(1.0, 0.65, 0.25), 1.8)
		"dark": res = Builder.mat(Color(0.03, 0.03, 0.035), 0.0, 0.9)
		"wood": res = Builder.mat(Color(0.2, 0.12, 0.07), 0.0, 0.85)
		"brush": res = Builder.mat(Color(0.09, 0.07, 0.05), 0.0, 1.0)
		"glassdark": res = Builder.mat(Color(0.05, 0.07, 0.1), 0.6, 0.1)
		"neon_red": res = Builder.mat(Color(1.0, 0.1, 0.15), 0.0, 0.4, Color(1.0, 0.1, 0.15), 4.0)
		"water": res = Builder.mat(Color(0.02, 0.05, 0.09), 0.2, 0.05, Color(0.1, 0.25, 0.4), 0.4)
		"lamp": res = Builder.mat(Color(1.0, 0.85, 0.6), 0.0, 0.4, Color(1.0, 0.8, 0.5), 3.5)
		"iron": res = Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.5)
		"brick": res = lit.call(Color(0.5, 0.16, 0.1), 0.22)
		"concrete": res = lit.call(Color(0.5, 0.5, 0.5), 0.18)
		"blink": res = Builder.mat(Color(1.0, 0.1, 0.05), 0.0, 0.4, Color(1.0, 0.1, 0.05), 4.0)
		_: res = Builder.mat(Color(1, 0, 1))
	_mats[key] = res
	return res


func _init(node: Node3D) -> void:
	n = node


func put(mesh: Mesh, mk: String, xf: Transform3D) -> void:
	var mt := m(mk)
	if not g.has(mt):
		g[mt] = []
	g[mt].append([mesh, xf])


func box(size: Vector3, pos: Vector3, mk: String, rot := 0.0) -> void:
	put(Builder.box(size), mk, Transform3D(Basis(Vector3.UP, rot), pos))


## Zylinder/Kegel, pos = Mitte der Grundfläche
func cyl(r0: float, r1: float, h: float, pos: Vector3, mk: String, segs := 12, rot := 0.0) -> void:
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	c.cap_top = r1 > 0.0
	put(c, mk, Transform3D(Basis(Vector3.UP, rot), pos + Vector3(0, h / 2.0, 0)))


## Spitzhelm mit 4 Flächen, Kanten diagonal
func spire(r: float, h: float, pos: Vector3, mk: String, segs := 4) -> void:
	cyl(r, 0.0, h, pos, mk, segs, PI / 4.0 if segs == 4 else 0.0)


## Satteldach: First entlang X (len), quer dazu depth; pos = Mitte der Traufe
func roof(len: float, depth: float, h: float, pos: Vector3, mk: String, rot := 0.0) -> void:
	var p := PrismMesh.new()
	p.size = Vector3(depth, h, len)
	put(p, mk, Transform3D(Basis(Vector3.UP, rot + PI / 2.0), pos + Vector3(0, h / 2.0, 0)))


func sphere(r: float, pos: Vector3, mk: String, squash := 1.0) -> void:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	put(s, mk, Transform3D(Basis.from_scale(Vector3(1, squash, 1)), pos))


## Zwiebelhaube (Barock): Kugel, Einschnürung, Laterne, Spitze
func onion(r: float, pos: Vector3, mk: String) -> void:
	sphere(r, pos + Vector3(0, r * 0.8, 0), mk, 0.85)
	cyl(r * 0.35, r * 0.25, r * 0.7, pos + Vector3(0, r * 1.5, 0), mk, 8)
	sphere(r * 0.45, pos + Vector3(0, r * 2.4, 0), mk, 1.1)
	spire(r * 0.2, r * 1.4, pos + Vector3(0, r * 2.8, 0), mk, 6)
	box(Vector3(0.12, 1.2, 0.12), pos + Vector3(0, r * 4.4, 0), "gold")


## Fensterraster auf der Straßenseite einer Fassade (Ebene z, Blick nach -Z)
func windows(x0: float, x1: float, dx: float, y0: float, rows: int, dy: float, z: float, size: Vector2, mk := "win", rot := 0.0) -> void:
	var x := x0
	var b := Basis(Vector3.UP, rot)
	while x <= x1 + 0.01:
		for r in rows:
			put(Builder.box(Vector3(size.x, size.y, 0.12)), mk, Transform3D(b, b * Vector3(x, y0 + r * dy + size.y / 2.0, z - 0.04)))
		x += dx


func label(text: String, pos: Vector3, size: int, col: Color, glow := 2.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.02
	l.modulate = Color(col.r * glow, col.g * glow, col.b * glow)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = 180.0
	n.add_child(l)


func light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	n.add_child(l)


func bake() -> void:
	for mt in g:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in g[mt]:
			st.append_from(p[0], 0, p[1])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mt
		n.add_child(mi)
	g = {}


## Baut ein Wahrzeichen in den Knoten n (City.new(n).make(...)). extra: Brückenlänge usw.
func make(kind: String, extra := {}) -> void:
	match kind:
		"aachen_dom": _aachen_dom()
		"aachen_rathaus": _aachen_rathaus()
		"elisenbrunnen": _elisenbrunnen()
		"super_c": _super_c()
		"theater": _theater()
		"residenz": _residenz()
		"festung": _festung()
		"mainbruecke": _mainbruecke(extra.get("len", 120.0))
		"kiliansdom": _kiliansdom()
		"kaeppele": _kaeppele()
		"marienkapelle": _marienkapelle()
		"alter_kranen": _alter_kranen()
		"regentenbau": _regentenbau()
		"arkadenbau": _arkadenbau()
		"spielbank": _spielbank()
		"gradierbau": _gradierbau()
		"altes_rathaus": _altes_rathaus()
		"tuermersturm": _tuermersturm()
		"tbb_rathaus": _tbb_rathaus()
		"st_martin": _st_martin()
		"hammelburg_rathaus": _hammelburg_rathaus()
		"saaleck": _saaleck()
		"oberbaumbruecke": _oberbaumbruecke(extra.get("hw", 14.0))
		"fernsehturm": _fernsehturm()
		"nkz": _nkz()
		"koelner_dom": _koelner_dom()
		"hohenzollernbruecke": _hohenzollernbruecke(extra.get("len", 140.0))
		"roland": _roland()
		"stuttgart_turm": _stuttgart_turm()
		"elbphilharmonie": _elbphilharmonie()
		"messeturm": _messeturm()
		"roemer": _roemer()
		"siegestor": _tor(extra.get("hw", 16.0), "sand", 21.0, true, extra.get("name", ""))
		"friedensengel": _friedensengel()
		"frauenkirche": _frauenkirche()
		"landungsbruecken": _landungsbruecken()
		"michel": _michel()
		"kaiserburg": _kaiserburg()
		"stadttor": _stadttor(extra.get("hw", 16.0), extra.get("name", ""))
		"hochofen": _hochofen()
		"foerderturm": _foerderturm()
		"heidelberger_schloss": _heidelberger_schloss()
		"brueckentor": _brueckentor(extra.get("hw", 16.0), extra.get("name", ""))
		"backsteintor": _backsteintor(extra.get("hw", 16.0), extra.get("name", ""))
		"marienkirche": _marienkirche()
		"leuchtturm": _leuchtturm()
	var far := kind in FAR
	if far:
		for mt in g.keys():
			if not _far_mats.has(mt):
				var fm: StandardMaterial3D = mt.duplicate()
				fm.disable_fog = _far_night
				if fm.emission_enabled and fm.emission_energy_multiplier < 1.0:
					fm.emission_energy_multiplier = maxf(fm.emission_energy_multiplier * 2.2, 0.55)
				_far_mats[mt] = fm
			g[_far_mats[mt]] = g[mt]
			g.erase(mt)
	if INFO.get(kind, {}).get("hill", false):
		# Sockel- und Stützmauern bis hinunter in den Hang; im Nebel wie alles andere (seit 2.33: vorher ohne Nebel,
		# die Burg schwebte tagsüber auf einer hellen Platte über dem Dunst)
		var info: Dictionary = INFO[kind]
		box(Vector3(info["hl"] * 2.0, 16.0, info["hd"] * 2.0), Vector3(0, -8.05, 0), "dimstone")
	bake()


## Nur nachts (angestrahlt) vom Nebel ausgenommen (seit 2.33): tagsüber schwebten Burgen und Türme klar über dem Dunst,
## während Hang und Häuser darunter im Nebel verschwanden. day: 0 Nacht, 1 Tag (Track.set_daytime).
static func set_far_daytime(day: float) -> void:
	var night := day < 0.35
	if night == _far_night:
		return
	_far_night = night
	for fm in _far_mats.values():
		(fm as StandardMaterial3D).disable_fog = night


# --- Aachen -------------------------------------------------------------------

## Dom: karolingisches Oktogon mit Faltkuppel, gotische Chorhalle ("Glashaus"), Westturm
func _aachen_dom() -> void:
	cyl(15.0, 15.0, 15.0, Vector3.ZERO, "grey", 16)  # Sechzehneck (Umgang)
	cyl(10.0, 10.0, 13.0, Vector3(0, 15, 0), "grey", 8)  # Oktogon
	cyl(11.2, 2.4, 10.0, Vector3(0, 28, 0), "slate", 8, PI / 8.0)  # Faltkuppel
	cyl(1.8, 1.8, 3.5, Vector3(0, 38, 0), "grey", 8)
	spire(1.9, 4.5, Vector3(0, 41.5, 0), "slate", 8)
	box(Vector3(0.25, 2.2, 0.25), Vector3(0, 47, 0), "gold")
	box(Vector3(1.2, 0.25, 0.25), Vector3(0, 47.4, 0), "gold")
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var p := Vector3(sin(a), 0, cos(a)) * 9.95
		if p.z < 0.0:
			put(Builder.box(Vector3(2.0, 5.5, 0.15)), "glass_gold", Transform3D(Basis(Vector3.UP, a), p + Vector3(0, 20, 0)))
	# Westturm (neugotischer Helm, bis 74 m)
	box(Vector3(11, 50, 11), Vector3(-25, 25, 0), "grey")
	box(Vector3(12, 1.2, 12), Vector3(-25, 50, 0), "grey")
	spire(7.0, 24.0, Vector3(-25, 50.5, 0), "slate")
	box(Vector3(0.3, 3.0, 0.3), Vector3(-25, 76, 0), "gold")
	windows(-27.0, -23.0, 4.0, 22.0, 3, 8.0, -5.5, Vector2(1.2, 4.5), "glass_gold")
	# Chorhalle: fast nur Glas zwischen Strebepfeilern, steiles Dach
	box(Vector3(30, 32, 15), Vector3(29, 16, 0), "grey")
	roof(31.0, 15.6, 15.0, Vector3(29, 32, 0), "slate")
	for i in 6:
		var x := 16.5 + i * 5.0
		put(Builder.box(Vector3(3.2, 22.0, 0.15)), "glass", Transform3D(Basis.IDENTITY, Vector3(x, 17, -7.6)))
		box(Vector3(1.3, 30.0, 2.4), Vector3(x + 2.5, 15, -7.8), "grey")
		box(Vector3(0.5, 4.0, 0.5), Vector3(x + 2.5, 32, -8.2), "grey")
	# Kapellen
	box(Vector3(9, 11, 9), Vector3(10, 5.5, -13), "grey")
	cyl(4.5, 1.5, 4.0, Vector3(10, 11, -13), "slate", 8)
	box(Vector3(10, 9, 8), Vector3(-13, 4.5, -12), "grey")
	roof(10.0, 8.4, 4.5, Vector3(-13, 9, -12), "slate")


## Rathaus: gotischer Saalbau mit Granusturm und Marktturm, Kaiserfiguren, Karlsbrunnen davor
func _aachen_rathaus() -> void:
	box(Vector3(46, 17, 16), Vector3(0, 8.5, 0), "grey")
	roof(46.5, 16.6, 13.0, Vector3(0, 17, 0), "slate")
	windows(-19.0, 19.0, 4.2, 2.5, 2, 7.0, -8.0, Vector2(1.6, 4.2))
	for i in 10:
		box(Vector3(0.9, 2.0, 0.6), Vector3(-18.0 + i * 4.0, 12.6, -8.3), "sand")  # Kaiserfiguren
	for s in [-1.0, 1.0]:
		var x: float = s * 26.0
		box(Vector3(10, 28, 10), Vector3(x, 14, 0), "grey")
		windows(x - 2.0, x + 2.0, 4.0, 18.0, 2, 4.5, -5.0, Vector2(1.0, 2.6))
		cyl(5.6, 4.6, 3.0, Vector3(x, 28, 0), "slate", 8)
		onion(3.6, Vector3(x, 31, 0), "slate")
	for i in 4:
		box(Vector3(1.2, 2.2, 1.0), Vector3(-12.0 + i * 8.0, 18.2, -6.0), "slate")  # Gauben
	# Karlsbrunnen
	cyl(4.0, 4.2, 0.9, Vector3(0, 0, -16), "grey", 12)
	cyl(3.5, 3.5, 0.2, Vector3(0, 0.75, -16), "water", 12)
	cyl(0.5, 0.4, 3.5, Vector3(0, 0.9, -16), "grey", 8)
	box(Vector3(0.8, 1.8, 0.6), Vector3(0, 5.3, -16), "gold")


## Elisenbrunnen: dorischer Rundtempel mit zwei Säulenhallen
func _elisenbrunnen() -> void:
	cyl(7.0, 7.0, 7.0, Vector3(0, 0, 2), "white", 16)
	cyl(8.6, 8.6, 1.2, Vector3(0, 7, 2), "white", 20)
	cyl(8.2, 3.0, 3.0, Vector3(0, 8.2, 2), "slate", 20)
	for i in 9:
		var a := PI * (0.5 + i / 8.0)
		cyl(0.45, 0.4, 7.0, Vector3(sin(a) * 8.0, 0, 2 + cos(a) * 8.0), "white", 8)
	cyl(4.0, 4.0, 0.15, Vector3(0, 0, -3), "lamp", 12)
	for s in [-1.0, 1.0]:
		var cx: float = s * 17.0
		box(Vector3(14, 6, 1), Vector3(cx, 3, 3.5), "white")
		box(Vector3(15, 1.0, 6), Vector3(cx, 6.5, 1.0), "white")
		box(Vector3(15, 0.6, 6.4), Vector3(cx, 7.3, 1.0), "slate")
		for i in 6:
			cyl(0.35, 0.3, 6.0, Vector3(cx - 6.0 + i * 2.4, 0, -1.6), "white", 8)
		box(Vector3(5, 8.5, 7), Vector3(s * 26.5, 4.25, 1.0), "white")
		roof(5.4, 7.4, 2.0, Vector3(s * 26.5, 8.5, 1.0), "slate")
	label("ELISENBRUNNEN", Vector3(0, 7.6, -6.7), 90, Color(0.15, 0.13, 0.1), 1.0)
	light(Vector3(0, 4, -4), Color(1.0, 0.85, 0.6), 3.0, 18.0)


## SuperC der RWTH: Block mit weit auskragendem Obergeschoss (ein liegendes C)
func _super_c() -> void:
	box(Vector3(22, 26, 24), Vector3(16, 13, 0), "dimstone")
	box(Vector3(56, 10, 24), Vector3(0, 31, 0), "dimstone")
	box(Vector3(14, 6, 24), Vector3(-21, 3, 0), "dimstone")
	for y in [4.0, 8.0, 12.0, 16.0, 20.0]:
		box(Vector3(20, 1.4, 0.2), Vector3(16, y, -12.1), "win_cool")
	for y in [28.0, 32.0]:
		box(Vector3(54, 1.4, 0.2), Vector3(0, y, -12.1), "win_cool")
	box(Vector3(12, 1.2, 0.2), Vector3(-21, 3, -12.1), "win_cool")
	label("RWTH", Vector3(-14, 25.0, -12.3), 220, Color(0.6, 0.8, 1.0), 1.6)


## Stadttheater: klassizistischer Bau mit Säulenvorhalle und Giebel
func _theater() -> void:
	box(Vector3(30, 17, 26), Vector3(0, 8.5, 4), "cream")
	roof(30.5, 26.5, 5.0, Vector3(0, 17, 4), "slate")
	box(Vector3(18, 1.6, 6), Vector3(0, 0.8, -12), "cream")
	for i in 6:
		cyl(0.75, 0.65, 10.5, Vector3(-7.5 + i * 3.0, 1.6, -13), "cream", 10)
	box(Vector3(18.6, 2.2, 6.4), Vector3(0, 13.2, -12), "cream")
	var p := PrismMesh.new()
	p.size = Vector3(18.6, 4.0, 1.0)
	put(p, "cream", Transform3D(Basis.IDENTITY, Vector3(0, 16.3, -14.6)))
	windows(-12.0, 12.0, 4.0, 4.0, 2, 5.5, -9.0, Vector2(1.6, 3.2))
	label("THEATER AACHEN", Vector3(0, 13.2, -15.25), 80, Color(0.15, 0.12, 0.08), 1.0)
	light(Vector3(0, 6, -16), Color(1.0, 0.8, 0.55), 3.0, 20.0)


# --- Würzburg -----------------------------------------------------------------

## Residenz: dreiflügeliges Barockschloss, Ehrenhof zur Straße, Frankoniabrunnen davor
func _residenz() -> void:
	var h := 21.0
	box(Vector3(90, h, 26), Vector3(0, h / 2.0, 30), "ochre")  # Mittelbau
	box(Vector3(24, h + 6, 28), Vector3(0, (h + 6) / 2.0, 22), "ochre")  # Mittelpavillon
	put(Builder.tapered_box(Vector2(90.5, 26.5), Vector2(80, 14), 7.0, 0.0), "slate", Transform3D(Basis.IDENTITY, Vector3(0, h, 30)))
	put(Builder.tapered_box(Vector2(24.5, 28.5), Vector2(14, 16), 6.0, 0.0), "slate", Transform3D(Basis.IDENTITY, Vector3(0, h + 6, 22)))
	windows(-42.0, 42.0, 4.0, 3.0, 3, 6.5, 17.0, Vector2(1.6, 3.6))
	for s in [-1.0, 1.0]:
		var x: float = s * 60.0
		box(Vector3(30, h, 80), Vector3(x, h / 2.0, 5), "ochre")
		put(Builder.tapered_box(Vector2(30.5, 80.5), Vector2(18, 70), 7.0, 0.0), "slate", Transform3D(Basis.IDENTITY, Vector3(x, h, 5)))
		windows(x - 12.0, x + 12.0, 4.0, 3.0, 3, 6.5, -35.0, Vector2(1.6, 3.6))
		# Hofseite der Flügel
		windows(-24.0, 34.0, 4.0, 3.0, 3, 6.5, 0.0, Vector2(1.6, 3.6), "win", s * PI / 2.0)
		for i in 7:
			box(Vector3(1.0, h, 0.6), Vector3(x - 13.5 + i * 4.5, h / 2.0, -35.2), "ochre")
	# Giebel des Mittelpavillons
	var p := PrismMesh.new()
	p.size = Vector3(22, 5, 1)
	put(p, "ochre", Transform3D(Basis.IDENTITY, Vector3(0, h + 8.5, 7.5)))
	box(Vector3(4.5, 6.0, 0.2), Vector3(0, 3.0, 7.9), "win")
	# Frankoniabrunnen
	cyl(5.0, 5.2, 1.0, Vector3(0, 0, -48), "sand", 12)
	cyl(4.4, 4.4, 0.2, Vector3(0, 0.85, -48), "water", 12)
	cyl(1.0, 0.7, 5.5, Vector3(0, 1.0, -48), "sand", 8)
	box(Vector3(1.2, 2.4, 0.9), Vector3(0, 7.7, -48), "sand")
	for i in 3:
		var a := TAU * i / 3.0
		box(Vector3(1.0, 2.0, 0.8), Vector3(sin(a) * 3.0, 2.0, -48 + cos(a) * 3.0), "sand")
	light(Vector3(0, 8, -40), Color(1.0, 0.8, 0.5), 4.0, 50.0)


## Festung Marienberg: Ringmauer mit Bastionen, Echterbau-Flügel um den Hof, Bergfried, Rundkirche, Kiliansturm
func _festung() -> void:
	for s in [-1.0, 1.0]:
		box(Vector3(200, 12, 3), Vector3(0, 6, s * 50.0), "sand")
		box(Vector3(3, 12, 100), Vector3(s * 100.0, 6, 0), "sand")
		for t in [-1.0, 1.0]:
			box(Vector3(18, 13, 18), Vector3(s * 100.0, 6.5, t * 50.0), "sand", PI / 4.0)
	# Flügel um den Innenhof (helle Fenster), rote Ziegeldächer
	var wings := [[Vector3(0, 0, -26), 70.0, 0.0], [Vector3(0, 0, 26), 70.0, 0.0], [Vector3(-38, 0, 0), 56.0, PI / 2.0], [Vector3(38, 0, 0), 56.0, PI / 2.0]]
	for w in wings:
		var c: Vector3 = w[0]
		var len: float = w[1]
		var rot: float = w[2]
		box(Vector3(len, 17, 13), c + Vector3(0, 8.5, 0), "sand", rot)
		roof(len + 0.6, 13.6, 9.0, c + Vector3(0, 17, 0), "tile", rot)
	windows(-32.0, 32.0, 4.0, 4.0, 3, 4.5, -32.6, Vector2(1.2, 2.2))
	windows(-60.0, 60.0, 8.0, 1.5, 1, 3.0, -51.6, Vector2(1.0, 1.6))
	# Bergfried und Marienkirche im Hof
	cyl(5.5, 5.5, 34.0, Vector3(-8, 0, 2), "sand", 12)
	cyl(6.2, 0.0, 8.0, Vector3(-8, 34, 2), "tile", 12)
	cyl(7.5, 7.5, 13.0, Vector3(12, 0, 4), "sand", 12)
	cyl(8.0, 2.0, 6.0, Vector3(12, 13, 4), "copper", 12)
	onion(1.6, Vector3(12, 19, 4), "copper")
	# Kiliansturm (Uhrturm über dem Tor) mit Haube
	box(Vector3(9, 32, 9), Vector3(-36, 16, -26), "sand")
	onion(3.4, Vector3(-36, 32, -26), "copper")
	box(Vector3(9, 30, 9), Vector3(34, 15, 26), "sand")
	spire(6.0, 10.0, Vector3(34, 30, 26), "tile")
	light(Vector3(0, 20, -60), Color(1.0, 0.8, 0.5), 5.0, 90.0)


## Alte Mainbrücke: Steinbögen, zwölf Heiligenfiguren auf den Pfeilern, Laternen, Leute beim Brückenschoppen.
## Lokal: X = Brückenachse (über den Fluss), Wasser liegt bei y = -2.2.
func _mainbruecke(len: float) -> void:
	var deck := 1.2
	box(Vector3(len, 1.4, 8.0), Vector3(0, deck - 0.7, 0), "sand")
	for s in [-1.0, 1.0]:
		box(Vector3(len, 1.1, 0.6), Vector3(0, deck + 0.55, s * 3.7), "sand")
	var arches := maxi(int(len / 22.0), 4)
	var span := len / arches
	var figure := 0
	for i in arches + 1:
		var x := -len / 2.0 + i * span
		if i > 0 and i < arches:
			box(Vector3(5.0, 7.0, 9.0), Vector3(x, -3.5 + deck - 0.6, 0), "sand")
			for s in [-1.0, 1.0]:
				box(Vector3(3.6, 7.0, 3.6), Vector3(x, -3.5 + deck - 0.6, s * 5.2), "sand", PI / 4.0)  # Eisbrecher
				# Heiligenfigur auf Sockel
				if figure < 12:
					box(Vector3(1.4, 1.6, 1.4), Vector3(x, deck + 0.8, s * 3.7), "sand")
					box(Vector3(0.9, 2.6, 0.7), Vector3(x, deck + 2.9, s * 3.7), "sand")
					sphere(0.4, Vector3(x, deck + 4.5, s * 3.7), "sand")
					box(Vector3(0.12, 0.12, 0.9), Vector3(x, deck + 4.9, s * 3.7), "gold")
					figure += 1
		if i < arches:
			# Bogen: dunkle Öffnung unter dem Scheitel
			var cx := x + span / 2.0
			for s in [-1.0, 1.0]:
				put(Builder.box(Vector3(span - 5.2, 3.2, 0.2)), "dark", Transform3D(Basis.IDENTITY, Vector3(cx, -1.6, s * 4.05)))
			box(Vector3(0.25, 1.2, 0.25), Vector3(cx, deck + 1.7, -3.7), "iron")
			sphere(0.32, Vector3(cx, deck + 2.5, -3.7), "lamp")
	var xfs := []
	var modes := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 26:
		var x := rng.randf_range(-len * 0.4, len * 0.4)
		var z := rng.randf_range(-2.6, 2.6)
		xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, deck, z)))
		modes.append(People.WAIT if rng.randf() < 0.6 else People.PHONE)
	People.crowd(n, xfs, modes, rng)
	light(Vector3(0, 4, 0), Color(1.0, 0.8, 0.5), 3.0, 40.0)


## Dom St. Kilian: romanische Basilika mit zwei schlanken Westtürmen und zwei Osttürmen
func _kiliansdom() -> void:
	box(Vector3(80, 22, 24), Vector3(6, 11, 0), "white")
	roof(80.5, 24.6, 9.0, Vector3(6, 22, 0), "slate")
	box(Vector3(14, 18, 40), Vector3(30, 9, 0), "white")
	roof(14.4, 40.4, 7.0, Vector3(30, 18, 0), "slate", PI / 2.0)
	windows(-26.0, 42.0, 6.0, 12.0, 1, 0.0, -12.0, Vector2(1.6, 4.0), "glass_gold")
	for t in [-1.0, 1.0]:
		box(Vector3(8, 48, 8), Vector3(-40, 24, t * 7.0), "white")
		spire(5.0, 16.0, Vector3(-40, 48, t * 7.0), "slate")
		box(Vector3(6, 34, 6), Vector3(44, 17, t * 9.0), "white")
		spire(4.0, 10.0, Vector3(44, 34, t * 9.0), "slate")
		windows(-40.0, -40.0, 1.0, 30.0, 3, 5.0, t * 7.0 - 4.0, Vector2(1.0, 2.6), "win")
	box(Vector3(10, 16, 14), Vector3(-40, 8, 0), "white")


## Käppele: Wallfahrtskirche am Hang, Kuppel und zwei Fronttürme mit Zwiebelhauben
func _kaeppele() -> void:
	box(Vector3(30, 16, 22), Vector3(0, 8, 3), "white")
	roof(30.5, 22.6, 7.0, Vector3(0, 16, 3), "copper")
	cyl(7.0, 7.0, 6.0, Vector3(4, 16, 3), "white", 12)
	cyl(7.5, 1.5, 6.0, Vector3(4, 22, 3), "copper", 12)
	onion(1.4, Vector3(4, 28, 3), "copper")
	for s in [-1.0, 1.0]:
		box(Vector3(6, 26, 6), Vector3(-12, 13, s * 7.0), "white")
		onion(3.0, Vector3(-12, 26, s * 7.0), "copper")
	windows(-8.0, 12.0, 5.0, 4.0, 2, 6.0, -8.0, Vector2(1.4, 3.0))
	light(Vector3(0, 10, -18), Color(1.0, 0.85, 0.6), 4.0, 40.0)


## Marienkapelle: gotische Hallenkirche (rot-weiß) mit filigranem Turm, goldene Madonna auf der Spitze
func _marienkapelle() -> void:
	box(Vector3(40, 20, 16), Vector3(4, 10, 0), "white")
	roof(40.5, 16.6, 13.0, Vector3(4, 20, 0), "slate")
	for i in 7:
		var x := -12.0 + i * 5.5
		box(Vector3(1.4, 22.0, 2.0), Vector3(x, 11, -8.6), "redsand")
		put(Builder.box(Vector3(2.4, 13.0, 0.15)), "glass", Transform3D(Basis.IDENTITY, Vector3(x + 2.75, 10, -8.1)))
	box(Vector3(8, 40, 8), Vector3(-20, 20, 0), "redsand")
	spire(5.0, 28.0, Vector3(-20, 40, 0), "dimstone", 8)
	box(Vector3(0.6, 2.2, 0.6), Vector3(-20, 69.5, 0), "gold")


## Alter Kranen: barocker Hafenkran am Mainufer, runder Turm mit Haube und zwei Auslegern
func _alter_kranen() -> void:
	cyl(5.0, 4.6, 8.0, Vector3.ZERO, "sand", 8)
	cyl(5.6, 0.6, 5.0, Vector3(0, 8, 0), "slate", 8)
	for s in [-1.0, 1.0]:
		put(Builder.box(Vector3(0.6, 0.6, 9.0)), "wood", Transform3D(Basis(Vector3.RIGHT, s * 0.5) * Basis(Vector3.UP, s * 0.4), Vector3(s * 2.0, 10.5, -5.0)))
	windows(-1.5, 1.5, 3.0, 3.0, 1, 0.0, -4.7, Vector2(1.0, 1.6))


# --- Bad Kissingen ------------------------------------------------------------

## Regentenbau: neubarocker Kursaalbau mit Säulenportikus und Mansarddach
func _regentenbau() -> void:
	box(Vector3(110, 17, 30), Vector3(0, 8.5, 2), "cream")
	put(Builder.tapered_box(Vector2(110.5, 30.5), Vector2(100, 18), 6.0, 0.0), "slate", Transform3D(Basis.IDENTITY, Vector3(0, 17, 2)))
	windows(-52.0, 52.0, 4.0, 3.0, 2, 7.0, -13.0, Vector2(1.8, 4.2))
	box(Vector3(28, 22, 10), Vector3(0, 11, -16), "cream")
	for i in 6:
		cyl(0.8, 0.7, 14.0, Vector3(-10.0 + i * 4.0, 0, -21.5), "cream", 10)
	var p := PrismMesh.new()
	p.size = Vector3(28, 5, 1)
	put(p, "cream", Transform3D(Basis.IDENTITY, Vector3(0, 24.5, -20.6)))
	put(Builder.tapered_box(Vector2(28.5, 10.5), Vector2(20, 6), 4.0, 0.0), "copper", Transform3D(Basis.IDENTITY, Vector3(0, 22, -16)))
	label("REGENTENBAU", Vector3(0, 19.5, -21.15), 110, Color(0.16, 0.12, 0.06), 1.0)
	light(Vector3(0, 8, -26), Color(1.0, 0.85, 0.6), 4.0, 30.0)


## Arkadenbau: 200 m lange Rundbogenhalle am Kurgarten
func _arkadenbau() -> void:
	box(Vector3(200, 11, 3), Vector3(0, 5.5, 3.5), "cream")
	box(Vector3(200, 1.4, 9), Vector3(0, 7.2, 0), "cream")
	box(Vector3(200, 4.0, 6), Vector3(0, 9.8, 1.5), "cream")
	roof(200.5, 6.6, 2.5, Vector3(0, 11.8, 1.5), "slate")
	var x := -98.0
	while x <= 98.0:
		cyl(0.45, 0.4, 6.5, Vector3(x, 0, -4.0), "cream", 8)
		x += 5.0
	windows(-96.0, 96.0, 5.0, 2.0, 1, 0.0, 1.95, Vector2(2.4, 3.6))
	windows(-96.0, 96.0, 5.0, 8.6, 1, 0.0, -1.55, Vector2(1.4, 1.8))
	for i in 9:
		box(Vector3(0.2, 0.6, 0.6), Vector3(-80.0 + i * 20.0, 6.3, -3.5), "lamp")
	label("ARKADENBAU", Vector3(0, 7.2, -4.6), 90, Color(0.16, 0.12, 0.06), 1.0)


## Spielbank im Luitpoldpark: heller Bau, rote Leuchtschrift
func _spielbank() -> void:
	box(Vector3(42, 12, 22), Vector3(0, 6, 2), "white")
	put(Builder.tapered_box(Vector2(42.5, 22.5), Vector2(36, 14), 4.5, 0.0), "slate", Transform3D(Basis.IDENTITY, Vector3(0, 12, 2)))
	windows(-18.0, 18.0, 4.0, 2.0, 2, 5.0, -9.0, Vector2(2.0, 3.0))
	box(Vector3(14, 0.5, 6), Vector3(0, 4.5, -12), "white")
	for s in [-1.0, 1.0]:
		cyl(0.3, 0.3, 4.5, Vector3(s * 6.5, 0, -14.5), "white", 8)
	box(Vector3(13, 0.15, 5.6), Vector3(0, 4.2, -12), "lamp")
	label("SPIELBANK", Vector3(0, 10.0, -9.3), 200, Color(1.0, 0.15, 0.2), 2.6)
	light(Vector3(0, 3.5, -13), Color(1.0, 0.75, 0.45), 3.0, 18.0)


## Gradierbau der Oberen Saline: hohes Holzgerüst mit Schwarzdornwänden, über die Sole rieselt
func _gradierbau() -> void:
	var len := 124.0
	box(Vector3(len, 14.0, 5.0), Vector3(0, 8.0, 0), "brush")
	box(Vector3(len, 1.0, 9.0), Vector3(0, 0.5, 0), "dimstone")  # Auffangbecken
	box(Vector3(len - 1.0, 0.1, 8.0), Vector3(0, 1.0, 0), "water")
	var x := -len / 2.0
	while x <= len / 2.0:
		for s in [-1.0, 1.0]:
			box(Vector3(0.4, 16.0, 0.4), Vector3(x, 8.0, s * 2.8), "wood")
		x += 4.0
	for y in [1.0, 15.0]:
		for s in [-1.0, 1.0]:
			box(Vector3(len, 0.4, 0.4), Vector3(0, y, s * 2.8), "wood")
	roof(len + 1.0, 6.6, 2.4, Vector3(0, 15.2, 0), "wood")
	for i in 7:
		box(Vector3(0.3, 0.3, 0.3), Vector3(-54.0 + i * 18.0, 3.0, -3.2), "lamp")
	label("GRADIERBAU", Vector3(0, 12.0, -3.05), 160, Color(1.0, 0.85, 0.6), 1.4)
	light(Vector3(0, 6, -8), Color(1.0, 0.8, 0.5), 3.0, 40.0)


## Altes Rathaus: Renaissancebau mit Treppengiebeln und Dachreiter
func _altes_rathaus() -> void:
	box(Vector3(22, 12, 14), Vector3(0, 6, 0), "ochre")
	roof(22.0, 14.6, 9.0, Vector3(0, 12, 0), "tile")
	for s in [-1.0, 1.0]:
		for k in 4:
			box(Vector3(0.8, 2.2, 14.0 - k * 3.4), Vector3(s * 11.2, 13.1 + k * 2.2, 0), "ochre")
	box(Vector3(2.4, 4.0, 2.4), Vector3(0, 22, 0), "ochre")
	onion(1.4, Vector3(0, 24, 0), "copper")
	windows(-8.0, 8.0, 4.0, 2.5, 2, 4.5, -7.0, Vector2(1.4, 2.4))


# --- Tauberbischofsheim -------------------------------------------------------

## Türmersturm (Bergfried der alten Burg) und Kurmainzisches Schloss
func _tuermersturm() -> void:
	cyl(5.5, 5.3, 29.0, Vector3(-10, 0, 0), "grey", 16)
	cyl(6.3, 6.3, 4.0, Vector3(-10, 29, 0), "white", 16)
	windows(-12.0, -8.0, 4.0, 30.0, 1, 0.0, -6.3, Vector2(1.2, 1.8))
	cyl(6.8, 0.0, 10.0, Vector3(-10, 33, 0), "tile", 16)
	box(Vector3(0.25, 2.0, 0.25), Vector3(-10, 43.5, 0), "gold")
	box(Vector3(26, 13, 12), Vector3(8, 6.5, 2), "white")
	roof(26.5, 12.6, 9.0, Vector3(8, 13, 2), "tile")
	box(Vector3(10, 11, 16), Vector3(18, 5.5, 10), "white")
	roof(10.4, 16.4, 7.0, Vector3(18, 11, 10), "tile", PI / 2.0)
	windows(-2.0, 18.0, 3.5, 2.5, 3, 3.6, -4.0, Vector2(1.2, 2.0))
	label("KURMAINZISCHES SCHLOSS", Vector3(8, 4.0, -4.1), 46, Color(0.15, 0.12, 0.08), 1.0)
	light(Vector3(-10, 12, -14), Color(1.0, 0.85, 0.6), 4.0, 36.0)


## Neugotisches Rathaus am Marktplatz mit Mittelturm und Fialen
func _tbb_rathaus() -> void:
	box(Vector3(26, 15, 14), Vector3(0, 7.5, 0), "redsand")
	roof(26.5, 14.6, 8.0, Vector3(0, 15, 0), "slate")
	box(Vector3(7, 22, 7), Vector3(0, 11, -4), "redsand")
	spire(4.5, 12.0, Vector3(0, 22, -4), "slate")
	box(Vector3(0.2, 1.8, 0.2), Vector3(0, 34.8, -4), "gold")
	for x in [-13.0, -3.5, 3.5, 13.0]:
		box(Vector3(0.7, 18.5, 0.7), Vector3(x, 9.25, -7.4), "redsand")
		spire(0.6, 2.5, Vector3(x, 18.5, -7.4), "redsand")
	windows(-11.0, 11.0, 3.6, 3.0, 2, 5.0, -7.0, Vector2(1.3, 3.0))
	cyl(1.6, 1.6, 0.2, Vector3(0, 16.5, -7.55), "lamp", 12)
	label("RATHAUS", Vector3(0, 13.4, -7.65), 70, Color(0.95, 0.85, 0.6), 1.2)


## Stadtkirche St. Martin: neugotisch, hoher Westturm
func _st_martin() -> void:
	box(Vector3(42, 17, 18), Vector3(4, 8.5, 0), "redsand")
	roof(42.5, 18.6, 11.0, Vector3(4, 17, 0), "slate")
	for i in 6:
		var x := -12.0 + i * 6.0
		put(Builder.box(Vector3(2.0, 9.0, 0.15)), "glass", Transform3D(Basis.IDENTITY, Vector3(x + 3.0, 8.5, -9.1)))
		box(Vector3(1.0, 15.0, 1.6), Vector3(x, 7.5, -9.4), "redsand")
	box(Vector3(9, 44, 9), Vector3(-21, 22, 0), "redsand")
	spire(6.0, 24.0, Vector3(-21, 44, 0), "slate", 8)
	box(Vector3(0.3, 2.6, 0.3), Vector3(-21, 69, 0), "gold")
	cyl(1.6, 1.6, 0.2, Vector3(-21, 34, -4.6), "lamp", 12)


# --- Hammelburg ---------------------------------------------------------------

## Renaissance-Rathaus mit Treppenturm von 1526 und Marktbrunnen von 1541
func _hammelburg_rathaus() -> void:
	box(Vector3(26, 13, 14), Vector3(0, 6.5, 4), "white")
	roof(26.5, 14.6, 10.0, Vector3(0, 13, 4), "tile")
	for s in [-1.0, 1.0]:
		for k in 4:
			box(Vector3(0.8, 2.5, 14.0 - k * 3.4), Vector3(s * 13.2, 14.2 + k * 2.5, 4), "white")
	cyl(2.8, 2.8, 18.0, Vector3(-6, 0, -3.6), "ochre", 8)
	cyl(3.2, 0.0, 6.0, Vector3(-6, 18, -3.6), "tile", 8)
	box(Vector3(0.2, 1.6, 0.2), Vector3(-6, 24.8, -3.6), "gold")
	windows(-1.0, 10.0, 3.6, 2.5, 3, 3.6, -3.0, Vector2(1.3, 2.2))
	for i in 3:
		box(Vector3(1.2, 1.8, 1.2), Vector3(-6.0 + i * 6.0, 15.2, -1.0), "tile")
	# Marktbrunnen (Achteckbecken, Säule mit Figur)
	cyl(3.2, 3.3, 0.9, Vector3(0, 0, -14), "sand", 8)
	cyl(2.8, 2.8, 0.2, Vector3(0, 0.75, -14), "water", 8)
	cyl(0.4, 0.35, 4.2, Vector3(0, 0.9, -14), "sand", 8)
	box(Vector3(0.7, 1.6, 0.5), Vector3(0, 5.9, -14), "gold")
	light(Vector3(0, 5, -16), Color(1.0, 0.8, 0.55), 3.0, 22.0)


## Schloss Saaleck über der Saale: Bergfried, Palas, Mauern
func _saaleck() -> void:
	box(Vector3(9, 26, 9), Vector3(-14, 13, 2), "sand")
	spire(6.5, 8.0, Vector3(-14, 26, 2), "tile")
	box(Vector3(30, 14, 13), Vector3(8, 7, 4), "sand")
	roof(30.5, 13.6, 8.0, Vector3(8, 14, 4), "tile")
	windows(-4.0, 20.0, 4.0, 3.0, 2, 4.5, -2.5, Vector2(1.2, 2.0))
	for s in [-1.0, 1.0]:
		box(Vector3(56, 6, 1.6), Vector3(0, 3, s * 20.0), "sand")
		box(Vector3(1.6, 6, 40), Vector3(s * 28.0, 3, 0), "sand")
	windows(-15.0, -13.0, 2.0, 18.0, 1, 0.0, -2.5, Vector2(1.0, 1.6))
	light(Vector3(0, 10, -24), Color(1.0, 0.8, 0.5), 4.0, 44.0)


# --- Berlin-Kreuzberg -----------------------------------------------------------

## Oberbaumbrücke: rote Backsteinbrücke über die Spree mit den zwei Türmen in der Mitte und dem Hochbahn-Viadukt
## (Bogengang) an der Seite. Steht direkt auf der Fahrbahn: lokal -Z = Fahrtrichtung, hw = halbe Breite bis Gehwegkante.
func _oberbaumbruecke(hw: float) -> void:
	var len := 60.0
	for s in [-1.0, 1.0]:
		# Brüstung aus Backstein mit Zinnen
		box(Vector3(0.8, 1.3, len), Vector3(s * (hw + 0.6), 0.65, 0), "brick")
		var z := -len / 2.0
		while z <= len / 2.0:
			box(Vector3(0.9, 0.4, 0.8), Vector3(s * (hw + 0.6), 1.5, z), "brick")
			z += 2.4
		# Türme in der Brückenmitte
		box(Vector3(5.0, 22.0, 5.0), Vector3(s * (hw + 3.0), 11.0, 0), "brick")
		box(Vector3(5.6, 1.2, 5.6), Vector3(s * (hw + 3.0), 22.4, 0), "brick")
		spire(4.0, 8.0, Vector3(s * (hw + 3.0), 23.0, 0), "copper")
		windows(s * (hw + 3.0) - 1.0, s * (hw + 3.0) + 1.0, 2.0, 8.0, 3, 4.5, -2.5, Vector2(0.8, 2.2))
	# Hochbahn-Viadukt mit Bögen auf der linken Seite
	var vx := -(hw + 6.5)
	box(Vector3(7.0, 1.4, len), Vector3(vx, 7.2, 0), "brick")
	var z2 := -len / 2.0
	while z2 <= len / 2.0:
		box(Vector3(7.0, 6.5, 1.6), Vector3(vx, 3.25, z2), "brick")
		z2 += 7.5
	for s in [-1.0, 1.0]:
		box(Vector3(0.3, 1.0, len), Vector3(vx + s * 3.3, 8.4, 0), "iron")
	light(Vector3(0, 6, 0), Color(1.0, 0.75, 0.5), 3.0, 30.0)


## Fernsehturm am Alexanderplatz: weit weg, aber über Kreuzberg immer zu sehen
func _fernsehturm() -> void:
	cyl(16.0, 4.5, 200.0, Vector3.ZERO, "concrete", 16)
	sphere(16.0, Vector3(0, 212.0, 0), "concrete")
	cyl(16.3, 16.3, 3.0, Vector3(0, 208.0, 0), "win", 24)
	cyl(4.0, 4.0, 18.0, Vector3(0, 226.0, 0), "concrete", 12)
	cyl(1.6, 0.4, 120.0, Vector3(0, 244.0, 0), "white", 8)
	box(Vector3(2.0, 2.0, 2.0), Vector3(0, 364.0, 0), "blink")
	box(Vector3(1.5, 1.5, 1.5), Vector3(0, 300.0, 0), "blink")


## Neues Kreuzberger Zentrum am Kottbusser Tor: langer, geschwungener Wohnblock mit Laubengängen
func _nkz() -> void:
	for i in 5:
		var a := (i - 2) * 0.12
		var x := (i - 2) * 22.0
		box(Vector3(23.0, 38.0, 14.0), Vector3(x, 19.0, abs(i - 2) * 3.0), "concrete", a)
		for f in 12:
			box(Vector3(22.5, 0.35, 0.8), Vector3(x, 3.0 + f * 3.0, abs(i - 2) * 3.0 - 7.2), "dimstone", a)
	windows(-50.0, 50.0, 3.0, 3.6, 11, 3.0, -7.3, Vector2(1.4, 1.6))
	label("KOTTBUSSER TOR", Vector3(0, 4.0, -7.8), 120, Color(1.0, 0.85, 0.3), 2.0)



# --- Wahrzeichen der entworfenen Städte (seit 2.36) ---------------------------------------------------------------------

## Kölner Dom: gotische Kathedrale aus dunklem Sandstein, zwei Westtürme mit durchbrochenen Helmen, Querhaus, Chor mit
## Strebewerk und Fialen; nachts angestrahlt. Die Türme stehen am Ende der Rheinufer-Geraden vor der Kehre im Blick.
func _koelner_dom() -> void:
	var len := 92.0
	box(Vector3(len, 34, 30), Vector3(4, 17, 0), "grey")
	roof(len + 0.5, 30.6, 15.0, Vector3(4, 34, 0), "slate")
	box(Vector3(22, 30, 62), Vector3(14, 15, 0), "grey")
	roof(22.4, 62.4, 13.0, Vector3(14, 30, 0), "slate", PI / 2.0)
	cyl(15.0, 15.0, 34.0, Vector3(50, 0, 0), "grey", 10)
	cyl(15.5, 2.0, 14.0, Vector3(50, 34, 0), "slate", 10)
	windows(-30.0, 44.0, 6.5, 12.0, 1, 0.0, -15.0, Vector2(2.6, 15.0), "glass_gold")
	# Strebepfeiler mit Fialen
	var x := -34.0
	while x <= 46.0:
		for s in [-1.0, 1.0]:
			box(Vector3(2.4, 26, 5.0), Vector3(x, 13, s * 18.0), "grey")
			spire(1.6, 9.0, Vector3(x, 26, s * 18.0), "grey")
			box(Vector3(1.0, 1.2, 4.0), Vector3(x, 29.0, s * 16.0), "grey")
		x += 8.0
	# Westtürme
	for t in [-1.0, 1.0]:
		box(Vector3(16, 74, 16), Vector3(-50, 37, t * 11.0), "grey")
		box(Vector3(12, 18, 12), Vector3(-50, 83, t * 11.0), "grey")
		cyl(7.5, 0.6, 40.0, Vector3(-50, 92, t * 11.0), "grey", 8, PI / 8.0)
		for c in [[-1, -1], [-1, 1], [1, -1], [1, 1]]:
			spire(1.4, 12.0, Vector3(-50 + c[0] * 7.0, 74, t * 11.0 + c[1] * 7.0), "grey")
		windows(-50.0, -50.0, 1.0, 40.0, 3, 11.0, t * 11.0 - 8.1, Vector2(2.2, 8.0), "win")
		box(Vector3(1.2, 1.2, 1.2), Vector3(-50, 133, t * 11.0), "gold")
	box(Vector3(10, 30, 22), Vector3(-50, 15, 0), "grey")
	box(Vector3(6.0, 16.0, 0.4), Vector3(-58.2, 8.0, 0), "dark")
	label("DOM", Vector3(-58.6, 26.0, 0), 140, Color(1.0, 0.85, 0.55), 1.4)
	light(Vector3(-62, 30, -30), Color(1.0, 0.88, 0.7), 5.0, 90.0)
	light(Vector3(20, 25, -32), Color(1.0, 0.88, 0.7), 4.0, 70.0)


## Hohenzollernbrücke: Eisenbahnbrücke mit drei stählernen Bögen je Seite über den Rhein (nicht befahrbar), nachts
## angestrahlt; liegt quer über den Fluss neben dem Dom
func _hohenzollernbruecke(len: float) -> void:
	var deck := 9.0
	box(Vector3(len, 1.6, 14.0), Vector3(0, deck - 0.8, 0), "iron")
	var spans := 3
	var span := len / spans
	for i in spans + 1:
		var x := -len / 2.0 + i * span
		box(Vector3(6.0, deck + 4.0, 16.0), Vector3(x, (deck + 4.0) / 2.0 - 4.0, 0), "sand")
	var steel := "copper"
	for i in spans:
		var cx := -len / 2.0 + (i + 0.5) * span
		for s in [-1.0, 1.0]:
			var segs := 14
			var prev := Vector3(cx - span / 2.0 + 3.0, deck, s * 7.0)
			for k in range(1, segs + 1):
				var t := float(k) / segs
				var px := cx - span / 2.0 + 3.0 + (span - 6.0) * t
				var py := deck + 22.0 * 4.0 * t * (1.0 - t)
				var q := Vector3(px, py, s * 7.0)
				var mid := (prev + q) / 2.0
				var seg := q - prev
				put(Builder.box(Vector3(seg.length() + 0.3, 1.2, 0.9)), steel, Transform3D(Basis(Vector3.BACK, atan2(seg.y, seg.x)), mid))
				if k % 2 == 0 and k < segs:
					box(Vector3(0.3, py - deck, 0.3), Vector3(px, deck + (py - deck) / 2.0, s * 7.0), steel)
				prev = q
	for k in 7:
		light(Vector3(-len / 2.0 + len * (k + 0.5) / 7.0, deck + 6.0, 0), Color(0.75, 0.85, 1.0), 2.0, 34.0)


## Bremer Roland mit Rathaus: Renaissancefassade mit Giebeln, davor der steinerne Roland auf dem Marktplatz
func _roland() -> void:
	box(Vector3(56, 20, 22), Vector3(0, 10, 6), "redsand")
	roof(56.5, 22.6, 12.0, Vector3(0, 20, 6), "copper")
	for gx in [-18.0, 0.0, 18.0]:
		box(Vector3(10, 12, 2.0), Vector3(gx, 26, -5.0), "sand")
		spire(5.5, 8.0, Vector3(gx, 32, -5.0), "sand", 4)
	windows(-24.0, 24.0, 6.0, 4.0, 2, 7.0, -5.1, Vector2(2.0, 4.0))
	# Arkaden unten
	var ax := -24.0
	while ax <= 24.0:
		box(Vector3(1.2, 6, 1.2), Vector3(ax, 3, -6.0), "sand")
		ax += 6.0
	# Roland: Sockel, Figur, Schild
	box(Vector3(3.0, 2.0, 3.0), Vector3(-10, 1.0, -18.0), "sand")
	box(Vector3(1.6, 7.0, 1.2), Vector3(-10, 5.5, -18.0), "grey")
	sphere(0.8, Vector3(-10, 9.6, -18.0), "grey")
	box(Vector3(1.4, 2.0, 0.3), Vector3(-10, 5.5, -18.8), "gold")
	box(Vector3(0.15, 4.0, 0.15), Vector3(-9.0, 6.5, -18.6), "grey")
	label("RATHAUS", Vector3(0, 17.0, -5.2), 120, Color(1.0, 0.85, 0.55), 1.5)
	light(Vector3(-10, 6, -26), Color(1.0, 0.85, 0.6), 3.0, 30.0)
	light(Vector3(10, 10, -16), Color(1.0, 0.85, 0.6), 3.0, 40.0)


## Fernsehturm Stuttgart: schlanker Betonschaft, Korb mit Fenstern, rot-weiße Antenne; über dem Kessel weit zu sehen
func _stuttgart_turm() -> void:
	cyl(5.5, 3.2, 130.0, Vector3.ZERO, "concrete", 14)
	cyl(7.5, 7.5, 14.0, Vector3(0, 130.0, 0), "concrete", 18)
	cyl(7.6, 7.6, 5.0, Vector3(0, 133.0, 0), "win", 18)
	cyl(7.8, 7.8, 1.0, Vector3(0, 144.0, 0), "white", 18)
	cyl(1.6, 0.5, 46.0, Vector3(0, 145.0, 0), "white", 8)
	for hy in [158.0, 172.0, 190.0]:
		box(Vector3(1.4, 1.4, 1.4), Vector3(0, hy, 0), "blink")



## Elbphilharmonie: Backstein-Kaispeicher, darauf der Glasaufbau mit geschwungenem Dach (Wellenkronen), nachts hinter
## den Scheiben hell; liegt gegenüber dem Hafen-Drift auf der anderen Elbseite
func _elbphilharmonie() -> void:
	box(Vector3(108, 30, 40), Vector3(0, 15, 0), "brick")
	windows(-50.0, 50.0, 4.0, 3.0, 6, 4.4, -20.0, Vector2(1.2, 1.6), "dark")
	box(Vector3(108, 2.0, 40.5), Vector3(0, 31, 0), "concrete")
	box(Vector3(106, 34, 38), Vector3(0, 49, 0), "glass")
	# Wellen des Dachs: Kuppen unterschiedlicher Höhe
	var crests := [[-42.0, 6.0], [-22.0, 12.0], [-4.0, 22.0], [16.0, 14.0], [36.0, 9.0], [48.0, 4.0]]
	for c in crests:
		sphere(16.0, Vector3(c[0], 66.0 + c[1] * 0.3, 0), "white", c[1] / 16.0)
	box(Vector3(106, 1.0, 38.4), Vector3(0, 66.0, 0), "white")
	for k in 9:
		box(Vector3(106.2, 0.25, 38.6), Vector3(0, 35.0 + k * 3.6, 0), "win_cool")
	light(Vector3(0, 40, -40), Color(0.7, 0.85, 1.0), 4.0, 90.0)



# --- Wahrzeichen der übrigen entworfenen Städte (seit 2.36, frei nachempfunden, ohne Schriftzüge echter Marken) ------

## Turm mit Pyramidenspitze (Frankfurter Messeturm nachempfunden): Schaft mit abgeschrägten Ecken, Fensterbänder,
## leuchtende Spitze; steht am Ende der Hochhausschlucht im Blick
func _messeturm() -> void:
	box(Vector3(30, 120, 30), Vector3(0, 60, 0), "redsand")
	for c in [[-1, -1], [-1, 1], [1, -1], [1, 1]]:
		box(Vector3(4, 120, 4), Vector3(c[0] * 14.0, 60, c[1] * 14.0), "grey", PI / 4.0)
	box(Vector3(24, 18, 24), Vector3(0, 129, 0), "redsand")
	spire(17.0, 26.0, Vector3(0, 138, 0), "glass_gold")
	windows(-12.0, 12.0, 4.0, 6.0, 26, 4.4, -15.0, Vector2(2.4, 2.0), "win_cool")
	box(Vector3(1.2, 1.2, 1.2), Vector3(0, 165, 0), "blink")
	light(Vector3(0, 150, -24), Color(1.0, 0.8, 0.45), 4.0, 70.0)


## Römer: drei Fachwerk-Giebelhäuser mit Treppengiebeln und Balkon, davor ein Brunnen (Frankfurter Römerberg)
func _roemer() -> void:
	for i in 3:
		var x := (i - 1) * 18.0
		box(Vector3(16, 16, 18), Vector3(x, 8, 2), "cream" if i != 1 else "sand")
		for k in 4:
			box(Vector3(16.0 - k * 4.0, 2.4, 1.2), Vector3(x, 17.2 + k * 2.4, -6.6), "sand")
		roof(17.0, 19.0, 9.0, Vector3(x, 16, 2), "slate", PI / 2.0)
		windows(x - 6.0, x + 6.0, 3.0, 3.0, 4, 3.5, -7.0, Vector2(1.3, 1.8))
	box(Vector3(30, 0.4, 2.2), Vector3(0, 7.0, -8.2), "iron")
	cyl(3.0, 3.0, 1.0, Vector3(0, 0, -22), "sand", 12)
	cyl(0.5, 0.4, 5.0, Vector3(0, 1, -22), "sand", 8)
	sphere(0.7, Vector3(0, 6.6, -22), "gold")
	light(Vector3(0, 8, -20), Color(1.0, 0.82, 0.55), 3.0, 34.0)


## Tor über der Straße (Siegestor, Stadttor, Brückentor): zwei Pfeilertürme neben dem Gehweg (hw = halbe Breite bis
## zur Außenkante), ein Bogen in Höhe h über der ganzen Fahrbahn; arch: Rundbogen mit Attika und Figuren (Siegestor),
## sonst Türme mit Spitzhelm (Stadt- und Brückentor). Name oben auf der Attika.
func _tor(hw: float, mk: String, h: float, arch: bool, name: String) -> void:
	var tw := 9.0
	for s in [-1.0, 1.0]:
		var x: float = s * (hw + tw / 2.0)
		box(Vector3(tw, h + 6.0, 10.0), Vector3(x, (h + 6.0) / 2.0, 0), mk)
		if not arch:
			spire(6.0, 10.0, Vector3(x, h + 6.0, 0), "slate")
			windows(x, x, 1.0, 6.0, 3, 5.0, -5.0, Vector2(1.2, 2.2))
	box(Vector3(hw * 2.0 + tw * 2.0, 6.0, 10.0), Vector3(0, h + 3.0, 0), mk)
	if arch:
		box(Vector3(hw * 2.0 + tw * 2.0 + 2.0, 1.2, 11.0), Vector3(0, h + 6.6, 0), mk)
		box(Vector3(6.0, 4.0, 3.0), Vector3(0, h + 9.2, 0), "copper")
		for k in 4:
			sphere(0.9, Vector3(-4.5 + k * 3.0, h + 12.0, 0), "copper")
		for s in [-1.0, 1.0]:
			for c in 2:
				box(Vector3(1.2, h, 1.2), Vector3(s * (hw + 1.0 + c * 6.5), h / 2.0, -5.4), mk)
	box(Vector3(hw * 2.0, 0.6, 10.2), Vector3(0, h - 0.3, 0), "dimstone")
	if name != "":
		_label2(name, h + 3.0, 5.15, 140)
	light(Vector3(0, h - 2.0, -9.0), Color(1.0, 0.85, 0.6), 3.0, 30.0)
	light(Vector3(0, h - 2.0, 9.0), Color(1.0, 0.85, 0.6), 3.0, 30.0)


## Name auf beiden Seiten eines Tors (man fährt von +Z her darauf zu)
func _label2(text: String, y: float, z: float, size: int) -> void:
	for s in [-1.0, 1.0]:
		label(text, Vector3(0, y, s * z), size, Color(1.0, 0.86, 0.6), 1.3)
		if s > 0.0:
			(n.get_child(n.get_child_count() - 1) as Node3D).rotation_degrees.y = 0.0


## Brückentor (Heidelberg): Torbogen am Ende der Alten Brücke zwischen zwei runden hellen Türmen mit dunklen barocken
## Hauben
func _brueckentor(hw: float, name: String) -> void:
	var oh := 8.0
	var top := 14.0
	var dep := 9.0
	for s in [-1.0, 1.0]:
		var tx: float = s * (hw + 4.6)
		cyl(5.3, 5.0, 24.0, Vector3(tx, 0, 0), "sand", 16)
		cyl(5.6, 5.6, 0.8, Vector3(tx, 24.0, 0), "dimstone", 16)
		cyl(5.4, 3.0, 3.6, Vector3(tx, 24.8, 0), "slate", 16)
		sphere(3.2, Vector3(tx, 29.4, 0), "slate", 0.8)
		cyl(1.1, 0.8, 2.2, Vector3(tx, 31.6, 0), "slate", 8)
		spire(0.9, 5.0, Vector3(tx, 33.8, 0), "slate", 8)
		box(Vector3(0.12, 1.4, 0.12), Vector3(tx, 39.4, 0), "gold")
		for k in 3:
			for zs in [-1.0, 1.0]:
				box(Vector3(1.0, 1.7, 0.3), Vector3(tx - s * 1.5, 7.0 + k * 5.5, zs * 4.95), "win" if (k + int(zs)) % 2 == 0 else "dark")
		box(Vector3(2.2, 1.4, dep), Vector3(s * (hw - 1.1), oh - 0.7, 0), "redsand")
		box(Vector3(1.0, 0.9, dep), Vector3(s * (hw - 2.7), oh - 0.45, 0), "redsand")
	box(Vector3(hw * 2.0 + 2.0, top - oh, dep), Vector3(0, (top + oh) / 2.0, 0), "sand")
	box(Vector3(hw * 2.0 + 2.0, 0.8, dep + 0.4), Vector3(0, top + 0.4, 0), "dimstone")
	roof(hw * 2.0 + 2.0, dep, 3.2, Vector3(0, top + 0.8, 0), "slate")
	box(Vector3(hw * 2.0 + 0.2, 0.7, dep + 0.1), Vector3(0, oh + 0.35, 0), "redsand")
	if name != "":
		_label2(name, oh + 1.9, dep / 2.0 + 0.15, 90)
	light(Vector3(0, oh - 1.5, -dep / 2.0 - 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(0, oh - 1.5, dep / 2.0 + 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(0, 20.0, 14.0), Color(1.0, 0.85, 0.65), 4.0, 36.0)


## Backsteintor (Rostock, Kröpeliner Tor): Torhaus aus Backstein mit Spitzbogen und Blendnischen, darüber der hohe
## Torturm mit steilem Satteldach
func _backsteintor(hw: float, name: String) -> void:
	var oh := 8.5
	var top := 16.0
	var dep := 12.0
	for s in [-1.0, 1.0]:
		box(Vector3(5.0, top, dep), Vector3(s * (hw + 2.5), top / 2.0, 0), "brick")
		box(Vector3(2.4, 1.6, dep), Vector3(s * (hw - 1.2), oh - 0.8, 0), "brick")
		box(Vector3(1.1, 1.2, dep), Vector3(s * (hw - 2.9), oh - 0.6, 0), "brick")
	box(Vector3(hw * 2.0, top - oh, dep), Vector3(0, (top + oh) / 2.0, 0), "brick")
	# Turm über der Durchfahrt: Blendnischen (dunkel), helle Putzstreifen, Fenster, steiles Dach mit Dachreiter
	var tw := 16.0
	box(Vector3(tw, 20.0, dep), Vector3(0, top + 10.0, 0), "brick")
	for z in [-dep / 2.0 - 0.05, dep / 2.0 + 0.05]:
		for k in 4:
			var x := -5.4 + k * 3.6
			box(Vector3(2.2, 9.0, 0.3), Vector3(x, top + 7.0, z), "dark")
			box(Vector3(2.2, 0.5, 0.3), Vector3(x, top + 12.0, z), "cream")
			box(Vector3(1.1, 1.8, 0.32), Vector3(x, top + 15.5, z), "win" if k % 3 != 1 else "dark")
		box(Vector3(tw, 0.6, 0.3), Vector3(0, top + 1.0, z), "cream")
		for k in 5:
			box(Vector3(1.6, 5.0, 0.3), Vector3(-hw + 2.5 + k * (hw * 2.0 - 5.0) / 4.0, oh + 3.6, z), "dark")
	roof(dep + 0.6, tw + 0.6, 12.0, Vector3(0, top + 20.0, 0), "slate", PI / 2.0)
	box(Vector3(1.6, 4.0, 1.6), Vector3(0, top + 33.0, 0), "copper")
	spire(1.2, 5.0, Vector3(0, top + 35.0, 0), "copper", 8)
	if name != "":
		_label2(name, oh + 1.0, dep / 2.0 + 0.15, 90)
	light(Vector3(0, oh - 1.5, -dep / 2.0 - 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(0, oh - 1.5, dep / 2.0 + 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(0, top + 12.0, 16.0), Color(1.0, 0.8, 0.6), 4.0, 40.0)


## Stadttor (Nürnberg): Torhaus aus rotem Sandstein über der Straße mit abgetrepptem Bogen und Satteldach, daneben der
## dicke runde Torturm mit Wehrgang und Kegeldach (wie die vier großen Tortürme der Stadtmauer)
func _stadttor(hw: float, name: String) -> void:
	var oh := 8.5
	var pw := 5.0
	var top := 17.0
	var dep := 11.0
	for s in [-1.0, 1.0]:
		box(Vector3(pw, top, dep), Vector3(s * (hw + pw / 2.0), top / 2.0, 0), "redsand")
		box(Vector3(2.2, 1.4, dep), Vector3(s * (hw - 1.1), oh - 0.7, 0), "redsand")
		box(Vector3(1.0, 0.9, dep), Vector3(s * (hw - 2.7), oh - 0.45, 0), "redsand")
	box(Vector3(hw * 2.0, top - oh, dep), Vector3(0, (top + oh) / 2.0, 0), "redsand")
	box(Vector3(hw * 2.0 + pw * 2.0 + 0.6, 0.6, dep + 0.6), Vector3(0, top - 0.3, 0), "dimstone")
	roof(hw * 2.0 + pw * 2.0 + 0.6, dep + 0.6, 7.5, Vector3(0, top, 0), "tile")
	for z in [-dep / 2.0, dep / 2.0 + 0.08]:
		windows(-hw + 3.0, hw - 3.0, 4.5, oh + 2.8, 2, 3.0, z, Vector2(1.0, 1.5))
	var tx := hw + pw + 6.5
	cyl(8.6, 8.1, 30.0, Vector3(tx, 0, 0), "redsand", 18)
	cyl(8.7, 8.7, 1.4, Vector3(tx, 30.0, 0), "dimstone", 18)
	cyl(9.2, 0.0, 13.0, Vector3(tx, 31.4, 0), "tile", 18)
	for k in 8:
		var a := k * TAU / 8.0 + 0.2
		box(Vector3(0.6, 1.8, 0.3), Vector3(tx + 8.35 * cos(a), 9.0 + (k % 3) * 6.0, 8.35 * sin(a)), "win" if k % 2 == 0 else "dimstone", PI / 2.0 - a)
	if name != "":
		_label2(name, oh + 1.1, dep / 2.0 + 0.15, 100)
	light(Vector3(0, oh - 1.5, -dep / 2.0 - 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(0, oh - 1.5, dep / 2.0 + 3.0), Color(1.0, 0.8, 0.55), 3.0, 26.0)
	light(Vector3(tx - 4.0, 18.0, -16.0), Color(1.0, 0.82, 0.6), 4.0, 40.0)


## Friedensengel: Säule auf einer Terrasse mit Treppen, oben ein goldener Engel
func _friedensengel() -> void:
	box(Vector3(28, 4, 22), Vector3(0, 2, 0), "sand")
	box(Vector3(14, 4, 14), Vector3(0, 6, 0), "sand")
	cyl(1.8, 1.6, 28.0, Vector3(0, 8, 0), "white", 14)
	box(Vector3(4.6, 2.0, 4.6), Vector3(0, 37, 0), "sand")
	box(Vector3(1.2, 3.6, 1.0), Vector3(0, 39.8, 0), "gold")
	box(Vector3(3.6, 1.6, 0.3), Vector3(0, 41.0, 0.4), "gold")
	light(Vector3(0, 30, -14), Color(1.0, 0.85, 0.6), 4.0, 50.0)


## Frauenkirche (München): Backsteinhalle, zwei hohe Türme mit grünen Hauben
func _frauenkirche() -> void:
	box(Vector3(70, 30, 34), Vector3(8, 15, 0), "brick")
	roof(70.5, 34.6, 22.0, Vector3(8, 30, 0), "tile")
	windows(-22.0, 38.0, 7.5, 6.0, 1, 0.0, -17.0, Vector2(2.2, 16.0), "glass_gold")
	for s in [-1.0, 1.0]:
		box(Vector3(13, 70, 13), Vector3(-34, 35, s * 8.0), "brick")
		sphere(6.2, Vector3(-34, 74, s * 8.0), "copper", 1.3)
		box(Vector3(0.4, 4.0, 0.4), Vector3(-34, 84, s * 8.0), "gold")
		windows(-34.0, -34.0, 1.0, 46.0, 2, 8.0, s * 8.0 - 6.6, Vector2(1.6, 4.0), "win")
	light(Vector3(-50, 40, -20), Color(1.0, 0.85, 0.65), 5.0, 80.0)


## Landungsbrücken (Hamburg): langes Abfertigungsgebäude mit Kuppeln und Uhrturm am Wasser
func _landungsbruecken() -> void:
	box(Vector3(120, 12, 22), Vector3(0, 6, 0), "redsand")
	for x in [-45.0, -15.0, 15.0, 45.0]:
		sphere(6.0, Vector3(x, 12, 0), "copper", 0.8)
	box(Vector3(10, 34, 10), Vector3(56, 17, 0), "redsand")
	cyl(5.5, 0.6, 12.0, Vector3(56, 34, 0), "copper", 8)
	cyl(3.0, 3.0, 0.4, Vector3(56, 28, -5.2), "white", 16, 0.0)
	windows(-55.0, 50.0, 5.0, 3.0, 2, 4.0, -11.0, Vector2(2.2, 2.4))
	light(Vector3(0, 10, -18), Color(1.0, 0.8, 0.5), 4.0, 60.0)


## Michel (St. Michaelis): heller Barockturm mit grüner Kupferhaube, Kirchenschiff
func _michel() -> void:
	box(Vector3(40, 26, 34), Vector3(10, 13, 0), "cream")
	roof(40.5, 34.6, 12.0, Vector3(10, 26, 0), "copper")
	box(Vector3(14, 60, 14), Vector3(-16, 30, 0), "cream")
	cyl(6.0, 5.0, 16.0, Vector3(-16, 60, 0), "copper", 8)
	onion(3.4, Vector3(-16, 76, 0), "copper")
	cyl(2.6, 2.6, 0.4, Vector3(-16, 52, -7.2), "white", 16)
	light(Vector3(-16, 50, -22), Color(1.0, 0.85, 0.65), 4.0, 60.0)


## Kaiserburg (Nürnberg): Sandsteinburg auf dem Felsen, runder Turm, Palas, Wehrmauer
func _kaiserburg() -> void:
	box(Vector3(90, 10, 50), Vector3(0, 5, 0), "redsand")
	box(Vector3(46, 16, 18), Vector3(-14, 18, 6), "redsand")
	roof(46.5, 18.6, 9.0, Vector3(-14, 26, 6), "tile")
	cyl(8.0, 8.0, 34.0, Vector3(28, 10, 0), "redsand", 16)
	cyl(8.6, 0.8, 10.0, Vector3(28, 44, 0), "tile", 12)
	box(Vector3(12, 30, 12), Vector3(-40, 25, -8), "redsand")
	spire(8.0, 12.0, Vector3(-40, 40, -8), "tile")
	windows(-34.0, 6.0, 5.0, 14.0, 2, 4.0, -3.1, Vector2(1.4, 2.0))
	light(Vector3(0, 30, -40), Color(1.0, 0.82, 0.6), 5.0, 90.0)


## Hochofen mit Winderhitzern, Gichtbühne und Rohrbrücken (Ruhrgebiet, nachts angestrahlt)
func _hochofen() -> void:
	cyl(9.0, 7.0, 46.0, Vector3(0, 0, 0), "iron", 16)
	cyl(5.0, 3.0, 22.0, Vector3(0, 46, 0), "iron", 12)
	box(Vector3(20, 2, 20), Vector3(0, 38, 0), "iron")
	for k in 3:
		cyl(5.5, 5.5, 40.0, Vector3(-22 + k * 12.0, 0, 18), "grey", 14)
		sphere(5.5, Vector3(-22 + k * 12.0, 40, 18), "grey")
	box(Vector3(60, 2.2, 2.2), Vector3(-10, 30, 9), "iron")
	box(Vector3(2.2, 2.2, 36), Vector3(14, 26, 0), "iron")
	box(Vector3(1.4, 1.4, 1.4), Vector3(0, 69, 0), "blink")
	light(Vector3(0, 20, -16), Color(1.0, 0.55, 0.25), 6.0, 60.0)
	light(Vector3(0, 52, 0), Color(1.0, 0.45, 0.15), 4.0, 40.0)


## Förderturm einer Zeche: Stahlgerüst mit zwei Seilscheiben, Maschinenhaus
func _foerderturm() -> void:
	for s in [-1.0, 1.0]:
		box(Vector3(1.4, 44, 1.4), Vector3(s * 7.0, 22, -4), "iron")
		box(Vector3(1.4, 44, 1.4), Vector3(s * 7.0, 22, 4), "iron")
	box(Vector3(16, 2, 10), Vector3(0, 44, 0), "iron")
	for s in [-1.0, 1.0]:
		cyl(4.0, 4.0, 0.8, Vector3(s * 3.0, 47, 0), "iron", 16)
	box(Vector3(1.0, 50, 1.0), Vector3(0, 21, 14), "iron", 0.0)
	box(Vector3(24, 14, 14), Vector3(0, 7, 24), "brick")
	roof(24.5, 14.6, 5.0, Vector3(0, 14, 24), "slate", PI / 2.0)
	box(Vector3(1.2, 1.2, 1.2), Vector3(0, 50, 0), "blink")
	light(Vector3(0, 30, -14), Color(1.0, 0.8, 0.5), 4.0, 50.0)


## Heidelberger Schloss: rote Sandsteinruine am Hang, Fassaden mit leeren Fenstern, dicker Turm, nachts angestrahlt
func _heidelberger_schloss() -> void:
	# Terrasse mit Stützmauer
	box(Vector3(112, 9, 70), Vector3(0, 4.5, 2), "redsand_dk")
	box(Vector3(112.6, 0.8, 70.6), Vector3(0, 9.2, 2), "dimstone")
	# Palast zur Stadt (-Z): drei Geschosse, Pilaster, drei Zwerchgiebel, steiles Dach
	box(Vector3(56, 18, 16), Vector3(-8, 18, -22), "redsand")
	for k in 8:
		box(Vector3(0.9, 18, 0.7), Vector3(-35 + k * 7.7, 18, -30.2), "redsand_dk")
	for r in 3:
		for k in 7:
			var lit := (k * 3 + r * 5) % 4 != 0 and r < 2
			box(Vector3(2.0, 2.8, 0.3), Vector3(-31.2 + k * 7.7, 11.0 + r * 5.6, -30.15), "win" if lit else "dark")
	for k in 3:
		var gx := -27.0 + k * 19.0
		box(Vector3(9.0, 5.0, 1.4), Vector3(gx, 29.5, -29.4), "redsand")
		box(Vector3(5.0, 3.0, 1.4), Vector3(gx, 33.5, -29.4), "redsand")
		box(Vector3(1.6, 2.0, 1.4), Vector3(gx, 36.0, -29.4), "redsand")
		box(Vector3(1.6, 2.4, 0.3), Vector3(gx, 29.6, -30.15), "win")
	roof(56.5, 16.6, 10.0, Vector3(-8, 27, -22), "slate")
	# dachloser Flügel (Ruine): hohe Mauer mit leeren Fensteröffnungen, Seitenwand
	box(Vector3(30, 22, 1.6), Vector3(36, 20, -16), "redsand")
	for r in 2:
		for k in 4:
			box(Vector3(2.6, 4.2, 0.3), Vector3(25.0 + k * 7.5, 14.0 + r * 8.0, -16.85), "dark")
	box(Vector3(1.6, 22, 22), Vector3(50.2, 20, -6), "redsand_dk")
	# Flügel hinten am Hof
	box(Vector3(72, 15, 14), Vector3(-2, 16.5, 20), "redsand_dk")
	roof(72.5, 14.6, 8.0, Vector3(-2, 24, 20), "slate")
	# Glockenturm mit barocker Haube
	box(Vector3(11, 32, 11), Vector3(24, 25, -26), "redsand")
	windows(21.0, 27.0, 3.0, 30.0, 2, 4.5, -31.5, Vector2(1.0, 2.4))
	cyl(7.6, 4.0, 4.0, Vector3(24, 41, -26), "slate", 8)
	sphere(3.4, Vector3(24, 46.5, -26), "slate", 0.9)
	spire(1.0, 6.0, Vector3(24, 49.5, -26), "slate", 8)
	# dicker Turm mit Zinnenkranz
	cyl(13.0, 12.6, 30.0, Vector3(-46, 8, 6), "redsand", 22)
	for k in 16:
		var a := k * TAU / 16.0
		box(Vector3(2.2, 2.0, 1.4), Vector3(-46 + 12.2 * cos(a), 39.0, 6 + 12.2 * sin(a)), "redsand", PI / 2.0 - a)
	for k in 4:
		var a := -PI / 2.0 + (k - 1.5) * 0.35
		box(Vector3(1.2, 2.2, 0.3), Vector3(-46 + 12.75 * cos(a), 22.0 + (k % 2) * 6.0, 6 + 12.75 * sin(a)), "win", PI / 2.0 - a)
	# gesprengter Turm: halber Ring, die vordere Hälfte liegt im Graben
	for k in 9:
		var a := PI * (0.05 + 0.9 * k / 8.0)
		var hk := 14.0 + 7.0 * sin(k * 1.7) + 4.0
		box(Vector3(4.4, hk, 3.0), Vector3(47 + 9.0 * cos(a), 9.0 + hk / 2.0, 22 + 9.0 * sin(a)), "redsand", PI / 2.0 - a)
	light(Vector3(-10, 22, -52), Color(1.0, 0.62, 0.4), 6.0, 110.0)
	light(Vector3(-46, 20, -24), Color(1.0, 0.6, 0.38), 3.0, 50.0)


## Marienkirche (Rostock): Backsteingotik, wuchtiger Westturm mit Kupferhaube
func _marienkirche() -> void:
	box(Vector3(70, 28, 30), Vector3(8, 14, 0), "brick")
	roof(70.5, 30.6, 16.0, Vector3(8, 28, 0), "copper")
	box(Vector3(18, 30, 50), Vector3(20, 15, 0), "brick")
	roof(18.5, 50.6, 12.0, Vector3(20, 30, 0), "copper", PI / 2.0)
	box(Vector3(20, 60, 20), Vector3(-34, 30, 0), "brick")
	cyl(9.0, 1.5, 22.0, Vector3(-34, 60, 0), "copper", 8)
	windows(-20.0, 40.0, 8.0, 6.0, 1, 0.0, -15.0, Vector2(2.6, 16.0), "glass_gold")
	light(Vector3(-50, 40, -20), Color(1.0, 0.85, 0.65), 5.0, 80.0)


## Leuchtturm an der Küste mit Laterne und Drehfeuer, daneben ein Pavillon mit geschwungenem Dach (Warnemünde)
func _leuchtturm() -> void:
	cyl(5.0, 3.6, 34.0, Vector3(0, 0, 0), "white", 16)
	for k in 3:
		cyl(5.0 - k * 0.45, 4.8 - k * 0.45, 2.0, Vector3(0, 6 + k * 10.0, 0), "neon_red", 16)
	cyl(4.4, 4.4, 1.0, Vector3(0, 34, 0), "iron", 16)
	cyl(2.6, 2.6, 4.0, Vector3(0, 35, 0), "win", 12)
	cyl(3.0, 0.6, 3.0, Vector3(0, 39, 0), "copper", 12)
	box(Vector3(26, 4, 20), Vector3(26, 2, 0), "white")
	sphere(13.0, Vector3(26, 3, 0), "white", 0.35)
	windows(16.0, 36.0, 4.0, 1.0, 1, 0.0, -10.2, Vector2(2.4, 2.0))
	var beam := OmniLight3D.new()
	beam.position = Vector3(0, 37, 0)
	beam.light_color = Color(1.0, 0.95, 0.8)
	beam.light_energy = 6.0
	beam.omni_range = 60.0
	n.add_child(beam)
