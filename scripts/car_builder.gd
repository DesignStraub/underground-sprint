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
static var _mesh_cache := {}  # Reifen, Speichen, Flügel, Kennzeichen: einmal gebaut, von allen Autos geteilt

## t = Anteil der Länge von vorn (0) nach hinten (1), Höhen in Metern über dem Boden.
##   nose/hood: Bug-Oberkante und Haube an der Scheibe, cowl: Scheibenansatz, rf/rr: Dach von/bis,
##   ge: Ende der Heckscheibe, cp: Ende der Seitenfenster, roof/deck/tail: Dach, Heckdeckel, Heckkante,
##   belt: Gürtellinie, fender: Kotflügel-Buckel über dem Vorderrad, hips: Hüften über dem Hinterrad,
##   round_f/round_r: Rundung der Ecken in der Draufsicht, tumble: so viel schmaler ist das Dach,
##   hl/tl: Hautband -> bis/ab welchem t es leuchtet (Scheinwerfer/Rückleuchten), doors: Türfugen,
##   intake: Lufteinlass vorn (Anteil der Breite, Höhe)
## Optional: pipes/pipe_r (Endrohre), tire_w (Reifenbreite), softtop (Stoffverdeck), black_bumpers (Schürzen aus
##   schwarzem Kunststoff), trim_low (schwarzer Streifen unten an der Flanke), wheel_r (Radradius), axle (Achse so weit
##   von Bug und Heck), mid (Mittelmotor: Einlässe in den Flanken), rear_engine (Heckmotor), chrome_bumpers
##   (Chromstoßstangen), overfenders (aufgeschraubte Kotflügelverbreiterungen)
const SHAPES := {
	"kaizen": {  # JDM-Fließheck (Civic-EG-Gefühl): rundliche flache Nase, schmale breite Scheinwerfer, große Scheiben,
		# langes Dach, steile Heckscheibe, fast senkrechte Klappe mit umlaufenden Rückleuchten, dicker Endtopf
		"nose": 0.6, "hood": 0.82, "cowl": 0.3, "rf": 0.49, "rr": 0.66, "ge": 0.935, "cp": 0.85,
		"roof": 1.29, "deck": 0.99, "tail": 0.95, "belt": 0.8, "fender": 0.0, "hips": 0.02,
		"round_f": 0.22, "round_r": 0.08, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.315, 0.62], "intake": Vector2(0.48, 0.06), "pipes": [0.46], "pipe_r": 0.085, "trim_low": true,
		"drop": 0.035,  # ab Werk etwas tiefer
	},
	"mirai": {  # 350Z: lange Haube, Dachbogen fließt ins kurze Heck, breite Hüften
		"nose": 0.6, "hood": 0.86, "cowl": 0.42, "rf": 0.56, "rr": 0.64, "ge": 0.89, "cp": 0.71,
		"roof": 1.22, "deck": 0.95, "tail": 0.96, "belt": 0.85, "fender": 0.04, "hips": 0.055,
		"round_f": 0.14, "round_r": 0.12, "tumble": 0.21, "hl": {6: 0.14, 5: 0.05}, "tl": {},
		"doors": [0.435, 0.68], "intake": Vector2(0.5, 0.12),
	},
	"sakura": {  # Silvia-Coupé: schmale Scheinwerfer, Stufenheck mit kurzem Kofferraum
		"nose": 0.6, "hood": 0.84, "cowl": 0.38, "rf": 0.54, "rr": 0.67, "ge": 0.81, "cp": 0.69,
		"roof": 1.22, "deck": 0.93, "tail": 0.94, "belt": 0.84, "fender": 0.02, "hips": 0.025,
		"round_f": 0.12, "round_r": 0.07, "tumble": 0.16, "hl": {6: 0.09, 5: 0.035}, "tl": {},
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
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.12, "hl": {6: 0.075, 5: 0.06}, "tl": {},
		"doors": [0.37, 0.545, 0.725], "intake": Vector2(0.62, 0.17), "pipes": [0.42], "pipe_r": 0.072,
	},
	"tsubame": {  # Roadster (S2000/MX-5): lange Haube, kleines Stoffverdeck weit hinten, kurzes Heck
		"nose": 0.57, "hood": 0.8, "cowl": 0.465, "rf": 0.585, "rr": 0.655, "ge": 0.765, "cp": 0.71,
		"roof": 1.1, "deck": 0.9, "tail": 0.92, "belt": 0.82, "fender": 0.05, "hips": 0.055,
		"round_f": 0.19, "round_r": 0.13, "tumble": 0.27, "hl": {6: 0.125, 5: 0.045}, "tl": {},
		"doors": [0.47, 0.695], "intake": Vector2(0.42, 0.1), "pipes": [-0.32, 0.32], "softtop": true,
	},
	"hachi": {  # 80er-Fließheck (AE86): kantig, Klappscheinwerfer, schwarze Stoßfänger, breites Leuchtenband
		"nose": 0.63, "hood": 0.84, "cowl": 0.37, "rf": 0.52, "rr": 0.665, "ge": 0.9, "cp": 0.75,
		"roof": 1.22, "deck": 0.96, "tail": 0.95, "belt": 0.87, "fender": 0.0, "hips": 0.015,
		"round_f": 0.05, "round_r": 0.04, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.385, 0.66], "intake": Vector2(0.7, 0.05), "pipes": [-0.46], "pipe_r": 0.04,
		"tire_w": 0.2, "black_bumpers": true, "trim_low": true,
	},
	"hayate": {  # 90er-Coupé (Integra-Gefühl): flache Nase mit vier runden Scheinwerfern, lange schräge
		# Heckklappe, Eckleuchten, hoher Flügel auf der Klappe
		"nose": 0.6, "hood": 0.83, "cowl": 0.37, "rf": 0.51, "rr": 0.62, "ge": 0.9, "cp": 0.79,
		"roof": 1.25, "deck": 0.97, "tail": 0.96, "belt": 0.81, "fender": 0.01, "hips": 0.03,
		"round_f": 0.17, "round_r": 0.07, "tumble": 0.17, "hl": {}, "tl": {},
		"doors": [0.375, 0.64], "intake": Vector2(0.56, 0.1), "pipes": [0.44], "pipe_r": 0.062,
	},
	"kitsune": {  # Fließheck-Coupé mit Klappscheinwerfern (180SX-Gefühl): lange flache Haube, flaches Dach, Heckscheibe bis
		# fast ans Ende, Leuchten über die ganze Klappe, kleiner Bürzel
		"nose": 0.58, "hood": 0.8, "cowl": 0.4, "rf": 0.53, "rr": 0.61, "ge": 0.925, "cp": 0.75,
		"roof": 1.22, "deck": 0.96, "tail": 0.95, "belt": 0.8, "fender": 0.015, "hips": 0.03,
		"round_f": 0.15, "round_r": 0.06, "tumble": 0.19, "hl": {}, "tl": {},
		"doors": [0.405, 0.665], "intake": Vector2(0.62, 0.08), "pipes": [0.42], "pipe_r": 0.07,
	},
	"tenshi": {  # Mittelmotor (MR2-Gefühl): kurze flache Nase mit Klappscheinwerfern, Kabine weit vorn, steiles kleines
		# Heckfenster, lange Motorhaube hinten, breite Hüften mit Lufteinlässen, Bürzel
		"nose": 0.56, "hood": 0.76, "cowl": 0.335, "rf": 0.47, "rr": 0.575, "ge": 0.665, "cp": 0.65,
		"roof": 1.18, "deck": 0.99, "tail": 0.97, "belt": 0.8, "fender": 0.03, "hips": 0.07,
		"round_f": 0.2, "round_r": 0.1, "tumble": 0.21, "hl": {}, "tl": {},
		"doors": [0.355, 0.58], "intake": Vector2(0.45, 0.07), "pipes": [-0.36, 0.36], "mid": true,
	},
	"kumo": {  # Viertürer mit Heckantrieb (Chaser-Gefühl): lange Haube, hohes Glashaus, langer Kofferraum, große eckige
		# Leuchten, Chrom
		"nose": 0.66, "hood": 0.86, "cowl": 0.35, "rf": 0.485, "rr": 0.69, "ge": 0.805, "cp": 0.75,
		"roof": 1.33, "deck": 0.99, "tail": 0.99, "belt": 0.87, "fender": 0.0, "hips": 0.015,
		"round_f": 0.07, "round_r": 0.05, "tumble": 0.12, "hl": {}, "tl": {},
		"doors": [0.365, 0.545, 0.725], "intake": Vector2(0.6, 0.11), "pipes": [-0.45, 0.45], "pipe_r": 0.055,
	},
	"shiden": {  # Mittelmotor-Supersportler (NSX-Gefühl): sehr flach, Kanzel weit vorn, lange flache Heckpartie,
		# Klappscheinwerfer, schwarzes Band über das ganze Heck, Flügel aus einem Stück mit den Flanken
		"nose": 0.54, "hood": 0.72, "cowl": 0.33, "rf": 0.455, "rr": 0.585, "ge": 0.72, "cp": 0.7,
		"roof": 1.14, "deck": 0.97, "tail": 0.99, "belt": 0.79, "fender": 0.035, "hips": 0.06,
		"round_f": 0.21, "round_r": 0.07, "tumble": 0.24, "hl": {}, "tl": {},
		"doors": [0.36, 0.6], "intake": Vector2(0.55, 0.07), "pipes": [-0.3, -0.2, 0.2, 0.3], "pipe_r": 0.045, "mid": true,
	},
	"ryujin": {  # Breites Biturbo-Coupé (300ZX-Gefühl): flache Keilnase mit schmalen liegenden Scheinwerfern, Glasdach mit
		# Mittelsteg, kurzes hohes Heck mit Leuchtenband über die ganze Breite
		"nose": 0.57, "hood": 0.8, "cowl": 0.39, "rf": 0.525, "rr": 0.62, "ge": 0.845, "cp": 0.72,
		"roof": 1.2, "deck": 0.96, "tail": 0.98, "belt": 0.82, "fender": 0.03, "hips": 0.07,
		"round_f": 0.17, "round_r": 0.06, "tumble": 0.23, "hl": {6: 0.13}, "tl": {},
		"doors": [0.42, 0.67], "intake": Vector2(0.4, 0.07), "pipes": [-0.42, 0.42], "pipe_r": 0.06,
	},
	# --- Kleinwagen: kleinere Räder (wheel_r) und kurze Überhänge (axle) ---
	"chibi": {  # Kei-Turbo (Alto-Works-Gefühl): kurz, schmal, hoch, kurze Haube mit Hutze, langes Dach, senkrechte Klappe
		"nose": 0.66, "hood": 0.87, "cowl": 0.27, "rf": 0.43, "rr": 0.81, "ge": 0.972, "cp": 0.93,
		"roof": 1.38, "deck": 0.99, "tail": 0.97, "belt": 0.86, "fender": 0.0, "hips": 0.01,
		"round_f": 0.15, "round_r": 0.05, "tumble": 0.1, "hl": {}, "tl": {},
		"doors": [0.3, 0.6], "intake": Vector2(0.42, 0.07), "pipes": [0.36], "pipe_r": 0.045, "trim_low": true,
		"wheel_r": 0.275, "axle": 0.56, "tire_w": 0.17,
	},
	"hotaru": {  # Kei-Mittelmotor-Roadster (Beat-Gefühl): winzig, flach, Stoffverdeck, Kabine in der Mitte, flaches Heck
		"nose": 0.57, "hood": 0.77, "cowl": 0.37, "rf": 0.5, "rr": 0.57, "ge": 0.66, "cp": 0.63,
		"roof": 1.16, "deck": 0.9, "tail": 0.91, "belt": 0.79, "fender": 0.03, "hips": 0.045,
		"round_f": 0.17, "round_r": 0.11, "tumble": 0.2, "hl": {6: 0.1, 5: 0.035}, "tl": {},
		"doors": [0.39, 0.62], "intake": Vector2(0.36, 0.06), "pipes": [0.34], "pipe_r": 0.04, "softtop": true, "mid": true,
		"wheel_r": 0.27, "axle": 0.52, "tire_w": 0.165,
	},
	"tanuki": {  # Allrad-Turbo-Kleinwagen (GR-Yaris-Gefühl): kurz und breit, flaches Dach, riesige Hüften, großes Gitter vorn
		"nose": 0.66, "hood": 0.89, "cowl": 0.3, "rf": 0.46, "rr": 0.72, "ge": 0.925, "cp": 0.86,
		"roof": 1.35, "deck": 1.02, "tail": 0.99, "belt": 0.87, "fender": 0.04, "hips": 0.09,
		"round_f": 0.13, "round_r": 0.07, "tumble": 0.2, "hl": {}, "tl": {},
		"doors": [0.34, 0.62], "intake": Vector2(0.72, 0.17), "pipes": [-0.36, 0.36], "pipe_r": 0.055,
		"wheel_r": 0.31, "axle": 0.66,
	},
	# --- JDM-Klassiker: Chromstoßstangen (chrome_bumpers) ---
	"kaido": {  # 70er-Hardtop (Hakosuka-Gefühl): kantige Kiste, hohe flache Front mit Gitter über die ganze Breite, runde
		# Scheinwerfer, aufgeschraubte Kotflügelverbreiterungen (overfenders), vier runde Rückleuchten
		"nose": 0.75, "hood": 0.87, "cowl": 0.36, "rf": 0.5, "rr": 0.69, "ge": 0.8, "cp": 0.74,
		"roof": 1.37, "deck": 0.96, "tail": 0.94, "belt": 0.86, "fender": 0.0, "hips": 0.0,
		"round_f": 0.04, "round_r": 0.035, "tumble": 0.1, "hl": {}, "tl": {},
		"doors": [0.375, 0.655], "intake": Vector2(0.3, 0.04), "pipes": [0.4], "pipe_r": 0.042,
		"wheel_r": 0.3, "axle": 0.74, "tire_w": 0.22, "chrome_bumpers": true, "overfenders": true,
	},
	"hakone": {  # 70er-Fließheck (S30-Gefühl): sehr lange Haube, Scheinwerfer in Mulden vorn in den Kotflügeln, kleines
		# Maul, Dach fließt bis ans Heck, Leuchten in einem schwarzen Feld
		"nose": 0.6, "hood": 0.83, "cowl": 0.47, "rf": 0.585, "rr": 0.655, "ge": 0.93, "cp": 0.83,
		"roof": 1.27, "deck": 0.96, "tail": 0.93, "belt": 0.82, "fender": 0.045, "hips": 0.045,
		"round_f": 0.16, "round_r": 0.06, "tumble": 0.18, "hl": {}, "tl": {},
		"doors": [0.49, 0.71], "intake": Vector2(0.42, 0.09), "pipes": [0.4], "pipe_r": 0.045,
		"wheel_r": 0.3, "axle": 0.72, "tire_w": 0.21, "chrome_bumpers": true,
	},
	# --- Exoten: größere Räder, lange Überhänge ---
	"kagura": {  # V10-Supersportler (LFA-Gefühl): lange Haube, Kabine weit hinten, nach hinten gezogene Scheinwerfer,
		# dreieckige Rückleuchten, drei Endrohre in der Mitte
		"nose": 0.56, "hood": 0.8, "cowl": 0.41, "rf": 0.555, "rr": 0.635, "ge": 0.86, "cp": 0.74,
		"roof": 1.2, "deck": 0.98, "tail": 0.99, "belt": 0.84, "fender": 0.04, "hips": 0.075,
		"round_f": 0.18, "round_r": 0.07, "tumble": 0.25, "hl": {6: 0.13, 5: 0.06}, "tl": {},
		"doors": [0.43, 0.68], "intake": Vector2(0.5, 0.12), "pipes": [-0.085, 0.0, 0.085], "pipe_r": 0.042,
		"wheel_r": 0.335, "axle": 0.84, "tire_w": 0.27,
	},
	"falke": {  # Heckmotor-Sportwagen (911-Gefühl): runde Scheinwerfer oben auf den Kotflügeln, flache Haube dazwischen,
		# Dach fällt in einem Bogen zum Heck, breite Hüften, Leuchtenband über das ganze Heck, Entenbürzel
		"nose": 0.56, "hood": 0.74, "cowl": 0.36, "rf": 0.5, "rr": 0.59, "ge": 0.8, "cp": 0.73,
		"roof": 1.27, "deck": 0.97, "tail": 0.95, "belt": 0.83, "fender": 0.085, "hips": 0.095,
		"round_f": 0.23, "round_r": 0.19, "tumble": 0.25, "hl": {}, "tl": {},
		"doors": [0.375, 0.655], "intake": Vector2(0.6, 0.1), "pipes": [-0.11, 0.11], "pipe_r": 0.05,
		"wheel_r": 0.33, "axle": 0.92, "tire_w": 0.26, "rear_engine": true,
	},
	"furia": {  # V12-Keil (Countach-Gefühl): sehr flach und breit, spitze Nase, Kanzel weit vorn, hoher Motordeckel mit
		# Lamellen, Y-Leuchten, sechseckige Einlässe, Endrohre in der Mitte
		"nose": 0.5, "hood": 0.71, "cowl": 0.32, "rf": 0.465, "rr": 0.55, "ge": 0.63, "cp": 0.66,
		"roof": 1.13, "deck": 1.0, "tail": 1.0, "belt": 0.8, "fender": 0.03, "hips": 0.065,
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.27, "hl": {6: 0.07}, "tl": {},
		"doors": [0.33, 0.6], "intake": Vector2(0.74, 0.12), "pipes": [-0.075, 0.075], "pipe_r": 0.058, "mid": true,
		"wheel_r": 0.345, "axle": 1.0, "tire_w": 0.3,
	},
}


static func build(car_id: String, cfg: Dictionary, headlights := true, lod := true) -> Node3D:
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var P: Dictionary = Catalog.PARTS
	var paint_c: Color = paint_color(car_id, cfg)
	var rim: Dictionary = Catalog.part_of(cfg, "rims")
	var kit: int = int(cfg.get("bodykit", 0))
	var hood: int = int(cfg.get("hood", 0))
	var L: float = spec["length"]
	var W: float = spec["width"]
	var flare := kit_flare(cfg)
	var zf := -L / 2.0
	var zr := L / 2.0

	var root := Node3D.new()
	root.name = "Car"
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)

	var paint := paint_mat(car_id, cfg)
	var dark := mat(Color(0.04, 0.04, 0.05), 0.2, 0.6)
	var stripe_c := Color(0.95, 0.95, 0.95) if paint_c.get_luminance() < 0.5 else Color(0.05, 0.05, 0.05)
	var vc: Dictionary = Catalog.part_of(cfg, "vinylcol")
	var stripe_m: Material = mat(stripe_c, 0.3, 0.3)
	if vc.get("carbon", false):
		stripe_m = carbon_mat()
	elif vc.has("color"):
		stripe_m = mat(vc["color"], 0.85 if vc.get("metal", false) else 0.3, 0.25 if vc.get("metal", false) else 0.3)
	var light_c: Color = Catalog.part_of(cfg, "lights")["color"]
	var tint: Dictionary = Catalog.part_of(cfg, "tint")
	var perf := int(cfg.get("engine", 0)) + int(cfg.get("turbo", 0)) + int(cfg.get("suspension", 0)) + int(cfg.get("tires", 0))
	var mats := {
		"paint": paint,
		"glass": mat(tint["color"], 0.8 if int(cfg.get("tint", 0)) == 3 else 0.6, 0.06),
		"under": mat(Color(0.025, 0.025, 0.03), 0.0, 0.85),
		"seam": mat(Color(0.012, 0.012, 0.016), 0.2, 0.7),
		"head": mat(Color(1, 1, 0.95).lerp(light_c, 0.5), 0, 0.3, light_c, 2.6),
		"tail": mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 2.2),
		"stripe": stripe_m,
		"carbon": carbon_mat(),
		"trim": mat(Color(0.035, 0.035, 0.04), 0.1, 0.7),
		"top": mat(Color(0.03, 0.03, 0.035), 0.0, 0.95),
	}
	_shell(body, S, W, L, flare, int(cfg.get("vinyl", 0)), mats, hood == 5 or hood == 6)
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
	elif kit != 1 and kit != 2:
		_bodykit(body, fb, S, W, L, flare, kit, fw, dark, paint, mats)
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
		"kaizen":  # EG-Gefühl: breite flache Scheinwerfer, um die Ecke gezogen, außen Blinker; dazwischen schmaler Grill
			# mit rotem Emblem; Blinker unten in der Schürze, roter Abschlepphaken
			var f_belt: float = front[6].y
			var y0 := front[5].y - 0.03
			var y1 := f_belt + 0.012
			var ym := (y0 + y1) / 2.0
			_lamp(fb, S, W, L, flare, dark, y0 - 0.012, y1 + 0.01, 0.17, 0.115, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, y0, y1, 99.0, 0.105, 0.0, 0.006)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, 0.19, 0.07, 0.0, 0.008)
			_lamp(fb, S, W, L, flare, dark, ym - 0.004, ym + 0.004, 0.19, 0.07, 0.0, 0.01)
			_add(fb, box(Vector3(0.34, y1 - y0 - 0.012, 0.012)), dark, Vector3(0, ym, zf - 0.006))
			for k in 3:
				_add(fb, box(Vector3(0.32, 0.005, 0.012)), mat(Color(0.3, 0.3, 0.32), 0.7, 0.4), Vector3(0, y0 + 0.012 + k * 0.016, zf - 0.009))
			_add(fb, box(Vector3(0.07, 0.032, 0.012)), mat(Color(0.85, 0.02, 0.03), 0.3, 0.3, Color(0.9, 0.0, 0.05), 0.6), Vector3(0, ym, zf - 0.013))
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.12, 0.035, 0.012)), amber, Vector3(s * (fw - 0.14), CLEARANCE + 0.2, zf - 0.006))
			_add(fb, box(Vector3(0.05, 0.05, 0.1)), mat(Color(0.85, 0.05, 0.04), 0.4, 0.4), Vector3(-fw * 0.55, CLEARANCE + 0.09, zf - 0.02))
			hy = ym
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
		"hayate":  # vier runde Scheinwerfer in einem dunklen Band, das um die Ecke läuft, schmaler Grillschlitz
			var y0 := front[5].y - 0.075
			var y1 := front[6].y + 0.02
			var ym := (y0 + y1) / 2.0
			var r := (y1 - y0) / 2.0 - 0.008
			_lamp(fb, S, W, L, flare, dark, y0, y1, 0.2, 0.075, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, ym - 0.02, ym + 0.02, 99.0, 0.07, 0.0, 0.007)
			var ring_m := mat(Color(0.3, 0.3, 0.32), 0.8, 0.3)
			for s in [-1, 1]:
				for x in [fw - 0.12, fw - 0.12 - 2.25 * r]:
					_add(fb, _disc(r, 0.01), ring_m, Vector3(s * x, ym, zf - 0.006)).rotation_degrees.x = 90
					_add(fb, _disc(r * 0.82, 0.012), head_m, Vector3(s * x, ym, zf - 0.009)).rotation_degrees.x = 90
			_add(fb, box(Vector3(0.36, 0.03, 0.012)), dark, Vector3(0, ym, zf - 0.006))
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.1, 0.03, 0.012)), amber, Vector3(s * (fw - 0.1), CLEARANCE + 0.24, zf - 0.006))
			hy = ym
		"kitsune":  # Klappscheinwerfer (zu), darunter ein schmales Lichtband über die ganze Front: außen Standlicht, Ecken Blinker
			_popups(body, S, W, L, flare, mats["seam"], 0.47, 0.4, 0.2, 0.5)
			var y0 := front[5].y - 0.025
			var y1 := front[6].y + 0.008
			_lamp(fb, S, W, L, flare, dark, y0 - 0.008, y1 + 0.008, 0.0, 0.09, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, y0, y1, 99.0, 0.085, 0.0, 0.006)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.3, 0.04, 0.0, 0.008)
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.16, 0.04, 0.012)), dark, Vector3(s * (fw - 0.16), CLEARANCE + 0.15, zf - 0.005))
			hy = (y0 + y1) / 2.0
		"tenshi":  # Klappscheinwerfer (zu), flache Nase, Blinker an den Ecken, runde Nebelscheinwerfer unten
			_popups(body, S, W, L, flare, mats["seam"], 0.48, 0.34, 0.16, 0.42)
			var y0 := front[5].y - 0.035
			var y1 := front[6].y
			_lamp(fb, S, W, L, flare, dark, y0 - 0.008, y1 + 0.008, fw - 0.34, 0.1, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, y0, y1, fw - 0.2, 0.095, 0.0, 0.006)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.32, 0.0, 0.0, 0.008)
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.15, 0.08, 0.012)), dark, Vector3(s * (fw - 0.17), CLEARANCE + 0.14, zf - 0.005))
				_add(fb, _disc(0.033, 0.012), head_m, Vector3(s * (fw - 0.17), CLEARANCE + 0.14, zf - 0.009)).rotation_degrees.x = 90
			hy = (y0 + y1) / 2.0
		"kumo":  # breite eckige Scheinwerfer um die Ecke, Blinker außen, Chromgrill mit Emblem dazwischen
			var y0 := front[5].y - 0.04
			var y1 := front[6].y + 0.01
			var ym := (y0 + y1) / 2.0
			var chrome_g := mat(Color(0.75, 0.75, 0.78), 0.9, 0.2)
			_lamp(fb, S, W, L, flare, dark, y0 - 0.012, y1 + 0.01, 0.27, 0.075, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, y0, y1, 99.0, 0.07, 0.0, 0.006)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, 0.29, 0.045, 0.0, 0.008)
			_lamp(fb, S, W, L, flare, dark, ym - 0.004, ym + 0.004, 0.29, 0.045, 0.0, 0.01)
			_add(fb, box(Vector3(0.5, y1 - y0, 0.014)), dark, Vector3(0, ym, zf - 0.006))
			for k in 4:
				_add(fb, box(Vector3(0.48, 0.006, 0.012)), chrome_g, Vector3(0, y0 + 0.012 + k * (y1 - y0 - 0.024) / 3.0, zf - 0.01))
			_add(fb, box(Vector3(0.5, 0.012, 0.016)), chrome_g, Vector3(0, y1 + 0.004, zf - 0.008))
			_add(fb, _disc(0.026, 0.012), chrome_g, Vector3(0, ym, zf - 0.016)).rotation_degrees.x = 90
			for s in [-1, 1]:
				_add(fb, _disc(0.035, 0.012), head_m, Vector3(s * (fw - 0.16), CLEARANCE + 0.16, zf - 0.008)).rotation_degrees.x = 90
			hy = ym
		"shiden":  # Klappscheinwerfer (zu), breites flaches Lichtband mit Blinkern, großer schwarzer Einlass
			_popups(body, S, W, L, flare, mats["seam"], 0.5, 0.36, 0.17, 0.43)
			var y0 := front[5].y - 0.03
			var y1 := front[6].y
			_lamp(fb, S, W, L, flare, dark, y0 - 0.008, y1 + 0.006, 0.0, 0.11, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, amber, y0, y1, fw - 0.14, 0.1, 0.0, 0.006)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.36, 0.0, 0.0, 0.008)
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.2, 0.06, 0.012)), dark, Vector3(s * (fw - 0.2), CLEARANCE + 0.15, zf - 0.005))
			hy = (y0 + y1) / 2.0
		"ryujin":  # schmale, flach liegende Scheinwerfer (Hautband an der Haubenkante), Blinker und Einlässe unten
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.22, 0.035, 0.012)), amber, Vector3(s * (fw - 0.17), CLEARANCE + 0.27, zf - 0.005))
				_add(fb, box(Vector3(0.22, 0.06, 0.012)), dark, Vector3(s * (fw - 0.17), CLEARANCE + 0.17, zf - 0.005))
			hy = S["nose"] - 0.06
		"chibi":  # eckige Scheinwerfer an den Ecken, dazwischen ein Grill mit Querstreben, Blinker darunter
			var y0 := front[5].y - 0.01
			var y1 := front[6].y + 0.015
			var ym := (y0 + y1) / 2.0
			_lamp(fb, S, W, L, flare, dark, y0 - 0.01, y1 + 0.01, fw - 0.29, 0.06, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.27, 0.05, 0.0, 0.008)
			_add(fb, box(Vector3((fw - 0.3) * 2.0, y1 - y0, 0.012)), dark, Vector3(0, ym, zf - 0.006))
			for k in 3:
				_add(fb, box(Vector3((fw - 0.32) * 2.0, 0.007, 0.012)), mat(Color(0.32, 0.32, 0.34), 0.7, 0.4),
					Vector3(0, y0 + 0.014 + k * (y1 - y0 - 0.028) / 2.0, zf - 0.009))
			_add(fb, box(Vector3(0.05, 0.03, 0.012)), mat(Color(0.8, 0.8, 0.82), 0.8, 0.3), Vector3(0, ym, zf - 0.012))
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.11, 0.04, 0.012)), amber, Vector3(s * (fw - 0.12), y0 - 0.075, zf - 0.006))
			hy = ym
		"hotaru":  # schmale Scheinwerfer in der Haut, kleines Maul, runde Blinker
			for s in [-1, 1]:
				_add(fb, _disc(0.024, 0.012), amber, Vector3(s * (fw - 0.1), CLEARANCE + 0.2, zf - 0.006)).rotation_degrees.x = 90
			_add(fb, box(Vector3(0.34, 0.05, 0.012)), dark, Vector3(0, CLEARANCE + 0.22, zf - 0.004))
			hy = S["nose"] - 0.05
		"tanuki":  # schmale, nach hinten gezogene Scheinwerfer, riesiges Gitter, Nebelscheinwerfer in den Ecken
			var y0 := front[6].y - 0.035
			var y1 := front[6].y + 0.018
			_lamp(fb, S, W, L, flare, dark, y0 - 0.01, y1 + 0.008, fw - 0.36, 0.1, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.34, 0.09, 0.0, 0.008)
			_lamp(fb, S, W, L, flare, amber, y0, y0 + 0.012, fw - 0.34, 0.09, 0.0, 0.011)
			var gw := fw * 2.0 * iv.x
			var gy := CLEARANCE + 0.07 + iv.y / 2.0
			for k in 4:  # Gitterstege vor dem Einlass
				_add(fb, box(Vector3(gw - 0.04, 0.008, 0.014)), mat(Color(0.12, 0.12, 0.13), 0.4, 0.5), Vector3(0, gy - iv.y / 2.0 + 0.03 + k * (iv.y - 0.06) / 3.0, zf - 0.02))
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.12, 0.07, 0.012)), dark, Vector3(s * (fw - 0.1), CLEARANCE + 0.14, zf - 0.004))
				_add(fb, box(Vector3(0.09, 0.015, 0.012)), head_m, Vector3(s * (fw - 0.1), CLEARANCE + 0.16, zf - 0.008))
			hy = (y0 + y1) / 2.0
		"kaido":  # Gitter über die ganze Front mit Chromrahmen, darin außen je ein runder Scheinwerfer
			var y0 := front[5].y + 0.01
			var y1: float = S["nose"] - 0.06
			var ym := (y0 + y1) / 2.0
			var r := (y1 - y0) / 2.0 - 0.004
			var chrome_k := mat(Color(0.78, 0.78, 0.8), 0.95, 0.15)
			_add(fb, box(Vector3(fw * 2.0 - 0.06, y1 - y0 + 0.02, 0.012)), chrome_k, Vector3(0, ym, zf - 0.004))
			_add(fb, box(Vector3(fw * 2.0 - 0.09, y1 - y0, 0.012)), dark, Vector3(0, ym, zf - 0.008))
			for k in 4:
				_add(fb, box(Vector3(fw * 2.0 - 0.6, 0.006, 0.012)), mat(Color(0.35, 0.35, 0.37), 0.8, 0.35), Vector3(0, y0 + 0.014 + k * (y1 - y0 - 0.028) / 3.0, zf - 0.012))
			_add(fb, _disc(0.03, 0.012), chrome_k, Vector3(0, ym, zf - 0.016)).rotation_degrees.x = 90
			for s in [-1, 1]:
				_add(fb, _disc(r + 0.008, 0.012), chrome_k, Vector3(s * (fw - 0.16), ym, zf - 0.012)).rotation_degrees.x = 90
				_add(fb, _disc(r, 0.012), head_m, Vector3(s * (fw - 0.16), ym, zf - 0.016)).rotation_degrees.x = 90
				_add(fb, box(Vector3(0.1, 0.035, 0.012)), amber, Vector3(s * (fw - 0.2), CLEARANCE + 0.14, zf - 0.006))
			hy = ym
		"hakone":  # runde Scheinwerfer in Mulden vorn in den Kotflügeln (mit Glasdeckel), kleines Maul, Blinker darunter
			var ym: float = S["nose"] - 0.05
			for s in [-1, 1]:
				var bucket := _add(fb, _disc(0.09, 0.05), dark, Vector3(s * (fw - 0.17), ym, zf + 0.022))
				bucket.rotation_degrees.x = 90
				_add(fb, _disc(0.084, 0.008), mat(Color(0.78, 0.78, 0.8), 0.95, 0.15), Vector3(s * (fw - 0.17), ym, zf - 0.006)).rotation_degrees.x = 90
				_add(fb, _disc(0.07, 0.01), head_m, Vector3(s * (fw - 0.17), ym, zf - 0.011)).rotation_degrees.x = 90
				_add(fb, box(Vector3(0.12, 0.035, 0.012)), amber, Vector3(s * (fw - 0.16), CLEARANCE + 0.15, zf - 0.006))
			_add(fb, box(Vector3(0.44, 0.075, 0.012)), dark, Vector3(0, CLEARANCE + 0.2, zf - 0.004))
			hy = ym
		"kagura":  # Scheinwerfer in der Haut, darunter große Einlässe an den Ecken mit Tagfahrlicht-Strich
			for s in [-1, 1]:
				_add(fb, box(Vector3(0.26, 0.11, 0.012)), dark, Vector3(s * (fw - 0.2), CLEARANCE + 0.15, zf - 0.004))
				_add(fb, box(Vector3(0.22, 0.012, 0.012)), head_m, Vector3(s * (fw - 0.2), CLEARANCE + 0.215, zf - 0.008))
			hy = S["nose"] - 0.06
		"falke":  # runde Scheinwerfer oben auf den Kotflügeln (leicht nach oben gekippt), große Einlässe unten, Tagfahrlicht
			var ht := 0.075
			var hp: PackedVector2Array = _section(S, ht, W, L, flare)["p"]
			var hx: float = hp[7].x - 0.15
			var hyy := _top_y(hp, clampf(hx / hp[7].x, 0.0, 1.0))
			var hn := Vector3(0.0, sin(deg_to_rad(28.0)), -cos(deg_to_rad(28.0)))  # Blickrichtung: vorn, 28° nach oben
			for s in [-1, 1]:
				var hc := Vector3(s * hx, hyy + 0.025, zf + ht * L)
				var bez := _add(body, _disc(0.1, 0.06), paint, hc)
				bez.rotation_degrees.x = -62
				var ring := _add(body, _disc(0.092, 0.008), mat(Color(0.78, 0.78, 0.8), 0.95, 0.15), hc + hn * 0.031)
				ring.rotation_degrees.x = -62
				var lens := _add(body, _disc(0.08, 0.008), head_m, hc + hn * 0.036)
				lens.rotation_degrees.x = -62
				_add(fb, box(Vector3(0.24, 0.1, 0.012)), dark, Vector3(s * (fw - 0.18), CLEARANCE + 0.14, zf - 0.004))
				_add(fb, box(Vector3(0.2, 0.014, 0.012)), head_m, Vector3(s * (fw - 0.18), CLEARANCE + 0.2, zf - 0.008))
			hy = hyy
		"furia":  # schmale Scheinwerfer in der Haut, Y-Tagfahrlicht, große Einlässe an den Ecken
			for s in [-1, 1]:
				var ix: float = s * (fw - 0.22)
				_add(fb, tapered_box(Vector2(0.36, 0.012), Vector2(0.26, 0.012), 0.14, 0.0), dark, Vector3(ix, CLEARANCE + 0.07, zf - 0.006))
				var y_top: float = S["nose"] - 0.045
				var arm := _add(fb, box(Vector3(0.14, 0.012, 0.012)), head_m, Vector3(s * (fw - 0.16), y_top - 0.04, zf - 0.008))
				arm.rotation_degrees.z = s * 35.0
				_add(fb, box(Vector3(0.12, 0.012, 0.012)), head_m, Vector3(s * (fw - 0.3), y_top - 0.08, zf - 0.008))
			hy = S["nose"] - 0.05
		_:
			pass
	if headlights:
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, hy, zf - 0.1)
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.light_energy = 4.0
		spot.light_color = light_c
		spot.rotation_degrees.x = -4.0
		body.add_child(spot)

	# Heck: Kennzeichen, Diffusor, Rückleuchten je Auto
	var rbm: Node3D = body.get_node("RearBumper")
	var tail_m: Material = mats["tail"]
	var rev_m := mat(Color(0.85, 0.85, 0.85), 0, 0.3, Color(1, 1, 1), 0.35)
	var rw: float = rear[6].x
	var ty: float = S["tail"] - 0.2
	# Höhen auf der Heckfläche: Gürtellinie und Flankenmitte; Leuchten liegen dazwischen und laufen um die Ecke
	var r_belt: float = rear[6].y
	var r_mid: float = rear[5].y
	var lens := mat(Color(0.25, 0.02, 0.02), 0.2, 0.25, Color(0.5, 0.0, 0.0), 0.5)  # Blende: dunkelrot, glimmt
	var lamp := func(m: Material, y0: float, y1: float, x_in: float, t_wrap: float, off: float) -> void:
		_lamp(rbm, S, W, L, flare, m, y0, y1, x_in, t_wrap, 1.0, off)
	# Kennzeichen: Schild mit dunklem Rand und Schrift
	_add(rbm, box(Vector3(0.33, 0.165, 0.01)), mat(Color(0.85, 0.85, 0.8), 0.0, 0.5), Vector3(0, CLEARANCE + 0.3, zr + 0.004))
	_add(rbm, box(Vector3(0.342, 0.177, 0.006)), dark, Vector3(0, CLEARANCE + 0.3, zr + 0.001))
	_near(_add(rbm, _plate_text(plate_text(car_id)), dark, Vector3(0, CLEARANCE + 0.296, zr + 0.0095)))
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
		"mirai":  # Bumerang: hohe Leuchte an der Ecke, weit in die Flanke gezogen, schräg geteilt, innen Rückfahrlicht
			lamp.call(dark, r_mid - 0.005, r_belt + 0.01, rw - 0.3, 0.948, 0.004)
			lamp.call(tail_m, r_mid + 0.005, r_belt, rw - 0.22, 0.952, 0.006)
			lamp.call(dark, (r_mid + r_belt) / 2.0 - 0.004, (r_mid + r_belt) / 2.0 + 0.004, rw - 0.22, 0.952, 0.009)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.06, r_belt - r_mid - 0.02, 0.012)), rev_m, Vector3(s * (rw - 0.26), (r_mid + r_belt) / 2.0, zr + 0.009))
		"sakura":  # flaches Band über das ganze Heck, außen rot um die Ecke, Mitte dunkle Blende
			var y0 := r_mid + 0.025
			var y1 := r_belt - 0.04
			lamp.call(dark, y0 - 0.012, y1 + 0.012, 0.0, 0.962, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.42, 0.966, 0.006)
			lamp.call(mats["seam"], (y0 + y1) / 2.0 - 0.004, (y0 + y1) / 2.0 + 0.004, rw - 0.42, 0.966, 0.009)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.07, y1 - y0 - 0.02, 0.012)), rev_m, Vector3(s * (rw - 0.38), (y0 + y1) / 2.0, zr + 0.01))
		"kaze":  # dunkle Felder an den Ecken, darin je zwei große runde Leuchten
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.44, 0.17, 0.01)), dark, Vector3(s * (rw - 0.25), ty, zr + 0.003))
				for k in 2:
					_add(rbm, _disc(0.066, 0.012), tail_m, Vector3(s * (rw - 0.13 - k * 0.18), ty, zr + 0.007)).rotation_degrees.x = 90
				_add(rbm, _disc(0.028, 0.012), rev_m, Vector3(s * (rw - 0.43), ty, zr + 0.007)).rotation_degrees.x = 90
		"raijin":  # breite Leuchten, um die Ecken gezogen, innen Rückfahrlicht
			var y0 := r_mid + 0.02
			var y1 := r_belt - 0.02
			lamp.call(dark, y0 - 0.012, y1 + 0.012, rw - 0.47, 0.958, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.35, 0.962, 0.006)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.1, y1 - y0, 0.012)), rev_m, Vector3(s * (rw - 0.41), (y0 + y1) / 2.0, zr + 0.009))
		"tsubame":  # schmale Leuchten über die Ecken, innen ein heller Streifen
			var y0 := r_belt - 0.085
			var y1 := r_belt - 0.02
			lamp.call(dark, y0 - 0.01, y1 + 0.01, rw - 0.38, 0.958, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.28, 0.962, 0.006)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.09, y1 - y0, 0.012)), rev_m, Vector3(s * (rw - 0.33), (y0 + y1) / 2.0, zr + 0.009))
		"hachi":  # Leuchtenband über das ganze Heck, Stoßfängerleiste aus schwarzem Kunststoff
			_add(rbm, box(Vector3(rear[4].x * 2.0 + 0.02, 0.18, 0.1)), mats["trim"], Vector3(0, CLEARANCE + 0.12, zr - 0.025))
			_add(rbm, box(Vector3(rw * 2.0 - 0.04, 0.13, 0.01)), dark, Vector3(0, ty, zr + 0.003))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.4, 0.1, 0.01)), tail_m, Vector3(s * (rw - 0.22), ty, zr + 0.006))
				_add(rbm, box(Vector3(0.09, 0.1, 0.01)), amber, Vector3(s * (rw - 0.47), ty, zr + 0.006))
		"kaizen":  # EG-Fließheck: ein Leuchtenband über die ganze Klappe. Außen rote Leuchten, um die Ecke gezogen und
			# zweigeteilt, dazwischen dunkelrote Blende, innen Rückfahrlicht; darunter die Kante der Stoßstange
			var y0 := r_mid + 0.012
			var y1 := r_belt - 0.022
			var ym := (y0 + y1) / 2.0
			var xi := rw - 0.36
			lamp.call(dark, y0 - 0.014, y1 + 0.014, 0.0, 0.956, 0.004)
			lamp.call(tail_m, y0, y1, xi, 0.962, 0.006)
			lamp.call(dark, ym - 0.005, ym + 0.005, xi, 0.962, 0.009)
			_add(rbm, box(Vector3(xi * 2.0 - 0.04, y1 - y0 - 0.03, 0.012)), lens, Vector3(0, ym, zr + 0.008))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.075, ym - y0 - 0.01, 0.012)), rev_m, Vector3(s * (xi + 0.05), (y0 + ym) / 2.0, zr + 0.011))
			lamp.call(mats["seam"], CLEARANCE + 0.43, CLEARANCE + 0.442, 0.0, REAR_SEAM + 0.004, 0.004)
		"hayate":  # Eckleuchten, oben rot, unten Blinker und Rückfahrlicht, dazwischen lackierte Klappe
			var y0 := r_mid + 0.01
			var y1 := r_belt - 0.01
			var ym := (y0 + y1) / 2.0 + 0.01
			lamp.call(dark, y0 - 0.012, y1 + 0.012, rw - 0.4, 0.956, 0.004)
			lamp.call(tail_m, ym, y1, rw - 0.38, 0.96, 0.006)
			lamp.call(amber, y0, ym - 0.006, rw - 0.16, 0.96, 0.006)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.2, ym - y0 - 0.014, 0.012)), rev_m, Vector3(s * (rw - 0.27), (y0 + ym) / 2.0 - 0.003, zr + 0.009))
		"kitsune":  # Leuchten über die ganze Klappe, mit Rippen; in der Mitte dunkelrote Blende
			var y0 := r_mid + 0.015
			var y1 := r_belt - 0.015
			lamp.call(dark, y0 - 0.012, y1 + 0.012, 0.0, 0.958, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.46, 0.962, 0.006)
			for k in 2:
				var yk := y0 + (y1 - y0) * (k + 1) / 3.0
				lamp.call(dark, yk - 0.004, yk + 0.004, rw - 0.46, 0.962, 0.009)
			_add(rbm, box(Vector3((rw - 0.48) * 2.0, y1 - y0 - 0.02, 0.012)), lens, Vector3(0, (y0 + y1) / 2.0, zr + 0.008))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.08, y1 - y0 - 0.02, 0.012)), rev_m, Vector3(s * (rw - 0.42), (y0 + y1) / 2.0, zr + 0.011))
		"tenshi":  # dunkles Band über das ganze Heck, darin je zwei runde Leuchten, Blinker um die Ecke
			var y0 := r_mid + 0.01
			var y1 := r_belt
			var ym := (y0 + y1) / 2.0
			lamp.call(dark, y0, y1, 0.0, 0.955, 0.004)
			lamp.call(amber, y0 + 0.012, y1 - 0.012, 99.0, 0.96, 0.006)
			for s in [-1, 1]:
				for k in 2:
					_add(rbm, _disc((y1 - y0) / 2.0 - 0.012, 0.012), tail_m, Vector3(s * (rw - 0.13 - k * 0.17), ym, zr + 0.009)).rotation_degrees.x = 90
				_add(rbm, _disc(0.03, 0.012), rev_m, Vector3(s * (rw - 0.47), ym, zr + 0.009)).rotation_degrees.x = 90
		"kumo":  # große eckige Leuchten um die Ecke, innen rundes Rückfahrlicht, Chromleiste über den Kofferraum
			var y0 := r_mid - 0.02
			var y1 := r_belt - 0.005
			var ym := (y0 + y1) / 2.0
			lamp.call(dark, y0 - 0.012, y1 + 0.012, rw - 0.5, 0.955, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.48, 0.958, 0.006)
			lamp.call(amber, y0, ym - 0.03, rw - 0.2, 0.958, 0.008)
			for s in [-1, 1]:
				_add(rbm, _disc(0.04, 0.012), rev_m, Vector3(s * (rw - 0.38), ym + 0.01, zr + 0.011)).rotation_degrees.x = 90
			_add(rbm, box(Vector3((rw - 0.5) * 2.0, 0.025, 0.014)), mat(Color(0.75, 0.75, 0.78), 0.9, 0.2), Vector3(0, y1 - 0.02, zr + 0.006))
		"shiden":  # schwarzes Band über das ganze Heck und um die Ecken, darin außen die roten Leuchten
			var y0 := r_mid + 0.005
			var y1 := r_belt + 0.01
			lamp.call(dark, y0 - 0.01, y1 + 0.01, 0.0, 0.95, 0.004)
			lamp.call(tail_m, y0 + 0.012, y1 - 0.012, rw - 0.34, 0.956, 0.007)
			lamp.call(amber, y0 + 0.012, y0 + 0.04, rw - 0.12, 0.956, 0.009)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.08, y1 - y0 - 0.03, 0.012)), rev_m, Vector3(s * (rw - 0.4), (y0 + y1) / 2.0, zr + 0.009))
		"ryujin":  # schmales rotes Leuchtenband über die ganze Breite, hoch unter der Heckkante
			var y1 := r_belt + 0.01
			var y0 := y1 - 0.08
			lamp.call(dark, y0 - 0.012, y1 + 0.012, 0.0, 0.955, 0.004)
			lamp.call(tail_m, y0, y1, 0.0, 0.96, 0.006)
			lamp.call(dark, (y0 + y1) / 2.0 - 0.003, (y0 + y1) / 2.0 + 0.003, 0.0, 0.96, 0.009)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.1, 0.035, 0.012)), rev_m, Vector3(s * 0.22, y0 - 0.04, zr + 0.006))
		"chibi":  # hohe Leuchten an den Ecken neben der Klappe: oben rot, unten Blinker, innen Rückfahrlicht
			var y0 := r_mid - 0.07
			var y1 := r_belt + 0.005
			var ym := y0 + (y1 - y0) * 0.4
			lamp.call(dark, y0 - 0.01, y1 + 0.01, rw - 0.19, 0.965, 0.004)
			lamp.call(tail_m, ym + 0.005, y1, rw - 0.17, 0.968, 0.006)
			lamp.call(amber, y0, ym - 0.005, rw - 0.09, 0.968, 0.006)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.06, ym - y0 - 0.012, 0.012)), rev_m, Vector3(s * (rw - 0.14), (y0 + ym) / 2.0, zr + 0.009))
		"hotaru":  # dunkles Band über das Heck, außen breite rote Leuchten, daneben runde Blinker
			var y0 := r_mid + 0.01
			var y1 := r_belt - 0.005
			lamp.call(dark, y0, y1, 0.0, 0.955, 0.004)
			lamp.call(tail_m, y0 + 0.012, y1 - 0.012, rw - 0.26, 0.958, 0.007)
			for s in [-1, 1]:
				_add(rbm, _disc((y1 - y0) / 2.0 - 0.016, 0.012), amber, Vector3(s * (rw - 0.33), (y0 + y1) / 2.0, zr + 0.009)).rotation_degrees.x = 90
				_add(rbm, box(Vector3(0.06, y1 - y0 - 0.03, 0.012)), rev_m, Vector3(s * 0.2, (y0 + y1) / 2.0, zr + 0.009))
		"tanuki":  # Leuchten an den Ecken, dazwischen eine schwarze Leiste mit schmalem Lichtstreifen, Nebelschlussleuchte
			var y0 := r_belt - 0.1
			var y1 := r_belt - 0.01
			lamp.call(dark, y0 - 0.01, y1 + 0.01, 0.0, 0.958, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.3, 0.962, 0.006)
			_add(rbm, box(Vector3((rw - 0.32) * 2.0, 0.012, 0.012)), tail_m, Vector3(0, (y0 + y1) / 2.0, zr + 0.008))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.06, y1 - y0 - 0.025, 0.012)), rev_m, Vector3(s * (rw - 0.26), (y0 + y1) / 2.0, zr + 0.009))
			_add(rbm, box(Vector3(0.1, 0.03, 0.012)), tail_m, Vector3(0, CLEARANCE + 0.17, zr + 0.006))
		"kaido":  # je Seite zwei runde Leuchten in Chromringen, innen mit hellem Rückfahrlicht in der Mitte
			var chrome_k := mat(Color(0.78, 0.78, 0.8), 0.95, 0.15)
			var ym := (r_mid + r_belt) / 2.0 + 0.01
			for s in [-1, 1]:
				for k in 2:
					var x: float = s * (rw - 0.13 - k * 0.17)
					_add(rbm, _disc(0.07, 0.012), chrome_k, Vector3(x, ym, zr + 0.004)).rotation_degrees.x = 90
					_add(rbm, _disc(0.06, 0.012), tail_m, Vector3(x, ym, zr + 0.008)).rotation_degrees.x = 90
					if k == 1:
						_add(rbm, _disc(0.022, 0.012), rev_m, Vector3(x, ym, zr + 0.011)).rotation_degrees.x = 90
		"hakone":  # schwarzes Feld über das ganze Heck, darin je Seite rote Leuchten, außen Blinker, innen Rückfahrlicht
			var y0 := r_mid + 0.02
			var y1 := r_belt - 0.01
			var ym := (y0 + y1) / 2.0
			lamp.call(dark, y0 - 0.008, y1 + 0.008, 0.0, 0.962, 0.004)
			lamp.call(tail_m, y0 + 0.01, y1 - 0.01, rw - 0.3, 0.965, 0.007)
			lamp.call(amber, y0 + 0.01, y1 - 0.01, rw - 0.07, 0.966, 0.009)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.08, y1 - y0 - 0.02, 0.012)), rev_m, Vector3(s * (rw - 0.36), ym, zr + 0.009))
			_add(rbm, _disc(0.03, 0.012), mat(Color(0.78, 0.78, 0.8), 0.95, 0.15), Vector3(0, ym, zr + 0.009)).rotation_degrees.x = 90
		"kagura":  # dreieckige Leuchten an den Ecken (Spitze nach unten), dunkle Blende dazwischen
			var y1 := r_belt + 0.005
			lamp.call(dark, y1 - 0.06, y1 + 0.008, 0.0, 0.955, 0.004)
			for s in [-1, 1]:
				var tri := _add(rbm, tapered_box(Vector2(0.32, 0.012), Vector2(0.03, 0.012), 0.15, 0.0), tail_m, Vector3(s * (rw - 0.2), y1, zr + 0.008))
				tri.rotation_degrees.z = 180.0
				_add(rbm, box(Vector3(0.07, 0.02, 0.012)), rev_m, Vector3(s * (rw - 0.43), y1 - 0.03, zr + 0.009))
		"falke":  # schmales Leuchtenband über die ganze Breite, außen höher gezogen
			var y1 := r_belt + 0.005
			var y0 := y1 - 0.05
			lamp.call(dark, y0 - 0.01, y1 + 0.01, 0.0, 0.958, 0.004)
			lamp.call(tail_m, y0 + 0.012, y1 - 0.012, 0.0, 0.962, 0.006)
			lamp.call(tail_m, y0 - 0.04, y1 - 0.012, rw - 0.16, 0.962, 0.008)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.08, 0.018, 0.012)), rev_m, Vector3(s * (rw - 0.3), y0 - 0.025, zr + 0.008))
		"furia":  # schwarzes Gitter über das ganze Heck, darin je Seite ein Y aus drei Leuchtbalken
			var ym := (r_mid + r_belt) / 2.0 + 0.02
			lamp.call(dark, CLEARANCE + 0.13, r_belt + 0.01, 0.0, 0.955, 0.004)
			for k in 3:
				_add(rbm, box(Vector3(rw * 2.0 - 0.3, 0.006, 0.012)), mat(Color(0.12, 0.12, 0.13), 0.4, 0.5), Vector3(0, r_mid - 0.01 + k * (r_belt - r_mid) / 2.5, zr + 0.007))
			for s in [-1, 1]:
				var cx: float = s * (rw - 0.2)
				_add(rbm, box(Vector3(0.14, 0.016, 0.012)), tail_m, Vector3(cx - s * 0.03, ym, zr + 0.01))
				var a := _add(rbm, box(Vector3(0.12, 0.016, 0.012)), tail_m, Vector3(cx + s * 0.08, ym + 0.035, zr + 0.01))
				a.rotation_degrees.z = s * 35.0
				var b := _add(rbm, box(Vector3(0.12, 0.016, 0.012)), tail_m, Vector3(cx + s * 0.08, ym - 0.035, zr + 0.01))
				b.rotation_degrees.z = -s * 35.0
		_:
			_add(rbm, box(Vector3(rw * 2.0 - 0.3, 0.1, 0.01)), dark, Vector3(0, ty, zr + 0.003))
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.12, 0.2, 0.01)), tail_m, Vector3(s * (rw - 0.08), ty - 0.02, zr + 0.004))
	if car_id == "kaizen":
		_kaizen_extras(body, S, W, L, mats)
	_extras(body, fb, rbm, car_id, S, W, L, flare, hood, kit, dark, paint)

	# Spiegel, Türgriffe
	var ms: PackedVector2Array = _section(S, S["cowl"] + 0.035, W, L, flare)["p"]
	var mz: float = zf + (S["cowl"] + 0.035) * L
	var doors: Array = S["doors"]
	var hs: PackedVector2Array = _section(S, doors[1] - 0.035, W, L, flare)["p"]
	for s in [-1, 1]:
		_add(body, box(Vector3(0.1, 0.03, 0.04)), dark, Vector3(s * (ms[6].x + 0.04), ms[6].y + 0.04, mz))
		_add(body, box(Vector3(0.05, 0.075, 0.14)), paint, Vector3(s * (ms[6].x + 0.1), ms[6].y + 0.06, mz))
		_add(body, box(Vector3(0.012, 0.022, 0.1)), dark, Vector3(s * (hs[5].x * 0.4 + hs[6].x * 0.6 + 0.008), hs[6].y - 0.05, zf + (doors[1] - 0.035) * L))
	# Scheibenwischer: zwei dunkle Blätter unten auf der Frontscheibe, der Neigung der Scheibe folgend
	var t_w0: float = S["cowl"] + 0.006
	var t_w1: float = S["cowl"] + 0.03
	var y_w0 := _top_c(S, t_w0)
	var y_w1 := _top_c(S, t_w1)
	var w_slope := atan2(y_w1 - y_w0, (t_w1 - t_w0) * L)
	var t_wb := t_w0 + 0.008
	var wiper_m := mat(Color(0.09, 0.09, 0.1), 0.4, 0.45)  # etwas heller als das Glas, damit man sie sieht
	var sec_w: PackedVector2Array = _section(S, t_wb, W, L, flare)["p"]
	var half_w: float = sec_w[7].x
	var blade := half_w * 0.62
	for k in 2:
		var wx := (-0.47 + k * 0.92) * half_w * 0.95
		var xl := wx - blade / 2.0
		var xr := wx + blade / 2.0
		var yl := _top_y(sec_w, clampf(absf(xl) / half_w, 0.0, 1.0))
		var yr := _top_y(sec_w, clampf(absf(xr) / half_w, 0.0, 1.0))
		var ym := maxf((yl + yr) / 2.0, _top_y(sec_w, clampf(absf(wx) / half_w, 0.0, 1.0)))
		var wp := _near(_add(body, box(Vector3(blade, 0.012, 0.016)), wiper_m, Vector3(wx, ym + 0.012, zf + t_wb * L)))
		wp.rotation = Vector3(-w_slope, 0.0, atan2(yr - yl, blade))
	if car_id == "vortex":
		# Luftauslässe auf der Haube
		var vs: PackedVector2Array = _section(S, 0.27, W, L, flare)["p"]
		for s in [-1, 1]:
			_add(body, box(Vector3(0.22, 0.01, 0.16)), dark, Vector3(s * 0.32, _top_y(vs, 0.32 / vs[7].x) + 0.003, zf + 0.27 * L))
	elif car_id == "raijin" and hood != 1 and hood != 4 and hood != 6:
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
				_add(body, box(Vector3(0.22, 0.2, 0.012)), flap, Vector3(s * (W / 2.0 - 0.18), CLEARANCE + 0.04, zi * (L / 2.0 - axle(S)) + wheel_r(S) + 0.1))

	if hood != 0:
		_hood(body, S, W, L, flare, hood, dark, mats["carbon"] if hood == 6 else paint)
	elif int(cfg.get("engine", 0)) >= 3 and car_id not in ["vortex", "raijin", "falke", "furia"]:
		var lt: float = (S["ge"] + 1.0) / 2.0 - 0.03 if engine_rear(S) else 0.24  # Mittel-/Heckmotor: Lamellen hinten
		var hv: PackedVector2Array = _section(S, lt, W, L, flare)["p"]
		for sx in [-1, 1]:
			for k in 4:
				_add(body, box(Vector3(0.2, 0.008, 0.018)), dark, Vector3(sx * 0.3, _top_y(hv, 0.3 / hv[7].x) + 0.004, zf + lt * L - 0.06 + k * 0.04))

	# Mittelmotor: Lufteinlässe in den Flanken hinter den Türen
	if S.get("mid", false):
		var doors_m: Array = S["doors"]
		var tk: float = doors_m[-1] + 0.06
		var sy: float = S["belt"] - 0.07
		var sxk := _side_x(S, tk, sy, W, L, flare)
		for s in [-1, 1]:
			# Lufthutze: dunkle Öffnung, vorn schmal, nach hinten höher (der Flanke entlang leicht nach innen gedreht)
			var scoop := _add(body, tapered_box(Vector2(0.03, 0.26), Vector2(0.03, 0.2), 0.15, 0.03), dark,
				Vector3(s * (sxk - 0.008), sy - 0.1, zf + tk * L))
			scoop.rotation_degrees.y = -s * 5.0

	# Ryujin: Glasdach mit Mittelsteg (T-Bar)
	if car_id == "ryujin":
		var rt0: float = S["rf"] + 0.01
		var rt1: float = S["rr"] - 0.005
		var tm := (rt0 + rt1) / 2.0
		var rp: PackedVector2Array = _section(S, tm, W, L, flare)["p"]
		var px := 0.22
		var slope := 2.0 * (rp[7].y - rp[10].y) * px / (rp[7].x * rp[7].x)
		for s in [-1, 1]:
			# Glasdeckel liegen auf der gewölbten Dachfläche (quer geneigt), dazwischen bleibt der lackierte Steg
			var gp := _add(body, box(Vector3(0.3, 0.006, (rt1 - rt0) * L)), mats["glass"], Vector3(s * px, _top_y(rp, px / rp[7].x), zf + tm * L))
			gp.rotation.z = s * atan(slope)

	# Bodykit: Schweller, Frontlippe
	if kit == 1 or kit == 2:
		var sp3: PackedVector2Array = _section(S, 0.5, W, L, flare)["p"]
		var sw := sp3[3].x
		for s in [-1, 1]:
			var sk := _add(body, box(Vector3(0.07, 0.09, L - 2.0 * axle(S) - 0.85)), dark, Vector3(s * (sw + 0.01), CLEARANCE + 0.05, 0))
			sk.name = "SideSkirt"
		_add(fb, box(Vector3(fw * 2.0 - 0.1, 0.03, 0.18)), dark, Vector3(0, CLEARANCE + 0.02, zf + 0.06))

	# Spoiler
	var sp: int = int(cfg.get("spoiler", 0))
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
	elif sp == 0 and car_id == "hayate":
		# Serienflügel: hoch auf der Klappe, zwei Stützen
		for s in [-1, 1]:
			_add(body, box(Vector3(0.04, 0.13, 0.1)), paint, Vector3(s * (W / 2.0 - 0.36), deck_y + 0.06, wz + 0.04))
		_add(body, box(Vector3(W - 0.36, 0.035, 0.22)), paint, Vector3(0, deck_y + 0.14, wz + 0.06)).rotation_degrees.x = -6
	elif sp == 0 and (car_id == "kitsune" or car_id == "tenshi" or car_id == "kumo" or car_id == "ryujin"):
		# Serien-Bürzel: flache Abrisskante an der Heckkante
		var bt := 1.0 - 0.07 / L
		var bp: PackedVector2Array = _section(S, bt, W, L, flare)["p"]
		_add(body, box(Vector3(bp[7].x * 2.0 - 0.06, 0.035, 0.12)), paint, Vector3(0, bp[10].y + 0.018, zf + bt * L - 0.02)).rotation_degrees.x = -10
	elif sp == 0 and car_id == "tanuki":
		# Serien-Dachspoiler über der Heckscheibe, seitlich kleine Finnen
		var rt: float = S["rr"]
		var ry := _top_c(S, rt)
		_add(body, box(Vector3(W - 0.6, 0.03, 0.2)), paint, Vector3(0, ry - 0.012, zf + rt * L + 0.1)).rotation_degrees.x = -6
		for s in [-1, 1]:
			_add(body, box(Vector3(0.025, 0.05, 0.18)), paint, Vector3(s * (W / 2.0 - 0.32), ry - 0.035, zf + rt * L + 0.1))
	elif sp == 0 and car_id == "kagura":
		# schmale Abrisskante aus Kohlefaser hinten auf dem Deckel
		_add(body, box(Vector3(W - 0.5, 0.025, 0.14)), carbon_mat(), Vector3(0, deck_y + 0.03, wz + 0.12)).rotation_degrees.x = -8
	elif sp == 0 and car_id == "falke":
		# Entenbürzel: der Motordeckel biegt hinten nach oben
		_add(body, tapered_box(Vector2(W - 0.42, 0.34), Vector2(W - 0.48, 0.1), 0.07, 0.1), paint, Vector3(0, deck_y - 0.02, wz + 0.04))
	elif sp == 0 and car_id == "furia":
		# flaches Flügelblatt über dem Heck, zwei kurze Stützen
		for s in [-1, 1]:
			_add(body, box(Vector3(0.04, 0.08, 0.12)), dark, Vector3(s * (W / 2.0 - 0.45), deck_y + 0.03, wz + 0.08))
		_add(body, box(Vector3(W - 0.44, 0.03, 0.24)), carbon_mat(), Vector3(0, deck_y + 0.08, wz + 0.1)).rotation_degrees.x = -5
	elif sp == 0 and car_id == "shiden":
		# Serienflügel aus einem Stück mit den Flanken: zwei Finnen an den Heckecken, Blatt über die ganze Breite
		var fy: float = deck_y
		for s in [-1, 1]:
			_add(body, tapered_box(Vector2(0.06, 0.4), Vector2(0.05, 0.26), 0.11, 0.06), paint, Vector3(s * (W / 2.0 - 0.13), fy - 0.02, wz + 0.02))
		_add(body, box(Vector3(W - 0.18, 0.035, 0.24)), paint, Vector3(0, fy + 0.1, wz + 0.08)).rotation_degrees.x = -4
	elif sp == 1:
		_add(body, box(Vector3(W - 0.4, 0.045, 0.16)), paint, Vector3(0, deck_y + 0.02, zr - 0.12))
	elif sp == 2 or sp == 3:
		var hgt := 0.22 if sp == 2 else 0.4
		var ww := W - 0.12 if sp == 2 else W + 0.04
		for s in [-1, 1]:
			_add(body, box(Vector3(0.05, hgt, 0.1)), dark, Vector3(s * (W / 2 - 0.38), deck_y + hgt / 2, wz))
			_add(body, box(Vector3(0.04, 0.18, 0.42)), paint, Vector3(s * ww / 2, deck_y + hgt + 0.02, wz))
		_add(body, box(Vector3(ww, 0.045, 0.4)), paint, Vector3(0, deck_y + hgt, wz))
		if sp == 3:
			_add(body, box(Vector3(ww, 0.04, 0.2)), dark, Vector3(0, deck_y + hgt + 0.1, wz + 0.1))
	elif sp >= 4:
		_spoiler(body, S, W, L, flare, sp, deck_y, wz, dark, paint, car_id)

	# Unterbodenneon: weicher Lichtteppich auf der Straße (Decal, liegt auf dem Asphalt statt darüber, daher keine
	# Spiegelung als Block) plus zwei schwache Lichter für Bordsteine und Nachbarautos
	var neon: Dictionary = Catalog.part_of(cfg, "neon")
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
	var pipe_m: Material = chrome
	var pipes: Array = S.get("pipes", [-0.38, 0.38])  # RX-7: ein Endrohr in der Mitte
	var oval := 1.0
	match int(cfg.get("exhaust", 0)):
		1:  # Sport: größere Rohre
			pr = S.get("pipe_r", 0.05) * 1.4
		2:  # Doppelrohr: je Seite zwei Rohre nebeneinander
			pr = S.get("pipe_r", 0.05) * 0.95
			var dbl := []
			for x in pipes:
				if absf(x) < 0.01:
					dbl.append_array([-pr * 1.15, pr * 1.15])
				else:
					dbl.append_array([x - signf(x) * pr * 1.15, x + signf(x) * pr * 1.15])
			pipes = dbl
		3:  # Ovalrohr: breit und flach
			pr = S.get("pipe_r", 0.05) * 1.5
			oval = 0.6
		4:  # Titan: blau-violett angelaufen
			pr = S.get("pipe_r", 0.05) * 1.35
			pipe_m = mat(Color(0.42, 0.38, 0.62), 0.95, 0.18)
		5:  # Rennauspuff: ein großes Rohr in der Mitte
			pr = 0.085
			pipes = [0.0]
	for x in pipes:
		var pipe := CylinderMesh.new()
		pipe.top_radius = pr - 0.005
		pipe.bottom_radius = pr
		pipe.height = 0.16
		var p := _add(body, pipe, pipe_m, Vector3(x, CLEARANCE + 0.08, zr + 0.03))
		p.rotation_degrees.x = 90
		p.scale = Vector3(1, 1, oval)
		var inner := _add(body, _disc(pr * 0.72, 0.01), dark, Vector3(x, CLEARANCE + 0.08, zr + 0.112))
		inner.rotation_degrees.x = 90
		inner.scale = Vector3(1, 1, oval)
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
	var rc: Dictionary = Catalog.part_of(cfg, "rimcol")
	var rim_m: Material = mat(rim["color"], 0.65, 0.28)
	if rc.get("paint", false):
		rim_m = paint
	elif rc.has("color"):
		rim_m = mat(rc["color"], 0.85 if rc.get("chrome", false) else 0.65, 0.14 if rc.get("chrome", false) else 0.28)
	var rotor_m := mat(Color(0.42, 0.42, 0.44), 0.8, 0.35)
	var hat_m := mat(Color(0.2, 0.2, 0.22), 0.7, 0.45)
	var caliper_m := mat(Color(0.85, 0.06, 0.04), 0.3, 0.35) if perf > 0 else mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
	var fronts := []
	var spinners := []
	var track := W / 2 - 0.15 + (0.05 if flare > 0.0 else 0.0) + (0.03 if S.get("overfenders", false) else 0.0)  # bündig unter dem Kotflügel
	var wr := wheel_r(S)
	var tw: float = S.get("tire_w", 0.24) * WHEEL_R / wr  # Breite in Metern (das Rad wird danach skaliert)
	var o := tw / 2.0
	for zi in [-1, 1]:
		for s in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * track, wr, zi * (L / 2 - axle(S)))
			pivot.scale = Vector3.ONE * (wr / WHEEL_R)  # kleinere/größere Räder: das ganze Rad samt Felge und Bremse skaliert
			root.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			_near(_add(spin, _tire_mesh(tw), tire_m, Vector3.ZERO))
			var far_tire := CylinderMesh.new()
			far_tire.top_radius = WHEEL_R
			far_tire.bottom_radius = WHEEL_R
			far_tire.height = tw
			far_tire.radial_segments = 16
			far_tire.rings = 1
			_far(_add(spin, far_tire, tire_m, Vector3.ZERO)).rotation_degrees.z = 90
			# Schichten mit klarem Abstand (Reifen bis o, Bremsscheibe o + 0.004, Sattel o + 0.01, Speichen bis o + 0.025)
			var closed: bool = rim.get("style", "std") in ["steel", "aero"]
			if not closed:
				var rr: float = rim["radius"]
				_add(spin, _disc(rr * 0.8, 0.008), rotor_m, Vector3(s * (o + 0.004), 0, 0)).rotation_degrees.z = 90
				# Bremsscheibe: dunkler Topf in der Mitte, gelochter Reibring (zwei versetzte Lochkreise)
				_add(spin, _disc(rr * 0.42, 0.01), hat_m, Vector3(s * (o + 0.006), 0, 0)).rotation_degrees.z = 90
				for k in 16:
					var ha := TAU * k / 16.0
					var hr := rr * (0.56 if k % 2 == 0 else 0.68)
					_near(_add(spin, _disc(0.0075, 0.004), dark, Vector3(s * (o + 0.0085), cos(ha) * hr, sin(ha) * hr))).rotation_degrees.z = 90
				_add(spin, _disc(rr * 0.26, 0.012), mat(Color(0.12, 0.12, 0.12), 0.6, 0.4), Vector3(s * (o + 0.02), 0, 0)).rotation_degrees.z = 90
				# Bremssattel steht still (am Achsschenkel), oben hinten an der Scheibe: kräftiger Block, der über den
				# Reibring greift, außen eine schmalere Deckplatte
				var cal := _add(pivot, box(Vector3(0.03, rr * 0.48, 0.1)), caliper_m,
					Vector3(s * (o - 0.004), rr * 0.5, rr * 0.4))
				cal.rotation_degrees.x = -40.0
				var cap := _add(pivot, box(Vector3(0.006, rr * 0.36, 0.072)), caliper_m,
					Vector3(s * (o + 0.013), rr * 0.5, rr * 0.4))
				cap.rotation_degrees.x = -40.0
			_rim(spin, rim, rim_m, dark, chrome, s, o)
			spinners.append(spin)
			if zi == -1:
				fronts.append(pivot)

	body.position.y -= Catalog.part_of(cfg, "suspension")["drop"] + S.get("drop", 0.0)
	if not OS.get_cmdline_user_args().has("--nobatch"):
		_merge_parts(root, body, fronts, spinners, flames)
		if lod:
			_build_lod(root, flames, GameState.car_lod_distance())
	# Ersatzteile der Fernansicht stecken jetzt im LOD-Mesh (oder werden ohne LOD nicht gebraucht)
	var far := [root]
	while not far.is_empty():
		var nd: Node = far.pop_back()
		far.append_array(nd.get_children())
		if nd.has_meta("lod_only"):
			nd.get_parent().remove_child(nd)
			nd.free()
	_set_layer(root)
	root.set_meta("body", body)
	root.set_meta("front_pivots", fronts)
	root.set_meta("spinners", spinners)
	root.set_meta("flames", flames)
	root.set_meta("length", L)
	root.set_meta("width", W)
	root.set_meta("wheel_r", wr)
	root.set_meta("axle", axle(S))
	root.set_meta("eye", Vector3(0, S["roof"] - 0.1, zf + (S["cowl"] + 0.07) * L))
	return root


## Kennzeichen je Auto (Kürzel für "Need for Geschwindigkeit", dahinter eine Nummer mit Bezug zum Vorbild)
static func plate_text(car_id: String) -> String:
	var nums := {"kaizen": "92", "hachi": "86", "sakura": "15", "hayate": "88", "kitsune": "18", "tsubame": "99",
		"mirai": "240", "tenshi": "91", "kumo": "100", "raijin": "4", "vortex": "34", "ronin": "33", "shiden": "1",
		"ryujin": "300", "kaze": "7", "chibi": "660", "hotaru": "64", "tanuki": "20", "kaido": "73", "hakone": "24",
		"kagura": "10", "falke": "911", "furia": "12"}
	return "NF-G " + str(nums.get(car_id, str(absi(hash(car_id)) % 900 + 100)))


## Lackfarbe: "Werkslack" (Stufe 0) ist je Auto eigen (Kaizen in Championship-Weiß), sonst die gewählte Farbe
static func paint_color(car_id: String, cfg: Dictionary) -> Color:
	var opt: Dictionary = Catalog.PARTS["paint"]["options"][cfg.get("paint", 0)]
	if int(cfg.get("paint", 0)) == 0:
		return Catalog.CARS[car_id].get("paint", opt["color"])
	return opt["color"]


## Lack mit Oberfläche: glänzend mit Klarlack (Standard), stark metallisch, Perlmutt (heller Schimmer an den Kanten),
## matt (ohne Klarlack) oder Chrom
static func paint_mat(car_id: String, cfg: Dictionary) -> StandardMaterial3D:
	var c := paint_color(car_id, cfg)
	var m: StandardMaterial3D
	match str(Catalog.part_of(cfg, "paint").get("finish", "")):
		"matt":
			return mat(c, 0.1, 0.78)
		"chrome":
			# echtes Chrom spiegelt nachts fast nur Schwarz: etwas Eigenhelligkeit und helle Kanten, damit es glänzt
			m = mat(c, 0.75, 0.1)
			m.rim_enabled = true
			m.rim = 1.0
			m.rim_tint = 0.6
		"metal":
			m = mat(c, 0.85, 0.2)
		"pearl":
			m = mat(c, 0.25, 0.15)
			m.rim_enabled = true
			m.rim = 0.7
			m.rim_tint = 0.15
		_:
			m = mat(c, 0.55, 0.22)
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	return m


## Breitbau: Kotflügel weiter ausgestellt (Querschnitte), Räder weiter außen
static func kit_flare(cfg: Dictionary) -> float:
	return 0.06 if Catalog.part_of(cfg, "bodykit").get("flare", false) else 0.0


## Kohlefaser: Köperbindung als kleine Kachel, dreiplanar aufgetragen (die Karosserie hat keine UV-Koordinaten)
static var _carbon: StandardMaterial3D


static func carbon_mat() -> StandardMaterial3D:
	if _carbon == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
		for y in 8:
			for x in 8:
				var vertical := ((x / 2) + (y / 2)) % 2 == 0
				var u := float(x % 2) if vertical else float(y % 2)
				var v := 0.045 + 0.06 * (1.0 - u)
				img.set_pixel(x, y, Color(v, v, v * 1.08))
		img.generate_mipmaps()
		_carbon = mat(Color.WHITE, 0.35, 0.28)
		_carbon.albedo_texture = ImageTexture.create_from_image(img)
		_carbon.uv1_triplanar = true
		_carbon.uv1_scale = Vector3(16, 16, 16)
		_carbon.clearcoat_enabled = true
		_carbon.clearcoat = 1.0
	return _carbon


## Speiche von Radius r0 bis r1, Mitte bei Winkel a, Richtung a + tilt (tilt != 0: Speichen kreuzen oder laufen
## parallel versetzt). Die Radachse ist x.
## Speiche: an der Nabe breiter und kräftiger, zum Horn hin schmaler (wie gegossen), Kanten leicht gefast
static func _spoke(spin: Node3D, m: Material, x: float, a: float, r0: float, r1: float, w: float, tilt := 0.0, th := 0.012) -> MeshInstance3D:
	var rm := (r0 + r1) / 2.0
	var ln := r1 - r0
	var key := "spoke_%.4f_%.4f_%.4f" % [ln, w, th]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = _spoke_mesh(ln, w, th)
	var dir := Vector3(0, cos(a + tilt), sin(a + tilt))
	var sk := _add(spin, _mesh_cache[key], m, Vector3(x, cos(a) * rm, sin(a) * rm) - dir * ln / 2.0)
	sk.rotation.x = a + tilt
	return sk


## Speiche entlang +Y von 0 bis ln: Querschnitt achteckig gefast (Breite w quer, Dicke th nach außen), innen
## 25 % breiter, außen 15 % schmaler; die Außenseite ist leicht gewölbt
static func _spoke_mesh(ln: float, w: float, th: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sec := func(y: float, k: float) -> Array:
		var hw := w * k / 2.0
		var ht := th / 2.0
		var c := minf(hw, ht) * 0.45
		return [Vector3(-ht, y, -hw + c), Vector3(-ht + c, y, -hw), Vector3(ht - c, y, -hw), Vector3(ht, y, -hw + c),
			Vector3(ht + th * 0.15, y, 0.0), Vector3(ht, y, hw - c), Vector3(ht - c, y, hw), Vector3(-ht + c, y, hw), Vector3(-ht, y, hw - c)]
	var lo: Array = sec.call(0.0, 1.25)
	var hi: Array = sec.call(ln, 0.85)
	var n := lo.size()
	for i in n:
		var j := (i + 1) % n
		var mid: Vector3 = (lo[i] + lo[j]) / 2.0
		var nf := Vector3(mid.x, 0.0, mid.z).normalized()
		_tri(st, lo[i], hi[i], hi[j], nf, nf, nf, nf)
		_tri(st, lo[i], hi[j], lo[j], nf, nf, nf, nf)
	for cap in [[lo, Vector3.DOWN], [hi, Vector3.UP]]:
		var ring: Array = cap[0]
		var c0: Vector3 = ring[0]
		for i in range(1, n - 1):
			_tri(st, c0, ring[i], ring[i + 1], cap[1], cap[1], cap[1], cap[1])
	return st.commit()


## Reifen als Drehkörper um die X-Achse (bis 2.15 ein Zylinder mit 14 Ecken): runde Schultern, leicht gewölbte
## Flanken, Lauffläche mit drei Längsrillen, 36 Segmente. Innen und außen geschlossen (hinter offenen Speichen dunkel).
static func _tire_mesh(tw: float) -> ArrayMesh:
	var key := "tire_%.3f" % tw
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var R := WHEEL_R
	var h := tw / 2.0
	var side := [Vector2(-h, 0.0), Vector2(-h, R - 0.085), Vector2(-h - 0.005, R - 0.06), Vector2(-h - 0.006, R - 0.04),
		Vector2(-h - 0.002, R - 0.02), Vector2(-h + 0.008, R - 0.007), Vector2(-h + 0.022, R)]
	var prof: Array = side.duplicate()
	var tread := h - 0.022
	for g in [-0.5, 0.0, 0.5]:
		var gc: float = g * tread
		prof.append_array([Vector2(gc - 0.008, R), Vector2(gc - 0.006, R - 0.006), Vector2(gc + 0.006, R - 0.006), Vector2(gc + 0.008, R)])
	for i in range(side.size() - 1, -1, -1):
		prof.append(Vector2(-side[i].x, side[i].y))
	# Normale je Profilabschnitt (nach außen), an weichen Knicken gemittelt
	var segn := []
	for i in prof.size() - 1:
		var d: Vector2 = prof[i + 1] - prof[i]
		segn.append(Vector2(-d.y, d.x).normalized())
	var seg := 36
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		if p0.distance_to(p1) < 1e-5:
			continue
		var n0: Vector2 = segn[i]
		var n1: Vector2 = segn[i]
		if i > 0 and segn[i - 1].dot(segn[i]) > 0.6:
			n0 = (segn[i - 1] + segn[i]).normalized()
		if i < segn.size() - 1 and segn[i + 1].dot(segn[i]) > 0.6:
			n1 = (segn[i + 1] + segn[i]).normalized()
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			var P := func(p: Vector2, a: float) -> Vector3: return Vector3(p.x, p.y * cos(a), p.y * sin(a))
			var N := func(nn: Vector2, a: float) -> Vector3: return Vector3(nn.x, nn.y * cos(a), nn.y * sin(a))
			var am := (a0 + a1) / 2.0
			var nf: Vector3 = N.call(segn[i], am)
			var v00: Vector3 = P.call(p0, a0)
			var v01: Vector3 = P.call(p0, a1)
			var v10: Vector3 = P.call(p1, a0)
			var v11: Vector3 = P.call(p1, a1)
			if p0.y > 1e-5:
				_tri(st, v00, v10, v11, N.call(n0, a0), N.call(n1, a0), N.call(n1, a1), nf)
			if p1.y > 1e-5:
				_tri(st, v00, v11, v01, N.call(n0, a0), N.call(n1, a1), N.call(n0, a1), nf)
	var m := st.commit()
	_mesh_cache[key] = m
	return m


## Flügelprofil entlang X (Spannweite), Sehne entlang Z (vorn = -Z): oben fast flach, unten gewölbt wie ein
## umgedrehter Tragflügel, runde Nase, spitze Hinterkante. Ersetzt die flachen Kästen der Heckflügel.
static func _airfoil(span: float, chord: float, thick: float) -> ArrayMesh:
	var key := "wing_%.3f_%.3f_%.3f" % [span, chord, thick]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var pts := []  # (z, y), Nase -> oben -> Hinterkante -> unten -> Nase
	var n := 8
	for i in n + 1:
		var t := float(i) / n
		var x := (1.0 - cos(t * PI)) / 2.0  # dichter an der Nase
		pts.append(Vector2(-chord / 2.0 + x * chord, thick * 0.32 * sqrt(maxf(x, 0.0)) * (1.0 - x) * 2.4))
	for i in range(n - 1, 0, -1):
		var t := float(i) / n
		var x := (1.0 - cos(t * PI)) / 2.0
		pts.append(Vector2(-chord / 2.0 + x * chord, -thick * 1.05 * sqrt(maxf(x, 0.0)) * (1.0 - x) * 2.2))
	var c := pts.size()
	var segn := []
	for i in c:
		var d: Vector2 = pts[(i + 1) % c] - pts[i]
		segn.append(Vector2(-d.y, d.x).normalized())  # nach außen (Umlauf im Uhrzeigersinn in z/y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := span / 2.0
	for i in c:
		var j := (i + 1) % c
		var ni: Vector2 = segn[i]
		var n_a: Vector2 = (segn[(i - 1 + c) % c] + ni).normalized() if segn[(i - 1 + c) % c].dot(ni) > 0.5 else ni
		var n_b: Vector2 = (segn[j] + ni).normalized() if segn[j].dot(ni) > 0.5 else ni
		var a0 := Vector3(-hs, pts[i].y, pts[i].x)
		var a1 := Vector3(hs, pts[i].y, pts[i].x)
		var b0 := Vector3(-hs, pts[j].y, pts[j].x)
		var b1 := Vector3(hs, pts[j].y, pts[j].x)
		var na := Vector3(0, n_a.y, n_a.x)
		var nb := Vector3(0, n_b.y, n_b.x)
		var nf := Vector3(0, ni.y, ni.x)
		_tri(st, a0, b0, b1, na, nb, nb, nf)
		_tri(st, a0, b1, a1, na, nb, na, nf)
	for e in [-1.0, 1.0]:
		var nx := Vector3(e, 0, 0)
		for i in range(1, c - 1):
			_tri(st, Vector3(e * hs, pts[0].y, pts[0].x), Vector3(e * hs, pts[i].y, pts[i].x), Vector3(e * hs, pts[i + 1].y, pts[i + 1].x), nx, nx, nx, nx)
	# Abrisskante (Gurney-Flap) hinten oben: gibt dem Flügel auch von hinten Masse
	_box_into(st, Vector3(0, thick * 0.55, chord / 2.0 - 0.004), Vector3(span, thick * 1.1, 0.008))
	var m := st.commit()
	_mesh_cache[key] = m
	return m


## Quader (Mitte, Größe) mit flachen Normalen in eine SurfaceTool
static func _box_into(st: SurfaceTool, c: Vector3, sz: Vector3) -> void:
	var h := sz / 2.0
	for ax in 3:
		for sg in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			var v := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			v[(ax + 2) % 3] = h[(ax + 2) % 3]
			var f := c + n * h[ax]
			_tri(st, f - u - v, f + u - v, f + u + v, n, n, n, n)
			_tri(st, f - u - v, f + u + v, f - u + v, n, n, n, n)


## Kennzeichen-Schrift (einmal je Text gebaut): dunkle Buchstaben, flach, Vorderseite nach +Z
static func _plate_text(text: String) -> Mesh:
	var key := "plate_" + text
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var tm := TextMesh.new()
	tm.text = text
	tm.font = load("res://assets/fonts/D-DINCondensed-Bold.otf")
	tm.font_size = 64
	tm.pixel_size = 0.00125
	tm.depth = 0.0
	tm.curve_step = 1.5
	_mesh_cache[key] = tm
	return tm


## Felge je Bauart (Catalog rims.style) auf der Außenseite des Rads, s = Seite, o = halbe Reifenbreite.
static func _rim(spin: Node3D, rim: Dictionary, rim_m: Material, dark: Material, chrome: Material, s: float, o: float) -> void:
	var rr: float = rim["radius"]
	var n: int = rim["spokes"]
	var x := s * (o + 0.019)
	var style: String = rim.get("style", "std")
	var lip_in := 0.86
	var face := func(r: float, m: Material, dx: float, h := 0.012) -> MeshInstance3D:
		var d := _add(spin, _disc(r, h), m, Vector3(s * (o + dx), 0, 0))
		d.rotation_degrees.z = 90
		return d
	match style:
		"std":
			for k in n:
				_spoke(spin, rim_m, x, TAU * k / n, rr * 0.025, rr * 0.975, 0.05)
		"thin":
			for k in n:
				_spoke(spin, rim_m, x, TAU * k / n, rr * 0.2, rr * 0.95, 0.022)
			face.call(rr * 0.3, rim_m, 0.02)
		"mesh", "cross":
			# Gitter: zwei Lagen schräger Speichen, die sich kreuzen; Kreuzspeichen mit Zwischenring
			var tilt := 0.38 if style == "mesh" else 0.55
			for k in n:
				var a := TAU * k / n
				_spoke(spin, rim_m, x, a, rr * 0.28, rr * 0.93, 0.022, tilt)
				_spoke(spin, rim_m, x - s * 0.003, a, rr * 0.28, rr * 0.93, 0.022, -tilt)
			face.call(rr * 0.32, rim_m, 0.02)
			if style == "cross":
				var ring := TorusMesh.new()
				ring.inner_radius = rr * 0.5
				ring.outer_radius = rr * 0.58
				ring.rings = 40
				ring.ring_segments = 6
				var rm := _add(spin, ring, rim_m, Vector3(x, 0, 0))
				rm.rotation_degrees.z = 90
				rm.scale = Vector3(1, 0.3, 1)
		"split":
			# Doppelspeichen: je zwei schmale Speichen parallel nebeneinander
			for k in n:
				var a := TAU * k / n
				for e in [-1.0, 1.0]:
					_spoke(spin, rim_m, x, a + e * 0.12, rr * 0.25, rr * 0.95, 0.026, -e * 0.12)
			face.call(rr * 0.3, rim_m, 0.02)
		"y":
			# Y-Speichen: innen eine kräftige Speiche, außen zwei auseinanderlaufende Äste
			for k in n:
				var a := TAU * k / n
				_spoke(spin, rim_m, x, a, rr * 0.12, rr * 0.55, 0.055)
				for e in [-1.0, 1.0]:
					_spoke(spin, rim_m, x, a + e * 0.16, rr * 0.5, rr * 0.95, 0.03, e * 0.28)
		"turbine":
			# Turbine: verdrehte Schaufeln wie ein Lüfterrad
			for k in n:
				var a := TAU * k / n
				var bl := _add(spin, box(Vector3(0.01, rr * 0.66, 0.06)), rim_m, Vector3(x - s * 0.008, cos(a) * rr * 0.6, sin(a) * rr * 0.6))
				bl.basis = Basis(Vector3.RIGHT, a) * Basis(Vector3.UP, 0.35)
			face.call(rr * 0.3, rim_m, 0.02)
			face.call(rr * 0.24, dark, 0.008, 0.01)
		"te":
			# Rennsport-Sechs: breite, flache Speichen bis an das Horn, schmales Horn
			for k in n:
				_spoke(spin, rim_m, x, TAU * k / n, rr * 0.18, rr * 0.92, 0.075)
			face.call(rr * 0.28, rim_m, 0.02)
			lip_in = 0.9
		"dish":
			# Tiefbett: kurze Speichen innen, breites poliertes Horn außen (tief zurückgesetzter Stern)
			for k in n:
				_spoke(spin, rim_m, x - s * 0.006, TAU * k / n, rr * 0.08, rr * 0.62, 0.05)
			var bed := TorusMesh.new()
			bed.inner_radius = rr * 0.6
			bed.outer_radius = rr
			bed.rings = 40
			bed.ring_segments = 6
			var bm := _add(spin, bed, chrome, Vector3(s * (o + 0.017), 0, 0))
			bm.rotation_degrees.z = 90
			bm.scale = Vector3(1, 0.12, 1)
			lip_in = 0.94
		"steel":
			# Stahlfelge: geschlossene Scheibe mit Löchern, Chromkappe
			face.call(rr, rim_m, 0.006, 0.02)
			for k in n:
				var a := TAU * k / n + 0.3
				var hole := _add(spin, _disc(rr * 0.13, 0.008), dark, Vector3(s * (o + 0.0165), cos(a) * rr * 0.62, sin(a) * rr * 0.62))
				hole.rotation_degrees.z = 90
			face.call(rr * 0.24, chrome, 0.02)
		"aero":
			# Aero-Scheibe: geschlossen und glatt, kleine Kühlschlitze am Rand
			face.call(rr, rim_m, 0.008, 0.02)
			for k in n * 2:
				var a := TAU * k / (n * 2)
				var sl := _add(spin, box(Vector3(0.006, 0.06, 0.022)), dark, Vector3(s * (o + 0.0185), cos(a) * rr * 0.76, sin(a) * rr * 0.76))
				sl.rotation.x = a + PI / 2.0
			face.call(rr * 0.3, rim_m, 0.016, 0.014)
	# Radmuttern und Nabendeckel
	if style != "aero":
		for k in 5:
			var a := TAU * k / 5.0
			var nut := _add(spin, _disc(0.014, 0.012), chrome, Vector3(s * (o + 0.027), cos(a) * rr * 0.15, sin(a) * rr * 0.15))
			nut.rotation_degrees.z = 90
		face.call(rr * 0.07, dark, 0.028, 0.008)
	if style != "steel":
		var lip := TorusMesh.new()
		lip.inner_radius = rr * lip_in
		lip.outer_radius = rr
		lip.rings = 40
		lip.ring_segments = 8
		var lm := _add(spin, lip, chrome if style == "dish" else rim_m, Vector3(s * (o + 0.016), 0, 0))
		lm.rotation_degrees.z = 90
		lm.scale = Vector3(1, 0.35, 1)


## Bodykits 3–6: Street (lackierte Lippe, Schweller, Heckschürze), Rallye (Schmutzfänger, Unterfahrschutz,
## Zusatzscheinwerfer), Racing und Breitbau Racing (Kohlefaser-Splitter, Canards, Schweller, großer Diffusor)
static func _bodykit(body: Node3D, fb: Node3D, S: Dictionary, W: float, L: float, flare: float, kit: int, fw: float,
		dark: Material, paint: Material, mats: Dictionary) -> void:
	var zf := -L / 2.0
	var zr := L / 2.0
	var sw: float = _section(S, 0.5, W, L, flare)["p"][3].x
	var rw: float = _section(S, 1.0, W, L, flare)["p"][6].x
	var skirt_l := L - 2.0 * axle(S) - 0.85
	match kit:
		3:
			_add(fb, box(Vector3(fw * 2.0 - 0.06, 0.04, 0.2)), paint, Vector3(0, CLEARANCE + 0.025, zf + 0.07))
			_add(fb, box(Vector3(fw * 2.0 - 0.1, 0.012, 0.21)), dark, Vector3(0, CLEARANCE + 0.0, zf + 0.07))
			for s in [-1, 1]:
				_add(body, box(Vector3(0.08, 0.1, skirt_l)), paint, Vector3(s * (sw + 0.015), CLEARANCE + 0.05, 0)).name = "SideSkirt"
				_add(body, box(Vector3(0.012, 0.02, skirt_l)), dark, Vector3(s * (sw + 0.05), CLEARANCE + 0.0, 0))
			_add(body, box(Vector3(rw * 2.0 - 0.2, 0.06, 0.18)), paint, Vector3(0, CLEARANCE + 0.07, zr - 0.11))
		4:
			var flap := mat(Color(0.75, 0.04, 0.04), 0.0, 0.8)
			for zi in [-1, 1]:
				for s in [-1, 1]:
					_add(body, box(Vector3(0.24, 0.22, 0.012)), flap, Vector3(s * (W / 2.0 - 0.18), CLEARANCE + 0.03, zi * (L / 2.0 - axle(S)) + wheel_r(S) + 0.1))
			_add(body, box(Vector3(fw * 1.3, 0.02, 0.4)), mat(Color(0.6, 0.6, 0.62), 0.9, 0.35), Vector3(0, CLEARANCE - 0.03, zf + 0.22))
			var aux := mat(Color(1.0, 0.92, 0.7), 0.0, 0.3, Color(1.0, 0.85, 0.5), 2.2)
			for s in [-1, 1]:
				var ring := _add(fb, _disc(0.075, 0.04), dark, Vector3(s * 0.3, CLEARANCE + 0.22, zf - 0.03))
				ring.rotation_degrees.x = 90
				var lens := _add(fb, _disc(0.06, 0.01), aux, Vector3(s * 0.3, CLEARANCE + 0.22, zf - 0.052))
				lens.rotation_degrees.x = 90
			_add(fb, box(Vector3(0.66, 0.02, 0.03)), dark, Vector3(0, CLEARANCE + 0.15, zf - 0.025))
		5, 6:
			var cf: Material = mats["carbon"]
			_add(fb, box(Vector3(fw * 2.0 + 0.04, 0.04, 0.3)), cf, Vector3(0, CLEARANCE + 0.02, zf + 0.1))
			for s in [-1, 1]:
				var cx := _side_x(S, 0.03, CLEARANCE + 0.2, W, L, flare)
				for k in 2:
					var cn := _add(fb, box(Vector3(0.13, 0.01, 0.1)), cf, Vector3(s * (cx + 0.02), CLEARANCE + 0.14 + k * 0.09, zf + 0.08))
					cn.rotation.z = s * 0.28
				_add(body, box(Vector3(0.07, 0.07, skirt_l)), cf, Vector3(s * (sw + 0.02), CLEARANCE + 0.02, 0)).name = "SideSkirt"
			for k in 7:
				_add(body, box(Vector3(0.012, 0.15, 0.36)), cf, Vector3((k - 3) * rw * 0.15, CLEARANCE + 0.03, zr - 0.15))
			_add(body, box(Vector3(rw * 1.8, 0.012, 0.36)), cf, Vector3(0, CLEARANCE - 0.0, zr - 0.15))
			_add(fb, box(Vector3(0.05, 0.05, 0.1)), mat(Color(0.85, 0.05, 0.04), 0.4, 0.4), Vector3(fw * 0.6, CLEARANCE + 0.08, zf - 0.02))


## Spoiler 4–9: Entenbürzel, Street-Flügel, Schwanenhals, Doppeldecker, Dachspoiler, Bügelflügel
static func _spoiler(body: Node3D, S: Dictionary, W: float, L: float, flare: float, sp: int, deck_y: float, wz: float,
		dark: Material, paint: Material, car_id: String) -> void:
	var zf := -L / 2.0
	match sp:
		4:
			var bt := 1.0 - 0.09 / L
			var bp: PackedVector2Array = _section(S, bt, W, L, flare)["p"]
			var bw := bp[7].x * 2.0 - 0.04
			_add(body, tapered_box(Vector2(bw, 0.24), Vector2(bw - 0.05, 0.05), 0.1, 0.12), paint, Vector3(0, bp[10].y - 0.015, zf + bt * L - 0.08))
		5:
			for s in [-1, 1]:
				_add(body, box(Vector3(0.035, 0.1, 0.08)), dark, Vector3(s * (W / 2.0 - 0.42), deck_y + 0.05, wz + 0.03))
				_add(body, box(Vector3(0.02, 0.08, 0.3)), paint, Vector3(s * (W / 2.0 - 0.16), deck_y + 0.12, wz + 0.04))
			_add(body, _airfoil(W - 0.32, 0.27, 0.035), paint, Vector3(0, deck_y + 0.11, wz + 0.04)).rotation_degrees.x = -6
		6:
			var hgt := 0.32
			for s in [-1, 1]:
				_add(body, box(Vector3(0.04, hgt + 0.06, 0.06)), dark, Vector3(s * 0.32, deck_y + (hgt + 0.06) / 2.0, wz + 0.17))
				_add(body, box(Vector3(0.04, 0.04, 0.2)), dark, Vector3(s * 0.32, deck_y + hgt + 0.06, wz + 0.08))
				_add(body, box(Vector3(0.03, 0.2, 0.42)), paint, Vector3(s * (W / 2.0 - 0.05), deck_y + hgt - 0.02, wz + 0.02))
			_add(body, _airfoil(W - 0.1, 0.36, 0.04), paint, Vector3(0, deck_y + hgt, wz + 0.02)).rotation_degrees.x = -8
		7:
			for s in [-1, 1]:
				_add(body, box(Vector3(0.05, 0.24, 0.1)), dark, Vector3(s * (W / 2.0 - 0.4), deck_y + 0.12, wz))
				_add(body, box(Vector3(0.03, 0.26, 0.46)), paint, Vector3(s * (W / 2.0 - 0.04), deck_y + 0.3, wz + 0.02))
			_add(body, _airfoil(W - 0.08, 0.34, 0.04), paint, Vector3(0, deck_y + 0.24, wz)).rotation_degrees.x = -5
			_add(body, _airfoil(W - 0.08, 0.2, 0.03), paint, Vector3(0, deck_y + 0.38, wz + 0.1)).rotation_degrees.x = -14
		8:
			if car_id == "kaizen":
				return  # hat ab Werk einen Dachspoiler
			var t0: float = S["rr"]
			var y0 := _top_c(S, t0)
			var roof_w: float = (W / 2.0 - S["tumble"]) * 2.0
			var rs := _add(body, box(Vector3(roof_w * 0.86, 0.025, 0.22)), paint, Vector3(0, y0 + 0.012, (t0 - 0.5) * L + 0.09))
			rs.rotation.x = 0.1
			for s in [-1, 1]:
				_add(body, box(Vector3(0.02, 0.05, 0.22)), paint, Vector3(s * roof_w * 0.43, y0 - 0.005, (t0 - 0.5) * L + 0.09)).rotation.x = 0.1
		9:
			for s in [-1, 1]:
				_add(body, box(Vector3(0.07, 0.25, 0.16)), paint, Vector3(s * (W / 2.0 - 0.25), deck_y + 0.09, wz + 0.03)).rotation_degrees.x = 20
			_add(body, _airfoil(W - 0.4, 0.27, 0.04), paint, Vector3(0, deck_y + 0.21, wz + 0.08)).rotation_degrees.x = -5


## Motorhauben 1–6 (5 = Kohlefaser ist nur Haut, siehe _skin): Hutze, Lamellen, NACA-Einlass, Doppelhutze
static func _hood(body: Node3D, S: Dictionary, W: float, L: float, flare: float, hood: int, dark: Material, scoop_m: Material) -> void:
	var zf := -L / 2.0
	var th: float = S["cowl"] * 0.58
	var p: PackedVector2Array = _section(S, th, W, L, flare)["p"]
	var slope := (_top_c(S, th + 0.04) - _top_c(S, th - 0.04)) / (0.08 * L)
	var tilt := -atan(slope)
	var scoop := func(x: float, size: float) -> void:
		var y := _top_y(p, absf(x) / p[7].x) - 0.01
		var sc := _add(body, tapered_box(Vector2(0.5, 0.42) * size, Vector2(0.42, 0.3) * size, 0.075 * size, 0.05 * size), scoop_m, Vector3(x, y, zf + th * L))
		sc.rotation.x = tilt
		var op := _add(body, box(Vector3(0.4 * size, 0.045 * size, 0.05)), dark, Vector3(x, y + 0.035 * size, zf + th * L - 0.18 * size))
		op.rotation.x = tilt
	match hood:
		1, 6:
			scoop.call(0.0, 1.0)
		4:
			for sx in [-1, 1]:
				scoop.call(sx * 0.3, 0.6)
		2:
			var lt: float = S["cowl"] * 0.62
			var hv: PackedVector2Array = _section(S, lt, W, L, flare)["p"]
			for sx in [-1, 1]:
				for k in 6:
					var sl := _add(body, box(Vector3(0.24, 0.008, 0.018)), dark, Vector3(sx * 0.3, _top_y(hv, 0.3 / hv[7].x) + 0.004 + k * 0.04 * slope, zf + lt * L - 0.1 + k * 0.04))
					sl.rotation.x = tilt
		3:
			# NACA-Einlass: flache dunkle Mulde, vorn schmal, nach hinten breiter
			var t0 := th - 0.05
			var t1 := th + 0.04
			var y0 := _top_c(S, t0) + 0.003
			var y1 := _top_c(S, t1) + 0.003
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			_quad(st, Vector3(-0.05, y0, zf + t0 * L), Vector3(-0.14, y1, zf + t1 * L), Vector3(0.14, y1, zf + t1 * L), Vector3(0.05, y0, zf + t0 * L))
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = dark
			body.add_child(mi)


## Kaizen-Erkennungszeichen: Dachspoiler über der Heckscheibe und Sonnenstreifen mit Schriftzug oben in der Scheibe
## Eigenheiten der neuen Autos: Chromstoßstangen, aufgeschraubte Verbreiterungen, Hutze, Haubenschlitze, Lamellen im
## Motordeckel
static func _extras(body: Node3D, fb: Node3D, rbm: Node3D, car_id: String, S: Dictionary, W: float, L: float, flare: float,
		hood: int, kit: int, dark: Material, paint: Material) -> void:
	var zf := -L / 2.0
	var zr := L / 2.0
	if S.get("chrome_bumpers", false) and kit == 0:
		# Chromstoßstangen: Stange über die Front bzw. das Heck, an den Ecken nach hinten bzw. vorn um die Ecke
		var chrome_b := mat(Color(0.8, 0.8, 0.82), 0.95, 0.15)
		var yb := CLEARANCE + 0.19
		for end in [0.0, 1.0]:
			var p: PackedVector2Array = _section(S, end, W, L, flare)["p"]
			var ze := zf - 0.02 if end == 0.0 else zr + 0.02
			var par: Node3D = fb if end == 0.0 else rbm
			_add(par, box(Vector3(p[4].x * 2.0 + 0.02, 0.05, 0.05)), chrome_b, Vector3(0, yb, ze))
			for s in [-1, 1]:
				var dz := 0.08 if end == 0.0 else -0.08
				var c := _add(par, box(Vector3(0.04, 0.05, 0.17)), chrome_b, Vector3(s * (p[4].x + 0.03), yb, ze + dz))
				c.rotation_degrees.y = s * (16.0 if end == 0.0 else -16.0)
				# Gummipuffer (Hörner) an der Stoßstange
				_add(par, box(Vector3(0.05, 0.07, 0.03)), dark, Vector3(s * 0.38, yb, ze + (-0.025 if end == 0.0 else 0.025)))
	if S.get("overfenders", false):
		# Verbreiterungen: schwarze Bögen um die Radläufe, außen auf die Flanke geschraubt
		var ra := wheel_r(S) + 0.07
		var flare_m := mat(Color(0.03, 0.03, 0.035), 0.1, 0.65)
		for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
			for s in [-1, 1]:
				for k in 11:
					var a := deg_to_rad(-80.0 + k * 16.0)
					var y := wheel_r(S) + cos(a) * ra
					var z: float = wz + sin(a) * ra
					var x := _side_x(S, (z - zf) / L, clampf(y, CLEARANCE + 0.1, S["belt"] - 0.05), W, L, flare) + 0.022
					var seg := _add(body, box(Vector3(0.05, 0.035, ra * 0.29)), flare_m, Vector3(s * x, y, z))
					seg.rotation.x = a
	match car_id:
		"chibi":
			if hood == 0:
				# Hutze für den Ladeluftkühler, der Neigung der Haube folgend, Öffnung vorn
				var ht := 0.16
				var hp: PackedVector2Array = _section(S, ht, W, L, flare)["p"]
				var slope := (_top_c(S, ht + 0.02) - _top_c(S, ht - 0.02)) / (0.04 * L)
				var sc := _add(body, tapered_box(Vector2(0.42, 0.26), Vector2(0.36, 0.18), 0.055, 0.03), paint, Vector3(0, hp[10].y - 0.012, zf + ht * L))
				sc.rotation.x = -atan(slope)
				var op := _add(body, box(Vector3(0.32, 0.03, 0.02)), dark, Vector3(0, hp[10].y + 0.016, zf + ht * L - 0.095))
				op.rotation.x = -atan(slope)
		"tanuki":
			if hood == 0:
				# zwei Luftauslässe auf der Haube
				var vs: PackedVector2Array = _section(S, 0.2, W, L, flare)["p"]
				for s in [-1, 1]:
					_add(body, box(Vector3(0.2, 0.01, 0.15)), dark, Vector3(s * 0.28, _top_y(vs, 0.28 / vs[7].x) + 0.004, zf + 0.2 * L))
		"falke":
			# Gitter im Motordeckel hinten
			for k in 5:
				var t := 0.855 + k * 0.012
				var lp: PackedVector2Array = _section(S, t, W, L, flare)["p"]
				_add(body, box(Vector3(0.46, 0.008, 0.022)), dark, Vector3(0, lp[10].y + 0.004, zf + t * L))
		"furia":
			# Motordeckel mit zwei Reihen Lamellen
			for k in 7:
				var t := 0.67 + k * 0.035
				var lp: PackedVector2Array = _section(S, t, W, L, flare)["p"]
				for s in [-1, 1]:
					_add(body, box(Vector3(0.32, 0.008, 0.03)), dark, Vector3(s * 0.22, _top_y(lp, 0.22 / lp[7].x) + 0.005, zf + t * L))


static func _kaizen_extras(body: Node3D, S: Dictionary, W: float, L: float, mats: Dictionary) -> void:
	var roof_w: float = (W / 2.0 - S["tumble"]) * 2.0
	# Dachspoiler: setzt bündig an der Dachkante an und läuft flach über den Anfang der Heckscheibe
	var t0: float = S["rr"] + 0.01
	var t1: float = S["rr"] + 0.09
	var p0 := Vector3(0, _top_c(S, t0), (t0 - 0.5) * L)
	var p1 := Vector3(0, _top_c(S, t1) + 0.06, (t1 - 0.5) * L)
	var sb := Basis.looking_at(p1 - p0, Vector3.UP)
	var sl := (p1 - p0).length() + 0.06
	var sm := (p0 + p1) / 2.0 + Vector3(0, 0.006, 0)
	_add(body, box(Vector3(roof_w * 0.9, 0.03, sl)), mats["paint"], sm).basis = sb
	# Seitenwangen bis auf die Scheibe: der Spoiler sitzt auf, statt über dem Dach zu schweben
	for s in [-1, 1]:
		_add(body, box(Vector3(0.035, 0.07, sl * 0.85)), mats["paint"], sm + Vector3(s * roof_w * 0.43, -0.03, 0.0)).basis = sb
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
	# Anbauteile der Schürzen (Leuchten, Grill, Kennzeichen) hängen an den Schürzen-Meshes. Die Sammlung steigt nicht in
	# Meshes hinab: ohne Umhängen blieben sie ~25 einzelne Draw Calls je Auto und fehlten in der Fernansicht.
	for bn in ["FrontBumper", "RearBumper"]:
		var b := body.get_node_or_null(bn) as Node3D
		if b:
			for c in b.get_children():
				b.remove_child(c)
				(c as Node3D).transform = b.transform * (c as Node3D).transform
				body.add_child(c)
	var canon := {}
	for g in [root, body] + fronts + spinners:
		var buckets := {}
		collect_static(g, Transform3D.IDENTITY, stops, canon, buckets, func(mi, _xf): return 1 if mi.has_meta("near_only") else 0)
		for mi in merge_buckets(g, buckets):
			if mi.get_meta("merge_extra", 0) == 1:
				mi.set_meta("near_only", true)


## Fernansicht: das ganze Auto als eine Fläche in Vertexfarben, dazu je eine Fläche für Leuchtteile. Ab dist
## zeichnet die Grafikkarte nur das statt ~40 Einzelflächen; Räder und Neigung sieht man von dort ohnehin nicht.
static func _build_lod(root: Node3D, flames: Array, dist: float) -> void:
	var stops := {}
	for f in flames:
		stops[f] = true
	# Fernansicht ohne feine Details, mit den einfachen Ersatzteilen
	var swap := []
	var all := [root]
	while not all.is_empty():
		var nd: Node = all.pop_back()
		all.append_array(nd.get_children())
		if nd is MeshInstance3D and (nd.has_meta("near_only") or nd.has_meta("lod_only")):
			swap.append(nd)
			(nd as MeshInstance3D).visible = nd.has_meta("lod_only")
	var buckets := {}
	collect_static(root, Transform3D.IDENTITY, stops, {}, buckets, func(_mi, _xf): return 0)
	for nd in swap:
		(nd as MeshInstance3D).visible = nd.has_meta("near_only")
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
					or mi.transparency > 0.0 or mi.visibility_range_end > 0.0 or mi.has_meta("no_merge"):
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
	var ax := axle(S)
	var wr := wheel_r(S)
	var tf := ax / L
	var tr := 1.0 - ax / L
	# Draufsicht: runde Ecken, Kotflügel vorn, Hüften hinten
	var w := W / 2.0
	w -= S["round_f"] * pow(maxf(1.0 - t / 0.14, 0.0), 2.0)
	w -= S["round_r"] * pow(maxf(1.0 - (1.0 - t) / 0.12, 0.0), 2.0)
	var hip: float = (S["hips"] + flare) * exp(-pow((t - tr) / 0.1, 2.0))
	var fend: float = (0.015 + flare) * exp(-pow((t - tf) / 0.08, 2.0))
	var w2 := w + hip + fend
	var w3 := w2 - 0.05 - hip * 0.5
	# Radausschnitt
	var ra := wr + 0.045
	var dz := minf(absf(z - (-L / 2.0 + ax)), absf(z - (L / 2.0 - ax)))
	var arch := dz < ra
	# Schürzen unten eingezogen: die Unterkante steigt zu Bug und Heck hin an
	C += 0.06 * smoothstep(0.05, 0.0, t) + 0.1 * smoothstep(0.93, 1.0, t)
	var ybot := wr + sqrt(ra * ra - dz * dz) if arch else C + 0.05
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


## Geschlossene Klappscheinwerfer: Fugen eines Deckels je Seite auf der Haube (Mitte x_c, Breite w, von z0 bis z1 ab Bug)
static func _popups(body: Node3D, S: Dictionary, W: float, L: float, flare: float, seam_m: Material,
		x_c: float, w: float, z0: float, z1: float) -> void:
	var zf := -L / 2.0
	for s in [-1, 1]:
		for z in [z0, z1]:
			var ps: PackedVector2Array = _section(S, z / L, W, L, flare)["p"]
			_add(body, box(Vector3(w, 0.008, 0.008)), seam_m, Vector3(s * x_c, _top_y(ps, x_c / ps[7].x) + 0.004, zf + z))
		var zm := (z0 + z1) / 2.0
		var pm: PackedVector2Array = _section(S, zm / L, W, L, flare)["p"]
		for x in [x_c - w / 2.0, x_c + w / 2.0]:
			_add(body, box(Vector3(0.008, 0.008, z1 - z0)), seam_m, Vector3(s * x, _top_y(pm, x / pm[7].x) + 0.004, zf + zm))


## x der Flanke in Höhe y beim Querschnitt t (zwischen Schweller und Schulter)
static func _side_x(S: Dictionary, t: float, y: float, W: float, L: float, flare: float) -> float:
	var p: PackedVector2Array = _section(S, t, W, L, flare)["p"]
	if y <= p[3].y:
		return p[3].x
	for j in range(3, 7):
		if y <= p[j + 1].y:
			return lerpf(p[j].x, p[j + 1].x, (y - p[j].y) / maxf(p[j + 1].y - p[j].y, 1e-4))
	return p[7].x


## Leuchte (oder Zierleiste) aus einem Stück: ein Feld auf der Stirnfläche von x_in bis zur Kante und ein Streifen,
## der der Flanke bis t_wrap um die Ecke folgt, Ober- und Unterkante auf gleicher Höhe (y0..y1). Beide Seiten.
## end = 1: Heck, end = 0: Bug. x_in = 0: durchgehend über die ganze Breite.
static func _lamp(parent: Node3D, S: Dictionary, W: float, L: float, flare: float, m: Material,
		y0: float, y1: float, x_in: float, t_wrap: float, end := 1.0, off := 0.006) -> MeshInstance3D:
	var dz := 1.0 if end > 0.5 else -1.0
	var ze := (end - 0.5) * L + dz * off
	var n := 7 if absf(t_wrap - end) > 1e-4 else 0  # ohne Streifen um die Ecke: nur das Feld vorn bzw. hinten
	var ring := []
	for i in n + 1:
		var t := lerpf(end, t_wrap, float(i) / n) if n > 0 else end
		ring.append([_side_x(S, t, y0, W, L, flare), _side_x(S, t, y1, W, L, flare), (t - 0.5) * L])
	# Außennormale der Flanke je Ring (in der Draufsicht), daran wird der Streifen etwas abgehoben
	var nrm := []
	for i in n + 1:
		var a: Array = ring[maxi(i - 1, 0)]
		var b: Array = ring[mini(i + 1, n)]
		var tx: float = (b[0] + b[1]) / 2.0 - (a[0] + a[1]) / 2.0
		var tz: float = b[2] - a[2]
		var v := Vector3(tz, 0.0, -tx).normalized()
		if v.dot(Vector3(1.0, 0.0, dz)) < 0.0:
			v = -v
		nrm.append(v)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		var sx := Vector3(side, 1.0, 1.0)
		var fz := Vector3(0, 0, dz)
		var r0: Array = ring[0]
		if x_in < minf(r0[0], r0[1]):
			var q := [Vector3(x_in, y0, ze), Vector3(r0[0], y0, ze), Vector3(r0[1], y1, ze), Vector3(x_in, y1, ze)]
			_tri(st, q[0] * sx, q[1] * sx, q[2] * sx, fz, fz, fz, fz)
			_tri(st, q[0] * sx, q[2] * sx, q[3] * sx, fz, fz, fz, fz)
		for i in n:
			var p := []
			var pn := []
			for k in [i, i + 1]:
				var r: Array = ring[k]
				var o: Vector3 = nrm[k] * off
				p.append_array([Vector3(r[0], y0, r[2]) + o, Vector3(r[1], y1, r[2]) + o])
				pn.append_array([nrm[k], nrm[k]])
			var fn: Vector3 = ((nrm[i] + nrm[i + 1]) * sx).normalized()
			_tri(st, p[0] * sx, p[2] * sx, p[3] * sx, pn[0] * sx, pn[2] * sx, pn[3] * sx, fn)
			_tri(st, p[0] * sx, p[3] * sx, p[1] * sx, pn[0] * sx, pn[3] * sx, pn[1] * sx, fn)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	parent.add_child(mi)
	return mi


## Material eines Hautstücks (Band b zwischen Punkt b und b+1) bei t
static func _skin(S: Dictionary, b: int, t: float, g: float, seam: bool, vinyl: int, carbon_hood := false) -> String:
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
	if carbon_hood and b >= 7 and t > FRONT_SEAM + 0.008 and t < S["cowl"] - 0.004:
		return "carbon"
	var inside := t > 0.02 and t < 0.98
	match vinyl:
		1:  # Rennstreifen: zwei Streifen über Haube, Dach und Heck
			if b == 8 and inside:
				return "stripe"
		2:  # Seitenstreifen unten an der Flanke
			if b == 4 and t > 0.1 and t < 0.9:
				return "stripe"
		3:  # ein breiter Streifen in der Mitte
			if b == 9 and inside:
				return "stripe"
		4:  # zweifarbig: untere Hälfte abgesetzt
			if b == 3 or b == 4:
				return "stripe"
		5:  # Flankenband oben an der Flanke, vorn und hinten offen
			if b == 5 and t > 0.18 and t < 0.86:
				return "stripe"
		6:  # Haube und Heckdeckel ganz in Folienfarbe (Dach bleibt Lack)
			if b >= 8 and inside and (t < S["cowl"] or t > S["ge"]):
				return "stripe"
		7:  # Kontrastdach
			if b >= 7 and t >= S["rf"] and t <= S["rr"]:
				return "stripe"
		8:  # Rallye: Rennstreifen und Seitenstreifen zusammen
			if (b == 8 and inside) or (b == 4 and t > 0.1 and t < 0.9):
				return "stripe"
	if S.get("trim_low", false) and b == 3:
		return "trim"
	return "paint"


## Karosserie-Haut aus Querschnitten: Frontschürze, Mittelteil, Heckschürze als eigene Meshes. Fugen (Schürzen,
## Türen) sind schmale dunkle Bänder zwischen zwei dicht liegenden Querschnitten.
static func _shell(body: Node3D, S: Dictionary, W: float, L: float, flare: float, vinyl: int, mats: Dictionary, carbon_hood := false) -> void:
	var seams: Array = [FRONT_SEAM, REAR_SEAM] + S["doors"]
	var ra := wheel_r(S) + 0.045
	# Feste Querschnitte: Fugen (zwei dicht beieinander) und Radkanten (senkrechter Übergang)
	var must := []
	for sm in seams:
		must.append_array([sm, sm + 0.006 / L])
	for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
		for e in [-1.0, 1.0]:
			must.append_array([(wz + e * (ra - 0.002)) / L + 0.5, (wz + e * (ra + 0.002)) / L + 0.5])
	var extra := []
	var n := int(L / 0.09)
	for i in n + 1:
		extra.append(float(i) / n)
	extra.append_array([0.004, 0.012, 0.025, 0.045, 0.07, 0.955, 0.975, 0.988, 0.996])
	for key in ["cowl", "rf", "rr", "ge", "cp"]:
		extra.append(S[key])
	for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
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
			var key := _skin(S, j, tm, gm, is_seam, vinyl, carbon_hood)
			if key == "paint" and part != "Shell" and j == 4 and S.get("black_bumpers", false):
				key = "trim"
			elif key == "trim" and part == "RearBumper" and not S.get("black_bumpers", false):
				key = "paint"  # sonst wirken die schwarzen Ecken der Heckschürze wie ein Rahmen um das Heck
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


## Radradius und Abstand der Achsen von Bug und Heck je Auto (Kleinwagen: kleinere Räder, kurze Überhänge)
static func wheel_r(S: Dictionary) -> float:
	return S.get("wheel_r", WHEEL_R)


static func axle(S: Dictionary) -> float:
	return S.get("axle", AXLE)


## Motor hinten (Mittel- oder Heckmotor): Lamellen und Motorraum hinten, Kofferraum vorn
static func engine_rear(S: Dictionary) -> bool:
	return S.get("mid", false) or S.get("rear_engine", false)


## Animiert Räder, Lenkung, Karosserie-Neigung und Nitroflammen.
static func animate(car: Node3D, speed: float, steer: float, roll: float, pitch: float, nitro_on: bool, delta: float) -> void:
	for p in car.get_meta("front_pivots"):
		p.rotation.y = -steer * 0.5
	for s in car.get_meta("spinners"):
		s.rotation.x -= speed / float(car.get_meta("wheel_r", WHEEL_R)) * delta
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
## Flache Scheibe; große Scheiben runder (Felgen, Bremsen, Leuchten), kleine bleiben sparsam (Radmuttern)
static func _disc(r: float, h: float) -> CylinderMesh:
	var key := "disc_%.4f_%.4f" % [r, h]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 36 if r >= 0.1 else (20 if r >= 0.03 else 12)
	c.rings = 1
	_mesh_cache[key] = c
	return c


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Feines Detail nur für die Nahansicht (Fernansicht/LOD lässt es weg): Bremsscheiben-Löcher, Schrift, Wischer,
## der runde Reifen. Beim Verschmelzen bleibt es in eigenen Flächen, damit _build_lod es erkennt.
static func _near(mi: MeshInstance3D) -> MeshInstance3D:
	mi.set_meta("near_only", true)
	return mi


## Ersatz nur für die Fernansicht (z. B. Reifen mit 16 Ecken); unsichtbar, bis _build_lod ihn einsammelt
static func _far(mi: MeshInstance3D) -> MeshInstance3D:
	mi.set_meta("lod_only", true)
	mi.visible = false
	return mi


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
	var flare := kit_flare(cfg)
	var zf := -L / 2.0
	var sc := Node3D.new()
	sc.name = "Showcase"
	body.add_child(sc)
	var paint := paint_mat(car_id, cfg)
	var bay := mat(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	var chrome := mat(Color(0.78, 0.78, 0.8), 0.95, 0.15)
	var t0: float
	var t1: float
	# Mittelmotor: Motor hinten unter dem Heckdeckel, Nitro vorn im Kofferraum
	var at_front: bool = (mode == "engine") != engine_rear(S)
	if at_front:
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
	if at_front:
		hinge.position = Vector3(0, y1 + 0.03, zf + t1 * L)
		hinge.rotation_degrees.x = 62.0
		_add(hinge, lid, paint, Vector3(0, 0, -(depth + 0.04) / 2.0))
		_add(hinge, box(Vector3(half * 2.0 - 0.1, 0.01, depth - 0.1)), bay, Vector3(0, -0.018, -(depth + 0.04) / 2.0))
	else:
		hinge.position = Vector3(0, y0 + 0.03, zf + t0 * L)
		hinge.rotation_degrees.x = -64.0
		_add(hinge, lid, paint, Vector3(0, 0, (depth + 0.04) / 2.0))
		_add(hinge, box(Vector3(half * 2.0 - 0.1, 0.01, depth - 0.1)), bay, Vector3(0, -0.018, (depth + 0.04) / 2.0))
	if mode == "engine":
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
