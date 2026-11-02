extends RefCounted
## Baut ein Low-Poly-Auto abhängig von Auto-Typ und Tuning. Die Karosserie ist ein Körper aus Querschnitten von
## vorn nach hinten (Unterboden, Radhaus, Schweller, Flanke, Gürtellinie, Schulter, Dach): daraus entstehen
## Radausschnitte, Kotflügel-Buckel, Hüften, ein eingezogenes Glashaus und gewölbte Hauben. Die Form je Auto steht in
## SHAPES, lose angelehnt an 2000er-JDM-Sportwagen. Front- und Heckschürze sind eigene Teile (später tauschbar),
## Scheinwerfer und Rückleuchten sitzen in der Haut. Vorne ist -Z. Wichtige Knoten landen als Meta-Daten am Wurzelknoten.

const Catalog := preload("res://scripts/catalog.gd")

const WHEEL_R := 0.32
const CLEARANCE := 0.15
const AXLE := 0.78  # Achse so weit von Bug und Heck
const CAR_LAYER := 2  # eigene Sichtebene: das Unterbodenlicht malt nur auf die Straße, nicht auf Autos
const FRONT_SEAM := 0.075  # Fuge Frontschürze (t)
const REAR_SEAM := 0.94  # Fuge Heckschürze (t)

static var _glow_tex: ImageTexture

## t = Anteil der Länge von vorn (0) nach hinten (1), Höhen in Metern über dem Boden.
##   nose/hood: Bug-Oberkante und Haube an der Scheibe, cowl: Scheibenansatz, rf/rr: Dach von/bis,
##   ge: Ende der Heckscheibe, cp: Ende der Seitenfenster, roof/deck/tail: Dach, Heckdeckel, Heckkante,
##   belt: Gürtellinie, fender: Kotflügel-Buckel über dem Vorderrad, hips: Hüften über dem Hinterrad,
##   round_f/round_r: Rundung der Ecken in der Draufsicht, tumble: so viel schmaler ist das Dach,
##   hl/tl: Hautband -> bis/ab welchem t es leuchtet (Scheinwerfer/Rückleuchten), doors: Türfugen,
##   intake: Lufteinlass vorn (Anteil der Breite, Höhe)
## Optional: pipes/pipe_r (Endrohre), tire_w (Reifenbreite), softtop (Stoffverdeck), black_bumpers (Schürzen aus
##   schwarzem Kunststoff), trim_low (schwarzer Streifen unten an der Flanke)
const SHAPES := {
	"kaizen": {  # JDM-Fließheck (Civic-EG-Gefühl): rundliche flache Nase, schmale breite Scheinwerfer, große Scheiben,
		# langes Dach, steile Heckscheibe, fast senkrechte Klappe mit umlaufenden Rückleuchten, dicker Endtopf
		"nose": 0.6, "hood": 0.82, "cowl": 0.3, "rf": 0.49, "rr": 0.66, "ge": 0.935, "cp": 0.85,
		"roof": 1.29, "deck": 0.99, "tail": 0.95, "belt": 0.8, "fender": 0.0, "hips": 0.02,
		"round_f": 0.22, "round_r": 0.08, "tumble": 0.15, "hl": {6: 0.085, 5: 0.025}, "tl": {6: 0.957, 5: 0.962},
		"doors": [0.315, 0.62], "intake": Vector2(0.48, 0.06), "pipes": [0.46], "pipe_r": 0.085, "trim_low": true,
		"drop": 0.035,  # ab Werk etwas tiefer
	},
	"mirai": {  # 350Z: lange Haube, Dachbogen fließt ins kurze Heck, breite Hüften
		"nose": 0.6, "hood": 0.86, "cowl": 0.42, "rf": 0.56, "rr": 0.64, "ge": 0.89, "cp": 0.71,
		"roof": 1.22, "deck": 0.95, "tail": 0.96, "belt": 0.85, "fender": 0.04, "hips": 0.055,
		"round_f": 0.14, "round_r": 0.12, "tumble": 0.21, "hl": {6: 0.14, 5: 0.05}, "tl": {5: 0.945, 6: 0.96},
		"doors": [0.435, 0.68], "intake": Vector2(0.5, 0.12),
	},
	"sakura": {  # Silvia-Coupé: schmale Scheinwerfer, Stufenheck mit kurzem Kofferraum
		"nose": 0.6, "hood": 0.84, "cowl": 0.38, "rf": 0.54, "rr": 0.67, "ge": 0.81, "cp": 0.69,
		"roof": 1.22, "deck": 0.93, "tail": 0.94, "belt": 0.84, "fender": 0.02, "hips": 0.025,
		"round_f": 0.12, "round_r": 0.07, "tumble": 0.16, "hl": {6: 0.09, 5: 0.035}, "tl": {5: 0.968},
		"doors": [0.395, 0.67], "intake": Vector2(0.56, 0.09),
	},
	"vortex": {  # GT-R-Limousine: kantiger, höheres Dach, Stufenheck, vier Türen
		"nose": 0.66, "hood": 0.88, "cowl": 0.36, "rf": 0.5, "rr": 0.71, "ge": 0.82, "cp": 0.72,
		"roof": 1.27, "deck": 0.98, "tail": 0.99, "belt": 0.87, "fender": 0.02, "hips": 0.035,
		"round_f": 0.07, "round_r": 0.05, "tumble": 0.13, "hl": {6: 0.075, 5: 0.05}, "tl": {},
		"doors": [0.375, 0.55, 0.715], "intake": Vector2(0.66, 0.13),
	},
	"ronin": {  # RX-7: sehr flach, runde Formen, hohe Kotflügel, Glaskuppel, langes gewölbtes Heckfenster
		"nose": 0.54, "hood": 0.8, "cowl": 0.39, "rf": 0.55, "rr": 0.61, "ge": 0.87, "cp": 0.68,
		"roof": 1.18, "deck": 0.92, "tail": 0.93, "belt": 0.82, "fender": 0.06, "hips": 0.05,
		"round_f": 0.2, "round_r": 0.15, "tumble": 0.22, "hl": {}, "tl": {},
		"doors": [0.405, 0.655], "intake": Vector2(0.58, 0.13), "pipes": [0.0],
	},
	"kaze": {  # Supra-Gefühl: lang und rund, lange Nase, Kuppeldach, Bügelflügel, vier runde Rückleuchten
		"nose": 0.55, "hood": 0.83, "cowl": 0.41, "rf": 0.565, "rr": 0.645, "ge": 0.85, "cp": 0.73,
		"roof": 1.19, "deck": 0.95, "tail": 0.95, "belt": 0.83, "fender": 0.035, "hips": 0.065,
		"round_f": 0.23, "round_r": 0.17, "tumble": 0.25, "hl": {6: 0.11, 5: 0.075}, "tl": {},
		"doors": [0.43, 0.69], "intake": Vector2(0.6, 0.12), "pipes": [0.46], "pipe_r": 0.068,
	},
	"raijin": {  # Rallye-Limousine (Evo/Impreza): kantig, breite Backen, Hutze, riesiger Flügel, Schmutzfänger
		"nose": 0.66, "hood": 0.9, "cowl": 0.355, "rf": 0.495, "rr": 0.685, "ge": 0.825, "cp": 0.745,
		"roof": 1.28, "deck": 0.99, "tail": 1.0, "belt": 0.88, "fender": 0.055, "hips": 0.06,
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.12, "hl": {6: 0.075, 5: 0.06}, "tl": {6: 0.972, 5: 0.976},
		"doors": [0.37, 0.545, 0.725], "intake": Vector2(0.62, 0.17), "pipes": [0.42], "pipe_r": 0.072,
	},
	"tsubame": {  # Roadster (S2000/MX-5): lange Haube, kleines Stoffverdeck weit hinten, kurzes Heck
		"nose": 0.57, "hood": 0.8, "cowl": 0.465, "rf": 0.585, "rr": 0.655, "ge": 0.765, "cp": 0.71,
		"roof": 1.1, "deck": 0.9, "tail": 0.92, "belt": 0.82, "fender": 0.05, "hips": 0.055,
		"round_f": 0.19, "round_r": 0.13, "tumble": 0.27, "hl": {6: 0.125, 5: 0.045}, "tl": {5: 0.962, 6: 0.972},
		"doors": [0.47, 0.695], "intake": Vector2(0.42, 0.1), "pipes": [-0.32, 0.32], "softtop": true,
	},
	"hachi": {  # 80er-Fließheck (AE86): kantig, Klappscheinwerfer, schwarze Stoßfänger, breites Leuchtenband
		"nose": 0.63, "hood": 0.84, "cowl": 0.37, "rf": 0.52, "rr": 0.665, "ge": 0.9, "cp": 0.75,
		"roof": 1.22, "deck": 0.96, "tail": 0.95, "belt": 0.87, "fender": 0.0, "hips": 0.015,
		"round_f": 0.05, "round_r": 0.04, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.385, 0.66], "intake": Vector2(0.7, 0.05), "pipes": [-0.46], "pipe_r": 0.04,
		"tire_w": 0.2, "black_bumpers": true, "trim_low": true,
	},
}


static func build(car_id: String, cfg: Dictionary, headlights := true, lod := true) -> Node3D:
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var P: Dictionary = Catalog.PARTS
	var paint_c: Color = paint_color(car_id, cfg)
	var rim: Dictionary = P["rims"]["options"][cfg["rims"]]
	var kit: int = cfg["bodykit"]
	var L: float = spec["length"]
	var W: float = spec["width"]
	var flare := 0.06 if kit == 2 else 0.0
	var zf := -L / 2.0
	var zr := L / 2.0

	var root := Node3D.new()
	root.name = "Car"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint := mat(paint_c, 0.55, 0.22)
	paint.clearcoat_enabled = true
	paint.clearcoat = 1.0
	var dark := mat(Color(0.04, 0.04, 0.05), 0.2, 0.6)
	var stripe_c := Color(0.95, 0.95, 0.95) if paint_c.get_luminance() < 0.5 else Color(0.05, 0.05, 0.05)
	var tint: Dictionary = Catalog.part_of(cfg, "tint")
	var perf := int(cfg.get("engine", 0)) + int(cfg.get("turbo", 0)) + int(cfg.get("suspension", 0)) + int(cfg.get("tires", 0))
	var mats := {
		"paint": paint,
		"glass": mat(tint["color"], 0.8 if int(cfg.get("tint", 0)) == 3 else 0.6, 0.06),
		"under": mat(Color(0.025, 0.025, 0.03), 0.0, 0.85),
		"seam": mat(Color(0.012, 0.012, 0.016), 0.2, 0.7),
		"head": mat(Color(1, 1, 0.95), 0, 0.3, Color(1, 0.97, 0.9), 2.6),
		"tail": mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 2.2),
		"stripe": mat(stripe_c, 0.3, 0.3),
		"trim": mat(Color(0.035, 0.035, 0.04), 0.1, 0.7),
		"top": mat(Color(0.03, 0.03, 0.035), 0.0, 0.95),
	}
	_shell(body, S, W, L, flare, cfg["vinyl"], mats)
	var front: PackedVector2Array = _section(S, 0.0, W, L, flare)["p"]
	var rear: PackedVector2Array = _section(S, 1.0, W, L, flare)["p"]

	# Front: Lufteinlass, je Auto eigene Lichter in der Schürze
	var fb: Node3D = body.get_node("FrontBumper")
	var head_m: Material = mats["head"]
	var amber := mat(Color(1, 0.55, 0.05), 0, 0.3, Color(1, 0.5, 0.0), 1.5)
	var fw: float = front[6].x  # halbe Breite der Bugfläche in Gürtelhöhe
	var iv: Vector2 = S["intake"]
	_add(fb, box(Vector3(fw * 2.0 * iv.x, iv.y, 0.012)), dark, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.004))
	if int(cfg.get("turbo", 0)) > 0:
		# Ladeluftkühler hinter dem Einlass: silbernes Netz mit Lamellen
		var ic := mat(Color(0.55, 0.57, 0.6), 0.85, 0.35)
		var icw := fw * 2.0 * iv.x * 0.86
		var ich := iv.y * 0.78
		_add(fb, box(Vector3(icw, ich, 0.01)), ic, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.011))
		for k in int(ich / 0.022):
			_add(fb, box(Vector3(icw, 0.006, 0.012)), dark, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0 - ich / 2.0 + 0.011 + k * 0.022, zf - 0.017))
	if kit == 0:
		# dezente Frontlippe ab Werk (sportlich, nicht so ausladend wie das Bodykit)
		_add(fb, box(Vector3(fw * 2.0 - 0.18, 0.018, 0.08)), dark, Vector3(0, CLEARANCE + 0.005, zf + 0.03))
	var hy: float = S["nose"] - 0.09
	match car_id:
		"ronin":  # Klappscheinwerfer (zu): Fugen auf der Haube, kleine Lichter unten in der Schürze
			for s in [-1, 1]:
				var hood_y := _top_y(_section(S, 0.11, W, L, flare)["p"], 0.5)
				_add(body, box(Vector3(0.36, 0.008, 0.008)), mats["seam"], Vector3(s * 0.5, hood_y + 0.01, zf + 0.33))
				_add(body, box(Vector3(0.36, 0.008, 0.008)), mats["seam"], Vector3(s * 0.5, hood_y - 0.005, zf + 0.6))
				_add(fb, box(Vector3(0.2, 0.045, 0.012)), head_m, Vector3(s * (fw - 0.2), CLEARANCE + 0.22, zf - 0.005))
				_add(fb, box(Vector3(0.07, 0.045, 0.012)), amber, Vector3(s * (fw - 0.05), CLEARANCE + 0.22, zf - 0.004))
			hy = CLEARANCE + 0.22
		"vortex":  # kantige Scheinwerfer bis in die Front, Nebelscheinwerfer
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.3, 0.08, 0.012)), head_m, Vector3(s * (fw - 0.2), hy, zf - 0.004))
				_add(fb, _disc(0.04, 0.012), head_m, Vector3(s * (fw - 0.12), CLEARANCE + 0.12, zf - 0.005)).rotation_degrees.x = 90
		"sakura":
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.09, 0.04, 0.012)), amber, Vector3(s * (fw - 0.07), CLEARANCE + 0.14, zf - 0.004))
		"kaizen":  # JDM: schmaler Grill mit rotem Emblem, Blinker an den Ecken, roter Abschlepphaken
			var gy: float = S["nose"] - 0.085
			_add(fb, box(Vector3(fw * 0.9, 0.045, 0.02)), dark, Vector3(0, gy, zf + 0.012))
			_add(fb, box(Vector3(0.075, 0.034, 0.012)), mat(Color(0.85, 0.02, 0.03), 0.3, 0.3, Color(0.9, 0.0, 0.05), 0.6), Vector3(0, gy, zf + 0.001))
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.11, 0.035, 0.012)), amber, Vector3(s * (fw - 0.1), gy - 0.05, zf + 0.03))
			_add(fb, box(Vector3(0.05, 0.05, 0.1)), mat(Color(0.85, 0.05, 0.04), 0.4, 0.4), Vector3(-fw * 0.55, CLEARANCE + 0.09, zf - 0.02))
		"kaze":  # großes Maul in der Mitte, außen kleine Einlässe, Blinker unter den Scheinwerfern
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.15, 0.06, 0.012)), dark, Vector3(s * (fw - 0.14), CLEARANCE + 0.13, zf - 0.004))
				_add(fb, box(Vector3(0.13, 0.028, 0.012)), amber, Vector3(s * (fw - 0.13), CLEARANCE + 0.25, zf - 0.004))
		"raijin":  # Nebelscheinwerfer außen, Spoilerlippe
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.16, 0.11, 0.012)), dark, Vector3(s * (fw - 0.12), CLEARANCE + 0.15, zf - 0.004))
				_add(fb, _disc(0.045, 0.012), head_m, Vector3(s * (fw - 0.12), CLEARANCE + 0.15, zf - 0.008)).rotation_degrees.x = 90
			_add(fb, box(Vector3(fw * 2.0 - 0.04, 0.025, 0.14)), dark, Vector3(0, CLEARANCE + 0.065, zf + 0.04))
		"tsubame":  # kleine Einlässe mit runden Blinkern
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.12, 0.055, 0.012)), dark, Vector3(s * (fw - 0.14), CLEARANCE + 0.13, zf - 0.004))
				_add(fb, _disc(0.026, 0.012), amber, Vector3(s * (fw - 0.14), CLEARANCE + 0.13, zf - 0.008)).rotation_degrees.x = 90
		"hachi":  # Klappscheinwerfer (zu), breite Stand- und Blinklichter im schwarzen Stoßfänger, Kühlerschlitz
			for s in [-1, 1]:
				for z in [0.28, 0.56]:
					var ps: PackedVector2Array = _section(S, z / L, W, L, flare)["p"]
					_add(body, box(Vector3(0.38, 0.008, 0.008)), mats["seam"], Vector3(s * 0.45, _top_y(ps, 0.45 / ps[7].x) + 0.004, zf + z))
				var pm: PackedVector2Array = _section(S, 0.42 / L, W, L, flare)["p"]
				for x in [0.26, 0.64]:
					_add(body, box(Vector3(0.008, 0.008, 0.28)), mats["seam"], Vector3(s * x, _top_y(pm, x / pm[7].x) + 0.004, zf + 0.42))
				_add(fb, box(Vector3(0.24, 0.045, 0.012)), mat(Color(0.95, 0.95, 0.9), 0, 0.3, Color(1, 0.95, 0.85), 1.4),
					Vector3(s * (fw - 0.22), CLEARANCE + 0.31, zf - 0.005))
				_add(fb, box(Vector3(0.09, 0.045, 0.012)), amber, Vector3(s * (fw - 0.05), CLEARANCE + 0.31, zf - 0.005))
			# Stoßfängerleiste aus schwarzem Kunststoff mit Kühlerschlitz
			_add(fb, box(Vector3(front[4].x * 2.0 + 0.02, 0.18, 0.1)), mats["trim"], Vector3(0, CLEARANCE + 0.15, zf + 0.025))
			_add(fb, box(Vector3(fw * 1.1, 0.035, 0.012)), mat(Color(0.18, 0.18, 0.19), 0.6, 0.4), Vector3(0, CLEARANCE + 0.15, zf - 0.03))
			hy = CLEARANCE + 0.31
		_:
			pass
	if headlights:
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, hy, zf - 0.1)
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.light_energy = 4.0
		spot.light_color = Color(1, 0.97, 0.88)
		spot.rotation_degrees.x = -4.0
		body.add_child(spot)

	# Heck: Kennzeichen, Diffusor, Rückleuchten je Auto
	var rbm: Node3D = body.get_node("RearBumper")
	var tail_m: Material = mats["tail"]
	var rev_m := mat(Color(0.85, 0.85, 0.85), 0, 0.3, Color(1, 1, 1), 0.35)
	var rw: float = rear[6].x
	var ty: float = S["tail"] - 0.2
	_add(rbm, box(Vector3(0.33, 0.165, 0.01)), mat(Color(0.85, 0.85, 0.8), 0.0, 0.5), Vector3(0, CLEARANCE + 0.3, zr + 0.004))
	_add(rbm, box(Vector3(rw * 1.1, 0.07, 0.05)), dark, Vector3(0, CLEARANCE + 0.04, zr - 0.01))
	for k in 5:  # Diffusor-Finnen
		_add(rbm, box(Vector3(0.012, 0.09, 0.22)), dark, Vector3((k - 2) * rw * 0.22, CLEARANCE + 0.03, zr - 0.1))
	match car_id:
		"ronin":  # dunkles Band über das ganze Heck, darin runde Leuchten
			_add(rbm, box(Vector3(rw * 2.0 - 0.08, 0.13, 0.01)), dark, Vector3(0, ty, zr + 0.004))
			for s in [-1, 1]:
				for k in 2:
					_add(rbm, _disc(0.052, 0.012), tail_m, Vector3(s * (rw - 0.13 - k * 0.15), ty, zr + 0.008)).rotation_degrees.x = 90
		"vortex":  # runde Doppel-Rückleuchten
			for s in [-1, 1]:
				for k in 2:
					_add(rbm, _disc(0.068, 0.012), tail_m, Vector3(s * (rw - 0.14 - k * 0.19), ty, zr + 0.006)).rotation_degrees.x = 90
		"mirai":  # hochkant an den Ecken (Bumerang)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.09, 0.22, 0.01)), tail_m, Vector3(s * (rw - 0.06), ty - 0.04, zr + 0.004))
				_add(rbm, box(Vector3(0.22, 0.06, 0.01)), tail_m, Vector3(s * (rw - 0.17), ty + 0.04, zr + 0.004))
		"sakura":  # flaches Band, Mitte dunkel
			_add(rbm, box(Vector3(rw * 2.0 - 0.1, 0.07, 0.01)), dark, Vector3(0, ty + 0.02, zr + 0.003))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.4, 0.075, 0.01)), tail_m, Vector3(s * (rw - 0.25), ty + 0.02, zr + 0.006))
		"kaze":  # dunkle Felder an den Ecken, darin je zwei große runde Leuchten
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.44, 0.17, 0.01)), dark, Vector3(s * (rw - 0.25), ty, zr + 0.003))
				for k in 2:
					_add(rbm, _disc(0.066, 0.012), tail_m, Vector3(s * (rw - 0.13 - k * 0.18), ty, zr + 0.007)).rotation_degrees.x = 90
				_add(rbm, _disc(0.028, 0.012), rev_m, Vector3(s * (rw - 0.43), ty, zr + 0.007)).rotation_degrees.x = 90
		"raijin":  # breite Leuchten, um die Ecken gezogen, innen Rückfahrlicht
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.34, 0.13, 0.01)), tail_m, Vector3(s * (rw - 0.17), ty, zr + 0.004))
				_add(rbm, box(Vector3(0.09, 0.05, 0.01)), rev_m, Vector3(s * (rw - 0.39), ty - 0.035, zr + 0.004))
		"tsubame":  # schmale Leuchten über die Ecken, innen ein heller Streifen
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.28, 0.07, 0.01)), tail_m, Vector3(s * (rw - 0.14), ty + 0.04, zr + 0.004))
				_add(rbm, box(Vector3(0.09, 0.07, 0.01)), rev_m, Vector3(s * (rw - 0.325), ty + 0.04, zr + 0.004))
		"hachi":  # Leuchtenband über das ganze Heck, Stoßfängerleiste aus schwarzem Kunststoff
			_add(rbm, box(Vector3(rear[4].x * 2.0 + 0.02, 0.18, 0.1)), mats["trim"], Vector3(0, CLEARANCE + 0.12, zr - 0.025))
			_add(rbm, box(Vector3(rw * 2.0 - 0.04, 0.13, 0.01)), dark, Vector3(0, ty, zr + 0.003))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.4, 0.1, 0.01)), tail_m, Vector3(s * (rw - 0.22), ty, zr + 0.006))
				_add(rbm, box(Vector3(0.09, 0.1, 0.01)), amber, Vector3(s * (rw - 0.47), ty, zr + 0.006))
		"kaizen":  # durchgehendes Leuchtenband über die ganze Klappe, außen Rückfahrlicht
			_add(rbm, box(Vector3(rw * 2.0 - 0.04, 0.12, 0.01)), tail_m, Vector3(0, ty, zr + 0.004))
			_add(rbm, box(Vector3(rw * 0.8, 0.03, 0.012)), dark, Vector3(0, ty, zr + 0.006))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.08, 0.05, 0.012)), rev_m, Vector3(s * (rw - 0.3), ty - 0.03, zr + 0.006))
		_:
			_add(rbm, box(Vector3(rw * 2.0 - 0.3, 0.1, 0.01)), dark, Vector3(0, ty, zr + 0.003))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.12, 0.2, 0.01)), tail_m, Vector3(s * (rw - 0.08), ty - 0.02, zr + 0.004))
	if car_id == "kaizen":
		_kaizen_extras(body, S, W, L, mats)

	# Spiegel, Türgriffe
	var ms: PackedVector2Array = _section(S, S["cowl"] + 0.035, W, L, flare)["p"]
	var mz: float = zf + (S["cowl"] + 0.035) * L
	var doors: Array = S["doors"]
	var hs: PackedVector2Array = _section(S, doors[1] - 0.035, W, L, flare)["p"]
	for s in [-1, 1]:
		_add(body, box(Vector3(0.1, 0.03, 0.04)), dark, Vector3(s * (ms[6].x + 0.04), ms[6].y + 0.04, mz))
		_add(body, box(Vector3(0.05, 0.075, 0.14)), paint, Vector3(s * (ms[6].x + 0.1), ms[6].y + 0.06, mz))
		_add(body, box(Vector3(0.012, 0.022, 0.1)), dark, Vector3(s * (hs[5].x * 0.4 + hs[6].x * 0.6 + 0.008), hs[6].y - 0.05, zf + (doors[1] - 0.035) * L))
	if car_id == "vortex":
		# Luftauslässe auf der Haube
		var vs: PackedVector2Array = _section(S, 0.27, W, L, flare)["p"]
		for s in [-1, 1]:
			_add(body, box(Vector3(0.22, 0.01, 0.16)), dark, Vector3(s * 0.32, _top_y(vs, 0.32 / vs[7].x) + 0.003, zf + 0.27 * L))
	elif car_id == "raijin":
		# Hutze auf der Haube, Luftauslässe vorn, Finnen an der Dachkante, Schmutzfänger hinter den Rädern
		var hz := 0.21 * L
		var hp: PackedVector2Array = _section(S, 0.21, W, L, flare)["p"]
		_add(body, tapered_box(Vector2(0.52, 0.46), Vector2(0.44, 0.34), 0.075, 0.05), paint, Vector3(0, hp[10].y - 0.01, zf + hz))
		_add(body, box(Vector3(0.4, 0.045, 0.05)), dark, Vector3(0, hp[10].y + 0.03, zf + hz - 0.19))
		var vp: PackedVector2Array = _section(S, 0.12, W, L, flare)["p"]
		for s in [-1, 1]:
			_add(body, box(Vector3(0.2, 0.01, 0.13)), dark, Vector3(s * 0.38, _top_y(vp, 0.38 / vp[7].x) + 0.004, zf + 0.12 * L))
		var rp: PackedVector2Array = _section(S, S["rr"], W, L, flare)["p"]
		for k in 7:
			var x := -0.36 + k * 0.12
			_add(body, box(Vector3(0.012, 0.04, 0.09)), dark, Vector3(x, _top_y(rp, absf(x) / rp[7].x) + 0.015, zf + S["rr"] * L + 0.03))
		var flap := mat(Color(0.5, 0.03, 0.03), 0.0, 0.8)
		for zi in [-1, 1]:
			for s in [-1, 1]:
				_add(body, box(Vector3(0.22, 0.2, 0.012)), flap, Vector3(s * (W / 2.0 - 0.18), CLEARANCE + 0.04, zi * (L / 2.0 - AXLE) + WHEEL_R + 0.1))

	if int(cfg.get("engine", 0)) >= 3 and car_id != "vortex" and car_id != "raijin":
		var hv: PackedVector2Array = _section(S, 0.24, W, L, flare)["p"]
		for sx in [-1, 1]:
			for k in 4:
				_add(body, box(Vector3(0.2, 0.008, 0.018)), dark, Vector3(sx * 0.3, _top_y(hv, 0.3 / hv[7].x) + 0.004, zf + 0.24 * L - 0.06 + k * 0.04))

	# Bodykit: Schweller, Frontlippe
	if kit >= 1:
		var sp3: PackedVector2Array = _section(S, 0.5, W, L, flare)["p"]
		var sw := sp3[3].x
		for s in [-1, 1]:
			var sk := _add(body, box(Vector3(0.07, 0.09, L - 2.0 * AXLE - 0.85)), dark, Vector3(s * (sw + 0.01), CLEARANCE + 0.05, 0))
			sk.name = "SideSkirt"
		_add(fb, box(Vector3(fw * 2.0 - 0.1, 0.03, 0.18)), dark, Vector3(0, CLEARANCE - 0.01, zf + 0.06))

	# Spoiler
	var sp: int = cfg["spoiler"]
	var wz := zr - 0.25
	var dp: PackedVector2Array = _section(S, (wz - zf) / L, W, L, flare)["p"]
	var deck_y := dp[10].y
	if sp == 0 and car_id == "kaze":
		# Serienflügel: Bügel von den äußeren Heckkanten, nach hinten geneigt
		for s in [-1, 1]:
			_add(body, box(Vector3(0.07, 0.25, 0.16)), paint, Vector3(s * (W / 2.0 - 0.25), deck_y + 0.09, wz + 0.03)).rotation_degrees.x = 20
		_add(body, box(Vector3(W - 0.4, 0.04, 0.27)), paint, Vector3(0, deck_y + 0.21, wz + 0.08)).rotation_degrees.x = -5
	elif sp == 0 and car_id == "raijin":
		# Serienflügel: hoch, zwei Blätter
		for s in [-1, 1]:
			_add(body, box(Vector3(0.05, 0.26, 0.12)), dark, Vector3(s * (W / 2.0 - 0.32), deck_y + 0.13, wz))
			_add(body, box(Vector3(0.035, 0.16, 0.38)), paint, Vector3(s * (W / 2.0 - 0.07), deck_y + 0.28, wz))
		_add(body, box(Vector3(W - 0.14, 0.04, 0.36)), paint, Vector3(0, deck_y + 0.26, wz))
		_add(body, box(Vector3(W - 0.14, 0.03, 0.14)), paint, Vector3(0, deck_y + 0.33, wz + 0.12)).rotation_degrees.x = -14
	elif sp == 1:
		_add(body, box(Vector3(W - 0.4, 0.045, 0.16)), paint, Vector3(0, deck_y + 0.02, zr - 0.12))
	elif sp >= 2:
		var hgt := 0.22 if sp == 2 else 0.4
		var ww := W - 0.12 if sp == 2 else W + 0.04
		for s in [-1, 1]:
			_add(body, box(Vector3(0.05, hgt, 0.1)), dark, Vector3(s * (W / 2 - 0.38), deck_y + hgt / 2, wz))
			_add(body, box(Vector3(0.04, 0.18, 0.42)), paint, Vector3(s * ww / 2, deck_y + hgt + 0.02, wz))
		_add(body, box(Vector3(ww, 0.045, 0.4)), paint, Vector3(0, deck_y + hgt, wz))
		if sp == 3:
			_add(body, box(Vector3(ww, 0.04, 0.2)), dark, Vector3(0, deck_y + hgt + 0.1, wz + 0.1))

	# Unterbodenneon: weicher Lichtteppich auf der Straße (Decal, liegt auf dem Asphalt statt darüber, daher keine
	# Spiegelung als Block) plus zwei schwache Lichter für Bordsteine und Nachbarautos
	var neon: Dictionary = P["neon"]["options"][cfg["neon"]]
	if neon.has("color"):
		var nc: Color = neon["color"]
		var dc := Decal.new()
		dc.size = Vector3(W + 1.5, 1.2, L + 1.3)
		dc.texture_emission = _glow_texture()
		dc.emission_energy = 2.2
		dc.modulate = nc
		dc.albedo_mix = 0.0
		dc.upper_fade = 0.2
		dc.lower_fade = 0.3
		dc.cull_mask = 0xFFFFF & ~CAR_LAYER
		dc.distance_fade_enabled = true
		dc.distance_fade_begin = 70.0
		dc.distance_fade_length = 20.0
		dc.position.y = 0.3
		root.add_child(dc)
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			# Browser (WebGL) kennt keine Decals: dort ein flacher, additiver Lichtfleck knapp über dem Asphalt
			dc.queue_free()
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.albedo_texture = _glow_texture()
			gm.albedo_color = Color(nc.r * 1.4, nc.g * 1.4, nc.b * 1.4)
			gm.disable_receive_shadows = true
			var pm := PlaneMesh.new()
			pm.size = Vector2(W + 1.5, L + 1.3)
			var gl := MeshInstance3D.new()
			gl.mesh = pm
			gl.material_override = gm
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gl.position.y = 0.03
			root.add_child(gl)
		for z in [-1, 1]:
			var ol := OmniLight3D.new()
			ol.light_color = nc
			ol.light_energy = 0.9
			ol.light_specular = 0.0  # kein Glanzpunkt: sonst spiegelt sich das Licht als Streifen in Pfützen
			ol.omni_range = 2.6
			ol.position = Vector3(0, 0.12, z * L * 0.3)
			body.add_child(ol)

	# Auspuff + Nitroflammen
	var flames := []
	var flame_m := mat(Color(0.3, 0.6, 1), 0, 0.5, Color(0.3, 0.6, 1.0), 6.0)
	flame_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_m.albedo_color.a = 0.8
	var pr: float = S.get("pipe_r", 0.05) * (1.25 if int(cfg.get("engine", 0)) + int(cfg.get("turbo", 0)) >= 2 else 1.0)
	var chrome := mat(Color(0.75, 0.75, 0.78), 0.95, 0.15)
	for x in S.get("pipes", [-0.38, 0.38]):  # RX-7: ein Endrohr in der Mitte
		var pipe := CylinderMesh.new()
		pipe.top_radius = pr - 0.005
		pipe.bottom_radius = pr
		pipe.height = 0.16
		var p := _add(body, pipe, chrome, Vector3(x, CLEARANCE + 0.08, zr + 0.03))
		p.rotation_degrees.x = 90
		_add(body, _disc(pr * 0.72, 0.01), dark, Vector3(x, CLEARANCE + 0.08, zr + 0.112)).rotation_degrees.x = 90
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.7
		var f := _add(body, cone, flame_m, Vector3(x, CLEARANCE + 0.08, zr + 0.4))
		f.rotation_degrees.x = 90
		f.visible = false
		flames.append(f)

	# Räder
	var tire_m := mat(Color(0.05, 0.05, 0.05), 0, 0.9)
	var rim_m := mat(rim["color"], 0.65, 0.28)
	var rotor_m := mat(Color(0.42, 0.42, 0.44), 0.8, 0.35)
	var caliper_m := mat(Color(0.85, 0.06, 0.04), 0.3, 0.35) if perf > 0 else mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	var fronts := []
	var spinners := []
	var track := W / 2 - 0.15 + (0.05 if kit == 2 else 0.0)  # bündig unter dem Kotflügel
	var tw: float = S.get("tire_w", 0.24)
	var o := tw / 2.0
	for zi in [-1, 1]:
		for s in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * track, WHEEL_R, zi * (L / 2 - AXLE))
			root.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var tire := CylinderMesh.new()
			tire.top_radius = WHEEL_R
			tire.bottom_radius = WHEEL_R
			tire.height = tw
			tire.radial_segments = 14
			_add(spin, tire, tire_m, Vector3.ZERO).rotation_degrees.z = 90
			var disc := CylinderMesh.new()
			disc.top_radius = rim["radius"]
			disc.bottom_radius = rim["radius"]
			disc.height = 0.02
			disc.radial_segments = 14
			# Schichten mit klarem Abstand (Reifen bis o, Bremsscheibe o + 0.004, Sattel o + 0.01, Speichen bis o + 0.025)
			if rim["spokes"] > 0:
				var rotor := CylinderMesh.new()
				rotor.top_radius = rim["radius"] * 0.8
				rotor.bottom_radius = rim["radius"] * 0.8
				rotor.height = 0.008
				rotor.radial_segments = 14
				_add(spin, rotor, rotor_m, Vector3(s * (o + 0.004), 0, 0)).rotation_degrees.z = 90
				_add(spin, _disc(rim["radius"] * 0.26, 0.012), mat(Color(0.12, 0.12, 0.12), 0.6, 0.4), Vector3(s * (o + 0.02), 0, 0)).rotation_degrees.z = 90
				# Bremssattel steht still (am Achsschenkel), oben hinten an der Scheibe
				var cal := _add(pivot, box(Vector3(0.012, rim["radius"] * 0.42, 0.09)), caliper_m,
					Vector3(s * (o + 0.013), rim["radius"] * 0.5, rim["radius"] * 0.38))
				cal.rotation_degrees.x = -40.0
			else:
				_add(spin, disc, rim_m, Vector3(s * (o + 0.002), 0, 0)).rotation_degrees.z = 90
			var n: int = rim["spokes"]
			var rr: float = rim["radius"]
			for k in n:
				var a := TAU * k / n
				var sk := _add(spin, box(Vector3(0.012, rr * 0.95, 0.05)), rim_m,
					Vector3(s * (o + 0.019), cos(a) * rr * 0.5, sin(a) * rr * 0.5))
				sk.rotation.x = a
			if n > 0:  # Felgenhorn als Ring
				var lip := TorusMesh.new()
				lip.inner_radius = rr * 0.86
				lip.outer_radius = rr
				lip.rings = 16
				lip.ring_segments = 6
				var lm := _add(spin, lip, rim_m, Vector3(s * (o + 0.016), 0, 0))
				lm.rotation_degrees.z = 90
				lm.scale = Vector3(1, 0.35, 1)
			spinners.append(spin)
			if zi == -1:
				fronts.append(pivot)

	body.position.y -= Catalog.part_of(cfg, "suspension")["drop"] + S.get("drop", 0.0)
	if not OS.get_cmdline_user_args().has("--nobatch"):
		_merge_parts(root, body, fronts, spinners, flames)
		if lod:
			_build_lod(root, flames, GameState.car_lod_distance())
	_set_layer(root)
	root.set_meta("body", body)
	root.set_meta("front_pivots", fronts)
	root.set_meta("spinners", spinners)
	root.set_meta("flames", flames)
	root.set_meta("length", L)
	root.set_meta("width", W)
	root.set_meta("eye", Vector3(0, S["roof"] - 0.1, zf + (S["cowl"] + 0.07) * L))
	return root


## Lackfarbe: "Werkslack" (Stufe 0) ist je Auto eigen (Kaizen in Championship-Weiß), sonst die gewählte Farbe
static func paint_color(car_id: String, cfg: Dictionary) -> Color:
	var opt: Dictionary = Catalog.PARTS["paint"]["options"][cfg.get("paint", 0)]
	if int(cfg.get("paint", 0)) == 0:
		return Catalog.CARS[car_id].get("paint", opt["color"])
	return opt["color"]


## Kaizen-Erkennungszeichen: Dachspoiler über der Heckscheibe und Sonnenstreifen mit Schriftzug oben in der Scheibe
static func _kaizen_extras(body: Node3D, S: Dictionary, W: float, L: float, mats: Dictionary) -> void:
	var roof_w: float = (W / 2.0 - S["tumble"]) * 2.0
	# Dachspoiler: setzt bündig an der Dachkante an und läuft flach über den Anfang der Heckscheibe
	var t0: float = S["rr"] + 0.01
	var t1: float = S["rr"] + 0.09
	var p0 := Vector3(0, _top_c(S, t0), (t0 - 0.5) * L)
	var p1 := Vector3(0, _top_c(S, t1) + 0.06, (t1 - 0.5) * L)
	var sb := Basis.looking_at(p1 - p0, Vector3.UP)
	_add(body, box(Vector3(roof_w * 0.9, 0.028, (p1 - p0).length() + 0.06)), mats["paint"], (p0 + p1) / 2.0 + Vector3(0, 0.02, 0)).basis = sb
	var ta: float = S["rf"] - 0.05
	var tb: float = S["rf"] - 0.008
	var a := Vector3(0, _top_c(S, ta), (ta - 0.5) * L)
	var b := Vector3(0, _top_c(S, tb), (tb - 0.5) * L)
	var up := (b - a).normalized()
	var bas := Basis(Vector3(-1, 0, 0), up, Vector3(-1, 0, 0).cross(up))
	var mid := (a + b) / 2.0 + bas.z * 0.012
	var strip := _add(body, box(Vector3(roof_w * 0.98, (b - a).length(), 0.008)), mat(Color(0.02, 0.06, 0.2), 0.2, 0.3), mid)
	strip.basis = bas
	var l := Label3D.new()
	l.text = "KAIZEN"
	l.font_size = 40
	l.pixel_size = 0.0022
	l.modulate = Color(0.95, 0.95, 0.95)
	l.outline_size = 0
	l.double_sided = false
	l.transform = Transform3D(bas, mid + bas.z * 0.006)
	body.add_child(l)


## Ein Auto hat 50 bis 70 Einzelteile, jedes wäre ein eigener Draw Call. Alles, was sich gemeinsam bewegt
## (Karosserie, jeder Achsschenkel, jedes Rad), wird je Material zu einer Fläche verschmolzen.
static func _merge_parts(root: Node3D, body: Node3D, fronts: Array, spinners: Array, flames: Array) -> void:
	var stops := {body: true}
	for n in fronts + spinners + flames:
		stops[n] = true
	var canon := {}
	for g in [root, body] + fronts + spinners:
		var buckets := {}
		collect_static(g, Transform3D.IDENTITY, stops, canon, buckets, func(_mi, _xf): return 0)
		merge_buckets(g, buckets)


## Fernansicht: das ganze Auto als eine Fläche in Vertexfarben, dazu je eine Fläche für Leuchtteile. Ab dist
## zeichnet die Grafikkarte nur das statt ~40 Einzelflächen; Räder und Neigung sieht man von dort ohnehin nicht.
static func _build_lod(root: Node3D, flames: Array, dist: float) -> void:
	var stops := {}
	for f in flames:
		stops[f] = true
	var buckets := {}
	collect_static(root, Transform3D.IDENTITY, stops, {}, buckets, func(_mi, _xf): return 0)
	var mesh := ArrayMesh.new()
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for key in buckets:
		var st := SurfaceTool.new()
		for it in buckets[key]:
			st.append_from(it[0], it[1], it[2])
		var m: Material = key[0]
		var plain: bool = m is StandardMaterial3D and not (m as StandardMaterial3D).emission_enabled \
			and (m as StandardMaterial3D).albedo_texture == null and key[1][0]
		if not plain:
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, m)
			continue
		st.deindex()
		var arr := st.commit_to_arrays()
		var n: int = arr[Mesh.ARRAY_VERTEX].size()
		pos.append_array(arr[Mesh.ARRAY_VERTEX])
		nrm.append_array(arr[Mesh.ARRAY_NORMAL])
		var c := PackedColorArray()
		c.resize(n)
		c.fill((m as StandardMaterial3D).albedo_color)
		col.append_array(c)
	if not pos.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = pos
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_COLOR] = col
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var lm := StandardMaterial3D.new()
		lm.vertex_color_use_as_albedo = true
		lm.vertex_color_is_srgb = true
		lm.metallic = 0.35
		lm.roughness = 0.4
		mesh.surface_set_material(mesh.get_surface_count() - 1, lm)
	# Nahansicht (alles mit Mesh außer Flammen und Lichtteppich) blendet ab dist aus, die Fernansicht ein
	var near := [root]
	while not near.is_empty():
		var nd: Node = near.pop_back()
		near.append_array(nd.get_children())
		if nd is MeshInstance3D and not stops.has(nd) and (nd as MeshInstance3D).transparency == 0.0 \
				and not ((nd as MeshInstance3D).material_override is BaseMaterial3D and (nd as MeshInstance3D).material_override.transparency):
			(nd as GeometryInstance3D).visibility_range_end = dist
			(nd as GeometryInstance3D).visibility_range_end_margin = 2.0
	var mi := MeshInstance3D.new()
	mi.name = "Lod"
	mi.mesh = mesh
	mi.visibility_range_begin = dist
	mi.visibility_range_begin_margin = 2.0
	root.add_child(mi)


## Fasst alle unbeweglichen Teile unter n je Material zusammen (Verkehrsautos, Laternen und anderes Umfahrbares)
static func merge_static(n: Node3D) -> void:
	var buckets := {}
	collect_static(n, Transform3D.IDENTITY, {}, {}, buckets, func(_mi, _xf): return 0)
	merge_buckets(n, buckets)


## Sammelt unbewegliche Mesh-Flächen unterhalb von n (nur durch einfache Node3D hindurch, ohne Skripte) in
## Eimer [Material, Format, extra] -> [[Mesh, Fläche, Transform, Knoten]]. extra(mi, xf) teilt zusätzlich auf
## (Rasterzelle, Detailstufe).
static func collect_static(n: Node, xf: Transform3D, stops: Dictionary, canon: Dictionary, buckets: Dictionary, extra: Callable) -> void:
	for c in n.get_children():
		if stops.has(c) or not c is Node3D:
			continue
		var cxf: Transform3D = xf * (c as Node3D).transform
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if mi.mesh == null or mi.get_script() != null or mi.get_child_count() > 0 or not mi.visible or mi.material_overlay \
					or mi.transparency > 0.0 or mi.visibility_range_end > 0.0:
				continue
			var parts := []
			for si in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(si)
				if m == null:
					m = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
				var cm = merge_material(m, canon)
				if cm == null or (mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES):
					parts = []
					break
				parts.append([cm, si])
			for pt in parts:
				var key := [pt[0], surface_format(mi.mesh, pt[1]), extra.call(mi, cxf)]
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append([mi.mesh, pt[1], cxf, mi])
		elif c.get_class() == "Node3D" and c.get_script() == null and (c as Node3D).visible:
			collect_static(c, cxf, stops, canon, buckets, extra)


## Verschmilzt jeden Eimer mit mindestens zwei Teilen zu einem Mesh unter parent und entfernt die Einzelteile.
## Liefert die neuen MeshInstances.
static func merge_buckets(parent: Node3D, buckets: Dictionary) -> Array:
	var made := []
	var gone := {}
	for key in buckets:
		var items: Array = buckets[key]
		if items.size() < 2:
			continue
		var st := SurfaceTool.new()
		for it in items:
			st.append_from(it[0], it[1], it[2])
			gone[it[3]] = true
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = key[0]
		mi.set_meta("merge_extra", key[2])
		parent.add_child(mi)
		made.append(mi)
	# Teile mit mehreren Flächen nur entfernen, wenn alle Flächen verschmolzen wurden
	for key in buckets:
		if buckets[key].size() < 2:
			for it in buckets[key]:
				gone.erase(it[3])
	for old in gone:
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.free()
	return made


## Material, das beim Verschmelzen stellvertretend für alle mit gleichen Werten steht, oder null, wenn es nicht geht
## (durchsichtig, Billboard, Triplanar oder ein Shader, der Position/Instanz des Einzelobjekts braucht).
static func merge_material(m: Material, canon: Dictionary):
	if m == null:
		return null
	if canon.has(m):
		return canon[m]
	var res = null
	if m is ShaderMaterial:
		var code: String = (m as ShaderMaterial).shader.code if (m as ShaderMaterial).shader else "NODE_POSITION"
		if not ("NODE_POSITION" in code or "INSTANCE" in code or "billboard" in code):
			res = m
	elif m is StandardMaterial3D:
		var sm := m as StandardMaterial3D
		if sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and sm.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED \
				and not (sm.uv1_triplanar or sm.uv2_triplanar or sm.grow or sm.use_point_size or sm.fixed_size or sm.next_pass):
			var key := []
			for prop in sm.get_property_list():
				if prop["usage"] & PROPERTY_USAGE_STORAGE and not prop["name"].begins_with("resource_"):
					var v = sm.get(prop["name"])
					key.append(v.get_instance_id() if v is Object else v)
			var k := str(key)
			if not canon.has(k):
				canon[k] = sm
			res = canon[k]
	canon[m] = res
	return res


## Welche Vertex-Daten eine Fläche hat; nur Gleiches lässt sich verschmelzen
static func surface_format(mesh: Mesh, si: int) -> Array:
	var a := mesh.surface_get_arrays(si)
	return [a[Mesh.ARRAY_NORMAL] != null, a[Mesh.ARRAY_TANGENT] != null, a[Mesh.ARRAY_TEX_UV] != null,
		a[Mesh.ARRAY_COLOR] != null, a[Mesh.ARRAY_TEX_UV2] != null, a[Mesh.ARRAY_INDEX] != null]


static func _set_layer(n: Node) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			c.layers = CAR_LAYER
		_set_layer(c)


## Weicher Lichtfleck (Rechteck mit runden, auslaufenden Rändern) für das Unterbodenneon
static func _glow_texture() -> ImageTexture:
	if _glow_tex:
		return _glow_tex
	var img := Image.create(48, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 48:
			var u := absf((x + 0.5) / 24.0 - 1.0)
			var v := absf((y + 0.5) / 48.0 - 1.0)
			var d := Vector2(maxf(u - 0.35, 0.0) / 0.65, maxf(v - 0.55, 0.0) / 0.45).length()
			var k := pow(1.0 - smoothstep(0.0, 1.0, d), 1.6)
			img.set_pixel(x, y, Color(k, k, k, k))
	_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


## Höhe der Ober-Mittellinie (Haube, Scheibe, Dach, Heckscheibe, Heckdeckel) an der Stelle t
static func _top_c(S: Dictionary, t: float) -> float:
	var cowl: float = S["cowl"]
	if t <= cowl:
		var u := t / cowl
		return S["nose"] + (S["hood"] - S["nose"]) * (1.0 - (1.0 - u) * (1.0 - u))
	if t <= S["rf"]:
		var u: float = (t - cowl) / (S["rf"] - cowl)
		return lerpf(S["hood"], S["roof"], u * (1.35 - 0.35 * u))  # Scheibe leicht gewölbt
	if t <= S["rr"]:
		var u: float = (t - S["rf"]) / (S["rr"] - S["rf"])
		return S["roof"] + 0.012 * sin(u * PI)
	if t <= S["ge"]:
		var u: float = (t - S["rr"]) / (S["ge"] - S["rr"])
		return S["roof"] - (S["roof"] - S["deck"]) * pow(u, 1.3)  # Fließheck: oben flach, unten steiler
	return lerpf(S["deck"], S["tail"], (t - S["ge"]) / (1.0 - S["ge"]))


## Querschnitt bei t: 11 Punkte (x, y) der rechten Hälfte, von unten Mitte über Radhaus, Schweller, Flanke,
## Gürtellinie und Schulter bis oben Mitte. Dazu g: 0 = Haube/Heckdeckel, 1 = volles Glashaus.
static func _section(S: Dictionary, t: float, W: float, L: float, flare: float) -> Dictionary:
	var C := CLEARANCE
	var z := (t - 0.5) * L
	var tf := AXLE / L
	var tr := 1.0 - AXLE / L
	# Draufsicht: runde Ecken, Kotflügel vorn, Hüften hinten
	var w := W / 2.0
	w -= S["round_f"] * pow(maxf(1.0 - t / 0.14, 0.0), 2.0)
	w -= S["round_r"] * pow(maxf(1.0 - (1.0 - t) / 0.12, 0.0), 2.0)
	var hip: float = (S["hips"] + flare) * exp(-pow((t - tr) / 0.1, 2.0))
	var fend: float = (0.015 + flare) * exp(-pow((t - tf) / 0.08, 2.0))
	var w2 := w + hip + fend
	var w3 := w2 - 0.05 - hip * 0.5
	# Radausschnitt
	var ra := WHEEL_R + 0.045
	var dz := minf(absf(z - (-L / 2.0 + AXLE)), absf(z - (L / 2.0 - AXLE)))
	var arch := dz < ra
	# Schürzen unten eingezogen: die Unterkante steigt zu Bug und Heck hin an
	C += 0.06 * smoothstep(0.05, 0.0, t) + 0.1 * smoothstep(0.93, 1.0, t)
	var ybot := WHEEL_R + sqrt(ra * ra - dz * dz) if arch else C + 0.05
	# Gürtellinie: vorn schnell ansteigend (Kotflügel), hinten leicht keilförmig
	var cowl: float = S["cowl"]
	var belt: float
	if t <= cowl:
		var u := t / cowl
		belt = S["nose"] - 0.04 + (S["belt"] - S["nose"] + 0.04) * (1.0 - (1.0 - u) * (1.0 - u))
	elif t <= S["ge"]:
		belt = lerpf(S["belt"], S["deck"] - 0.04, smoothstep(cowl, S["ge"], t))
	else:
		belt = lerpf(S["deck"] - 0.04, S["tail"] - 0.04, (t - S["ge"]) / (1.0 - S["ge"]))
	belt += S["fender"] * exp(-pow((t - tf) / 0.075, 2.0))
	var top := _top_c(S, t)
	# Bug und Heck oben abgerundet: die obere Kante fällt zum Ende ab und zieht sich nach innen (keine Kiste)
	var er := smoothstep(0.955, 1.0, t)
	var ef := smoothstep(0.04, 0.0, t)
	top -= 0.07 * er + 0.03 * ef
	belt -= 0.06 * er + 0.02 * ef
	w3 -= 0.1 * er + 0.06 * ef
	w2 -= 0.035 * er
	var g := clampf((top - belt - 0.04) / 0.12, 0.0, 1.0)
	var p4 := Vector2(lerpf(w3 - 0.07, w - S["tumble"], g), lerpf(belt + 0.035, top - 0.045, g))
	var y2 := clampf(maxf(C + 0.28, ybot + 0.035), C + 0.1, belt - 0.05)
	var x1 := w2 - (0.01 if arch else 0.06)
	var w_in := W / 2.0 - 0.33 if arch else x1
	var pts := PackedVector2Array([
		Vector2(0.0, C), Vector2(w_in, C), Vector2(w_in, ybot), Vector2(x1, ybot), Vector2(w2, y2),
		Vector2((w2 + w3) / 2.0 + 0.012, (y2 + belt) / 2.0), Vector2(w3, belt), p4,
		Vector2(p4.x * 0.55, top + (p4.y - top) * 0.3025), Vector2(p4.x * 0.18, top + (p4.y - top) * 0.0324),
		Vector2(0.0, top)])
	return {"p": pts, "g": g, "t": t, "z": z}


## Höhe der Oberseite bei Anteil f (0 Mitte .. 1 Schulter) eines Querschnitts
static func _top_y(p: PackedVector2Array, f: float) -> float:
	return p[10].y + (p[7].y - p[10].y) * f * f


## Material eines Hautstücks (Band b zwischen Punkt b und b+1) bei t
static func _skin(S: Dictionary, b: int, t: float, g: float, seam: bool, vinyl: int) -> String:
	if b <= 2:
		return "under"
	if seam and b <= 5:
		return "seam"
	if b == 6 and t > S["cowl"] and t < S["cp"] and g > 0.25:
		return "glass"
	if b >= 7 and t > S["cowl"] and t < S["rf"]:
		return "glass"
	# Stoffverdeck: Dach, kleines Heckfenster, hinterer Teil der Seite
	if S.get("softtop", false) and t >= S["rf"] and t < S["ge"] and (b >= 7 or (b == 6 and g > 0.25)):
		return "glass" if b >= 8 and t > S["rr"] + 0.02 and t < S["ge"] - 0.015 else "top"
	if b >= 7 and t > S["rr"] and t < S["ge"]:
		return "glass"
	var hl: Dictionary = S["hl"]
	if hl.has(b) and t < hl[b]:
		return "head"
	var tl: Dictionary = S["tl"]
	if tl.has(b) and t > tl[b]:
		return "tail"
	if (vinyl == 1 and b == 8 and t > 0.02 and t < 0.98) or (vinyl == 2 and b == 4 and t > 0.1 and t < 0.9):
		return "stripe"
	if S.get("trim_low", false) and b == 3:
		return "trim"
	return "paint"


## Karosserie-Haut aus Querschnitten: Frontschürze, Mittelteil, Heckschürze als eigene Meshes. Fugen (Schürzen,
## Türen) sind schmale dunkle Bänder zwischen zwei dicht liegenden Querschnitten.
static func _shell(body: Node3D, S: Dictionary, W: float, L: float, flare: float, vinyl: int, mats: Dictionary) -> void:
	var seams: Array = [FRONT_SEAM, REAR_SEAM] + S["doors"]
	var ra := WHEEL_R + 0.045
	# Feste Querschnitte: Fugen (zwei dicht beieinander) und Radkanten (senkrechter Übergang)
	var must := []
	for sm in seams:
		must.append_array([sm, sm + 0.006 / L])
	for wz in [-L / 2.0 + AXLE, L / 2.0 - AXLE]:
		for e in [-1.0, 1.0]:
			must.append_array([(wz + e * (ra - 0.002)) / L + 0.5, (wz + e * (ra + 0.002)) / L + 0.5])
	var extra := []
	var n := int(L / 0.09)
	for i in n + 1:
		extra.append(float(i) / n)
	extra.append_array([0.004, 0.012, 0.025, 0.045, 0.07, 0.955, 0.975, 0.988, 0.996])
	for key in ["cowl", "rf", "rr", "ge", "cp"]:
		extra.append(S[key])
	for wz in [-L / 2.0 + AXLE, L / 2.0 - AXLE]:
		for k in range(1, 14):
			extra.append((wz - ra + 2.0 * ra * k / 14.0) / L + 0.5)
	var ts := must.duplicate()
	for t in extra:
		var free := true
		for m in must:
			if absf(t - m) < 0.012 / L:
				free = false
		if free:
			ts.append(t)
	ts.sort()
	var secs := []
	for t in ts:
		if t < 0.0 or t > 1.0 or (not secs.is_empty() and t - secs[-1]["t"] < 0.0005 / L):
			continue
		secs.append(_section(S, t, W, L, flare))
	var ns := secs.size()
	var NP := 11
	var V := func(i: int, j: int) -> Vector3:
		var p: Vector2 = secs[i]["p"][j]
		return Vector3(p.x, p.y, secs[i]["z"])
	# Flächennormalen (nach außen); für die Haut gemittelte Punktnormalen -> runde Formen
	var fnorm := []
	var vnorm := []
	for i in ns:
		vnorm.append([])
		for j in NP:
			vnorm[i].append(Vector3.ZERO)
	for i in ns - 1:
		fnorm.append([])
		for j in NP - 1:
			var a: Vector3 = V.call(i, j)
			var b: Vector3 = V.call(i, j + 1)
			var c: Vector3 = V.call(i + 1, j + 1)
			var d: Vector3 = V.call(i + 1, j)
			var fn := (c - a).cross(d - b)
			var mid := (a + b + c + d) / 4.0
			if fn.dot(Vector3(mid.x, mid.y - 0.55, 0.0)) < 0.0:
				fn = -fn
			fnorm[i].append(fn)
			if j >= 3:
				for q in [[i, j], [i, j + 1], [i + 1, j], [i + 1, j + 1]]:
					vnorm[q[0]][q[1]] += fn
	var parts := {"FrontBumper": {}, "Shell": {}, "RearBumper": {}}
	var get_st := func(part: String, key: String) -> SurfaceTool:
		if not parts[part].has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			parts[part][key] = st
		return parts[part][key]
	for i in ns - 1:
		var t0: float = secs[i]["t"]
		var t1: float = secs[i + 1]["t"]
		var tm := (t0 + t1) / 2.0
		var gm: float = (secs[i]["g"] + secs[i + 1]["g"]) / 2.0
		var is_seam := false
		for sm in seams:
			if absf(t0 - sm) < 1e-6 and t1 - t0 < 0.01 / L:
				is_seam = true
		var part := "FrontBumper" if tm < FRONT_SEAM else ("RearBumper" if tm > REAR_SEAM + 0.001 else "Shell")
		for j in NP - 1:
			var fn: Vector3 = fnorm[i][j]
			if fn.length_squared() < 1e-12:
				continue
			var key := _skin(S, j, tm, gm, is_seam, vinyl)
			if key == "paint" and part != "Shell" and j == 4 and S.get("black_bumpers", false):
				key = "trim"
			var st: SurfaceTool = get_st.call(part, key)
			var q := [[i, j], [i, j + 1], [i + 1, j + 1], [i + 1, j]]
			var pos := []
			var nrm := []
			for c in q:
				pos.append(V.call(c[0], c[1]))
				var vn: Vector3 = vnorm[c[0]][c[1]]
				nrm.append(vn.normalized() if j >= 3 and vn.length_squared() > 1e-12 else fn.normalized())
			for side in [1.0, -1.0]:
				var m := Vector3(side, 1.0, 1.0)
				var P := []
				var N := []
				for k in 4:
					P.append(pos[k] * m)
					N.append(nrm[k] * m)
				_tri(st, P[0], P[1], P[2], N[0], N[1], N[2], fn * m)
				_tri(st, P[0], P[2], P[3], N[0], N[2], N[3], fn * m)
	# Stirnflächen vorn und hinten
	for e in [[0, "FrontBumper", -1.0], [ns - 1, "RearBumper", 1.0]]:
		var p: PackedVector2Array = secs[e[0]]["p"]
		var poly := PackedVector2Array()
		for j in NP:
			poly.append(p[j])
		for j in range(NP - 2, 0, -1):
			poly.append(Vector2(-p[j].x, p[j].y))
		var clean := PackedVector2Array()
		for v in poly:
			if clean.is_empty() or v.distance_to(clean[-1]) > 0.002:
				clean.append(v)
		if clean[0].distance_to(clean[-1]) < 0.002:
			clean.remove_at(clean.size() - 1)
		var tri := Geometry2D.triangulate_polygon(clean)
		var z: float = secs[e[0]]["z"]
		var nz := Vector3(0, 0, e[2])
		var st: SurfaceTool = get_st.call(e[1], "paint")
		for k in range(0, tri.size(), 3):
			var a := Vector3(clean[tri[k]].x, clean[tri[k]].y, z)
			var b := Vector3(clean[tri[k + 1]].x, clean[tri[k + 1]].y, z)
			var c := Vector3(clean[tri[k + 2]].x, clean[tri[k + 2]].y, z)
			_tri(st, a, b, c, nz, nz, nz, nz)
	for part in parts:
		var mesh := ArrayMesh.new()
		for key in parts[part]:
			parts[part][key].commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[key])
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = mesh
		body.add_child(mi)


## Dreieck mit Punktnormalen; Reihenfolge so, dass die Vorderseite nach nf zeigt (Godot: im Uhrzeigersinn)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nf: Vector3) -> void:
	if (c - a).cross(b - a).dot(nf) < 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


## Animiert Räder, Lenkung, Karosserie-Neigung und Nitroflammen.
static func animate(car: Node3D, speed: float, steer: float, roll: float, pitch: float, nitro_on: bool, delta: float) -> void:
	for p in car.get_meta("front_pivots"):
		p.rotation.y = -steer * 0.5
	for s in car.get_meta("spinners"):
		s.rotation.x -= speed / WHEEL_R * delta
	var body: Node3D = car.get_meta("body")
	body.rotation.z = lerpf(body.rotation.z, roll, 8.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, pitch, 6.0 * delta)
	for f in car.get_meta("flames"):
		f.visible = nitro_on
		if nitro_on:
			f.scale = Vector3.ONE * randf_range(0.7, 1.3)


static func mat(c: Color, metal := 0.0, rough := 0.5, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	return m


## Flache Scheibe (runde Lampe)
static func _disc(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _add(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Quader, dessen Oberseite kleiner ist (bottom/top = Breite, Länge). top_z verschiebt die Oberseite nach hinten.
static func tapered_box(bottom: Vector2, top: Vector2, h: float, top_z: float) -> ArrayMesh:
	var bfl := Vector3(-bottom.x / 2, 0, -bottom.y / 2)
	var bfr := Vector3(bottom.x / 2, 0, -bottom.y / 2)
	var brr := Vector3(bottom.x / 2, 0, bottom.y / 2)
	var brl := Vector3(-bottom.x / 2, 0, bottom.y / 2)
	var tfl := Vector3(-top.x / 2, h, top_z - top.y / 2)
	var tfr := Vector3(top.x / 2, h, top_z - top.y / 2)
	var trr := Vector3(top.x / 2, h, top_z + top.y / 2)
	var trl := Vector3(-top.x / 2, h, top_z + top.y / 2)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for q in [[tfl, trl, trr, tfr], [bfl, bfr, brr, brl], [bfr, bfl, tfl, tfr],
			[brl, brr, trr, trl], [bfr, tfr, trr, brr], [brl, trl, tfl, bfl]]:
		_quad(st, q[0], q[1], q[2], q[3])
	return st.commit()


## Quad gegen den Uhrzeigersinn von außen gesehen; Godot erwartet Dreiecke im Uhrzeigersinn.
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	for v in [a, c, b, a, d, c]:
		st.set_normal(n)
		st.add_vertex(v)


## Werkstatt-Ansicht in der Garage: Motorhaube auf mit Motor (mode "engine") oder Kofferraum auf mit
## Nitroflaschen (mode "nitro"). Die Teile zeigen die eingebauten Tuning-Stufen. "" räumt wieder ab.
static func showcase(car: Node3D, car_id: String, cfg: Dictionary, mode: String) -> void:
	var body: Node3D = car.get_meta("body")
	var old := body.get_node_or_null("Showcase")
	if old:
		body.remove_child(old)
		old.queue_free()
	if mode == "":
		return
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var L: float = spec["length"]
	var W: float = spec["width"]
	var flare := 0.06 if int(cfg.get("bodykit", 0)) == 2 else 0.0
	var zf := -L / 2.0
	var sc := Node3D.new()
	sc.name = "Showcase"
	body.add_child(sc)
	var paint := mat(paint_color(car_id, cfg), 0.55, 0.22)
	var bay := mat(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	var chrome := mat(Color(0.78, 0.78, 0.8), 0.95, 0.15)
	var t0: float
	var t1: float
	if mode == "engine":
		t0 = 0.1
		t1 = S["cowl"] - 0.035
	else:
		t0 = minf(S["ge"], 0.84) + 0.01
		t1 = 0.965
	var p0: PackedVector2Array = _section(S, t0, W, L, flare)["p"]
	var p1: PackedVector2Array = _section(S, t1, W, L, flare)["p"]
	var y0 := p0[10].y
	var y1 := p1[10].y
	var depth := (t1 - t0) * L
	var half := minf(p0[7].x, p1[7].x) * 0.86
	# Fläche entlang der Haube bzw. des Hecks, darauf die Teile
	var plate := Node3D.new()
	plate.position = Vector3(0, (y0 + y1) / 2.0 + 0.012, zf + (t0 + t1) / 2.0 * L)
	plate.rotation.x = atan2(y0 - y1, depth)
	sc.add_child(plate)
	_add(plate, box(Vector3(half * 2.0, 0.02, depth)), bay, Vector3.ZERO)
	# Deckel: an der Scheibe (Haube) bzw. an der Heckscheibe (Kofferraum) angeschlagen, offen
	var hinge := Node3D.new()
	sc.add_child(hinge)
	var lid := box(Vector3(half * 2.0 + 0.06, 0.025, depth + 0.04))
	if mode == "engine":
		hinge.position = Vector3(0, y1 + 0.03, zf + t1 * L)
		hinge.rotation_degrees.x = 62.0
		_add(hinge, lid, paint, Vector3(0, 0, -(depth + 0.04) / 2.0))
		_add(hinge, box(Vector3(half * 2.0 - 0.1, 0.01, depth - 0.1)), bay, Vector3(0, -0.018, -(depth + 0.04) / 2.0))
		var stage := int(cfg.get("engine", 0))
		var turbo := int(cfg.get("turbo", 0))
		var cover_cols := [Color(0.45, 0.45, 0.47), Color(0.8, 0.08, 0.06), Color(0.1, 0.3, 0.9), Color(0.85, 0.65, 0.15)]
		var cover := mat(cover_cols[stage], 0.6, 0.3)
		var cyl: int = spec["sound"].get("cyl", 4)
		var bl := minf(depth * 0.55, 0.12 + cyl * 0.07)
		# Motorblock mit Ventildeckel, Ansaugbrücke, Zündkerzen-Reihe
		_add(plate, box(Vector3(0.42, 0.16, bl)), mat(Color(0.18, 0.18, 0.19), 0.6, 0.5), Vector3(-0.05, 0.09, 0.02))
		_add(plate, box(Vector3(0.36, 0.06, bl - 0.04)), cover, Vector3(-0.05, 0.2, 0.02))
		for k in cyl if cyl <= 6 else 4:
			var zz := -bl / 2.0 + 0.05 + k * (bl - 0.1) / maxf((cyl if cyl <= 6 else 4) - 1, 1)
			_add(plate, box(Vector3(0.05, 0.03, 0.03)), mat(Color(0.05, 0.05, 0.05), 0.2, 0.6), Vector3(-0.05, 0.245, 0.02 + zz))
			_add(plate, box(Vector3(0.16, 0.035, 0.04)), chrome if stage >= 2 else mat(Color(0.3, 0.3, 0.32), 0.7, 0.4), Vector3(0.17, 0.15, 0.02 + zz))
		_add(plate, box(Vector3(0.08, 0.1, bl)), chrome if stage >= 2 else mat(Color(0.3, 0.3, 0.32), 0.7, 0.4), Vector3(0.27, 0.16, 0.02))
		# Luftfilter: offener Pilzfilter ab Stufe 1, sonst Kasten
		if stage >= 1:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 0.075
			cone.height = 0.13
			cone.radial_segments = 12
			_add(plate, cone, cover, Vector3(0.36, 0.17, -bl / 2.0 - 0.02)).rotation_degrees.z = -90
		else:
			_add(plate, box(Vector3(0.2, 0.1, 0.16)), mat(Color(0.06, 0.06, 0.06), 0.1, 0.8), Vector3(half - 0.2, 0.06, -depth / 2.0 + 0.14))
		# Turbolader: Schneckengehäuse mit Rohr zum Ladeluftkühler
		if turbo > 0 or spec["sound"].get("turbo", 0.0) > 0.4:
			var snail := TorusMesh.new()
			snail.inner_radius = 0.03
			snail.outer_radius = 0.075 + 0.012 * turbo
			_add(plate, snail, chrome, Vector3(-0.35, 0.13, -0.02)).rotation_degrees.z = 90
			var pipe := CylinderMesh.new()
			pipe.top_radius = 0.028
			pipe.bottom_radius = 0.028
			pipe.height = depth * 0.45
			_add(plate, pipe, chrome, Vector3(-0.35, 0.09, -depth * 0.25)).rotation_degrees.x = 90
		# Domstrebe ab Fahrwerk Gewinde
		if int(cfg.get("suspension", 0)) >= 2:
			_add(plate, box(Vector3(half * 1.8, 0.025, 0.035)), mat(Color(0.85, 0.08, 0.06), 0.6, 0.3), Vector3(0, 0.27, depth / 2.0 - 0.08))
		# Kühler vorn, Batterie
		_add(plate, box(Vector3(half * 1.6, 0.12, 0.04)), mat(Color(0.2, 0.2, 0.22), 0.7, 0.4), Vector3(0, 0.07, -depth / 2.0 + 0.05))
		_add(plate, box(Vector3(0.14, 0.12, 0.12)), mat(Color(0.05, 0.05, 0.06), 0.1, 0.7), Vector3(-half + 0.12, 0.07, depth / 2.0 - 0.14))
		_add(plate, box(Vector3(0.03, 0.02, 0.03)), mat(Color(0.8, 0.05, 0.05), 0, 0.5), Vector3(-half + 0.08, 0.14, depth / 2.0 - 0.12))
	else:
		hinge.position = Vector3(0, y0 + 0.03, zf + t0 * L)
		hinge.rotation_degrees.x = -64.0
		_add(hinge, lid, paint, Vector3(0, 0, (depth + 0.04) / 2.0))
		_add(hinge, box(Vector3(half * 2.0 - 0.1, 0.01, depth - 0.1)), bay, Vector3(0, -0.018, (depth + 0.04) / 2.0))
		# Nitroflaschen quer im Kofferraum, mit Halteschellen und Ventilen
		var stage := int(cfg.get("nitro", 0))
		var n := 1 + mini(stage, 1)
		var r := 0.065 + 0.012 * stage
		var bottle := mat(Color(0.08, 0.3, 0.95), 0.5, 0.25)
		for k in n:
			var zz := (k - (n - 1) / 2.0) * (r * 2.4)
			var b := CylinderMesh.new()
			b.top_radius = r
			b.bottom_radius = r
			b.height = half * 1.5
			b.radial_segments = 14
			_add(plate, b, bottle, Vector3(0, r + 0.01, zz)).rotation_degrees.z = 90
			var cap := CylinderMesh.new()
			cap.top_radius = r * 0.45
			cap.bottom_radius = r * 0.6
			cap.height = 0.06
			_add(plate, cap, chrome, Vector3(half * 0.78, r + 0.01, zz)).rotation_degrees.z = -90
			for x in [-0.25, 0.25]:
				_add(plate, box(Vector3(0.03, r * 2.1, r * 2.1)), chrome, Vector3(x * half * 1.4, r + 0.01, zz))
		var hose := CylinderMesh.new()
		hose.top_radius = 0.012
		hose.bottom_radius = 0.012
		hose.height = depth * 0.8
		_add(plate, hose, mat(Color(0.05, 0.05, 0.05), 0.2, 0.6), Vector3(half * 0.85, 0.03, 0)).rotation_degrees.x = 90
	_set_layer(sc)
