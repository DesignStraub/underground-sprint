extends RefCounted
## Leute: ein Körper aus Querschnitten (Becken und Rumpf mit Brust, Taille und Schulterschräge, Hals, Kopf mit Kinn,
## Nase und Ohren, Arme mit Hand und Daumen, Beine mit Knie und Wade, Schuhe mit Ferse und Spitze), weiche Normalen.
## Der Shader biegt ihn an den Gelenken weich wie eine Haut (Ecken nahe am Gelenk drehen nur anteilig mit, UV2.y),
## formt die Statur (Frau/Mann, schlank bis kräftig) und malt Kleidung und Gesicht. Kleidung und Frisur wechseln je
## Figur: T-Shirt, Langarm, Hoodie mit Kapuze, offene Jacke mit Kragen; Jeans, Shorts, Rock; kurze Haare, lang,
## Zopf, Dutt, Glatze, Kappe, Mütze; Rucksack, Umhängetasche. Alle Varianten stecken in einem Modell; der Shader
## blendet die nicht gewählten Teile aus (UV2.x = Variante), so bleibt es ein MultiMesh je Gruppe.
## In der Ferne eine einfache Blockfigur mit denselben Bewegungen (ab 30–96 m je nach Detaildichte, gemessen zur
## Mitte einer Zelle). Gruppen werden dafür in Zellen von CELL m geteilt, jede mit naher und ferner Fassung.
## Maße: Mann 1,745 m (7,5 Kopflängen), Frauen macht der Shader 6 % kleiner; die Gelenke stehen auch im Shader (J_*).

const SHADER := preload("res://shaders/people.gdshader")

enum { CHEER, DANCE, WAIT, WAVE, CLAP, RUN, PHONE, STARTER }

## Oberteile: eher Alltagsfarben der Stadt bei Nacht (Schwarz, Grau, Navy, Weiß), dazu einige kräftige
const SHIRTS := [Color(0.72, 0.1, 0.12), Color(0.12, 0.3, 0.7), Color(0.85, 0.68, 0.16), Color(0.9, 0.9, 0.88),
	Color(0.07, 0.07, 0.08), Color(0.2, 0.5, 0.3), Color(0.85, 0.42, 0.12), Color(0.42, 0.22, 0.55),
	Color(0.88, 0.36, 0.5), Color(0.12, 0.55, 0.62), Color(0.42, 0.44, 0.47), Color(0.1, 0.13, 0.24),
	Color(0.16, 0.16, 0.17), Color(0.55, 0.52, 0.46)]

const CELL := 30.0

## Körperteile (UV.x) für die Bewegung im Shader
enum { P_BODY, P_ARM_L, P_ARM_R, P_LEG_L, P_LEG_R, P_HEAD, P_FORE_L, P_FORE_R, P_SHIN_L, P_SHIN_R, P_HIPS,
	P_FOOT_L, P_FOOT_R }
## Farbgruppen (UV.y), siehe people.gdshader. Rumpf, Arm, Bein und Schuh teilt der Shader nach Höhe (Saum, Ärmel,
## Hosenbein, Sohle), dafür braucht es keine eigenen Ecken.
enum { G_TORSO, G_LEG, G_SKIN, G_HAIR, G_SHOE, G_GLOW, G_ARM, G_JACKET, G_CAP, G_PHONE, G_SCREEN, G_SKIRT, G_BAG,
	G_HOOD }
## Varianten (UV2.x): 0 immer sichtbar. Brille und Bart malt der Shader ins Gesicht.
enum { O_ALL, O_HAIR_TOP, O_HAIR_LONG, O_PONY, O_BUN, O_CAP, O_BEANIE, O_HOOD, O_SKIRT, O_JACKET, O_STICKS, O_PHONE,
	O_HAIR_NAPE, O_BACKPACK, O_BAG }

## Rumpf von Schritt bis Halsansatz: [y, halbe Breite, Tiefe vorn, Tiefe hinten, Rundung (2 rund, 3 eckiger)]
const TORSO := [
	[0.795, 0.060, 0.044, 0.050, 2.0],  # Schritt
	[0.835, 0.135, 0.074, 0.090, 2.3],
	[0.885, 0.164, 0.087, 0.106, 2.5],  # Hüfte, Gesäß
	[0.945, 0.165, 0.091, 0.103, 2.6],
	[1.065, 0.148, 0.098, 0.086, 2.6],  # Taille
	[1.135, 0.150, 0.104, 0.088, 2.7],
	[1.270, 0.165, 0.114, 0.098, 2.9],  # Brust
	[1.330, 0.170, 0.110, 0.101, 3.0],  # Achseln
	[1.385, 0.17, 0.100, 0.099, 3.0],
	[1.418, 0.163, 0.087, 0.092, 2.7],  # Schulterhöhe
	[1.448, 0.122, 0.069, 0.079, 2.4],  # Schulterschräge
	[1.474, 0.082, 0.053, 0.064, 2.2],
	[1.492, 0.058, 0.046, 0.054, 2.0],  # Halsansatz
]
## Kopf von Kinn bis Scheitel: [y, halbe Breite, Tiefe vorn, Tiefe hinten, Rundung, Mitte z]
const HEAD := [
	[1.513, 0.018, 0.016, 0.014, 2.0, -0.070],  # Kinn unten
	[1.527, 0.040, 0.026, 0.040, 2.0, -0.064],
	[1.550, 0.056, 0.042, 0.058, 2.2, -0.052],  # Kiefer
	[1.578, 0.065, 0.058, 0.074, 2.3, -0.040],  # Mund, Kieferwinkel
	[1.605, 0.071, 0.080, 0.088, 2.4, -0.020],  # Nasenbasis, Wangen
	[1.632, 0.075, 0.093, 0.099, 2.5, -0.005],  # Augen, Schläfen
	[1.662, 0.0765, 0.097, 0.103, 2.4, 0.000],  # Brauen
	[1.692, 0.0745, 0.093, 0.100, 2.3, 0.002],  # Stirn
	[1.733, 0.053, 0.060, 0.068, 2.1, 0.005],
	[1.742, 0.032, 0.036, 0.042, 2.0, 0.005],
	[1.7465, 0.012, 0.013, 0.015, 2.0, 0.005],  # Scheitel
]
## Arm von der Schulterkuppe bis zu den Fingerspitzen (rechts): [y, halbe Dicke x, halbe Tiefe z, Mitte x, Mitte z].
## Die Hand hängt mit der Handfläche zum Oberschenkel (schmal von vorn, breit von der Seite).
const ARM := [
	[1.434, 0.012, 0.012, 0.169, 0.004],  # Schulterkuppe (unter der Schulterschräge)
	[1.428, 0.03, 0.032, 0.173, 0.004],
	[1.414, 0.042, 0.045, 0.178, 0.004],
	[1.39, 0.047, 0.05, 0.183, 0.004],  # Deltamuskel
	[1.300, 0.045, 0.047, 0.195, 0.008],
	[1.235, 0.043, 0.046, 0.201, 0.008],  # Bizeps
	[1.125, 0.037, 0.039, 0.204, 0.012],
	[1.095, 0.037, 0.039, 0.205, 0.012],  # Ellbogen
	[1.060, 0.040, 0.042, 0.207, 0.008],
	[1.000, 0.038, 0.040, 0.210, 0.004],  # Unterarm
	[0.885, 0.027, 0.031, 0.219, 0.000],
	[0.858, 0.024, 0.029, 0.221, 0.000],  # Handgelenk
	[0.835, 0.019, 0.031, 0.222, -0.003],  # Handballen
	[0.806, 0.0165, 0.035, 0.222, -0.005],  # Mittelhand
	[0.779, 0.0155, 0.034, 0.22, -0.006],  # Knöchel
	[0.756, 0.0145, 0.03, 0.214, -0.005],  # Finger, zur Handfläche gekrümmt
	[0.737, 0.0125, 0.025, 0.207, -0.004],
	[0.726, 0.009, 0.017, 0.202, -0.003],  # Fingerspitzen
]
## Bein von der Hüfte bis in den Schuh (rechts): [y, halbe Breite, halbe Tiefe, Mitte x, Mitte z]
const LEG := [
	[0.950, 0.062, 0.06, 0.084, 0.008],  # im Becken (bleibt unter der Hüfte)
	[0.880, 0.072, 0.068, 0.088, 0.008],
	[0.800, 0.083, 0.084, 0.093, -0.004],
	[0.700, 0.074, 0.075, 0.095, -0.008],  # Oberschenkel
	[0.600, 0.064, 0.066, 0.096, -0.008],
	[0.535, 0.056, 0.058, 0.096, -0.006],
	[0.495, 0.053, 0.055, 0.096, -0.004],  # Knie
	[0.455, 0.050, 0.052, 0.097, 0.000],
	[0.400, 0.053, 0.058, 0.098, 0.008],  # Wade
	[0.240, 0.041, 0.043, 0.100, 0.012],
	[0.075, 0.031, 0.034, 0.100, 0.020],  # Knöchel (im Schuh)
]
## Schuh von der Ferse bis zur Spitze (rechts): [z, halbe Breite, Sohle unten, Oberkante, Mitte x]
const SHOE := [
	[0.086, 0.019, 0.005, 0.048, 0.100],  # Ferse
	[0.073, 0.036, 0.000, 0.078, 0.100],
	[0.040, 0.043, 0.000, 0.104, 0.100],  # Schaft am Knöchel
	[0.000, 0.045, 0.000, 0.100, 0.101],
	[-0.050, 0.048, 0.000, 0.081, 0.103],  # Spann
	[-0.100, 0.050, 0.000, 0.064, 0.106],  # Ballen
	[-0.185, 0.038, 0.002, 0.044, 0.108],  # Zehen
	[-0.205, 0.020, 0.006, 0.034, 0.107],  # Spitze
]

## Seiten der Querschnitte (Rumpf durch 4 teilbar: eine Ecke genau vorn und hinten)
const TORSO_N := 16
const ARM_N := 8
const LEG_N := 10
const SHOE_N := 8

## 0/1: Figur (alle Varianten), 2: Starterin (mit Leuchtstäben), 3: Blockfigur für die Ferne
static var _meshes := {}


static func mesh(kind: int) -> ArrayMesh:
	if kind == 1:
		kind = 0
	if _meshes.has(kind):
		return _meshes[kind]
	var m := _far_mesh() if kind == 3 else _detail_mesh(kind == 2)
	_meshes[kind] = m
	return m


## Sammelt Ecken und Dreiecke; Normalen werden je Teil weich aus den Flächen gemittelt
class Mb:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var shape := PackedFloat32Array()  # CUSTOM0 je Ecke, zwei Werte (siehe _shape_all), leer = keine

	## Ecke mit Körperteil, Farbgruppe, Variante und Anteil der eigenen Gelenkdrehung k
	func add(p: Vector3, part: int, grp: int, opt: int, k := 1.0) -> int:
		v.append(p)
		n.append(Vector3.ZERO)
		uv.append(Vector2(part, grp))
		uv2.append(Vector2(opt, clampf(k, 0.0, 1.0)))
		return v.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	## Dreiecke ab i0 so drehen, dass sie von hint weg nach außen zeigen (Godots Vorderseite läuft im
	## Uhrzeigersinn), dann weiche Normalen für die Ecken ab v0
	func smooth(v0: int, i0: int, hint: Vector3) -> void:
		var s := 0.0
		for i in range(i0, idx.size(), 3):
			var a := v[idx[i]]
			var b := v[idx[i + 1]]
			var c := v[idx[i + 2]]
			s += (b - a).cross(c - a).dot((a + b + c) / 3.0 - hint)
		if s > 0.0:
			for i in range(i0, idx.size(), 3):
				var t := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = t
		for i in range(i0, idx.size(), 3):
			var a := v[idx[i]]
			var fn := -(v[idx[i + 1]] - a).cross(v[idx[i + 2]] - a)
			for j in 3:
				n[idx[i + j]] += fn
		for j in range(v0, v.size()):
			n[j] = n[j].normalized() if n[j].length_squared() > 1e-16 else Vector3.UP

	## Fläche durch Ringe gleicher Punktzahl. attr(p) -> Vector2(Teil, k). closed: Ring rundum (sonst offener Bogen).
	## cap0/cap1: ersten/letzten Ring mit einem Mittelpunkt schließen; band: der Ring ist ein dünnes Band (außen hin,
	## innen zurück), dann quer zuschließen statt zur Mitte
	func loft(rings: Array, attr: Callable, grp: int, opt: int, closed := true, cap0 := false, cap1 := false,
			hint = null, band := false) -> void:
		var v0 := v.size()
		var i0 := idx.size()
		var m: int = (rings[0] as PackedVector3Array).size()
		var base := []
		var sum := Vector3.ZERO
		for r in rings:
			base.append(v.size())
			for p in r:
				var a: Vector2 = attr.call(p)
				add(p, int(a.x), grp, opt, a.y)
				sum += p
		var segs := m if closed else m - 1
		for k in rings.size() - 1:
			for i in segs:
				var i2 := (i + 1) % m
				var a: int = base[k] + i
				var b: int = base[k] + i2
				var c: int = base[k + 1] + i2
				var d: int = base[k + 1] + i
				tri(a, b, c)
				tri(a, c, d)
		for cap in [[cap0, 0], [cap1, rings.size() - 1]]:
			if not cap[0]:
				continue
			if band:
				var bb: int = base[cap[1]]
				for i in m / 2 - 1:
					var a := bb + i
					var c := bb + m - 2 - i
					if cap[1] == 0:
						tri(a, c, a + 1)
						tri(a, c + 1, c)
					else:
						tri(a, a + 1, c)
						tri(a, c, c + 1)
				continue
			var r: PackedVector3Array = rings[cap[1]]
			var ctr := Vector3.ZERO
			for p in r:
				ctr += p
			ctr /= r.size()
			var at: Vector2 = attr.call(ctr)
			var ci := add(ctr, int(at.x), grp, opt, at.y)
			var b0: int = base[cap[1]]
			for i in segs:
				var i2 := (i + 1) % m
				if cap[1] == 0:
					tri(ci, b0 + i2, b0 + i)
				else:
					tri(ci, b0 + i, b0 + i2)
		smooth(v0, i0, sum / (rings.size() * m) if hint == null else hint)

	## Quader mit eigenen Normalen je Seite (Blockfigur, Handy)
	func box(c: Vector3, size: Vector3, part: int, grp: int, opt: int, top_scale := Vector2.ONE) -> void:
		var h := size / 2.0
		var faces := [
			[Vector3.RIGHT, [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
			[Vector3.LEFT, [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
			[Vector3.UP, [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
			[Vector3.DOWN, [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
			[Vector3.BACK, [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
			[Vector3.FORWARD, [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
		]
		for f in faces:
			var q: Array = f[1]
			var ids := []
			var pts := []
			for corner in q:
				var cv: Vector3 = corner
				# oben schmaler oder breiter (Rumpf der Blockfigur)
				var sc := top_scale if cv.y > 0.0 else Vector2.ONE
				var p := c + Vector3(cv.x * h.x * sc.x, cv.y * h.y, cv.z * h.z * sc.y)
				pts.append(p)
				ids.append(add(p, part, grp, opt))
			var cr: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
			var fn := cr.normalized()
			if fn.dot((pts[0] + pts[2]) * 0.5 - c) < 0.0:
				fn = -fn  # nach außen
			for i in ids:
				n[i] = fn
			# im Uhrzeigersinn von außen gesehen
			if cr.dot(fn) > 0.0:
				tri(ids[0], ids[2], ids[1])
				tri(ids[0], ids[3], ids[2])
			else:
				tri(ids[0], ids[1], ids[2])
				tri(ids[0], ids[2], ids[3])

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var flags := 0
		if shape.size() == v.size() * 2:
			arr[Mesh.ARRAY_CUSTOM0] = shape
			flags = Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
		# Bewegung kommt aus dem Shader: Grenzen bis zur Reichweite der Arme (hoch 2,25 m, seitlich 0,95 m wie die Starterin
		# mit ausgestreckten Armen, vorn 0,7 m), damit erhobene Arme am Bildrand nicht weggeschnitten werden
		m.custom_aabb = AABB(Vector3(-0.95, -0.05, -0.7), Vector3(1.9, 2.3, 1.4))
		return m


## Punkt auf einem Querschnitt: a = 0 rechts (+X), PI/2 hinten (+Z), PI links, 3PI/2 vorn (-Z)
static func _se(a: float, rx: float, zf: float, zb: float, e: float) -> Vector2:
	var c := cos(a)
	var s := sin(a)
	return Vector2(rx * signf(c) * pow(absf(c), 2.0 / e), (zb if s > 0.0 else zf) * signf(s) * pow(absf(s), 2.0 / e))


## Ring um (cx, y, cz); n Punkte rundum oder als Bogen von a0 bis a1
static func _ring(y: float, rx: float, zf: float, zb: float, e: float, cx: float, cz: float, n: int,
		a0 := 0.0, a1 := TAU, closed := true) -> PackedVector3Array:
	var r := PackedVector3Array()
	for i in n:
		var a := a0 + (a1 - a0) * float(i) / (n if closed else n - 1)
		var p := _se(a, rx, zf, zb, e)
		r.append(Vector3(cx + p.x, y, cz + p.y))
	return r


## Kopf-Querschnitt an beliebiger Höhe (weich zwischen den Zeilen von HEAD)
static func _head_sec(y: float) -> Array:
	var i := 0
	while i < HEAD.size() - 2 and y > HEAD[i + 1][0]:
		i += 1
	var r1: Array = HEAD[i]
	var r2: Array = HEAD[i + 1]
	var t := smoothstep(r1[0], r2[0], y)
	var out := []
	for k in range(1, 6):
		out.append(lerpf(r1[k], r2[k], t))
	return out


## Punkt auf der Kopfoberfläche (Höhe y, Winkel a), um off vom Kopfmittelpunkt weg nach außen geschoben
static func _head_pt(y: float, a: float, off: float) -> Vector3:
	var top: float = HEAD[HEAD.size() - 1][0]
	var p: Vector3
	if y > top:
		# Scheitel: Kugelkappe über dem obersten Ring
		var s := _head_sec(top)
		var q := _se(a, s[0], s[1], s[2], s[3])
		var f := clampf((y - top) / 0.004, 0.0, 1.0)
		p = Vector3(q.x * (1.0 - f), y, s[4] + q.y * (1.0 - f))
	else:
		var s := _head_sec(y)
		var q := _se(a, s[0], s[1], s[2], s[3])
		p = Vector3(q.x, y, s[4] + q.y)
	var c := Vector3(0.0, 1.628, 0.004)
	return p + (p - c).normalized() * off


## Abstand der Rumpfoberfläche vorn (front) oder hinten bei (x, y), für Gurte und Taschen
static func _torso_z(x: float, y: float, front: bool) -> float:
	var i := 0
	while i < TORSO.size() - 2 and y > TORSO[i + 1][0]:
		i += 1
	var r1: Array = TORSO[i]
	var r2: Array = TORSO[i + 1]
	var t := clampf((y - r1[0]) / (r2[0] - r1[0]), 0.0, 1.0)
	var rx := lerpf(r1[1], r2[1], t)
	var dz := lerpf(r1[2] if front else r1[3], r2[2] if front else r2[3], t)
	var e := lerpf(r1[4], r2[4], t)
	var u := clampf(absf(x) / rx, 0.0, 1.0)
	var z := dz * pow(maxf(1.0 - pow(u, e), 0.0), 1.0 / e)
	return -z if front else z


## Rumpf: unten Becken, über der Taille Brustkorb (weich überblendet), außen an den Schultern ein Teil Oberarm
static func _torso_attr(p: Vector3) -> Vector2:
	if absf(p.x) > 0.125 and p.y > 1.33:
		var k := 0.22 * smoothstep(0.125, 0.172, absf(p.x)) * smoothstep(1.33, 1.42, p.y)
		return Vector2(P_ARM_R if p.x > 0.0 else P_ARM_L, k)
	if p.y < 0.965:
		return Vector2(P_HIPS, 1.0)
	return Vector2(P_BODY, smoothstep(0.965, 1.12, p.y))


## Arm: oben dreht die Schulter nur anteilig mit, um den Ellbogen geht der Unterarm weich in den Oberarm über
static func _arm_attr(p: Vector3) -> Vector2:
	var s := signf(p.x)
	if p.y > 1.155:
		return Vector2(P_ARM_R if s > 0.0 else P_ARM_L, lerpf(0.3, 1.0, 1.0 - smoothstep(1.33, 1.45, p.y)))
	return Vector2(P_FORE_R if s > 0.0 else P_FORE_L, 1.0 - smoothstep(1.06, 1.155, p.y))


## Bein: oben in der Hüfte anteilig, ums Knie weich in den Oberschenkel
static func _leg_attr(p: Vector3) -> Vector2:
	var s := signf(p.x)
	if p.y > 0.545:
		return Vector2(P_LEG_R if s > 0.0 else P_LEG_L, lerpf(0.35, 1.0, 1.0 - smoothstep(0.8, 0.92, p.y)))
	return Vector2(P_SHIN_R if s > 0.0 else P_SHIN_L, 1.0 - smoothstep(0.45, 0.545, p.y))


static func _detail_mesh(sticks: bool) -> ArrayMesh:
	var b := Mb.new()
	var head1 := func(_p: Vector3) -> Vector2: return Vector2(P_HEAD, 1.0)
	# Rumpf mit Becken: 20 Seiten, unten geschlossen, oben geht der Hals weiter
	var rings := []
	for row in TORSO:
		rings.append(_ring(row[0], row[1], row[2], row[3], row[4], 0.0, 0.0, TORSO_N))
	b.loft(rings, _torso_attr, G_TORSO, O_ALL, true, true, false, Vector3(0, 1.15, 0))
	# Hals: unten im Rumpf, oben im Kopf; biegt sich weich mit dem Nicken
	var neck0 := b.v.size()
	rings = []
	for r in [[1.44, 0.058, 0.010], [1.48, 0.057, 0.012], [1.52, 0.055, 0.014], [1.556, 0.054, 0.016],
			[1.6, 0.050, 0.018]]:
		rings.append(_ring(r[0], r[1], r[1], r[1] * 1.04, 2.0, 0.0, r[2], 10))
	b.loft(rings, func(p: Vector3) -> Vector2: return Vector2(P_HEAD, smoothstep(1.47, 1.585, p.y)), G_SKIN, O_ALL)
	var neck1 := b.v.size()
	# Kopf: 16 Seiten, Kinn und Scheitel geschlossen
	rings = []
	for row in HEAD:
		rings.append(_ring(row[0], row[1], row[2], row[3], row[4], 0.0, row[5], 16))
	b.loft(rings, head1, G_SKIN, O_ALL, true, true, true, Vector3(0, 1.63, 0.0))
	# Nase: schmaler Keil auf der Gesichtsmitte
	var v0 := b.v.size()
	var i0 := b.idx.size()
	var nose := [Vector3(0, 1.643, -0.1), Vector3(-0.009, 1.632, -0.1), Vector3(0.009, 1.632, -0.1),
		Vector3(0, 1.601, -0.124), Vector3(-0.016, 1.594, -0.102), Vector3(0.016, 1.594, -0.102), Vector3(0, 1.59, -0.108)]
	for p in nose:
		b.add(p, P_HEAD, G_SKIN, O_ALL)
	for t in [[1, 0, 3], [0, 2, 3], [1, 3, 4], [2, 5, 3], [4, 3, 6], [3, 5, 6]]:
		b.tri(v0 + t[0], v0 + t[1], v0 + t[2])
	b.smooth(v0, i0, Vector3(0, 1.615, -0.06))
	# Ohren: flache Muscheln an den Kopfseiten
	for s in [-1.0, 1.0]:
		rings = []
		for k in 3:
			var t := float(k + 1) / 4.0
			var yy := 1.626 + 0.029 * cos(PI * t)
			var w := sin(PI * t)
			rings.append(_ring(yy, 0.013 * w, 0.019 * w, 0.017 * w, 2.0, s * 0.0745, 0.014, 6))
		rings.reverse()
		b.loft(rings, head1, G_SKIN, O_ALL, true, true, true, Vector3(s * 0.06, 1.626, 0.014))
	# Arme mit Hand (ein Stück: kein Absatz am Handgelenk), Daumen vorn an der Handfläche
	for s in [-1.0, 1.0]:
		rings = []
		for row in ARM:
			rings.append(_ring(row[0], row[1], row[2], row[2], 2.0, s * row[3], row[4], ARM_N))
		b.loft(rings, _arm_attr, G_ARM, O_ALL, true, true, true, Vector3(s * 0.205, 1.1, 0.0))
		rings = []
		for r in [[0.836, 0.0105, 0.214, -0.019], [0.816, 0.0105, 0.209, -0.031], [0.797, 0.009, 0.205, -0.037],
				[0.784, 0.007, 0.204, -0.038]]:
			rings.append(_ring(r[0], r[1], r[1], r[1], 2.0, s * r[2], r[3], 6))
		b.loft(rings, _arm_attr, G_SKIN, O_ALL, true, false, true, Vector3(s * 0.222, 0.8, -0.01))
		if sticks:
			rings = [_ring(0.8, 0.014, 0.014, 0.014, 2.0, s * 0.214, -0.006, 6), _ring(0.53, 0.014, 0.014, 0.014, 2.0, s * 0.214, -0.006, 6)]
			b.loft(rings, func(_p: Vector3) -> Vector2: return Vector2(P_FORE_R if s > 0.0 else P_FORE_L, 1.0),
				G_GLOW, O_STICKS, true, true, true)
	# Beine und Schuhe
	for s in [-1.0, 1.0]:
		rings = []
		for row in LEG:
			rings.append(_ring(row[0], row[1], row[2], row[2], 2.0, s * row[3], row[4], LEG_N))
		b.loft(rings, _leg_attr, G_LEG, O_ALL, true, false, false, Vector3(s * 0.095, 0.5, 0.0))
		var foot := P_FOOT_R if s > 0.0 else P_FOOT_L
		rings = []
		for row in SHOE:
			var r := PackedVector3Array()
			for i in SHOE_N:
				var a := TAU * float(i) / SHOE_N
				var c := cos(a)
				var sn := sin(a)
				var e := 2.2 if sn > 0.0 else 5.0  # oben rund, unten flache Sohle
				var hh: float = (row[3] - row[2]) * 0.5
				r.append(Vector3(s * row[4] + row[1] * signf(c) * pow(absf(c), 2.0 / e), row[2] + hh + hh * signf(sn) * pow(absf(sn), 2.0 / e), row[0]))
			rings.append(r)
		b.loft(rings, func(p: Vector3) -> Vector2: return Vector2(foot, 1.0 - 0.5 * smoothstep(0.06, 0.104, p.y)),
			G_SHOE, O_ALL, true, true, true, Vector3(s * 0.1, 0.04, -0.06))
	_blend_hips(b)
	_blend_shoulders(b)
	_hair(b)
	_clothes(b)
	_shape_all(b, neck0, neck1)
	return b.commit()


## Becken und Oberschenkel schneiden sich an der Hüfte; dort zeigen ihre Normalen in verschiedene Richtungen, die
## Schnittlinie sähe zackig aus. Beide Flächen bekommen nahe der Hüfte eine gemeinsame, gemittelte Normale.
static func _blend_hips(b: Mb) -> void:
	for i in b.v.size():
		var p := b.v[i]
		var g := int(b.uv[i].y)
		var part := int(b.uv[i].x)
		if p.y < 0.78 or p.y > 0.95 or absf(p.x) < 0.03:
			continue
		var w := 1.0 - absf(p.y - 0.865) / 0.085
		if (g == G_TORSO and part == P_HIPS) or (g == G_LEG and (part == P_LEG_L or part == P_LEG_R)):
			var s := signf(p.x)
			var hip := Vector3(p.x * 0.6 + s * 0.04, 0.0, p.z).normalized()
			b.n[i] = b.n[i].lerp(hip, clampf(w, 0.0, 1.0) * 0.8).normalized()


## Schulter: Rumpf und Oberarmkuppe treffen sich mit einer Kerbe; nahe der Schulter zeigen beide Normalen weich
## vom Schulterinneren weg, so wirkt die Schulter rund statt wie ein angesetztes Polster
static func _blend_shoulders(b: Mb) -> void:
	for i in b.v.size():
		var p := b.v[i]
		var g := int(b.uv[i].y)
		if not (g == G_TORSO or g == G_ARM) or p.y < 1.33 or absf(p.x) < 0.11:
			continue
		var s := signf(p.x)
		var w := smoothstep(1.33, 1.4, p.y) * smoothstep(0.11, 0.16, absf(p.x)) * (1.0 - smoothstep(0.215, 0.245, absf(p.x)))
		var rn := (p - Vector3(s * 0.12, 1.32, 0.004)).normalized()
		b.n[i] = b.n[i].lerp(rn, w * 0.6).normalized()


## Formdaten je Ecke für die Statur im Shader (CUSTOM0, zwei Floats; halbe Floats zeigt der Compatibility-Renderer
## falsch): was nur von der Ruhelage abhängt, wird hier einmal gerechnet, der Shader mischt nur noch.
##   Rumpf, Jacke, Rock, Taschen: x Breitenzone (0 Hüfte, 1 Taille, 2 Brust, 3 Schultern),
##     y = 2 * Bauch (in 1/127) + Brust vorn bzw. Gesäß hinten (0..1)
##   Arm, Bein: xy Abstand zur Achse (x, z)
##   Kopf: x Merkmale (1 Hals, 2 Haaransatz vorn, 4 Bartgegend)
static func _shape_all(b: Mb, neck0: int, neck1: int) -> void:
	b.shape.resize(b.v.size() * 2)
	for i in b.v.size():
		var p := b.v[i]
		var part := int(b.uv[i].x)
		var grp := int(b.uv[i].y)
		var opt := int(b.uv2[i].x)
		var c := Vector2.ZERO
		if grp in [G_TORSO, G_JACKET, G_SKIRT, G_BAG, G_HOOD]:
			c.x = smoothstep(0.92, 1.06, p.y) + smoothstep(1.08, 1.22, p.y) + smoothstep(1.3, 1.42, p.y)
			var belly := 0.0
			var bump := 0.0
			if p.z < 0.0:
				if p.y > 0.9 and p.y < 1.26:
					belly = exp(-p.x * p.x / 0.014 - pow(p.y - 1.08, 2.0) / 0.012)
				var bx := absf(p.x) - 0.072
				if p.y > 1.14 and p.y < 1.36:
					bump = exp(-bx * bx / 0.0022 - pow(p.y - 1.245, 2.0) / 0.0028)
			elif p.y < 1.02:
				bump = exp(-p.x * p.x / 0.014 - pow(p.y - 0.9, 2.0) / 0.006)
			c.y = 2.0 * roundf(belly * 127.0) + minf(bump, 0.999)
		elif grp == G_ARM:
			c = Vector2(p.x - signf(p.x) * (0.172 + (1.44 - p.y) * 0.074), p.z - 0.005)
		elif grp == G_LEG:
			c = Vector2(p.x - signf(p.x) * 0.095, p.z + 0.002)
		elif part == P_HEAD:
			var neck := i >= neck0 and i < neck1
			if neck:
				c.x += 1.0
			if opt == O_HAIR_TOP and p.z < -0.03 and p.y < 1.705:
				c.x += 2.0
			if grp == G_SKIN and not neck and p.y > 1.51 and p.y < 1.6 and p.z < 0.02:
				c.x += 4.0
		b.shape[i * 2] = c.x
		b.shape[i * 2 + 1] = c.y


## Frisuren und Kopfbedeckungen, alle an die Kopfform angelegt
static func _hair(b: Mb) -> void:
	var head1 := func(_p: Vector3) -> Vector2: return Vector2(P_HEAD, 1.0)
	var front := 1.5 * PI
	# kurze Haare oben: Haaransatz vorn an der Stirn, an den Seiten über den Ohren, hinten bis zum Hinterkopf
	var rings := []
	for t in [0.03, 0.16, 0.36, 0.6, 0.84, 1.0]:
		var r := PackedVector3Array()
		for i in 16:
			var a := TAU * float(i) / 16.0
			var d := absf(wrapf(a - front, -PI, PI))  # 0 vorn, PI hinten
			var edge := 1.695 - 0.02 * smoothstep(0.2, 0.6, d) - 0.013 * smoothstep(0.6, 1.5, d) - 0.022 * smoothstep(1.6, 2.8, d)
			var y := lerpf(1.7475, edge, t)
			r.append(_head_pt(y, a, 0.004 + 0.012 * pow(1.0 - t, 0.7)))
		rings.append(r)
	b.loft(rings, head1, G_HAIR, O_HAIR_TOP, true, true, false, Vector3(0, 1.63, 0.004))
	# Nacken: hinten unter Kappe und Mütze sichtbar, vor den Ohren kurze Koteletten
	rings = []
	for t in [0.0, 0.4, 0.75, 1.0]:
		var r := PackedVector3Array()
		for i in 13:
			var a := -0.32 + (PI + 0.64) * float(i) / 12.0
			var d := absf(a - PI * 0.5)  # 0 hinten Mitte
			var edge := lerpf(1.585, 1.622, smoothstep(0.6, 1.7, d))
			var y := lerpf(1.672, edge, t)
			r.append(_head_pt(y, a, 0.0075 - 0.0045 * t))
		rings.append(r)
	b.loft(rings, head1, G_HAIR, O_HAIR_NAPE, false, false, false, Vector3(0, 1.62, 0.0))
	# lange Haare: dicker Vorhang bis auf den Rücken, seitlich am Gesicht vorbei; unten folgt er dem Rumpf
	rings = []
	var lv := [[1.672, 0.55, 0.0], [1.632, 0.5, 0.0], [1.58, 0.42, 0.008], [1.52, 0.3, 0.014], [1.46, 0.1, 0.02],
		[1.405, -0.12, 0.024], [1.37, -0.42, 0.022]]
	for row in lv:
		var y: float = row[0]
		var ext: float = row[1]
		var back: float = row[2]
		var hy := maxf(y, 1.632)
		var s := _head_sec(hy)
		var r := PackedVector3Array()
		var n := 7
		var outer := []
		var inner := []
		for i in n:
			var a := -ext + (PI + 2.0 * ext) * float(i) / (n - 1)
			var q := _se(a, s[0], s[1], s[2], s[3])
			var c := Vector2(0.0, s[4])
			var dir := q.normalized()
			var p := c + q + dir * 0.019
			# unterhalb des Kopfes fällt das Haar gerade herab und legt sich hinten auf den Rücken
			var low := clampf((1.632 - y) / 0.27, 0.0, 1.0)
			p.y += back * 1.0 + low * 0.02 * maxf(sin(a), 0.0)
			p.x *= lerpf(1.0, 0.93, low)
			outer.append(Vector3(p.x, y, p.y))
			inner.append(Vector3(p.x - dir.x * 0.016, y, p.y - dir.y * 0.016))
		for p in outer:
			r.append(p)
		inner.reverse()
		for p in inner:
			r.append(p)
		rings.append(r)
	b.loft(rings, func(p: Vector3) -> Vector2: return Vector2(P_HEAD, smoothstep(1.47, 1.6, p.y)), G_HAIR, O_HAIR_LONG,
		true, true, true, Vector3(0, 1.55, 0.03), true)
	# Zopf: vom Hinterkopf schräg nach unten, mit Haargummi
	rings = []
	for r in [[1.668, 0.02, 0.098], [1.655, 0.027, 0.118], [1.62, 0.03, 0.132], [1.57, 0.026, 0.136], [1.52, 0.019, 0.128],
			[1.475, 0.01, 0.118]]:
		rings.append(_ring(r[0], r[1], r[1], r[1], 2.0, 0.0, r[2], 7))
	b.loft(rings, head1, G_HAIR, O_PONY, true, true, true, Vector3(0, 1.58, 0.12))
	rings = [_ring(1.661, 0.019, 0.019, 0.019, 2.0, 0.0, 0.108, 7), _ring(1.648, 0.021, 0.021, 0.021, 2.0, 0.0, 0.121, 7)]
	b.loft(rings, head1, G_CAP, O_PONY, true, false, false, Vector3(0, 1.655, 0.11))
	# Dutt oben am Hinterkopf
	rings = []
	for k in 5:
		var t := float(k + 1) / 6.0
		var w := sin(PI * t)
		rings.append(_ring(1.722 + 0.036 * cos(PI * t), 0.042 * w, 0.042 * w, 0.042 * w, 2.0, 0.0, 0.07, 8))
	rings.reverse()
	b.loft(rings, head1, G_HAIR, O_BUN, true, true, true, Vector3(0, 1.72, 0.07))
	# Kappe: Kuppel über dem Kopf, Schirm vorn (der Shader dreht sie bei manchen nach hinten)
	rings = []
	for t in [0.0, 0.25, 0.55, 0.8, 1.0]:
		var r := PackedVector3Array()
		for i in 12:
			var a := TAU * float(i) / 12.0
			var d := absf(wrapf(a - front, -PI, PI))
			var edge := 1.69 - 0.022 * smoothstep(0.3, 1.6, d) - 0.012 * smoothstep(1.6, 2.8, d)
			var y := lerpf(1.7475, edge, t * t * (3.0 - 2.0 * t) * 0.6 + t * 0.4)
			r.append(_head_pt(y, a, 0.017 - 0.004 * t))
		rings.append(r)
	b.loft(rings, head1, G_CAP, O_CAP, true, true, false, Vector3(0, 1.63, 0.004))
	rings = []
	for i in 9:
		var a := front - 0.95 + 1.9 * float(i) / 8.0
		var lim := cos((a - front) / 0.95 * PI * 0.5)
		var p_in := _head_pt(1.69, a, 0.014)
		var dir := Vector3(p_in.x, 0.0, p_in.z - 0.004).normalized()
		var p_out := p_in + dir * (0.012 + 0.07 * sqrt(lim)) + Vector3(0, -0.014 * lim, 0)
		var r := PackedVector3Array([p_in + Vector3(0, 0.003, 0), p_out + Vector3(0, 0.003, 0), p_out - Vector3(0, 0.004, 0), p_in - Vector3(0, 0.004, 0)])
		rings.append(r)
	b.loft(rings, head1, G_CAP, O_CAP, true, true, true, Vector3(0, 1.69, -0.02))
	# Mütze: weiche Kuppel bis über die Ohren, unten ein umgeschlagener Rand
	rings = []
	for t in [0.0, 0.2, 0.45, 0.7, 0.82, 0.82, 1.0]:
		var r := PackedVector3Array()
		var fold: bool = t > 0.81 and rings.size() >= 5
		for i in 12:
			var a := TAU * float(i) / 12.0
			var d := absf(wrapf(a - front, -PI, PI))
			var edge := 1.672 - 0.024 * smoothstep(0.4, 1.5, d) - 0.016 * smoothstep(1.6, 2.8, d)
			var y := lerpf(1.752, edge, t)
			r.append(_head_pt(y, a, (0.025 if fold else 0.019) + 0.012 * (1.0 - t) * (1.0 - t)))
		rings.append(r)
	b.loft(rings, head1, G_CAP, O_BEANIE, true, true, true, Vector3(0, 1.66, 0.004))


## Kleidung über dem Körper: Kapuze, offene Jacke mit Kragen, Rock, Rucksack, Umhängetasche, Handy
static func _clothes(b: Mb) -> void:
	# Kapuze des Hoodies: Wulst um den Nacken, hinten hängt sie auf den Rücken
	var rings := []
	for i in 9:
		var f := float(i) / 8.0
		var a := -0.55 + (PI + 1.1) * f
		var backness := maxf(sin(a), 0.0)
		var rad := Vector3(cos(a) * 0.088, 0.0, sin(a) * (0.1 if sin(a) > 0.0 else 0.07))
		var c := Vector3(0.0, lerpf(1.468, 1.452, backness), 0.012) + rad
		var out := Vector3(cos(a), 0.0, sin(a)).normalized()
		var rr := lerpf(0.022, 0.04, backness)
		var rv := lerpf(0.022, 0.05, backness)
		c += out * 0.012 * backness - Vector3(0, 0.022 * backness, 0)
		var r := PackedVector3Array()
		for k in 6:
			var th := TAU * float(k) / 6.0
			r.append(c + out * rr * cos(th) + Vector3(0, rv * sin(th), 0))
		rings.append(r)
	b.loft(rings, _torso_attr, G_HOOD, O_HOOD, true, true, true, Vector3(0, 1.42, 0.0))
	# offene Jacke: Hülle um den Rumpf, vorn offen, oben mit Kragen um den Hals
	rings = []
	var jrows := []
	for row in TORSO:
		if row[0] in [0.885, 0.945, 1.065, 1.135, 1.27, 1.33, 1.418, 1.448]:
			jrows.append(row)
	jrows.append([1.476, 0.088, 0.062, 0.072, 2.2])
	jrows.append([1.506, 0.08, 0.06, 0.07, 2.1])
	for row in jrows:
		var y: float = row[0]
		if y < 0.9:
			y = 0.905
		var gap := lerpf(0.26, 0.17, smoothstep(0.95, 1.4, y)) + (0.25 if y > 1.47 else 0.0)
		var flare := 0.01 * (1.0 - smoothstep(0.9, 1.05, y))
		rings.append(_ring(y, row[1] + 0.014 + flare, row[2] + 0.017 + flare, row[3] + 0.015 + flare, row[4],
			0.0, 0.0, 15, 1.5 * PI + gap, 3.5 * PI - gap, false))
	b.loft(rings, _torso_attr, G_JACKET, O_JACKET, false, false, false, Vector3(0, 1.2, 0.0))
	# Rock: vom Bund über die Hüfte bis übers Knie, leicht ausgestellt
	rings = []
	for row in [[1.02, 0.161, 0.104, 0.095, 2.6], [0.95, 0.176, 0.101, 0.113, 2.5], [0.84, 0.186, 0.113, 0.128, 2.4],
			[0.7, 0.197, 0.128, 0.143, 2.3], [0.585, 0.206, 0.139, 0.154, 2.2]]:
		rings.append(_ring(row[0], row[1], row[2], row[3], row[4], 0.0, 0.0, 12))
	b.loft(rings, _torso_attr, G_SKIRT, O_SKIRT, true, false, false, Vector3(0, 0.85, 0.0))
	# Rucksack: abgerundeter Kasten auf dem Rücken, Gurte über die Schultern
	rings = []
	for r in [[1.055, 0.115, 0.05], [1.075, 0.135, 0.065], [1.33, 0.135, 0.065], [1.375, 0.12, 0.055], [1.392, 0.08, 0.035]]:
		rings.append(_ring(r[0], r[1], r[2], r[2], 4.0, 0.0, 0.172, 8))
	b.loft(rings, _torso_attr, G_BAG, O_BACKPACK, true, true, true, Vector3(0, 1.22, 0.17))
	for s in [-1.0, 1.0]:
		var path := []
		for q in [[0.075, 1.36, false], [0.088, 1.43, false], [0.1, 1.462, false], [0.1, 1.462, true], [0.1, 1.42, true],
				[0.1, 1.34, true], [0.105, 1.2, true]]:
			var x: float = q[0]
			var y: float = q[1]
			var fr: bool = q[2]
			var z := _torso_z(x, y, fr)
			if y > 1.45:
				z = -0.03 if fr else 0.035
			path.append(Vector3(s * x, y + (0.008 if y > 1.45 else 0.0), z + (-0.008 if fr else 0.008)))
		_strip(b, path, 0.019, G_BAG, O_BACKPACK)
	# Umhängetasche links an der Hüfte, Gurt quer über Brust und Rücken zur rechten Schulter
	rings = []
	for r in [[0.885, 0.026, 0.1], [0.895, 0.032, 0.11], [1.035, 0.032, 0.11], [1.045, 0.024, 0.098]]:
		rings.append(_ring(r[0], r[1], r[2], r[2], 4.0, -0.188, -0.02, 10))
	b.loft(rings, _torso_attr, G_BAG, O_BAG, true, true, true, Vector3(-0.188, 0.96, -0.02))
	for fr in [true, false]:
		var path := []
		for k in 8:
			var f := float(k) / 7.0
			var x := lerpf(0.105, -0.17, f)
			var y := lerpf(1.462, 1.045, f)
			var z := _torso_z(x, y, fr) + (-0.008 if fr else 0.008)
			if y > 1.45:
				z = -0.03 if fr else 0.03
			path.append(Vector3(x, y + (0.008 if y > 1.45 else 0.0), z))
		_strip(b, path, 0.017, G_BAG, O_BAG)
	# Handy in der rechten Hand an der Handfläche, Bildschirm zur Handfläche hin (beim Filmen zum Gesicht)
	b.box(Vector3(0.198, 0.79, -0.008), Vector3(0.009, 0.145, 0.07), P_FORE_R, G_PHONE, O_PHONE)
	var v0 := b.v.size()
	var i0 := b.idx.size()
	for q in [Vector3(0.1932, 0.725, -0.038), Vector3(0.1932, 0.855, -0.038), Vector3(0.1932, 0.855, 0.022), Vector3(0.1932, 0.725, 0.022)]:
		b.add(q, P_FORE_R, G_SCREEN, O_PHONE)
	b.tri(v0, v0 + 1, v0 + 2)
	b.tri(v0, v0 + 2, v0 + 3)
	b.smooth(v0, i0, Vector3(0.198, 0.79, -0.008))


## Flaches Band entlang eines Pfades (Gurte), Breite w quer zum Pfad, Normale vom Körper weg
static func _strip(b: Mb, path: Array, w: float, grp: int, opt: int) -> void:
	var v0 := b.v.size()
	var i0 := b.idx.size()
	for k in path.size():
		var p: Vector3 = path[k]
		var t: Vector3 = (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
		var out := Vector3(0.0, 0.0, p.z).normalized() if absf(p.z) > 0.05 else Vector3(signf(p.x), 1.0, 0.0).normalized()
		var side := t.cross(out).normalized()
		for s in [-1.0, 1.0]:
			var q: Vector3 = p + side * s * w * 0.5
			var a := _torso_attr(q)
			b.add(q, int(a.x), grp, opt, a.y)
	for k in path.size() - 1:
		var a := v0 + k * 2
		b.tri(a, a + 1, a + 3)
		b.tri(a, a + 3, a + 2)
	b.smooth(v0, i0, Vector3(0, 1.3, 0))


## Blockfigur für die Ferne: gleiche Maße, Körperteile und Farbgruppen wie die nahe Figur, wenige Dreiecke
static func _far_mesh() -> ArrayMesh:
	var b := Mb.new()
	for s in [-1.0, 1.0]:
		var leg := P_LEG_R if s > 0.0 else P_LEG_L
		var shin := P_SHIN_R if s > 0.0 else P_SHIN_L
		var foot := P_FOOT_R if s > 0.0 else P_FOOT_L
		b.box(Vector3(s * 0.101, 0.045, -0.058), Vector3(0.094, 0.09, 0.27), foot, G_SHOE, O_ALL)
		b.box(Vector3(s * 0.098, 0.29, 0.006), Vector3(0.096, 0.42, 0.104), shin, G_LEG, O_ALL, Vector2(1.12, 1.08))
		b.box(Vector3(s * 0.094, 0.705, -0.004), Vector3(0.13, 0.45, 0.14), leg, G_LEG, O_ALL, Vector2(1.25, 1.2))
		var up := P_ARM_R if s > 0.0 else P_ARM_L
		var fo := P_FORE_R if s > 0.0 else P_FORE_L
		b.box(Vector3(s * 0.198, 1.29, 0.006), Vector3(0.085, 0.32, 0.09), up, G_ARM, O_ALL, Vector2(1.2, 1.15))
		b.box(Vector3(s * 0.214, 0.91, 0.002), Vector3(0.06, 0.43, 0.075), fo, G_ARM, O_ALL, Vector2(1.2, 1.1))
	b.box(Vector3(0, 0.905, 0.006), Vector3(0.32, 0.22, 0.19), P_HIPS, G_TORSO, O_ALL, Vector2(0.95, 0.95))
	b.box(Vector3(0, 1.235, 0.004), Vector3(0.29, 0.47, 0.19), P_BODY, G_TORSO, O_ALL, Vector2(1.2, 1.05))
	b.box(Vector3(0, 1.252, 0.004), Vector3(0.315, 0.43, 0.215), P_BODY, G_JACKET, O_JACKET, Vector2(1.18, 1.0))
	b.box(Vector3(0, 0.79, 0.006), Vector3(0.39, 0.42, 0.3), P_HIPS, G_SKIRT, O_SKIRT, Vector2(0.84, 0.75))
	b.box(Vector3(0, 1.625, -0.006), Vector3(0.15, 0.235, 0.19), P_HEAD, G_SKIN, O_ALL)
	# Haare oben (vorn bis an die Stirn), Nacken, lang über den Rücken, Zopf; Kappe und Mütze wie Haare oben
	b.box(Vector3(0, 1.716, 0.003), Vector3(0.164, 0.066, 0.212), P_HEAD, G_HAIR, O_HAIR_TOP)
	b.box(Vector3(0, 1.63, 0.084), Vector3(0.162, 0.13, 0.04), P_HEAD, G_HAIR, O_HAIR_NAPE)
	b.box(Vector3(0, 1.53, 0.086), Vector3(0.17, 0.3, 0.05), P_HEAD, G_HAIR, O_HAIR_LONG)
	b.box(Vector3(0, 1.58, 0.128), Vector3(0.05, 0.16, 0.05), P_HEAD, G_HAIR, O_PONY)
	b.box(Vector3(0, 1.72, 0.002), Vector3(0.17, 0.064, 0.218), P_HEAD, G_CAP, O_CAP)
	b.box(Vector3(0, 1.718, 0.002), Vector3(0.174, 0.076, 0.222), P_HEAD, G_CAP, O_BEANIE)
	b.box(Vector3(0, 1.22, 0.17), Vector3(0.26, 0.31, 0.12), P_BODY, G_BAG, O_BACKPACK)
	_shape_all(b, 0, 0)
	return b.commit()


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


## Gruppe aus Figuren an den Transformationen xfs (Blick = lokales -Z). modes: Liste möglicher Bewegungen.
## far: Sichtweite (0 = ohne Grenze). Liefert einen Knoten mit je Zelle zwei MultiMeshes (nah detailliert, fern als
## Blockfigur); set_mode() kann später umschalten.
static func crowd(parent: Node3D, xfs: Array, modes: Array, rng: RandomNumberGenerator, far := 0.0) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var mat := material()
	# Detaildichte Niedrig bis Ultra: 30 / 42 / 60 / 96 m
	var near := maxf(30.0, GameState.gv("detail")[2] * 1.2)
	var cells := {}
	for xf in xfs:
		var p: Vector3 = xf.origin
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(key):
			cells[key] = []
		# Größe: Männer 1,61–1,88 m, Frauen (im Shader 6 % kleiner) 1,51–1,77 m; Statur formt der Shader
		var s := rng.randf_range(0.925, 1.075)
		var b: Basis = xf.basis.scaled(Vector3(s, s, s))
		cells[key].append([Transform3D(b, p), SHIRTS[rng.randi() % SHIRTS.size()],
			Color(rng.randf(), rng.randf(), modes[rng.randi() % modes.size()] / 10.0, rng.randf())])
	for key in cells:
		var list: Array = cells[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh(0 if lod == 0 else 3)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				mm.set_instance_color(i, list[i][1])
				mm.set_instance_custom_data(i, list[i][2])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == 0:
				mmi.visibility_range_end = near
				mmi.visibility_range_end_margin = 4.0
			else:
				mmi.visibility_range_begin = near
				mmi.visibility_range_begin_margin = 4.0
				if far > 0.0:
					mmi.visibility_range_end = far
					mmi.visibility_range_end_margin = 20.0
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mmi)
	holder.set_meta("mat", mat)
	return holder


## Alle Figuren einer Gruppe auf eine Bewegung umstellen
static func set_mode(holder: Node3D, mode: int) -> void:
	for c in holder.get_children():
		if c is MultiMeshInstance3D:
			var mm: MultiMesh = c.multimesh
			for i in mm.instance_count:
				var cd := mm.get_instance_custom_data(i)
				cd.b = mode / 10.0
				mm.set_instance_custom_data(i, cd)


## Einzelne Figur mit eigenem Material (Starterin, Fans im Ziel). kind 2: mit Leuchtstäben.
## Die Werte gehen als Vector4 an den Shader: eine Color würde Godot als sRGB-Farbe in linear umrechnen, aus
## Bewegung 0,7 (Starterin) wurde so 0,45 (klatschen), die Starterin hob nie die Arme.
static func single(parent: Node3D, kind: int, mode: int, top: Color, skin: float, hair: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	var m := material()
	m.set_shader_parameter("custom", Vector4(skin, hair, mode / 10.0, randf()))
	m.set_shader_parameter("shirt", Vector3(top.r, top.g, top.b))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Bewegung einer einzelnen Figur umstellen (Fans im Ziel: erst rennen, dann tanzen oder klatschen)
static func set_single_mode(mi: MeshInstance3D, mode: int) -> void:
	var m := mi.material_override as ShaderMaterial
	var cd: Vector4 = m.get_shader_parameter("custom")
	cd.z = mode / 10.0
	m.set_shader_parameter("custom", cd)
