extends RefCounted
## Gelände zum Austoben (seit 2.39): umzäunte Flächen abseits der Straßen, auf denen man frei über Gras, Sand, Kies und
## Erde fährt, mit Kuppen, Rampen, Bunkern und Teichen. Bis 2.38 fuhr das Auto nur auf Straßen (Wände hielten es dort).
## Hier stehen Planung und Abfragen: Lage, Form, Höhe (Hügel, Kieshaufen, Bunker, Wall, Rampen), Untergrund, Wasser.
## Gebaut (Boden, Bäume, Gebäude, Zaun, Rampen, Schilder) wird in offroad_build.gd.
##
## Jede Fläche hängt über eine Ausfahrt an einer Querspange: ein Weg "ramp" im Autobahnstück (race["ramps"], mit
## "gelaende", 16 m breit wie zu den Städten) öffnet Wand und Leitplanke wie eine Stadtausfahrt, mit Ausfahrt-Schild.
## Am Ende der Ausfahrt liegt das Tor im Zaun. Innen rechnet jede Fläche in eigenen Koordinaten: s längs der Straße, t von der
## Straße weg, Ursprung in der Mitte des Tors (local/world). Die Höhe ist eine glatte Funktion aus Formen (base_h); die
## Rampen kommen als Stufe obendrauf (ground: "h" mit Rampe, "base" ohne), so gilt für Absprung, Flug und Landung
## dieselbe Logik wie auf der Straße (player_car._update_vertical).

const Track := preload("res://scripts/track_builder.gd")

const SKIRT := 26.0  # außerhalb des Zauns fällt das Gelände auf dieser Breite auf den Boden der Landschaft ab
const CELL := 24.0  # Raster für die schnelle Suche der Formen (m, in Flächenkoordinaten)
const ACCESS_HALF := 8.0  # Ausfahrt zum Gelände: breit wie zu den Städten (rechtwinklig von der Querspange, gut zu treffen)
const GATE_HALF := ACCESS_HALF + 0.3  # halbe Breite des Tors (Ausfahrt plus Wand)

static var areas: Array = []  # Flächen der geladenen Welt (world.gd setzt sie, im Rennen leer)

## Untergründe: Haftung (Anteil vom Asphalt), Rollwiderstand (m/s²), Bremse und Zug beim Anfahren (Anteile), lose (0..1:
## wie leicht das Heck kommt, wie sehr es staubt), Farbe von Staub und Spuren. Weniger Grip, aber nie unfahrbar.
const SURF := {
	"asphalt": {"grip": 1.0, "roll": 0.0, "brake": 1.0, "trac": 1.0, "loose": 0.0, "dust": Color(0.6, 0.6, 0.6), "mark": Color(0.025, 0.025, 0.03)},
	"gras": {"grip": 0.66, "roll": 0.8, "brake": 0.62, "trac": 0.8, "loose": 0.45, "dust": Color(0.46, 0.43, 0.33), "mark": Color(0.09, 0.11, 0.05)},
	"rasen": {"grip": 0.72, "roll": 0.5, "brake": 0.66, "trac": 0.84, "loose": 0.35, "dust": Color(0.48, 0.46, 0.36), "mark": Color(0.08, 0.13, 0.05)},
	"gruen": {"grip": 0.72, "roll": 0.45, "brake": 0.66, "trac": 0.84, "loose": 0.3, "dust": Color(0.48, 0.46, 0.36), "mark": Color(0.07, 0.12, 0.04)},
	"sand": {"grip": 0.52, "roll": 3.0, "brake": 0.5, "trac": 0.66, "loose": 0.85, "dust": Color(0.8, 0.72, 0.54), "mark": Color(0.45, 0.39, 0.27)},
	"kies": {"grip": 0.6, "roll": 1.3, "brake": 0.6, "trac": 0.74, "loose": 0.7, "dust": Color(0.62, 0.59, 0.53), "mark": Color(0.2, 0.19, 0.17)},
	"erde": {"grip": 0.68, "roll": 1.0, "brake": 0.68, "trac": 0.8, "loose": 0.6, "dust": Color(0.52, 0.42, 0.31), "mark": Color(0.16, 0.11, 0.07)},
	"schotter": {"grip": 0.8, "roll": 0.5, "brake": 0.8, "trac": 0.9, "loose": 0.4, "dust": Color(0.62, 0.6, 0.55), "mark": Color(0.27, 0.25, 0.22)},
}
## Untergrund je Art: Grund (Index 0) und die vier Farbkanäle des Bodens (rgba, offroad.gdshader); höherer Kanal gewinnt
const LAYERS := {"golf": ["gras", "rasen", "gruen", "sand", "schotter"], "kies": ["kies", "sand", "erde", "gras", "schotter"]}


# --- Planung ------------------------------------------------------------------------------------------------------

## Flächen planen (world_layout.build, nach den Autobahnstücken): beide an der nördlichsten Querspange, der Golfplatz
## am Stadtrand von Erfurt (gut 1,2 km vom Kreisel), die Kiesgrube draußen nahe dem Ring. Trägt die Ausfahrten in
## race["ramps"] des Stücks ein und hält Häuser und Wahrzeichen der Stücke von den Flächen fern (race["keepout"]).
static func plan(segments: Array) -> Array:
	var host: Dictionary = {}
	var best := 1e9
	for sg in segments:
		var race: Dictionary = sg["race"]
		if race.get("name", "") != "Querspange" or not race.get("gap_start", false):
			continue
		var p0: Vector3 = race["pts"][0]
		if p0.z < best:
			best = p0.z
			host = sg
	if host.is_empty():
		return []
	var race: Dictionary = host["race"]
	var curve := _host_curve(race)
	var out := []
	var golf := _golf()
	if _place(golf, race, curve, _d_at_radius(curve, 1180.0), 1.0):
		out.append(golf)
	var kies := _kies()
	if _place(kies, race, curve, 430.0, -1.0):
		out.append(kies)
	for a in out:
		_finish(a)
		# Häuser, Wahrzeichen und Plakate der Autobahnstücke in der Nähe nicht auf die Fläche (wie fremde Fahrbahnen)
		for sg in segments:
			if (sg["center"] as Vector3).distance_to(Vector3(a["o"].x, 0.0, a["o"].y)) > float(sg["radius"]) + 700.0:
				continue
			var ko: Array = sg["race"].get("keepout", [])
			for q in a["outline"]:
				ko.append({"pos": Vector3(q.x, 0.0, q.y), "r": SKIRT + 14.0, "ko": true})  # Zaun samt Randstreifen
			ko.append({"pos": Vector3(a["mid"].x, 0.0, a["mid"].y), "r": a["inner_r"], "ko": true})
			sg["race"]["keepout"] = ko
	return out


## Mittellinie eines Autobahnstücks wie in track_builder.begin (gleiche Tangenten, damit d dort dasselbe meint)
static func _host_curve(race: Dictionary) -> Curve3D:
	var pts: Array = race["pts"]
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var n := pts.size()
	for i in n:
		var t: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)) * 0.22
		c.add_point(pts[i], -t, t)
	return c


## Stelle auf dem Stück, die r vom Kreisel (Kartenmitte) entfernt ist
static func _d_at_radius(c: Curve3D, r: float) -> float:
	var L := c.get_baked_length()
	var bd := 0.0
	var be := 1e9
	var d := 0.0
	while d < L:
		var q := c.sample_baked(d)
		var e := absf(Vector2(q.x, q.z).length() - r)
		if e < be:
			be = e
			bd = d
		d += 5.0
	return bd


## Lage der Fläche: Tor gate_t neben der Mittellinie bei d (side: +1 rechts, -1 links in Fahrtrichtung des Stücks).
## Nur dort, wo die Straße flach ist (keine Kuppe, Ausfahrt auf Höhe 0): sonst die nächste flache Stelle bis 600 m weiter
## (die Kuppen der Querspangen sind zufällig; ändert sich die Welt, rückt die Fläche mit, statt zu fehlen).
static func _place(a: Dictionary, race: Dictionary, c: Curve3D, d0: float, side: float) -> bool:
	var L := c.get_baked_length()
	var d := -1.0
	for k in 25:
		var cand := d0 + (k + 1) / 2 * 50.0 * (1.0 if k % 2 == 1 else -1.0)
		if cand < 150.0 or cand > L - 150.0:
			continue
		var flat := true
		for cr in race.get("crests", []):
			if cand > float(cr[0]) * L - 60.0 and cand < float(cr[1]) * L + 60.0:
				flat = false
		for r in race["ramps"]:
			if absf(c.get_closest_offset(r["from"]) - cand) < 140.0:
				flat = false  # nicht an einer anderen Ausfahrt
		if flat:
			d = cand
			break
	if d < 0.0:
		push_warning("Gelände %s: keine flache Stelle für die Ausfahrt" % a["name"])
		return false
	var f := Track.frame_at(c, d)
	var fwd: Vector3 = f["fwd"]
	var right: Vector3 = f["right"]
	var pos: Vector3 = f["pos"]
	a["u"] = Vector2(fwd.x, fwd.z)
	a["v"] = Vector2(right.x, right.z) * side
	var gate_w: Vector3 = pos + right * side * float(a["gate_t"])
	# Tor liegt in Flächenkoordinaten bei (gate_s, 0): Ursprung so verschieben, dass es genau vor der Ausfahrt liegt
	var o: Vector2 = Vector2(gate_w.x, gate_w.z) - a["u"] * float(a["gate_s"])
	a["o"] = o
	a["exit_d"] = d
	var from := Vector3(pos.x, 0.0, pos.z)
	var end := Vector3(gate_w.x, 0.0, gate_w.z)
	race["ramps"].append({"k": -1, "from": from, "end": end, "name": a["exit"], "half": ACCESS_HALF, "gelaende": true})
	a["access"] = PackedVector2Array([Vector2(from.x, from.z), Vector2(end.x, end.z)])
	return true


# --- Golfplatz -------------------------------------------------------------------------------------------------------

## Golfplatz am Stadtrand von Erfurt: vier Bahnen mit Abschlag, Fairway, Grün mit Fahne und Bunkern, zwei Teiche,
## sanfte Hügel, Kuppen zum Abheben, Clubhaus mit Parkplatz und Golfcarts, ein Greenkeeper-Hof mit Erdhaufen und
## Rampen, Baumgruppen (mit festem Stamm). Rundherum Hecke und Zaun. Flächenkoordinaten: s -260..260, t 0..330.
static func _golf() -> Dictionary:
	var a := {"name": "Golfclub Eichenhain", "kind": "golf", "exit": "Golfplatz", "seed": 3901,
		"w": 520.0, "d": 330.0, "corner": 70.0, "wob": 8.0, "gate_s": -170.0, "gate_t": 74.0, "level": 1.0, "rise": 26.0,
		"prims": [], "shapes": [], "ponds": [], "ramps": [], "trees": [], "rocks": [], "builds": [], "knock": [], "lights": []}
	# Parkplatz hinter dem Tor, Clubhaus mit Terrasse, Golfcarts
	_box(a, 4, Vector2(-170, 36), Vector2(40, 21), 0.0, 5.0)
	_pad(a, Vector2(-170, 38), Vector2(56, 34), 0.0, 1.0, 0.75)
	_pad(a, Vector2(-212, 88), Vector2(34, 22), 0.0, 1.2, 0.7)
	_box(a, 4, Vector2(-208, 72), Vector2(20, 4.5), 0.0, 1.0)
	a["builds"].append({"k": "clubhaus", "c": Vector2(-214, 90), "size": Vector3(26.0, 7.0, 13.0), "a": 0.0})
	for i in 5:
		a["builds"].append({"k": "cart", "c": Vector2(-186.0 + i * 3.4, 74.0), "a": PI / 2.0, "size": Vector3(1.3, 1.8, 2.5)})
	# Wege: vom Parkplatz zum ersten Abschlag, vom letzten Grün zurück
	_line(a, 4, [Vector2(-150, 40), Vector2(-132, 58), Vector2(-122, 66)], 1.4)
	_line(a, 4, [Vector2(-186, 108), Vector2(-196, 96)], 1.4)
	# Bahn 1: Abschlag am Clubhaus, Fairway nach Osten zum Grün in der Mitte
	_hole(a, Vector2(-118, 70), [Vector2(-108, 80), Vector2(-56, 96), Vector2(0, 110), Vector2(50, 120)], 17.0,
		Vector2(82, 128), Vector2(15, 12), 0.3, [[Vector2(63, 110), Vector2(7, 4.5), 0.4], [Vector2(100, 145), Vector2(6.5, 5), -0.2],
		[Vector2(-28, 122), Vector2(9, 4.5), 0.2]])
	# Bahn 2: nach Norden hinauf, Dogleg
	_hole(a, Vector2(126, 92), [Vector2(130, 104), Vector2(160, 148), Vector2(196, 200), Vector2(208, 236)], 16.0,
		Vector2(214, 262), Vector2(13, 11), -0.2, [[Vector2(194, 272), Vector2(6, 5), 0.0], [Vector2(234, 250), Vector2(5, 6.5), 0.3],
		[Vector2(176, 166), Vector2(8, 4.5), 1.0]])
	# Bahn 3: lang zurück nach Westen, hinten am Zaun
	_hole(a, Vector2(176, 305), [Vector2(164, 300), Vector2(108, 287), Vector2(48, 284), Vector2(-12, 290)], 17.0,
		Vector2(-46, 293), Vector2(14, 12), 0.1, [[Vector2(-30, 313), Vector2(7, 4), 0.1], [Vector2(-64, 274), Vector2(6, 4.5), -0.5]])
	# Bahn 4: über den Westhang hinunter zum Grün am Clubhaus
	_hole(a, Vector2(-84, 258), [Vector2(-92, 246), Vector2(-138, 212), Vector2(-166, 172), Vector2(-176, 142)], 16.0,
		Vector2(-180, 122), Vector2(13, 11), 0.4, [[Vector2(-158, 112), Vector2(5, 6.5), 0.2], [Vector2(-201, 136), Vector2(5, 4), 0.6]])
	# Teiche (Wasser wie die Seen: wer hineinfährt, spritzt und wird zurückgesetzt)
	_pond(a, Vector2(-14, 205), Vector2(46, 27), 0.15, 0.55)
	_pond(a, Vector2(122, 204), Vector2(15, 6.5), -0.4, 0.6)
	# sanfte Hügel und Wellen im Fairway
	_hill(a, Vector2(-66, 160), Vector2(40, 28), 0.2, 3.0)
	_hill(a, Vector2(46, 168), Vector2(30, 22), 0.5, 2.4)
	_hill(a, Vector2(236, 150), Vector2(34, 46), 0.0, 4.5)
	_hill(a, Vector2(-214, 226), Vector2(40, 46), 0.3, 4.2)
	_hill(a, Vector2(84, 318), Vector2(60, 18), 0.0, 2.2)
	_hill(a, Vector2(-62, 98), Vector2(24, 16), 0.3, 0.8)
	_hill(a, Vector2(178, 196), Vector2(20, 18), 0.0, 0.9)
	_hill(a, Vector2(-120, 300), Vector2(46, 22), 0.2, 2.6)
	# Kuppen zum Abheben (rund, ab gut 60 km/h fliegt man)
	_hill(a, Vector2(150, 42), Vector2(16, 22), 0.0, 3.2)
	_hill(a, Vector2(44, 232), Vector2(13, 17), 0.3, 2.6)
	_hill(a, Vector2(-128, 168), Vector2(15, 14), 0.0, 2.8)
	# Greenkeeper-Hof am Zaun: Schotterfläche, Sand- und Erdhaufen, Rampen aus Erde und Holz
	_box(a, 4, Vector2(214, 44), Vector2(30, 22), 0.0, 6.0)
	_pad(a, Vector2(214, 44), Vector2(42, 32), 0.0, 1.0, 0.7)
	_pile(a, 3, Vector2(232, 60), Vector2(7, 7), 0.0, 2.4)
	_pile(a, 3, Vector2(242, 40), Vector2(5.5, 6), 0.0, 1.8)
	a["builds"].append({"k": "schuppen", "c": Vector2(206, 22), "size": Vector3(14.0, 4.5, 8.0), "a": 0.0})
	_ramp(a, Vector2(196, 66), Vector2(-0.18, 1.0), 6.0, 8.0, 1.7, "erde")
	# Sprung über den kleinen Teich: Stahlrampe, Anlauf über den Rough
	_ramp(a, Vector2(111.5, 179.2), Vector2(0.39, 0.92), 7.0, 10.0, 2.8, "stahl")
	_pad(a, Vector2(110, 176), Vector2(9, 18), -0.4, 1.0, 0.6)
	# Holzrampe im Westen, über die Kuppe am Hang
	_ramp(a, Vector2(-108, 128), Vector2(-0.45, 0.89), 6.0, 8.0, 1.6, "holz")
	_pad(a, Vector2(-104, 122), Vector2(10, 14), -0.45, 1.0, 0.6)
	# Baumgruppen (fest): am Zaun zur Straße, um das Clubhaus, zwischen den Bahnen
	_grove(a, Vector2(-30, 24), Vector2(90, 12), 0.0, 16)
	_grove(a, Vector2(-236, 140), Vector2(14, 40), 0.0, 7)
	_grove(a, Vector2(-112, 196), Vector2(22, 16), 0.0, 6)
	_grove(a, Vector2(88, 70), Vector2(24, 12), 0.0, 6)
	_grove(a, Vector2(244, 214), Vector2(12, 30), 0.0, 6)
	_grove(a, Vector2(-170, 312), Vector2(60, 10), 0.0, 10)
	_grove(a, Vector2(222, 312), Vector2(28, 10), 0.0, 6)
	_grove(a, Vector2(10, 150), Vector2(18, 10), 0.0, 4)
	_grove(a, Vector2(-160, 258), Vector2(18, 16), 0.0, 5)
	_grove(a, Vector2(0, 165), Vector2(250, 160), 0.0, 34)  # einzelne Bäume im Rough
	# Laternen am Parkplatz (nachts Licht)
	a["lights"].append(Vector2(-196, 30))
	a["lights"].append(Vector2(-144, 30))
	return a


## Golfbahn: Abschlag (Rechteck), Fairway (Linienzug), Grün (Ellipse) mit Fahne, Bunker (Mulden mit Sand)
static func _hole(a: Dictionary, tee: Vector2, fairway: Array, fw: float, green: Vector2, gr: Vector2, ga: float, bunkers: Array) -> void:
	_box(a, 2, tee, Vector2(6, 4.5), (fairway[0] - tee).angle() + PI / 2.0, 1.5)
	_pad(a, tee, Vector2(9, 8), 0.0, a["level"] + 0.35, 0.8)
	_line(a, 1, fairway, fw)
	_shape_ell(a, 1, green, gr * 1.45, ga, 2.0)
	_shape_ell(a, 2, green, gr, ga, 1.2)
	a["knock"].append({"k": "fahne", "c": green + Vector2(gr.x * 0.25, -gr.y * 0.2)})
	for b in bunkers:
		_bunker(a, b[0], b[1], b[2])


static func _bunker(a: Dictionary, c: Vector2, r: Vector2, ang: float) -> void:
	_shape_ell(a, 3, c, r, ang, 1.0)
	a["prims"].append({"k": "dip", "c": c, "r": r * 1.25, "a": ang, "h": 0.75})


# --- Kiesgrube -----------------------------------------------------------------------------------------------------

## Kiesgrube bei Moosbrunn: Grubensohle aus Kies, rundherum ein steiler Wall (11 m, innen fast 40°, oben eine breite
## Krone bis zum Zaun), Einfahrt durch einen Schnitt im Wall. Innen Kieshaufen und Sandhaufen (oben spitz: wer schnell
## drüberfährt, fliegt), ein Erdwall, eine Buckelpiste, ein Baggersee, vier Rampen, Findlinge, Bagger, Radlader,
## Muldenkipper, Förderband, Baucontainer. Flächenkoordinaten: s -190..190, t 0..300.
static func _kies() -> Dictionary:
	var a := {"name": "Kiesgrube Moosbrunn", "kind": "kies", "exit": "Kieswerk", "seed": 3902,
		"w": 380.0, "d": 300.0, "corner": 60.0, "wob": 6.0, "gate_s": -60.0, "gate_t": 74.0, "level": 1.0, "rise": 26.0,
		"wall": {"h": 11.0, "crest": 22.0, "run": 20.0, "cut": 14.0, "flank": 22.0},
		"prims": [], "shapes": [], "ponds": [], "ramps": [], "trees": [], "rocks": [], "builds": [], "knock": [], "lights": []}
	# Wallhänge Erde, außen und auf der Krone Gras; Fahrspuren Schotter
	a["shapes"].append({"ch": 2, "k": "band", "in": -46.0, "out": -21.0})
	a["shapes"].append({"ch": 3, "k": "band", "in": -21.5, "out": 40.0})
	_line(a, 4, [Vector2(-60, -2), Vector2(-60, 40), Vector2(-40, 70), Vector2(10, 96), Vector2(60, 110)], 5.0)
	_line(a, 4, [Vector2(-60, 40), Vector2(-100, 64), Vector2(-120, 100)], 4.0)
	# Kieshaufen und Sandhaufen
	_pile(a, 0, Vector2(62, 152), Vector2(12, 12), 0.0, 8.0)
	_pile(a, 0, Vector2(150, 202), Vector2(11, 11), 0.0, 7.0)
	_pile(a, 0, Vector2(-108, 214), Vector2(14, 14), 0.0, 9.5)
	_pile(a, 1, Vector2(132, 158), Vector2(8, 8), 0.0, 5.0)
	_pile(a, 1, Vector2(-122, 124), Vector2(7.5, 7.5), 0.0, 4.5)
	_pile(a, 1, Vector2(-16, 220), Vector2(9, 7), 0.6, 4.0)
	# Erdwall quer in der Grube (Kuppe zum Abheben) und Buckelpiste
	_hill(a, Vector2(-34, 168), Vector2(32, 9), 0.35, 3.2)
	_shape_ell(a, 2, Vector2(-34, 168), Vector2(36, 12), 0.35, 2.0)
	for i in 6:
		var bc := Vector2(-6.0 + i * 13.0, 250.0 - i * 3.0)
		_hill(a, bc, Vector2(6.5, 6.5), 0.0, 1.1)
	_shape_ell(a, 2, Vector2(28, 242), Vector2(46, 12), -0.23, 3.0)
	# Baggersee: lang und schmal, quer zur Rampe (Sprung über gut 25 m Wasser)
	_pond(a, Vector2(100, 100), Vector2(32, 9), 0.0, 0.45)
	# Rampen: gleich hinter der Einfahrt, über den Erdwall, über den Baggersee, Holzschanze im Westen
	_ramp(a, Vector2(-30, 84), Vector2(0.12, 0.99), 8.0, 10.0, 2.4, "stahl")
	_pad(a, Vector2(-28, 96), Vector2(14, 26), 0.12, 1.0, 0.6)
	_ramp(a, Vector2(-50, 122), Vector2(-0.34, 0.94), 7.0, 8.0, 1.8, "erde")
	_pad(a, Vector2(-51, 124), Vector2(10, 12), -0.35, 1.0, 0.6)
	_ramp(a, Vector2(100, 126), Vector2(0.0, -1.0), 8.0, 10.0, 2.8, "stahl")
	_pad(a, Vector2(100, 126), Vector2(12, 16), 0.0, 1.0, 0.6)
	_ramp(a, Vector2(-112, 152), Vector2(0.5, 0.87), 7.0, 9.0, 2.2, "holz")
	_pad(a, Vector2(-110, 156), Vector2(10, 14), 0.52, 1.0, 0.6)
	# Findlinge am Rand der Sohle
	for r in [[Vector2(-146, 150), 1.4], [Vector2(-145, 182), 1.0], [Vector2(158, 120), 1.6], [Vector2(84, 258), 1.2],
			[Vector2(-40, 128), 1.1], [Vector2(162, 236), 1.3], [Vector2(-150, 64), 1.5], [Vector2(46, 72), 0.9]]:
		a["rocks"].append([r[0], r[1]])
	# Maschinen und Baustelle (auf der Sohle, nicht im Wall)
	a["builds"].append({"k": "bagger", "c": Vector2(-80, 240), "a": -2.4})
	a["builds"].append({"k": "radlader", "c": Vector2(40, 206), "a": 0.6})
	a["builds"].append({"k": "kipper", "c": Vector2(18, 58), "a": 0.1})
	a["builds"].append({"k": "foerderband", "c": Vector2(122, 236), "a": 0.0})
	a["builds"].append({"k": "container", "c": Vector2(-124, 64), "a": 0.0})
	_pad(a, Vector2(-124, 66), Vector2(18, 12), 0.0, 1.0, 0.7)
	a["knock"].append({"k": "dixi", "c": Vector2(-108, 60)})
	for i in 4:
		a["knock"].append({"k": "bake", "c": Vector2(-48.0 + i * 2.2, 46.0 + i * 1.0)})
	for i in 5:
		a["knock"].append({"k": "kegel", "c": Vector2(-14.0 + i * 4.0, 64.0)})
	a["lights"].append(Vector2(-100, 74))
	a["lights"].append(Vector2(40, 86))
	return a


# --- Bausteine der Planung --------------------------------------------------------------------------------------------

static func _hill(a: Dictionary, c: Vector2, r: Vector2, ang: float, h: float) -> void:
	a["prims"].append({"k": "hill", "c": c, "r": r, "a": ang, "h": h})


## Haufen (Kegel mit runder Spitze und weichem Fuß); ch: Farbkanal (0 = Grund)
static func _pile(a: Dictionary, ch: int, c: Vector2, r: Vector2, ang: float, h: float) -> void:
	a["prims"].append({"k": "pile", "c": c, "r": r, "a": ang, "h": h})
	if ch > 0:
		_shape_ell(a, ch, c, r * 1.12, ang, 1.5)


## Ebene Fläche auf Höhe level (core: innerer Anteil, der ganz eben ist)
static func _pad(a: Dictionary, c: Vector2, r: Vector2, ang: float, level: float, core: float) -> void:
	a["prims"].append({"k": "pad", "c": c, "r": r, "a": ang, "level": level, "core": core})


static func _pond(a: Dictionary, c: Vector2, r: Vector2, ang: float, level: float) -> void:
	a["ponds"].append({"c": c, "r": r, "a": ang, "level": level, "wob": minf(r.x, r.y) * 0.12})
	a["prims"].append({"k": "dip", "c": c, "r": r * 1.35, "a": ang, "h": float(a["level"]) - level + 0.9})


static func _ramp(a: Dictionary, c: Vector2, dir: Vector2, w: float, l: float, h: float, look: String) -> void:
	a["ramps"].append({"c": c, "d": dir.normalized(), "w": w, "l": l, "h": h, "look": look})


## Baumgruppe: n Bäume in der Ellipse (Lage zufällig, aber fest, beim Abschluss geprüft)
static func _grove(a: Dictionary, c: Vector2, r: Vector2, ang: float, n: int) -> void:
	a["trees"].append({"c": c, "r": r, "a": ang, "n": n})


static func _shape_ell(a: Dictionary, ch: int, c: Vector2, r: Vector2, ang: float, wob: float) -> void:
	a["shapes"].append({"ch": ch, "k": "ell", "c": c, "r": r, "a": ang, "wob": wob})


static func _box(a: Dictionary, ch: int, c: Vector2, half: Vector2, ang: float, corner: float) -> void:
	a["shapes"].append({"ch": ch, "k": "box", "c": c, "half": half, "a": ang, "rad": corner})


static func _line(a: Dictionary, ch: int, pts: Array, w: float) -> void:
	a["shapes"].append({"ch": ch, "k": "line", "pts": PackedVector2Array(pts), "w": w})


## Abschluss: Formen vorbereiten (Drehung, Reichweite), Raster, Umriss, Bäume setzen, Weltlage von allem
static func _finish(a: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"])
	a["layers"] = LAYERS[a["kind"]]
	a["half"] = Vector2(float(a["w"]) / 2.0, float(a["d"]) / 2.0)
	a["ctr"] = Vector2(0.0, float(a["d"]) / 2.0)
	# Ebnen zuletzt (sie überschreiben die Hügel darunter)
	var add := []
	var pads := []
	for pr in a["prims"]:
		(pads if pr["k"] == "pad" else add).append(pr)
	a["prims"] = add + pads
	for pr in a["prims"]:
		var ang: float = pr["a"]
		pr["ca"] = cos(ang)
		pr["sa"] = sin(ang)
		var rr: Vector2 = pr["r"]
		var reach: float = maxf(rr.x, rr.y) * (1.2 if pr["k"] == "pile" else 1.0) + 0.5
		pr["bb2"] = reach * reach
		pr["reach"] = reach
	for sh in a["shapes"]:
		_prep_shape(sh)
	a["grid"] = _grid(a["prims"], func(pr: Dictionary) -> Array: return [pr["c"], pr["reach"]])
	a["slist"] = a["shapes"].filter(func(sh): return sh["k"] != "band")
	a["sgrid"] = _grid(a["slist"], func(sh: Dictionary) -> Array: return [sh["c"], sh["reach"]])
	a["bands"] = a["shapes"].filter(func(sh): return sh["k"] == "band")
	# Lage der Rampen in der Welt (für die Abfragen je Takt) und ihre Seitenrichtung
	for r in a["ramps"]:
		r["x"] = Vector2(-r["d"].y, r["d"].x)
	# Umriss (Zaun): Rand des abgerundeten Rechtecks alle gut 6 m, mit der Welle auf die Nullinie gezogen
	var ol := PackedVector2Array()
	var hs: Vector2 = a["half"]
	var rc: float = a["corner"]
	var pts := []
	var edges := [[Vector2(-hs.x + rc, -hs.y), Vector2(hs.x - rc, -hs.y)], [Vector2(hs.x, -hs.y + rc), Vector2(hs.x, hs.y - rc)],
		[Vector2(hs.x - rc, hs.y), Vector2(-hs.x + rc, hs.y)], [Vector2(-hs.x, hs.y - rc), Vector2(-hs.x, -hs.y + rc)]]
	var corners := [Vector2(hs.x - rc, -hs.y + rc), Vector2(hs.x - rc, hs.y - rc), Vector2(-hs.x + rc, hs.y - rc), Vector2(-hs.x + rc, -hs.y + rc)]
	for k in 4:
		var e0: Vector2 = edges[k][0]
		var e1: Vector2 = edges[k][1]
		var n := maxi(int(e0.distance_to(e1) / 6.0), 1)
		for j in n:
			pts.append(e0.lerp(e1, float(j) / n))
		var cc: Vector2 = corners[k]
		var a0 := -PI / 2.0 + k * PI / 2.0
		var nc := maxi(int(rc * PI / 2.0 / 6.0), 2)
		for j in nc:
			var ang := a0 + PI / 2.0 * float(j) / nc
			pts.append(cc + Vector2(cos(ang), sin(ang)) * rc)
	for q in pts:
		var l: Vector2 = q + a["ctr"]
		for it in 3:
			var g := _sd_grad(a, l)
			l -= g * area_sd(a, l)
		ol.append(l)
	a["outline_l"] = ol
	var olw := PackedVector2Array()
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for l in ol:
		var w := world(a, l)
		olw.append(w)
		lo = lo.min(w)
		hi = hi.max(w)
	a["outline"] = olw
	a["lo"] = lo
	a["hi"] = hi
	a["mid"] = world(a, a["ctr"])
	a["inner_r"] = minf(hs.x, hs.y) * 0.9
	# Bäume: in jeder Gruppe zufällig, nicht auf Bahnen, Wegen, Teichen, Rampen, Kuppen, Gebäuden und nicht zu dicht
	var placed := []
	var trees := []
	for gr in a["trees"]:
		var got := 0
		var tries := 0
		while got < int(gr["n"]) and tries < int(gr["n"]) * 25:
			tries += 1
			var q := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if q.length() > 1.0:
				continue
			var rr: Vector2 = gr["r"]
			var l: Vector2 = gr["c"] + Vector2(q.x * rr.x, q.y * rr.y).rotated(gr["a"])
			if not _tree_ok(a, l, placed):
				continue
			var sc := rng.randf_range(0.8, 1.25)
			trees.append([l, sc, 0 if rng.randf() < (0.35 if a["kind"] == "golf" else 0.6) else 1, rng.randf() * TAU])
			placed.append(l)
			got += 1
	a["tree_list"] = trees


## Kann an l ein Baum stehen? Abstand zu Bahnen, Grüns, Bunkern, Wegen, Teichen, Rampen, Gebäuden, Zaun und Bäumen
static func _tree_ok(a: Dictionary, l: Vector2, placed: Array) -> bool:
	if area_sd(a, l) > -7.0:
		return false
	for k in range(1, 5):
		if shape_sd(a, l, k) < 5.0:
			return false
	for pd in a["ponds"]:
		if pond_sd(pd, l) < 6.0:
			return false
	for r in a["ramps"]:
		var q: Vector2 = l - r["c"]
		var along: float = q.dot(r["d"])
		if along > -40.0 and along < float(r["l"]) + 45.0 and absf(q.dot(r["x"])) < 12.0:
			return false  # Anlauf und Flugbahn frei
	for b in a["builds"]:
		if l.distance_to(b["c"]) < 16.0:
			return false
	for pr in a["prims"]:
		if pr["k"] == "hill" and float(pr["h"]) > 2.5 and l.distance_to(pr["c"]) < maxf(pr["r"].x, pr["r"].y) + 10.0:
			return false  # Kuppen zum Abheben: Landung frei
	for q in placed:
		if l.distance_to(q) < 5.5:
			return false
	return true


## Raster der Formen (Flächenkoordinaten): Zelle -> Indizes aller Formen, deren Reichweite sie berührt
static func _grid(list: Array, cr: Callable) -> Dictionary:
	var g := {}
	for i in list.size():
		var v: Array = cr.call(list[i])
		var c: Vector2 = v[0]
		var r: float = v[1]
		for cz in range(floori((c.y - r) / CELL), floori((c.y + r) / CELL) + 1):
			for cx in range(floori((c.x - r) / CELL), floori((c.x + r) / CELL) + 1):
				var key := Vector2i(cx, cz)
				if not g.has(key):
					g[key] = PackedInt32Array()
				var arr: PackedInt32Array = g[key]
				arr.append(i)
				g[key] = arr
	return g


static func _prep_shape(sh: Dictionary) -> void:
	match sh["k"]:
		"ell":
			sh["ca"] = cos(float(sh["a"]))
			sh["sa"] = sin(float(sh["a"]))
			sh["reach"] = maxf(sh["r"].x, sh["r"].y) + float(sh["wob"]) + 4.0
		"box":
			sh["ca"] = cos(float(sh["a"]))
			sh["sa"] = sin(float(sh["a"]))
			sh["reach"] = (sh["half"] as Vector2).length() + 4.0
		"line":
			var pts: PackedVector2Array = sh["pts"]
			var lo := Vector2(1e9, 1e9)
			var hi := Vector2(-1e9, -1e9)
			for q in pts:
				lo = lo.min(q)
				hi = hi.max(q)
			sh["c"] = (lo + hi) / 2.0
			sh["reach"] = (hi - lo).length() / 2.0 + float(sh["w"]) * 1.2 + 4.0
		"band":
			sh["c"] = Vector2.ZERO
			sh["reach"] = 0.0


# --- Abfragen ---------------------------------------------------------------------------------------------------------

## Welt (x, z) -> Flächenkoordinaten (s längs der Straße, t von der Straße weg)
static func local(a: Dictionary, p: Vector2) -> Vector2:
	var d: Vector2 = p - a["o"]
	return Vector2(d.dot(a["u"]), d.dot(a["v"]))


static func world(a: Dictionary, l: Vector2) -> Vector2:
	return a["o"] + a["u"] * l.x + a["v"] * l.y


## Richtung in Flächenkoordinaten -> Welt
static func wdir(a: Dictionary, d: Vector2) -> Vector2:
	return a["u"] * d.x + a["v"] * d.y


## Fläche, in der p (Welt x, z) liegt, sonst leer
static func find(p: Vector2) -> Dictionary:
	for a in areas:
		var lo: Vector2 = a["lo"]
		var hi: Vector2 = a["hi"]
		if p.x < lo.x - 1.0 or p.y < lo.y - 1.0 or p.x > hi.x + 1.0 or p.y > hi.y + 1.0:
			continue
		if area_sd(a, local(a, p)) < 0.0:
			return a
	return {}


## Abstand zum Zaun (unter 0: innen). Abgerundetes Rechteck, an den Seiten ohne Tor leicht gewellt.
static func area_sd(a: Dictionary, l: Vector2) -> float:
	var hs: Vector2 = a["half"]
	var rc: float = a["corner"]
	var q: Vector2 = (l - a["ctr"]).abs() - hs + Vector2(rc, rc)
	var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - rc
	# Welle (nicht an der Straßenseite: dort liegt das Tor in einer geraden Kante)
	var wob: float = a["wob"]
	if wob > 0.0:
		sd += wob * sin(l.x * 0.031 + l.y * 0.017) * sin(l.y * 0.027 - l.x * 0.012 + 1.3) * smoothstep(6.0, 60.0, l.y)
	return sd


static func _sd_grad(a: Dictionary, l: Vector2) -> Vector2:
	var e := 0.5
	var g := Vector2(area_sd(a, l + Vector2(e, 0)) - area_sd(a, l - Vector2(e, 0)), area_sd(a, l + Vector2(0, e)) - area_sd(a, l - Vector2(0, e)))
	return g.normalized() if g.length() > 1e-5 else Vector2(0, -1)


## Bodenhöhe ohne Rampen (glatt): Plateau (vom Tor sanft hinauf), Wall, Formen, außerhalb des Zauns abfallend
static func base_h(a: Dictionary, l: Vector2) -> float:
	var sd := area_sd(a, l)
	var lv: float = a["level"]
	var h := lv * smoothstep(0.0, a["rise"], l.y)
	if a.has("wall"):
		h += _wall_h(a, l, sd)
	var list = a["grid"].get(Vector2i(floori(l.x / CELL), floori(l.y / CELL)))
	if list != null:
		var prims: Array = a["prims"]
		for i in list:
			h = _prim(prims[i], l, h)
	if sd > 0.0:
		h = lerpf(h, -0.05, smoothstep(0.0, SKIRT, sd))
	return h


## Wall der Kiesgrube: vom Zaun eben (Krone), dann steil hinunter auf die Sohle; beim Tor ein Schnitt
static func _wall_h(a: Dictionary, l: Vector2, sd: float) -> float:
	var w: Dictionary = a["wall"]
	var x := -sd
	var H: float = w["h"]
	var crest: float = w["crest"]
	var run: float = w["run"]
	var y := H
	if x > crest:
		y = H * (1.0 - smoothstep(0.0, 1.0, (x - crest) / run))
	if x < 0.0:
		y = H  # außerhalb: Krone läuft bis unter den Zaun durch (dort fällt der Rand ab)
	var near_gate := 1.0 - smoothstep(crest + run, crest + run + 20.0, l.y)
	if near_gate > 0.0:
		var cut := smoothstep(w["cut"], float(w["cut"]) + float(w["flank"]), absf(l.x - float(a["gate_s"])))
		y *= lerpf(1.0, cut, near_gate)
	return y


static func _prim(pr: Dictionary, l: Vector2, h: float) -> float:
	var q: Vector2 = l - pr["c"]
	if q.length_squared() > float(pr["bb2"]):
		return h
	var ca: float = pr["ca"]
	var sa: float = pr["sa"]
	var rr: Vector2 = pr["r"]
	var x := (q.x * ca + q.y * sa) / rr.x
	var y := (-q.x * sa + q.y * ca) / rr.y
	var e := sqrt(x * x + y * y)  # 1 am Rand der Form
	match pr["k"]:
		"hill":
			if e < 1.0:
				h += float(pr["h"]) * (0.5 + 0.5 * cos(PI * e))
		"pile":
			h += float(pr["h"]) * _pile_f(e)
		"dip":
			if e < 1.0:
				var f := 1.0 if e < 0.5 else 0.5 + 0.5 * cos(PI * (e - 0.5) / 0.5)
				h -= float(pr["h"]) * f
		"pad":
			if e < 1.0:
				h = lerpf(h, float(pr["level"]), 1.0 - smoothstep(float(pr["core"]), 1.0, e))
	return h


## Haufen: Kegel (Hang = Höhe/Radius) mit runder Spitze (innerstes Viertel) und weichem Fuß (bis 1,15)
static func _pile_f(e: float) -> float:
	const A := 0.25
	const B := 0.15
	if e < A:
		return 1.0 - A / 2.0 - e * e / (2.0 * A)
	if e < 1.0 - B:
		return 1.0 - e
	if e < 1.0 + B:
		var k := e - (1.0 + B)
		return k * k / (4.0 * B)
	return 0.0


## Untergrund-Formen: Abstand zur Form (unter 0: darin)
static func _shape_sd(a: Dictionary, sh: Dictionary, l: Vector2) -> float:
	match sh["k"]:
		"ell":
			var q: Vector2 = l - sh["c"]
			var ca: float = sh["ca"]
			var sa: float = sh["sa"]
			var rr: Vector2 = sh["r"]
			var x := (q.x * ca + q.y * sa) / rr.x
			var y := (-q.x * sa + q.y * ca) / rr.y
			var wob: float = sh["wob"]
			return (sqrt(x * x + y * y) - 1.0) * minf(rr.x, rr.y) + wob * sin(atan2(y, x) * 3.0 + rr.x) * 0.6
		"box":
			var q2: Vector2 = l - sh["c"]
			var ca2: float = sh["ca"]
			var sa2: float = sh["sa"]
			var r2: float = sh["rad"]
			var d: Vector2 = Vector2(absf(q2.x * ca2 + q2.y * sa2), absf(-q2.x * sa2 + q2.y * ca2)) - sh["half"] + Vector2(r2, r2)
			return Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length() + minf(maxf(d.x, d.y), 0.0) - r2
		"line":
			var pts: PackedVector2Array = sh["pts"]
			var best := 1e9
			for k in pts.size() - 1:
				best = minf(best, _seg_dist(l, pts[k], pts[k + 1]))
			var w: float = sh["w"]
			return best - w * (1.0 + 0.12 * sin(l.x * 0.05 + l.y * 0.031))
		"band":
			var sd := area_sd(a, l)
			return maxf(float(sh["in"]) - sd, sd - float(sh["out"]))
	return 1e9


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Kleinster Abstand zu den Formen eines Farbkanals ch (1..4)
static func shape_sd(a: Dictionary, l: Vector2, ch: int) -> float:
	var best := 1e9
	var list = a["sgrid"].get(Vector2i(floori(l.x / CELL), floori(l.y / CELL)))
	if list != null:
		var shapes: Array = a["slist"]
		for i in list:
			var sh: Dictionary = shapes[i]
			if int(sh["ch"]) == ch:
				best = minf(best, _shape_sd(a, sh, l))
	for sh in a["bands"]:
		if int(sh["ch"]) == ch:
			best = minf(best, _shape_sd(a, sh, l))
	return best


## Untergrund an l: höchster Kanal, in dessen Formen l liegt
static func surf_at(a: Dictionary, l: Vector2) -> String:
	var layers: Array = a["layers"]
	for ch in [4, 3, 2, 1]:
		if shape_sd(a, l, ch) < 0.0:
			return layers[ch]
	return layers[0]


static func pond_sd(pd: Dictionary, l: Vector2) -> float:
	var q: Vector2 = l - pd["c"]
	var ang: float = pd["a"]
	var rr: Vector2 = pd["r"]
	var x := (q.x * cos(ang) + q.y * sin(ang)) / rr.x
	var y := (-q.x * sin(ang) + q.y * cos(ang)) / rr.y
	return (sqrt(x * x + y * y) - 1.0) * minf(rr.x, rr.y) + float(pd["wob"]) * sin(atan2(y, x) * 4.0 + rr.y)


## Teich an l (oder leer): Wasser ist, wo der Boden unter dem Wasserspiegel liegt (genau die sichtbare Uferlinie;
## die Wasserfläche reicht unter dem Ufer etwas weiter). base: Bodenhöhe an l, falls schon bekannt.
static func pond_at(a: Dictionary, l: Vector2, base := NAN) -> Dictionary:
	for pd in a["ponds"]:
		if pond_sd(pd, l) < 8.0:
			if is_nan(base):
				base = base_h(a, l)
			if base < float(pd["level"]) - 0.05:
				return pd
	return {}


## Abstand zum nächsten Teich (Wasserlinie)
static func water_dist(a: Dictionary, l: Vector2) -> float:
	var best := 1e9
	for pd in a["ponds"]:
		best = minf(best, pond_sd(pd, l))
	return best


## Rampen-Aufsatz an l: [Höhe über dem Boden, Rampe] (Höhe 0: keine)
static func ramp_at(a: Dictionary, l: Vector2) -> Array:
	var best := 0.0
	var br = null
	for r in a["ramps"]:
		var q: Vector2 = l - r["c"]
		var along: float = q.dot(r["d"])
		if along < 0.0 or along > float(r["l"]):
			continue
		if absf(q.dot(r["x"])) > float(r["w"]) / 2.0:
			continue
		var rh: float = float(r["h"]) * along / float(r["l"])
		if rh > best:
			best = rh
			br = r
	return [best, br]


## Boden für das Auto (Welt x, z): wie Track.ground. "h" mit Rampe, "base" ohne; im Teich "water" (dann ist "base"
## der Wasserspiegel und "h" liegt darunter wie bei den Seen der Strecken). "surf": Untergrund.
static func ground(a: Dictionary, p: Vector2) -> Dictionary:
	var l := local(a, p)
	var base := base_h(a, l)
	var rp := ramp_at(a, l)
	var pd := pond_at(a, l, base) if float(rp[0]) <= 0.0 else {}
	if not pd.is_empty():
		var lv: float = pd["level"]
		return {"h": lv - Track.WATER_DROP, "base": lv, "ramp": false, "water": true, "surf": "sand", "l": l}
	return {"h": base + float(rp[0]), "base": base, "ramp": float(rp[0]) > 0.0, "water": false, "surf": surf_at(a, l), "l": l,
		"ramp_r": rp[1]}


## Steigung des befahrenen Bodens (Welt: dh/dx, dh/dz); auf einer Rampe deren Neigung dazu
static func gradient(a: Dictionary, p: Vector2, ramp = null) -> Vector2:
	var e := 0.7
	var l := local(a, p)
	var gs := (base_h(a, l + Vector2(e, 0)) - base_h(a, l - Vector2(e, 0))) / (2.0 * e)
	var gt := (base_h(a, l + Vector2(0, e)) - base_h(a, l - Vector2(0, e))) / (2.0 * e)
	var g := Vector2(gs, gt)
	if ramp != null:
		g += (ramp["d"] as Vector2) * float(ramp["h"]) / float(ramp["l"])
	# Flächenkoordinaten -> Welt (u, v sind orthonormal; gespiegelte Flächen eingeschlossen)
	return a["u"] * g.x + a["v"] * g.y


## Krümmung des Bodens entlang dir (Welt, Einheitsvektor): unter 0 eine Kuppe
static func curvature(a: Dictionary, p: Vector2, dir: Vector2, step := 3.0) -> float:
	var l := local(a, p)
	var dl := Vector2(dir.dot(a["u"]), dir.dot(a["v"])) * step
	return (base_h(a, l + dl) - 2.0 * base_h(a, l) + base_h(a, l - dl)) / (step * step)


## Bodenhöhe an p (Welt x, z) in irgendeiner Fläche, sonst NAN (Reifenspuren am Hang)
static func height_at(p: Vector2) -> float:
	var a := find(p)
	if a.is_empty():
		return NAN
	var l := local(a, p)
	return base_h(a, l) + float(ramp_at(a, l)[0])


## Für die Landschaft: Abstand von p zur flachen Zone um alle Flächen (unter 0: darin; dort kein Gelände, keine Bäume)
static func land_free(p: Vector2, margin := 0.0, list = null) -> float:
	var best := 1e9
	for a in (areas if list == null else list):
		var lo: Vector2 = a["lo"]
		var hi: Vector2 = a["hi"]
		var reach := SKIRT + margin + 600.0
		if p.x < lo.x - reach or p.y < lo.y - reach or p.x > hi.x + reach or p.y > hi.y + reach:
			continue
		best = minf(best, area_sd(a, local(a, p)) - SKIRT - margin)
	return best
