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
## Sichtebene des Reifenqualms (tire_fx, seit 2.36): Neon, Lichtteppiche und Scheinwerfer der Autos beleuchten ihn nicht
## (Laternen schon). Bis 2.35 färbte das Neon-Decal den Qualm in einem scharf begrenzten Kasten.
const SMOKE_LAYER := 1 << 10
const OWN_LIGHT_MASK := 0xFFFFF & ~SMOKE_LAYER
const SHELL_SUB := 3  # Teilstücke je Band beim Verfeinern der Querschnitte (_refine)
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
## Optional: pipes/pipe_r (Endrohre), tire_w (Reifenbreite), softtop (Stoffverdeck), wheel_r (Radradius), axle (Achse so weit
##   von Bug und Heck), mid (Mittelmotor: Einlässe in den Flanken), rear_engine (Heckmotor), chrome_bumpers
##   (Chromstoßstangen), overfenders (aufgeschraubte Kotflügelverbreiterungen)
## Breite: Catalog "width" ist seit 2.37 die größte Breite wie bei den echten Vorbildern (über den Hüften, ohne Spiegel);
##   Hüften und Kotflügel-Buckel gehen von der Grundbreite ab (_section). Bis 2.36 kamen sie obendrauf: die Autos waren 3
##   bis 23 cm breiter als angegeben (Tengu 2,18 m statt 1,95 m, Raiden 2,18 m, Falke 2,04 m) und wirkten zu breit; dazu
##   waren die Hüften kräftiger (z. B. Tengu 0,115, Raiden 0,1, Falke 0,095 je Seite).
## arch_r (nur zur Laufzeit, build): Radius der Radläufe, wenn ein großes Rad mehr Platz braucht (wheel_fit)
const SHAPES := {
	"kaizen": {  # JDM-Fließheck (Civic-EG-Gefühl): rundliche flache Nase, schmale breite Scheinwerfer, große Scheiben,
		# langes Dach, steile Heckscheibe, fast senkrechte Klappe mit umlaufenden Rückleuchten, dicker Endtopf
		"nose": 0.6, "hood": 0.82, "cowl": 0.3, "rf": 0.49, "rr": 0.66, "ge": 0.935, "cp": 0.85,
		"roof": 1.29, "deck": 0.99, "tail": 0.95, "belt": 0.8, "fender": 0.0, "hips": 0.02,
		"round_f": 0.22, "round_r": 0.08, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.315, 0.62], "intake": Vector2(0.48, 0.06), "pipes": [0.46], "pipe_r": 0.085,
		"drop": 0.035,  # ab Werk etwas tiefer
	},
	"mirai": {  # 350Z: lange Haube, Dachbogen fließt ins kurze Heck, breite Hüften
		"nose": 0.6, "hood": 0.86, "cowl": 0.42, "rf": 0.56, "rr": 0.64, "ge": 0.89, "cp": 0.71,
		"roof": 1.22, "deck": 0.95, "tail": 0.96, "belt": 0.85, "fender": 0.04, "hips": 0.035,
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
		"roof": 1.27, "deck": 0.98, "tail": 0.99, "belt": 0.87, "fender": 0.02, "hips": 0.025,
		"round_f": 0.07, "round_r": 0.05, "tumble": 0.13, "hl": {6: 0.075, 5: 0.05}, "tl": {},
		"doors": [0.375, 0.55, 0.715], "intake": Vector2(0.66, 0.13),
	},
	"ronin": {  # RX-7: sehr flach, runde Formen, hohe Kotflügel, Glaskuppel, langes gewölbtes Heckfenster
		"nose": 0.54, "hood": 0.8, "cowl": 0.39, "rf": 0.55, "rr": 0.61, "ge": 0.87, "cp": 0.68,
		"roof": 1.18, "deck": 0.92, "tail": 0.93, "belt": 0.82, "fender": 0.06, "hips": 0.035,
		"round_f": 0.2, "round_r": 0.15, "tumble": 0.22, "hl": {}, "tl": {},
		"doors": [0.405, 0.655], "intake": Vector2(0.58, 0.13), "pipes": [0.0],
	},
	"kaze": {  # Supra-Gefühl: lang und rund, lange Nase, Kuppeldach, Bügelflügel, vier runde Rückleuchten
		"nose": 0.55, "hood": 0.83, "cowl": 0.41, "rf": 0.565, "rr": 0.645, "ge": 0.85, "cp": 0.73,
		"roof": 1.19, "deck": 0.95, "tail": 0.95, "belt": 0.83, "fender": 0.035, "hips": 0.04,
		"round_f": 0.23, "round_r": 0.17, "tumble": 0.25, "hl": {6: 0.11, 5: 0.075}, "tl": {},
		"doors": [0.43, 0.69], "intake": Vector2(0.6, 0.12), "pipes": [0.46], "pipe_r": 0.068,
	},
	"raijin": {  # Rallye-Limousine (Evo/Impreza): kantig, breite Backen, Hutze, riesiger Flügel, Schmutzfänger
		"nose": 0.66, "hood": 0.9, "cowl": 0.355, "rf": 0.495, "rr": 0.685, "ge": 0.825, "cp": 0.745,
		"roof": 1.28, "deck": 0.99, "tail": 1.0, "belt": 0.88, "fender": 0.055, "hips": 0.035,
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.12, "hl": {6: 0.075, 5: 0.06}, "tl": {},
		"doors": [0.37, 0.545, 0.725], "intake": Vector2(0.62, 0.17), "pipes": [0.42], "pipe_r": 0.072,
	},
	"yari": {  # Allrad-Rallye-Limousine (seit 2.36, Evo-Gefühl): hohes kantiges Glashaus, riesiges Maul mit Ladeluftkühler,
		# große Seiteneinlässe mit Nebelscheinwerfern, Haube mit Luftauslässen, ausgestellte Backen, klare Rückleuchten,
		# hoher Flügel, ein dickes Endrohr
		"nose": 0.68, "hood": 0.9, "cowl": 0.36, "rf": 0.49, "rr": 0.69, "ge": 0.815, "cp": 0.75,
		"roof": 1.31, "deck": 1.0, "tail": 1.0, "belt": 0.89, "fender": 0.065, "hips": 0.045,
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.11, "hl": {}, "tl": {},
		"doors": [0.36, 0.545, 0.725], "intake": Vector2(0.56, 0.15), "pipes": [0.44], "pipe_r": 0.06,
		"axle": 0.9, "wheel_r": 0.325, "tire_w": 0.235, "edge_f": 0.055, "edge_r": 0.05,
	},
	"tatsumaki": {  # Kreiskolben-Coupé (seit 2.36, FD-Gefühl): sehr flach und rund, Klappscheinwerfer, Kotflügel höher als
		# die Haube, Doppelbuckel-Dach (bubble), lange gewölbte Heckscheibe, schmales Leuchtenband, Bügelflügel
		"nose": 0.54, "hood": 0.79, "cowl": 0.405, "rf": 0.55, "rr": 0.625, "ge": 0.885, "cp": 0.7,
		"roof": 1.16, "deck": 0.93, "tail": 0.95, "belt": 0.8, "fender": 0.085, "hips": 0.045,
		"round_f": 0.24, "round_r": 0.16, "tumble": 0.25, "hl": {}, "tl": {},
		"doors": [0.415, 0.665], "intake": Vector2(0.38, 0.115), "pipes": [0.3, 0.405], "pipe_r": 0.045,
		"axle": 0.92, "tire_w": 0.235, "edge_f": 0.09, "edge_r": 0.075, "bubble": 0.014,
	},
	"tsubame": {  # Roadster (S2000/MX-5): lange Haube, kleines Stoffverdeck weit hinten, kurzes Heck
		"nose": 0.57, "hood": 0.8, "cowl": 0.465, "rf": 0.585, "rr": 0.655, "ge": 0.765, "cp": 0.71,
		"roof": 1.1, "deck": 0.9, "tail": 0.92, "belt": 0.82, "fender": 0.05, "hips": 0.035,
		"round_f": 0.19, "round_r": 0.13, "tumble": 0.27, "hl": {6: 0.125, 5: 0.045}, "tl": {},
		"doors": [0.47, 0.695], "intake": Vector2(0.42, 0.1), "pipes": [-0.32, 0.32], "softtop": true,
	},
	"hachi": {  # 80er-Fließheck (AE86): kantig, Klappscheinwerfer, schwarze Stoßfänger, breites Leuchtenband
		"nose": 0.63, "hood": 0.84, "cowl": 0.37, "rf": 0.52, "rr": 0.665, "ge": 0.9, "cp": 0.75,
		"roof": 1.22, "deck": 0.96, "tail": 0.95, "belt": 0.87, "fender": 0.0, "hips": 0.015,
		"round_f": 0.05, "round_r": 0.04, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.385, 0.66], "intake": Vector2(0.7, 0.05), "pipes": [-0.46], "pipe_r": 0.04,
		"tire_w": 0.2,
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
		"roof": 1.18, "deck": 0.99, "tail": 0.97, "belt": 0.8, "fender": 0.03, "hips": 0.045,
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
		"roof": 1.14, "deck": 0.97, "tail": 0.99, "belt": 0.79, "fender": 0.035, "hips": 0.035,
		"round_f": 0.21, "round_r": 0.07, "tumble": 0.24, "hl": {}, "tl": {},
		"doors": [0.36, 0.6], "intake": Vector2(0.55, 0.07), "pipes": [-0.3, -0.2, 0.2, 0.3], "pipe_r": 0.045, "mid": true,
	},
	"ryujin": {  # Breites Biturbo-Coupé (300ZX-Gefühl): flache Keilnase mit schmalen liegenden Scheinwerfern, Glasdach mit
		# Mittelsteg, kurzes hohes Heck mit Leuchtenband über die ganze Breite
		"nose": 0.57, "hood": 0.8, "cowl": 0.39, "rf": 0.525, "rr": 0.62, "ge": 0.845, "cp": 0.72,
		"roof": 1.2, "deck": 0.96, "tail": 0.98, "belt": 0.82, "fender": 0.03, "hips": 0.04,
		"round_f": 0.17, "round_r": 0.06, "tumble": 0.23, "hl": {6: 0.13}, "tl": {},
		"doors": [0.42, 0.67], "intake": Vector2(0.4, 0.07), "pipes": [-0.42, 0.42], "pipe_r": 0.06,
	},
	# --- Kleinwagen: kleinere Räder (wheel_r) und kurze Überhänge (axle) ---
	"chibi": {  # Kei-Turbo (Alto-Works-Gefühl): kurz, schmal, hoch, kurze Haube mit Hutze, langes Dach, senkrechte Klappe
		"nose": 0.66, "hood": 0.87, "cowl": 0.27, "rf": 0.43, "rr": 0.81, "ge": 0.972, "cp": 0.93,
		"roof": 1.38, "deck": 0.99, "tail": 0.97, "belt": 0.86, "fender": 0.0, "hips": 0.01,
		"round_f": 0.15, "round_r": 0.05, "tumble": 0.1, "hl": {}, "tl": {},
		"doors": [0.3, 0.6], "intake": Vector2(0.42, 0.07), "pipes": [0.36], "pipe_r": 0.045,
		"wheel_r": 0.275, "axle": 0.56, "tire_w": 0.17,
	},
	"hotaru": {  # Kei-Mittelmotor-Roadster (Beat-Gefühl): winzig, flach, Stoffverdeck, Kabine in der Mitte, flaches Heck
		"nose": 0.57, "hood": 0.77, "cowl": 0.37, "rf": 0.5, "rr": 0.57, "ge": 0.66, "cp": 0.63,
		"roof": 1.16, "deck": 0.9, "tail": 0.91, "belt": 0.79, "fender": 0.03, "hips": 0.03,
		"round_f": 0.17, "round_r": 0.11, "tumble": 0.2, "hl": {6: 0.1, 5: 0.035}, "tl": {},
		"doors": [0.39, 0.62], "intake": Vector2(0.36, 0.06), "pipes": [0.34], "pipe_r": 0.04, "softtop": true, "mid": true,
		"wheel_r": 0.27, "axle": 0.52, "tire_w": 0.165,
	},
	"tanuki": {  # Allrad-Turbo-Kleinwagen (GR-Yaris-Gefühl): kurz und breit, flaches Dach, riesige Hüften, großes Gitter vorn
		"nose": 0.66, "hood": 0.89, "cowl": 0.3, "rf": 0.46, "rr": 0.72, "ge": 0.925, "cp": 0.86,
		"roof": 1.35, "deck": 1.02, "tail": 0.99, "belt": 0.87, "fender": 0.04, "hips": 0.06,
		"round_f": 0.13, "round_r": 0.07, "tumble": 0.2, "hl": {}, "tl": {},
		"doors": [0.34, 0.62], "intake": Vector2(0.72, 0.17), "pipes": [-0.36, 0.36], "pipe_r": 0.055,
		"wheel_r": 0.31, "axle": 0.66,
	},
	# --- JDM-Klassiker: Chromstoßstangen (chrome_bumpers) ---
	"kaido": {  # 70er-Hardtop (Hakosuka-Gefühl): kantige Kiste, hohe flache Front mit Gitter über die ganze Breite, runde
		# Scheinwerfer, aufgeschraubte Kotflügelverbreiterungen (overfenders), vier runde Rückleuchten
		# 2.25: flacher und runder (vorher Dach 1,37 m, Gürtel 0,86 m, kaum Rundung: wirkte wie eine Kiste aus Klötzchen),
		# größere Räder
		"nose": 0.72, "hood": 0.84, "cowl": 0.36, "rf": 0.5, "rr": 0.69, "ge": 0.8, "cp": 0.74,
		"roof": 1.3, "deck": 0.93, "tail": 0.92, "belt": 0.82, "fender": 0.02, "hips": 0.025,
		"round_f": 0.08, "round_r": 0.065, "tumble": 0.15, "hl": {}, "tl": {},
		"doors": [0.375, 0.655], "intake": Vector2(0.3, 0.04), "pipes": [0.4], "pipe_r": 0.042,
		"wheel_r": 0.315, "axle": 0.74, "tire_w": 0.225, "chrome_bumpers": true, "overfenders": true,
	},
	"hakone": {  # 70er-Fließheck (S30-Gefühl): sehr lange Haube, Scheinwerfer in Mulden vorn in den Kotflügeln, kleines
		# Maul, Dach fließt bis ans Heck, Leuchten in einem schwarzen Feld
		"nose": 0.6, "hood": 0.83, "cowl": 0.47, "rf": 0.585, "rr": 0.655, "ge": 0.93, "cp": 0.83,
		"roof": 1.27, "deck": 0.96, "tail": 0.93, "belt": 0.82, "fender": 0.045, "hips": 0.03,
		"round_f": 0.16, "round_r": 0.06, "tumble": 0.18, "hl": {}, "tl": {},
		"doors": [0.49, 0.71], "intake": Vector2(0.42, 0.09), "pipes": [0.4], "pipe_r": 0.045,
		"wheel_r": 0.3, "axle": 0.72, "tire_w": 0.21, "chrome_bumpers": true,
	},
	# --- Exoten: größere Räder, lange Überhänge ---
	"kagura": {  # V10-Supersportler (LFA-Gefühl): lange Haube, Kabine weit hinten, nach hinten gezogene Scheinwerfer,
		# dreieckige Rückleuchten, drei Endrohre in der Mitte
		"nose": 0.56, "hood": 0.8, "cowl": 0.41, "rf": 0.555, "rr": 0.635, "ge": 0.86, "cp": 0.74,
		"roof": 1.2, "deck": 0.98, "tail": 0.99, "belt": 0.84, "fender": 0.04, "hips": 0.045,
		"round_f": 0.18, "round_r": 0.07, "tumble": 0.25, "hl": {6: 0.13, 5: 0.06}, "tl": {},
		"doors": [0.43, 0.68], "intake": Vector2(0.5, 0.12), "pipes": [-0.085, 0.0, 0.085], "pipe_r": 0.042,
		"wheel_r": 0.335, "axle": 0.84, "tire_w": 0.27,
	},
	"falke": {  # Heckmotor-Sportwagen (911-Gefühl): runde Scheinwerfer oben auf den Kotflügeln, flache Haube dazwischen,
		# Dach fällt in einem Bogen zum Heck, breite Hüften, Leuchtenband über das ganze Heck, Entenbürzel
		"nose": 0.56, "hood": 0.74, "cowl": 0.36, "rf": 0.5, "rr": 0.59, "ge": 0.8, "cp": 0.73,
		"roof": 1.27, "deck": 0.97, "tail": 0.95, "belt": 0.83, "fender": 0.085, "hips": 0.06,
		"round_f": 0.23, "round_r": 0.19, "tumble": 0.25, "hl": {}, "tl": {},
		"doors": [0.375, 0.655], "intake": Vector2(0.6, 0.1), "pipes": [-0.11, 0.11], "pipe_r": 0.05,
		"wheel_r": 0.33, "axle": 0.92, "tire_w": 0.26, "rear_engine": true,
	},
	"furia": {  # V12-Keil (Countach-Gefühl): sehr flach und breit, spitze Nase, Kanzel weit vorn, hoher Motordeckel mit
		# Lamellen, Y-Leuchten, sechseckige Einlässe, Endrohre in der Mitte
		"nose": 0.5, "hood": 0.71, "cowl": 0.32, "rf": 0.465, "rr": 0.55, "ge": 0.63, "cp": 0.66,
		"roof": 1.13, "deck": 1.0, "tail": 1.0, "belt": 0.8, "fender": 0.03, "hips": 0.045,
		"round_f": 0.06, "round_r": 0.04, "tumble": 0.27, "hl": {6: 0.07}, "tl": {},
		"doors": [0.33, 0.6], "intake": Vector2(0.74, 0.12), "pipes": [-0.075, 0.075], "pipe_r": 0.058, "mid": true,
		"wheel_r": 0.345, "axle": 1.0, "tire_w": 0.3,
	},
	"raiden": {  # Allrad-GT (seit 2.32, Level 10): langes, flaches Coupé, Kabine in der Mitte, breite Hüften, vier Endrohre
		"nose": 0.53, "hood": 0.77, "cowl": 0.39, "rf": 0.52, "rr": 0.6, "ge": 0.8, "cp": 0.71,
		"roof": 1.18, "deck": 0.99, "tail": 0.98, "belt": 0.82, "fender": 0.055, "hips": 0.055,
		"round_f": 0.12, "round_r": 0.06, "tumble": 0.27, "hl": {6: 0.1}, "tl": {},
		"doors": [0.38, 0.64], "intake": Vector2(0.66, 0.12), "pipes": [-0.12, -0.075, 0.075, 0.12], "pipe_r": 0.04,
		"wheel_r": 0.34, "axle": 0.95, "tire_w": 0.29,
	},
	"tengu": {  # Drift-Monster (seit 2.32, Level 16): kurzer Überhang hinten, breite Backen, großes Mittelrohr
		"nose": 0.55, "hood": 0.79, "cowl": 0.41, "rf": 0.53, "rr": 0.62, "ge": 0.84, "cp": 0.72,
		"roof": 1.2, "deck": 0.97, "tail": 0.96, "belt": 0.83, "fender": 0.075, "hips": 0.07,
		"round_f": 0.15, "round_r": 0.08, "tumble": 0.24, "hl": {6: 0.1}, "tl": {},
		"doors": [0.4, 0.66], "intake": Vector2(0.6, 0.13), "pipes": [0.0], "pipe_r": 0.065,
		"wheel_r": 0.335, "axle": 0.9, "tire_w": 0.3,
	},
}


## batch: Teile zu wenigen Meshes verschmelzen (spart im Rennen Zeichenaufrufe, kostet aber gut 0,4 s; die Garage
## mit nur einem Auto baut ohne, damit das Blättern im Tuning flüssig bleibt)
static func build(car_id: String, cfg: Dictionary, headlights := true, lod := true, batch := true) -> Node3D:
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var P: Dictionary = Catalog.PARTS
	var paint_c: Color = paint_color(car_id, cfg)
	var rim := rim_spec(car_id, cfg)
	var kit: int = int(cfg.get("bodykit", 0))
	var hood: int = int(cfg.get("hood", 0))
	var L: float = spec["length"]
	var W: float = spec["width"]
	var flare := kit_flare(cfg)
	var zf := -L / 2.0
	var zr := L / 2.0
	# Sitz der Räder (Spur, Sturz) und Radläufe: ein größeres Rad hebt die Karosserie, die Läufe werden weiter (die Form
	# hier ist eine Kopie, SHAPES bleibt unverändert)
	var drop: float = Catalog.part_of(cfg, "suspension")["drop"] + S.get("drop", 0.0)
	var fit := wheel_fit(rim, S, W, L, flare, drop)
	if fit["arch_r"] > arch_r(S) + 0.0005:
		S = S.duplicate()
		S["arch_r"] = fit["arch_r"]

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
		"glass": glass_mat(tint["color"], 1.0 if int(cfg.get("tint", 0)) == 3 else 0.0),
		"under": mat(Color(0.025, 0.025, 0.03), 0.0, 0.85),
		"seam": mat(Color(0.012, 0.012, 0.016), 0.2, 0.7),
		"head": mat(Color(1, 1, 0.95).lerp(light_c, 0.5), 0, 0.3, light_c, 2.6),
		"tail": mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 2.2),
		"stripe": stripe_m,
		"carbon": carbon_mat(),
		"top": mat(Color(0.03, 0.03, 0.035), 0.0, 0.95),
		"pillar": mat(Color(0.008, 0.008, 0.01), 0.1, 0.16),  # Klavierlack-Schwarz (B-Säule)
		"dark": dark,
	}
	# Fensterrahmen: schwarze Dichtung (dieselbe Fläche wie die Fugen), bei Autos mit Chromstoßstangen Chrom
	mats["frame"] = mat(Color(0.75, 0.75, 0.78), 0.95, 0.15) if S.get("chrome_bumpers", false) else mats["seam"]
	mats["cowl"] = mats["seam"]  # Windlauf und dunkle Siebdruckränder der Scheiben
	_shell(body, S, W, L, flare, int(cfg.get("vinyl", 0)), mats, hood == 5 or hood == 6)
	var front: PackedVector2Array = _section(S, 0.0, W, L, flare)["p"]
	var rear: PackedVector2Array = _section(S, 1.0, W, L, flare)["p"]

	# Front: Lufteinlass, je Auto eigene Lichter in der Schürze
	var fb: Node3D = body.get_node("FrontBumper")
	var head_m: Material = mats["head"]
	var amber := mat(Color(1, 0.55, 0.05), 0, 0.3, Color(1, 0.5, 0.0), 1.5)
	var fw: float = front[6].x  # halbe Breite der Bugfläche in Gürtelhöhe
	var iv: Vector2 = S["intake"]
	var iw := fw * 2.0 * iv.x
	var ic_k := 0.86  # Breite des Ladeluftkühlers im Einlass
	match car_id:
		"tatsumaki":  # ovales Maul
			_add(fb, _rplate(iw, iv.y, iv.y * 0.48), grille_mat(), Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.004))
			ic_k = 0.66
		"yari":  # großes Trapez, unten schmaler
			_add(fb, _poly_plate(PackedVector2Array([Vector2(-iw * 0.45, -iv.y / 2), Vector2(iw * 0.45, -iv.y / 2), Vector2(iw / 2, iv.y / 2),
				Vector2(-iw / 2, iv.y / 2)]), 0.02, 0.012), grille_mat(), Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.004))
			ic_k = 0.8
		_:
			_add(fb, box(Vector3(iw, iv.y, 0.012)), dark, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.004))
	if int(cfg.get("turbo", 0)) > 0 or car_id == "yari":
		# Ladeluftkühler hinter dem Einlass: silbernes Netz mit Lamellen (Yari ab Werk)
		var ic := mat(Color(0.55, 0.57, 0.6), 0.85, 0.35)
		var icw := iw * ic_k
		var ich := iv.y * 0.78
		_add(fb, box(Vector3(icw, ich, 0.01)), ic, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0, zf - 0.011))
		for k in int(ich / 0.022):
			_add(fb, box(Vector3(icw, 0.006, 0.012)), dark, Vector3(0, CLEARANCE + 0.07 + iv.y / 2.0 - ich / 2.0 + 0.011 + k * 0.022, zf - 0.017))
	if kit == 0:
		# dezente Frontlippe ab Werk (sportlich, nicht so ausladend wie das Bodykit)
		_add(fb, rbox(Vector3(fw * 2.0 - 0.18, 0.018, 0.08)), dark, Vector3(0, CLEARANCE + 0.005, zf + 0.03))
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
		"tatsumaki":  # FD-Gefühl: ovales Maul (oben), außen kleine runde Einlässe mit Blinkern, Klappscheinwerfer: in der
			# Garage zu (Fugen auf den Kotflügeln), auf der Straße hochgeklappt (_popup_pods)
			for s in [-1, 1]:
				var sx: float = s * (fw - 0.19)
				_add(fb, _rplate(0.19, 0.075, 0.034), grille_mat(), Vector3(sx, CLEARANCE + 0.14, zf - 0.004))
				_add(fb, _rplate(0.075, 0.028, 0.013, 0.01), amber, Vector3(s * (fw - 0.135), CLEARANCE + 0.15, zf - 0.011))
				_add(fb, _disc(0.02, 0.01), mat(Color(0.75, 0.77, 0.8), 0.9, 0.1), Vector3(s * (fw - 0.235), CLEARANCE + 0.145, zf - 0.011)).rotation_degrees.x = 90
				_add(fb, _rplate(0.11, 0.02, 0.009, 0.01), amber, Vector3(s * (fw - 0.08), S["nose"] - 0.075, zf - 0.006))
			if headlights:
				hy = _popup_pods(body, S, W, L, flare, paint, head_m, dark, 0.5, 0.34, 0.24, 0.6)
			else:
				_popups(body, S, W, L, flare, mats["seam"], 0.5, 0.34, 0.24, 0.6)
				hy = CLEARANCE + 0.15
		"yari":  # Evo-Gefühl: große, nach hinten gezogene klare Scheinwerfer, dazwischen ein schmaler Grill mit Schild in
			# Wagenfarbe, unten das große Trapez mit Ladeluftkühler, außen hohe Einlässe mit runden Nebelscheinwerfern
			var y0: float = front[5].y - 0.035
			var y1: float = front[6].y + 0.014
			var ym := (y0 + y1) / 2.0
			_lamp(fb, S, W, L, flare, dark, y0 - 0.012, y1 + 0.012, fw - 0.4, 0.088, 0.0, 0.004)
			_lamp(fb, S, W, L, flare, head_m, y0, y1, fw - 0.38, 0.084, 0.0, 0.008)
			_lamp(fb, S, W, L, flare, amber, y0, y0 + 0.018, fw - 0.13, 0.084, 0.0, 0.011)
			var gw := (fw - 0.42) * 2.0
			for s in [-1, 1]:
				_add(fb, _rplate(gw / 2.0 - 0.01, 0.06, 0.01), grille_mat(), Vector3(s * gw / 4.0, ym, zf - 0.006))
				_add(fb, _rplate(0.16, 0.13, 0.03), grille_mat(), Vector3(s * (fw - 0.14), CLEARANCE + 0.15, zf - 0.004))
				_add(fb, _disc(0.046, 0.012), mat(Color(0.75, 0.75, 0.78), 0.95, 0.15), Vector3(s * (fw - 0.14), CLEARANCE + 0.15, zf - 0.009)).rotation_degrees.x = 90
				_add(fb, _disc(0.037, 0.012), head_m, Vector3(s * (fw - 0.14), CLEARANCE + 0.15, zf - 0.012)).rotation_degrees.x = 90
			# Schild in der Mitte: lackiertes Trapez mit kleiner Plakette
			_add(fb, _poly_plate(PackedVector2Array([Vector2(-0.07, -0.035), Vector2(0.07, -0.035), Vector2(0.05, 0.04), Vector2(-0.05, 0.04)]),
				0.01, 0.014), paint, Vector3(0, ym - 0.004, zf - 0.009))
			_add(fb, _rplate(0.05, 0.03, 0.012, 0.006), mat(Color(0.75, 0.75, 0.78), 0.95, 0.15), Vector3(0, ym, zf - 0.017))
			hy = ym
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
		"hachi":  # Klappscheinwerfer (zu), breite Stand- und Blinklichter im Stoßfänger, Kühlerschlitz
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
			# Stoßfängerleiste in Wagenfarbe mit Kühlerschlitz
			_add(fb, rbox(Vector3(front[4].x * 2.0 + 0.02, 0.18, 0.1)), mats["paint"], Vector3(0, CLEARANCE + 0.15, zf + 0.025))
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
	_grille_intakes(fb, dark)
	# Echte Scheinwerfer nur mit dem vollen Renderer: im Browser zeichnet jedes Licht jedes Objekt, das es trifft,
	# noch einmal (das kostete bei vier Autos viel); dort macht der Lichtteppich (_light_pools) den Lichtschein
	if headlights and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, hy, zf - 0.1)
		spot.spot_range = 45.0
		spot.spot_angle = 32.0
		spot.light_energy = 4.0
		spot.light_color = light_c
		spot.rotation_degrees.x = -4.0
		spot.light_cull_mask = OWN_LIGHT_MASK
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
		"yari":  # klare Rückleuchten um die Ecken (silbernes Glas), darin zwei rote Ringe, Blinker und Rückfahrlicht
			var y0 := r_mid + 0.01
			var y1 := r_belt - 0.012
			var ym := (y0 + y1) / 2.0
			var clear := mat(Color(0.62, 0.62, 0.66), 0.85, 0.08)
			lamp.call(dark, y0 - 0.014, y1 + 0.014, rw - 0.5, 0.955, 0.004)
			lamp.call(clear, y0, y1, rw - 0.48, 0.96, 0.006)
			var rr := minf((y1 - y0) / 2.0 - 0.008, 0.05)
			for s in [-1, 1]:
				for k in 2:
					_add(rbm, _disc(rr, 0.012), tail_m, Vector3(s * (rw - 0.13 - k * (2.0 * rr + 0.04)), ym, zr + 0.009)).rotation_degrees.x = 90
				_add(rbm, _disc(rr * 0.55, 0.012), amber, Vector3(s * (rw - 0.13 - 2.0 * (2.0 * rr + 0.04)), ym + rr * 0.4, zr + 0.009)).rotation_degrees.x = 90
				_add(rbm, _disc(rr * 0.5, 0.012), rev_m, Vector3(s * (rw - 0.13 - 2.0 * (2.0 * rr + 0.04)), ym - rr * 0.5, zr + 0.009)).rotation_degrees.x = 90
		"tatsumaki":  # FD-Gefühl: schmales, dunkel getöntes Leuchtenband über das ganze Heck, darin je Seite runde Leuchten
			var y1 := r_belt - 0.006
			var y0 := y1 - 0.075
			var ym := (y0 + y1) / 2.0
			lamp.call(dark, y0 - 0.01, y1 + 0.01, 0.0, 0.955, 0.004)
			lamp.call(lens, y0, y1, 0.0, 0.96, 0.006)
			var rr := (y1 - y0) / 2.0 - 0.006
			for s in [-1, 1]:
				for k in 2:
					_add(rbm, _disc(rr, 0.012), tail_m, Vector3(s * (rw - 0.12 - k * (2.0 * rr + 0.03)), ym, zr + 0.01)).rotation_degrees.x = 90
				_add(rbm, _disc(rr * 0.8, 0.012), amber, Vector3(s * (rw - 0.12 - 2.0 * (2.0 * rr + 0.03)), ym, zr + 0.01)).rotation_degrees.x = 90
				_add(rbm, _disc(rr * 0.6, 0.012), rev_m, Vector3(s * 0.2, ym, zr + 0.01)).rotation_degrees.x = 90
		"tsubame":  # schmale Leuchten über die Ecken, innen ein heller Streifen
			var y0 := r_belt - 0.085
			var y1 := r_belt - 0.02
			lamp.call(dark, y0 - 0.01, y1 + 0.01, rw - 0.38, 0.958, 0.004)
			lamp.call(tail_m, y0, y1, rw - 0.28, 0.962, 0.006)
			for s in [-1, 1]:
				_add(rbm, box(Vector3(0.09, y1 - y0, 0.012)), rev_m, Vector3(s * (rw - 0.33), (y0 + y1) / 2.0, zr + 0.009))
		"hachi":  # Leuchtenband über das ganze Heck, Stoßfängerleiste in Wagenfarbe
			_add(rbm, rbox(Vector3(rear[4].x * 2.0 + 0.02, 0.18, 0.1)), mats["paint"], Vector3(0, CLEARANCE + 0.12, zr - 0.025))
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

	# Spiegel: dunkles Dreieck in der Fensterecke, Arm, Gehäuse quer zur Fahrt (rund, leicht nach hinten gepfeilt), hinten
	# das dunkle Spiegelglas. Seit 2.36 sitzt das Gehäuse auf einem Arm etwas von der Tür ab (vorher klebte es daran).
	var ms: PackedVector2Array = _section(S, S["cowl"] + 0.035, W, L, flare)["p"]
	var mz: float = zf + (S["cowl"] + 0.035) * L
	for s in [-1, 1]:
		_add(body, rbox(Vector3(0.03, 0.06, 0.1), 0.01), mats["pillar"], Vector3(s * (ms[6].x - 0.004), ms[6].y + 0.045, mz + 0.012))
		var arm := _add(body, rbox(Vector3(0.1, 0.022, 0.04), 0.009), paint, Vector3(s * (ms[6].x + 0.05), ms[6].y + 0.06, mz + 0.004))
		arm.rotation.z = s * 0.3
		var mp := Node3D.new()
		mp.position = Vector3(s * (ms[6].x + 0.145), ms[6].y + 0.085, mz)
		mp.rotation.y = -s * 0.14
		body.add_child(mp)
		_add(mp, rbox(Vector3(0.17, 0.09, 0.075), 0.03), paint, Vector3.ZERO)
		_add(mp, rbox(Vector3(0.145, 0.07, 0.01), 0.004), mats["glass"], Vector3(0, 0, 0.036))
	# Türgriffe, Fugen von Haube und Deckel, Antenne, Wappen, Rückstrahler, Heckwischer
	_door_handles(body, S, W, L, flare, paint, mats["seam"])
	_panel_lines(body, car_id, S, W, L, flare, mats["seam"])
	_small_parts(body, car_id, spec, S, W, L, flare, dark, mats)
	# Radläufe mit gerollter Kante, seitliche Begrenzungsleuchten, Tankdeckel, dritte Bremsleuchte
	_arch_lips(body, S, W, L, flare, paint)
	for e in [[0.05, amber], [0.955, mats["tail"]]]:
		var tm: float = e[0]
		var pm: PackedVector2Array = _section(S, tm, W, L, flare)["p"]
		var ym: float = lerpf(pm[5].y, pm[6].y, 0.25)
		var xa := _side_x(S, tm - 0.012, ym, W, L, flare)
		var xb := _side_x(S, tm + 0.012, ym, W, L, flare)
		var ang := atan2(xb - xa, 0.024 * L)
		for s in [-1, 1]:
			var mk := _add(body, rbox(Vector3(0.012, 0.028, 0.075), 0.005), e[1], Vector3(s * (_side_x(S, tm, ym, W, L, flare) + 0.003), ym, zf + tm * L))
			mk.rotation.y = -s * ang
	if not S.get("mid", false) and not S.get("rear_engine", false):
		var tf: float = (float((S["doors"] as Array)[-1]) + REAR_SEAM) / 2.0
		var pf: PackedVector2Array = _section(S, tf, W, L, flare)["p"]
		var yf: float = lerpf(pf[5].y, pf[6].y, 0.55)
		var xf := _side_x(S, tf, yf, W, L, flare)
		var ring := _add(body, _disc(0.068, 0.006), mats["seam"], Vector3(xf + 0.001, yf, zf + tf * L))
		ring.rotation_degrees.z = 90
		var cap := _add(body, _disc(0.062, 0.006), paint, Vector3(xf + 0.003, yf, zf + tf * L))
		cap.rotation_degrees.z = 90
	if not S.get("softtop", false):
		var tb: float = S["rr"] + 0.012
		var bl := _add(body, rbox(Vector3(0.26, 0.022, 0.035), 0.009), mats["tail"], Vector3(0, _top_c(S, tb) - 0.004, zf + tb * L))
		bl.rotation.x = -atan2(_top_c(S, tb + 0.01) - _top_c(S, tb - 0.01), 0.02 * L)
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
		_add(body, rtapered_box(Vector2(0.52, 0.46), Vector2(0.44, 0.34), 0.075, 0.05, 0.025), paint, Vector3(0, hp[10].y - 0.01, zf + hz))
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
				_add(body, box(Vector3(0.22, 0.2, 0.012)), flap, Vector3(s * _flap_x(S, W, L, flare, zi), CLEARANCE + 0.04, zi * (L / 2.0 - axle(S)) + arch_r(S) + 0.055))
	elif car_id == "yari" and hood == 0:
		# Haube mit großem Luftauslass vorn in der Mitte (Lamellen in Wagenfarbe über dunkler Öffnung) und je Seite einer
		# Reihe Kiemen
		var vt := 0.15
		var q := _top_pt(S, vt, 0.0, W, L, flare)
		var slope := atan2(_top_c(S, vt + 0.02) - _top_c(S, vt - 0.02), 0.04 * L)
		var pv := Node3D.new()
		pv.position = (q[0] as Vector3) + Vector3(0, 0.003, 0)
		pv.rotation.x = -slope
		body.add_child(pv)
		_add(pv, rbox(Vector3(0.5, 0.012, 0.24), 0.005), mats["seam"], Vector3.ZERO)
		for k in 5:
			_add(pv, box(Vector3(0.47, 0.016, 0.014)), paint, Vector3(0, 0.004, -0.09 + k * 0.045))
		for s in [-1, 1]:
			for k in 4:
				var t := 0.22 + k * 0.012
				var sq := _top_pt(S, t, s * 0.37, W, L, flare)
				var sl := _add(body, box(Vector3(0.17, 0.008, 0.018)), dark, (sq[0] as Vector3) + Vector3(0, 0.004, 0))
				sl.rotation.x = -slope

	if hood != 0:
		_hood(body, S, W, L, flare, hood, dark, mats["carbon"] if hood == 6 else paint)
	elif int(cfg.get("engine", 0)) >= 3 and car_id not in ["vortex", "raijin", "falke", "furia", "yari"]:
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

	# Bodykit: Schweller, Frontlippe, in Wagenfarbe (gehören zur Karosserie)
	if kit == 1 or kit == 2:
		var sp3: PackedVector2Array = _section(S, 0.5, W, L, flare)["p"]
		var sw := sp3[3].x
		for s in [-1, 1]:
			var sk := _add(body, rbox(Vector3(0.07, 0.09, L - 2.0 * axle(S) - 0.85)), mats["paint"], Vector3(s * (sw + 0.01), CLEARANCE + 0.05, 0))
			sk.name = "SideSkirt"
		_add(fb, rbox(Vector3(fw * 2.0 - 0.1, 0.03, 0.18)), mats["paint"], Vector3(0, CLEARANCE + 0.02, zf + 0.06))

	# Spoiler
	var sp: int = int(cfg.get("spoiler", 0))
	var wz := zr - 0.25
	var dp: PackedVector2Array = _section(S, (wz - zf) / L, W, L, flare)["p"]
	var deck_y := dp[10].y
	# halbe Spannweite der Flügel: Karosserie am Flügel + 2 cm (seit 2.37; bis dahin halbe Katalogbreite, mit den
	# schlankeren Karosserien standen Endplatten bis 7 cm über, ein großer Flügel am Falke 15 cm)
	var wh: float = dp[4].x + 0.02
	if sp == 0 and car_id == "kaze":
		# Serienflügel: Bügel von den äußeren Heckkanten, nach hinten geneigt
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.07, 0.25, 0.16)), paint, Vector3(s * (wh - 0.25), deck_y + 0.09, wz + 0.03)).rotation_degrees.x = 20
		_add(body, _airfoil(2.0 * wh - 0.4, 0.27, 0.04), paint, Vector3(0, deck_y + 0.21, wz + 0.08)).rotation_degrees.x = -5
	elif sp == 0 and car_id == "raijin":
		# Serienflügel: hoch, zwei Blätter
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.05, 0.26, 0.12)), dark, Vector3(s * (wh - 0.32), deck_y + 0.13, wz))
			_add(body, _endplate(0.035, 0.16, 0.38), paint, Vector3(s * (wh - 0.07), deck_y + 0.28, wz))
		_add(body, _airfoil(2.0 * wh - 0.14, 0.36, 0.04), paint, Vector3(0, deck_y + 0.26, wz))
		_add(body, _airfoil(2.0 * wh - 0.14, 0.14, 0.03), paint, Vector3(0, deck_y + 0.33, wz + 0.12)).rotation_degrees.x = -14
	elif sp == 0 and car_id == "hayate":
		# Serienflügel: hoch auf der Klappe, zwei Stützen
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.04, 0.13, 0.1)), paint, Vector3(s * (wh - 0.36), deck_y + 0.06, wz + 0.04))
		_add(body, _airfoil(2.0 * wh - 0.36, 0.22, 0.035), paint, Vector3(0, deck_y + 0.14, wz + 0.06)).rotation_degrees.x = -6
	elif sp == 0 and (car_id == "kitsune" or car_id == "tenshi" or car_id == "kumo" or car_id == "ryujin"):
		# Serien-Bürzel: flache Abrisskante an der Heckkante
		var bt := 1.0 - 0.07 / L
		var bp: PackedVector2Array = _section(S, bt, W, L, flare)["p"]
		_add(body, rbox(Vector3(bp[7].x * 2.0 - 0.06, 0.035, 0.12)), paint, Vector3(0, bp[10].y + 0.018, zf + bt * L - 0.02)).rotation_degrees.x = -10
	elif sp == 0 and car_id == "tanuki":
		# Serien-Dachspoiler über der Heckscheibe, seitlich kleine Finnen
		var rt: float = S["rr"]
		var ry := _top_c(S, rt)
		var roof_h: float = (_section(S, rt, W, L, flare)["p"] as PackedVector2Array)[7].x  # halbe Dachbreite
		_add(body, _airfoil(roof_h * 2.0 - 0.18, 0.2, 0.03), paint, Vector3(0, ry - 0.012, zf + rt * L + 0.1)).rotation_degrees.x = -6
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.025, 0.05, 0.18)), paint, Vector3(s * (roof_h - 0.12), ry - 0.035, zf + rt * L + 0.1))
	elif sp == 0 and car_id == "kagura":
		# schmale Abrisskante aus Kohlefaser hinten auf dem Deckel
		_add(body, _airfoil(2.0 * wh - 0.5, 0.14, 0.025), carbon_mat(), Vector3(0, deck_y + 0.03, wz + 0.12)).rotation_degrees.x = -8
	elif sp == 0 and car_id == "falke":
		# Entenbürzel: der Motordeckel biegt hinten nach oben
		_add(body, tapered_box(Vector2(2.0 * wh - 0.42, 0.34), Vector2(2.0 * wh - 0.48, 0.1), 0.07, 0.1), paint, Vector3(0, deck_y - 0.02, wz + 0.04))
	elif sp == 0 and car_id == "furia":
		# flaches Flügelblatt über dem Heck, zwei kurze Stützen
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.04, 0.08, 0.12)), dark, Vector3(s * (wh - 0.45), deck_y + 0.03, wz + 0.08))
		_add(body, _airfoil(2.0 * wh - 0.44, 0.24, 0.03), carbon_mat(), Vector3(0, deck_y + 0.08, wz + 0.1)).rotation_degrees.x = -5
	elif sp == 0 and car_id == "shiden":
		# Serienflügel aus einem Stück mit den Flanken: zwei Finnen an den Heckecken, Blatt über die ganze Breite
		var fy: float = deck_y
		for s in [-1, 1]:
			_add(body, tapered_box(Vector2(0.06, 0.4), Vector2(0.05, 0.26), 0.11, 0.06), paint, Vector3(s * (wh - 0.13), fy - 0.02, wz + 0.02))
		_add(body, _airfoil(2.0 * wh - 0.18, 0.24, 0.035), paint, Vector3(0, fy + 0.1, wz + 0.08)).rotation_degrees.x = -4
	elif sp == 0 and car_id == "tatsumaki":
		# Serienflügel: flacher Bügel hinten auf der Klappe, Stützen außen in Wagenfarbe
		var bt := 1.0 - 0.13 / L
		var by: float = (_section(S, bt, W, L, flare)["p"] as PackedVector2Array)[10].y
		for s in [-1, 1]:
			_add(body, tapered_box(Vector2(0.05, 0.2), Vector2(0.045, 0.12), 0.095, 0.03), paint, Vector3(s * (wh - 0.27), by - 0.02, zr - 0.13))
		_add(body, _airfoil(2.0 * wh - 0.5, 0.17, 0.03), paint, Vector3(0, by + 0.075, zr - 0.11)).rotation_degrees.x = -4
	elif sp == 0 and car_id == "yari":
		# Serienflügel: hoch auf zwei dunklen Stützen, großes Blatt mit Abrisskante, Endplatten in Wagenfarbe
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.045, 0.3, 0.13), 0.012), dark, Vector3(s * (wh - 0.36), deck_y + 0.14, wz + 0.02))
			_add(body, _endplate(0.03, 0.17, 0.4), paint, Vector3(s * (wh - 0.09), deck_y + 0.3, wz + 0.02))
		_add(body, _airfoil(2.0 * wh - 0.18, 0.34, 0.045), paint, Vector3(0, deck_y + 0.29, wz + 0.02)).rotation_degrees.x = -6
	elif sp == 1:
		_add(body, _airfoil(2.0 * wh - 0.4, 0.16, 0.045), paint, Vector3(0, deck_y + 0.02, zr - 0.12))
	elif sp == 2 or sp == 3:
		var hgt := 0.22 if sp == 2 else 0.4
		var ww := 2.0 * wh - 0.12 if sp == 2 else 2.0 * wh + 0.04
		for s in [-1, 1]:
			_add(body, rbox(Vector3(0.05, hgt, 0.1)), dark, Vector3(s * (wh - 0.38), deck_y + hgt / 2, wz))
			_add(body, _endplate(0.04, 0.18, 0.42), paint, Vector3(s * ww / 2, deck_y + hgt + 0.02, wz))
		_add(body, _airfoil(ww, 0.4, 0.045), paint, Vector3(0, deck_y + hgt, wz)).rotation_degrees.x = -4
		if sp == 3:
			_add(body, _airfoil(ww, 0.2, 0.04), dark, Vector3(0, deck_y + hgt + 0.1, wz + 0.1)).rotation_degrees.x = -12
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
		dc.cull_mask = 0xFFFFF & ~(CAR_LAYER | SMOKE_LAYER)
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
		for z in ([] if RenderingServer.get_current_rendering_method() == "gl_compatibility" else [-1, 1]):
			var ol := OmniLight3D.new()
			ol.light_color = nc
			ol.light_energy = 0.9
			ol.light_specular = 0.0  # kein Glanzpunkt: sonst spiegelt sich das Licht als Streifen in Pfützen
			ol.omni_range = 2.6
			ol.light_cull_mask = OWN_LIGHT_MASK
			ol.position = Vector3(0, 0.12, z * L * 0.3)
			body.add_child(ol)

	# Auspuff + Flammen: Nitro ein blauer Kegel, Fehlzündung ein kurzer orangefarbener (animate() tauscht das Material)
	var flames := []
	var flame_m := mat(Color(0.3, 0.6, 1), 0, 0.5, Color(0.3, 0.6, 1.0), 6.0)
	flame_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_m.albedo_color.a = 0.8
	var fire_m := mat(Color(1.0, 0.55, 0.2), 0, 0.5, Color(1.0, 0.45, 0.1), 5.0)
	fire_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_m.albedo_color.a = 0.8
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
	# Endrohr (seit 2.36 doppelwandig): außen das Rohr, an der Mündung ein gerollter Rand, innen ein dunkles Rohr mit
	# zurückgesetztem Boden (vorher eine flache dunkle Scheibe vorn auf dem Rohr)
	var lip_m := TorusMesh.new()
	lip_m.inner_radius = pr * 0.8
	lip_m.outer_radius = pr * 1.02
	lip_m.rings = 24
	lip_m.ring_segments = 6
	var wall := CylinderMesh.new()
	wall.top_radius = pr * 0.82
	wall.bottom_radius = pr * 0.82
	wall.height = 0.1
	wall.radial_segments = 20
	wall.rings = 1
	wall.cap_top = false
	wall.cap_bottom = false
	wall.flip_faces = true
	for x in pipes:
		var pipe := CylinderMesh.new()
		pipe.top_radius = pr - 0.005
		pipe.bottom_radius = pr
		pipe.height = 0.16
		pipe.radial_segments = 24
		var p := _add(body, pipe, pipe_m, Vector3(x, CLEARANCE + 0.08, zr + 0.03))
		p.rotation_degrees.x = 90
		p.scale = Vector3(1, 1, oval)
		var lip := _add(body, lip_m, pipe_m, Vector3(x, CLEARANCE + 0.08, zr + 0.108))
		lip.rotation_degrees.x = 90
		lip.scale = Vector3(1, 0.45, oval)
		var wl := _add(body, wall, dark, Vector3(x, CLEARANCE + 0.08, zr + 0.06))
		wl.rotation_degrees.x = 90
		wl.scale = Vector3(1, 1, oval)
		var inner := _add(body, _disc(pr * 0.82, 0.01), mats["seam"], Vector3(x, CLEARANCE + 0.08, zr + 0.02))
		inner.rotation_degrees.x = 90
		inner.scale = Vector3(1, 1, oval)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.09
		cone.height = 0.7
		var f := _add(body, cone, flame_m, Vector3(x, CLEARANCE + 0.08, zr + 0.4))
		f.rotation_degrees.x = 90
		f.visible = false
		f.set_meta("z0", zr + 0.05)  # Rohrmündung: die kurze Fehlzündungsflamme setzt hier an
		flames.append(f)
	root.set_meta("flame_mats", [flame_m, fire_m])

	# Räder (seit 2.37): je Rad drei geteilte Meshes (Reifen, Felge mit Bremsscheibe, Sattel), je Material eine Fläche
	# (_wheel_mesh). Sitz aus wheel_fit: Spur je Achse knapp innerhalb der Kotflügelkante, große Räder heben die Karosserie,
	# tief und breit gibt negativen Sturz. Felgengröße in Zoll und Reifen aus rim_spec.
	var tire_m := tire_mat()
	var rc: Dictionary = Catalog.part_of(cfg, "rimcol")
	var rim_c: Color = rim["color"]
	var rim_m: Material = mat(rim_c, 0.65, 0.28)
	if rc.get("paint", false):
		# Wagenfarbe ohne Folie: das Motiv läge sonst in Felgenkoordinaten auf den Speichen
		var c_nv := cfg.duplicate()
		c_nv["vinyl"] = 0
		rim_m = paint_mat(car_id, c_nv)
		rim_c = paint_c
	elif rc.has("color"):
		rim_c = rc["color"]
		rim_m = mat(rim_c, 0.85 if rc.get("chrome", false) else 0.65, 0.14 if rc.get("chrome", false) else 0.28)
	# poliertes Metall statt Chrom: flache Chromflächen spiegeln nachts nur Schwarz
	var polish := mat(Color(0.86, 0.87, 0.89), 0.72, 0.24)
	# Sättel: getunt rot, Klasse S ab Werk gelb, sonst dunkel; große Bremsen gelocht
	var big_brake: bool = perf > 0 or spec["class"] == "S"
	var cal_c := Color(0.85, 0.06, 0.04) if perf > 0 else (Color(0.95, 0.66, 0.04) if spec["class"] == "S" else Color(0.2, 0.2, 0.22))
	var role_m := {"face": rim_m, "lip": polish if rim["polish"] else rim_m, "barrel": mat(rim_c.darkened(0.55), 0.55, 0.42),
		"dark": dark, "chrome": polish, "accent": mat(Color(0.8, 0.08, 0.05), 0.6, 0.3), "rotor": mat(Color(0.46, 0.46, 0.48), 0.8, 0.32),
		"hat": mat(Color(0.2, 0.2, 0.22), 0.7, 0.45), "caliper": mat(cal_c, 0.3, 0.35)}
	var fronts := []
	var spinners := []
	var blurs := []
	var wr: float = rim["wheel_r"]
	var mu: float = rim["mu"]
	var tw: float = float(rim["tire_w"]) * mu  # Reifenbreite in Modellmaßen (das Rad wird danach skaliert)
	var o := tw / 2.0
	var rr: float = rim["radius"]
	var blur_m := _blur_mesh(rr, rim_c, rim["style"])
	for zi in [-1, 1]:
		var track: float = fit["track_f"] if zi < 0 else fit["track_r"]
		for s in [-1, 1]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * track, wr + fit["camber_lift"], zi * (L / 2 - axle(S)))
			pivot.scale = Vector3.ONE * (wr / WHEEL_R)  # kleinere/größere Räder: das ganze Rad samt Felge und Bremse skaliert
			pivot.rotation.z = s * fit["camber"]  # oben nach innen
			root.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			_add(spin, _tire_mesh(tw, rr - 0.008, mu, s), tire_m, Vector3.ZERO)
			var far_tire := CylinderMesh.new()
			far_tire.top_radius = WHEEL_R
			far_tire.bottom_radius = WHEEL_R
			far_tire.height = tw
			far_tire.radial_segments = 16
			far_tire.rings = 1
			_far(_add(spin, far_tire, tire_m, Vector3.ZERO)).rotation_degrees.z = 90
			_far(_add(spin, _disc(rr, 0.012), rim_m, Vector3(s * (o + 0.002), 0, 0))).rotation_degrees.z = 90
			var wm: Array = _wheel_mesh(rim, tw, big_brake, s)
			var wmi := _add(spin, wm[0], null, Vector3.ZERO)
			for i in (wm[1] as Array).size():
				wmi.set_surface_override_material(i, role_m[wm[1][i]])
			# Bremssattel steht still (am Achsschenkel), oben hinten über der Scheibe
			var cm: Array = _caliper_mesh(rim, tw, big_brake, s)
			var cmi := _add(pivot, cm[0], null, Vector3.ZERO)
			for i in (cm[1] as Array).size():
				cmi.set_surface_override_material(i, role_m[cm[1][i]])
			# alles außer den Fernansicht-Ersatzteilen nur in der Nahansicht
			for c in spin.get_children() + pivot.get_children():
				if c is MeshInstance3D and not c.has_meta("lod_only"):
					c.set_meta("near_only", true)
			# Unschärfescheibe (steht still, dreht nicht mit): blendet bei schnell drehendem Rad ein, animate()
			var bm := StandardMaterial3D.new()
			bm.vertex_color_use_as_albedo = true
			bm.vertex_color_is_srgb = true
			bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			bm.albedo_color = Color(1, 1, 1, 0)
			bm.metallic = 0.5
			bm.roughness = 0.4
			var bl := _add(pivot, blur_m, bm, Vector3(s * (o + 0.02), 0, 0))
			bl.rotation.y = 0.0 if s > 0 else PI
			bl.set_meta("no_merge", true)
			bl.visible = false
			blurs.append(bl)
			spinners.append(spin)
			if zi == -1:
				fronts.append(pivot)

	var head_spots := _lamp_spots(body, mats["head"])
	var tail_spots := _lamp_spots(body, mats["tail"])
	_lamp_detail(body, mats, L, light_c, not car_id in POPUP_IN)
	body.position.y += fit["lift"] - fit["drop"]
	if batch and not OS.get_cmdline_user_args().has("--nobatch"):
		_merge_parts(root, body, fronts, spinners, flames)
		if lod:
			_build_lod(root, flames, GameState.car_lod_distance())
			for bl in blurs:
				(bl as GeometryInstance3D).visibility_range_end = GameState.car_lod_distance()
				(bl as GeometryInstance3D).visibility_range_end_margin = 2.0
	# Ersatzteile der Fernansicht stecken jetzt im LOD-Mesh (oder werden ohne LOD nicht gebraucht)
	var far := [root]
	while not far.is_empty():
		var nd: Node = far.pop_back()
		far.append_array(nd.get_children())
		if nd.has_meta("lod_only"):
			nd.get_parent().remove_child(nd)
			nd.free()
	_lamp_glows(body, head_spots, tail_spots, light_c)
	if headlights:
		_light_pools(root, W, L, light_c)
	_set_layer(root)
	root.set_meta("body", body)
	root.set_meta("front_pivots", fronts)
	root.set_meta("spinners", spinners)
	root.set_meta("flames", flames)
	root.set_meta("length", L)
	root.set_meta("width", W)
	root.set_meta("wheel_r", wr)
	root.set_meta("blurs", blurs)
	# Winkel zwischen zwei gleichen Speichen (Drahtspeichen: zwei Lagen), für Unschärfe und Begrenzung in animate()
	root.set_meta("rim_period", TAU / float(maxi(int(rim["spokes"]) * (2 if rim["style"] == "wire" else 1), 1)))
	root.set_meta("axle", axle(S))
	root.set_meta("eye", Vector3(0, S["roof"] - 0.1 + fit["lift"], zf + (S["cowl"] + 0.07) * L))
	root.set_meta("track_r", fit["track_r"])
	return root


## Kennzeichen je Auto (Kürzel für "Need for Geschwindigkeit", dahinter eine Nummer mit Bezug zum Vorbild)
static func plate_text(car_id: String) -> String:
	var nums := {"kaizen": "92", "hachi": "86", "sakura": "15", "hayate": "88", "kitsune": "18", "tsubame": "99",
		"mirai": "240", "tenshi": "91", "kumo": "100", "raijin": "4", "vortex": "34", "ronin": "33", "shiden": "1",
		"ryujin": "300", "kaze": "7", "chibi": "660", "hotaru": "64", "tanuki": "20", "kaido": "73", "hakone": "24",
		"kagura": "10", "falke": "911", "furia": "12", "yari": "8", "tatsumaki": "13"}
	return "NF-G " + str(nums.get(car_id, str(absi(hash(car_id)) % 900 + 100)))


## Lackfarbe: "Werkslack" (Stufe 0) ist je Auto eigen (Kaizen in Championship-Weiß), sonst die gewählte Farbe
static func paint_color(car_id: String, cfg: Dictionary) -> Color:
	var opt: Dictionary = Catalog.PARTS["paint"]["options"][cfg.get("paint", 0)]
	if int(cfg.get("paint", 0)) == 0:
		return Catalog.CARS[car_id].get("paint", opt["color"])
	return opt["color"]


## Lackarten (Shader car_paint): metal/rough = Grundlack, coat = Klarlack, flakes = Metallic-Flitter, flop = zur Seite
## dunkler, pearl = Anteil des Schimmertons am Rand, rim = helle Kanten (Chrom spiegelt nachts sonst fast nur Schwarz)
const FINISH := {
	"gloss": {"metal": 0.2, "rough": 0.3, "coat": 1.0, "coat_rough": 0.03},
	"metal": {"metal": 0.78, "rough": 0.36, "coat": 1.0, "coat_rough": 0.04, "flakes": 1.0, "flop": 0.65},
	"matt": {"metal": 0.08, "rough": 0.82, "coat": 0.0, "coat_rough": 0.5},
	"pearl": {"metal": 0.35, "rough": 0.24, "coat": 1.0, "coat_rough": 0.03, "flakes": 0.45, "pearl": 0.6, "rim": 0.35, "rim_tint": 0.2},
	"chrome": {"metal": 0.85, "rough": 0.08, "coat": 0.6, "coat_rough": 0.02, "rim": 1.0, "rim_tint": 0.6},
	"chrome_matt": {"metal": 0.9, "rough": 0.42, "coat": 0.0, "coat_rough": 0.5, "rim": 0.5, "rim_tint": 0.7},
}
const PAINT_SHADER := preload("res://shaders/car_paint.gdshader")
const GLASS_SHADER := preload("res://shaders/car_glass.gdshader")
## Lichtkarte der Strecke für den Lack: track_builder._bake_street_light setzt sie (tex, rect, gain), die Garage leert
## sie. Autos unter Laternen und im Tunnel bekommen so dasselbe Licht wie die Straße darunter.
static var street := {}


## Lackart: "Standard" in der Kategorie Lackart nimmt die der Farbe (Candyblau metallic, Mattschwarz matt, Werkslack
## je Auto), sonst die gewählte. Chrom bleibt Chrom (matt gewählt: gebürstet).
static func paint_finish(car_id: String, cfg: Dictionary) -> String:
	var own: String
	if int(cfg.get("paint", 0)) == 0:
		var spec: Dictionary = Catalog.CARS[car_id]
		own = str(spec.get("finish", "" if spec.has("paint") else "metal"))  # ohne eigene Farbe: Silbermetallic
	else:
		own = str(Catalog.part_of(cfg, "paint").get("finish", ""))
	var pick := str(Catalog.part_of(cfg, "finish").get("finish", ""))
	if own == "chrome":
		return "chrome_matt" if pick == "matt" else "chrome"
	if pick != "":
		return pick
	return own if own != "" else "gloss"


## Schimmerton für Perlmutt: bunte Lacke kippen etwas im Farbton und werden heller, Weiß/Silber schimmern kühl
## lavendel, Schwarz tiefblau
static func pearl_tint(c: Color) -> Color:
	if c.s < 0.25:
		if c.v < 0.3:
			return Color(0.16, 0.2, 0.45)
		return Color(0.84, 0.85, 1.0) * clampf(c.v * 1.05, 0.5, 1.0)
	return Color.from_hsv(fposmod(c.h + 0.06, 1.0), c.s * 0.75, minf(c.v * 1.2 + 0.15, 1.0))


static func paint_mat(car_id: String, cfg: Dictionary) -> Material:
	var c := paint_color(car_id, cfg)
	var f: Dictionary = FINISH[paint_finish(car_id, cfg)]
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("metal", f["metal"])
	m.set_shader_parameter("rough", f["rough"])
	m.set_shader_parameter("coat", f["coat"])
	m.set_shader_parameter("coat_rough", f["coat_rough"])
	m.set_shader_parameter("flakes", f.get("flakes", 0.0))
	m.set_shader_parameter("flop", f.get("flop", 0.0))
	m.set_shader_parameter("pearl", f.get("pearl", 0.0))
	m.set_shader_parameter("pearl_color", pearl_tint(c))
	m.set_shader_parameter("rim_k", f.get("rim", 0.0))
	m.set_shader_parameter("rim_tint_k", f.get("rim_tint", 0.5))
	m.set_meta("lod_color", c)  # Fernansicht (_build_lod) malt den Lack als Vertexfarbe
	vinyl_params(m, car_id, cfg)
	light_paint(m)
	return m


## Vinyl mit Motiv (Catalog.PARTS vinyl, "art"): Bild und Maße dieses Autos an den Lack (Shader car_paint). Die Maße
## sind die der Karosserie (Bug, Länge, Schweller bis Gürtellinie, halbe Breite mit Breitbau), das Motiv streckt sich
## darauf: so passt jedes Vinyl auf jedes Auto. Einfarbige Motive (tint) nehmen die Folienfarbe, "Kontrast" ist Weiß
## auf dunklem und Schwarz auf hellem Lack.
## Welt (world.gd setzt es): Vinyl-Bilder im Hintergrund laden. Herausforderer tauchen mitten in der Fahrt auf, ein
## Bild synchron zu laden kostete dort einen Ruckler (gut 10 ms); das Motiv erscheint dann ein paar Bilder später.
static var async_vinyls := false
static var _vinyl_wait := []  # [ShaderMaterial, Pfad]


static func vinyl_params(m: ShaderMaterial, car_id: String, cfg: Dictionary) -> void:
	var opt: Dictionary = Catalog.part_of(cfg, "vinyl")
	var path := "res://assets/vinyls/%s.svg" % str(opt.get("art", ""))
	if not opt.has("art") or not ResourceLoader.exists(path):
		m.set_shader_parameter("vinyl_on", 0.0)
		return
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var L: float = spec["length"]
	if async_vinyls and not ResourceLoader.has_cached(path):
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)
		m.set_shader_parameter("vinyl_on", 0.0)
		_vinyl_wait.append([m, path])
		var tree := Engine.get_main_loop() as SceneTree
		if tree and not tree.process_frame.is_connected(_poll_vinyls):
			tree.process_frame.connect(_poll_vinyls)
	else:
		m.set_shader_parameter("vinyl_tex", load(path))
		m.set_shader_parameter("vinyl_on", 1.0)
	m.set_shader_parameter("vinyl_box", Vector4(-L / 2.0, L, CLEARANCE + 0.05, float(S["belt"]) + 0.02))
	m.set_shader_parameter("vinyl_hw", float(spec["width"]) / 2.0 + kit_flare(cfg) + 0.03)
	m.set_shader_parameter("vinyl_mirror", 1.0 if opt.get("mirror", true) else 0.0)
	var vc: Dictionary = Catalog.part_of(cfg, "vinylcol")
	var tint := Color(0.95, 0.95, 0.95) if paint_color(car_id, cfg).get_luminance() < 0.5 else Color(0.05, 0.05, 0.05)
	if vc.has("color"):
		tint = vc["color"]
	tint.a = 1.0 if opt.get("tint", false) else 0.0
	m.set_shader_parameter("vinyl_tint", tint)
	m.set_shader_parameter("vinyl_metal", 0.85 if opt.get("tint", false) and vc.get("metal", false) else 0.1)


static func _poll_vinyls() -> void:
	for w in _vinyl_wait.duplicate():
		var path: String = w[1]
		var tex: Texture2D = null
		if ResourceLoader.has_cached(path):
			tex = load(path)
		else:
			var st := ResourceLoader.load_threaded_get_status(path)
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				tex = ResourceLoader.load_threaded_get(path)
			elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_vinyl_wait.erase(w)
				continue
		if tex:
			(w[0] as ShaderMaterial).set_shader_parameter("vinyl_tex", tex)
			(w[0] as ShaderMaterial).set_shader_parameter("vinyl_on", 1.0)
			_vinyl_wait.erase(w)
	if _vinyl_wait.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.process_frame.is_connected(_poll_vinyls):
			tree.process_frame.disconnect(_poll_vinyls)


## Lichtkarte der Strecke auf einen Lack (auch für den Lack der Verkehrsautos)
static func light_paint(m: ShaderMaterial) -> void:
	if street.is_empty():
		m.set_shader_parameter("street_car", 0.0)
		return
	m.set_shader_parameter("street_light", street["tex"])
	m.set_shader_parameter("street_rect", street["rect"])
	m.set_shader_parameter("street_gain", street["gain"])
	m.set_shader_parameter("street_car", 1.0)


## Einfacher Glanzlack (Verkehr): dieselbe Lackoberfläche und dasselbe Laternenlicht wie bei den Rennautos
static func gloss_mat(c: Color, metal := 0.3, rough := 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("metal", metal)
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("coat", 0.6)
	m.set_shader_parameter("coat_rough", 0.08)
	m.set_meta("lod_color", c)
	light_paint(m)
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


## Flügel-Endplatte: flache Platte (Dicke thick quer zur Fahrt), Umriss in der Seitenansicht vorn unten abgeschrägt,
## alle Ecken rund; Rand mit weichen Normalen. Mitte im Ursprung wie ein Quader gleicher Größe.
static func _endplate(thick: float, h: float, ln: float) -> ArrayMesh:
	var key := "plate_%.3f_%.3f_%.3f" % [thick, h, ln]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var hz := ln / 2.0
	var hy := h / 2.0
	var corners := [Vector2(-hz, -hy * 0.35), Vector2(-hz + ln * 0.3, -hy), Vector2(hz, -hy), Vector2(hz, hy), Vector2(-hz + ln * 0.12, hy)]
	var rc := minf(h, ln) * 0.18
	var outline := PackedVector2Array()  # (z, y)
	var nc := corners.size()
	for i in nc:
		var c: Vector2 = corners[i]
		var a: Vector2 = (corners[(i - 1 + nc) % nc] - c).normalized()
		var b: Vector2 = (corners[(i + 1) % nc] - c).normalized()
		var p0 := c + a * rc
		var p1 := c + b * rc
		for k in 5:
			var f := k / 4.0
			outline.append(p0.lerp(c, f).lerp(c.lerp(p1, f), f))  # quadratische Kurve um die Ecke
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(outline)
	var tx := thick / 2.0
	for e in [-1.0, 1.0]:
		var nx := Vector3(e, 0, 0)
		for k in range(0, tri.size(), 3):
			var va: Vector2 = outline[tri[k]]
			var vb: Vector2 = outline[tri[k + 1]]
			var vc: Vector2 = outline[tri[k + 2]]
			_tri(st, Vector3(e * tx, va.y, va.x), Vector3(e * tx, vb.y, vb.x), Vector3(e * tx, vc.y, vc.x), nx, nx, nx, nx)
	var no := outline.size()
	var ctr := Vector2.ZERO
	for v in outline:
		ctr += v
	ctr /= no
	var vn := []
	for i in no:
		var d: Vector2 = outline[(i + 1) % no] - outline[(i - 1 + no) % no]
		var n2 := Vector2(d.y, -d.x).normalized()
		if n2.dot(outline[i] - ctr) < 0.0:
			n2 = -n2
		vn.append(Vector3(0.0, n2.y, n2.x))
	for i in no:
		var j := (i + 1) % no
		var A := Vector3(-tx, outline[i].y, outline[i].x)
		var B := Vector3(tx, outline[i].y, outline[i].x)
		var Cq := Vector3(tx, outline[j].y, outline[j].x)
		var D := Vector3(-tx, outline[j].y, outline[j].x)
		var nf: Vector3 = vn[i] + vn[j]
		_tri(st, A, B, Cq, vn[i], vn[i], vn[j], nf)
		_tri(st, A, Cq, D, vn[i], vn[j], vn[j], nf)
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


# --- Räder (seit 2.37) ----------------------------------------------------------------------------------------------
## Ein Rad sind drei Meshes, die alle Autos teilen (_mesh_cache): Reifen, Felge mit Bremsscheibe und Bremssattel (steht
## still am Achsschenkel). Je Material eine Fläche ("Rolle": face Speichen und Stern, lip Horn und Stufenbett, barrel
## Felgenbett innen, dark Schatten und Löcher, chrome Radmuttern, Nieten, Ventilkappe, accent Zentralmutter, rotor/hat
## Bremsscheibe und Topf, caliper Sattel); build() gibt jeder Rolle ihr Material. Bis 2.36 waren es 40 bis 70 Einzelteile
## je Rad, in der Garage (ohne Verschmelzen) jedes ein Draw Call.
## Gebaut wird in Modellmaßen (Reifen außen WHEEL_R, das Rad wird danach auf seine echte Größe skaliert) und immer das
## rechte Rad (außen = +X), das linke entsteht gespiegelt. mu = Modelleinheiten je Meter: Nabe, Radmuttern und Bremse
## haben echte Maße und wachsen nicht mit der Felge (eine 20-Zoll-Felge zeigt mehr Luft um die Bremse als eine 15er).
const WHEEL_ROLES := ["face", "lip", "barrel", "dark", "chrome", "accent", "rotor", "hat"]
## Rad-Meshes (Felge, Reifen, Sattel, Unschärfescheibe) hängen von Felge, Größe, Reifenbreite und Spur ab: in der Garage
## kam bis 2.37 bei jedem Teil, über das man fährt, ein neues dazu (87 Vorschauen: +38 MB Grafikspeicher, wichtig im
## Browser). Seit 2.37 bleiben nur die zuletzt benutzten WHEEL_CACHE Einträge im Cache (gut 15 Räder mit Reifen, Sattel
## und Scheibe), ältere fallen heraus; ein Auto, das ein Mesh noch trägt, behält es, bis es selbst verschwindet.
const WHEEL_CACHE := 64
static var _wheel_keys: Array = []


## Rad-Mesh aus dem Cache holen (null, wenn nicht da) und als zuletzt benutzt markieren
static func _wget(key: String):
	var v = _mesh_cache.get(key)
	if v != null:
		var i := _wheel_keys.find(key)
		if i >= 0 and i < _wheel_keys.size() - 1:
			_wheel_keys.remove_at(i)
			_wheel_keys.append(key)
	return v


## Rad-Mesh ablegen; über WHEEL_CACHE fällt das am längsten unbenutzte heraus
static func _wput(key: String, v) -> void:
	if not _mesh_cache.has(key):
		_wheel_keys.append(key)
	_mesh_cache[key] = v
	while _wheel_keys.size() > WHEEL_CACHE:
		_mesh_cache.erase(_wheel_keys.pop_front())
## Bauarten mit poliertem Horn und Stufenbett (mehrteilig) bzw. Chromrand
const POLISHED_LIP := ["mesh", "dish", "3pc", "thin", "wire", "cup"]


## Dreieck in den Rohbau wb (Rolle -> [Punkte, Normalen, UVs]); Vorderseite nach nf (Godot: im Uhrzeigersinn)
static func _wtri(wb: Dictionary, role: String, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nf: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	if not wb.has(role):
		wb[role] = [[], [], []]
	var buf: Array = wb[role]
	if (c - a).cross(b - a).dot(nf) < 0.0:
		var tv := b
		b = c
		c = tv
		var tn := nb
		nb = nc
		nc = tn
		var tu := ub
		ub = uc
		uc = tu
	buf[0].append_array([a, b, c])
	buf[1].append_array([na, nb, nc])
	buf[2].append_array([ua, ub, uc])


## Viereck a-b-c-d (umlaufend), Normalen je Ecke
static func _wquad(wb: Dictionary, role: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		nd: Vector3, nf: Vector3) -> void:
	_wtri(wb, role, a, b, c, na, nb, nc, nf)
	_wtri(wb, role, a, c, d, na, nc, nd, nf)


## Drehkörper um die X-Achse aus dem Profil prof (Vector2(x, r)), seg Schritte am Umfang. Die Normale eines Abschnitts
## ist (-d.r, d.x): Profile laufen so, dass sie nach außen zeigt (über eine Fläche nach vorn: von außen nach innen, über
## eine Außenseite: von hinten nach vorn). An weichen Knicken (unter ~50°) gemittelt. vs: v je Profilpunkt (UV), u am
## Umfang 0..1.
static func _wrev(wb: Dictionary, role: String, prof: Array, seg: int, vs: Array = []) -> void:
	var np := prof.size()
	var segn := []
	for i in np - 1:
		var d: Vector2 = prof[i + 1] - prof[i]
		segn.append(Vector2(-d.y, d.x).normalized() if d.length() > 1e-7 else Vector2.ZERO)
	var cs := []
	for k in seg + 1:
		cs.append(Vector2(cos(TAU * k / seg), sin(TAU * k / seg)))
	for i in np - 1:
		var sn: Vector2 = segn[i]
		if sn == Vector2.ZERO:
			continue
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var n0 := sn
		var n1 := sn
		if i > 0 and (segn[i - 1] as Vector2).dot(sn) > 0.64:
			n0 = (segn[i - 1] + sn).normalized()
		if i < np - 2 and (segn[i + 1] as Vector2).dot(sn) > 0.64:
			n1 = (segn[i + 1] + sn).normalized()
		var v0: float = vs[i] if vs.size() > i else 0.0
		var v1: float = vs[i + 1] if vs.size() > i + 1 else 0.0
		for k in seg:
			var ca: Vector2 = cs[k]
			var cb: Vector2 = cs[k + 1]
			var A := Vector3(p0.x, p0.y * ca.x, p0.y * ca.y)
			var B := Vector3(p0.x, p0.y * cb.x, p0.y * cb.y)
			var C := Vector3(p1.x, p1.y * ca.x, p1.y * ca.y)
			var D := Vector3(p1.x, p1.y * cb.x, p1.y * cb.y)
			var nA := Vector3(n0.x, n0.y * ca.x, n0.y * ca.y)
			var nB := Vector3(n0.x, n0.y * cb.x, n0.y * cb.y)
			var nC := Vector3(n1.x, n1.y * ca.x, n1.y * ca.y)
			var nD := Vector3(n1.x, n1.y * cb.x, n1.y * cb.y)
			var cm := (ca + cb).normalized()
			var nf := Vector3(sn.x, sn.y * cm.x, sn.y * cm.y)
			var u0 := float(k) / seg
			var u1 := float(k + 1) / seg
			if p1.y > 1e-6:
				_wtri(wb, role, A, C, D, nA, nC, nD, nf, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1))
			if p0.y > 1e-6:
				_wtri(wb, role, A, D, B, nA, nD, nB, nf, Vector2(u0, v0), Vector2(u1, v1), Vector2(u1, v0))


## Flaches Vieleck (n Ecken, Radius r) um c, Vorderseite nach nrm, raised hebt die Mitte an (Kuppe: Nieten, Schrauben)
static func _wdisc(wb: Dictionary, role: String, c: Vector3, r: float, n: int, nrm: Vector3, raised := 0.0) -> void:
	var u := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.FORWARD).normalized()
	var v := nrm.cross(u).normalized()
	var tip := c + nrm * raised
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := c + (u * cos(a0) + v * sin(a0)) * r
		var p1 := c + (u * cos(a1) + v * sin(a1)) * r
		var nn := nrm if raised <= 0.0 else (p1 - tip).cross(p0 - tip).normalized()
		if nn.dot(nrm) < 0.0:
			nn = -nn
		_wtri(wb, role, tip, p0, p1, nn, nn, nn, nn)


## Sechskant (Radmutter): Prisma entlang +X von x0 bis x1 um (y, z), Kopf leicht gefast
static func _wnut(wb: Dictionary, role: String, y: float, z: float, x0: float, x1: float, r: float, n := 6) -> void:
	var ctr := Vector3(x0, y, z)
	for k in n:
		var a0 := TAU * k / n + PI / n
		var a1 := TAU * (k + 1) / n + PI / n
		var d0 := Vector3(0, cos(a0), sin(a0))
		var d1 := Vector3(0, cos(a1), sin(a1))
		var nf := Vector3(0, cos((a0 + a1) / 2.0), sin((a0 + a1) / 2.0))
		var b0 := ctr + d0 * r
		var b1 := ctr + d1 * r
		var t0 := b0 + Vector3(x1 - x0 - r * 0.25, 0, 0)
		var t1 := b1 + Vector3(x1 - x0 - r * 0.25, 0, 0)
		_wquad(wb, role, b0, t0, t1, b1, nf, nf, nf, nf, nf)
		# Fase zum Kopf
		var c0 := Vector3(x1, y, z) + d0 * r * 0.72
		var c1 := Vector3(x1, y, z) + d1 * r * 0.72
		var nc := (nf + Vector3.RIGHT).normalized()
		_wquad(wb, role, t0, c0, c1, t1, nc, nc, nc, nc, nc)
		_wtri(wb, role, Vector3(x1, y, z), c0, c1, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)


## Schnitte einer Speiche von Radius r0 (Nabe) bis r1 (Bett) ab Winkel a: Breite vorn w0 -> w1 (wfn(f) statt linear, wenn
## gesetzt), hinten back-mal so breit (Formschräge), Tiefe th, Fase ch. bend: so weit dreht sie bis außen (Sichel,
## Kreuzspeichen; bexp formt den Bogen), off0/off1: seitlicher Versatz innen/außen (Doppelspeichen). xf(r): Lage der
## Vorderseite (Konkave), dx verschiebt (zweite Lage beim Gitter).
static func _wst(a: float, r0: float, r1: float, w0: float, w1: float, xf: Callable, th: float, ch: float, n := 5, bend := 0.0,
		bexp := 1.4, off0 := 0.0, off1 := 0.0, back := 1.2, dx := 0.0, wfn := Callable(), straight := false) -> Array:
	var pts := []
	for i in n:
		var f := float(i) / (n - 1)
		if straight:
			# gerade Sehne vom Anfangs- zum Endpunkt (Kreuzgitter), nicht als Spirale
			pts.append(Vector2(cos(a), sin(a)) * r0 * (1.0 - f) + Vector2(cos(a + bend), sin(a + bend)) * r1 * f)
			continue
		var r := lerpf(r0, r1, f)
		var ang := a + bend * pow(f, bexp)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	var out := []
	for i in n:
		var f := float(i) / (n - 1)
		var d: Vector2 = ((pts[mini(i + 1, n - 1)] as Vector2) - (pts[maxi(i - 1, 0)] as Vector2)).normalized()
		var t := Vector2(-d.y, d.x)
		var q: Vector2 = pts[i] + t * lerpf(off0, off1, f)
		var w: float = wfn.call(f) if wfn.is_valid() else lerpf(w0, w1, f)
		out.append([Vector3(float(xf.call(q.length())) + dx, q.x, q.y), Vector3(0.0, t.x, t.y), w, w * back, th, ch])
	return out


## Speiche aus Schnitten (_wst): Seiten, Fasen und Vorderseite (crown > 0: Grat in der Mitte, gewölbt bzw. als V), die
## Rückseite sieht man nie. Normalen flach je Fläche, entlang der Speiche gemittelt. cap_end: Stirnfläche außen (Speichen,
## die bis über das Horn laufen).
static func _wspoke(wb: Dictionary, role: String, st: Array, crown := 0.0, cap_end := false) -> void:
	var X := Vector3.RIGHT
	var secs := []
	for s in st:
		var c: Vector3 = s[0]
		var t: Vector3 = s[1]
		var hf: float = s[2] / 2.0
		var hb: float = s[3] / 2.0
		var th: float = s[4]
		var ch: float = minf(s[5], hf * 0.45)
		var sec := [c - t * hb - X * th, c - t * (hf + ch) - X * ch, c - t * hf]
		if crown != 0.0:
			sec.append(c + X * crown)
		sec.append_array([c + t * hf, c + t * (hf + ch) - X * ch, c + t * hb - X * th])
		secs.append(sec)
	var n := secs.size()
	var m: int = (secs[0] as Array).size()
	var fn := []
	for i in n - 1:
		var row := []
		var ctr: Vector3 = ((st[i][0] as Vector3) + (st[i + 1][0] as Vector3)) / 2.0 - X * (float(st[i][4]) * 0.5)
		for j in m - 1:
			var a: Vector3 = secs[i][j]
			var b: Vector3 = secs[i][j + 1]
			var c: Vector3 = secs[i + 1][j + 1]
			var d: Vector3 = secs[i + 1][j]
			var nn := (c - a).cross(d - b).normalized()
			if nn.dot((a + b + c + d) / 4.0 - ctr) < 0.0:
				nn = -nn
			row.append(nn)
		fn.append(row)
	# Punktnormalen: entlang der Speiche gemittelt, quer nur über flache Knicke (Wölbung der Vorderseite, unter ~30°);
	# Fasen und Seiten bleiben scharf
	var vn := func(i: int, j: int, side: int) -> Vector3:
		var acc := Vector3.ZERO
		for ii in [i - 1, i]:
			if ii < 0 or ii > n - 2:
				continue
			var f0: Vector3 = fn[ii][j]
			acc += f0
			var jn := j + side
			if jn >= 0 and jn < m - 1 and (fn[ii][jn] as Vector3).dot(f0) > 0.87:
				acc += fn[ii][jn]
		return acc.normalized()
	for i in n - 1:
		for j in m - 1:
			var nf: Vector3 = fn[i][j]
			_wquad(wb, role, secs[i][j], secs[i][j + 1], secs[i + 1][j + 1], secs[i + 1][j], vn.call(i, j, -1), vn.call(i, j, 1),
				vn.call(i + 1, j, 1), vn.call(i + 1, j, -1), nf)
	if cap_end:
		var last: Array = secs[n - 1]
		var dl: Vector3 = ((st[n - 1][0] as Vector3) - (st[n - 2][0] as Vector3)).normalized()
		for j in range(1, m - 1):
			_wtri(wb, role, last[0], last[j], last[j + 1], dl, dl, dl, dl)


## Rohbau in ein ArrayMesh (je Rolle eine Fläche, in der Reihenfolge roles); mirror: linkes Rad (X gespiegelt, Umlaufsinn
## gedreht). Liefert [Mesh, Liste der Rollen je Fläche].
static func _wcommit(wb: Dictionary, roles: Array, mirror: bool, uv := false) -> Array:
	var mesh := ArrayMesh.new()
	var used := []
	for role in roles:
		if not wb.has(role):
			continue
		var buf: Array = wb[role]
		var pv := PackedVector3Array(buf[0])
		var pn := PackedVector3Array(buf[1])
		var pu := PackedVector2Array(buf[2])
		if pv.is_empty():
			continue
		if mirror:
			for i in pv.size():
				var p := pv[i]
				pv[i] = Vector3(-p.x, p.y, p.z)
				var q := pn[i]
				pn[i] = Vector3(-q.x, q.y, q.z)
			for i in range(0, pv.size(), 3):
				var tp := pv[i + 1]
				pv[i + 1] = pv[i + 2]
				pv[i + 2] = tp
				var tq := pn[i + 1]
				pn[i + 1] = pn[i + 2]
				pn[i + 2] = tq
				var tu := pu[i + 1]
				pu[i + 1] = pu[i + 2]
				pu[i + 2] = tu
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pv
		arr[Mesh.ARRAY_NORMAL] = pn
		if uv:
			arr[Mesh.ARRAY_TEX_UV] = pu
		# indiziert: Punkte mit gleicher Lage, Normale und UV nur einmal (Drehkörper teilen jeden Punkt mit bis zu sechs
		# Dreiecken), seit 2.37 gut halb so viel Speicher bei gleichem Bild
		var st := SurfaceTool.new()
		st.create_from_arrays(arr, Mesh.PRIMITIVE_TRIANGLES)
		st.index()
		st.commit(mesh)
		used.append(role)
	return [mesh, used]


## Reifen: Drehkörper mit flacher, leicht gewölbter Lauffläche, drei (breit: vier) Längsrillen, runden Schultern, leicht
## bauchiger Flanke und Felgenschutz-Wulst am Fuß. Querrillen, Lamellen und ein unlesbares Schriftband malt tire_mat()
## über die UVs: u am Umfang, v quer (Lauffläche -1..1 von innen nach außen, Schultern bis ±2, Flanke außen 2..3, innen
## -2..-3). tw Breite, rb Wulst-Radius (Modellmaße), mu Modelleinheiten je Meter, side < 0: linkes Rad (gespiegelt, die
## beschriftete Flanke zeigt auch dort nach außen). Bis 2.36: Ballon mit drei Rillen, beide Seiten gleich.
static func _tire_mesh(tw: float, rb: float, mu: float, side := 1) -> ArrayMesh:
	var key := "tire_%.4f_%.4f_%.3f_%d" % [tw, rb, mu, signi(side)]
	var hit = _wget(key)
	if hit != null:
		return hit
	var R := WHEEL_R
	var h := tw / 2.0
	var sh := R - rb
	var sr := clampf(sh * 0.3, 0.009, 0.022)  # Schulter
	var bul := clampf(sh * 0.11, 0.003, 0.008)  # Bauch der Flanke
	var xt := h - sr
	var crown := func(x: float) -> float: return R - 0.0022 * (x / h) * (x / h)
	var yt: float = crown.call(xt)
	var prof := []
	var vs := []
	var sidev := func(r: float) -> float: return 2.0 + clampf((yt - sr - r) / maxf(yt - sr - rb, 0.001), 0.0, 1.0)
	# innen: Wulst, Flanke, Schulter (sieht man kaum)
	for p in [Vector2(-h + 0.007, rb), Vector2(-h - bul * 0.8, rb + sh * 0.4), Vector2(-h - bul * 0.4, yt - sr * 1.15)]:
		prof.append(p)
		vs.append(-float(sidev.call(p.y)))
	for ph in [70.0, 35.0]:
		var a := deg_to_rad(ph)
		prof.append(Vector2(-xt - sr * sin(a), yt - sr + sr * cos(a)))
		vs.append(-(1.0 + ph / 90.0))
	# Lauffläche mit Längsrillen (leicht unsymmetrisch wie bei echten Sportreifen)
	var gw := 0.0095 * mu
	var gd := minf(0.0065 * mu, sh * 0.25)
	var grooves: Array = [-0.6, -0.18, 0.2, 0.62] if tw / mu >= 0.25 else [-0.5, 0.04, 0.55]
	prof.append(Vector2(-xt, yt))
	vs.append(-1.0)
	for g in grooves:
		var gx: float = g * xt
		for q in [[gx - gw / 2.0, 0.0], [gx - gw / 2.0 + 0.0012, gd], [gx + gw / 2.0 - 0.0012, gd], [gx + gw / 2.0, 0.0]]:
			prof.append(Vector2(q[0], float(crown.call(q[0])) - q[1]))
			vs.append(q[0] / xt)
	prof.append(Vector2(xt, yt))
	vs.append(1.0)
	for ph in [35.0, 70.0]:
		var a := deg_to_rad(ph)
		prof.append(Vector2(xt + sr * sin(a), yt - sr + sr * cos(a)))
		vs.append(1.0 + ph / 90.0)
	# außen: Flanke mit Bauch, Felgenschutz (bei flachen Reifen deutlich), Wulst
	var outer := [Vector2(h + bul * 0.45, yt - sr * 1.15), Vector2(h + bul, rb + sh * 0.5), Vector2(h + bul * 0.8, rb + sh * 0.3)]
	if sh > 0.03:
		outer.append_array([Vector2(h + bul + 0.0032, rb + minf(0.016, sh * 0.32)), Vector2(h + bul + 0.003, rb + minf(0.01, sh * 0.2)),
			Vector2(h + 0.0015, rb + 0.005)])
	outer.append(Vector2(h - 0.006, rb))
	for p in outer:
		prof.append(p)
		vs.append(float(sidev.call((p as Vector2).y)))
	var wb := {}
	_wrev(wb, "tire", prof, 44, vs)
	var m: ArrayMesh = _wcommit(wb, ["tire"], side < 0, true)[0]
	_wput(key, m)
	return m


## Reifen-Material (ein Shader für alle Autos): Gummi fast schwarz, Profil auf der Lauffläche (außen große Schulterblöcke,
## Mitte schräge Lamellen, innen schmalere Blöcke), auf der Außenflanke ein Band aus erhabenen, unlesbaren Zeichen (zwei
## Gruppen je Umlauf, keine Marke) und feine Rillen am Felgenschutz. Feine Muster blenden in der Ferne aus (kein Flimmern).
static var _tire_m: ShaderMaterial


static func tire_mat() -> ShaderMaterial:
	if _tire_m:
		return _tire_m
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// Reifen (car_builder.tire_mat): u am Umfang, v quer (Lauffläche -1..1, Schultern bis ±2, Flanke 2..3 außen)
uniform vec3 rubber : source_color = vec3(0.036, 0.036, 0.038);
uniform float pitches = 68.0;
float h1(float n) { return fract(sin(n * 127.1 + 3.7) * 43758.5453); }
float glyph(float id, vec2 p) {
	if (p.x < 0.16 || p.x > 0.84 || p.y < 0.08 || p.y > 0.92) return 0.0;
	vec2 g = floor(vec2((p.x - 0.16) / 0.68 * 3.0, (p.y - 0.08) / 0.84 * 5.0));
	float on = step(0.45, h1(id * 17.0 + g.x * 3.0 + g.y * 11.0));
	// senkrechte Striche öfter: wirkt wie Großbuchstaben
	on = max(on, step(0.62, h1(id * 5.0 + g.x)) * step(0.5, abs(g.x - 1.0)));
	return on;
}
void fragment() {
	float v = UV.y;
	float av = abs(v);
	float u = UV.x;
	vec3 col = rubber;
	float rough = 0.82;
	float fade = 1.0 - smoothstep(0.25, 0.7, fwidth(u * pitches));
	if (av < 2.0) {
		float g = 0.0;
		if (v > 0.42) {
			float q = fract(u * pitches + (v - 0.42) * 0.6);
			g = step(q, 0.17) * smoothstep(0.42, 0.56, v);
		} else if (v < -0.42) {
			float q = fract(u * pitches * 1.25 - (v + 0.42) * 0.8 + 0.5);
			g = step(q, 0.13) * smoothstep(-0.42, -0.56, v);
		} else {
			float q = fract(u * pitches * 0.5 + v * 1.1);
			g = step(q, 0.045) * 0.85;
		}
		g *= (1.0 - smoothstep(1.45, 1.9, av)) * fade;
		col = mix(col, rubber * 0.3, g);
		rough = mix(0.78, 0.96, g) - 0.07 * (1.0 - smoothstep(0.0, 1.0, av)) * (1.0 - g);
	} else {
		float t = av - 2.0;
		col = rubber * 1.1;
		rough = 0.7;
		if (v > 0.0) {
			float w = fract(u * 2.0);
			float big = step(0.3, t) * step(t, 0.54) * step(0.06, w) * step(w, 0.27);
			float small = step(0.6, t) * step(t, 0.7) * step(0.38, w) * step(w, 0.5);
			float lg = 0.0;
			if (big > 0.0) {
				float gu = u * 170.0;
				lg = glyph(floor(gu), vec2(fract(gu), (t - 0.3) / 0.24));
			} else if (small > 0.0) {
				float gu = u * 330.0;
				lg = glyph(floor(gu) + 91.0, vec2(fract(gu), (t - 0.6) / 0.1));
			}
			lg *= 1.0 - smoothstep(0.3, 0.8, fwidth(u * 170.0));
			col = mix(col, vec3(0.07, 0.07, 0.074), lg * 0.75);
			rough = mix(rough, 0.56, lg);
			// Felgenschutz: feine Rillen
			float ring = step(0.82, t) * step(0.5, fract(t * 60.0));
			rough = mix(rough, 0.6, ring * 0.6);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.32;
}
"""
	_tire_m = ShaderMaterial.new()
	_tire_m.shader = sh
	_tire_m.set_meta("lod_color", Color(0.04, 0.04, 0.042))
	return _tire_m


## Felge mit Bremsscheibe (rechtes Rad bzw. side < 0 gespiegelt): [Mesh, Rollen je Fläche]. rim aus rim_spec, tw
## Reifenbreite (Modellmaße), big: große gelochte Bremse.
static func _wheel_mesh(rim: Dictionary, tw: float, big: bool, side: int) -> Array:
	var key := "wheel_%s_%d_%d_%.4f_%.4f_%.3f_%d_%.3f" % [rim["style"], rim["spokes"], rim["lugs"], rim["radius"], tw, rim["mu"], int(big),
		float(rim.get("wide", 0.0))]
	var hit = _wget(key)
	if hit == null:
		var wb := {}
		_rim_build(wb, rim, tw)
		_brake_build(wb, rim, tw, big)
		hit = [_wcommit(wb, WHEEL_ROLES, false), _wcommit(wb, WHEEL_ROLES, true)]
		_wput(key, hit)
	return hit[0 if side > 0 else 1]


## Maße, die Felge, Bremse und Sattel teilen (Modellmaße, rechtes Rad): Horn vorn x_lip, Anlage der Nabe x_mount
## (Einpresstiefe ~40 mm; breite Felgen haben weniger), Felgenbett innen rb, Bremsscheibe disc_r und ihre Vorderseite x_rf
static func _wheel_dims(rim: Dictionary, tw: float) -> Dictionary:
	var rr: float = rim["radius"]
	var mu: float = rim["mu"]
	var fl := clampf(0.05 * rr, 0.008, 0.013)
	var rb := rr - fl - 0.004
	var x_mount := (0.04 - 0.6 * float(rim.get("wide", 0.0))) * mu
	return {"rr": rr, "mu": mu, "h": tw / 2.0, "x_lip": tw / 2.0 + 0.004, "fl": fl, "rb": rb, "x_mount": x_mount,
		"x_rf": x_mount - 0.033 * mu}


## Felge je Bauart nach echten Vorbildern (ohne Marken): Horn und Bett, bei mehrteiligen ein poliertes Stufenbett mit
## Nieten, der Stern (konkave Speichen, die vorn am Horn ansetzen und zur Nabe hin tiefer liegen), Nabe mit Radmuttern in
## dunklen Bohrungen, Nabendeckel, Ventil, dunkle Rückwand.
static func _rim_build(wb: Dictionary, rim: Dictionary, tw: float) -> void:
	var D := _wheel_dims(rim, tw)
	var rr: float = D["rr"]
	var mu: float = D["mu"]
	var h: float = D["h"]
	var x_lip: float = D["x_lip"]
	var fl: float = D["fl"]
	var x_mount: float = D["x_mount"]
	var n: int = maxi(int(rim["spokes"]), 1)
	var style: String = str(rim.get("style", "std"))
	var lugs: int = int(rim.get("lugs", 5))
	var seg := 48
	# Grundmaße je Bauart: dish Tiefe des Stufenbetts (Anteil der halben Reifenbreite), rc Außenkante des Sterns (Anteil
	# des Felgenradius, nur mit Stufenbett), cvk Konkave (Anteil des Platzes vor der Nabe), pex Form der Konkave (<1:
	# vorn steil, zur Nabe flach), rivets Nieten im Stufenbett
	var dish := 0.0
	var rc := 0.88
	var cvk := 0.45
	var pex := 0.8
	var rivets := 0
	var over_lip := style in ["te", "ten"]  # Speichen laufen bis über das Horn
	match style:
		"mesh":
			dish = 0.2
			rc = 0.86
			cvk = 0.3
			rivets = n * 2
		"dish":
			dish = 0.46
			rc = 0.8
			cvk = 0.1
			pex = 1.0
			rivets = 36
		"3pc":
			dish = 0.24
			rc = 0.86
			cvk = 0.3
			rivets = 30
		"thin":
			dish = 0.1
			rc = 0.91
			cvk = 0.3
			rivets = 20
		"cup":
			dish = 0.08
			rc = 0.92
			cvk = 0.35
		"concave":
			cvk = 0.95
			pex = 0.6
		"te":
			cvk = 0.45
			pex = 1.0
		"ten":
			cvk = 0.6
			pex = 0.9
		"split", "sickle":
			cvk = 0.65
			pex = 0.7
		"y", "center":
			cvk = 0.55
		"rally":
			cvk = 0.12
			pex = 1.0
		"clover":
			cvk = 0.12
			pex = 1.0
		"turbine":
			cvk = 0.1
			pex = 1.0
		"wire":
			cvk = 0.7
			pex = 1.0
		"steel", "holes", "cap", "aero":
			cvk = 0.35
			pex = 1.0
		"cross":
			cvk = 0.5
	var room := x_lip - x_mount - 0.02
	dish = minf(dish * h, room * 0.55)
	var stepped := dish > 0.0
	# Außenkante des Sterns mindestens 1,2 cm unter dem Horn: sonst kippt der Konus des Stufenbetts nach hinten und
	# fehlt als schmaler Streifen (Cup-Stern, Mehrspeichen bei kleinen Felgen)
	var r_c := minf(rc * rr, rr - fl - 0.012) if stepped else rr - fl - 0.004
	var x_out := x_lip - dish - 0.003
	if over_lip:
		x_out = x_lip + 0.0012
	var cv := cvk * maxf(x_out - x_mount - 0.032, 0.0)
	var rh := maxf(0.068 * mu, 0.25 * rr)  # Nabe (Mitte des Sterns)
	if style == "rally":
		rh = maxf(rh, 0.34 * rr)
	var r_end: float = r_c - 0.014 if stepped else float(D["rb"]) + 0.004
	if over_lip:
		r_end = rr - 0.004
	var x_root := x_out - cv
	var xf := func(r: float) -> float:
		var f := clampf((r_end - r) / maxf(r_end - rh, 0.01), 0.0, 1.0)
		return x_out - cv * pow(f, pex)
	var x_hub := x_root + 0.003  # Vorderseite der Nabe
	var r0 := rh - 0.006
	var th := 0.017
	var ch := 0.0035

	# Horn: abgerundete Kante vorn, bei mehrteiligen ein poliertes Stufenbett (Konus nach hinten bis zum Stern)
	var lip := [Vector2(x_lip - 0.009, rr - 0.0015), Vector2(x_lip - 0.0025, rr + 0.0004), Vector2(x_lip + 0.0006, rr - 0.003),
		Vector2(x_lip + 0.001, rr - fl * 0.55), Vector2(x_lip - 0.0004, rr - fl)]
	if stepped:
		lip.append_array([Vector2(x_lip - 0.003, rr - fl - 0.0025), Vector2(x_lip - dish + 0.003, r_c + 0.006),
			Vector2(x_lip - dish + 0.0005, r_c + 0.0015), Vector2(x_lip - dish + 0.0005, r_c - 0.002)])
	else:
		lip.append_array([Vector2(x_lip - 0.004, rr - fl - 0.003), Vector2(x_lip - 0.012, D["rb"])])
	_wrev(wb, "lip", lip, seg)
	# Felgenbett innen (zwischen den Speichen sichtbar) mit Tiefbett in der Mitte, dahinter eine dunkle Rückwand
	var rb: float = D["rb"]
	var xb: float = (x_lip - dish - 0.004) if stepped else (x_out - 0.012 if not over_lip else x_lip - 0.012)
	_wrev(wb, "barrel", [Vector2(xb, rb), Vector2(h * 0.05, rb), Vector2(-h * 0.08, rb - 0.012), Vector2(-h * 0.55, rb - 0.012),
		Vector2(-h * 0.66, rb), Vector2(-h + 0.012, rb)], 40)
	_wrev(wb, "dark", [Vector2(-h + 0.014, rb), Vector2(-h + 0.014, 0.0)], 32)
	if stepped:
		# Außenring des Sterns, darauf die Nieten bzw. Schrauben der mehrteiligen Felge
		var xr := x_lip - dish - 0.0012
		_wrev(wb, "face", [Vector2(xr - 0.004, r_c + 0.001), Vector2(xr, r_c - 0.001), Vector2(xr, r_c - 0.022), Vector2(xr - 0.006, r_c - 0.026)], seg)
		for k in rivets:
			var a := TAU * (k + 0.5) / rivets
			_wdisc(wb, "chrome", Vector3(xr, cos(a) * (r_c - 0.011), sin(a) * (r_c - 0.011)), 0.0036 * mu, 6, Vector3.RIGHT, 0.0024 * mu)

	# Stern je Bauart
	match style:
		"std":
			var w0 := rr * (0.2 if n <= 5 else (0.135 if n <= 7 else 0.1))
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, w0, w0 * 1.28, xf, th, ch), 0.003)
		"te", "ten":
			# geschmiedet: flache Speichen bis über das Horn, schmale Fase; Sechs breit, Zehn schlank
			var w0 := rr * (0.15 if style == "te" else 0.07)
			var w1 := rr * (0.25 if style == "te" else 0.095)
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, w0, w1, xf, th, 0.0025, 6), 0.0 if style == "te" else 0.0015, true)
		"split":
			# Doppelspeichen: je zwei schlanke Speichen, die zur Nabe hin zusammenlaufen
			for k in n:
				for e in [-1.0, 1.0]:
					_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.062, rr * 0.07, xf, th, ch, 5, 0.0, 1.4, e * rr * 0.03, e * rr * 0.085), 0.002)
		"y", "center":
			# Y: kräftiger Stamm, außen zwei Äste zum Nachbarn hin
			var da := TAU / n * 0.24
			for k in n:
				var a := TAU * k / n
				_wspoke(wb, "face", _wst(a, r0, rr * 0.56, rr * 0.17, rr * 0.13, xf, th, ch, 4), 0.003)
				for e in [-1.0, 1.0]:
					_wspoke(wb, "face", _wst(a, rr * 0.5, r_end, rr * 0.075, rr * 0.07, xf, th, ch, 5, e * da, 1.0), 0.002)
		"concave":
			if n >= 10:
				# tief konkave Zehnspeichen, paarweise
				for k in n / 2:
					for e in [-1.0, 1.0]:
						_wspoke(wb, "face", _wst(TAU * k / (n / 2), r0, r_end, rr * 0.06, rr * 0.068, xf, th, ch, 6, 0.0, 1.4, e * rr * 0.028, e * rr * 0.1), 0.002)
			else:
				for k in n:
					_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.16, rr * 0.2, xf, th, ch, 6), 0.004)
		"sickle":
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.075, rr * 0.06, xf, th, ch, 7, 0.55), 0.002)
		"thin":
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.042, rr * 0.052, xf, 0.014, 0.003), 0.0015)
		"mesh", "cross":
			# Kreuzgitter: zwei Lagen schräger Speichen zum übernächsten Nachbarn, sie kreuzen sich auf halbem Weg (Rauten)
			var da := TAU / n
			var ws := rr * (0.04 if style == "mesh" else 0.068)
			var rs0 := rh + (0.004 if style == "mesh" else -0.004)
			for k in n:
				var a := TAU * k / n
				# gerade Sehnen: vier Schnitte reichen (30 Speichen beim Kreuzgitter, Dreiecke sparen)
				_wspoke(wb, "face", _wst(a, rs0, r_end, ws, ws * 1.05, xf, 0.012, 0.002, 4, da, 1.0, 0.0, 0.0, 1.2, 0.0, Callable(), true), 0.004)
				_wspoke(wb, "face", _wst(a, rs0, r_end, ws, ws * 1.05, xf, 0.012, 0.002, 4, -da, 1.0, 0.0, 0.0, 1.2, -0.004, Callable(), true), 0.004)
		"3pc":
			# mehrteilig mit Y-Gitter: n/2 Stämme, die sich außen teilen und am Ring mit dem Nachbarn treffen
			var m := maxi(n / 2, 3)
			var da := TAU / m * 0.5
			for k in m:
				var a := TAU * k / m
				_wspoke(wb, "face", _wst(a, r0, rr * 0.6, rr * 0.13, rr * 0.085, xf, th, ch, 4), 0.003)
				for e in [-1.0, 1.0]:
					_wspoke(wb, "face", _wst(a, rr * 0.55, r_end, rr * 0.055, rr * 0.05, xf, 0.014, 0.0025, 5, e * da, 1.0), 0.002)
		"dish":
			# Tiefbett: Stern tief im polierten Bett, Speichen nach außen schmaler
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.15, rr * 0.11, xf, th, ch), 0.003)
		"cup":
			# Cup: fünf breite Speichen mit Grat (V), poliertes Horn
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.17, rr * 0.25, xf, th, 0.003), 0.012)
		"rally":
			# Rallye: breite flache Speichen, kleine Fenster, große Mitte
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end, rr * 0.27, rr * 0.34, xf, th, 0.003), 0.0)
		"clover":
			# Fünfblatt: polierte Blätter, die zum Rand hin breit werden, dazwischen schwarz eloxiert
			var wend := 0.55 * TAU * r_end / n
			var wst := 0.6 * TAU * rh / n
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, r0, r_end - 0.006, wst, wend, xf, th, 0.004, 6, 0.0, 1.4, 0.0, 0.0, 1.05, 0.0,
					func(f: float) -> float: return lerpf(wst, wend, pow(f, 0.75))), 0.005)
			_wrev(wb, "dark", [Vector2(x_out - 0.012, r_end), Vector2(x_root - 0.008, rh)], seg)
			_wrev(wb, "face", [Vector2(x_out - 0.005, r_end + 0.002), Vector2(x_out, r_end - 0.002), Vector2(x_out, r_end - 0.012),
				Vector2(x_out - 0.006, r_end - 0.016)], seg)
		"turbine":
			# Turbofächer: viele schmale, gebogene Schaufeln zwischen zwei Ringen
			for k in n:
				_wspoke(wb, "face", _wst(TAU * k / n, rh + 0.006, r_end - 0.01, rr * 0.05, rr * 0.07, xf, 0.01, 0.002, 6, 0.6, 1.2), 0.002)
			_wrev(wb, "face", [Vector2(x_out - 0.006, r_end + 0.002), Vector2(x_out, r_end - 0.002), Vector2(x_out, r_end - 0.018),
				Vector2(x_out - 0.008, r_end - 0.022)], seg)
			_wrev(wb, "face", [Vector2(x_root - 0.008, rh + 0.024), Vector2(x_root + 0.001, rh + 0.02), Vector2(x_root + 0.001, rh - 0.004)], seg)
		"wire":
			# Drahtspeichen: zwei Lagen dünner, gekreuzter Speichen, Nabe mit Flügelmutter
			for k in n * 2:
				var a := TAU * k / (n * 2)
				var odd := k % 2 == 1
				_wspoke(wb, "chrome", _wst(a, rh * 0.85, r_end, 0.0045, 0.0045, xf, 0.0045, 0.0012, 3, 0.5 if odd else -0.5, 1.0, 0.0, 0.0, 1.0,
					-0.006 if odd else 0.0))
		"steel", "holes", "cap", "aero":
			_disc_face(wb, style, n, rr, r_end, rh, x_out, x_root, mu, seg)

	# Nabe: Sockel des Sterns mit Radmuttern in dunklen Bohrungen und Nabendeckel (Zentralverschluss: große Mutter;
	# Radkappe und Aero-Scheibe decken die Mitte selbst ab)
	if not style in ["cap"]:
		_wrev(wb, "face", [Vector2(x_mount, rh + 0.002), Vector2(x_hub - 0.004, rh + 0.002), Vector2(x_hub, rh - 0.002),
			Vector2(x_hub, 0.034 * mu), Vector2(x_hub - 0.003, 0.031 * mu)], seg)
	if style == "center":
		_wnut(wb, "accent", 0.0, 0.0, x_hub - 0.004, x_hub + 0.02 * mu, 0.042 * mu)
		_wrev(wb, "chrome", [Vector2(x_hub + 0.02 * mu, 0.016 * mu), Vector2(x_hub + 0.026 * mu, 0.0)], 12)
	elif style == "wire":
		_wnut(wb, "chrome", 0.0, 0.0, x_hub - 0.004, x_hub + 0.016 * mu, 0.03 * mu, 8)
		for e in [-1.0, 1.0]:
			_wspoke(wb, "chrome", _wst(PI / 2.0 + (0.0 if e > 0 else PI), 0.02 * mu, 0.07 * mu, 0.014 * mu, 0.01 * mu,
				func(_r: float) -> float: return x_hub + 0.014 * mu, 0.008, 0.002, 2), 0.002)
	elif style != "cap":
		var pcd := (0.05 if lugs == 4 else 0.0572) * mu
		var xn := x_hub
		if style == "aero":
			xn = x_out - 0.004
		for k in lugs:
			var a := TAU * k / lugs + PI / lugs
			var y := cos(a) * pcd
			var z := sin(a) * pcd
			_wdisc(wb, "dark", Vector3(xn + 0.0009, y, z), 0.0135 * mu, 10, Vector3.RIGHT)
			_wnut(wb, "chrome", y, z, xn - 0.004, xn + 0.009 * mu, 0.0094 * mu)
		# Nabendeckel: dunkle Kuppe mit hellem Ring und glattem Mittelfeld (ohne Zeichen)
		var rcap := 0.03 * mu
		_wrev(wb, "chrome", [Vector2(xn - 0.002, rcap + 0.0025), Vector2(xn + 0.003, rcap + 0.0022), Vector2(xn + 0.0042, rcap)], 24)
		_wrev(wb, "dark", [Vector2(xn + 0.0042, rcap), Vector2(xn + 0.0068, rcap * 0.78), Vector2(xn + 0.0082, rcap * 0.45), Vector2(xn + 0.0086, 0.0)], 24)
		_wdisc(wb, "face", Vector3(xn + 0.0089, 0, 0), rcap * 0.42, 16, Vector3.RIGHT)
	# Ventil: im Bett zwischen zwei Speichen (mehrteilig: in der Wand des Stufenbetts), schräg nach vorn
	if not style in ["cap", "aero"]:
		var va := PI / n + 0.04
		var vr: float = ((r_c + rr - fl) / 2.0 - 0.004) if stepped else D["rb"] - 0.003
		var vx: float = (x_lip - dish * 0.55) if stepped else (x_out - 0.012 if not over_lip else x_lip - 0.016)
		var base := Vector3(vx, cos(va) * vr, sin(va) * vr)
		var radial := Vector3(0.0, cos(va), sin(va))
		var tg := Vector3(0.0, -sin(va), cos(va))
		var vd := (Vector3.RIGHT * 0.95 - radial * 0.32).normalized()
		var tip := base + vd * 0.018
		_wspoke(wb, "dark", [[base, tg, 0.0065, 0.0065, 0.0065, 0.0016], [tip, tg, 0.006, 0.006, 0.006, 0.0016]])
		_wdisc(wb, "chrome", tip + vd * 0.0035, 0.0034, 8, vd, 0.002)


## Geschlossene Scheiben (Stahlfelge, Lochfelge, Radkappe, Aero): Fläche als Drehkörper, Löcher und Schlitze als dunkle
## Flächen davor
static func _disc_face(wb: Dictionary, style: String, n: int, rr: float, r_end: float, rh: float, x_out: float, x_root: float, mu: float, seg: int) -> void:
	match style:
		"steel":
			# gepresste Stahlscheibe: flacher Außenring, Mulde mit Lüftungslöchern, erhabener Hut mit den Radmuttern
			_wrev(wb, "face", [Vector2(x_out - 0.004, r_end + 0.003), Vector2(x_out, r_end - 0.004), Vector2(x_out - 0.002, rr * 0.78),
				Vector2(x_out - 0.014, rr * 0.7), Vector2(x_out - 0.014, rr * 0.56), Vector2(x_root - 0.002, rh + 0.012),
				Vector2(x_root + 0.002, rh + 0.004)], seg)
			for k in n:
				var a := TAU * k / n + PI / n
				_wdisc(wb, "dark", Vector3(x_out - 0.0132, cos(a) * rr * 0.63, sin(a) * rr * 0.63), rr * 0.07, 14, Vector3.RIGHT)
		"holes":
			# Lochfelge: leicht gewölbte Scheibe mit großen runden Löchern, jedes mit heller Fase
			_wrev(wb, "face", [Vector2(x_out - 0.004, r_end + 0.003), Vector2(x_out, r_end - 0.004), Vector2(x_out - 0.004, rr * 0.5),
				Vector2(x_root, rh + 0.004)], seg)
			var hr := rr * (0.17 if n <= 5 else 0.115)
			for k in n:
				var a := TAU * k / n + PI / n
				var r := rr * 0.6
				var xs: float = lerpf(x_out - 0.004, x_out, (r - rr * 0.5) / (r_end - rr * 0.5)) + 0.0006
				var c := Vector3(xs, cos(a) * r, sin(a) * r)
				_wdisc(wb, "chrome", c, hr * 1.12, 18, Vector3.RIGHT)
				_wdisc(wb, "dark", c + Vector3(0.0007, 0, 0), hr, 18, Vector3.RIGHT)
		"cap":
			# Radkappe aus Kunststoff: gewölbt, erhabener Ring, Schlitze, Mitte mit glattem Emblem
			_wrev(wb, "face", [Vector2(x_out - 0.004, r_end + 0.003), Vector2(x_out + 0.002, r_end - 0.006), Vector2(x_out + 0.008, rr * 0.82),
				Vector2(x_out + 0.009, rr * 0.76), Vector2(x_out + 0.004, rr * 0.7), Vector2(x_out + 0.004, rr * 0.36),
				Vector2(x_out + 0.012, rr * 0.3), Vector2(x_out + 0.014, rr * 0.12), Vector2(x_out + 0.0145, 0.0)], seg)
			for k in n:
				var a := TAU * k / n
				var c := Vector3(x_out + 0.0045, cos(a) * rr * 0.53, sin(a) * rr * 0.53)
				var rad := Vector3(0, cos(a), sin(a))
				var tg := Vector3(0, -sin(a), cos(a))
				_wquad(wb, "dark", c - rad * rr * 0.12 - tg * 0.006, c + rad * rr * 0.12 - tg * 0.006, c + rad * rr * 0.12 + tg * 0.006,
					c - rad * rr * 0.12 + tg * 0.006, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)
			_wdisc(wb, "chrome", Vector3(x_out + 0.0148, 0, 0), rr * 0.09, 16, Vector3.RIGHT)
		"aero":
			# Aero-Scheibe: glatt und geschlossen, Kühlschlitze am Rand
			_wrev(wb, "face", [Vector2(x_out - 0.004, r_end + 0.003), Vector2(x_out, r_end - 0.004), Vector2(x_out - 0.002, rr * 0.5),
				Vector2(x_out - 0.004, rh + 0.004), Vector2(x_out - 0.0046, rh - 0.004)], seg)
			for k in n * 3:
				var a := TAU * k / (n * 3)
				var c := Vector3(x_out + 0.0006, cos(a) * rr * 0.77, sin(a) * rr * 0.77)
				var rad := Vector3(0, cos(a), sin(a))
				var tg := Vector3(0, -sin(a), cos(a))
				_wquad(wb, "dark", c - rad * rr * 0.09 - tg * 0.005, c + rad * rr * 0.09 - tg * 0.005, c + rad * rr * 0.09 + tg * 0.005,
					c - rad * rr * 0.09 + tg * 0.005, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT, Vector3.RIGHT)


## Bremse in der Felge: belüftete Scheibe (Reibring mit dunklem Rand, große Bremse gelocht und mit Topf-Nieten), Topf bis
## zur Nabe. Echte Größen: 280 bis 380 mm, kleine Felgen begrenzen.
static func _brake_build(wb: Dictionary, rim: Dictionary, tw: float, big: bool) -> void:
	var D := _wheel_dims(rim, tw)
	var mu: float = D["mu"]
	var dr := _disc_r(rim, tw, big)
	var x_rf: float = D["x_rf"]
	var thk := 0.026 * mu
	var ri := dr * 0.6
	var rhat := minf(0.078 * mu, dr * 0.55)
	_wrev(wb, "rotor", [Vector2(x_rf - thk, dr), Vector2(x_rf - 0.002, dr), Vector2(x_rf, dr - 0.002), Vector2(x_rf, ri + 0.004)], 40)
	_wrev(wb, "dark", [Vector2(x_rf - thk * 0.8, dr + 0.0005), Vector2(x_rf - thk * 0.2, dr + 0.0005)], 40)  # Kühlkanäle im Rand
	_wrev(wb, "hat", [Vector2(x_rf + 0.0006, ri + 0.004), Vector2(x_rf + 0.0006, rhat + 0.003), Vector2(x_rf + 0.003, rhat),
		Vector2(D["x_mount"] - 0.002, rhat), Vector2(D["x_mount"], rhat - 0.004), Vector2(D["x_mount"], 0.03 * mu)], 32)
	if big:
		# gelocht: drei versetzte Reihen, Topf mit Nieten (schwimmend gelagert)
		for row in 3:
			var r := lerpf(ri + 0.012 * mu, dr - 0.012 * mu, row / 2.0)
			for k in 12:
				var a := TAU * (k + row / 3.0) / 12.0
				_wdisc(wb, "dark", Vector3(x_rf + 0.0006, cos(a) * r, sin(a) * r), 0.0042 * mu, 6, Vector3.RIGHT)
		for k in 10:
			var a := TAU * k / 10.0
			_wdisc(wb, "chrome", Vector3(x_rf + 0.0012, cos(a) * (ri + 0.002), sin(a) * (ri + 0.002)), 0.0045 * mu, 6, Vector3.RIGHT, 0.002 * mu)


## Radius der Bremsscheibe (Modellmaße): ab Werk ~300 mm, groß ~350 mm, höchstens so groß, dass der Sattel ins Bett passt
static func _disc_r(rim: Dictionary, tw: float, big: bool) -> float:
	var D := _wheel_dims(rim, tw)
	var mu: float = D["mu"]
	return minf((0.176 if big else 0.15) * mu, float(D["rb"]) - 0.03 * mu)


## Bremssattel (steht still am Achsschenkel, oben hinten über der Scheibe): gebogener Block mit runden Enden und Fase,
## zwei Schrauben vorn. [Mesh, Rollen] wie _wheel_mesh.
static func _caliper_mesh(rim: Dictionary, tw: float, big: bool, side: int) -> Array:
	var key := "caliper_%.4f_%.4f_%.3f_%d_%.3f" % [rim["radius"], tw, rim["mu"], int(big), float(rim.get("wide", 0.0))]
	var hit = _wget(key)
	if hit == null:
		var D := _wheel_dims(rim, tw)
		var mu: float = D["mu"]
		var dr := _disc_r(rim, tw, big)
		var x_rf: float = D["x_rf"]
		var ro := dr + 0.013 * mu
		var ri := dr - (0.048 if big else 0.04) * mu
		var xo := x_rf + 0.022 * mu
		var xi := x_rf - 0.05 * mu
		var ch := 0.006 * mu
		var span := (0.24 if big else 0.17) * mu / dr
		var ca := 0.75
		var K := 10
		var wb := {}
		var secs := []
		var mids := []
		for k in K + 1:
			var f := float(k) / K
			var a := ca + (f - 0.5) * span
			var e := pow(1.0 - pow(absf(2.0 * f - 1.0), 3.0), 1.0 / 3.0)  # runde Enden
			var hh := (ro - ri) / 2.0 * (0.4 + 0.6 * e)
			var rm := (ro + ri) / 2.0
			var cs := Vector2(cos(a), sin(a))
			var P := func(x: float, r: float) -> Vector3: return Vector3(x, cs.x * r, cs.y * r)
			secs.append([P.call(xi, rm + hh), P.call(xo - ch, rm + hh), P.call(xo, rm + hh - ch), P.call(xo, rm - hh + ch),
				P.call(xo - ch, rm - hh), P.call(xi, rm - hh)])
			mids.append(P.call((xi + xo) / 2.0, rm))
		for k in K:
			for j in 5:
				var a: Vector3 = secs[k][j]
				var b: Vector3 = secs[k][j + 1]
				var c: Vector3 = secs[k + 1][j + 1]
				var d: Vector3 = secs[k + 1][j]
				var nn := (c - a).cross(d - b).normalized()
				if nn.dot((a + b + c + d) / 4.0 - ((mids[k] as Vector3) + (mids[k + 1] as Vector3)) / 2.0) < 0.0:
					nn = -nn
				_wquad(wb, "caliper", a, b, c, d, nn, nn, nn, nn, nn)
		for end in [0, K]:
			var sec: Array = secs[end]
			var tg: Vector3 = ((secs[mini(end + 1, K)][2] as Vector3) - (secs[maxi(end - 1, 0)][2] as Vector3)).normalized() * (-1.0 if end == 0 else 1.0)
			for j in range(1, 5):
				_wtri(wb, "caliper", sec[0], sec[j], sec[j + 1], tg, tg, tg, tg)
		for f: float in [0.2, 0.8]:
			var a := ca + (f - 0.5) * span
			var rm := (ro + ri) / 2.0 + (ro - ri) * 0.18
			_wdisc(wb, "chrome", Vector3(xo + 0.0004, cos(a) * rm, sin(a) * rm), 0.0062 * mu, 6, Vector3.RIGHT, 0.0025 * mu)
		hit = [_wcommit(wb, ["caliper", "chrome"], false), _wcommit(wb, ["caliper", "chrome"], true)]
		_wput(key, hit)
	return hit[0 if side > 0 else 1]


## Unschärfescheibe für schnell drehende Räder: flacher Ring (Vorderseite +X) in Vertexfarben. Innen und am Horn
## fast durchsichtig, im Speichenbereich deckend in der Mischfarbe aus Speichen und dunklem Felgenbett (je nachdem,
## wie viel Fläche die Speichen bedecken), mit feinen konzentrischen Streifen wie auf echten Aufnahmen.
static func _blur_mesh(rr: float, c: Color, style: String) -> ArrayMesh:
	var key := "blur_%.4f_%s_%s" % [rr, c.to_html(), style]
	var hit = _wget(key)
	if hit != null:
		return hit
	var cov: float = {"steel": 0.95, "aero": 0.95, "cap": 0.95, "holes": 0.85, "clover": 0.8, "wire": 0.35, "thin": 0.5,
		"mesh": 0.5, "cross": 0.55, "rally": 0.7, "te": 0.55, "dish": 0.4, "ten": 0.4, "concave": 0.45, "cup": 0.55, "turbine": 0.6,
		"3pc": 0.45}.get(style, 0.45)
	var mid := Color(0.05, 0.05, 0.055).lerp(c, cov)
	var rings := [[0.1, 0.0], [0.15, 0.45], [0.24, 0.55], [0.32, 0.93], [0.45, 0.97], [0.58, 0.95], [0.7, 0.97], [0.82, 0.95], [0.92, 0.85], [0.985, 0.0]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 40
	var col := []
	for i in rings.size():
		var cc := mid.lightened(0.07) if i % 2 == 0 else mid.darkened(0.07)
		cc.a = rings[i][1]
		col.append(cc)
	for i in rings.size() - 1:
		var r0: float = rings[i][0] * rr
		var r1: float = rings[i + 1][0] * rr
		for k in seg:
			var a0 := TAU * k / seg
			var a1 := TAU * (k + 1) / seg
			# Reihenfolge so, dass die Vorderseite nach +X zeigt (Godot: im Uhrzeigersinn von vorn)
			for v in [[r0, a0, i], [r1, a1, i + 1], [r1, a0, i + 1], [r0, a0, i], [r0, a1, i], [r1, a1, i + 1]]:
				st.set_color(col[v[2]])
				st.set_normal(Vector3.RIGHT)
				st.add_vertex(Vector3(0.0, v[0] * cos(v[1]), v[0] * sin(v[1])))
	st.index()
	var m := st.commit()
	_wput(key, m)
	return m


## Felge eines Autos mit Tuning: Bauart, Speichen, Farbe und Radmuttern ("Serie" = Werksfelge des Autos), Größe in Zoll
## (Kategorie Zoll: "Standard" = Werk + Aufschlag der Felge, sonst fest 13" bis 24"; kleiner als zwei Zoll unter Werk
## passt nicht über die Bremse, min_in), Reifen (wird mit der Felge etwas breiter, "Breit" legt 30 mm drauf) und Rad:
## der Reifen behält seinen Außendurchmesser, solange mindestens ein 20er-Querschnitt bzw. 4 cm Flanke bleibt (bis fit_in);
## darüber wächst das ganze Rad (grow, build hebt die Karosserie und weitet die Radläufe, wheel_fit). radius und mu in
## Modellmaßen (das Rad wird auf wheel_r skaliert), tire als Text (z. B. "225/40 R18").
## Bis 2.36 galt die Größe relativ (-1 … +4 Zoll zur Standardgröße) und höchstens so groß, dass 4,5 cm Flanke blieben.
static func rim_spec(car_id: String, cfg: Dictionary) -> Dictionary:
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var wr := wheel_r(S)
	var opt := Catalog.part_of(cfg, "rims")
	var fac: Array = Catalog.FACTORY_RIMS.get(car_id, ["std", 7, Color(0.62, 0.63, 0.66), 16, 5])
	var r := opt.duplicate()
	if int(cfg.get("rims", 0)) == 0:
		r["style"] = fac[0]
		r["spokes"] = fac[1]
		r["color"] = fac[2]
	r["lugs"] = fac[4]
	r["polish"] = str(r["style"]) in POLISHED_LIP
	var fac_in: int = fac[3]
	var tw0: float = S.get("tire_w", 0.24)
	var sp := Catalog.part_of(cfg, "spur")
	var wide: float = sp.get("wide", 0.0)
	var min_in := maxi(13, fac_in - 2)
	var fit_in := min_in
	for i in range(min_in, 25):
		if i * 0.0127 + _min_side(_tire_w(tw0, fac_in, i, 0.0)) <= wr + 0.0005:
			fit_in = i
	var std_in := clampi(fac_in + int(opt.get("plus", 0)), min_in, fit_in)
	var so := Catalog.part_of(cfg, "rimsize")
	var inch := std_in
	if so.has("abs"):
		inch = clampi(int(so["abs"]), min_in, 24)
	elif int(so.get("inch", 0)) != 0:
		inch = clampi(std_in + int(so["inch"]), min_in, fit_in)  # alter Spielstand (bis 2.36): relativ zur Standardgröße
	var tw := _tire_w(tw0, fac_in, inch, wide)
	var side := maxf(wr - inch * 0.0127, _min_side(tw - wide))
	var R := inch * 0.0127 + side
	r["inch"] = inch
	r["std_in"] = std_in
	r["min_in"] = min_in
	r["fit_in"] = fit_in
	r["max_in"] = 24
	r["wheel_r"] = R
	r["grow"] = R - wr
	r["tire_w"] = tw
	r["spacer"] = float(sp.get("spacer", 0.0))
	r["wide"] = wide
	r["radius"] = inch * 0.0127 * WHEEL_R / R
	r["mu"] = WHEEL_R / R
	var width := roundi((tw * 1000.0 - 5.0) / 10.0) * 10 + 5
	var prof := clampi(roundi(side * 1000.0 / width * 20.0) * 5, 20, 80)
	r["tire"] = "%d/%d R%d" % [width, prof, inch]
	return r


## Reifenbreite (m): ab Werk tire_w, je Zoll über Werk 5 mm mehr (höchstens 30 mm, kleiner bis 10 mm schmaler), dazu wide
static func _tire_w(tw0: float, fac_in: int, inch: int, wide: float) -> float:
	return tw0 + clampf((inch - fac_in) * 0.005, -0.01, 0.03) + wide


## Kleinste Flanke (m): 20er-Querschnitt, mindestens 4 cm
static func _min_side(tw: float) -> float:
	return maxf(0.04, tw * 0.2)


## Sitz der Räder (seit 2.37): Spur je Achse aus der Karosserie (Reifenflanke 2 cm innerhalb der Kotflügelkante, Spurplatten
## schieben hinaus, mit Breitbau rückt die Kante und damit das Rad nach außen), Radius der Radläufe und Höherlegung für große
## Räder (lift). Bis 2.36 saßen die Räder fest bei halber Breite minus 15 cm, an breiten Hüften tief im Radhaus.
## Der Radlauf reicht höchstens bis 5 cm unter die Gürtellinie (dort beginnt die Flanke, _section); braucht ein großes Rad
## mehr, steht das Auto um den Rest höher (extra_lift), damit oben 2 cm Luft bleiben.
## Tiefergelegt steht der Reifen oben über der Kante des Radlaufs. Liegt er dabei innen (ab Werk), verschwindet er hinter dem
## Blech. Steht er an oder über der Kante (Spurplatten, breit), stäche er durch Kotflügel und Radlaufkante; dann wie bei
## echten tiefen Autos mit breiter Spur: negativer Sturz (die obere Hälfte wandert nach innen), der Radlauf wird etwas weiter
## (gezogene Kotflügel: bis 4 cm, nicht über die Grenze unter der Gürtellinie), und reicht das nicht, geht die Karosserie nur
## so weit herunter, wie das Rad Platz hat (drop: so viel tiefer liegt sie wirklich). drop_in: gewünschte Tieferlegung
## (Fahrwerk, Werk).
static func wheel_fit(rim: Dictionary, S: Dictionary, W: float, L: float, flare: float, drop_in: float) -> Dictionary:
	var R: float = rim["wheel_r"]
	var bulge := 0.007  # so weit steht die Flanke über die halbe Reifenbreite (m)
	var tw: float = rim["tire_w"]
	var wide: float = rim["wide"]
	var wr := wheel_r(S)
	var out := {}
	var poke := -1.0
	var belt := 9.0  # tiefste Gürtellinie über den Achsen
	for i in 2:
		var t := axle(S) / L if i == 0 else 1.0 - axle(S) / L
		var sec: PackedVector2Array = _section(S, t, W, L, flare)["p"]
		belt = minf(belt, sec[6].y)
		var lip: float = sec[4].x
		if S.get("overfenders", false):
			lip += 0.045  # aufgeschraubte Verbreiterungen (_extras): die Räder füllen sie aus wie beim Vorbild
		var xc: float = lip - 0.02 - (tw - wide) / 2.0 - bulge + float(rim["spacer"])
		out["track_f" if i == 0 else "track_r"] = xc
		poke = maxf(poke, xc + tw / 2.0 + bulge - lip)
	var ra_max := maxf(belt - 0.05 - wr, wr + 0.045)  # nie enger als ab Werk
	var ra := minf(maxf(wr + 0.045, R + 0.02), ra_max)
	var extra := maxf(R + 0.02 - ra, 0.0)
	var camber := 0.0
	var drop := drop_in
	var gap := 0.008
	# Radmitte über der Mitte des Radlaufs (Karosserie-Maß): drop + Sturzhub - extra
	if poke > -0.019 and drop_in - extra > ra - R - gap:
		# Sturz: ab dieser Höhe über der Radmitte liegt die Außenkante 1,9 cm innen (hinter Blech und Radlaufkante)
		camber = asin(minf((poke + 0.019) / (0.75 * R), sin(deg_to_rad(9.0))))
		ra = minf(maxf(ra, R + drop_in - extra + gap), maxf(ra, minf(ra + 0.04, ra_max)))
		var cl0 := (tw / 2.0) * sin(camber) - R * (1.0 - cos(camber))
		var d_max := ra - gap - R
		if camber > 0.0:
			var hide := (poke + 0.019) / sin(camber)
			d_max = -hide + sqrt(hide * hide + (ra - gap) * (ra - gap) - R * R)
		drop = clampf(d_max - cl0 + extra, 0.0, drop_in)
	out["lift"] = R - wr + extra
	out["extra_lift"] = extra
	out["arch_r"] = ra
	out["drop"] = drop
	out["camber"] = camber
	out["camber_lift"] = (tw / 2.0) * sin(camber) - R * (1.0 - cos(camber))
	out["poke"] = poke
	return out


## Zoll für Gegner und Herausforderer (gewürfelt, seit 2.37): feste Größen unter dem kleinsten, das über die Bremse passt
## (würden sonst alle auf min_in hochgesetzt), und solche, bei denen das Rad wachsen müsste, werden zu "Standard". Die alten
## relativen Plätze (1–5) bleiben: rim_spec hält sie zwischen min_in und fit_in, das Rad wächst damit nie.
static func rival_rimsize(car_id: String, cfg: Dictionary) -> int:
	var opt: Dictionary = Catalog.part_of(cfg, "rimsize")
	if opt.has("abs"):
		var rs := rim_spec(car_id, cfg)
		if int(opt["abs"]) < int(rs["min_in"]) or float(rs["grow"]) > 0.001:
			return 0
	return int(cfg.get("rimsize", 0))


## Felge und Sitz der Räder eines Autos mit Tuning in einem (Garage: Zoll, Reifen, Höherlegung, Sturz)
static func fit_info(car_id: String, cfg: Dictionary) -> Dictionary:
	var spec: Dictionary = Catalog.CARS[car_id]
	var S: Dictionary = SHAPES.get(car_id, SHAPES["kaizen"])
	var rim := rim_spec(car_id, cfg)
	var drop: float = Catalog.part_of(cfg, "suspension")["drop"] + S.get("drop", 0.0)
	rim.merge(wheel_fit(rim, S, spec["width"], spec["length"], kit_flare(cfg), drop))
	rim["drop_in"] = drop
	return rim


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
			_add(fb, rbox(Vector3(fw * 2.0 - 0.06, 0.04, 0.2)), paint, Vector3(0, CLEARANCE + 0.025, zf + 0.07))
			_add(fb, rbox(Vector3(fw * 2.0 - 0.1, 0.012, 0.21)), paint, Vector3(0, CLEARANCE + 0.0, zf + 0.07))
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.08, 0.1, skirt_l)), paint, Vector3(s * (sw + 0.015), CLEARANCE + 0.05, 0)).name = "SideSkirt"
				_add(body, rbox(Vector3(0.012, 0.02, skirt_l)), paint, Vector3(s * (sw + 0.05), CLEARANCE + 0.0, 0))
			_add(body, rbox(Vector3(rw * 2.0 - 0.2, 0.06, 0.18)), paint, Vector3(0, CLEARANCE + 0.07, zr - 0.11))
		4:
			var flap := mat(Color(0.75, 0.04, 0.04), 0.0, 0.8)
			for zi in [-1, 1]:
				for s in [-1, 1]:
					_add(body, rbox(Vector3(0.24, 0.22, 0.012)), flap, Vector3(s * _flap_x(S, W, L, flare, zi), CLEARANCE + 0.03, zi * (L / 2.0 - axle(S)) + arch_r(S) + 0.055))
			_add(body, rbox(Vector3(fw * 1.3, 0.02, 0.4)), mat(Color(0.6, 0.6, 0.62), 0.9, 0.35), Vector3(0, CLEARANCE - 0.03, zf + 0.22))
			var aux := mat(Color(1.0, 0.92, 0.7), 0.0, 0.3, Color(1.0, 0.85, 0.5), 2.2)
			for s in [-1, 1]:
				var ring := _add(fb, _disc(0.075, 0.04), dark, Vector3(s * 0.3, CLEARANCE + 0.22, zf - 0.03))
				ring.rotation_degrees.x = 90
				var lens := _add(fb, _disc(0.06, 0.01), aux, Vector3(s * 0.3, CLEARANCE + 0.22, zf - 0.052))
				lens.rotation_degrees.x = 90
			_add(fb, rbox(Vector3(0.66, 0.02, 0.03)), dark, Vector3(0, CLEARANCE + 0.15, zf - 0.025))
		5, 6:
			var cf: Material = mats["carbon"]
			_add(fb, rbox(Vector3(fw * 2.0 + 0.04, 0.04, 0.3)), cf, Vector3(0, CLEARANCE + 0.02, zf + 0.1))
			for s in [-1, 1]:
				var cx := _side_x(S, 0.03, CLEARANCE + 0.2, W, L, flare)
				for k in 2:
					var cn := _add(fb, rbox(Vector3(0.13, 0.01, 0.1)), cf, Vector3(s * (cx + 0.02), CLEARANCE + 0.14 + k * 0.09, zf + 0.08))
					cn.rotation.z = s * 0.28
				_add(body, rbox(Vector3(0.07, 0.07, skirt_l)), cf, Vector3(s * (sw + 0.02), CLEARANCE + 0.02, 0)).name = "SideSkirt"
			for k in 7:
				_add(body, rbox(Vector3(0.012, 0.15, 0.36)), cf, Vector3((k - 3) * rw * 0.15, CLEARANCE + 0.03, zr - 0.15))
			_add(body, rbox(Vector3(rw * 1.8, 0.012, 0.36)), cf, Vector3(0, CLEARANCE - 0.0, zr - 0.15))
			_add(fb, rbox(Vector3(0.05, 0.05, 0.1)), mat(Color(0.85, 0.05, 0.04), 0.4, 0.4), Vector3(fw * 0.6, CLEARANCE + 0.08, zf - 0.02))


## Spoiler 4–9: Entenbürzel, Street-Flügel, Schwanenhals, Doppeldecker, Dachspoiler, Bügelflügel
static func _spoiler(body: Node3D, S: Dictionary, W: float, L: float, flare: float, sp: int, deck_y: float, wz: float,
		dark: Material, paint: Material, car_id: String) -> void:
	var zf := -L / 2.0
	# halbe Spannweite wie in build(): Karosserie am Flügel + 2 cm (bis 2.36 halbe Katalogbreite)
	var wh: float = (_section(S, (wz - zf) / L, W, L, flare)["p"] as PackedVector2Array)[4].x + 0.02
	match sp:
		4:
			var bt := 1.0 - 0.09 / L
			var bp: PackedVector2Array = _section(S, bt, W, L, flare)["p"]
			var bw := bp[7].x * 2.0 - 0.04
			_add(body, tapered_box(Vector2(bw, 0.24), Vector2(bw - 0.05, 0.05), 0.1, 0.12), paint, Vector3(0, bp[10].y - 0.015, zf + bt * L - 0.08))
		5:
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.035, 0.1, 0.08)), dark, Vector3(s * (wh - 0.42), deck_y + 0.05, wz + 0.03))
				_add(body, _endplate(0.02, 0.08, 0.3), paint, Vector3(s * (wh - 0.16), deck_y + 0.12, wz + 0.04))
			_add(body, _airfoil(2.0 * wh - 0.32, 0.27, 0.035), paint, Vector3(0, deck_y + 0.11, wz + 0.04)).rotation_degrees.x = -6
		6:
			var hgt := 0.32
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.04, hgt + 0.06, 0.06)), dark, Vector3(s * 0.32, deck_y + (hgt + 0.06) / 2.0, wz + 0.17))
				_add(body, rbox(Vector3(0.04, 0.04, 0.2)), dark, Vector3(s * 0.32, deck_y + hgt + 0.06, wz + 0.08))
				_add(body, _endplate(0.03, 0.2, 0.42), paint, Vector3(s * (wh - 0.05), deck_y + hgt - 0.02, wz + 0.02))
			_add(body, _airfoil(2.0 * wh - 0.1, 0.36, 0.04), paint, Vector3(0, deck_y + hgt, wz + 0.02)).rotation_degrees.x = -8
		7:
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.05, 0.24, 0.1)), dark, Vector3(s * (wh - 0.4), deck_y + 0.12, wz))
				_add(body, _endplate(0.03, 0.26, 0.46), paint, Vector3(s * (wh - 0.04), deck_y + 0.3, wz + 0.02))
			_add(body, _airfoil(2.0 * wh - 0.08, 0.34, 0.04), paint, Vector3(0, deck_y + 0.24, wz)).rotation_degrees.x = -5
			_add(body, _airfoil(2.0 * wh - 0.08, 0.2, 0.03), paint, Vector3(0, deck_y + 0.38, wz + 0.1)).rotation_degrees.x = -14
		8:
			if car_id == "kaizen":
				return  # hat ab Werk einen Dachspoiler
			var t0: float = S["rr"]
			var y0 := _top_c(S, t0)
			var roof_w: float = (_section(S, t0, W, L, flare)["p"] as PackedVector2Array)[7].x * 2.0  # Dachbreite dort
			var rs := _add(body, _airfoil(roof_w * 0.86, 0.22, 0.025), paint, Vector3(0, y0 + 0.012, (t0 - 0.5) * L + 0.09))
			rs.rotation.x = 0.1
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.02, 0.05, 0.22)), paint, Vector3(s * roof_w * 0.43, y0 - 0.005, (t0 - 0.5) * L + 0.09)).rotation.x = 0.1
		9:
			for s in [-1, 1]:
				_add(body, rbox(Vector3(0.07, 0.25, 0.16)), paint, Vector3(s * (wh - 0.25), deck_y + 0.09, wz + 0.03)).rotation_degrees.x = 20
			_add(body, _airfoil(2.0 * wh - 0.4, 0.27, 0.04), paint, Vector3(0, deck_y + 0.21, wz + 0.08)).rotation_degrees.x = -5


## Motorhauben 1–6 (5 = Kohlefaser ist nur Haut, siehe _skin): Hutze, Lamellen, NACA-Einlass, Doppelhutze
static func _hood(body: Node3D, S: Dictionary, W: float, L: float, flare: float, hood: int, dark: Material, scoop_m: Material) -> void:
	var zf := -L / 2.0
	var th: float = S["cowl"] * 0.58
	var p: PackedVector2Array = _section(S, th, W, L, flare)["p"]
	var slope := (_top_c(S, th + 0.04) - _top_c(S, th - 0.04)) / (0.08 * L)
	var tilt := -atan(slope)
	var scoop := func(x: float, size: float) -> void:
		var y := _top_y(p, absf(x) / p[7].x) - 0.01
		var sc := _add(body, rtapered_box(Vector2(0.5, 0.42) * size, Vector2(0.42, 0.3) * size, 0.075 * size, 0.05 * size, 0.025 * size), scoop_m, Vector3(x, y, zf + th * L))
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


## Radlauf: gerollte Kante um jeden Radausschnitt, ein dünnes lackiertes Rohr auf dem Rand (sonst endet die Haut dort
## wie ausgestanzt). Folgt der Flanke (Punkt 4 des Querschnitts), beide Seiten.
static func _arch_lips(body: Node3D, S: Dictionary, W: float, L: float, flare: float, m: Material) -> void:
	var wr := wheel_r(S)
	var ra := arch_r(S)
	var rt := 0.013
	const SEG := 20
	const RING := 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
		var path := []
		for i in SEG + 1:
			var th := lerpf(0.05, PI - 0.05, float(i) / SEG)
			var z: float = wz + ra * cos(th)
			var y := wr + ra * sin(th)
			var x: float = _section(S, (z + L / 2.0) / L, W, L, flare)["p"][4].x - 0.004
			path.append(Vector3(x, y, z))
		var rings := []
		for i in SEG + 1:
			var c: Vector3 = path[i]
			var tng: Vector3 = (path[mini(i + 1, SEG)] - path[maxi(i - 1, 0)]).normalized()
			var radial := Vector3(0.0, c.y - wr, c.z - wz).normalized()
			var b2 := tng.cross(radial).normalized()
			if b2.x < 0.0:
				b2 = -b2
			radial = b2.cross(tng).normalized() * signf(b2.cross(tng).dot(radial))
			var ring := []
			for k in RING:
				var a := TAU * k / RING
				var n := (radial * cos(a) + b2 * sin(a)).normalized()
				ring.append([c + n * rt, n])
			rings.append(ring)
		for side in [1.0, -1.0]:
			var mx := Vector3(side, 1.0, 1.0)
			for i in SEG:
				for k in RING:
					var k2 := (k + 1) % RING
					var A: Array = rings[i][k]
					var B: Array = rings[i + 1][k]
					var Cc: Array = rings[i + 1][k2]
					var D: Array = rings[i][k2]
					var nf: Vector3 = (A[1] + B[1] + Cc[1] + D[1]) * mx
					_tri(st, A[0] * mx, B[0] * mx, Cc[0] * mx, A[1] * mx, B[1] * mx, Cc[1] * mx, nf)
					_tri(st, A[0] * mx, Cc[0] * mx, D[0] * mx, A[1] * mx, Cc[1] * mx, D[1] * mx, nf)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
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
		# Verbreiterungen: Bögen um die Radläufe in Wagenfarbe, außen auf die Flanke geschraubt. Seit 2.25 ein glatter,
		# gerundeter Bogen (vorher elf aneinandergesetzte Klötzchen, das wirkte wie Lego).
		var ra := arch_r(S) + 0.025
		for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
			for s in [-1, 1]:
				var pts := []
				for k in 25:
					var a := deg_to_rad(-84.0 + k * 7.0)
					var y := wheel_r(S) + cos(a) * ra
					var z: float = wz + sin(a) * ra
					var x := _side_x(S, (z - zf) / L, clampf(y, CLEARANCE + 0.1, S["belt"] - 0.05), W, L, flare) + 0.008
					pts.append([Vector3(s * x, y, z), Vector3(0, cos(a), sin(a))])
				_add(body, _arc_strip(pts, s, 0.055, 0.042), paint, Vector3.ZERO)
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
	var roof_w: float = (_section(S, float(S["rr"]), W, L, 0.0)["p"] as PackedVector2Array)[7].x * 2.0  # Dachbreite (Querschnitt)
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


## --- Feinheiten (seit 2.36): Türgriffe, Fugen, Antenne, Wappen, Rückstrahler, Heckwischer, Gitter, Leuchten-Innenleben.
## Bis 2.35 wirkten die Autos etwas wie Spielzeug: Glas ohne Säulen und Rahmen, gleichmäßig leuchtende Lampenflächen,
## keine Fugen an Haube und Deckel, Spiegel ohne Arm.

## Türgriffe: lackierter Griff mit dunkler Fuge rundherum, vorn an der Hinterkante jeder Tür, der Flanke folgend
static func _door_handles(body: Node3D, S: Dictionary, W: float, L: float, flare: float, paint: Material, gap: Material) -> void:
	var zf := -L / 2.0
	var d: Array = S["doors"]
	var ends: Array = [d[1]] if d.size() < 3 else [d[1], d[2]]
	for te in ends:
		var t: float = float(te) - 0.12 / L
		var y: float = float((_section(S, t, W, L, flare)["p"] as PackedVector2Array)[6].y) - 0.06
		var x := _side_x(S, t, y, W, L, flare)
		var ang := atan2(_side_x(S, t + 0.01, y, W, L, flare) - _side_x(S, t - 0.01, y, W, L, flare), 0.02 * L)
		for s in [-1, 1]:
			var rim := _add(body, rbox(Vector3(0.008, 0.032, 0.125), 0.003), gap, Vector3(s * (x + 0.001), y, zf + t * L))
			rim.rotation.y = -s * ang
			var hd := _add(body, rbox(Vector3(0.014, 0.022, 0.112), 0.006), paint, Vector3(s * (x + 0.005), y, zf + t * L))
			hd.rotation.y = -s * ang


## Punkt auf der Oberseite der Haut (Haube, Dach, Deckel) bei t im Abstand x von der Mitte und die Flächennormale dort.
## Folgt dem verfeinerten Querschnitt wie die Haut (_shell), nicht der Näherung _top_y: Fugen liegen sonst in der
## Haube oder schweben darüber.
static func _top_pt(S: Dictionary, t: float, x: float, W: float, L: float, flare: float) -> Array:
	var p := _refine(_section(S, t, W, L, flare)["p"], SHELL_SUB)
	var ax := absf(x)
	var sx := 1.0 if x >= 0.0 else -1.0
	var z := (t - 0.5) * L
	for j in range(_ref_idx(7), p.size() - 1):
		var a := p[j]
		var b := p[j + 1]
		if ax <= a.x + 1e-5 and ax >= b.x - 1e-5:
			var f := (a.x - ax) / maxf(a.x - b.x, 1e-5)
			var q := a.lerp(b, f)
			var dd := b - a
			var n2 := Vector2(dd.y, -dd.x).normalized()
			if n2.y < 0.0:
				n2 = -n2
			return [Vector3(x, q.y, z), Vector3(n2.x * sx, n2.y, 0.0)]
	var top := p[p.size() - 1]
	return [Vector3(x, top.y, z), Vector3.UP]


## Schmales Band entlang einer Linie auf der Haut (Fugen): pts Punkte, nrm Flächennormalen, w Breite, lift Abstand
static func _ribbon(pts: Array, nrm: Array, w: float, lift := 0.0025) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var lo := []
	var hi := []
	var nn := []
	for i in n:
		var tg: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var nv: Vector3 = nrm[i]
		nv = (nv - tg * nv.dot(tg)).normalized()
		var sd := tg.cross(nv).normalized() * w / 2.0
		var p: Vector3 = (pts[i] as Vector3) + nv * lift
		lo.append(p - sd)
		hi.append(p + sd)
		nn.append(nv)
	for i in n - 1:
		var nf: Vector3 = (nn[i] + nn[i + 1]).normalized()
		_tri(st, lo[i], hi[i], hi[i + 1], nn[i], nn[i], nn[i + 1], nf)
		_tri(st, lo[i], hi[i + 1], lo[i + 1], nn[i], nn[i + 1], nn[i + 1], nf)
	return st.commit()


## Innenkante der geschlossenen Klappscheinwerfer je Auto: die Haubenfuge läuft innen daran vorbei
const POPUP_IN := {"ronin": 0.3, "hachi": 0.24, "kitsune": 0.25, "tenshi": 0.29, "shiden": 0.3, "tatsumaki": 0.31}


## Fugen um Haube und Heckdeckel (bzw. Heckklappe): Seitenlinien auf der Oberseite knapp innerhalb der Schulter, vorn
## quer über den Bug, hinten eine Querfuge auf der Heckfläche unter den Leuchten. Eine Fläche aus schmalen Bändern.
static func _panel_lines(body: Node3D, car_id: String, S: Dictionary, W: float, L: float, flare: float, gap: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wd := 0.0065
	var hx := func(t: float) -> float:
		var p: PackedVector2Array = _section(S, t, W, L, flare)["p"]
		var x: float = p[7].x - 0.022
		if POPUP_IN.has(car_id):
			x = minf(x, float(POPUP_IN[car_id]) - 0.02)
		return x
	var add_line := func(pts: Array, nrm: Array) -> void:
		var m := _ribbon(pts, nrm, wd)
		st.append_from(m, 0, Transform3D.IDENTITY)
	# Haube: Seiten von der Fuge der Frontschürze bis zum Windlauf, vorn quer
	var ta := FRONT_SEAM + 0.004
	var tb: float = float(S["cowl"]) - 0.045 / L
	for s in [-1.0, 1.0]:
		var pts := []
		var nrm := []
		for k in 13:
			var t := lerpf(ta, tb, k / 12.0)
			var q := _top_pt(S, t, s * hx.call(t), W, L, flare)
			pts.append(q[0])
			nrm.append(q[1])
		add_line.call(pts, nrm)
	var front := []
	var fn := []
	var xa: float = hx.call(ta)
	for k in 11:
		var q := _top_pt(S, ta, lerpf(-xa, xa, k / 10.0), W, L, flare)
		front.append(q[0])
		fn.append(q[1])
	add_line.call(front, fn)
	# Heckdeckel bzw. Heckklappe: Seiten bis an die Heckkante, bei der Klappe dazu die Querfuge am Dachende
	var hatch: bool = float(S["ge"]) >= 0.86 and not S.get("mid", false) and not S.get("softtop", false)
	var tr0: float = (float(S["rr"]) - 0.006 / L) if hatch else (float(S["ge"]) + 0.006 / L)
	var tr1 := 1.0 - 0.012 / L
	for s in [-1.0, 1.0]:
		var pts := []
		var nrm := []
		for k in 13:
			var t := lerpf(tr0, tr1, k / 12.0)
			var x: float = (_section(S, t, W, L, flare)["p"] as PackedVector2Array)[7].x - 0.03
			var q := _top_pt(S, t, s * x, W, L, flare)
			pts.append(q[0])
			nrm.append(q[1])
		add_line.call(pts, nrm)
	if hatch:
		var xr: float = (_section(S, tr0, W, L, flare)["p"] as PackedVector2Array)[7].x - 0.03
		var top := []
		var tn := []
		for k in 11:
			var q := _top_pt(S, tr0, lerpf(-xr, xr, k / 10.0), W, L, flare)
			top.append(q[0])
			tn.append(q[1])
		add_line.call(top, tn)
	# Querfuge auf der Heckfläche: Unterkante von Deckel bzw. Klappe, knapp unter der Flankenmitte
	var rp: PackedVector2Array = _section(S, 1.0, W, L, flare)["p"]
	var yl: float = rp[5].y - 0.035
	var xl := _side_x(S, 1.0, yl, W, L, flare) - 0.09
	var z := L / 2.0 + 0.0025
	var rear := []
	var rn := []
	for k in 2:
		rear.append(Vector3(lerpf(-xl, xl, k), yl, z))
		rn.append(Vector3(0, 0, 1))
	add_line.call(rear, rn)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = gap
	_near(mi)
	body.add_child(mi)


## Kleinteile: Antenne, Wappen vorn und hinten, Rückstrahler in der Heckschürze, Heckwischer bei Fließhecks,
## Waschdüsen auf der Haube
static func _small_parts(body: Node3D, car_id: String, spec: Dictionary, S: Dictionary, W: float, L: float, flare: float,
		dark: Material, mats: Dictionary) -> void:
	var zf := -L / 2.0
	var zr := L / 2.0
	var chrome := mat(Color(0.75, 0.75, 0.78), 0.95, 0.15)
	# Antenne: alte Autos mit Stabantenne auf dem rechten Kotflügel vorn, sonst ein kurzer Stab hinten auf dem Dach
	if S.get("chrome_bumpers", false) or car_id == "hachi":
		var ta: float = float(S["cowl"]) - 0.03
		var pa: PackedVector2Array = _section(S, ta, W, L, flare)["p"]
		var base := Vector3(pa[6].x - 0.03, pa[6].y + 0.005, zf + ta * L)
		_add(body, _disc(0.012, 0.012), chrome, base)
		var rod := _near(_add(body, _rod(0.0028, 0.62), chrome, base + Vector3(0, 0.31, 0.03)))
		rod.rotation.x = 0.1
	elif not S.get("softtop", false):
		var tr: float = float(S["rr"]) - 0.025
		var q := _top_pt(S, tr, 0.0, W, L, flare)
		var bp: Vector3 = q[0]
		var bb := _add(body, rbox(Vector3(0.03, 0.016, 0.06), 0.007), dark, bp + Vector3(0, 0.006, 0))
		bb.rotation.x = -atan2(_top_c(S, tr + 0.01) - _top_c(S, tr - 0.01), 0.02 * L)
		var rod := _near(_add(body, _rod(0.0025, 0.26), dark, bp + Vector3(0, 0.12, 0.065)))
		rod.rotation.x = 0.5
	# Wappen: kleine Chromplakette vorn oben in der Mitte (nicht bei Autos mit eigenem Emblem im Gitter) und
	# Typenschild rechts auf dem Heck unter den Leuchten
	if not car_id in ["kaizen", "kumo", "kaido", "chibi", "hakone", "yari"]:
		var yb: float = float(S["nose"]) - 0.045
		_near(_add(body, _rplate(0.07, 0.028, 0.01, 0.006), chrome, Vector3(0, yb, zf - 0.007)))
	var rp: PackedVector2Array = _section(S, 1.0, W, L, flare)["p"]
	var yr: float = rp[5].y - 0.075
	var xr := minf(_side_x(S, 1.0, yr, W, L, flare) - 0.2, 0.42)
	_near(_add(body, _rplate(0.13, 0.02, 0.006, 0.005), chrome, Vector3(xr, yr, zr + 0.004)))
	# Rückstrahler unten an den Ecken der Heckschürze
	var refl := mat(Color(0.25, 0.02, 0.02), 0.2, 0.25, Color(0.5, 0.0, 0.0), 0.5)  # wie die Blende hinten (build)
	var yf := CLEARANCE + 0.2
	var xf := _side_x(S, 1.0, yf, W, L, flare) - 0.14
	for s in [-1, 1]:
		_near(_add(body, _rplate(0.09, 0.024, 0.01, 0.006), refl, Vector3(s * xf, yf, zr + 0.003)))
	# Heckwischer auf der Heckscheibe der Fließhecks: Arm von unten Mitte schräg nach oben
	if str(spec.get("style", "")) == "hatch":
		var tw: float = float(S["ge"]) - 0.03
		var q := _top_pt(S, tw, 0.0, W, L, flare)
		var slope := atan2(_top_c(S, tw + 0.01) - _top_c(S, tw - 0.01), 0.02 * L)
		var pv := Node3D.new()
		pv.position = (q[0] as Vector3) + Vector3(0, 0.012, 0)
		pv.rotation.x = -slope
		body.add_child(pv)
		_add(pv, _disc(0.018, 0.014), dark, Vector3.ZERO)
		var arm := _near(_add(pv, box(Vector3(0.36, 0.01, 0.014)), mat(Color(0.09, 0.09, 0.1), 0.4, 0.45), Vector3(-0.17, 0.006, -0.05)))
		arm.rotation.y = -0.28
	# Waschdüsen auf der Haube vor dem Windlauf
	var tn: float = float(S["cowl"]) - 0.07 / L
	for s in [-1, 1]:
		var q := _top_pt(S, tn, s * 0.22, W, L, flare)
		_near(_add(body, rbox(Vector3(0.022, 0.012, 0.03), 0.005), dark, (q[0] as Vector3) + Vector3(0, 0.004, 0)))


## Dünner Stab entlang Y (Antenne)
static func _rod(r: float, h: float) -> CylinderMesh:
	var key := "rod_%.4f_%.3f" % [r, h]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var c := CylinderMesh.new()
	c.top_radius = r * 0.7
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	_mesh_cache[key] = c
	return c


## Flache Platte mit runden Ecken: Umriss pts (x, y), Eckenradius r, Dicke d entlang Z, Mitte im Ursprung, beide Seiten
## (vorn -Z, hinten +Z). Einlässe, Gehäuse, Plaketten; rundere Formen als ein Quader.
static func _poly_plate(pts: PackedVector2Array, r: float, d: float) -> ArrayMesh:
	var key := "pp_%s_%.4f_%.4f" % [str(pts), r, d]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var outline := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var c := pts[i]
		var a := pts[(i - 1 + n) % n] - c
		var b := pts[(i + 1) % n] - c
		var rr := minf(r, minf(a.length(), b.length()) * 0.49)
		if rr < 0.001:
			outline.append(c)
			continue
		var p0 := c + a.normalized() * rr
		var p1 := c + b.normalized() * rr
		for k in 6:
			var f := k / 5.0
			outline.append(p0.lerp(c, f).lerp(c.lerp(p1, f), f))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(outline)
	var hz := d / 2.0
	for e in [-1.0, 1.0]:
		var nz := Vector3(0, 0, e)
		for k in range(0, tri.size(), 3):
			var va := outline[tri[k]]
			var vb := outline[tri[k + 1]]
			var vc := outline[tri[k + 2]]
			_tri(st, Vector3(va.x, va.y, e * hz), Vector3(vb.x, vb.y, e * hz), Vector3(vc.x, vc.y, e * hz), nz, nz, nz, nz)
	var no := outline.size()
	var ctr := Vector2.ZERO
	for v in outline:
		ctr += v
	ctr /= no
	for i in no:
		var j := (i + 1) % no
		var dd := outline[j] - outline[i]
		var n2 := Vector2(dd.y, -dd.x).normalized()
		if n2.dot((outline[i] + outline[j]) / 2.0 - ctr) < 0.0:
			n2 = -n2
		var nv := Vector3(n2.x, n2.y, 0.0)
		var A := Vector3(outline[i].x, outline[i].y, -hz)
		var B := Vector3(outline[j].x, outline[j].y, -hz)
		var C := Vector3(outline[j].x, outline[j].y, hz)
		var D := Vector3(outline[i].x, outline[i].y, hz)
		_tri(st, A, B, C, nv, nv, nv, nv)
		_tri(st, A, C, D, nv, nv, nv, nv)
	var m := st.commit()
	_mesh_cache[key] = m
	return m


## Rechteckige Platte w x h mit Eckenradius r (siehe _poly_plate)
static func _rplate(w: float, h: float, r: float, d := 0.012) -> ArrayMesh:
	return _poly_plate(PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]), r, d)


## Gitter für Lufteinlässe: Wabenmuster im Shader (Lage aus den Modellkoordinaten, darum auch nach dem Verschmelzen
## gleich groß), dunkle Öffnungen, matt glänzende Stege. Ein Material für alle Autos (ein Draw Call je Auto).
static var _grille: ShaderMaterial


static func grille_mat() -> ShaderMaterial:
	if _grille:
		return _grille
	var sh := Shader.new()
	sh.code = """shader_type spatial;
// Wabengitter (car_builder.grille_mat): Muster in Modellkoordinaten, Projektion nach der größten Normalen-Achse
uniform float cell = 0.017;
varying vec3 lp;
varying vec3 ln;
void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}
float hexd(vec2 p) {
	p = abs(p);
	return max(dot(p, vec2(0.5, 0.8660254)), p.x);
}
void fragment() {
	vec3 n = abs(ln);
	vec2 uv = (n.z >= n.x && n.z >= n.y) ? lp.xy : ((n.x >= n.y) ? lp.zy : lp.xz);
	uv /= cell;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	float d = hexd(g);
	float aa = fwidth(d) * 1.2;
	float web = smoothstep(0.4 - aa, 0.4 + aa, d);
	ALBEDO = mix(vec3(0.004), vec3(0.055, 0.056, 0.06), web);
	METALLIC = 0.4 * web;
	ROUGHNESS = mix(0.95, 0.42, web);
}
"""
	_grille = ShaderMaterial.new()
	_grille.shader = sh
	_grille.set_meta("lod_color", Color(0.02, 0.02, 0.022))
	return _grille


## Lufteinlässe der Frontschürze mit Gitter: dünne dunkle Platten vorn (Einlass, Nebelscheinwerfer-Mulden, Grill) bekommen
## das Wabenmuster statt einfarbig Schwarz
static func _grille_intakes(fb: Node3D, dark: Material) -> void:
	for c in fb.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == dark and (c as MeshInstance3D).mesh is BoxMesh:
			var sz: Vector3 = ((c as MeshInstance3D).mesh as BoxMesh).size
			if sz.z <= 0.016 and sz.y >= 0.035 and sz.x >= 0.08:
				(c as MeshInstance3D).material_override = grille_mat()


## Innenleben der Leuchten. Die Leuchtflächen (Material head bzw. tail) vorn und hinten werden je Seite gesucht:
## Scheinwerfer bekommen eine Reflektor-Fläche statt gleichmäßigen Leuchtens, darin helle Projektoren mit Chromring und
## ein Tagfahrlicht-Streifen; Rückleuchten ein dunkleres Streuglas mit hellem Lichtband und Ring, runde Leuchten einen
## Ring mit Glühfaden-Mitte. front: Scheinwerfer bearbeiten (nicht bei geschlossenen Klappscheinwerfern).
static func _lamp_detail(body: Node3D, mats: Dictionary, L: float, light_c: Color, front: bool) -> void:
	var zf := -L / 2.0
	var zr := L / 2.0
	var head: Material = mats["head"]
	var tail: Material = mats["tail"]
	# alle Flächen mit Leuchtenmaterial: [MeshInstance, Fläche, Punkte im Body-Raum]
	var found := {head: [], tail: []}
	var stack: Array = [body]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not nd is MeshInstance3D or (nd as MeshInstance3D).mesh == null:
			continue
		var mi := nd as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != body:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			if m == head or m == tail:
				var pts := PackedVector3Array()
				for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					pts.append(xf * v)
				found[m].append([mi, si, pts])
	var hot_h := mat(Color(1, 1, 1), 0.0, 0.3, Color(1, 1, 1).lerp(light_c, 0.6), 5.0)
	var bezel := mat(Color(0.75, 0.75, 0.78), 0.95, 0.15)
	var lens_h := mat(Color(0.55, 0.57, 0.6), 1.0, 0.08, Color(1, 1, 0.97).lerp(light_c, 0.5), 0.5)
	var lens_t := mat(Color(0.32, 0.015, 0.015), 0.3, 0.14, Color(0.95, 0.04, 0.02), 1.25)
	var hot_t := mat(Color(1, 0.2, 0.15), 0.0, 0.3, Color(1, 0.1, 0.05), 4.2)
	var red_in := mat(Color(0.25, 0.02, 0.02), 0.2, 0.25, Color(0.5, 0.0, 0.0), 0.5)  # wie die Blende hinten (build)
	# Fernansicht (_build_lod): dort leuchten die Flächen wieder gleichmäßig hell, das Innenleben fehlt
	lens_h.set_meta("lod_material", head)
	lens_t.set_meta("lod_material", tail)
	for kind in ["head", "tail"]:
		if kind == "head" and not front:
			continue
		var m: Material = head if kind == "head" else tail
		for s in [-1.0, 1.0]:
			var pts := PackedVector3Array()
			var parts := []
			var discs := []
			for e in found[m]:
				var mine := PackedVector3Array()
				for v in (e[2] as PackedVector3Array):
					if signf(v.x) != s or absf(v.x) < 0.1:
						continue
					if kind == "head" and (v.z > zf + 0.12 or v.y < CLEARANCE + 0.19):
						continue
					if kind == "tail" and v.z < zr - 0.12:
						continue
					mine.append(v)
				if mine.is_empty():
					continue
				if (e[0] as MeshInstance3D).mesh is CylinderMesh:
					discs.append(e)
				else:
					parts.append(e)
					pts.append_array(mine)
			# runde Leuchten: hinten ein leuchtender Ring (die Scheibe selbst) um dunkleres Glas mit hellem Punkt, vorn ein
			# Reflektor mit heller Lampe in der Mitte
			for e in discs:
				var mi: MeshInstance3D = e[0]
				var cyl := mi.mesh as CylinderMesh
				var r: float = cyl.top_radius
				if r < 0.026:
					continue
				var c: Vector3 = Vector3.ZERO
				for v in (e[2] as PackedVector3Array):
					c += v
				c /= (e[2] as PackedVector3Array).size()
				if signf(c.x) != s:
					continue
				if kind == "tail":
					var zc: float = c.z + cyl.height / 2.0
					_near(_add(body, _disc(r * 0.64, 0.004), red_in, Vector3(c.x, c.y, zc + 0.0015))).rotation_degrees.x = 90
					_near(_add(body, _disc(r * 0.2, 0.004), hot_t, Vector3(c.x, c.y, zc + 0.003))).rotation_degrees.x = 90
				elif absf(mi.rotation_degrees.x - 90.0) < 1.0:
					var zc: float = c.z - cyl.height / 2.0
					mi.material_override = lens_h
					_near(_add(body, _disc(r * 0.42, 0.004), hot_h, Vector3(c.x, c.y, zc - 0.0015))).rotation_degrees.x = 90
			if pts.size() < 3:
				continue
			var lo := pts[0]
			var hi := pts[0]
			for v in pts:
				lo = lo.min(v)
				hi = hi.max(v)
			var x_in := absf(hi.x) if s < 0.0 else lo.x
			var x_out := absf(lo.x) if s < 0.0 else hi.x
			var w := x_out - x_in
			var h := hi.y - lo.y
			if w < 0.09 or h < 0.03:
				continue
			# Stirnfläche: die Punkte vorn (bzw. hinten) bis 4,5 cm hinter der vordersten Stelle, nach |x| sortiert; z bei x
			# dazwischen linear (Quader haben nur Eckpunkte). Um die Ecke gezogene Teile zählen nicht.
			var z_edge: float = lo.z if kind == "head" else hi.z
			var layer := []
			for v in pts:
				if absf(v.z - z_edge) < 0.045:
					layer.append(Vector2(absf(v.x), v.z))
			layer.sort_custom(func(a, b): return a.x < b.x)
			# je x nur die vorderste (hinten: hinterste) Stelle: dünne Teile haben auch eine Rückseite
			var front_l := []
			for q in layer:
				var qv: Vector2 = q
				if not front_l.is_empty() and qv.x - (front_l[-1] as Vector2).x < 0.002:
					var last: Vector2 = front_l[-1]
					front_l[-1] = Vector2(last.x, minf(last.y, qv.y) if kind == "head" else maxf(last.y, qv.y))
				else:
					front_l.append(qv)
			layer = front_l
			var face := func(xq: float) -> float:
				if layer.is_empty() or xq < (layer[0] as Vector2).x - 0.003 or xq > (layer[-1] as Vector2).x + 0.003:
					return INF
				var prev: Vector2 = layer[0]
				for q in layer:
					var qv: Vector2 = q
					if qv.x >= xq:
						if qv.x - prev.x < 1e-4:
							return qv.y
						return lerpf(prev.y, qv.y, (xq - prev.x) / (qv.x - prev.x))
					prev = qv
				return prev.y
			if layer.size() < 2:
				continue
			x_in = maxf(x_in, (layer[0] as Vector2).x)
			var x_face: float = (layer[-1] as Vector2).x
			var fw := x_face - x_in
			if fw < 0.07:
				continue
			for e in parts:
				var mi: MeshInstance3D = e[0]
				if mi.material_override == m:
					mi.material_override = lens_h if kind == "head" else lens_t
				else:
					mi.mesh.surface_set_material(e[1], lens_h if kind == "head" else lens_t)
			var dz := -1.0 if kind == "head" else 1.0
			var yc := (lo.y + hi.y) / 2.0
			if kind == "head":
				# Projektoren: innen beginnend, einer oder zwei
				var r := clampf(h * 0.34, 0.016, 0.042)
				var n := 2 if fw >= 0.26 and h >= 0.05 else 1
				for k in n:
					var xc := x_in + r * 1.6 + 0.008 + k * r * 2.75
					if xc + r * 1.3 > x_face:
						break
					var zc: float = face.call(xc)
					if not is_finite(zc):
						continue
					_near(_add(body, _disc(r * 1.3, 0.004), bezel, Vector3(s * xc, yc, zc - 0.002))).rotation_degrees.x = 90
					_near(_add(body, _disc(r, 0.004), hot_h, Vector3(s * xc, yc, zc - 0.004))).rotation_degrees.x = 90
				# Tagfahrlicht: Streifen an der Unterkante über die Stirnfläche
				if fw >= 0.15:
					var line := []
					var ln := []
					for k in 7:
						var xq := lerpf(x_in + 0.012, x_face - 0.008, k / 6.0)
						var zq: float = face.call(xq)
						if is_finite(zq):
							line.append(Vector3(s * xq, lo.y + 0.009, zq + dz * 0.003))
							ln.append(Vector3(0, 0, dz))
					if line.size() >= 2:
						_near(_add(body, _ribbon(line, ln, maxf(0.006, h * 0.12), 0.0), hot_h, Vector3.ZERO))
			else:
				# außen ein leuchtender Ring, innen davor ein Lichtband, bei breiten Leuchten Stege dazwischen
				var bar_end := x_face - 0.012
				if h >= 0.05 and fw >= 0.14:
					var r := clampf(h * 0.3, 0.018, 0.05)
					var xc := x_face - r - 0.02
					var zc: float = face.call(xc)
					if is_finite(zc):
						var yr := yc
						_near(_add(body, _disc(r, 0.004), hot_t, Vector3(s * xc, yr, zc + 0.003))).rotation_degrees.x = 90
						_near(_add(body, _disc(r * 0.62, 0.004), red_in, Vector3(s * xc, yr, zc + 0.0045))).rotation_degrees.x = 90
						bar_end = xc - r - 0.015
				var line := []
				var ln := []
				var yb := hi.y - h * 0.3
				for k in 7:
					var xq := lerpf(x_in + 0.015, bar_end, k / 6.0)
					var zq: float = face.call(xq)
					if is_finite(zq):
						line.append(Vector3(s * xq, yb, zq + dz * 0.003))
						ln.append(Vector3(0, 0, dz))
				if line.size() >= 2 and bar_end - x_in > 0.06:
					_near(_add(body, _ribbon(line, ln, clampf(h * 0.16, 0.007, 0.016), 0.0), hot_t, Vector3.ZERO))
				if fw >= 0.3:
					var nd := 2 if fw >= 0.5 else 1
					for k in nd:
						var xq := x_in + fw * float(k + 1) / float(nd + 1)
						var zq: float = face.call(xq)
						if is_finite(zq):
							_near(_add(body, box(Vector3(0.006, h * 0.8, 0.004)), mats["seam"], Vector3(s * xq, yc, zq + 0.0035)))


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
		collect_static(g, Transform3D.IDENTITY, stops, canon, buckets, func(mi, _xf): return 1 if mi.has_meta("near_only") else 0, true)
		for mi in merge_buckets(g, buckets, true):
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
	var canon := {}
	collect_static(root, Transform3D.IDENTITY, stops, canon, buckets, func(_mi, _xf): return 0)
	for nd in swap:
		(nd as MeshInstance3D).visible = nd.has_meta("near_only")
	# Leuchten mit Innenleben (_lamp_detail) in der Fernansicht wieder mit dem hellen Material, in derselben Fläche
	for key in buckets.keys():
		var m0: Material = key[0]
		if m0.has_meta("lod_material"):
			var alt = merge_material(m0.get_meta("lod_material"), canon)
			if alt == null:
				continue
			var nk := [alt, key[1], key[2]]
			if not buckets.has(nk):
				buckets[nk] = []
			buckets[nk].append_array(buckets[key])
			buckets.erase(key)
	var mesh := ArrayMesh.new()
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for key in buckets:
		var st := SurfaceTool.new()
		for it in buckets[key]:
			st.append_from(it[0], it[1], it[2])
		var m: Material = key[0]
		var plain: bool = (m is StandardMaterial3D and not (m as StandardMaterial3D).emission_enabled \
			and (m as StandardMaterial3D).albedo_texture == null or m.has_meta("lod_color")) and key[1][0]
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
		c.fill(m.get_meta("lod_color") if m.has_meta("lod_color") else (m as StandardMaterial3D).albedo_color)
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
	collect_static(n, Transform3D.IDENTITY, {}, {}, buckets, func(_mi, _xf): return 0, true)
	merge_buckets(n, buckets, true)


## Sammelt unbewegliche Mesh-Flächen unterhalb von n (nur durch einfache Node3D hindurch, ohne Skripte) in
## Eimer [Material, Format, extra] -> [[Mesh, Fläche, Transform, Knoten]]. extra(mi, xf) teilt zusätzlich auf
## (Rasterzelle, Detailstufe). loose (Autos, Verkehr): Texturkoordinaten, Tangenten und Index trennen nicht, so
## landen selbst gebaute Teile (runde Quader, Haut, Flügel) und fertige Formen (Quader, Zylinder) desselben
## Materials in einem Draw Call; merge_buckets gleicht den Index an.
static func collect_static(n: Node, xf: Transform3D, stops: Dictionary, canon: Dictionary, buckets: Dictionary, extra: Callable, loose := false) -> void:
	for c in n.get_children():
		collect_one(c, xf, stops, canon, buckets, extra, loose)


## Ein Kind (mit allem darunter) in die Eimer sortieren; xf = Lage des Elternknotens
static func collect_one(c: Node, xf: Transform3D, stops: Dictionary, canon: Dictionary, buckets: Dictionary, extra: Callable, loose := false) -> void:
	if stops.has(c) or not c is Node3D:
		return
	var cxf: Transform3D = xf * (c as Node3D).transform
	if c is MeshInstance3D:
		var mi := c as MeshInstance3D
		if mi.mesh == null or mi.get_script() != null or mi.get_child_count() > 0 or not mi.visible or mi.material_overlay \
				or mi.transparency > 0.0 or mi.visibility_range_end > 0.0 or mi.has_meta("no_merge"):
			return
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
			var key := [pt[0], surface_format(mi.mesh, pt[1], loose), extra.call(mi, cxf)]
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append([mi.mesh, pt[1], cxf, mi])
	elif c.get_class() == "Node3D" and c.get_script() == null and (c as Node3D).visible:
		collect_static(c, cxf, stops, canon, buckets, extra, loose)


## Verschmilzt jeden Eimer mit mindestens zwei Teilen zu einem Mesh unter parent und entfernt die Einzelteile.
## Liefert die neuen MeshInstances.
static func merge_buckets(parent: Node3D, buckets: Dictionary, loose := false) -> Array:
	var job := merge_begin(buckets, loose)
	while not merge_step(parent, job, -1):
		pass
	return job["made"]


## Verschmelzen in Stücken (Ladebildschirm): merge_begin() legt den Auftrag an, merge_step() arbeitet höchstens
## budget_ms (-1 = alles) und gibt true zurück, wenn alles fertig ist; job["made"] sind dann die neuen Flächen,
## job["done"] / job["keys"].size() ist der Fortschritt.
static func merge_begin(buckets: Dictionary, loose := false) -> Dictionary:
	return {"buckets": buckets, "keys": buckets.keys(), "done": 0, "loose": loose, "made": [], "gone": {}, "drop": null, "dropped": 0}


static func merge_step(parent: Node3D, job: Dictionary, budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var buckets: Dictionary = job["buckets"]
	var keys: Array = job["keys"]
	var gone: Dictionary = job["gone"]
	var loose: bool = job["loose"]
	while job["done"] < keys.size():
		if budget_ms >= 0 and Time.get_ticks_msec() - t0 >= budget_ms:
			return false
		var key = keys[job["done"]]
		job["done"] += 1
		var items: Array = buckets[key]
		if items.size() < 2:
			continue
		# gemischt mit und ohne Index (nur loose): ohne Index erst indizieren, sonst fielen sie beim Anhängen weg
		var idx := []
		var mixed := false
		if loose:
			for it in items:
				idx.append((it[0] as Mesh).surface_get_arrays(it[1])[Mesh.ARRAY_INDEX] != null)
			mixed = idx.has(true) and idx.has(false)
		var st := SurfaceTool.new()
		for k in items.size():
			var it: Array = items[k]
			if mixed and not idx[k]:
				var tmp := SurfaceTool.new()
				tmp.append_from(it[0], it[1], it[2])
				tmp.index()
				st.append_from(tmp.commit(), 0, Transform3D.IDENTITY)
			else:
				st.append_from(it[0], it[1], it[2])
			gone[it[3]] = true
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = key[0]
		mi.set_meta("merge_extra", key[2])
		parent.add_child(mi)
		job["made"].append(mi)
	# Teile mit mehreren Flächen nur entfernen, wenn alle Flächen verschmolzen wurden. Seit 2.36 (loose: Autos, Verkehr,
	# Umfahrbares): eine allein gebliebene Fläche eines sonst verschmolzenen Teils wird als eigenes Mesh herausgelöst. Bis
	# 2.35 blieb das ganze Teil stehen, seine verschmolzenen Flächen wurden doppelt gezeichnet (bei den Autos oft die
	# ganze Karosserie-Haut, wenn eine Fläche ein eigenes Material hatte).
	if job["drop"] == null:
		for key in buckets:
			if buckets[key].size() < 2:
				for it in buckets[key]:
					if loose and gone.has(it[3]) and (it[0] as Mesh).get_surface_count() > 1:
						var st1 := SurfaceTool.new()
						st1.append_from(it[0], it[1], it[2])
						var one := MeshInstance3D.new()
						one.mesh = st1.commit()
						one.material_override = key[0]
						one.set_meta("merge_extra", key[2])
						parent.add_child(one)
						job["made"].append(one)
					else:
						gone.erase(it[3])
		job["drop"] = gone.keys()
	var drop: Array = job["drop"]
	while job["dropped"] < drop.size():
		if budget_ms >= 0 and Time.get_ticks_msec() - t0 >= budget_ms:
			return false
		var old = drop[job["dropped"]]
		job["dropped"] += 1
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.free()
	return true


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
static func surface_format(mesh: Mesh, si: int, loose := false) -> Array:
	var a := mesh.surface_get_arrays(si)
	if loose:
		return [a[Mesh.ARRAY_NORMAL] != null, a[Mesh.ARRAY_COLOR] != null, a[Mesh.ARRAY_TEX_UV2] != null]
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


## Scheiben (seit 2.25): getönt, glatt, mit leichter falscher Spiegelung der Stadt (shaders/car_glass.gdshader)
static func glass_mat(tint: Color, mirror: float) -> ShaderMaterial:
	var key := "glass_%s_%.1f" % [tint.to_html(false), mirror]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := ShaderMaterial.new()
	m.shader = GLASS_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("mirror", mirror)
	m.set_meta("lod_color", tint)
	_mesh_cache[key] = m
	return m


## Glatter Bogen (Verbreiterung) entlang pts [[Mittelpunkt an der Flanke, Richtung vom Radmittelpunkt weg]]: flaches,
## gerundetes Profil, out m nach außen, depth m nach oben/außen über dem Radlauf
static func _arc_strip(pts: Array, side: int, out: float, depth: float) -> ArrayMesh:
	# Profil (seitlich, radial) mit runder Außenkante
	var prof := [Vector2(0.0, -0.004), Vector2(out * 0.55, -0.002), Vector2(out * 0.9, 0.006), Vector2(out, depth * 0.45),
		Vector2(out * 0.85, depth * 0.9), Vector2(out * 0.4, depth), Vector2(0.0, depth)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	for p in pts:
		var c: Vector3 = p[0]
		var rad: Vector3 = p[1]
		var ring := []
		for q in prof:
			ring.append(c + Vector3(side * q.x, 0, 0) + rad * q.y)
		rings.append(ring)
	for i in rings.size() - 1:
		for j in prof.size() - 1:
			var a: Vector3 = rings[i][j]
			var b: Vector3 = rings[i + 1][j]
			var c2: Vector3 = rings[i + 1][j + 1]
			var d: Vector3 = rings[i][j + 1]
			var n := (b - a).cross(d - a).normalized()
			# nach außen zeigen lassen (weg von der Flanke bzw. nach oben)
			var outward := Vector3(side, 0, 0) + (pts[i][1] as Vector3)
			if n.dot(outward) < 0.0:
				n = -n
				var t := b
				b = d
				d = t
			for v in [a, b, c2, a, c2, d]:
				st.set_normal(n)
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## Mittelpunkt und Größe der Leuchten mit diesem Material, je Seite (links/rechts), im Body-Raum. Liefert
## [{"c": Mitte, "size": Ausdehnung, "z": vorderste bzw. hinterste Stelle}]
static func _lamp_spots(body: Node3D, lamp: Material) -> Array:
	var sides := {-1: [], 1: []}
	var stack: Array = [body]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not nd is MeshInstance3D:
			continue
		var mi := nd as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != body:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(si)
			if m != lamp:
				continue
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				sides[1 if w.x > 0.0 else -1].append(w)
	var out := []
	for sd in sides:
		var all_pts: Array = sides[sd]
		if all_pts.is_empty():
			continue
		# nur die Leuchten unten am Bug bzw. Heck (eine dritte Bremsleuchte am Dach zählt nicht)
		var ymin := INF
		for q in all_pts:
			ymin = minf(ymin, (q as Vector3).y)
		var pts := all_pts.filter(func(q): return (q as Vector3).y < ymin + 0.3)
		var lo: Vector3 = pts[0]
		var hi: Vector3 = pts[0]
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
		out.append({"c": (lo + hi) / 2.0, "size": hi - lo, "zmin": lo.z, "zmax": hi.z})
	return out


## Leuchthöfe (seit 2.25): weiche, additive Lichtflecken auf den Scheinwerfern und Rückleuchten, damit man sie als
## Lichter erkennt (bis 2.24 nur helle Flächen). Nur von vorn bzw. hinten sichtbar, wie echte Lampen.
static func _lamp_glows(body: Node3D, heads: Array, tails: Array, light_c: Color) -> void:
	for kind in [[heads, -1.0, Color(light_c.r, light_c.g, light_c.b) * 0.38], [tails, 1.0, Color(1.0, 0.08, 0.04) * 0.45]]:
		var spots: Array = kind[0]
		if spots.is_empty():
			continue
		var dir: float = kind[1]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for sp in spots:
			var sz: Vector3 = sp["size"]
			# eng an der Leuchte (seit 2.27; vorher fast doppelt so groß und rund, das wirkte wie eine Kugel vor der Lampe)
			var w := clampf(sz.x * 1.15 + 0.08, 0.16, 1.4)
			var h := clampf(sz.y * 1.3 + 0.06, 0.08, 0.3)
			var c: Vector3 = sp["c"]
			c.z = (sp["zmin"] if dir < 0.0 else sp["zmax"]) + dir * 0.04
			var hx := w / 2.0
			var hy := h / 2.0
			# Viereck mit Vorderseite nach außen (vorn: -Z, hinten: +Z)
			var q := [Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)]
			var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			# Godot: Vorderseite im Uhrzeigersinn, von außen gesehen
			var order := [0, 1, 2, 0, 2, 3] if dir < 0.0 else [0, 2, 1, 0, 3, 2]
			for i in order:
				st.set_uv(uv[i])
				st.set_normal(Vector3(0, 0, dir))
				st.add_vertex(c + q[i])
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_texture = _lamp_halo_texture()
		gm.albedo_color = kind[2]
		gm.disable_receive_shadows = true
		gm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("glow", dir)
		body.add_child(mi)


## Lichtteppiche (seit 2.25): die Scheinwerfer legen einen hellen Kegel vor das Auto auf die Straße, die Rückleuchten
## einen roten Schein dahinter. Decal (liegt auf dem Asphalt, auch am Hang), im Browser additive Flächen.
## Seit 2.27.1 vorn nur noch im Browser: mit dem vollen Renderer leuchtet der echte Scheinwerfer (SpotLight) schon auf die
## Straße, der Teppich lag dort zusätzlich als heller, scharf begrenzter Kasten vor dem Auto (in Aufnahmen sehr störend).
static func _light_pools(root: Node3D, W: float, L: float, light_c: Color) -> void:
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if OS.get_cmdline_user_args().has("--nopool"):
		return  # nur Aufnahmen: ganz ohne Lichtteppich
	var specs := [[_halo_texture(), Vector3(W * 0.95, 1.4, 1.7), L / 2.0 + 0.45, Color(1.0, 0.06, 0.03), 0.22]]
	if compat:
		specs.push_front([_beam_texture(), Vector3(W + 1.6, 1.6, 22.0), -L / 2.0 - 11.2, light_c, 0.7])
	for spec in specs:
		var size: Vector3 = spec[1]
		if compat:
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			gm.albedo_texture = spec[0]
			var c: Color = spec[3]
			gm.albedo_color = Color(c.r, c.g, c.b) * (0.35 * spec[4])
			gm.disable_receive_shadows = true
			var pm := PlaneMesh.new()
			pm.size = Vector2(size.x, size.z)
			var gl := MeshInstance3D.new()
			gl.mesh = pm
			gl.material_override = gm
			gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gl.position = Vector3(0, 0.035, spec[2])
			root.add_child(gl)
			continue
		var dc := Decal.new()
		dc.size = size
		dc.texture_emission = spec[0]
		dc.emission_energy = spec[4] * 0.4
		dc.modulate = spec[3]
		dc.albedo_mix = 0.0
		dc.upper_fade = 0.3
		dc.lower_fade = 0.3
		dc.cull_mask = 0xFFFFF & ~(CAR_LAYER | SMOKE_LAYER)
		dc.distance_fade_enabled = true
		dc.distance_fade_begin = 80.0
		dc.distance_fade_length = 20.0
		dc.position = Vector3(0, 0.3, spec[2])
		root.add_child(dc)


static var _halo_tex: ImageTexture
static var _beam_tex: ImageTexture


## Leuchthof um eine Lampe: weich, ohne hellen Kern (das Leuchten der Lampe selbst macht ihr Material)
static var _lamp_halo_tex: ImageTexture


static func _lamp_halo_texture() -> ImageTexture:
	if _lamp_halo_tex:
		return _lamp_halo_tex
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var d := Vector2((x + 0.5) / 32.0 - 1.0, (y + 0.5) / 16.0 - 1.0).length()
			var k := pow(maxf(1.0 - d, 0.0), 1.6)
			img.set_pixel(x, y, Color(k, k, k, k))
	_lamp_halo_tex = ImageTexture.create_from_image(img)
	return _lamp_halo_tex


## Leuchthof: heller Kern, weich auslaufend
static func _halo_texture() -> ImageTexture:
	if _halo_tex:
		return _halo_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d := Vector2((x + 0.5) / 32.0 - 1.0, (y + 0.5) / 32.0 - 1.0).length()
			var k := clampf(pow(maxf(1.0 - d, 0.0), 2.2) + 0.35 * pow(maxf(1.0 - d * 2.2, 0.0), 1.5), 0.0, 1.0)
			img.set_pixel(x, y, Color(k, k, k, k))
	_halo_tex = ImageTexture.create_from_image(img)
	return _halo_tex


## Scheinwerferkegel auf der Straße: v = 1 am Auto, 0 weit vorn; wird nach vorn breiter und blasser
static func _beam_texture() -> ImageTexture:
	if _beam_tex:
		return _beam_tex
	var img := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		var a := 1.0 - (y + 0.5) / 128.0  # 0 am Auto, 1 weit vorn
		var along := smoothstep(0.0, 0.08, a) * (1.0 - smoothstep(0.35, 1.0, a))
		var hw := 0.3 + 0.16 * a  # fast so breit wie das Auto, nach vorn nur wenig breiter (nicht zur Seite hinaus)
		for x in 64:
			var u := absf((x + 0.5) / 64.0 - 0.5)
			var across := 1.0 - smoothstep(hw * 0.55, hw, u)
			var k := along * across
			img.set_pixel(x, y, Color(k, k, k, k))
	_beam_tex = ImageTexture.create_from_image(img)
	return _beam_tex


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
	# Draufsicht: runde Ecken, Kotflügel vorn, Hüften hinten. W ist die größte Breite (über den Hüften): Hüften und
	# Kotflügel-Buckel gehen von der Grundbreite ab, aufgeschraubte Verbreiterungen (overfenders) sitzen noch darauf.
	var w := W / 2.0 - maxf(S["hips"], 0.015) - (0.045 if S.get("overfenders", false) else 0.0)
	w -= S["round_f"] * pow(maxf(1.0 - t / 0.14, 0.0), 2.0)
	w -= S["round_r"] * pow(maxf(1.0 - (1.0 - t) / 0.12, 0.0), 2.0)
	var hip: float = (S["hips"] + flare) * exp(-pow((t - tr) / 0.1, 2.0))
	var fend: float = (0.015 + flare) * exp(-pow((t - tf) / 0.08, 2.0))
	var w2 := w + hip + fend
	var w3 := w2 - 0.05 - hip * 0.5
	# Radausschnitt (Mitte auf Werks-Radhöhe; ein größeres Rad hebt die Karosserie, der Lauf wird weiter: arch_r)
	var ra := arch_r(S)
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
	var w_in := w2 - 0.36 if arch else x1  # Innenwand des Radhauses, mit Abstand zum breitesten Reifen
	var pts := PackedVector2Array([
		Vector2(0.0, C), Vector2(w_in, C), Vector2(w_in, ybot), Vector2(x1, ybot), Vector2(w2, y2),
		Vector2((w2 + w3) / 2.0 + 0.012, (y2 + belt) / 2.0), Vector2(w3, belt), p4,
		Vector2(p4.x * 0.55, top + (p4.y - top) * 0.3025), Vector2(p4.x * 0.18, top + (p4.y - top) * 0.0324),
		Vector2(0.0, top)])
	# Doppelbuckel-Dach (bubble, seit 2.36): die Dachmitte liegt etwas tiefer als die Buckel über den Sitzen
	var bub: float = S.get("bubble", 0.0)
	if bub > 0.0 and t > S["rf"] and t < S["rr"]:
		var kb := sin(PI * (t - S["rf"]) / (S["rr"] - S["rf"]))
		pts[10] = pts[10] - Vector2(0.0, bub * kb)
		pts[9] = pts[9] - Vector2(0.0, bub * 0.6 * kb)
	# Bug und Heck mit runden Kanten (Viertelkreis, Radius edge_f/edge_r): in den letzten Zentimetern rücken Flanke,
	# Schulter und Dach nach innen, die Stirnfläche wird kleiner. Bis 2.20 endete das Auto in einer senkrechten Wand
	# mit scharfer Kante. Die Unterkante bleibt (Lippe, Einlass, Diffusor hängen dort), vorn auch die Haubenkante.
	var rad: float = S.get("edge_f", 0.075) if t < 0.5 else S.get("edge_r", 0.065)
	var de := minf(t, 1.0 - t) * L
	if de < rad:
		var ins := rad - sqrt(maxf(rad * rad - (rad - de) * (rad - de), 0.0))
		var q := pts.duplicate()
		for j in range(3, 11):
			var nrm := Vector2(0.0, 1.0)
			if j < 10:
				var d1 := pts[j + 1] - pts[j]
				var n1 := Vector2(d1.y, -d1.x).normalized()
				nrm = n1
				if j > 3:
					var d0 := pts[j] - pts[j - 1]
					nrm = (n1 + Vector2(d0.y, -d0.x).normalized()).normalized()
			# vorn rückt alles nur seitlich ein: die Haubenkante bleibt auf ihrer Höhe (dort sitzen bei vielen Autos die
			# Scheinwerfer bis zur Oberkante), die Ecken zur Seite werden rund, und der Umriss kann sich nicht kreuzen
			var dv := Vector2(nrm.x, 0.0) if t < 0.5 else nrm
			q[j] = pts[j] - dv * ins * (0.5 if j == 3 else 1.0)
		q[10].x = 0.0
		pts = q
	return {"p": pts, "g": g, "t": t, "z": z}


## Querschnitt verfeinern: ab dem Schweller (Punkt 3) bis zur Dachmitte eine Kurve durch die Punkte (Catmull-Rom,
## zentripetal: läuft durch jeden Punkt, ohne Schlaufen), je Band sub Teilstücke. Punkte 0–3 (Unterboden, Radhaus)
## bleiben. Zur Dachmitte hin waagerecht (gespiegelter Nachbarpunkt).
## Seit 2.36 mit eigenen Teilpunkten für die Seitenscheibe (Band 6: schmale Streifen unten und oben für Dichtung und
## Rahmen) und das Band über der Schulter (7: schmaler Streifen außen für A-Säule und Dachkante), sonst sub je Band.
static func _refine(p: PackedVector2Array, sub: int) -> PackedVector2Array:
	var out := PackedVector2Array([p[0], p[1], p[2], p[3]])
	for j in range(3, 10):
		var a := p[j]
		var b := p[j + 1]
		var pa := p[j - 1] if j > 3 else a - (b - a)
		var pb := p[j + 2] if j < 9 else Vector2(-p[9].x, p[9].y)
		var ks: Array = KNOTS.get(j, [])
		if ks.is_empty():
			for k in range(1, sub + 1):
				ks.append(float(k) / sub)
		for f in ks:
			out.append(_cr(pa, a, b, pb, f) if f < 1.0 else b)
	return out


## Teilpunkte der Bänder mit Rahmen (Anteil 0..1 entlang des Bandes, der letzte ist das Bandende); siehe _refine, _skin
const KNOTS := {6: [0.075, 0.37, 0.66, 0.925, 1.0], 7: [0.16, 0.45, 0.74, 1.0]}


## Index des ursprünglichen Punkts k (3..10) im verfeinerten Querschnitt
static func _ref_idx(k: int) -> int:
	var i := 3
	for b in range(3, k):
		i += (KNOTS[b] as Array).size() if KNOTS.has(b) else SHELL_SUB
	return i


## Zentripetale Catmull-Rom-Kurve zwischen p1 und p2 bei f (0..1)
static func _cr(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, f: float) -> Vector2:
	var t1 := sqrt(maxf(p0.distance_to(p1), 1e-5))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 1e-5))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 1e-5))
	var u := lerpf(t1, t2, f)
	var a1 := p0 * (t1 - u) / t1 + p1 * u / t1
	var a2 := p1 * (t2 - u) / (t2 - t1) + p2 * (u - t1) / (t2 - t1)
	var a3 := p2 * (t3 - u) / (t3 - t2) + p3 * (u - t2) / (t3 - t2)
	var b1 := a1 * (t2 - u) / t2 + a2 * u / t2
	var b2 := a2 * (t3 - u) / (t3 - t1) + a3 * (u - t1) / (t3 - t1)
	return b1 * (t2 - u) / (t2 - t1) + b2 * (u - t1) / (t2 - t1)


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


## Hochgeklappte Klappscheinwerfer (seit 2.36, Tatsumaki auf der Straße): je Seite ein Gehäuse, das vorn aus der Öffnung
## in der Haube steht (oben lackierter Deckel, vorn dunkler Rahmen mit Glas), dahinter die dunkle Öffnung. Liefert die
## Höhe der Lampen (für den Scheinwerfer).
static func _popup_pods(body: Node3D, S: Dictionary, W: float, L: float, flare: float, paint: Material, lamp: Material,
		dark: Material, x_c: float, w: float, z0: float, z1: float) -> float:
	var zf := -L / 2.0
	var yl := 0.0
	var tm := (z0 + z1) / 2.0 / L
	var slope := atan2(_top_c(S, z1 / L) - _top_c(S, z0 / L), z1 - z0)
	for s in [-1, 1]:
		var q := _top_pt(S, tm, s * x_c, W, L, flare)
		var base: Vector3 = q[0]
		var hole := _add(body, rbox(Vector3(w, 0.01, z1 - z0), 0.004), dark, base + Vector3(0, 0.001, 0))
		hole.rotation.x = -slope
		var qf := _top_pt(S, (z0 + 0.03) / L, s * x_c, W, L, flare)
		var pod := Node3D.new()
		pod.position = Vector3(s * x_c, (qf[0] as Vector3).y, zf + z0 + 0.03)
		body.add_child(pod)
		_add(pod, rbox(Vector3(w - 0.02, 0.135, 0.13), 0.02), paint, Vector3(0, 0.06, 0.06))
		_add(pod, _rplate(w - 0.05, 0.095, 0.02, 0.01), dark, Vector3(0, 0.065, -0.008))
		_add(pod, _rplate(w - 0.075, 0.074, 0.016, 0.01), lamp, Vector3(0, 0.065, -0.012))
		yl = (qf[0] as Vector3).y + 0.065
	return yl


## x der Flanke in Höhe y beim Querschnitt t (zwischen Schweller und Schulter)
static func _side_x(S: Dictionary, t: float, y: float, W: float, L: float, flare: float) -> float:
	# auf der verfeinerten Kurve (wie die Haut, _shell): sonst liegen Leuchten an den runden Ecken in der Haut
	var p := _refine(_section(S, t, W, L, flare)["p"], SHELL_SUB)
	var top := _ref_idx(7)  # ursprünglicher Punkt 7 (Schulter)
	if y <= p[3].y:
		return p[3].x
	for j in range(3, top):
		if y <= p[j + 1].y:
			return lerpf(p[j].x, p[j + 1].x, (y - p[j].y) / maxf(p[j + 1].y - p[j].y, 1e-4))
	return p[top].x


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


## Material eines Hautstücks (Band b zwischen Punkt b und b+1) bei t; f = Lage im Band (0 unten/außen .. 1 oben/innen)
## Seit 2.36 Glas mit Rahmen: Seitenscheiben mit Dichtung an der Gürtellinie, Rahmen oben und hinten, dunkle B-Säule
## (_pillars); Frontscheibe zwischen A-Säulen in Wagenfarbe, oben ein dunkler Siebdruckrand, davor die dunkle
## Windlauf-Abdeckung; Heckscheibe ebenso mit Dachkante in Wagenfarbe und dunklem Rand. Bis 2.35 lief das Glas als
## eine Kuppel ohne Säulen um das ganze Dach (wirkte wie ein Spielzeugauto).
static func _skin(S: Dictionary, b: int, t: float, g: float, seam: bool, vinyl: int, carbon_hood := false, f := 0.5, L := 4.4) -> String:
	if b <= 2:
		return "under"
	if seam and b <= 5:
		return "seam"
	var cowl: float = S["cowl"]
	var rf: float = S["rf"]
	var a_post: bool = b == 7 and f < KNOTS[7][0]
	if b == 6 and t > cowl and t < S["cp"] and g > 0.25:
		if f < KNOTS[6][0] or f > KNOTS[6][3] or t > float(S["cp"]) - 0.022 / L:
			return "frame"
		for pc in _pillars(S):
			if absf(t - pc[0]) < pc[1] / L:
				return "pillar"
		return "glass"
	if b >= 7 and t > cowl and t < rf:
		if a_post:
			return "paint"
		return "cowl" if t > rf - 0.028 / L else "glass"
	if b >= 7 and not a_post and t > cowl - 0.04 / L and t <= cowl:
		return "cowl"  # Windlauf vor der Scheibe
	# Stoffverdeck: Dach, kleines Heckfenster, hinterer Teil der Seite
	if S.get("softtop", false) and t >= rf and t < S["ge"] and (b >= 7 or (b == 6 and g > 0.25)):
		return "glass" if b >= 8 and t > S["rr"] + 0.02 and t < S["ge"] - 0.015 else "top"
	if b >= 7 and t > S["rr"] and t < S["ge"]:
		if a_post:
			return "paint"
		return "cowl" if t < float(S["rr"]) + 0.022 / L or t > float(S["ge"]) - 0.018 / L else "glass"
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
	return "paint"


## Dunkle Säulen in den Seitenscheiben: [t der Mitte, halbe Breite in m]. Viertürer: B-Säule zwischen den Türen und ein
## Steg vor dem hinteren Seitenfenster; Coupés: ein Steg zwischen Tür- und hinterem Seitenfenster, wenn es eins gibt.
static func _pillars(S: Dictionary) -> Array:
	var d: Array = S["doors"]
	var cp: float = S["cp"]
	if d.size() >= 3:
		var out := [[d[1], 0.036]]
		if cp - d[2] > 0.025:
			out.append([d[2], 0.016])
		return out
	if cp - d[1] > 0.035:
		return [[d[1], 0.02]]
	return []


## Karosserie-Haut aus Querschnitten: Frontschürze, Mittelteil, Heckschürze als eigene Meshes. Fugen (Schürzen,
## Türen) sind schmale dunkle Bänder zwischen zwei dicht liegenden Querschnitten.
static func _shell(body: Node3D, S: Dictionary, W: float, L: float, flare: float, vinyl: int, mats: Dictionary, carbon_hood := false) -> void:
	var seams: Array = [FRONT_SEAM, REAR_SEAM] + S["doors"]
	var ra := arch_r(S)
	# Feste Querschnitte: Fugen (zwei dicht beieinander) und Radkanten (senkrechter Übergang)
	var must := []
	for sm in seams:
		must.append_array([sm, sm + 0.006 / L])
	for wz in [-L / 2.0 + axle(S), L / 2.0 - axle(S)]:
		for e in [-1.0, 1.0]:
			must.append_array([(wz + e * (ra - 0.002)) / L + 0.5, (wz + e * (ra + 0.002)) / L + 0.5])
	# Ränder von Glas, Rahmen und Säulen (_skin)
	must.append_array([S["cowl"], S["cowl"] - 0.04 / L, S["rf"], S["rf"] - 0.028 / L, S["rr"], S["rr"] + 0.022 / L,
		S["ge"], S["ge"] - 0.018 / L, S["cp"], S["cp"] - 0.022 / L])
	for pc in _pillars(S):
		must.append_array([pc[0] - pc[1] / L, pc[0] + pc[1] / L])
	var extra := []
	var n := int(L / 0.09)
	for i in n + 1:
		extra.append(float(i) / n)
	extra.append_array([0.004, 0.012, 0.025, 0.045, 0.07, 0.955, 0.975, 0.988, 0.996])
	# Rundung an Bug und Heck: dichte Querschnitte in den letzten Zentimetern
	for d in [0.002, 0.006, 0.012, 0.02, 0.03, 0.042, 0.056, 0.07]:
		extra.append_array([d / L, 1.0 - d / L])
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
	# Querschnitte verfeinern (runde Flanken, Schultern, Dachkanten); band[k] = ursprüngliches Band des Teilstücks k
	# (Material, Fugen, Folien bleiben, wo sie waren)
	var band := [0, 1, 2]
	var bandf := [0.5, 0.5, 0.5]  # Lage des Teilstücks im Band (Mitte, 0..1): Rahmen und Säulen in _skin
	for b in range(3, 10):
		var ks: Array = KNOTS.get(b, [])
		if ks.is_empty():
			for k in SHELL_SUB:
				ks.append(float(k + 1) / SHELL_SUB)
		var f0 := 0.0
		for f in ks:
			band.append(b)
			bandf.append((f0 + float(f)) / 2.0)
			f0 = f
	for sc in secs:
		sc["p"] = _refine(sc["p"], SHELL_SUB)
	var ns := secs.size()
	var NP: int = (secs[0]["p"] as PackedVector2Array).size()
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
			# außen = weg von einem Punkt in der Wagenmitte. Für die Außenhaut liegt er seit 2.36 tiefer (0,36 m statt
			# 0,55 m): bei flacher Nase (Ronin, Tatsumaki) lag die Haubenvorderkante darunter, ihre Flächen zeigten nach
			# innen und fehlten (man sah in den Wagen hinein)
			if fn.dot(Vector3(mid.x, mid.y - (0.55 if j < 3 else 0.36), 0.0)) < 0.0:
				fn = -fn
			fnorm[i].append(fn)
			if j >= 3:
				for q in [[i, j], [i, j + 1], [i + 1, j], [i + 1, j + 1]]:
					vnorm[q[0]][q[1]] += fn
	# Dreiecke je Teil und Material als Listen (seit 2.36 statt SurfaceTool je Punkt: die Haut ist der teuerste Schritt
	# beim Bauen, so geht es gut doppelt so schnell)
	var parts := {"FrontBumper": {}, "Shell": {}, "RearBumper": {}}
	var get_buf := func(part: String, key: String) -> Array:
		if not parts[part].has(key):
			parts[part][key] = [[], []]
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
		var last_key := ""
		var bv: Array = []
		var bn: Array = []
		for j in NP - 1:
			var fn: Vector3 = fnorm[i][j]
			if fn.length_squared() < 1e-12:
				continue
			var bj: int = band[j]
			var key := _skin(S, bj, tm, gm, is_seam, vinyl, carbon_hood, bandf[j], L)
			if key != last_key:
				var buf: Array = get_buf.call(part, key)
				bv = buf[0]
				bn = buf[1]
				last_key = key
			var p0: Vector3 = V.call(i, j)
			var p1: Vector3 = V.call(i, j + 1)
			var p2: Vector3 = V.call(i + 1, j + 1)
			var p3: Vector3 = V.call(i + 1, j)
			var n0 := fn.normalized()
			var n1 := n0
			var n2 := n0
			var n3 := n0
			if j >= 3:
				var v0: Vector3 = vnorm[i][j]
				var v1: Vector3 = vnorm[i][j + 1]
				var v2: Vector3 = vnorm[i + 1][j + 1]
				var v3: Vector3 = vnorm[i + 1][j]
				n0 = v0.normalized() if v0.length_squared() > 1e-12 else n0
				n1 = v1.normalized() if v1.length_squared() > 1e-12 else n1
				n2 = v2.normalized() if v2.length_squared() > 1e-12 else n2
				n3 = v3.normalized() if v3.length_squared() > 1e-12 else n3
			# Umlaufsinn je Dreieck (die gespiegelte Seite läuft andersherum): an den verdrehten Vierecken der Radläufe
			# liegt das zweite Dreieck andersherum als das erste; einmal je Viereck entschieden, zeigte es nach innen
			# und fehlte (vier kleine Löcher je Auto)
			var m := Vector3(-1.0, 1.0, 1.0)
			if (p2 - p0).cross(p1 - p0).dot(fn) < 0.0:
				bv.append_array([p0, p2, p1, p0 * m, p1 * m, p2 * m])
				bn.append_array([n0, n2, n1, n0 * m, n1 * m, n2 * m])
			else:
				bv.append_array([p0, p1, p2, p0 * m, p2 * m, p1 * m])
				bn.append_array([n0, n1, n2, n0 * m, n2 * m, n1 * m])
			if (p3 - p0).cross(p2 - p0).dot(fn) < 0.0:
				bv.append_array([p0, p3, p2, p0 * m, p2 * m, p3 * m])
				bn.append_array([n0, n3, n2, n0 * m, n2 * m, n3 * m])
			else:
				bv.append_array([p0, p2, p3, p0 * m, p3 * m, p2 * m])
				bn.append_array([n0, n2, n3, n0 * m, n3 * m, n2 * m])
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
		if tri.is_empty():
			# Umriss schneidet sich (sollte nicht vorkommen): Fächer um die Mitte statt eines Lochs
			var ctr := Vector2.ZERO
			for v in clean:
				ctr += v
			clean.append(ctr / clean.size())
			for k in clean.size() - 1:
				tri.append_array([clean.size() - 1, k, (k + 1) % (clean.size() - 1)])
		var z: float = secs[e[0]]["z"]
		var nz := Vector3(0, 0, e[2])
		var buf: Array = get_buf.call(e[1], "paint")
		for k in range(0, tri.size(), 3):
			var a := Vector3(clean[tri[k]].x, clean[tri[k]].y, z)
			var b := Vector3(clean[tri[k + 1]].x, clean[tri[k + 1]].y, z)
			var c := Vector3(clean[tri[k + 2]].x, clean[tri[k + 2]].y, z)
			if (c - a).cross(b - a).dot(nz) < 0.0:
				(buf[0] as Array).append_array([a, c, b])
			else:
				(buf[0] as Array).append_array([a, b, c])
			(buf[1] as Array).append_array([nz, nz, nz])
	for part in parts:
		var mesh := ArrayMesh.new()
		for key in parts[part]:
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(parts[part][key][0])
			arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(parts[part][key][1])
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
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


## Schmutzfänger hinter einem Rad (zi -1 vorn, 1 hinten): Mitte gut 13 cm innerhalb der Kotflügelkante, wo der Reifen läuft
## (bis 2.36 halbe Katalogbreite minus 18 cm: an den schlankeren Karosserien stünde er sonst über)
static func _flap_x(S: Dictionary, W: float, L: float, flare: float, zi: int) -> float:
	var t := axle(S) / L if zi < 0 else 1.0 - axle(S) / L
	return (_section(S, t, W, L, flare)["p"] as PackedVector2Array)[4].x - 0.135


## Radius der Radläufe (Mitte auf Werks-Radhöhe): ab Werk 4,5 cm über dem Reifen; braucht ein größeres Rad mehr Platz,
## setzt build() arch_r (wheel_fit)
static func arch_r(S: Dictionary) -> float:
	return S.get("arch_r", wheel_r(S) + 0.045)


## Motor hinten (Mittel- oder Heckmotor): Lamellen und Motorraum hinten, Kofferraum vorn
static func engine_rear(S: Dictionary) -> bool:
	return S.get("mid", false) or S.get("rear_engine", false)


## Animiert Räder, Lenkung, Karosserie-Neigung und Auspuffflammen. wheel_v (optional, Vector2): Umfangsgeschwindigkeit
## der Räder vorn und hinten in m/s, wenn sie nicht zum Tempo passt (blockiert = 0, durchdrehend = mehr als speed).
## fire: Fehlzündung beim Schalten oder Gaswegnehmen (0..1, der Aufrufer lässt sie schnell abklingen).
static func animate(car: Node3D, speed: float, steer: float, roll: float, pitch: float, nitro_on: bool, delta: float, wheel_v = null, fire := 0.0) -> void:
	for p in car.get_meta("front_pivots"):
		p.rotation.y = -steer * 0.5
	var wr: float = car.get_meta("wheel_r", WHEEL_R)
	var period: float = car.get_meta("rim_period", TAU / 5.0)
	var sp: Array = car.get_meta("spinners")
	var bl: Array = car.get_meta("blurs", [])
	for i in sp.size():
		var v := speed
		if wheel_v is Vector2:
			v = wheel_v.x if i < 2 else wheel_v.y
		# Das Bild kommt 60-mal je Sekunde: dreht sich ein Rad dazwischen um mehr als eine halbe Speichenteilung,
		# scheint es zu stehen oder rückwärts zu laufen. Darüber dreht es sichtbar nur noch so schnell wie gerade noch
		# erkennbar, und die Unschärfescheibe blendet ein (wie auf echten Aufnahmen).
		var step := v / wr * delta
		var lim := period * 0.42
		var sn: Node3D = sp[i]
		sn.rotation.x = wrapf(sn.rotation.x - clampf(step, -lim, lim), -PI, PI)
		if i < bl.size():
			var k := smoothstep(period * 0.12, period * 0.4, absf(step))
			var b: MeshInstance3D = bl[i]
			b.visible = k > 0.01
			if b.visible:
				(b.material_override as StandardMaterial3D).albedo_color.a = k
	var body: Node3D = car.get_meta("body")
	body.rotation.z = lerpf(body.rotation.z, roll, 8.0 * delta)
	body.rotation.x = lerpf(body.rotation.x, pitch, 6.0 * delta)
	var mats: Array = car.get_meta("flame_mats", [])
	var pop := fire > 0.05 and not nitro_on
	for f in car.get_meta("flames"):
		f.visible = nitro_on or pop
		if nitro_on:
			if mats.size() > 1:
				f.material_override = mats[0]
			f.scale = Vector3.ONE * randf_range(0.7, 1.3)
			f.position.z = f.get_meta("z0", f.position.z - 0.35) + 0.35
		elif pop:
			# Fehlzündung: kurz, an der Rohrmündung, orange
			if mats.size() > 1:
				f.material_override = mats[1]
			var ln := (0.25 + 0.3 * clampf(fire, 0.0, 1.0)) * randf_range(0.85, 1.15)
			f.scale = Vector3(1.1, ln, 1.1)
			f.position.z = f.get_meta("z0", f.position.z) + 0.35 * ln


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


## Quader mit runden Kanten und Ecken (Spoiler, Endplatten, Schweller, Lippen, Spiegel): je Fläche ein 4x4-Gitter
## (Kante, Beginn der Rundung, Beginn der Rundung, Kante), die Randpunkte liegen auf dem Radius, die Normalen zeigen
## aus der Rundung -> weiche Glanzlichter statt Lego-Kante. r < 0: ein gutes Drittel der kleinsten Seite (höchstens
## 3 cm). Sehr dünne Teile bleiben einfache Quader.
static func rbox(size: Vector3, r := -1.0) -> Mesh:
	var h := size / 2.0
	var hm := minf(h.x, minf(h.y, h.z))
	if r < 0.0:
		r = minf(hm * 0.8, 0.03)
	r = minf(r, hm * 0.95)
	if r < 0.004:
		return box(size)
	var key := "rbox_%.3f_%.3f_%.3f_%.3f" % [size.x, size.y, size.z, r]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var inner := h - Vector3(r, r, r)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var cu := [-h[u], -inner[u], inner[u], h[u]]
		var cv := [-h[v], -inner[v], inner[v], h[v]]
		for sg in [-1.0, 1.0]:
			var fn := Vector3.ZERO
			fn[axis] = sg
			var gp := []
			var gn := []
			for a in 4:
				for b in 4:
					var pt := Vector3.ZERO
					pt[axis] = sg * h[axis]
					pt[u] = cu[a]
					pt[v] = cv[b]
					var q := pt.clamp(-inner, inner)
					var n := (pt - q).normalized()
					gp.append(q + n * r)
					gn.append(n)
			for a in 3:
				for b in 3:
					var i0 := a * 4 + b
					var ids := [i0, i0 + 4, i0 + 5, i0 + 1]
					_tri(st, gp[ids[0]], gp[ids[1]], gp[ids[2]], gn[ids[0]], gn[ids[1]], gn[ids[2]], fn)
					_tri(st, gp[ids[0]], gp[ids[2]], gp[ids[3]], gn[ids[0]], gn[ids[2]], gn[ids[3]], fn)
	var m := st.commit()
	_mesh_cache[key] = m
	return m


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


## Wie tapered_box (Unterkante bei y = 0, oben schmaler und um top_z versetzt), aber mit runden Kanten: ein rbox,
## der nach oben verjüngt wird; die Normalen werden mitgeneigt. Verkehr, Hutzen, Bürzel.
static func rtapered_box(bottom: Vector2, top: Vector2, h: float, top_z: float, r := -1.0) -> Mesh:
	var key := "rtap_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [bottom.x, bottom.y, top.x, top.y, h, top_z]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var base := rbox(Vector3(bottom.x, h, bottom.y), r)
	if not base is ArrayMesh:
		return tapered_box(bottom, top, h, top_z)
	var arr: Array = (base as ArrayMesh).surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var kx := (top.x / bottom.x - 1.0) / h
	var kz := (top.y / bottom.y - 1.0) / h
	for i in vs.size():
		var v := vs[i]
		var n := ns[i]
		var f := (v.y + h / 2.0) / h
		var a := 1.0 + kx * h * f
		var d := 1.0 + kz * h * f
		var b := v.x * kx
		var c := v.z * kz + top_z / h
		vs[i] = Vector3(v.x * a, v.y + h / 2.0, v.z * d + top_z * f)
		ns[i] = Vector3(n.x / a, -b / a * n.x + n.y - c / d * n.z, n.z / d).normalized()
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_cache[key] = m
	return m


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
