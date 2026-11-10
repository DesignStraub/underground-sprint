extends RefCounted
## Erzeugt eine Sprintstrecke durch eine nächtliche Stadt aus einem Seed.
## Hauptstraße mit Gehweg, Abkürzungen (kurvige Gasse, Seesprung über eine Schanze), Seitenstraßen mit Ampeln,
## Bahnübergang mit Rampe, Tunnel, Hochbahn, Brücken, Gabelungen, Boulevards mit Mittelstreifen,
## Stadtviertel mit eigenem Stil (Downtown, Boulevard, Marktviertel, Altstadt, Docks, Schnellstraße; Chinatown ist
## derzeit keiner Strecke zugeordnet).
## Sprints laufen von A nach B, Rundkurse (circuit/drift) sind geschlossene Schleifen.
##
## Wege ("paths"): Index 0 ist die Hauptstraße, danach Abkürzungen und Seitenstraßen. Jeder Weg hat eine eigene
## Mittellinie (Curve3D). Rennfortschritt wird immer in Metern der Hauptstraße gemessen.

const Builder := preload("res://scripts/car_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const RailCrossing := preload("res://scripts/rail_crossing.gd")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const PAVEMENT_SHADER := preload("res://shaders/pavement.gdshader")
const ASPHALT_TEX := preload("res://assets/textures/asphalt.png")  # tools/gen_ground_tex.gd
const ASPHALT_N := preload("res://assets/textures/asphalt_n.png")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const RAMP_SHADER := preload("res://shaders/ramp.gdshader")
const SIGN_SHADER := preload("res://shaders/shop_sign.gdshader")
const GLINT_SHADER := preload("res://shaders/water_glint.gdshader")
const SIGN_FONTS := {"cond": preload("res://assets/fonts/D-DINCondensed-Bold.otf"), "wide": preload("res://assets/fonts/D-DINExp-Bold.otf")}
const BLINK_SHADER := preload("res://shaders/blink.gdshader")
const LIGHT_SHADER := preload("res://shaders/traffic_light.gdshader")
const TUNNEL_SHADER := preload("res://shaders/tunnel.gdshader")
const PANEL_SHADER := preload("res://shaders/panel_wall.gdshader")
const SCREEN_SHADER := preload("res://shaders/screen.gdshader")
const HILL_SHADER := preload("res://shaders/hill.gdshader")
const ElevatedRail := preload("res://scripts/elevated_rail.gd")
const AmbientSound := preload("res://scripts/ambient_sound.gd")
const CityData := preload("res://scripts/city_data.gd")
const People := preload("res://scripts/people.gd")
const City := preload("res://scripts/city_builder.gd")

const HALF_W := 9.0  # 4 Spuren à 4,5 m
const LANES := [-6.75, -2.25, 2.25, 6.75]
const WALK := 5.0  # Gehwegbreite
const CURB_H := 0.2
const WALL_H := 12.0  # hoch genug, dass man auch im Sprung nicht rausfliegt
const LAMP_STEP := 38.0
const WATER_DROP := 1.8  # Seen: so tief fällt man (Physik), gespritzt wird beim Eintauchen in die Oberfläche
## Bahnübergang auf einem Bahndamm (seit 2.24 statt einer 3,7 m hohen Rampe auf der rechten Spur): die Straße steigt
## über gut 25 m sanft an, liegt über den Gleisen flach und fällt wieder ab. Bei Renntempo hebt das Auto kurz ab.
const RAIL_DAM_H := 0.85
const SC_HALF := 5.0
const ALLEY_HALF := 5.0
const SPUR_HALF := 6.0
const FORK_HALF := 6.0  # Gabelung: zweispurige Straße mit Gegenverkehr
const MED := 2.6  # halbe Breite des Mittelstreifens auf Boulevards
const MED_TAPER := 45.0
const TUN_W := HALF_W + 1.6  # Tunnel-Innenwand
const TUN_H := 7.0
const DIP := 6.2  # so tief liegt die Fahrbahn im Tunnel (Decke knapp über dem Straßenniveau der Stadt)
const DIP_RAMP := 70.0  # Länge der Rampe hinunter in den Trog und wieder hinauf
const PARAPET := 0.9  # Trogmauer: so weit ragt sie über den Gehweg
const HILL_H := 5.5  # Bergstraße (Gabelung Altstadt): Höhe der Kuppe
const EL_H := 7.4  # Unterkante der Hochbahn
const TUNNEL_NAMES := ["INNENSTADTTUNNEL", "HAFENTUNNEL", "RINGTUNNEL", "NORDTUNNEL", "KAIZEN-TUNNEL", "UNTERFÜHRUNG OST"]
const STATIONS := ["MARKTPLATZ", "HAFENSTRASSE", "STADION", "RATHAUS", "NORDRING", "ZENTRUM", "DOCKS"]
const GANTRY_SIGNS := [["ZENTRUM", "STADION 2 km"], ["HAFEN", "CONTAINERTERMINAL"], ["FLUGHAFEN", "RING"], ["MESSE", "MARKT"],
	["ALTSTADT", "AUSFAHRT"], ["A 7  NORD", "INDUSTRIE"], ["ALLE RICHTUNGEN", "AUTOBAHN"], ["MESSE", "HAUPTBAHNHOF"]]
const SHOPS := ["PIZZA", "DÖNER", "KIOSK", "BÄCKEREI", "APOTHEKE", "FRISEUR", "TATTOO", "AUTOTEILE",
	"WÄSCHEREI", "SPÄTI", "SUSHI", "CURRYWURST", "HANDYLADEN", "BLUMEN", "JUWELIER", "SPIELHALLE", "MUSIK",
	"TURNSCHUHE", "NAGELSTUDIO", "WETTBÜRO", "CAFÉ", "KNEIPE", "TUNING", "REIFEN", "VIDEOTHEK", "ASIA IMBISS",
	"BUCHLADEN", "SPIELE", "FITNESS", "OPTIKER", "SHISHA", "PFANDHAUS", "SCHNITZELHAUS", "LOTTO TOTO"]
## Dachwerbung: ausgedachte Marken der Tuning-Szene (lange Texte brechen auf der Tafel um)
const BRANDS := ["KAIZEN MOTORS", "VORTEX GT-R", "NITROWERK", "MIRAI 240R", "TURBOSTARK", "ONE HUMANITY",
	"RADIO VOLLGAS", "DRIFTKÖNIGE", "NEED FOR GESCHWINDIGKEIT", "NACHTSCHICHT TUNING", "HOCHDREHZAHL",
	"STRASSENKÖNIG", "NEONWERK FELGEN", "UNTERGRUND"]
const CHINA_SHOPS := ["NUDELBAR", "DIM SUM", "TEEHAUS", "KARAOKE", "MAHJONG", "JADE", "GLÜCKS-8", "DRACHE", "WOK",
	"RAMEN", "PHO", "GOLD", "LOTUS", "TOFU", "BUBBLE TEA", "ASIA MARKT", "FEUERTOPF", "PANDA"]
const NEON := [Color(1, 0.1, 0.6), Color(0.1, 0.8, 1), Color(0.7, 0.2, 1), Color(1, 0.5, 0.1), Color(0.2, 1, 0.4), Color(1, 0.9, 0.3)]
const GERMAN_SHOPS := ["BÄCKEREI", "METZGEREI", "APOTHEKE", "WEINSTUBE", "EISCAFÉ", "DÖNER", "BUCHHANDLUNG", "OPTIKER",
	"FRISEUR", "BIERGARTEN", "KIOSK", "BLUMEN", "GASTHAUS", "SCHUHHAUS", "CAFÉ", "PIZZERIA", "BRAUHAUS", "WEINHANDEL",
	"DROGERIE", "KONDITOREI", "GOLDSCHMIED", "REISEBÜRO", "STEHCAFÉ", "SPÄTKAUF", "BANK", "POST"]
const RIVER_Y := -2.2  # Wasserspiegel der Flüsse (Ufermauer bis Straßenniveau)

## Stadtviertel: Bebauung, Fassadenstile (siehe building.gdshader), Farben, Laternen, Ausstattung.
## props: welche Gehweg-Möbel vorkommen (Nummern siehe _build_props).
const DISTRICTS := {
	"downtown": {"name": "BANKENVIERTEL", "shop": 0.3, "low": [6.0, 10.0], "tall": [24.0, 90.0], "tall_p": 0.7, "styles": [0, 1, 3, 3],
		"tints": [Color(0.08, 0.09, 0.11), Color(0.13, 0.14, 0.17), Color(0.05, 0.07, 0.1)], "lit": 0.45,
		"trees": 0.1, "billboard": 0.3, "neon_edge": 0.3, "lamp": Color(0.8, 0.88, 1.0), "lamp_kind": "modern",
		"screens": 0.35, "gantry": 0.5, "props": [0, 3, 7, 8, 9, 10, 11, 12, 13], "median": 0.35},
	"shops": {"name": "MARKTVIERTEL", "shop": 0.8, "low": [10.0, 16.0], "tall": [16.0, 24.0], "tall_p": 0.3, "styles": [6, 6, 4, 0],
		"tints": [Color(0.3, 0.25, 0.2), Color(0.26, 0.25, 0.23), Color(0.3, 0.16, 0.11), Color(0.2, 0.21, 0.23)], "lit": 0.5,
		"roof": 0.55, "gable": 0.15, "roof_tints": [Color(0.12, 0.13, 0.15), Color(0.3, 0.12, 0.08), Color(0.22, 0.1, 0.07)],
		"trees": 0.35, "billboard": 0.15, "neon_edge": 0.1, "lamp": Color(1.0, 0.68, 0.35), "lamp_kind": "classic",
		"blade": 0.3, "bulbs": true, "props": [0, 1, 2, 4, 5, 6, 8, 9, 11, 12]},
	"boulevard": {"name": "PRACHTALLEE", "shop": 0.45, "low": [14.0, 20.0], "tall": [22.0, 46.0], "tall_p": 0.35, "styles": [6, 6, 1, 0],
		"tints": [Color(0.32, 0.27, 0.21), Color(0.24, 0.23, 0.24), Color(0.36, 0.3, 0.22)], "lit": 0.55,
		"roof": 0.6, "gable": 0.0, "roof_tints": [Color(0.11, 0.12, 0.14), Color(0.15, 0.16, 0.19)],
		"trees": 0.7, "billboard": 0.15, "neon_edge": 0.1, "lamp": Color(1.0, 0.82, 0.55), "lamp_kind": "classic",
		"median": 1.0, "blade": 0.15, "props": [0, 4, 5, 8, 9, 10, 13]},
	"residential": {"name": "ALTSTADT", "shop": 0.25, "low": [9.0, 15.0], "tall": [15.0, 21.0], "tall_p": 0.2, "styles": [6, 5, 4, 6],
		"tints": [Color(0.36, 0.31, 0.24), Color(0.3, 0.14, 0.09), Color(0.34, 0.28, 0.2), Color(0.28, 0.27, 0.25)], "lit": 0.55,
		"trees": 0.6, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(1.0, 0.75, 0.45), "lamp_kind": "classic",
		"roof": 0.95, "gable": 0.4, "roof_tints": [Color(0.32, 0.12, 0.07), Color(0.26, 0.1, 0.07), Color(0.13, 0.14, 0.16)],
		"props": [0, 4, 5, 6, 8, 13, 14]},
	"industrial": {"name": "HAFEN", "shop": 0.05, "low": [7.0, 12.0], "tall": [12.0, 22.0], "tall_p": 0.25, "styles": [2, 2, 4, 4],
		"tints": [Color(0.15, 0.17, 0.18), Color(0.28, 0.12, 0.08), Color(0.24, 0.11, 0.07), Color(0.1, 0.14, 0.15)], "lit": 0.3,
		"roof": 0.3, "gable": 0.5, "roof_tints": [Color(0.1, 0.11, 0.12), Color(0.16, 0.2, 0.18)],
		"trees": 0.0, "billboard": 0.1, "neon_edge": 0.0, "lamp": Color(1.0, 0.62, 0.3), "lamp_kind": "sodium",
		"containers": true, "cranes": 0.14, "stacks": 0.35, "overpass": 0.5, "props": [2, 2, 6, 7, 14, 15]},
	"chinatown": {"name": "CHINATOWN", "shop": 0.75, "low": [7.0, 13.0], "tall": [14.0, 26.0], "tall_p": 0.2, "styles": [4, 0, 4],
		"tints": [Color(0.34, 0.07, 0.05), Color(0.1, 0.2, 0.13), Color(0.3, 0.2, 0.1), Color(0.2, 0.06, 0.06)], "lit": 0.65,
		"trees": 0.05, "billboard": 0.05, "neon_edge": 0.2, "lamp": Color(1.0, 0.4, 0.22), "lamp_kind": "lantern",
		"eaves": 0.55, "blade": 0.6, "lanterns": true, "fire_escape": 0.25, "names": CHINA_SHOPS, "props": [0, 3, 8, 11, 14]},
	"highway": {"name": "SCHNELLSTRASSE", "shop": 0.0, "low": [8.0, 14.0], "tall": [20.0, 60.0], "tall_p": 0.45, "styles": [0, 1, 2, 3],
		"tints": [Color(0.1, 0.11, 0.13), Color(0.15, 0.15, 0.16), Color(0.08, 0.1, 0.12)], "lit": 0.35,
		"trees": 0.0, "billboard": 0.5, "neon_edge": 0.05, "lamp": Color(1.0, 0.6, 0.28), "lamp_kind": "sodium",
		"setback": 10.0, "soundwall": true, "gantry": 1.0, "overpass": 1.0, "prop_gap": 3.0, "props": [2, 7, 15], "median": 0.6},
	# --- deutsche Städte (Orts-Strecken): Fachwerk, Putz, Ziegeldächer. roof = Anteil Satteldächer,
	# gable = Anteil mit Giebel zur Straße, roof_tints = Dachfarben
	"altstadt_de": {"name": "ALTSTADT", "shop": 0.55, "low": [9.0, 14.0], "tall": [14.0, 18.0], "tall_p": 0.15, "styles": [5, 5, 6],
		"tints": [Color(0.5, 0.46, 0.38), Color(0.54, 0.5, 0.42), Color(0.5, 0.42, 0.3), Color(0.46, 0.44, 0.4)], "lit": 0.6,
		"trees": 0.12, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(1.0, 0.72, 0.42), "lamp_kind": "classic",
		"roof": 1.0, "gable": 0.6, "roof_tints": [Color(0.36, 0.13, 0.08), Color(0.3, 0.12, 0.08), Color(0.25, 0.1, 0.07)],
		"names": GERMAN_SHOPS, "de": true, "props": [0, 4, 5, 6, 8, 13]},
	"innenstadt_de": {"name": "INNENSTADT", "shop": 0.55, "low": [12.0, 17.0], "tall": [17.0, 23.0], "tall_p": 0.25, "styles": [6, 6, 6, 4],
		"tints": [Color(0.44, 0.38, 0.3), Color(0.38, 0.36, 0.33), Color(0.46, 0.36, 0.28), Color(0.34, 0.37, 0.38)], "lit": 0.55,
		"trees": 0.35, "billboard": 0.05, "neon_edge": 0.0, "lamp": Color(1.0, 0.78, 0.5), "lamp_kind": "classic",
		"roof": 0.75, "gable": 0.1, "roof_tints": [Color(0.14, 0.15, 0.17), Color(0.32, 0.13, 0.09)],
		"names": GERMAN_SHOPS, "de": true, "bulbs": true, "props": [0, 1, 4, 5, 8, 9, 11, 12]},
	"kurviertel_de": {"name": "KURVIERTEL", "shop": 0.25, "low": [10.0, 15.0], "tall": [15.0, 19.0], "tall_p": 0.2, "styles": [6],
		"tints": [Color(0.56, 0.48, 0.32), Color(0.54, 0.52, 0.44), Color(0.5, 0.45, 0.36)], "lit": 0.6,
		"trees": 0.85, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(1.0, 0.8, 0.55), "lamp_kind": "classic",
		"roof": 0.8, "gable": 0.0, "roof_tints": [Color(0.14, 0.15, 0.17), Color(0.2, 0.36, 0.3)],
		"names": GERMAN_SHOPS, "de": true, "props": [0, 4, 5, 8, 13]},
	"campus_de": {"name": "CAMPUS", "shop": 0.1, "low": [10.0, 16.0], "tall": [18.0, 32.0], "tall_p": 0.4, "styles": [1, 3, 0],
		"tints": [Color(0.16, 0.17, 0.19), Color(0.22, 0.22, 0.24), Color(0.12, 0.14, 0.16)], "lit": 0.6,
		"trees": 0.4, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(0.85, 0.92, 1.0), "lamp_kind": "modern",
		"names": GERMAN_SHOPS, "de": true, "props": [0, 3, 8, 9, 13]},
	"kiez_de": {"name": "KIEZ", "shop": 0.65, "low": [16.0, 21.0], "tall": [21.0, 38.0], "tall_p": 0.12, "styles": [8, 8, 8, 6, 0],
		"tints": [Color(0.42, 0.36, 0.3), Color(0.36, 0.34, 0.33), Color(0.44, 0.33, 0.26), Color(0.3, 0.33, 0.36)], "lit": 0.65,
		"trees": 0.35, "billboard": 0.08, "neon_edge": 0.06, "lamp": Color(1.0, 0.78, 0.5), "lamp_kind": "classic",
		"roof": 0.35, "gable": 0.0, "roof_tints": [Color(0.14, 0.15, 0.17), Color(0.3, 0.13, 0.09)],
		"names": GERMAN_SHOPS, "de": true, "blade": 0.25, "props": [0, 3, 8, 9, 11, 12]},
	"vorstadt_de": {"name": "VORSTADT", "shop": 0.15, "low": [7.0, 11.0], "tall": [11.0, 15.0], "tall_p": 0.15, "styles": [6, 6, 4, 5],
		"tints": [Color(0.46, 0.42, 0.36), Color(0.42, 0.4, 0.38), Color(0.48, 0.4, 0.3), Color(0.38, 0.36, 0.34)], "lit": 0.45,
		"trees": 0.65, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(1.0, 0.7, 0.4), "lamp_kind": "classic",
		"roof": 1.0, "gable": 0.3, "roof_tints": [Color(0.34, 0.13, 0.08), Color(0.16, 0.16, 0.18), Color(0.28, 0.12, 0.08)],
		"names": GERMAN_SHOPS, "de": true, "props": [0, 4, 5, 6, 13]},
}
const DISTRICT_LEN := 400.0
const BATCH_CELL := 120.0  # Häuser werden in Zellen dieser Größe zu je einem Mesh zusammengefasst

## Häuser-Batch während build(): Zelle -> SurfaceTool
static var _bb := {}
## Straßenmaterial je Straßentyp (keine Werte pro Objekt: im Browser gibt es dafür nur wenig Platz)
static var _road_mats := {}
## Orts-Strecken: Ladennamen der Stadt (vor den allgemeinen deutschen), leer = Namen des Viertels
static var _city_names: Array = []
static var _box_arrays: Array = []
## Prüfwerkzeug (tools/track_check.gd --buildings): Array = Häuserquader mitschreiben [Transform, Haus-Nr., Art]
static var box_log = null
static var _box_id := 0
static var _box_tag := ""


## Ganze Strecke auf einmal bauen (Prüfwerkzeuge). Das Rennen baut sie mit begin()/step() in Stücken, damit der
## Ladebildschirm zwischendurch zeichnen kann.
static func build(race: Dictionary) -> Dictionary:
	var job := begin(race)
	while step(job) < 1.0:
		pass
	return job["track"]


## Planung (Mittellinie, Viertel, Abzweige, Tunnel ...): schnell. Gibt den Bauauftrag für step() zurück.
static func begin(race: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"]
	var root := Node3D.new()
	root.name = "Track"
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # Schilder in der Welt bleiben deutsch
	_bb = {}

	var type: String = race.get("type", "sprint")
	var loop := type == "circuit" or type == "drift"
	# Orts-Strecken: Mittellinie aus echten Straßen (OpenStreetMap), siehe tools/osm_city.py
	var city: Dictionary = CityData.CITIES.get(race.get("city", ""), {})
	_city_names = race.get("shops", [])
	var gen := _city_centerline(city) if not city.is_empty() else (_loop_centerline(race, rng) if loop else _centerline(race, rng))
	var pts: Array = gen["pts"]
	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	var n := pts.size()
	for i in n:
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, n - 1)]
		if loop and i == 0:
			prev = pts[n - 2]  # letzter Punkt = erster Punkt
		elif loop and i == n - 1:
			nxt = pts[1]
		var t: Vector3 = (nxt - prev) * (0.17 if type == "drift" else 0.22)
		curve.add_point(pts[i], -t, t)
	if loop:
		curve.set_meta("loop", true)
	if city.is_empty():
		_round_corners(curve, HALF_W + (6.5 if type == "drift" else 3.0), loop)
	var length := curve.get_baked_length()
	var laps: int = race.get("laps", 1) if loop else 1

	var track := {
		"node": root, "curve": curve, "length": length, "start": 25.0, "type": type, "loop": loop, "laps": laps,
		# Ziel als Gesamtfortschritt: Sprint am Ende der Straße, Rundkurs nach laps Runden an der Startlinie
		"finish": laps * length + 37.0 if loop else length - 80.0,
		"blocks": [], "ramps": [], "lakes": [], "zones": [], "crossing": null, "crossing_d": -1.0,
		"districts": [], "parks": [], "ponds": [], "tunnels": [], "el": [], "posts": [], "stadium_d": -1.0, "medians": [], "elev0": [],
		"force_stadium": race.get("stadium", false), "city": city, "rivers": [], "bridges": [], "hills": [],
		"spectators": [],  # Zuschauer hinter Zäunen und Absperrungen: [Transform, Wegstück d]
		"pools": [],  # zusätzliche Lichtflächen für die Lichtkarte (Tunnel): [x, z, Radius, Farbe mal Stärke]
		"extra": 2.5 if type == "drift" else 0.0,  # Drift-Kurse: breitere Fahrbahn
		"paths": [{"id": 0, "kind": "main", "curve": curve, "half_w": HALF_W, "length": length, "from": 0.0, "to": length}],
	}
	var weights: Dictionary = race.get("districts", {"downtown": 1.0})
	var dd := 0.0
	var prev_key := ""
	while dd < length + DISTRICT_LEN:
		var key := _pick(weights, rng)
		for retry in 2:
			if key == prev_key:
				key = _pick(weights, rng)  # Viertel sollen wechseln, gleiche hintereinander nur selten
		track["districts"].append(key)
		prev_key = key
		dd += DISTRICT_LEN

	for b in gen["bulges"]:
		_plan_shortcut(track, b, rng)
	if not city.is_empty():
		# echte Stadt: Flüsse mit Brücken, Hügel, Bahnübergang nur wo die Gleise wirklich kreuzen; keine Tunnel/Hochbahn
		_plan_rivers(track)
		_plan_hills(track)
		_plan_city_crossing(track, race)
		if race.get("city", "") == "kreuzberg":
			_plan_kreuzberg_el(track)
		_plan_spurs(track, rng)
		_plan_medians(track, rng)
	elif type == "drag":
		# Drag: vier freie Spuren geradeaus (kein Bahnübergang, keine Hochbahnstützen, kein Mittelstreifen)
		_plan_tunnels(track, rng)
		_plan_spurs(track, rng)
	elif type != "drift":
		# Drift-Kurse sind abgesperrt: keine Seitenstraßen, Tunnel, Hochbahn, Mittelstreifen, Bahnübergang
		_plan_crossing(track, rng)
		_plan_tunnels(track, rng)
		_plan_spurs(track, rng)
		_plan_el(track, rng)
		_plan_medians(track, rng)
	if not track["elev0"].is_empty():
		curve.set_meta("elev", track["elev0"])
	return {"race": race, "rng": rng, "root": root, "track": track, "city": city, "type": type, "loop": loop,
		"occupied": [], "buildings": [], "i": 0, "us": []}


## Gewicht je Bauschritt (ungefähre Dauer) für den Fortschrittsbalken
const STEP_W := [4.0, 2.0, 2.0, 10.0, 3.0, 3.0, 1.0, 1.0, 2.0, 72.0]


## Einen Bauschritt ausführen; gibt den Fortschritt 0..1 zurück (1 = fertig, job["track"] ist gebaut).
## Die Reihenfolge ist dieselbe wie früher in einem Stück: gleiche Zufallszahlen, gleiche Strecke.
static func step(job: Dictionary) -> float:
	var race: Dictionary = job["race"]
	var rng: RandomNumberGenerator = job["rng"]
	var root: Node3D = job["root"]
	var track: Dictionary = job["track"]
	var city: Dictionary = job["city"]
	var type: String = job["type"]
	var curve: Curve3D = track["curve"]
	var i: int = job["i"]
	var t0 := Time.get_ticks_usec()
	match i:
		0:
			_build_road(root, track)
			for p in track["paths"]:
				if p["id"] != 0:
					_build_branch(root, track, p, rng)
		1:
			_build_lakes(root, track, rng)
			_build_ramps(root, track)
			if track["crossing_d"] > 0.0:
				var rc := RailCrossing.new()
				root.add_child(rc)
				rc.setup(frame_at(curve, track["crossing_d"]), track["crossing_d"], HALF_W, WALK,
					race.get("station", STATIONS[int(track["crossing_d"]) % STATIONS.size()]))
				track["crossing"] = rc
			_build_tunnels(root, track, rng)
			_build_el(root, track, rng)
			if not city.is_empty():
				_build_rivers(root, track)
				_build_hills(root, track, rng)
		2:
			var occupied: Array = _build_city_landmarks(root, track) if not city.is_empty() else _build_landmarks(root, track, rng)
			occupied.append_array(_build_structures(root, track, rng))
			job["occupied"] = occupied
		3:
			_box_tag = "zeile"
			job["buildings"] = _build_city(root, track, rng, job["occupied"])
			_box_tag = ""
		4:
			if not city.is_empty():
				_box_tag = "osm"
				job["buildings"].append_array(_build_osm_buildings(root, track, rng, job["occupied"] + job["buildings"]))
				_box_tag = ""
		5:
			if type != "drift":
				_build_fences(root, track, job["buildings"] + job["occupied"])
			_build_lamps(root, track)
			if type == "drift":
				_build_barriers(root, track, rng)
			else:
				_build_props(root, track, rng)
			_build_steam(root, track, rng)
			_build_spectators(root, track, rng)
			if type == "drag":
				_drag_boards(root, track)
			if not city.is_empty() or race.has("town"):
				_build_city_signs(root, track, race)
			if race.get("city", "") == "kreuzberg":
				_east_side_gallery(root, track)
			if job["loop"]:
				_gate(root, track, track["start"] + 12.0, "START · ZIEL", Color(0.2, 1.0, 0.4))
			else:
				_gate(root, track, track["start"] + 12.0, "START", Color(0.2, 1.0, 0.4))
				_gate(root, track, track["finish"], "ZIEL", Color(1.0, 0.2, 0.4))
		6:
			# Boden (sichtbar, mit Löchern über den Trögen) + Boden-Kollision nur für umherfliegende Teile
			_build_ground(root, track)
		7:
			_bake_street_light(root, track)
		8:
			var gb := StaticBody3D.new()
			gb.collision_layer = Knockable.GROUND
			gb.collision_mask = 0
			var gs := CollisionShape3D.new()
			gs.shape = WorldBoundaryShape3D.new()
			gb.add_child(gs)
			root.add_child(gb)
			_bb_flush(root)
			_finalize_walls(root)
			_auto_collide(root, track)
		9:
			# Verschmelzen dauert am längsten: in Stücken von gut 0,1 s, damit der Ladebalken weiterläuft
			if not OS.get_cmdline_user_args().has("--nobatch"):
				if not job.has("batch"):
					job["batch"] = batch_begin(root)
				if not batch_step(root, job["batch"], 110):
					job["us"].append(Time.get_ticks_usec() - t0)
					return (_steps_done(8) + STEP_W[9] * batch_progress(job["batch"])) / _steps_done(9)
	job["us"].append(Time.get_ticks_usec() - t0)
	job["i"] = i + 1
	return 1.0 if i + 1 >= STEP_W.size() else _steps_done(i) / _steps_done(STEP_W.size() - 1)


## Summe der Gewichte bis einschließlich Schritt i
static func _steps_done(i: int) -> float:
	var t := 0.0
	for k in i + 1:
		t += STEP_W[k]
	return t


## Alles Feste und Schmale, das auf Fahrbahn oder Gehweg steht (Masten, Pfosten, Baumstämme, Schaltkästen,
## Schilder, Bänke), bekommt eine Kollisionsbox, falls es keine eigene hat; sonst fährt man hindurch.
## Ausgenommen: Flaches (Bordsteine, Markierungen), Hochliegendes (Schilder über der Straße), Durchsichtiges,
## Dünnes (Schilf, Kabel), Großes (Häuser, Brücken: haben eigene Wände) und alles mit Skript oder eigenem Körper.
static func _auto_collide(root: Node3D, track: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "AutoCollide"
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		for c in (e[0] as Node).get_children():
			if not c is Node3D or c is PhysicsBody3D or c.get_script() != null:
				continue
			var xf: Transform3D = e[1] * (c as Node3D).transform
			if c is MeshInstance3D:
				_auto_box(c, xf, track, body)
			if c.get_child_count() > 0 and not c.get_children().any(func(k): return k is StaticBody3D):
				stack.append([c, xf])
	if body.get_child_count() > 0:
		root.add_child(body)


static func _auto_box(mi: MeshInstance3D, xf: Transform3D, track: Dictionary, body: StaticBody3D) -> void:
	if mi.mesh == null or not mi.visible or mi.has_meta("no_collide"):
		return
	var m := mi.material_override
	if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return
	var ab := mi.get_aabb()
	var sc := xf.basis.get_scale()
	var size := ab.size * sc
	var wb: AABB = xf * ab
	if wb.size.y < 0.6 or minf(size.x, size.z) < 0.08 or maxf(size.x, size.z) > 4.0:
		return
	var c := wb.get_center()
	var loc := locate(track, Vector3(c.x, 0.0, c.z))
	var p: Dictionary = loc["path"]
	var reach: float = (hw(track, loc["d"]) + WALK if p["id"] == 0 else p["half_w"] + (3.0 if p["kind"] == "fork" else 0.0)) + 0.2
	var ground := elev_at(p["curve"], loc["d"])
	if absf(loc["lat"]) > reach or wb.position.y - ground > 1.2:
		return
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size.max(Vector3(0.15, 0.15, 0.15))
	cs.shape = bs
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf * ab.get_center())
	body.add_child(cs)


## Statisches Zusammenfassen wie in großen Engines: unbewegliche Teile mit gleichem Material (gleiche Werte) und
## gleicher Detailstufe werden je Rasterzelle zu einem Mesh verschmolzen. Im Browser kostet jeder Draw Call viel
## Prozessorzeit, so fallen die meisten weg. Alles mit Skript (Umfahrbares, Züge, Schranken) bleibt, wie es ist.
const STATIC_CELL := [32.0, 64.0, 128.0]  # Zellgröße je Detailstufe (klein, mittel, groß wie in apply_lod)


static func batch_static(root: Node3D) -> void:
	var job := batch_begin(root)
	while not batch_step(root, job, -1):
		pass


## Häuser und Kleinteile zu großen Flächen verschmelzen, in Stücken (Ladebildschirm): batch_begin() legt den
## Auftrag an, batch_step() arbeitet höchstens budget_ms (-1 = alles) und gibt true zurück, wenn alles fertig ist.
## Erst sammeln (je Kind der Strecke), dann verschmelzen, dann die Einzelteile entfernen; batch_progress() 0..1.
static func batch_begin(root: Node3D) -> Dictionary:
	var fn := func(mi: MeshInstance3D, xf: Transform3D) -> Array:
		var size := mi.get_aabb().size.length()
		var cls := 0 if size < 4.0 else (1 if size < 15.0 else 2)
		var c: Vector3 = xf * mi.get_aabb().get_center()
		return [cls, Vector2i(floori(c.x / STATIC_CELL[cls]), floori(c.z / STATIC_CELL[cls]))]
	return {"kids": root.get_children(), "ci": 0, "buckets": {}, "canon": {}, "fn": fn, "merge": {}}


static func batch_step(root: Node3D, job: Dictionary, budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var kids: Array = job["kids"]
	while job["ci"] < kids.size():
		if budget_ms >= 0 and Time.get_ticks_msec() - t0 >= budget_ms:
			return false
		Builder.collect_one(kids[job["ci"]], Transform3D.IDENTITY, {}, job["canon"], job["buckets"], job["fn"])
		job["ci"] += 1
	if job["merge"].is_empty():
		job["merge"] = Builder.merge_begin(job["buckets"])
	var rest := -1 if budget_ms < 0 else maxi(budget_ms - (Time.get_ticks_msec() - t0), 1)
	if not Builder.merge_step(root, job["merge"], rest):
		return false
	if not job.has("knock"):
		for mi in job["merge"]["made"]:
			mi.set_meta("lod_class", mi.get_meta("merge_extra")[0])
		# Umfahrbares (Laternen, Schilder, Poller) bewegt sich als Ganzes: je Teil die Flächen pro Material zusammen
		var knock := []
		var stack: Array = [root]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			for c in nd.get_children():
				if c is Knockable:
					knock.append(c)
				elif c.get_child_count() > 0:
					stack.append(c)
		job["knock"] = knock
		job["ki"] = 0
	var kn: Array = job["knock"]
	while job["ki"] < kn.size():
		if budget_ms >= 0 and Time.get_ticks_msec() - t0 >= budget_ms:
			return false
		Builder.merge_static(kn[job["ki"]])
		job["ki"] += 1
	return true


static func batch_progress(job: Dictionary) -> float:
	var col := float(job["ci"]) / maxf(job["kids"].size(), 1.0)
	var m: Dictionary = job["merge"]
	if m.is_empty():
		return 0.25 * col
	var mg := float(m["done"]) / maxf(m["keys"].size(), 1.0)
	var dr := 0.0 if m["drop"] == null else float(m["dropped"]) / maxf(m["drop"].size(), 1.0)
	var kn := 0.0 if not job.has("knock") else float(job["ki"]) / maxf(job["knock"].size(), 1.0)
	return 0.25 + 0.5 * mg + 0.1 * dr + 0.15 * kn


## Boden der Stadt als Quadtree: grobe Platten weit weg, feine Kacheln am Rand der offenen Tröge, über dem Trog
## selbst nichts (sonst läge die Bodenfläche wie ein Deckel über der abgesenkten Fahrbahn).
static func _build_ground(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var holes := PackedVector3Array()  # x, z, Radius
	for t in track["tunnels"]:
		for span in [[t["r0"], t["from"] + 1.0], [t["to"] - 1.0, t["r1"]]]:
			var d: float = span[0]
			while d <= span[1]:
				var q := curve.sample_baked(d)
				holes.append(Vector3(q.x, q.z, TUN_W + 1.6))
				d += 1.0
	# Flussbett: Löcher entlang der Mittellinie, Radius = halbe Wasserbreite an dieser Stelle
	for rv in track["rivers"]:
		var pts: PackedVector2Array = rv["pts"]
		var hws: PackedFloat32Array = rv["hw"]
		for i in pts.size() - 1:
			var steps := maxi(int(pts[i].distance_to(pts[i + 1]) / 4.0), 1)
			for k in steps:
				var t := float(k) / steps
				var hr := lerpf(hws[i], hws[i + 1], t)
				if hr > 1.5:
					var q := pts[i].lerp(pts[i + 1], t)
					holes.append(Vector3(q.x, q.y, hr))
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in track["paths"]:
		for q in (p["curve"] as Curve3D).get_baked_points():
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
	lo -= Vector2(1500.0, 1500.0)
	hi += Vector2(1500.0, 1500.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	_ground_cell(st, lo, maxf(hi.x - lo.x, hi.y - lo.y), holes)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Builder.mat(Color(0.03, 0.03, 0.035), 0.0, 0.9)
	mi.position = Vector3(0, -0.05, 0)
	root.add_child(mi)


static func _ground_cell(st: SurfaceTool, o: Vector2, s: float, holes: PackedVector3Array) -> void:
	var c := o + Vector2(s, s) * 0.5
	var near := PackedVector3Array()
	for h in holes:
		var reach := s * 0.7072 + h.z
		if Vector2(h.x, h.y).distance_squared_to(c) < reach * reach:
			near.append(h)
	if not near.is_empty():
		if s > 2.0:
			var hs := s * 0.5
			for k in 4:
				_ground_cell(st, o + Vector2(k % 2, k / 2) * hs, hs, near)
			return
		for h in near:
			if Vector2(h.x, h.y).distance_squared_to(c) < h.z * h.z:
				return
	# im Uhrzeigersinn von oben gesehen
	for v in [Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, 0), Vector2(s, s), Vector2(0, s)]:
		st.add_vertex(Vector3(o.x + v.x, 0.0, o.y + v.y))


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]


static func _dir(h: float) -> Vector3:
	return Vector3(-sin(h), 0, -cos(h))


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Mittellinie der Hauptstraße. An geplanten Stellen macht sie einen Bogen ("bulge"),
## die Sehne dieses Bogens wird später zur Abkürzung.
## Spitze Ecken runden: Ist die Kurve an einem Eckpunkt enger als min_r, überschneiden sich dort Fahrbahnrand,
## Leitplanke und Wände (die Drift-Sterne hatten 5 m Radius bei 11,5 m halber Breite: Planke quer über die Straße).
## Dann werden die Tangenten an diesem Punkt länger, bis der Radius reicht, höchstens bis knapp vor die Nachbarpunkte.
static func _round_corners(curve: Curve3D, min_r: float, loop: bool) -> void:
	var n := curve.point_count
	for it in 16:
		var changed := false
		for i in n - (1 if loop else 0):
			if not loop and (i == 0 or i == n - 1):
				continue
			var p := curve.get_point_position(i)
			if _min_radius(curve, curve.get_closest_offset(p), loop) >= min_r:
				continue
			var prev := curve.get_point_position(posmod(i - 1, n - 1) if loop else i - 1)
			var nxt := curve.get_point_position((i + 1) % (n - 1) if loop else i + 1)
			var out := curve.get_point_out(i)
			if out.length() * 1.15 > 0.45 * minf(p.distance_to(prev), p.distance_to(nxt)):
				continue
			curve.set_point_in(i, curve.get_point_in(i) * 1.15)
			curve.set_point_out(i, out * 1.15)
			if loop and i == 0:
				curve.set_point_in(n - 1, curve.get_point_in(i))
				curve.set_point_out(n - 1, curve.get_point_out(i))
			changed = true
		if not changed:
			break


## Kleinster Kurvenradius im Umkreis von 24 m um offset (aus drei Punkten im Abstand 6 m)
static func _min_radius(curve: Curve3D, offset: float, loop: bool) -> float:
	var L := curve.get_baked_length()
	var best := 1e9
	var d := offset - 24.0
	while d <= offset + 24.0:
		var at := func(x: float) -> Vector3: return curve.sample_baked(fposmod(x, L) if loop else clampf(x, 0.0, L))
		var a: Vector3 = at.call(d - 6.0)
		var b: Vector3 = at.call(d)
		var c: Vector3 = at.call(d + 6.0)
		var area := absf((b - a).cross(c - a).y) / 2.0
		if area > 1e-4:
			best = minf(best, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (4.0 * area))
		d += 2.0
	return best


static func _centerline(race: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pts := [Vector3.ZERO]
	var heading := 0.0
	var p := _dir(heading) * 160.0
	pts.append(p)
	var bulges := []
	var plan: Dictionary = race.get("bulges", {})
	for i in race["segments"]:
		if plan.has(i):
			var kind: String = plan[i]
			var a := 150.0 if kind == "lake" else (170.0 if kind == "fork" else 120.0)
			p += _dir(heading) * 80.0
			pts.append(p)
			var p0 := p
			var side := -signf(heading) if absf(heading) > 0.15 else (1.0 if rng.randf() < 0.5 else -1.0)
			var defl := deg_to_rad(60.0) * side
			var p1 := p0 + _dir(heading + defl) * a
			var p2 := p1 + _dir(heading - defl) * a
			pts.append(p1)
			pts.append(p2)
			p = p2 + _dir(heading) * 80.0
			pts.append(p)
			bulges.append({"kind": kind, "p0": p0, "p1": p1, "p2": p2, "heading": heading, "a": a})
			continue
		heading = clampf(heading + deg_to_rad(rng.randf_range(-race["max_turn"], race["max_turn"])), -1.3, 1.3)
		p += _dir(heading) * rng.randf_range(70.0, 150.0)
		pts.append(p)
	p += _dir(heading) * 200.0
	pts.append(p)
	return {"pts": pts, "bulges": bulges}


## Rundkurs: Eckpunkte grob auf einem Kreis, Radius und Winkel verwürfelt. Geplante Ausbuchtungen
## (Abkürzung/Gabelung) kommen auf lange Kanten, nach außen. Letzter Punkt = erster Punkt.
static func _loop_centerline(race: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var n: int = race["corners"]
	var R: float = race["radius"]
	var drift: bool = race.get("type", "") == "drift"
	var corners := []
	for i in n:
		var ang := TAU * (i + rng.randf_range(-0.15, 0.15)) / n
		var r := R * rng.randf_range(0.8, 1.15)
		if drift:
			# abwechselnd weit innen und außen: enge Kurvenfolgen links-rechts zum Querfahren
			r = R * (rng.randf_range(0.5, 0.62) if i % 2 == 1 else rng.randf_range(1.05, 1.2))
		corners.append(Vector3(sin(ang) * r, 0, cos(ang) * r))
	var plan: Dictionary = race.get("bulges", {})
	var pts := []
	var bulges := []
	for i in n:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % n]
		pts.append(a)
		if not plan.has(i):
			continue
		var kind: String = plan[i]
		var size := 150.0 if kind == "lake" else (170.0 if kind == "fork" else 120.0)
		var e := b - a
		if e.length() < size + 110.0:
			continue
		var du := e.normalized()
		var heading := atan2(-du.x, -du.z)
		var p0 := a + du * ((e.length() - size) / 2.0)
		var side := 1.0
		if (p0 + _dir(heading + deg_to_rad(60.0)) * size).length() < p0.length():
			side = -1.0  # Ausbuchtung nach außen
		var defl := deg_to_rad(60.0) * side
		var p1 := p0 + _dir(heading + defl) * size
		var p2 := p1 + _dir(heading - defl) * size
		pts.append_array([p0, p1, p2])
		bulges.append({"kind": kind, "p0": p0, "p1": p1, "p2": p2, "heading": heading, "a": size})
	pts.append(corners[0])
	return {"pts": pts, "bulges": bulges}


## "pos" liegt immer auf Straßenniveau der Stadt (y = 0), "y" ist die Höhe der Fahrbahn (Trog, Bergstraße)
static func frame_at(curve: Curve3D, d: float) -> Dictionary:
	var len := curve.get_baked_length()
	if curve.has_meta("loop"):
		d = fposmod(d, len)
		var la := curve.sample_baked(fposmod(d - 1.0, len))
		var lb := curve.sample_baked(fposmod(d + 1.0, len))
		var lf := lb - la
		lf.y = 0.0
		lf = lf.normalized()
		return {"pos": curve.sample_baked(d), "fwd": lf, "right": Vector3(-lf.z, 0, lf.x), "y": elev_at(curve, d)}
	var a := curve.sample_baked(clampf(d - 1.0, 0.0, len))
	var b := curve.sample_baked(clampf(d + 1.0, 0.0, len))
	var fwd := (b - a)
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd == Vector3.ZERO:
		fwd = Vector3.FORWARD
	return {"pos": curve.sample_baked(clampf(d, 0.0, len)), "fwd": fwd, "right": Vector3(-fwd.z, 0, fwd.x), "y": elev_at(curve, d)}


## Höhenprofil eines Wegs (Meta "elev" an der Kurve): Liste von {a, b, c, e, h}. Zwischen a und b geht es weich
## auf h (negativ = Senke), bis c bleibt es dort, bis e geht es zurück auf 0.
static func elev_at(curve: Curve3D, d: float) -> float:
	if not curve.has_meta("elev"):
		return 0.0
	var y := 0.0
	for s in curve.get_meta("elev"):
		if d <= s["a"] or d >= s["e"]:
			continue
		if d < s["b"]:
			y += s["h"] * smoothstep(s["a"], s["b"], d)
		elif d <= s["c"]:
			y += s["h"]
		else:
			y += s["h"] * (1.0 - smoothstep(s["c"], s["e"], d))
	return y


## Steigung (Höhe pro Meter) bei d
static func slope_at(curve: Curve3D, d: float) -> float:
	if not curve.has_meta("elev"):
		return 0.0
	return (elev_at(curve, d + 1.0) - elev_at(curve, d - 1.0)) / 2.0


## Transform an Streckenposition d, seitlich versetzt um lateral, Blick in Fahrtrichtung, auf Fahrbahnhöhe.
## pitched: zusätzlich entlang der Steigung geneigt (Verkehr)
static func xform_at(curve: Curve3D, d: float, lateral: float, pitched := false) -> Transform3D:
	var f := frame_at(curve, d)
	var pos: Vector3 = f["pos"] + f["right"] * lateral
	var basis := Basis.looking_at(f["fwd"], Vector3.UP)
	if pitched:
		basis = basis * Basis(Vector3.RIGHT, atan(slope_at(curve, d)))
	return Transform3D(basis, Vector3(pos.x, f["y"], pos.z))


# --- Abfragen für Fahrzeuge -----------------------------------------------------

## Halbe Breite des Mittelstreifens bei d (0 = kein Mittelstreifen), mit weichem Übergang
static func median_at(track: Dictionary, d: float) -> float:
	if track["loop"]:
		d = fposmod(d, track["length"])
	var m := 0.0
	for r in track["medians"]:
		if d > r["from"] and d < r["to"]:
			m = maxf(m, MED * smoothstep(0.0, 1.0, minf(d - r["from"], r["to"] - d) / MED_TAPER))
	return m


## Halbe Fahrbahnbreite der Hauptstraße bei d (breiter, wo ein Mittelstreifen ist)
static func hw(track: Dictionary, d: float) -> float:
	return HALF_W + track["extra"] + median_at(track, d)


## Spur (-6.75..6.75, ohne Mittelstreifen gedacht) -> tatsächlicher Querversatz bei d
static func lane_lat(track: Dictionary, d: float, lane: float) -> float:
	return lane + signf(lane) * median_at(track, d)


## Tatsächlicher Querversatz -> Spur-Koordinate (Mittelstreifen herausgerechnet)
static func logical_lat(track: Dictionary, d: float, lat: float) -> float:
	var m := median_at(track, d)
	return signf(lat) * maxf(absf(lat) - m, 0.0)


## Auf welchem Weg steht pos? Liefert {path, d, lat, score}; score < 0 heißt "auf der Fahrbahn".
static func locate(track: Dictionary, pos: Vector3) -> Dictionary:
	var best := {}
	var best_score := 1e9
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var d := c.get_closest_offset(pos)
		var f := frame_at(c, d)
		var dist := _flat(pos - f["pos"]).length()
		var lat: float = (pos - f["pos"]).dot(f["right"])
		var score: float = dist - (hw(track, d) if p["id"] == 0 else p["half_w"])
		if p["id"] != 0:
			score += 0.5  # bei Überlappung (Einmündungen) gilt die Hauptstraße
		if score < best_score:
			best_score = score
			best = {"path": p, "d": d, "lat": lat, "score": score}
	return best


## Rennfortschritt in Metern der Hauptstraße
static func race_progress(loc: Dictionary) -> float:
	var p: Dictionary = loc["path"]
	if p["id"] == 0:
		return loc["d"]
	return lerpf(p["from"], p["to"], clampf(loc["d"] / p["length"], 0.0, 1.0))


## Bodenhöhe und Wasser an einer Weg-Position (Rampen, Gehweg)
## "base" ist die Höhe der Fahrbahn (Trog, Bergstraße), "h" kommt Bordstein oder Rampe obendrauf
static func ground_path(track: Dictionary, path_id: int, d: float, lat: float, score := -1.0) -> Dictionary:
	var base := elev_at(track["paths"][path_id]["curve"], d)
	var h := 0.0
	var on_ramp := false
	if path_id == 0 and (score > 0.2 or absf(lat) < median_at(track, d) - 0.2):
		h = CURB_H  # Gehweg oder Mittelstreifen
	for r in track["ramps"]:
		if r["path"] == path_id and d >= r["d0"] and d <= r["d1"] and lat >= r["lat0"] and lat <= r["lat1"]:
			var rh: float = r["h"] * (d - r["d0"]) / (r["d1"] - r["d0"])
			if rh > h:
				h = rh
				on_ramp = true
	return {"h": base + h, "base": base, "ramp": on_ramp, "water": false}


static func ground(track: Dictionary, loc: Dictionary, pos: Vector3) -> Dictionary:
	var p: Dictionary = loc["path"]
	var g := ground_path(track, p["id"], loc["d"], loc["lat"], loc["score"])
	for lk in track["lakes"]:
		var l: Vector3 = pos - lk["center"]
		if absf(l.dot(lk["au"])) < lk["hu"] and absf(l.dot(lk["av"])) < lk["hv"]:
			var in_gap: bool = loc["d"] > lk["gap0"] and loc["d"] < lk["gap1"]
			var on_causeway: bool = p["id"] == lk["path"] and absf(loc["lat"]) <= p["half_w"] + 0.4 and not in_gap
			if not on_causeway:
				# kein Boden unter dem Wasser: wer zu kurz springt oder abkommt, fällt hinein
				g["water"] = true
				g["h"] = g["base"] - WATER_DROP
	return g


# --- Planung ----------------------------------------------------------------

static func _in_zone(track: Dictionary, d: float, margin: float) -> bool:
	for z in track["zones"]:
		if d > z["from"] - margin and d < z["to"] + margin:
			return true
	return false


## Abstand zur nächsten Nebenstraße (Abkürzung/Seitenstraße) minus deren halbe Breite
## skip_spurs: Sackgassen ignorieren (deren Einmündung ist abgesperrt, die Randmauer läuft dort durch)
static func _branch_clearance(track: Dictionary, pos: Vector3, skip_spurs := false) -> float:
	var best := 1e9
	for p in track["paths"]:
		if p["id"] == 0 or (skip_spurs and p["kind"] == "spur"):
			continue
		var c: Curve3D = p["curve"]
		var q := c.get_closest_point(pos)
		best = minf(best, _flat(pos - q).length() - p["half_w"])
	return best


static func _main_clearance(track: Dictionary, pos: Vector3) -> float:
	var c: Curve3D = track["curve"]
	return _flat(pos - c.get_closest_point(pos)).length() - hw(track, c.get_closest_offset(pos))


## Abstand zum Bahngelände: zwei Gleise mit Oberleitung, auf der Bahnhofsseite Bahnsteige und Empfangsgebäude
static func _rail_clearance(track: Dictionary, pos: Vector3) -> float:
	if track["crossing_d"] < 0.0:
		return 1e9
	var f := frame_at(track["curve"], track["crossing_d"])
	var along: float = (pos - f["pos"]).dot(f["right"]) * RailCrossing.STATION_SIDE
	var across := absf((pos - f["pos"]).dot(f["fwd"]))
	var edge := HALF_W + WALK + 0.5
	if along > edge - 2.0 and along < edge + RailCrossing.PLAT_LEN + 14.0:
		return across - 19.5
	return across - 6.5


static func _in_lake(track: Dictionary, pos: Vector3, margin: float) -> bool:
	for lk in track["lakes"]:
		var l: Vector3 = pos - lk["center"]
		if absf(l.dot(lk["au"])) < lk["hu"] + margin and absf(l.dot(lk["av"])) < lk["hv"] + margin:
			return true
	return false


static func _plan_shortcut(track: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var a: float = b["a"]
	var p0: Vector3 = b["p0"]
	var du := _dir(b["heading"])
	var dv := Vector3(-du.z, 0, du.x)
	var vb := signf((b["p1"] - p0).dot(dv))  # Richtung zur Ausbuchtung der Hauptstraße
	var w := 1.0 if rng.randf() < 0.5 else -1.0
	var lake: bool = b["kind"] == "lake"
	var fork: bool = b["kind"] == "fork"
	var half := SC_HALF if lake else (FORK_HALF if fork else ALLEY_HALF)
	var uv: Array
	if fork:
		uv = [[0.0, 0.0], [0.22, 5.0 * w], [0.5, -4.0 * w], [0.78, 4.0 * w], [1.0, 0.0]]
	elif lake:
		uv = [[0.0, 0.0], [0.16, 6.0 * w], [0.3, -4.0 * w], [0.4, 0.0], [0.5, 0.0], [0.6, 0.0], [0.7, 0.0],
			[0.78, 0.0], [0.9, 5.0 * w], [1.0, 0.0]]
	else:
		uv = [[0.0, 0.0], [0.18, 3.5 * w], [0.36, -3.5 * w], [0.54, 3.5 * w], [0.72, -3.5 * w], [0.88, 2.5 * w], [1.0, 0.0]]
	var pts := []
	for e in uv:
		pts.append(p0 + du * (e[0] * a) + dv * e[1])
	var sc := Curve3D.new()
	sc.bake_interval = 1.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (nxt - prev) * 0.2
		sc.add_point(pts[i], -t, t)
	var path := {"id": track["paths"].size(), "kind": b["kind"], "curve": sc, "half_w": half,
		"length": sc.get_baked_length(), "from": curve.get_closest_offset(p0), "to": curve.get_closest_offset(b["p2"]),
		"closed": false, "p0": p0, "p1": b["p1"], "p2": b["p2"]}
	if fork:
		# Außen herum: breiter Boulevard mit Mittelstreifen (schnell, aber länger)
		path["route"] = ["ALTSTADT", "BOULEVARD"]
		track["medians"].append({"from": path["from"] + 55.0, "to": path["to"] - 55.0, "fork": true})
		# Die Altstadt liegt auf einem Hügel: die Gabelung zweigt nach oben ab, über eine Kuppe und wieder hinunter
		var fl: float = path["length"]
		sc.set_meta("elev", [{"a": 0.18 * fl, "b": 0.44 * fl, "c": 0.56 * fl, "e": 0.82 * fl, "h": HILL_H * clampf(fl / 170.0, 0.6, 1.2)}])
	track["paths"].append(path)
	track["zones"].append({"from": path["from"] - 30.0, "to": path["from"] + 45.0})
	track["zones"].append({"from": path["to"] - 45.0, "to": path["to"] + 30.0})
	if lake:
		# Seit 2.24 ohne Sprungschanze und Lücke (wirkte wie eine Schanze im Nirgendwo): die Abkürzung führt auf einem
		# Damm mit niedrigen Mauern durch den See. gap0 > gap1 heißt: keine Lücke.
		# Der See bleibt im Dreieck zwischen Abkürzung und Hauptstraße (die Ecken mit gut 16 m Abstand zu deren Mitte),
		# sonst stünde an der Ausfahrt die Hauptstraße unter Wasser
		track["lakes"].append({"path": path["id"], "center": p0 + du * (0.52 * a) + dv * vb * 6.0,
			"au": du, "av": dv * vb, "hu": 0.22 * a, "hv": 29.0, "gap0": 1e9, "gap1": -1e9})
		track["parks"].append([p0, b["p1"], b["p2"]])


## Bahnübergang auf einem geraden Stück, auf einem flachen Bahndamm
static func _plan_crossing(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	for attempt in 120:
		var d := rng.randf_range(0.28, 0.75) * L
		if _in_zone(track, d, 140.0) or _near_median(track, d - 120.0, d + 60.0):
			continue
		var f0 := frame_at(curve, d - 45.0)
		var f1 := frame_at(curve, d + 80.0)
		if (f0["fwd"] as Vector3).angle_to(f1["fwd"]) > 0.12 or _in_zone(track, d + 80.0, 30.0):
			continue
		_set_crossing(track, d)
		return


static func _set_crossing(track: Dictionary, d: float) -> void:
	track["crossing_d"] = d
	track["zones"].append({"from": d - 80.0, "to": d + 45.0})
	track["elev0"].append({"a": d - 32.0, "b": d - 6.0, "c": d + 6.0, "e": d + 32.0, "h": RAIL_DAM_H})


## Kreuzungen: kurze Seitenstraßen nach links und rechts (Sackgassen) mit Ampeln und Zebrastreifen
static func _plan_spurs(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	var count := 2 + int(L / 1400.0)
	for k in count:
		for attempt in 40:
			var d := rng.randf_range(0.1, 0.92) * L
			if _in_zone(track, d, 70.0) or _near_median(track, d - 50.0, d + 50.0):
				continue
			var f0 := frame_at(curve, d - 25.0)
			var f1 := frame_at(curve, d + 25.0)
			if (f0["fwd"] as Vector3).angle_to(f1["fwd"]) > 0.15:
				continue
			var f := frame_at(curve, d)
			var wet := false
			for side in [-1.0, 1.0]:
				for kk in [0.4, 1.0]:
					wet = wet or _in_river(track, f["pos"] + f["right"] * side * (HALF_W + WALK + 34.0) * kk, 10.0)
			if wet:
				continue
			for side in [-1.0, 1.0]:
				var sc := Curve3D.new()
				sc.bake_interval = 1.0
				sc.add_point(f["pos"])
				sc.add_point(f["pos"] + f["right"] * side * (HALF_W + WALK + 34.0))
				if rng.randf() < 0.7:
					# Seitenstraße den Hang hinauf (hinter der Absperrung, nur zum Anschauen)
					var sl := HALF_W + WALK + 34.0
					sc.set_meta("elev", [{"a": HALF_W + WALK + 3.0, "b": sl - 3.0, "c": sl + 10.0, "e": sl + 20.0, "h": rng.randf_range(3.5, 6.5)}])
				track["paths"].append({"id": track["paths"].size(), "kind": "spur", "curve": sc, "half_w": SPUR_HALF,
					"length": sc.get_baked_length(), "from": d, "to": d, "closed": true, "side": side})
			track["zones"].append({"from": d - 20.0, "to": d + 20.0})
			break


# --- Straßen ----------------------------------------------------------------

static func _road_mesh(root: Node3D, st: SurfaceTool, lanes: float, width: float, cobble: float, y := 0.0) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var key := Vector3(lanes, width, cobble)
	if not _road_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = ROAD_SHADER
		m.set_shader_parameter("lanes", lanes)
		m.set_shader_parameter("road_w", width)
		m.set_shader_parameter("cobble", cobble)
		m.set_shader_parameter("detail", ASPHALT_TEX)
		m.set_shader_parameter("detail_n", ASPHALT_N)
		_road_mats[key] = m
	mi.material_override = _road_mats[key]
	mi.position.y = y
	root.add_child(mi)
	return mi


## Gehweg-Material (Betonplatten, Bordsteine) für eine Gehwegbreite; liegt bei den Fahrbahn-Materialien, damit
## die Stimmung (nass/trocken) beide erreicht
static func _walk_mat(width: float) -> ShaderMaterial:
	var key := Vector3(-1.0, width, 0.0)
	if not _road_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = PAVEMENT_SHADER
		m.set_shader_parameter("walk_w", width)
		m.set_shader_parameter("detail", ASPHALT_TEX)
		_road_mats[key] = m
	return _road_mats[key]


## Detailstufen je nach Grafik-Einstellung: Kleinteile und mittlere Teile ab einer Entfernung nicht mehr zeichnen,
## entfernte Lampen ausblenden. ranges = [klein, mittel, Licht]. Im Nebel sieht man den Unterschied kaum.
static func apply_lod(n: Node, ranges: Array) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			var gi := c as GeometryInstance3D
			var size := gi.get_aabb().size.length()
			var cls: int = gi.get_meta("lod_class", 0 if size < 4.0 else (1 if size < 15.0 else 2))
			if cls == 0:
				gi.visibility_range_end = ranges[0]
			elif cls == 1:
				gi.visibility_range_end = ranges[1]
		elif c is Light3D:
			var l := c as Light3D
			l.distance_fade_enabled = true
			l.distance_fade_begin = ranges[2]
			l.distance_fade_length = 40.0
		elif c is GPUParticles3D and GameState.gv("fx") == 0:
			c.queue_free()  # Effekte niedrig: kein Gully-Dampf
			continue
		apply_lod(c, ranges)


## SurfaceTool (mit Dreiecken) als MeshInstance ablegen
static func _flush(root: Node3D, st: SurfaceTool, m: Material) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	root.add_child(mi)


## Wand von a nach b als senkrechte Fläche. Alle Flächen eines Körpers werden am Ende zu einem durchgehenden
## Dreiecksnetz (_finalize_walls): keine Kisten-Stöße, an denen man beim Entlangschrammen hängen bleibt.
## Schräge vom Gehweg-Rand (Stadtmauer) zur Trogmauer über 16 m, dazu ein gelb-schwarzer Anpralldämpfer.
## dir -1: liegt vor der Mauer (Einfahrt in Fahrtrichtung), +1: dahinter
static func _trough_wedge(root: Node3D, walls: StaticBody3D, track: Dictionary, d_wall: float, dir: float) -> void:
	var curve: Curve3D = track["curve"]
	var fa := frame_at(curve, d_wall + dir * 16.0)
	var fb := frame_at(curve, d_wall)
	var h: float = HALF_W + track["extra"] + median_at(track, d_wall)
	var yel := Builder.mat(Color(0.95, 0.7, 0.05), 0.0, 0.5, Color(0.95, 0.65, 0.05), 0.35)
	var blk := Builder.mat(Color(0.04, 0.04, 0.045), 0.0, 0.7)
	for sd in [-1.0, 1.0]:
		var a: Vector3 = fa["pos"] + fa["right"] * sd * (h + WALK + 0.3) + Vector3(0, fa["y"], 0)
		var b: Vector3 = fb["pos"] + fb["right"] * sd * (TUN_W + 0.1) + Vector3(0, fb["y"], 0)
		_wall_shape(walls, a, b)
		var len := a.distance_to(b)
		var bas := Basis.looking_at((b - a).normalized(), Vector3.UP)
		var k := 0
		var u := 0.6
		while u < len:
			Builder._add(root, Builder.box(Vector3(0.45, 0.9, 1.15)), yel if k % 2 == 0 else blk,
				a.lerp(b, u / len) + Vector3(0, CURB_H + 0.45, 0)).basis = bas
			k += 1
			u += 1.2


static func _wall_shape(walls: StaticBody3D, a: Vector3, b: Vector3, h := WALL_H) -> void:
	if not walls.has_meta("faces"):
		walls.set_meta("faces", [])
	var f: Array = walls.get_meta("faces")
	var lo := Vector3(0, -0.5, 0)
	var up := Vector3(0, h, 0)
	f.append_array([a + lo, b + lo, b + up, a + lo, b + up, a + up])


static func _finalize_walls(n: Node) -> void:
	for c in n.get_children():
		if c is StaticBody3D and c.has_meta("faces"):
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(PackedVector3Array(c.get_meta("faces")))
			var cs := CollisionShape3D.new()
			cs.shape = sh
			c.add_child(cs)
			c.remove_meta("faces")
		elif c.get_child_count() > 0 and not c is MeshInstance3D:
			_finalize_walls(c)


static func _build_road(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var carr := SurfaceTool.new()  # Richtungsfahrbahnen neben dem Mittelstreifen
	carr.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grass := SurfaceTool.new()
	grass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := StaticBody3D.new()
	root.add_child(walls)
	var walk_m := _walk_mat(WALK)
	var grass_m := Builder.mat(Color(0.05, 0.11, 0.05), 0.0, 0.95)
	var trough := SurfaceTool.new()  # Trogmauern vor und hinter den Tunneln
	trough.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trough_m := Builder.mat(Color(0.33, 0.33, 0.34), 0.0, 0.85)
	var n_trough := 0
	var guide := []
	var bushes := []
	var barriers := []
	var step := 3.0
	var d := 0.0
	var prev := {}
	var piece := 0
	var piece_d0 := 0.0
	var n_road := 0
	var n_carr := 0
	while d <= length:
		var f := frame_at(curve, d)
		var c: Vector3 = f["pos"]
		var r: Vector3 = f["right"]
		var Y := Vector3(0, f["y"], 0)
		var m := median_at(track, d)
		var h: float = HALF_W + track["extra"] + m
		var cur := {
			"l": c - r * h + Y, "r": c + r * h + Y, "ml": c - r * m + Y, "mr": c + r * m + Y, "m": m,
			"lw": c - r * (h + WALK + 0.3), "rw": c + r * (h + WALK + 0.3),
			"lo": c - r * (h + WALK), "ro": c + r * (h + WALK),
			"lm": c - r * (h + WALK * 0.5), "rm": c + r * (h + WALK * 0.5), "d": d,
			# Trog: Seitenstreifen bis zur Mauer auf Fahrbahnhöhe, oben auf Stadtniveau der Gehweg ab der Mauerkrone
			"tr": _trough_at(track, d), "y": f["y"], "dir": r,
			"lt": c - r * TUN_W + Y, "rt": c + r * TUN_W + Y, "lc": c - r * (TUN_W + 0.35), "rc": c + r * (TUN_W + 0.35),
		}
		if not prev.is_empty():
			var up := Vector3(0, CURB_H, 0)
			var in_tr: bool = cur["tr"] > 0 or prev["tr"] > 0
			var open: bool = in_tr and not (cur["tr"] == 2 and prev["tr"] == 2)
			if cur["m"] > 0.3 or prev["m"] > 0.3:
				# Zwei Richtungsfahrbahnen, dazwischen ein erhöhter Mittelstreifen
				_strip(carr, prev["l"], prev["ml"], cur["l"], cur["ml"], prev["d"], d)
				_strip(carr, prev["mr"], prev["r"], cur["mr"], cur["r"], prev["d"], d)
				_strip(grass, prev["ml"] + up, prev["mr"] + up, cur["ml"] + up, cur["mr"] + up, 0.0, 0.0)
				_strip_v(walk, prev["ml"], cur["ml"], CURB_H, false)
				_strip_v(walk, prev["mr"], cur["mr"], CURB_H, true)
				n_carr += 1
				var mm: float = minf(cur["m"], prev["m"])
				# Kollision genau an den Bordsteinkanten: spitz zulaufende Insel, an der man seitlich abgleitet
				if mm > 0.35:
					_wall_shape(walls, prev["ml"], cur["ml"], 1.6)
					_wall_shape(walls, prev["mr"], cur["mr"], 1.6)
				elif maxf(cur["m"], prev["m"]) > 0.35:
					# Spitze als Keil, der bis zur Mitte des vorigen Stücks zuläuft: man gleitet seitlich ab
					var wide: Dictionary = cur if cur["m"] > prev["m"] else prev
					var thin: Dictionary = prev if cur["m"] > prev["m"] else cur
					var tip: Vector3 = (thin["ml"] + thin["mr"]) / 2.0
					_wall_shape(walls, tip, wide["ml"], 1.6)
					_wall_shape(walls, tip, wide["mr"], 1.6)
				if mm > 1.2:
					var mid: Vector3 = (prev["ml"] + prev["mr"] + cur["ml"] + cur["mr"]) / 4.0 + up
					var bf := Basis.looking_at(f["fwd"], Vector3.UP)
					if _district_at(track, d).has("soundwall"):
						barriers.append(Transform3D(bf, mid))
					else:
						var k := 0.8 + 0.4 * sin(d * 1.7)
						bushes.append(Transform3D(bf * Basis.from_scale(Vector3(k * mm * 0.5, 0.75 * k, 1.3 * k)), mid + Vector3(0, 0.35, 0)))
			else:
				_strip(road, prev["l"], prev["r"], cur["l"], cur["r"], prev["d"], d)
				n_road += 1
			if (cur["tr"] > 0) != (prev["tr"] > 0):
				# Anfang/Ende der Trogmauer: schräger Anlauf mit Anpralldämpfer vom Gehweg her, sonst fährt man am
				# Bordstein frontal auf die Mauerkante und bleibt hängen
				_trough_wedge(root, walls, track, cur["d"] if cur["tr"] > 0 else prev["d"], -1.0 if cur["tr"] > 0 else 1.0)
			if in_tr:
				# Seitenstreifen auf Fahrbahnhöhe bis zur Trog-/Tunnelwand
				_strip(walk, prev["lt"] + up, prev["l"] + up, cur["lt"] + up, cur["l"] + up, prev["d"], d)
				_strip_v(walk, prev["l"], cur["l"], CURB_H, true)
				_strip(walk, prev["r"] + up, prev["rt"] + up, cur["r"] + up, cur["rt"] + up, prev["d"], d)
				_strip_v(walk, prev["r"], cur["r"], CURB_H, false)
				for sd in [-1.0, 1.0]:
					var kt := "lt" if sd < 0.0 else "rt"
					_wall_shape(walls, prev[kt] + prev["dir"] * sd * 0.1, cur[kt] + cur["dir"] * sd * 0.1)
				if open:
					# Trogmauer: innen von der Fahrbahn bis über den Gehweg, Krone, außen zum Gehweg der Stadt
					var top := CURB_H + PARAPET
					for sd in [-1.0, 1.0]:
						var kt := "lt" if sd < 0.0 else "rt"
						var kc := "lc" if sd < 0.0 else "rc"
						var ko := "lo" if sd < 0.0 else "ro"
						_wall_quad(trough, prev[kt] + up, cur[kt] + up, top, top, sd < 0.0)
						var at: Vector3 = prev[kt] + Vector3(0, top - prev["y"], 0)
						var bt: Vector3 = cur[kt] + Vector3(0, top - cur["y"], 0)
						var ac: Vector3 = prev[kc] + Vector3(0, top, 0)
						var bc: Vector3 = cur[kc] + Vector3(0, top, 0)
						if sd < 0.0:
							_strip(trough, ac, at, bc, bt, 0.0, 0.0)
						else:
							_strip(trough, at, ac, bt, bc, 0.0, 0.0)
						_wall_quad(trough, prev[kc] + up, cur[kc] + up, top, top, sd > 0.0)
						if sd < 0.0:
							_strip(walk, prev[ko] + up, prev[kc] + up, cur[ko] + up, cur[kc] + up, prev["d"], d)
						else:
							_strip(walk, prev[kc] + up, prev[ko] + up, cur[kc] + up, cur[ko] + up, prev["d"], d)
						# Leitlichter in der Mauer
						if int(d / step) % 2 == 0 and cur["y"] < -1.0:
							var gp: Vector3 = cur[kt] - cur["dir"] * sd * 0.02 + Vector3(0, 1.1, 0)
							guide.append(Transform3D(Basis.looking_at(cur["dir"] * sd, Vector3.UP), gp))
					n_trough += 1
			else:
				# Gehweg und Wand nur dort, wo keine Nebenstraße abzweigt
				if _branch_clearance(track, (prev["lm"] + cur["lm"]) / 2) > WALK * 0.5 + 0.5:
					_strip(walk, prev["lo"] + up, prev["l"] + up, cur["lo"] + up, cur["l"] + up, prev["d"], d)
					_strip_v(walk, prev["l"], cur["l"], CURB_H, true)
				if _branch_clearance(track, (prev["rm"] + cur["rm"]) / 2) > WALK * 0.5 + 0.5:
					_strip(walk, prev["r"] + up, prev["ro"] + up, cur["r"] + up, cur["ro"] + up, prev["d"], d)
					_strip_v(walk, prev["r"], cur["r"], CURB_H, false)
			for side in ["lw", "rw"]:
				if _branch_clearance(track, (prev[side] + cur[side]) / 2, true) > 1.0 and not (cur["tr"] == 2 and prev["tr"] == 2):
					_wall_shape(walls, prev[side], cur[side])
			piece += 1
		prev = cur
		d += step
		# In Stücken von 60 m ablegen: der Browser-Renderer beleuchtet jedes Objekt nur mit wenigen Lampen
		if piece >= 20 or (d > length and piece > 0):
			if n_road > 0:
				# Altstadt-Abschnitte mit Kopfsteinpflaster: jede Strecke fühlt sich anders an
				# (nicht in Tunnel und Trog: die sind asphaltiert)
				var cob := 1.0 if _district_at(track, piece_d0 + 30.0)["name"] == "ALTSTADT" \
					and _trough_at(track, piece_d0) == 0 and _trough_at(track, minf(d, length)) == 0 else 0.0
				_road_mesh(root, road, 4.0, HALF_W * 2.0, cob)
			if n_carr > 0:
				_road_mesh(root, carr, 2.0, HALF_W, 0.0)
				_flush(root, grass, grass_m)
			if n_trough > 0:
				_flush(root, trough, trough_m)
			_flush(root, walk, walk_m)
			for st in [road, walk, carr, grass, trough]:
				st.clear()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
			piece = 0
			piece_d0 = d
			n_road = 0
			n_carr = 0
			n_trough = 0
	var bush := SphereMesh.new()
	bush.radius = 1.0
	bush.height = 1.6
	bush.radial_segments = 8
	bush.rings = 4
	_multi(root, bush, Builder.mat(Color(0.05, 0.22, 0.07), 0.0, 0.9), bushes)
	_multi(root, Builder.tapered_box(Vector2(0.7, 3.1), Vector2(0.28, 3.1), 0.85, 0.0), Builder.mat(Color(0.42, 0.42, 0.43), 0.0, 0.85), barriers)
	_multi(root, Builder.box(Vector3(1.6, 0.08, 0.04)), Builder.mat(Color(1.0, 0.7, 0.3), 0.0, 0.4, Color(1.0, 0.6, 0.2), 4.0), guide)
	_build_median_lamps(root, track)


## Drift-Kurs: durchgehende Bande an beiden Rändern (rot-weiß, mit Sponsorentafeln), Reifenstapel außen in
## den Kurven und Flutlicht. Man kann sich nicht verfahren, nur anecken. (Publikum gibt es nur an Start und Ziel.)
static func _build_barriers(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var walls := StaticBody3D.new()
	root.add_child(walls)
	var concrete := Builder.mat(Color(0.55, 0.55, 0.56), 0.0, 0.8)
	var red := Builder.mat(Color(0.75, 0.06, 0.05), 0.0, 0.6)
	var white := Builder.mat(Color(0.88, 0.88, 0.88), 0.0, 0.6)
	var tire := Builder.mat(Color(0.04, 0.04, 0.045), 0.0, 0.9)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caps := {"r": [], "w": []}
	var tires := []
	var bh := 1.1
	var d := 0.0
	var prev := {}
	var k := 0
	while d <= length:
		var f := frame_at(curve, d)
		var b := hw(track, d) + 0.4
		var cur := {"l": f["pos"] - f["right"] * b, "r": f["pos"] + f["right"] * b, "d": d}
		if not prev.is_empty():
			for sd in ["l", "r"]:
				_wall_uv(st, prev[sd], cur[sd], bh, 0.0, 0.0, sd == "l")
				_wall_shape(walls, prev[sd], cur[sd])
				var mid: Vector3 = (prev[sd] + cur[sd]) / 2.0
				var bb := Basis.looking_at((cur[sd] - prev[sd]).normalized(), Vector3.UP)
				caps["r" if k % 2 == 0 else "w"].append(Transform3D(bb, mid + Vector3(0, bh + 0.08, 0)))
		# Kurvenaußenseite: Reifenstapel
		var f2 := frame_at(curve, d + 12.0)
		var bend := (f["fwd"] as Vector3).signed_angle_to(f2["fwd"], Vector3.UP)
		if absf(bend) > 0.12:
			var out := -1.0 if bend > 0.0 else 1.0  # Linkskurve: außen ist rechts
			for j in 3:
				tires.append(Transform3D(Basis(), f["pos"] + f["right"] * out * (b - 0.6) + Vector3(0, 0.2 + j * 0.38, 0)))
		prev = cur
		k += 1
		d += 3.0
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	concrete.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = concrete
	root.add_child(mi)
	_multi(root, Builder.box(Vector3(0.32, 0.16, 3.05)), red, caps["r"])
	_multi(root, Builder.box(Vector3(0.32, 0.16, 3.05)), white, caps["w"])
	var tm := CylinderMesh.new()
	tm.top_radius = 0.42
	tm.bottom_radius = 0.42
	tm.height = 0.36
	tm.radial_segments = 10
	_multi(root, tm, tire, tires)
	# Sponsorentafeln auf der Bande und Flutlicht
	var brands := ["DRIFTKÖNIGE", "NITROWERK", "KAIZEN", "TURBOSTARK", "RADIO VOLLGAS", "ONE HUMANITY", "SAKURA", "RONIN", "REIFENWERK"]
	var dd := 20.0
	var i := 0
	while dd < length - 10.0:
		var f := frame_at(curve, dd)
		for sd in [-1.0, 1.0]:
			var b := hw(track, dd) + 0.25
			var n := Node3D.new()
			n.transform = Transform3D(Basis.looking_at(f["right"] * sd, Vector3.UP), f["pos"] + f["right"] * sd * b)
			root.add_child(n)
			var col: Color = NEON[(i + int(sd)) % NEON.size()]
			Builder._add(n, Builder.box(Vector3(5.0, 0.7, 0.06)), Builder.mat(Color(0.05, 0.05, 0.07), 0.2, 0.5, col, 0.35), Vector3(0, 0.55, 0))
			var l := Label3D.new()
			l.text = brands[(i * 3 + int(sd + 1.0)) % brands.size()]
			l.font_size = 44
			l.pixel_size = 0.012
			l.modulate = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2)
			l.shaded = false
			l.double_sided = false
			l.position = Vector3(0, 0.55, 0.05)
			n.add_child(l)
		if i % 3 == 0:
			var sd2 := 1.0 if i % 2 == 0 else -1.0
			var fp: Vector3 = f["pos"] + f["right"] * sd2 * (hw(track, dd) + WALK + 1.5)
			Builder._add(root, Builder.box(Vector3(0.5, 16.0, 0.5)), Builder.mat(Color(0.3, 0.3, 0.32), 0.6, 0.4), fp + Vector3(0, 8.0, 0))
			Builder._add(root, Builder.box(Vector3(3.0, 1.6, 0.4)), Builder.mat(Color(1, 1, 1), 0.0, 0.3, Color(0.95, 0.97, 1.0), 8.0), fp + Vector3(0, 16.2, 0)).basis = Basis.looking_at(-f["right"] * sd2, Vector3.UP)
			var light := OmniLight3D.new()
			light.light_color = Color(0.9, 0.95, 1.0)
			light.light_energy = 2.2
			light.omni_range = 30.0
			light.position = fp + Vector3(0, 14.0, 0) - f["right"] * sd2 * 4.0
			root.add_child(light)
		i += 1
		dd += 32.0


## Doppel-Laternen auf dem Mittelstreifen, Warnpoller mit Blinklicht an beiden Spitzen
static func _build_median_lamps(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var pole := Builder.mat(Color(0.12, 0.12, 0.13), 0.6, 0.4)
	var warn := Builder.mat(Color(1.0, 0.75, 0.05), 0.0, 0.5, Color(1.0, 0.6, 0.0), 1.2)
	var stripe := Builder.mat(Color(0.05, 0.05, 0.05), 0.0, 0.6)
	var bm := ShaderMaterial.new()
	bm.shader = BLINK_SHADER
	bm.set_shader_parameter("col", Color(1.0, 0.6, 0.05))
	bm.set_shader_parameter("rate", 1.4)
	for r in track["medians"]:
		for nd in [r["from"] + MED_TAPER * 0.45, r["to"] - MED_TAPER * 0.45]:
			var nf := frame_at(curve, nd)
			var post := Knockable.new()
			post.mass = 15.0
			post.slowdown = 0.93
			post.position = nf["pos"] + Vector3(0, CURB_H, 0)
			root.add_child(post)
			Builder._add(post, Builder.box(Vector3(0.5, 1.1, 0.5)), warn, Vector3(0, 0.55, 0))
			Builder._add(post, Builder.box(Vector3(0.52, 0.18, 0.52)), stripe, Vector3(0, 0.75, 0))
			var sm := SphereMesh.new()
			sm.radius = 0.16
			sm.height = 0.32
			Builder._add(post, sm, bm, Vector3(0, 1.25, 0))
			_knock_shape(post, Vector3(0.5, 1.3, 0.5), Vector3(0, 0.65, 0))
		var d: float = r["from"] + 40.0
		while d < r["to"] - 30.0:
			if median_at(track, d) > MED * 0.9:
				var dist := _district_at(track, d)
				var lc: Color = dist["lamp"]
				var head := Builder.mat(lc, 0.0, 0.3, lc, 3.0)
				var f := frame_at(curve, d)
				var n := Node3D.new()
				n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + Vector3(0, CURB_H, 0))
				root.add_child(n)
				Builder._add(n, Builder.box(Vector3(0.22, 9.0, 0.22)), pole, Vector3(0, 4.5, 0))
				for s in [-1.0, 1.0]:
					Builder._add(n, Builder.box(Vector3(3.0, 0.14, 0.14)), pole, Vector3(s * 1.5, 9.0, 0))
					Builder._add(n, Builder.box(Vector3(0.9, 0.14, 0.5)), head, Vector3(s * 2.9, 8.92, 0))
				var light := OmniLight3D.new()
				light.light_color = lc
				light.light_energy = 2.4
				light.omni_range = 22.0
				light.omni_attenuation = 1.2
				light.position = Vector3(0, 8.4, 0)
				n.add_child(light)
				_solid(n, Vector3(0.4, 3.0, 0.4), Vector3(0, 1.5, 0))
			d += LAMP_STEP


## Horizontaler Streifen; a/b = vorherige Kante links/rechts, c/d = aktuelle.
static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float) -> void:
	# Von oben gesehen im Uhrzeigersinn (Godot-Vorderseite), Fahrtrichtung ist "oben"
	var verts := [[a, Vector2(0, v0)], [c, Vector2(0, v1)], [b, Vector2(1, v0)],
		[b, Vector2(1, v0)], [c, Vector2(0, v1)], [d, Vector2(1, v1)]]
	for vv in verts:
		st.set_uv(vv[1])
		st.add_vertex(vv[0])


## Senkrechte Fläche von den Fußpunkten a, b bis auf die absoluten Höhen ha, hb (Wicklung wie _strip_v)
static func _wall_quad(st: SurfaceTool, a: Vector3, b: Vector3, ha: float, hb: float, flip: bool) -> void:
	var at := Vector3(a.x, ha, a.z)
	var bt := Vector3(b.x, hb, b.z)
	var tris := [a, bt, b, a, at, bt] if flip else [a, b, bt, a, bt, at]
	for v in tris:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


static func _strip_v(st: SurfaceTool, a: Vector3, b: Vector3, h: float, flip: bool) -> void:
	var up := Vector3(0, h, 0)
	var tris := [a, b + up, b, a, a + up, b + up] if flip else [a, b, b + up, a, b + up, a + up]
	for v in tris:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


## Abkürzung oder Seitenstraße: Fahrbahn, Wände, Ausstattung
static func _build_branch(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	var kind: String = p["kind"]
	var gap0 := 1e9
	var gap1 := -1e9
	for lk in track["lakes"]:
		if lk["path"] == p["id"]:
			gap0 = lk["gap0"]
			gap1 = lk["gap1"]
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := StaticBody3D.new()
	root.add_child(walls)
	var hedge := Builder.mat(Color(0.04, 0.16, 0.06), 0.0, 0.9)
	var concrete := Builder.mat(Color(0.3, 0.3, 0.31), 0.0, 0.85)
	var walk_w := 3.0 if kind == "fork" else 0.0  # Gabelung: richtige Straße mit Gehwegen
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_walk := 0
	var ret := SurfaceTool.new()  # Stützmauern, wo die Straße den Hang hinaufführt
	ret.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_ret := 0
	var step := 2.0
	var d := 0.0
	var prev := {}
	while d <= len + 0.01:
		var f := frame_at(c, d)
		var cp: Vector3 = f["pos"] + Vector3(0, f["y"], 0)
		var r: Vector3 = f["right"]
		var cur := {"l": cp - r * half, "r": cp + r * half, "lw": cp - r * (half + walk_w + 0.3), "rw": cp + r * (half + walk_w + 0.3),
			"lo": cp - r * (half + walk_w), "ro": cp + r * (half + walk_w), "d": d, "y": f["y"]}
		if not prev.is_empty():
			if cur["y"] > 0.05 or prev["y"] > 0.05:
				# Außenseite: Mauer vom Boden bis zur Gehweg- bzw. Fahrbahnkante
				var lift := CURB_H if walk_w > 0.0 else 0.0
				var lk := "lo" if walk_w > 0.0 else "l"
				var rk := "ro" if walk_w > 0.0 else "r"
				_wall_quad(ret, Vector3(prev[lk].x, -0.05, prev[lk].z), Vector3(cur[lk].x, -0.05, cur[lk].z), prev[lk].y + lift, cur[lk].y + lift, false)
				_wall_quad(ret, Vector3(prev[rk].x, -0.05, prev[rk].z), Vector3(cur[rk].x, -0.05, cur[rk].z), prev[rk].y + lift, cur[rk].y + lift, true)
				n_ret += 1
			var mid: Vector3 = (prev["l"] + cur["r"]) / 2
			var in_gap: bool = d > gap0 and prev["d"] < gap1
			if _main_clearance(track, mid) > -0.3 and not in_gap:
				_strip(road, prev["l"], prev["r"], cur["l"], cur["r"], prev["d"], d)
			if walk_w > 0.0:
				var up := Vector3(0, CURB_H, 0)
				for sd in [["lo", "l", true], ["r", "ro", false]]:
					var outer: Vector3 = (prev[sd[0]] + cur[sd[0]]) / 2.0 if sd[2] else (prev[sd[1]] + cur[sd[1]]) / 2.0
					if _main_clearance(track, outer) > 0.5:
						_strip(walk, prev[sd[0]] + up, prev[sd[1]] + up, cur[sd[0]] + up, cur[sd[1]] + up, prev["d"], d)
						_strip_v(walk, prev["l" if sd[2] else "r"], cur["l" if sd[2] else "r"], CURB_H, sd[2])
						n_walk += 1
			for side in ["lw", "rw"]:
				var wm: Vector3 = (prev[side] + cur[side]) / 2
				# Sackgassen: Wände erst hinter der durchlaufenden Randmauer der Hauptstraße (keine Kante in deren Linie)
				if _main_clearance(track, wm) < WALK + (1.6 if kind == "spur" else 0.4):
					continue
				_wall_shape(walls, prev[side], cur[side])
				# Über der Sprunglücke nur unsichtbar: wer in der Luft seitlich abtreibt, schrammt daran entlang, statt
				# frontal gegen den Anfang der Wand hinter der Lücke zu prallen
				if d > gap0 - 1.0 and prev["d"] < gap1 + 1.0:
					continue
				var seg: Vector3 = cur[side] - prev[side]
				var basis := Basis.looking_at(seg.normalized(), Vector3.UP)
				if kind == "alley":
					_bb_box(Transform3D(basis * Basis.from_scale(Vector3(0.5, 4.5, seg.length() + 0.1)), wm + Vector3(0, 2.25, 0)),
						Vector3(0.24, 0.11, 0.07), 0.4, float(p["id"]), 4.0, 0.0, 0.0, FACE_WALL)
				elif kind == "lake":
					var near_lake := _in_lake(track, wm, 2.0)
					var hm := MeshInstance3D.new()
					hm.mesh = Builder.box(Vector3(0.6 if near_lake else 1.0, 0.5 if near_lake else 1.0, seg.length() + 0.1))
					hm.material_override = concrete if near_lake else hedge
					hm.transform = Transform3D(basis, wm + Vector3(0, 0.25 if near_lake else 0.5, 0))
					root.add_child(hm)
		prev = cur
		d += step
	var lanes := 2.0 if kind == "spur" or kind == "fork" else 0.0
	_road_mesh(root, road, lanes, half * 2.0, 1.0 if kind == "alley" else 0.0, 0.012)
	if n_walk > 0:
		_flush(root, walk, _walk_mat(walk_w))
	if n_ret > 0:
		_flush(root, ret, concrete)

	if kind in SHORTCUT_COL:
		_shortcut_lights(root, track, p, gap0, gap1)
	match kind:
		"fork":
			_fork_details(root, track, p, rng)
		"alley":
			_alley_details(root, track, p, rng)
		"lake":
			_shortcut_sign(root, track, p)
			var lamp_m := Builder.mat(Color(1, 0.85, 0.6), 0.0, 0.3, Color(1.0, 0.75, 0.45), 4.0)
			var dl := 12.0
			var s := 1.0
			while dl < len - 8.0:
				if dl < gap0 - 6.0 or dl > gap1 + 6.0:
					var f := frame_at(c, dl)
					var pos: Vector3 = f["pos"] + f["right"] * s * (half + 1.2)
					if _main_clearance(track, pos) > WALK + 1.0:
						var cyl := CylinderMesh.new()
						cyl.top_radius = 0.07
						cyl.bottom_radius = 0.09
						cyl.height = 4.0
						Builder._add(root, cyl, Builder.mat(Color(0.1, 0.1, 0.1), 0.5, 0.4), pos + Vector3(0, 2.0, 0))
						var sm := SphereMesh.new()
						sm.radius = 0.3
						sm.height = 0.6
						Builder._add(root, sm, lamp_m, pos + Vector3(0, 4.1, 0))
						var ol := OmniLight3D.new()
						ol.light_color = Color(1.0, 0.75, 0.45)
						ol.light_energy = 1.6
						ol.omni_range = 13.0
						ol.position = pos + Vector3(0, 3.8, 0)
						root.add_child(ol)
					s = -s
				dl += 22.0
		"spur":
			_spur_details(root, track, p, rng)


## Abkürzungen hell machen, wie ein Lichttunnel: alle 12 m ein leuchtender Bogen über der Fahrbahn (jeder zweite
## bzw. dritte mit Lampe), am ersten Bogen groß "ABKÜRZUNG", dazu Leuchtbänder an beiden Rändern, die den Weg zeigen.
## Seen-Dämme nur mit Leuchtbändern, dort wird über die Lücke gesprungen.
const SHORTCUT_COL := {"fork": Color(0.2, 0.85, 1.0), "alley": Color(1.0, 0.3, 0.75), "lake": Color(1.0, 0.75, 0.4)}


static func _shortcut_lights(root: Node3D, track: Dictionary, p: Dictionary, gap0: float, gap1: float) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	var kind: String = p["kind"]
	var col: Color = SHORTCUT_COL[kind]
	var neon := Builder.mat(col, 0.0, 0.4, col, 4.0)
	var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.5, 0.5)
	var walk_w := 3.0 if kind == "fork" else 0.0
	# Leuchtbänder: Gabelung auf der Bordsteinkante, Gasse am Fuß der Hauswand, Damm flach am Fahrbahnrand
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var prev := {}
	var d := 0.0
	while d <= len + 0.01:
		var f := frame_at(c, d)
		var y := Vector3(0, f["y"], 0)
		var r: Vector3 = f["right"]
		var cur := {"ok": _main_clearance(track, f["pos"]) > WALK + 1.0 and (d < gap0 - 2.0 or d > gap1 + 2.0)}
		for sd in [-1.0, 1.0]:
			var lat: float = {"fork": half + 0.12, "alley": half + 0.02, "lake": half - 0.15}[kind]
			cur[sd] = f["pos"] + r * sd * lat + y
		if not prev.is_empty() and prev["ok"] and cur["ok"]:
			for sd in [-1.0, 1.0]:
				if kind != "alley":
					var w: Vector3 = r * sd * 0.07
					var up := Vector3(0, (CURB_H if kind == "fork" else 0.0) + 0.015, 0)
					_strip(st, prev[sd] - w + up, prev[sd] + w + up, cur[sd] - w + up, cur[sd] + w + up, 0.0, 0.0)
				else:
					_wall_quad(st, prev[sd] + Vector3(0, 0.12, 0), cur[sd] + Vector3(0, 0.12, 0), prev[sd].y + 0.3, cur[sd].y + 0.3, sd > 0.0)
				n += 1
		prev = cur
		d += 4.0
	if n > 0:
		neon.cull_mode = BaseMaterial3D.CULL_DISABLED
		_flush(root, st, neon)
	if kind == "lake":
		return
	# Bögen; Gabelung mit Pfosten in der Randmauer (dort hängt man nicht), in der Gasse hängt der Bogen zwischen den
	# Fassaden und die Leuchtstreifen liegen flach auf der Hauswand
	var alley := kind == "alley"
	var span := half + 0.02 if alley else half + walk_w + 0.4
	var top := 4.3 if kind == "alley" else 5.6
	var lit := Color(col.r * 0.5 + 0.5, col.g * 0.5 + 0.5, col.b * 0.5 + 0.5)
	var k := 0
	var dd := 8.0
	while dd < len - 6.0:
		var f := frame_at(c, dd)
		if _main_clearance(track, f["pos"]) < span + WALK:
			dd += 4.0
			continue
		var b := Basis.looking_at(f["fwd"], Vector3.UP)
		var base: Vector3 = f["pos"] + Vector3(0, f["y"], 0)
		var r: Vector3 = f["right"]
		for sd in [-1.0, 1.0]:
			if not alley:
				Builder._add(root, Builder.box(Vector3(0.3, top, 0.3)), dark, base + r * sd * span + Vector3(0, top / 2.0, 0)).basis = b
			var inset := 0.0 if alley else 0.17
			Builder._add(root, Builder.box(Vector3(0.06, top - 0.5, 0.1)), neon, base + r * sd * (span - inset) + Vector3(0, top / 2.0, 0)).basis = b
		Builder._add(root, Builder.box(Vector3(span * 2.0 + 0.3, 0.32, 0.32)), dark, base + Vector3(0, top, 0)).basis = b
		Builder._add(root, Builder.box(Vector3(span * 2.0 - 0.3, 0.07, 0.14)), neon, base + Vector3(0, top - 0.19, 0)).basis = b
		if alley or k % 2 == 0:
			var ol := OmniLight3D.new()
			ol.light_color = lit
			ol.light_energy = 2.6 if alley else 3.2
			ol.omni_range = 14.0 if alley else 19.0
			ol.light_specular = 0.2
			ol.position = base + Vector3(0, top - 1.0, 0)
			root.add_child(ol)
		if k == 0:
			var l := Label3D.new()
			l.text = "ABKÜRZUNG"
			l.font_size = 96
			l.pixel_size = 0.012
			l.outline_size = 18
			l.modulate = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2)
			l.outline_modulate = Color(0, 0, 0, 0.9)
			l.shaded = false
			l.transform = Transform3D(b, base + Vector3(0, top + 0.75, 0))
			root.add_child(l)
		k += 1
		dd += 12.0


## Gabelung: Wegweiser vor der Teilung, Verkehrsinsel mit Büschen zwischen den Fahrbahnen, Laternen
static func _fork_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var main: Curve3D = track["curve"]
	var half: float = p["half_w"]
	# Auf welche Seite biegt die Hauptstraße ab? Dort steht "BOULEVARD", auf der anderen die Gabelung.
	var f0 := frame_at(main, p["from"])
	var vb := signf((p["p1"] - p["p0"]).dot(f0["right"]))
	var texts := ["< ALTSTADT", "BOULEVARD >"] if vb > 0.0 else ["< BOULEVARD", "ALTSTADT >"]
	var subs := ["kurz · Gegenverkehr", "breit · länger"] if vb > 0.0 else ["breit · länger", "kurz · Gegenverkehr"]
	var gd: float = p["from"] - 95.0
	if not _near_post(track, gd, 20.0):
		_gantry(root, track, gd, rng, texts, subs)
	# Verkehrsinsel: wer sich nicht entscheidet, landet in den Büschen
	var curb := Builder.mat(Color(0.35, 0.35, 0.36), 0.0, 0.85)
	var bush := Builder.mat(Color(0.05, 0.22, 0.07), 0.0, 0.9)
	var chev := Builder.mat(Color(1.0, 0.75, 0.05), 0.0, 0.5, Color(1.0, 0.6, 0.0), 1.5)
	var nose := false
	var u := 3.0
	while u < 110.0:
		var f := frame_at(c, u)
		var fp: Vector3 = f["pos"]
		var md := main.get_closest_offset(fp)
		var mf := frame_at(main, md)
		var off: Vector3 = fp - mf["pos"]
		off.y = 0.0
		var gap := off.length() - hw(track, md) - half
		if gap > 0.9 and gap < WALK * 2.0 + 1.0:
			var mid: Vector3 = mf["pos"] + off.normalized() * (hw(track, md) + gap / 2.0)
			var b := Basis.looking_at(mf["fwd"], Vector3.UP)
			var w := gap - 0.3
			var xf := Transform3D(b, mid + Vector3(0, 0.1, 0))
			Builder._add(root, Builder.box(Vector3(w, 0.2, 3.2)), curb, Vector3.ZERO).transform = xf
			# Büsche: wer reinfährt, verliert Tempo und Grünzeug fliegt
			var kb := Knockable.new()
			kb.mass = 40.0
			kb.slowdown = 0.93
			kb.transform = Transform3D(b, mid + Vector3(0, 0.2, 0))
			root.add_child(kb)
			var sm := SphereMesh.new()
			sm.radius = clampf(w * 0.4, 0.5, 1.4)
			sm.height = 1.4
			sm.radial_segments = 8
			sm.rings = 4
			Builder._add(kb, sm, bush, Vector3(0, 0.7, 0))
			_knock_shape(kb, Vector3(minf(w, 2.6), 1.4, 2.6), Vector3(0, 0.7, 0))
			if not nose:
				# Pfeilschild an der Spitze der Insel
				nose = true
				var sn := Knockable.new()
				sn.mass = 20.0
				sn.slowdown = 0.92
				sn.transform = Transform3D(b, mid - mf["fwd"] * 1.2)
				_knock_shape(sn, Vector3(1.2, 2.0, 0.4), Vector3(0, 1.0, 0))
				root.add_child(sn)
				Builder._add(sn, Builder.box(Vector3(0.1, 1.4, 0.1)), curb, Vector3(0, 0.7, 0))
				Builder._add(sn, Builder.box(Vector3(1.2, 0.8, 0.08)), chev, Vector3(0, 1.6, 0.06))
				var l := Label3D.new()
				l.text = "< >"
				l.font_size = 64
				l.pixel_size = 0.01
				l.modulate = Color(0.05, 0.05, 0.05)
				l.shaded = false
				l.position = Vector3(0, 1.6, 0.11)
				sn.add_child(l)
		u += 3.0
	# Laternen entlang der Gabelung
	var mats := {}
	var dist := _district_at(track, p["from"])
	var dl := 18.0
	var side := 1.0
	while dl < p["length"] - 15.0:
		var f := frame_at(c, dl)
		var base: Vector3 = f["pos"] + f["right"] * side * (half + 0.8) + Vector3(0, f["y"], 0)
		if _main_clearance(track, base) > WALK + 1.5:
			_lamp(root, dist, f, side, base, mats)
		side = -side
		dl += 32.0


## Gasse: Lichterketten, Müllcontainer, Kisten, Hinweisschild (Licht kommt von den Bögen, _shortcut_lights)
static func _alley_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	_shortcut_sign(root, track, p)
	var bulb_cols := [Color(1, 0.8, 0.45), Color(1, 0.4, 0.6), Color(0.5, 0.8, 1), Color(0.6, 1, 0.5)]
	var cable := Builder.mat(Color(0.03, 0.03, 0.03), 0.3, 0.6)
	var d := 18.0
	while d < len - 12.0:
		var f := frame_at(c, d)
		if _main_clearance(track, f["pos"]) > WALK + 4.0:
			var a: Vector3 = f["pos"] - f["right"] * (half + 0.3) + Vector3(0, 5.2, 0)
			var b: Vector3 = f["pos"] + f["right"] * (half + 0.3) + Vector3(0, 5.2, 0)
			for i in 9:
				var t := i / 8.0
				var q := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.9, 0)
				var col: Color = bulb_cols[i % bulb_cols.size()]
				var sm := SphereMesh.new()
				sm.radius = 0.09
				sm.height = 0.18
				sm.radial_segments = 6
				sm.rings = 3
				Builder._add(root, sm, Builder.mat(col, 0.0, 0.4, col, 6.0), q)
				if i < 8:
					var q2 := a.lerp(b, (i + 1) / 8.0) - Vector3(0, sin((i + 1) / 8.0 * PI) * 0.9, 0)
					var seg := q2 - q
					var cm := MeshInstance3D.new()
					cm.mesh = Builder.box(Vector3(0.02, 0.02, seg.length()))
					cm.material_override = cable
					cm.transform = Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), (q + q2) / 2)
					root.add_child(cm)
		d += 14.0
	# Container und Kisten an den Wänden (harte Hindernisse)
	var cols := [Color(0.1, 0.3, 0.15), Color(0.15, 0.2, 0.45), Color(0.45, 0.25, 0.08)]
	for i in 4:
		var dd := len * rng.randf_range(0.2, 0.8)
		var f := frame_at(c, dd)
		if _main_clearance(track, f["pos"]) < WALK + 6.0:
			continue
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var n := Node3D.new()
		var pos: Vector3 = f["pos"] + f["right"] * s * (half - 0.9)
		n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), pos)
		root.add_child(n)
		if i % 2 == 0:
			Builder._add(n, Builder.box(Vector3(1.4, 1.3, 2.0)), Builder.mat(cols[i % cols.size()], 0.4, 0.5), Vector3(0, 0.65, 0))
			Builder._add(n, Builder.box(Vector3(1.5, 0.1, 2.1)), Builder.mat(Color(0.05, 0.05, 0.05), 0.3, 0.5), Vector3(0, 1.35, 0))
			_solid(n, Vector3(1.4, 1.6, 2.0), Vector3(0, 0.8, 0))
		else:
			var crate := Builder.mat(Color(0.35, 0.24, 0.12), 0.0, 0.8)
			Builder._add(n, Builder.box(Vector3(1.0, 1.0, 1.0)), crate, Vector3(0, 0.5, 0))
			Builder._add(n, Builder.box(Vector3(0.9, 0.9, 0.9)), crate, Vector3(0.1, 1.45, 0.05))
			_solid(n, Vector3(1.0, 2.0, 1.0), Vector3(0, 1.0, 0))


## Orangefarbenes Schild "ABKÜRZUNG" an der Einfahrt
static func _shortcut_sign(root: Node3D, track: Dictionary, p: Dictionary) -> void:
	var c: Curve3D = p["curve"]
	var d := 4.0
	while d < 60.0 and _main_clearance(track, c.sample_baked(d)) < 2.0:
		d += 2.0
	var f := frame_at(c, d)
	var pos: Vector3 = f["pos"] + f["right"] * (p["half_w"] + 0.8)
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), pos)
	root.add_child(n)
	var orange := Builder.mat(Color(1, 0.5, 0.05), 0.0, 0.5, Color(1, 0.45, 0.0), 2.5)
	Builder._add(n, Builder.box(Vector3(0.1, 2.4, 0.1)), Builder.mat(Color(0.2, 0.2, 0.2), 0.5, 0.4), Vector3(0, 1.2, 0))
	Builder._add(n, Builder.box(Vector3(2.4, 0.8, 0.08)), orange, Vector3(0, 2.4, 0))
	var l := Label3D.new()
	l.text = "ABKÜRZUNG >>" if p["kind"] == "alley" else "SPRUNG! >>"
	l.font_size = 44
	l.pixel_size = 0.01
	l.modulate = Color(0, 0, 0)
	l.shaded = false
	l.position = Vector3(0, 2.4, 0.06)
	n.add_child(l)


## Seitenstraße: Zebrastreifen, Ampeln, Absperrung am Ende, Gebäude als Abschluss
static func _spur_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var main: Curve3D = track["curve"]
	var fm := frame_at(main, p["from"])
	var white := Builder.mat(Color(0.85, 0.85, 0.85), 0.0, 0.5)
	var side: float = p["side"]
	# Zebrastreifen über die Hauptstraße (je Kreuzung einmal) und über die Einmündung
	if side > 0.0:
		for off in [-(SPUR_HALF + 3.0), SPUR_HALF + 3.0]:
			var n := Node3D.new()
			n.transform = Transform3D(Basis.looking_at(fm["fwd"], Vector3.UP), fm["pos"] + fm["fwd"] * off + Vector3(0, 0.015, 0))
			root.add_child(n)
			for i in 9:
				Builder._add(n, Builder.box(Vector3(1.0, 0.02, 3.2)), white, Vector3(-HALF_W + 1.0 + i * 2.0, 0, 0))
	var fe := frame_at(c, HALF_W + WALK + 2.5)
	var zn := Node3D.new()
	zn.transform = Transform3D(Basis.looking_at(fe["fwd"], Vector3.UP), fe["pos"] + Vector3(0, 0.03, 0))
	root.add_child(zn)
	for i in 6:
		Builder._add(zn, Builder.box(Vector3(1.0, 0.02, 3.0)), white, Vector3(-SPUR_HALF + 1.0 + i * 2.0, 0, 0))
	# Ampel an der Ecke, für den Verkehr auf der Hauptstraße
	var corner: Vector3 = fm["pos"] + fm["right"] * side * (HALF_W + 1.0) - fm["fwd"] * side * (SPUR_HALF + 1.5)
	var tl := Node3D.new()
	var face: Vector3 = -fm["fwd"] * side
	tl.transform = Transform3D(Basis.looking_at(-face, Vector3.UP), corner + Vector3(0, CURB_H, 0))
	root.add_child(tl)
	var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.6, 0.4)
	Builder._add(tl, Builder.box(Vector3(0.18, 5.0, 0.18)), dark, Vector3(0, 2.5, 0))
	var arm := MeshInstance3D.new()
	arm.mesh = Builder.box(Vector3(3.2, 0.12, 0.12))
	arm.material_override = dark
	arm.position = Vector3(-1.5, 5.0, 0)  # lokales -X zeigt zur Fahrbahnmitte
	tl.add_child(arm)
	var head_pos := Vector3(-3.0, 4.4, 0)
	Builder._add(tl, Builder.box(Vector3(0.45, 1.3, 0.35)), dark, head_pos)
	var phase := rng.randf() * 12.0
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		sm.radial_segments = 8
		sm.rings = 4
		var lmat := ShaderMaterial.new()
		lmat.shader = LIGHT_SHADER
		lmat.set_shader_parameter("which", float(k))
		lmat.set_shader_parameter("phase", phase)
		Builder._add(tl, sm, lmat, head_pos + Vector3(0, 0.4 - k * 0.4, 0.18))
	# Einmündung abgesperrt (die Randmauer der Hauptstraße läuft hier durch): Baken mit Blinklicht
	var fb := frame_at(c, HALF_W + WALK + 0.3)
	var mouth := Node3D.new()
	mouth.transform = Transform3D(Basis.looking_at(fb["fwd"], Vector3.UP), fb["pos"])
	root.add_child(mouth)
	var red := Builder.mat(Color(0.9, 0.15, 0.1), 0.0, 0.6)
	var bm := ShaderMaterial.new()
	bm.shader = BLINK_SHADER
	bm.set_shader_parameter("col", Color(1.0, 0.6, 0.05))
	bm.set_shader_parameter("rate", 1.2)
	for i in 5:
		Builder._add(mouth, Builder.box(Vector3(2.4, 0.9, 0.5)), red if i % 2 == 0 else white, Vector3(-SPUR_HALF + 1.2 + i * 2.4, 0.45 + CURB_H, 0))
		if i % 2 == 0:
			var lamp := SphereMesh.new()
			lamp.radius = 0.13
			lamp.height = 0.26
			Builder._add(mouth, lamp, bm, Vector3(-SPUR_HALF + 1.2 + i * 2.4, 1.1 + CURB_H, 0))
	# Zuschauer hinter der Absperrung, mit Blick auf die Hauptstraße
	for i in rng.randi_range(5, 10):
		var dd := HALF_W + WALK + rng.randf_range(1.6, 6.0)
		var fs := frame_at(c, dd)
		var q: Vector3 = fs["pos"] + fs["right"] * rng.randf_range(-SPUR_HALF + 0.6, SPUR_HALF - 0.6)
		q.y = elev_at(c, dd)
		var look := Basis.looking_at(-fs["fwd"], Vector3.UP).rotated(Vector3.UP, rng.randf_range(-0.6, 0.6))
		track["spectators"].append([Transform3D(look, q), p["from"]])
	# Absperrung + Gebäude am Ende der Sackgasse
	var fz := frame_at(c, len - 1.0)
	var bar := Node3D.new()
	bar.transform = Transform3D(Basis.looking_at(fz["fwd"], Vector3.UP), fz["pos"] + Vector3(0, fz["y"], 0))
	root.add_child(bar)
	var stripe := Builder.mat(Color(0.9, 0.15, 0.1), 0.0, 0.6)
	for i in 5:
		Builder._add(bar, Builder.box(Vector3(2.4, 0.9, 0.5)), stripe if i % 2 == 0 else white, Vector3(-SPUR_HALF + 1.2 + i * 2.4, 0.45, 0))
	_solid(bar, Vector3(SPUR_HALF * 2.0 + 1.0, WALL_H, 0.6), Vector3(0, WALL_H / 2.0, 0))
	var h := rng.randf_range(14.0, 40.0)
	var seed := rng.randf() * 100.0
	# reicht bis zum Boden hinunter (die Seitenstraße kann den Hang hinaufführen)
	var hb: float = h + fz["y"]
	_bb_box(Transform3D(Basis.looking_at(fz["fwd"], Vector3.UP) * Basis.from_scale(Vector3(SPUR_HALF * 2.0 + 16.0, hb, 14.0)),
		fz["pos"] + fz["fwd"] * 8.0 + Vector3(0, hb / 2.0, 0)), Vector3(0.12, 0.12, 0.14), 0.4, seed, float(rng.randi() % 5), 1.0, -fz["y"])


## Sichtbare Begrenzung: überall, wo die (sonst unsichtbare) Randwand nicht von einem Haus verdeckt wird,
## steht ein Zaun genau auf ihrer Linie. So gibt es keine unsichtbaren Hindernisse.
static func _build_fences(root: Node3D, track: Dictionary, blockers: Array) -> void:
	var posts := []
	var rails := []
	var mesh_panels := []
	var lines := []  # [Weg, Querabstand-Funktion, Bedingung]
	var bgrid := {}  # Rasterzelle -> Häuser/Wahrzeichen (nur die nahen prüfen)
	var bmax := 0.0
	for b in blockers:
		var k := Vector2i(floori(b["pos"].x / LOT_CELL), floori(b["pos"].z / LOT_CELL))
		if not bgrid.has(k):
			bgrid[k] = []
		bgrid[k].append(b)
		bmax = maxf(bmax, b["r"])
	var breach := int(ceil((bmax * 0.85 + 1.5) / LOT_CELL))
	# frei von Häusern? (für Zuschauer hinter dem Zaun)
	var free := func(q: Vector3, margin: float) -> bool:
		var qk := Vector2i(floori(q.x / LOT_CELL), floori(q.z / LOT_CELL))
		for gx in range(qk.x - breach, qk.x + breach + 1):
			for gz in range(qk.y - breach, qk.y + breach + 1):
				for b in bgrid.get(Vector2i(gx, gz), []):
					if _flat(q - b["pos"]).length() < b["r"] * 0.85 + margin:
						return false
		return true
	var fan_rng := RandomNumberGenerator.new()
	fan_rng.seed = int(track["length"] * 7.0) + 11
	var next_fans := {-1.0: 30.0, 1.0: 70.0}  # frühestes d für die nächste Gruppe je Seite
	for p in track["paths"]:
		if p["id"] == 0 or p["kind"] == "fork" or p["kind"] == "spur":
			lines.append(p)
	for p in lines:
		var c: Curve3D = p["curve"]
		var len: float = p["length"]
		var main: bool = p["id"] == 0
		var d := 1.5
		while d < len - 1.5:
			var f := frame_at(c, d)
			for side in [-1.0, 1.0]:
				var lat: float = (hw(track, d) + WALK + 0.3) if main else (p["half_w"] + (3.3 if p["kind"] == "fork" else 0.3))
				var pos: Vector3 = f["pos"] + f["right"] * side * lat
				if main:
					if not bridge_at(track, d).is_empty():
						continue
					if _branch_clearance(track, pos) <= 1.0 or not tunnel_at(track, d, 3.0).is_empty() \
							or _district_at(track, d).has("soundwall") or _rail_clearance(track, pos) < 1.0:
						continue
				elif _main_clearance(track, pos) < WALK + 0.4:
					continue
				var hidden := false
				var pk := Vector2i(floori(pos.x / LOT_CELL), floori(pos.z / LOT_CELL))
				for gx in range(pk.x - breach, pk.x + breach + 1):
					for gz in range(pk.y - breach, pk.y + breach + 1):
						for b in bgrid.get(Vector2i(gx, gz), []):
							if _flat(pos - b["pos"]).length() < b["r"] * 0.85 + 1.5:
								hidden = true
								break
						if hidden:
							break
					if hidden:
						break
				if hidden:
					continue
				var bf := Basis.looking_at(f["fwd"], Vector3.UP)
				var base := Vector3(pos.x, CURB_H + (0.0 if main else f["y"]), pos.z)
				# Zuschauer: ab und zu eine Gruppe hinter dem Zaun, die dem Rennen zuschaut
				if main and d > next_fans[side] and absf(f["y"]) < 0.5 and fan_rng.randf() < 0.12:
					var n := fan_rng.randi_range(3, 7)
					var face := Basis.looking_at(-f["right"] * side, Vector3.UP)
					for i in n:
						var dd := d + fan_rng.randf_range(-2.5, 4.5)
						var ff := frame_at(c, dd)
						var q: Vector3 = ff["pos"] + ff["right"] * side * (hw(track, dd) + WALK + fan_rng.randf_range(0.9, 2.6))
						if free.call(q, 1.0):
							q.y = 0.0
							track["spectators"].append([Transform3D(face.rotated(Vector3.UP, fan_rng.randf_range(-0.5, 0.5)), q), d])
					next_fans[side] = d + fan_rng.randf_range(45.0, 110.0)
				posts.append(Transform3D(bf, base + Vector3(0, 0.6, 0)))
				for ry in [0.45, 1.05]:
					rails.append(Transform3D(bf, base + Vector3(0, ry, 0)))
				mesh_panels.append(Transform3D(bf, base + Vector3(0, 0.6, 0)))
			d += 3.0
	var metal := Builder.mat(Color(0.25, 0.26, 0.28), 0.7, 0.4)
	var mesh_m := Builder.mat(Color(0.3, 0.32, 0.34, 0.35), 0.6, 0.5)
	mesh_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_multi(root, Builder.box(Vector3(0.07, 1.2, 0.07)), metal, posts)
	_multi(root, Builder.box(Vector3(0.05, 0.05, 3.05)), metal, rails)
	_multi(root, Builder.box(Vector3(0.01, 1.05, 3.0)), mesh_m, mesh_panels)


## Kollisionsform für ein wegfliegendes Teil
static func _knock_shape(k: Node3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	k.add_child(cs)


static func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


# --- See, Park, Rampen ------------------------------------------------------

static func _build_lakes(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	var rim := Builder.mat(Color(0.32, 0.32, 0.33), 0.0, 0.85)
	for lk in track["lakes"]:
		var au: Vector3 = lk["au"]
		var av: Vector3 = lk["av"]
		var hu: float = lk["hu"]
		var hv: float = lk["hv"]
		var basis := Basis.looking_at(au, Vector3.UP)
		var water := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(hv * 2.0, hu * 2.0)
		water.mesh = pm
		water.material_override = wm
		water.transform = Transform3D(basis, lk["center"] + Vector3(0, 0.005, 0))
		root.add_child(water)
		# Uferkante
		for s in [-1.0, 1.0]:
			Builder._add(root, Builder.box(Vector3(0.6, 0.4, hu * 2.0)), rim, lk["center"] + av * s * hv + Vector3(0, 0.2, 0)).basis = basis
		# Schilf und ein paar Lichter auf dem Wasser
		for i in 10:
			var pos: Vector3 = lk["center"] + au * rng.randf_range(-hu, hu) + av * (hv - rng.randf_range(0.5, 3.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			if _branch_clearance(track, pos) < 3.0:
				continue
			for k in 4:
				var reed := MeshInstance3D.new()
				reed.mesh = Builder.box(Vector3(0.05, rng.randf_range(0.8, 1.6), 0.05))
				reed.material_override = Builder.mat(Color(0.12, 0.18, 0.06), 0.0, 0.9)
				reed.position = pos + Vector3(rng.randf_range(-0.6, 0.6), 0.5, rng.randf_range(-0.6, 0.6))
				reed.rotation = Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
				root.add_child(reed)
	# Grünfläche im Inneren des Bogens, mit Bäumen
	var grass := Builder.mat(Color(0.03, 0.08, 0.035), 0.0, 0.95)
	for tri in track["parks"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (b - a).cross(c - a)
		var verts := [a, b, c] if n.y < 0.0 else [a, c, b]
		for v in verts:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3(0, -0.02, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = grass
		root.add_child(mi)
		for i in 40:
			var r1 := rng.randf()
			var r2 := rng.randf()
			if r1 + r2 > 1.0:
				r1 = 1.0 - r1
				r2 = 1.0 - r2
			var pos := a + (b - a) * r1 + (c - a) * r2
			if _main_clearance(track, pos) < WALK + 3.0 or _branch_clearance(track, pos) < 3.0 or _in_lake(track, pos, 2.0):
				continue
			_tree(root, pos, rng, false)


static func _tree(root: Node3D, pos: Vector3, rng: RandomNumberGenerator, solid: bool) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 2.4
	trunk.radial_segments = 6
	Builder._add(root, trunk, Builder.mat(Color(0.12, 0.08, 0.05), 0.0, 0.9), pos + Vector3(0, 1.2, 0))
	var crown := SphereMesh.new()
	var r := rng.randf_range(1.2, 1.9)
	crown.radius = r
	crown.height = r * 2.3
	crown.radial_segments = 7
	crown.rings = 4
	var g := rng.randf_range(0.6, 1.1)
	Builder._add(root, crown, Builder.mat(Color(0.03 * g, 0.12 * g, 0.04 * g), 0.0, 0.9), pos + Vector3(0, 2.4 + r, 0))
	if solid:
		var sb := StaticBody3D.new()
		sb.position = pos + Vector3(0, 1.0, 0)
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()  # rund: wer streift, gleitet ab
		cy.radius = 0.22
		cy.height = 2.0
		cs.shape = cy
		sb.add_child(cs)
		root.add_child(sb)


## Keil: Breite x, Länge entlang -Z, steigt von 0 auf h.
static func _wedge(w: float, l: float, h: float) -> ArrayMesh:
	var bl0 := Vector3(-w / 2, 0, 0)
	var br0 := Vector3(w / 2, 0, 0)
	var bl1 := Vector3(-w / 2, 0, -l)
	var br1 := Vector3(w / 2, 0, -l)
	var tl := Vector3(-w / 2, h, -l)
	var tr := Vector3(w / 2, h, -l)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Builder._quad(st, bl0, br0, tr, tl)
	Builder._quad(st, br1, bl1, tl, tr)
	for tri in [[bl0, tl, bl1], [br0, br1, tr]]:
		var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		for v in [tri[0], tri[2], tri[1]]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


static func _build_ramps(root: Node3D, track: Dictionary) -> void:
	var rm := ShaderMaterial.new()
	rm.shader = RAMP_SHADER
	var lamp := Builder.mat(Color(1, 0.5, 0.05), 0.0, 0.4, Color(1, 0.45, 0.0), 5.0)
	for r in track["ramps"]:
		var p: Dictionary = track["paths"][r["path"]]
		var c: Curve3D = p["curve"]
		var lat: float = (r["lat0"] + r["lat1"]) / 2.0
		var w: float = r["lat1"] - r["lat0"]
		var l: float = r["d1"] - r["d0"]
		var x := xform_at(c, r["d0"], lat)
		x.origin.y = 0.0 if r["path"] == 0 else 0.012
		var n := Node3D.new()
		n.transform = x
		root.add_child(n)
		Builder._add(n, _wedge(w, l, r["h"]), rm, Vector3.ZERO)
		for s in [-1.0, 1.0]:
			Builder._add(n, Builder.box(Vector3(0.15, 0.15, 0.15)), lamp, Vector3(s * w / 2.0, r["h"] + 0.08, -l))
		# Stützen unter der Abrisskante; ohne Kollision, ihre Box reichte bis an die Kante und stoppte jeden, der
		# am Rand der Rampe absprang
		for s in [-1.0, 1.0]:
			Builder._add(n, Builder.box(Vector3(0.12, r["h"], 0.12)), Builder.mat(Color(0.1, 0.1, 0.1), 0.6, 0.4),
				Vector3(s * (w / 2.0 - 0.2), r["h"] / 2.0, -l - 0.1)).set_meta("no_collide", true)


# --- Wahrzeichen -------------------------------------------------------------

## Knoten am Straßenrand der Hauptstraße: lokales -Z zeigt zur Straße.
static func _roadside(root: Node3D, curve: Curve3D, d: float, side: float, dist: float) -> Node3D:
	var f := frame_at(curve, d)
	var n := Node3D.new()
	var pos: Vector3 = f["pos"] + f["right"] * side * dist
	n.transform = Transform3D(Basis.looking_at(-f["right"] * side, Vector3.UP), Vector3(pos.x, 0, pos.z))
	root.add_child(n)
	return n


static func _label(parent: Node3D, text: String, col: Color, size: int, pos: Vector3, glow := 2.5) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.02
	l.modulate = Color(col.r * glow, col.g * glow, col.b * glow)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = 180.0  # Label ist von +Z lesbar, Straße liegt bei -Z
	parent.add_child(l)
	return l


static func _any(text: String, keys: Array) -> bool:
	for k in keys:
		if k in text:
			return true
	return false


## Stil eines Ladenschilds nach der Ladenart (seit 2.24; bis 2.23 sah jedes Schild gleich aus: dunkler Kasten mit
## Neonrahmen in Zufallsfarbe). top/bottom: Farbverlauf, text: Schriftfarbe, glow: Leuchtkasten (1) oder angestrahlt
## (0), font: "cond", "wide" oder normal, band: 1 Grün-Weiß-Rot, 2 Schachbrett, emblem: "apo" (rotes Apotheken-A),
## "pole" (Friseur-Drehsäule), neon: alter Neon-Stil (Bars, Spielhallen, Tattoo).
static func _sign_style(name: String, rng: RandomNumberGenerator) -> Dictionary:
	var n := name.to_upper()
	if _any(n, ["APOTHEKE"]):
		return {"top": Color(0.08, 0.6, 0.3), "bottom": Color(0.02, 0.38, 0.16), "text": Color(1, 1, 1), "glow": 0.9, "emblem": "apo"}
	if _any(n, ["FRISEUR", "BARBIER", "HAIR"]):
		return {"top": Color(0.1, 0.12, 0.22), "bottom": Color(0.02, 0.03, 0.08), "text": Color(0.95, 0.95, 0.92), "glow": 0.15, "font": "wide", "emblem": "pole"}
	if _any(n, ["NAGEL", "KOSMETIK", "BEAUTY"]):
		return {"top": Color(1.0, 0.72, 0.86), "bottom": Color(0.95, 0.45, 0.66), "text": Color(0.38, 0.05, 0.22), "glow": 0.8}
	if _any(n, ["BÄCKER", "KONDITOR", "BACK"]):
		return {"top": Color(0.6, 0.36, 0.14), "bottom": Color(0.33, 0.17, 0.06), "text": Color(1.0, 0.88, 0.6), "glow": 0.45}
	if _any(n, ["METZGER", "FLEISCH"]):
		return {"top": Color(0.88, 0.12, 0.1), "bottom": Color(0.6, 0.04, 0.04), "text": Color(1, 1, 1), "glow": 0.8}
	if _any(n, ["PIZZA", "PIZZERIA", "TRATTORIA"]):
		return {"top": Color(0.98, 0.96, 0.9), "bottom": Color(0.86, 0.82, 0.74), "text": Color(0.68, 0.05, 0.08), "glow": 0.85, "band": 1, "font": "cond"}
	if _any(n, ["DÖNER", "CURRYWURST", "IMBISS", "SCHNITZEL", "WOK", "GRILL", "BURGER"]):
		return {"top": Color(1.0, 0.84, 0.12), "bottom": Color(0.96, 0.46, 0.05), "text": Color(0.5, 0.04, 0.02), "glow": 1.0, "font": "wide"}
	if _any(n, ["LOTTO"]):
		return {"top": Color(0.92, 0.14, 0.1), "bottom": Color(0.7, 0.05, 0.05), "text": Color(1.0, 0.9, 0.15), "glow": 0.9, "font": "wide"}
	if _any(n, ["KIOSK", "SPÄTI", "SPÄTKAUF", "24/7"]):
		return {"top": Color(0.12, 0.32, 0.78), "bottom": Color(0.04, 0.15, 0.5), "text": Color(1.0, 0.86, 0.12), "glow": 0.9, "font": "wide"}
	if _any(n, ["EISCAFÉ", "EIS", "BUBBLE"]):
		return {"top": Color(0.7, 0.96, 0.86), "bottom": Color(1.0, 0.74, 0.86), "text": Color(0.32, 0.08, 0.26), "glow": 0.75}
	if _any(n, ["CAFÉ", "KAFFEE", "TEEHAUS", "TEE"]):
		return {"top": Color(0.96, 0.91, 0.8), "bottom": Color(0.78, 0.65, 0.48), "text": Color(0.3, 0.16, 0.07), "glow": 0.6}
	if _any(n, ["JUWELIER", "GOLD", "JADE", "UHREN"]):
		return {"top": Color(0.1, 0.1, 0.1), "bottom": Color(0.01, 0.01, 0.01), "text": Color(1.0, 0.8, 0.36), "glow": 0.0, "font": "wide"}
	if _any(n, ["BANK", "SPARKASSE"]):
		return {"top": Color(0.08, 0.24, 0.6), "bottom": Color(0.02, 0.1, 0.36), "text": Color(1, 1, 1), "glow": 0.8, "font": "wide"}
	if n == "POST" or n.begins_with("POST"):
		return {"top": Color(1.0, 0.82, 0.0), "bottom": Color(0.95, 0.7, 0.0), "text": Color(0.05, 0.05, 0.05), "glow": 0.9, "font": "wide"}
	if _any(n, ["OPTIK"]):
		return {"top": Color(0.98, 0.98, 0.98), "bottom": Color(0.82, 0.85, 0.9), "text": Color(0.08, 0.24, 0.6), "glow": 0.8, "font": "wide"}
	if _any(n, ["BLUMEN", "GARTEN"]) and not "BIER" in n:
		return {"top": Color(0.38, 0.68, 0.26), "bottom": Color(0.14, 0.4, 0.12), "text": Color(1, 1, 0.95), "glow": 0.6}
	if _any(n, ["BUCH"]):
		return {"top": Color(0.09, 0.26, 0.16), "bottom": Color(0.03, 0.12, 0.07), "text": Color(0.96, 0.9, 0.74), "glow": 0.0}
	if _any(n, ["HANDY", "TELEFON"]):
		return {"top": Color(0.12, 0.62, 0.96), "bottom": Color(0.05, 0.3, 0.72), "text": Color(1, 1, 1), "glow": 1.0, "font": "wide"}
	if _any(n, ["WÄSCHE", "REINIGUNG"]):
		return {"top": Color(0.78, 0.92, 1.0), "bottom": Color(0.5, 0.75, 0.95), "text": Color(0.05, 0.2, 0.46), "glow": 0.8}
	if _any(n, ["TUNING", "REIFEN", "AUTOTEILE", "WERKSTATT"]):
		return {"top": Color(0.14, 0.14, 0.15), "bottom": Color(0.03, 0.03, 0.03), "text": Color(1.0, 0.5, 0.05), "glow": 0.1, "band": 2, "font": "wide"}
	if _any(n, ["FITNESS", "BOXEN"]):
		return {"top": Color(0.13, 0.13, 0.13), "bottom": Color(0.02, 0.02, 0.02), "text": Color(1.0, 0.16, 0.1), "glow": 0.0, "font": "wide"}
	if _any(n, ["WEIN", "GASTHAUS", "BRAUHAUS", "BIERGARTEN", "WIRTSHAUS"]):
		return {"top": Color(0.34, 0.19, 0.08), "bottom": Color(0.18, 0.09, 0.03), "text": Color(0.96, 0.8, 0.42), "glow": 0.0}
	if _any(n, ["SCHUH", "TURNSCHUH", "MODE", "BOUTIQUE"]):
		return {"top": Color(0.98, 0.98, 0.98), "bottom": Color(0.8, 0.8, 0.82), "text": Color(0.05, 0.05, 0.05), "glow": 0.85, "font": "wide"}
	if _any(n, ["DROGERIE"]):
		return {"top": Color(1, 1, 1), "bottom": Color(0.86, 0.9, 1.0), "text": Color(0.8, 0.05, 0.12), "glow": 0.9, "font": "wide"}
	if _any(n, ["REISE"]):
		return {"top": Color(0.25, 0.65, 1.0), "bottom": Color(1.0, 0.75, 0.3), "text": Color(1, 1, 1), "glow": 0.8}
	if _any(n, ["MUSIK", "VIDEO", "SPIELE", "GAMES"]):
		return {"top": Color(0.48, 0.12, 0.72), "bottom": Color(0.14, 0.03, 0.34), "text": Color(0.45, 1.0, 1.0), "glow": 0.7, "font": "wide"}
	if _any(n, ["SUSHI", "RAMEN", "NUDEL", "DIM SUM", "PHO", "ASIA", "DRACHE", "LOTUS", "PANDA", "TOFU", "FEUERTOPF", "GLÜCKS"]):
		return {"top": Color(0.78, 0.07, 0.05), "bottom": Color(0.45, 0.02, 0.02), "text": Color(1.0, 0.84, 0.36), "glow": 0.7}
	if _any(n, ["PFAND"]):
		return {"top": Color(0.08, 0.22, 0.14), "bottom": Color(0.02, 0.08, 0.05), "text": Color(1.0, 0.82, 0.4), "glow": 0.0, "font": "wide"}
	if _any(n, ["TATTOO", "SHISHA", "SPIELHALLE", "WETT", "KNEIPE", "KARAOKE", "MAHJONG", "BAR", "CLUB"]):
		return {"neon": true}
	# unbekannte Läden (z. B. echte Namen aus den Städten): meist ein ruhiger Leuchtkasten, manchmal Neon
	if rng.randf() < 0.3:
		return {"neon": true}
	var pal := [[Color(0.98, 0.98, 0.96), Color(0.82, 0.82, 0.8), Color(0.1, 0.1, 0.12)],
		[Color(0.12, 0.3, 0.62), Color(0.05, 0.14, 0.38), Color(1, 1, 1)],
		[Color(0.7, 0.08, 0.1), Color(0.42, 0.03, 0.05), Color(1, 0.95, 0.85)],
		[Color(0.16, 0.45, 0.3), Color(0.06, 0.24, 0.15), Color(1, 1, 0.95)],
		[Color(0.2, 0.2, 0.22), Color(0.06, 0.06, 0.07), Color(0.95, 0.85, 0.55)]]
	var c: Array = pal[rng.randi() % pal.size()]
	return {"top": c[0], "bottom": c[1], "text": c[2], "glow": rng.randf_range(0.4, 0.9), "font": ["", "cond", "wide"][rng.randi() % 3]}


## Ladenschild über der Markise: Kasten mit Farbverlauf (Leuchtkasten oder angestrahlt), Schrift und Zeichen je nach
## Ladenart (_sign_style). xf: Mitte des Kastens, +Z zeigt zur Straße; das Schild wird höchstens max_w breit.
static func _shop_sign(root: Node3D, text: String, xf: Transform3D, max_w: float, rng: RandomNumberGenerator) -> void:
	var st := _sign_style(text, rng)
	if st.get("neon", false):
		_sign_box(root, text, NEON[rng.randi() % NEON.size()], 64, 0.02, xf, max_w)
		return
	var size := 64
	var px := 0.02
	var font: Font = SIGN_FONTS.get(st.get("font", ""), ThemeDB.fallback_font)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * px
	var pad := size * px * 0.5
	var bh := size * px * 0.85 + pad
	var em := bh * 0.78 if st.get("emblem", "") == "apo" else 0.0
	if tw + em + 2.0 * pad > max_w:
		var k := maxf(max_w - em - 2.0 * pad, 0.5) / tw
		px *= k
		tw *= k
	var bw := tw + em + 2.0 * pad
	var d := 0.18
	var n := Node3D.new()
	n.transform = xf
	root.add_child(n)
	Builder._add(n, Builder.box(Vector3(bw, bh, d)), Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.45), Vector3.ZERO)
	var q := QuadMesh.new()
	q.size = Vector2(bw - 0.05, bh - 0.05)
	var m := ShaderMaterial.new()
	m.shader = SIGN_SHADER
	m.set_shader_parameter("top_col", st["top"])
	m.set_shader_parameter("bottom_col", st["bottom"])
	m.set_shader_parameter("glow", st["glow"])
	m.set_shader_parameter("band", st.get("band", 0))
	var qi := MeshInstance3D.new()
	qi.mesh = q
	qi.material_override = m
	qi.position = Vector3(0, 0, d / 2.0 + 0.004)
	qi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(qi)
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = px
	var tc: Color = st["text"]
	# Leuchtkasten: dunkle Schrift bleibt dunkel; angestrahlte Schilder: helle Schrift leicht leuchtend
	l.modulate = tc if st["glow"] > 0.3 else Color(tc.r * 1.25, tc.g * 1.25, tc.b * 1.25)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = Vector3(em / 2.0, 0.0 if st.get("band", 0) == 0 else bh * 0.05, d / 2.0 + 0.02)
	n.add_child(l)
	match st.get("emblem", ""):
		"apo":
			# rotes Apotheken-A auf weißem Grund links im Schild
			var ax := -bw / 2.0 + pad * 0.6 + em / 2.0
			Builder._add(n, Builder.box(Vector3(em, em, 0.03)), Builder.mat(Color(0.95, 0.95, 0.95), 0.0, 0.5, Color(1, 1, 1), 0.9), Vector3(ax, 0, d / 2.0 + 0.015))
			var al := Label3D.new()
			al.text = "A"
			al.font = SIGN_FONTS["wide"]
			al.font_size = 64
			al.pixel_size = em / 64.0 * 0.95
			al.modulate = Color(0.85, 0.04, 0.06)
			al.shaded = false
			al.double_sided = false
			al.position = Vector3(ax, 0, d / 2.0 + 0.035)
			n.add_child(al)
		"pole":
			# Friseur-Drehsäule neben dem Schild: weiß mit roten und blauen Ringen, leuchtend
			var cols := [Color(0.95, 0.95, 0.95), Color(0.85, 0.05, 0.05), Color(0.95, 0.95, 0.95), Color(0.05, 0.15, 0.75)]
			var ring := CylinderMesh.new()
			ring.top_radius = 0.13
			ring.bottom_radius = 0.13
			ring.height = 0.12
			ring.radial_segments = 12
			ring.rings = 1
			var px0 := bw / 2.0 + 0.32
			for i in 8:
				var c: Color = cols[i % 4]
				Builder._add(n, ring, Builder.mat(c, 0.0, 0.3, c, 0.8), Vector3(px0, -0.42 + i * 0.12, 0.15))
			for s in [-1.0, 1.0]:
				Builder._add(n, Builder.box(Vector3(0.3, 0.06, 0.3)), Builder.mat(Color(0.75, 0.75, 0.78), 0.9, 0.3), Vector3(px0, s * 0.52, 0.15))


## Leuchtkasten an einer Fassade: dunkler Kasten mit Neonrahmen, die Schrift leuchtet darauf. xf: Mitte des Kastens,
## +Z zeigt zur Straße. Zu lange Wörter werden kleiner gesetzt, damit der Kasten höchstens max_w breit wird.
static func _sign_box(root: Node3D, text: String, col: Color, size: int, px: float, xf: Transform3D, max_w: float) -> void:
	var tw := ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x * px
	var pad := size * px * 0.45
	if tw + 2.0 * pad > max_w:
		var k := maxf(max_w - 2.0 * pad, 0.5) / tw
		px *= k
		tw *= k
		pad = size * px * 0.45
	var bw := tw + 2.0 * pad
	var bh := size * px * 0.8 + pad
	var d := 0.2
	var n := Node3D.new()
	n.transform = xf
	root.add_child(n)
	Builder._add(n, Builder.box(Vector3(bw, bh, d)), Builder.mat(Color(0.03, 0.03, 0.04), 0.3, 0.5, col, 0.12), Vector3.ZERO)
	var rim := Builder.mat(col, 0.0, 0.4, col, 2.2)
	var t := minf(0.06, bh * 0.08)
	for s in [-1.0, 1.0]:
		Builder._add(n, Builder.box(Vector3(bw + t, t, t)), rim, Vector3(0, s * bh / 2.0, d / 2.0))
		Builder._add(n, Builder.box(Vector3(t, bh, t)), rim, Vector3(s * bw / 2.0, 0, d / 2.0))
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = Color(col.r * 1.8, col.g * 1.8, col.b * 1.8)
	l.shaded = false
	l.double_sided = false
	l.position = Vector3(0, 0, d / 2.0 + 0.02)
	n.add_child(l)


## Baut Kirche, Krankenhaus, Tankstelle, Stadion. Liefert belegte Flächen [{pos, r}] für die übrige Bebauung.
static func _build_landmarks(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> Array:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var occupied := []
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var plan := [[0.2, "church", 30.0], [0.38, "gas", 22.0], [0.55, "hospital", 26.0], [0.72, "stadium", 150.0], [0.88, "church", 30.0]]
	if length < 1800.0:
		plan.resize(3)
	elif length < 4000.0:
		plan.resize(4)
	if track["force_stadium"]:
		plan = [[0.5, "stadium", 150.0], [0.15, "gas", 22.0]]
	# Stadtpark mit Teich am Straßenrand (seit 2.25): statt Häusern Wasser, in dem sich Laternen und Häuser spiegeln
	plan.append([0.3, "pond", 26.0])
	if length > 2600.0:
		plan.append([0.64, "pond", 26.0])
	for entry in plan:
		var depth: float = entry[2]
		var placed := false
		var shifts := [0.0, 70.0, -70.0, 140.0, -140.0, 210.0]
		if entry[1] == "stadium":
			shifts.append_array([-210.0, 280.0, -280.0, 350.0, -350.0, 420.0, -420.0])
		for shift in shifts:
			var d: float = length * entry[0] + shift
			if _in_zone(track, d, 40.0):
				continue
			for s in [side, -side]:
				var dist := hw(track, d) + WALK + 1.5 + depth / 2.0
				var r: float = 66.0 if entry[1] == "stadium" else depth
				var f := frame_at(curve, d)
				var pos: Vector3 = f["pos"] + f["right"] * s * dist
				if _branch_clearance(track, pos) < r or _in_lake(track, pos, r) or _rail_clearance(track, pos) < r \
						or _main_clearance(track, pos) < dist - hw(track, d) - 2.0 or _el_side(track, d, depth) == s:
					continue
				var n := _roadside(root, curve, d, s, dist)
				match entry[1]:
					"church":
						_church(n)
					"gas":
						_gas_station(n)
					"hospital":
						_hospital(n)
					"stadium":
						_stadium(n, dist - hw(track, d) - WALK - 0.3, rng)
						track["stadium_d"] = d
					"pond":
						_pond(root, n, depth, rng)
						track["ponds"].append([d, s])
				occupied.append({"pos": n.position, "r": r + 6.0})
				placed = true
				side = -s
				break
			if placed:
				break
	return occupied


## Stadtpark mit Teich (seit 2.25) auf einem Bauplatz am Straßenrand: Rasen, ein unregelmäßig runder Teich mit
## Steinkante, Kiesweg drumherum und zur Straße, Bänke, Bäume, Parklaternen und ein niedriger Zaun mit Durchgang.
## Eine Reflexionssonde (einmal beim Laden) lässt Laternen, Bäume und Häuser im Wasser spiegeln. n: -Z zur Straße.
static func _pond(root: Node3D, n: Node3D, depth: float, rng: RandomNumberGenerator) -> void:
	var half := depth / 2.0
	var grass := Builder.mat(Color(0.03, 0.075, 0.035), 0.0, 0.95)
	var gravel := Builder.mat(Color(0.3, 0.27, 0.22), 0.0, 0.95)
	var stone := Builder.mat(Color(0.42, 0.41, 0.39), 0.0, 0.85)
	var iron := Builder.mat(Color(0.05, 0.05, 0.06), 0.6, 0.5)
	var wood := Builder.mat(Color(0.28, 0.17, 0.08), 0.0, 0.8)
	Builder._add(n, Builder.box(Vector3(depth + 4.0, 0.04, depth)), grass, Vector3(0, 0.02, 0))
	# Teich: Umriss aus Sinuswellen (kein Kreis), Mitte etwas von der Straße weg
	var c := Vector3(rng.randf_range(-1.5, 1.5), 0, 1.5)
	var rx := half * 0.62
	var rz := half * 0.5
	var ph := rng.randf() * TAU
	var outline := []
	var nseg := 48
	for i in nseg:
		var a := TAU * i / nseg
		var k := 1.0 + 0.09 * sin(a * 3.0 + ph) + 0.05 * sin(a * 5.0 + ph * 1.7)
		outline.append(c + Vector3(cos(a) * rx * k, 0, sin(a) * rz * k))
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var path := SurfaceTool.new()
	path.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nseg:
		var p0: Vector3 = outline[i]
		var p1: Vector3 = outline[(i + 1) % nseg]
		var d0 := (p0 - c).normalized()
		var d1 := (p1 - c).normalized()
		for v in [c, p1, p0]:
			water.set_normal(Vector3.UP)
			water.set_uv(Vector2(v.x, v.z))
			water.add_vertex(v + Vector3(0, 0.07, 0))  # über dem Rasen (Platte bis 0,04 m)
		# Steinkante: innen schräg ins Wasser, oben flach, außen schräg auf den Rasen
		var prof := [[-0.05, 0.03], [0.1, 0.2], [0.55, 0.22], [0.7, 0.05]]
		for j in prof.size() - 1:
			var a0: Vector3 = p0 + d0 * prof[j][0] + Vector3(0, prof[j][1], 0)
			var a1: Vector3 = p1 + d1 * prof[j][0] + Vector3(0, prof[j][1], 0)
			var b0: Vector3 = p0 + d0 * prof[j + 1][0] + Vector3(0, prof[j + 1][1], 0)
			var b1: Vector3 = p1 + d1 * prof[j + 1][0] + Vector3(0, prof[j + 1][1], 0)
			var nn := (b0 - a0).cross(a1 - a0).normalized()
			if nn.y < 0.0:
				nn = -nn
			for v in [a0, b0, b1, a0, b1, a1]:
				rim.set_normal(nn)
				rim.add_vertex(v)
		# Kiesweg rund um den Teich
		var g0a: Vector3 = p0 + d0 * 1.2
		var g0b: Vector3 = p0 + d0 * 2.8
		var g1a: Vector3 = p1 + d1 * 1.2
		var g1b: Vector3 = p1 + d1 * 2.8
		for v in [g0a, g0b, g1b, g0a, g1b, g1a]:
			path.set_normal(Vector3.UP)
			path.add_vertex(v + Vector3(0, 0.05, 0))
	# Weg vom Gehweg zum Teich
	var e0 := Vector3(-1.1, 0.05, -half)
	var e1 := Vector3(1.1, 0.05, -half)
	var e2 := Vector3(1.1, 0.05, c.z - rz - 1.6)
	var e3 := Vector3(-1.1, 0.05, c.z - rz - 1.6)
	for v in [e0, e3, e2, e0, e2, e1]:
		path.set_normal(Vector3.UP)
		path.add_vertex(v)
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	wm.set_shader_parameter("mirror", 1.0)
	wm.set_shader_parameter("deep", Color(0.02, 0.035, 0.05))
	for it in [[water, wm], [rim, stone], [path, gravel]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (it[0] as SurfaceTool).commit()
		mi.material_override = it[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	# Parklaternen am Weg (ihr Licht spiegelt sich im Wasser), Bänke zum Wasser hin
	var lamp_m := Builder.mat(Color(1, 0.9, 0.7), 0.0, 0.3, Color(1.0, 0.78, 0.5), 3.5)
	for i in 4:
		var a := ph + TAU * (i + 0.5) / 4.0
		var lp := c + Vector3(cos(a) * (rx + 3.3), 0, sin(a) * (rz + 3.3))
		Builder._add(n, Builder.box(Vector3(0.12, 3.4, 0.12)), iron, lp + Vector3(0, 1.7, 0))
		var lan := SphereMesh.new()
		lan.radius = 0.24
		lan.height = 0.5
		lan.radial_segments = 10
		lan.rings = 5
		Builder._add(n, lan, lamp_m, lp + Vector3(0, 3.55, 0))
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.78, 0.5)
		ol.light_energy = 1.8
		ol.omni_range = 11.0
		ol.position = lp + Vector3(0, 3.3, 0)
		n.add_child(ol)
		# Spiegelung der Laterne als schimmernder Streifen auf dem Wasser (zur Kamera hin)
		var gm := ShaderMaterial.new()
		gm.shader = GLINT_SHADER
		gm.set_shader_parameter("lamp", n.transform * (c + Vector3(cos(a) * rx * 0.95, 0.09, sin(a) * rz * 0.95)))
		gm.set_shader_parameter("pond_inv", Projection(n.transform.affine_inverse()))
		gm.set_shader_parameter("pond_c", c)
		gm.set_shader_parameter("pond_r", Vector2(rx, rz))
		var gq := MeshInstance3D.new()
		gq.mesh = QuadMesh.new()
		gq.material_override = gm
		gq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gq.custom_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 4, 80))
		gq.top_level = true
		gq.position = n.transform * c
		n.add_child(gq)
	for i in 3:
		var a := ph + TAU * i / 3.0 + 0.4
		var bp := c + Vector3(cos(a) * (rx + 3.2), 0, sin(a) * (rz + 3.2))
		var bench := Node3D.new()
		bench.transform = Transform3D(Basis.looking_at(Vector3(c.x - bp.x, 0, c.z - bp.z).normalized(), Vector3.UP), bp)
		n.add_child(bench)
		Builder._add(bench, Builder.box(Vector3(1.6, 0.06, 0.45)), wood, Vector3(0, 0.45, 0))
		Builder._add(bench, Builder.box(Vector3(1.6, 0.4, 0.06)), wood, Vector3(0, 0.75, 0.22))
		for s in [-0.7, 0.7]:
			Builder._add(bench, Builder.box(Vector3(0.06, 0.45, 0.4)), iron, Vector3(s, 0.22, 0))
	# Bäume hinten und an den Seiten (nicht zwischen Straße und Wasser, sonst sähe man den Teich nicht)
	for i in 7:
		var a := lerpf(0.15, PI - 0.15, float(i) / 6.0) + rng.randf_range(-0.12, 0.12)
		var tp := c + Vector3(cos(a) * (rx + 6.0), 0, sin(a) * (rz + 5.5))
		if absf(tp.x) > half + 1.0 or tp.z > half - 0.5:
			continue
		_tree(root, n.transform * tp, rng, false)
	# niedriger Zaun zur Straße, in der Mitte offen
	for sx in [-1.0, 1.0]:
		var x0: float = sx * 1.6
		var x1: float = sx * (half + 1.8)
		var fz := -half + 0.4
		Builder._add(n, Builder.box(Vector3(absf(x1 - x0), 0.05, 0.05)), iron, Vector3((x0 + x1) / 2.0, 0.9, fz))
		Builder._add(n, Builder.box(Vector3(absf(x1 - x0), 0.05, 0.05)), iron, Vector3((x0 + x1) / 2.0, 0.45, fz))
		var x: float = x0
		while absf(x) < absf(x1):
			Builder._add(n, Builder.box(Vector3(0.05, 1.0, 0.05)), iron, Vector3(x, 0.5, fz))
			x += sx * 2.0
	# Spiegelung: Sonde über dem Teich, einmal beim Laden aufgenommen
	var rp := ReflectionProbe.new()
	rp.size = Vector3(depth + 30.0, 18.0, depth + 30.0)
	rp.position = c + Vector3(0, 2.5, 0)
	rp.box_projection = false
	rp.max_distance = 140.0
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.intensity = 1.0
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	n.add_child(rp)


static func _church(n: Node3D) -> void:
	var stone := Builder.mat(Color(0.5, 0.47, 0.43), 0.0, 0.9)
	var slate := Builder.mat(Color(0.15, 0.17, 0.2), 0.3, 0.6)
	var gold := Builder.mat(Color(1, 0.8, 0.3), 0.8, 0.3, Color(1, 0.75, 0.3), 3.0)
	Builder._add(n, Builder.box(Vector3(12, 12, 24)), stone, Vector3(0, 6, 4))
	var roof := PrismMesh.new()
	roof.size = Vector3(12.8, 6, 24.4)
	Builder._add(n, roof, slate, Vector3(0, 15, 4))
	Builder._add(n, Builder.box(Vector3(6, 24, 6)), stone, Vector3(0, 12, -11))
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 4.2
	spire.height = 14.0
	spire.radial_segments = 4
	Builder._add(n, spire, slate, Vector3(0, 31, -11)).rotation_degrees.y = 45.0
	Builder._add(n, Builder.box(Vector3(0.3, 3.0, 0.3)), gold, Vector3(0, 39.5, -11))
	Builder._add(n, Builder.box(Vector3(1.6, 0.3, 0.3)), gold, Vector3(0, 40.0, -11))
	var clock := CylinderMesh.new()
	clock.top_radius = 1.4
	clock.bottom_radius = 1.4
	clock.height = 0.2
	clock.radial_segments = 16
	Builder._add(n, clock, Builder.mat(Color(1, 0.95, 0.8), 0, 0.5, Color(1, 0.9, 0.7), 2.5), Vector3(0, 19, -14.05)).rotation_degrees.x = 90
	Builder._add(n, Builder.box(Vector3(2.6, 4.5, 0.3)), Builder.mat(Color(0.3, 0.2, 0.1), 0, 0.5, Color(1, 0.6, 0.25), 1.5), Vector3(0, 2.25, -14.05))
	var glass_cols := [Color(0.2, 0.4, 1), Color(1, 0.2, 0.2), Color(1, 0.8, 0.2), Color(0.3, 1, 0.5)]
	for s in [-1, 1]:
		for i in 5:
			var gc: Color = glass_cols[(i + (1 if s > 0 else 0)) % glass_cols.size()]
			Builder._add(n, Builder.box(Vector3(0.2, 5.0, 1.6)), Builder.mat(gc, 0, 0.3, gc, 2.0), Vector3(s * 6.05, 6.5, -4.0 + i * 4.5))
	# Strebepfeiler und Rosette
	for s in [-1, 1]:
		for i in 6:
			Builder._add(n, Builder.box(Vector3(0.8, 9.0, 0.9)), stone, Vector3(s * 6.3, 4.5, -6.25 + i * 4.5))
	var rose := CylinderMesh.new()
	rose.top_radius = 1.6
	rose.bottom_radius = 1.6
	rose.height = 0.2
	rose.radial_segments = 12
	Builder._add(n, rose, Builder.mat(Color(0.6, 0.2, 0.8), 0, 0.3, Color(0.7, 0.3, 1.0), 2.5), Vector3(0, 12.0, -8.05)).rotation_degrees.x = 90
	for s in [-1, 1]:
		var sp := SpotLight3D.new()
		var pos := Vector3(s * 6.0, 0.5, -15.5)
		sp.transform = Transform3D(Basis.looking_at(Vector3(0, 18, -11) - pos, Vector3.UP), pos)
		sp.light_color = Color(1, 0.85, 0.6)
		sp.light_energy = 6.0
		sp.spot_range = 40.0
		sp.spot_angle = 22.0
		n.add_child(sp)


static func _hospital(n: Node3D) -> void:
	_bb_box(n.transform * Transform3D(Basis.from_scale(Vector3(44, 24, 18)), Vector3(0, 12, 6)), Vector3(0.55, 0.57, 0.6), 0.6, 3.0, 1.0, 0.0)
	var red := Builder.mat(Color(1, 0.05, 0.05), 0, 0.4, Color(1, 0.05, 0.05), 5.0)
	var white := Builder.mat(Color(0.9, 0.9, 0.92), 0.1, 0.5)
	Builder._add(n, Builder.box(Vector3(6, 6, 0.6)), white, Vector3(0, 27.5, -2.6))
	Builder._add(n, Builder.box(Vector3(1.4, 5, 0.3)), red, Vector3(0, 27.5, -2.95))
	Builder._add(n, Builder.box(Vector3(5, 1.4, 0.3)), red, Vector3(0, 27.5, -2.95))
	_label(n, "KRANKENHAUS", Color(0.7, 0.9, 1.0), 160, Vector3(0, 21, -3.1), 2.0)
	# Hubschrauberlandeplatz auf dem Dach
	var pad := CylinderMesh.new()
	pad.top_radius = 5.0
	pad.bottom_radius = 5.0
	pad.height = 0.2
	pad.radial_segments = 20
	Builder._add(n, pad, Builder.mat(Color(0.15, 0.15, 0.16), 0, 0.7), Vector3(12, 24.1, 8))
	var hl := Label3D.new()
	hl.text = "H"
	hl.font_size = 300
	hl.pixel_size = 0.02
	hl.modulate = Color(1.2, 1.2, 1.2)
	hl.shaded = false
	hl.position = Vector3(12, 24.22, 8)
	hl.rotation_degrees.x = -90
	n.add_child(hl)
	Builder._add(n, Builder.box(Vector3(14, 0.4, 6)), white, Vector3(-10, 4.2, -6))
	for x in [-16.5, -3.5]:
		Builder._add(n, Builder.box(Vector3(0.4, 4.2, 0.4)), white, Vector3(x, 2.1, -8.6))
	Builder._add(n, Builder.box(Vector3(9, 1.3, 0.3)), red, Vector3(-10, 5.1, -9.1))
	_label(n, "NOTAUFNAHME", Color(1, 1, 1), 90, Vector3(-10, 5.1, -9.3), 1.5)
	var ol := OmniLight3D.new()
	ol.position = Vector3(-10, 3.5, -6)
	ol.light_color = Color(0.85, 0.95, 1.0)
	ol.light_energy = 2.5
	ol.omni_range = 12.0
	n.add_child(ol)
	var amb := Node3D.new()
	amb.position = Vector3(-10, 0, -6)
	amb.rotation_degrees.y = 90
	n.add_child(amb)
	Builder._add(amb, Builder.box(Vector3(2.1, 2.3, 5.6)), white, Vector3(0, 1.45, 0))
	Builder._add(amb, Builder.box(Vector3(2.12, 0.3, 5.62)), Builder.mat(Color(0.9, 0.1, 0.05), 0, 0.5), Vector3(0, 1.3, 0))
	var blue := Builder.mat(Color(0.1, 0.3, 1), 0, 0.3, Color(0.1, 0.3, 1), 6.0)
	Builder._add(amb, Builder.box(Vector3(1.4, 0.18, 0.3)), blue, Vector3(0, 2.7, -2.4))
	var bl := OmniLight3D.new()
	bl.set_meta("no_pool", true)  # blinkt: kein fester Lichtkreis auf der Lichtkarte
	bl.position = Vector3(0, 3.2, -2.4)
	bl.light_color = Color(0.15, 0.35, 1.0)
	bl.omni_range = 14.0
	amb.add_child(bl)
	bl.ready.connect(func():
		var tw := bl.create_tween().set_loops()
		tw.tween_property(bl, "light_energy", 6.0, 0.08)
		tw.tween_property(bl, "light_energy", 0.0, 0.25)
		tw.tween_interval(0.15))


static func _gas_station(n: Node3D) -> void:
	var white := Builder.mat(Color(0.85, 0.85, 0.88), 0.2, 0.5)
	var red := Builder.mat(Color(0.8, 0.1, 0.1), 0.1, 0.5)
	var panel := Builder.mat(Color(1, 1, 1), 0, 0.4, Color(0.95, 0.97, 1.0), 3.0)
	Builder._add(n, Builder.box(Vector3(20, 0.8, 12)), white, Vector3(0, 5.6, -4))
	Builder._add(n, Builder.box(Vector3(20.1, 0.3, 12.1)), red, Vector3(0, 5.6, -4))
	Builder._add(n, Builder.box(Vector3(19, 0.08, 11)), panel, Vector3(0, 5.17, -4))
	for x in [-8.0, 8.0]:
		for z in [-8.0, 0.0]:
			Builder._add(n, Builder.box(Vector3(0.6, 5.2, 0.6)), white, Vector3(x, 2.6, z))
	var disp := Builder.mat(Color(0.2, 1, 0.4), 0, 0.4, Color(0.2, 1, 0.4), 3.0)
	for x in [-4.0, 4.0]:
		Builder._add(n, Builder.box(Vector3(1.4, 0.25, 5)), white, Vector3(x, 0.12, -4))
		Builder._add(n, Builder.box(Vector3(0.8, 1.8, 0.6)), red, Vector3(x, 1.1, -4))
		Builder._add(n, Builder.box(Vector3(0.5, 0.3, 0.62)), disp, Vector3(x, 1.5, -4))
	for x in [-5.0, 5.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 4.6, -4)
		l.light_energy = 3.0
		l.omni_range = 16.0
		l.light_color = Color(0.92, 0.96, 1.0)
		n.add_child(l)
	_bb_box(n.transform * Transform3D(Basis.from_scale(Vector3(14, 4.5, 8)), Vector3(0, 2.25, 6)), Vector3(0.3, 0.3, 0.32), 0.4, 9.0)
	_label(n, "24/7 SHOP", Color(1, 0.3, 0.3), 70, Vector3(0, 3.8, 1.9))
	Builder._add(n, Builder.box(Vector3(0.5, 9, 0.5)), white, Vector3(11, 4.5, -10))
	Builder._add(n, Builder.box(Vector3(3.4, 3.4, 0.4)), Builder.mat(Color(0.05, 0.05, 0.08), 0, 0.5), Vector3(11, 9.5, -10))
	_label(n, "TANKE\nSUPER  1,89\nDIESEL 1,79", Color(1, 0.8, 0.2), 40, Vector3(11, 9.5, -10.25))
	# Geparktes Auto an der Zapfsäule
	Builder._add(n, Builder.tapered_box(Vector2(1.8, 4.4), Vector2(1.7, 4.2), 0.65, 0.0), Builder.mat(Color(0.4, 0.05, 0.05), 0.5, 0.3), Vector3(-6.5, 0.25, -4))
	Builder._add(n, Builder.tapered_box(Vector2(1.6, 2.2), Vector2(1.3, 1.4), 0.5, 0.1), Builder.mat(Color(0.02, 0.03, 0.05), 0.7, 0.1), Vector3(-6.5, 0.9, -3.8))


# --- Orts-Strecken (echte Städte aus OpenStreetMap) ----------------------------

## Mittellinie aus den Kartendaten (flache Liste x, z); Rundkurse schließen mit dem ersten Punkt
static func _city_centerline(city: Dictionary) -> Dictionary:
	var flat: Array = city["points"]
	var pts := []
	for i in range(0, flat.size(), 2):
		pts.append(Vector3(flat[i], 0, flat[i + 1]))
	if city["loop"]:
		pts.append(pts[0])
	return {"pts": pts, "bulges": []}


static func _flat_pts(flat: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, flat.size(), 2):
		out.append(Vector2(flat[i], flat[i + 1]))
	return out


## Flüsse: nur der Abschnitt in Sichtweite der Strecke. Die Wasserbreite schrumpft dort, wo die Straße am Ufer
## entlangführt (Fahrbahn und Gehweg bleiben trocken). Wo die Hauptstraße den Fluss quert, entsteht eine Brücke.
static func _plan_rivers(track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var edge := HALF_W + WALK + 2.5
	for rv in track["city"]["rivers"]:
		var raw := _flat_pts(rv["pts"])
		var half: float = rv["width"] / 2.0
		var first := -1
		var last := -1
		for i in raw.size():
			var q := curve.get_closest_point(Vector3(raw[i].x, 0, raw[i].y))
			if Vector2(q.x, q.z).distance_to(raw[i]) < 1100.0:
				if first < 0:
					first = i
				last = i
		if first < 0 or last - first < 2:
			continue
		var pts := raw.slice(maxi(first - 2, 0), mini(last + 3, raw.size()))
		var lat := PackedFloat32Array()
		var offs := PackedFloat32Array()
		for p in pts:
			var off := curve.get_closest_offset(Vector3(p.x, 0, p.y))
			var f := frame_at(curve, off)
			lat.append((Vector3(p.x, 0, p.y) - f["pos"]).dot(f["right"]))
			offs.append(off)
		var hws := PackedFloat32Array()
		for i in pts.size():
			hws.append(clampf(absf(lat[i]) - edge, 0.0, half))
		# Querungen: Seitenwechsel zwischen zwei Flusspunkten nahe der Straße
		for i in pts.size() - 1:
			if signf(lat[i]) == signf(lat[i + 1]) or minf(absf(lat[i]), absf(lat[i + 1])) > pts[i].distance_to(pts[i + 1]) + 20.0:
				continue
			var t := absf(lat[i]) / maxf(absf(lat[i]) + absf(lat[i + 1]), 0.001)
			var dc := lerpf(offs[i], offs[i + 1], t)
			if not track["loop"] and (dc < 5.0 or dc > length - 5.0):
				continue
			var f := frame_at(curve, dc)
			var rdir := (pts[i + 1] - pts[i]).normalized()
			var sn := absf(rdir.dot(Vector2(f["right"].x, f["right"].z)))  # 1 = rechtwinklig gequert
			sn = maxf(sn, 0.35)
			var reach := (half + 12.0) / sn
			track["bridges"].append({"d": dc, "d0": dc - reach, "d1": dc + reach, "half": half})
			track["zones"].append({"from": dc - reach - 15.0, "to": dc + reach + 15.0})
			var cp := pts[i].lerp(pts[i + 1], t)
			# unter der Brücke volle Breite
			for k in pts.size():
				if pts[k].distance_to(cp) < (half + edge + 10.0) / sn:
					hws[k] = half
		track["rivers"].append({"name": rv["name"], "pts": pts, "hw": hws, "half": half})


## Abstand von pos zum Wasser (negativ = im Wasser), 1e9 ohne Fluss
static func _river_clearance(track: Dictionary, pos: Vector3) -> float:
	var best := 1e9
	var p := Vector2(pos.x, pos.z)
	for rv in track["rivers"]:
		var pts: PackedVector2Array = rv["pts"]
		var hws: PackedFloat32Array = rv["hw"]
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var hr := lerpf(hws[i], hws[i + 1], t)
			if hr < 1.5:
				continue
			best = minf(best, p.distance_to(a + ab * t) - hr)
	return best


## Wie _river_clearance, aber nur bis limit genau (darüber kommt limit zurück): sucht über ein Raster der Flussabschnitte
static func _river_near(track: Dictionary, pos: Vector3, limit: float) -> float:
	if not track.has("river_cells"):
		var cells := {}
		for rv in track["rivers"]:
			var rp: PackedVector2Array = rv["pts"]
			var rh: PackedFloat32Array = rv["hw"]
			for i in rp.size() - 1:
				var hr := maxf(rh[i], rh[i + 1])
				if hr < 1.5:
					continue
				var lo := Vector2(minf(rp[i].x, rp[i + 1].x), minf(rp[i].y, rp[i + 1].y)) - Vector2(hr, hr)
				var hi := Vector2(maxf(rp[i].x, rp[i + 1].x), maxf(rp[i].y, rp[i + 1].y)) + Vector2(hr, hr)
				for gx in range(floori(lo.x / LOT_CELL), floori(hi.x / LOT_CELL) + 1):
					for gz in range(floori(lo.y / LOT_CELL), floori(hi.y / LOT_CELL) + 1):
						var k := Vector2i(gx, gz)
						if not cells.has(k):
							cells[k] = []
						cells[k].append([rp[i], rp[i + 1], rh[i], rh[i + 1]])
		track["river_cells"] = cells
	var cells: Dictionary = track["river_cells"]
	var p := Vector2(pos.x, pos.z)
	var best := limit
	var reach := int(ceil(limit / LOT_CELL))
	var key := Vector2i(floori(p.x / LOT_CELL), floori(p.y / LOT_CELL))
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			for sg in cells.get(Vector2i(gx, gz), []):
				var a: Vector2 = sg[0]
				var ab: Vector2 = sg[1] - a
				var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
				var hr := lerpf(sg[2], sg[3], t)
				if hr >= 1.5:
					best = minf(best, p.distance_to(a + ab * t) - hr)
	return best


static func _in_river(track: Dictionary, pos: Vector3, margin: float) -> bool:
	return not track["rivers"].is_empty() and _river_clearance(track, pos) < margin


static func bridge_at(track: Dictionary, d: float) -> Dictionary:
	if track["loop"]:
		d = fposmod(d, track["length"])
	for b in track["bridges"]:
		if d > b["d0"] and d < b["d1"]:
			return b
	return {}


## Vieleck (Fächer) mit Normale n; Godot erwartet Dreiecke im Uhrzeigersinn von vorn gesehen
static func _poly(st: SurfaceTool, v: Array, nrm: Vector3) -> void:
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(nrm) > 0.0:
		v = v.duplicate()
		v.reverse()
	for i in range(1, v.size() - 1):
		for q in [v[0], v[i], v[i + 1]]:
			st.set_normal(nrm)
			st.add_vertex(q)


static func _build_rivers(root: Node3D, track: Dictionary) -> void:
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	var quay_m := Builder.mat(Color(0.26, 0.24, 0.21), 0.0, 0.9)
	var top_m := Builder.mat(Color(0.4, 0.38, 0.35), 0.0, 0.85)
	for rv in track["rivers"]:
		var pts: PackedVector2Array = rv["pts"]
		var hws: PackedFloat32Array = rv["hw"]
		var nrm := []
		for i in pts.size():
			var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			nrm.append(Vector2(-t.y, t.x))
		var water := SurfaceTool.new()
		water.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wall := SurfaceTool.new()
		wall.begin(Mesh.PRIMITIVE_TRIANGLES)
		var top := SurfaceTool.new()
		top.begin(Mesh.PRIMITIVE_TRIANGLES)
		var y := RIVER_Y
		for i in pts.size() - 1:
			if hws[i] < 1.5 or hws[i + 1] < 1.5:
				continue
			var e := []
			for k in [i, i + 1]:
				var c: Vector2 = pts[k]
				var nv: Vector2 = nrm[k]
				e.append([c + nv * hws[k], c - nv * hws[k], nv])
			var la: Vector2 = e[0][0]
			var ra: Vector2 = e[0][1]
			var lb: Vector2 = e[1][0]
			var rb: Vector2 = e[1][1]
			_poly(water, [Vector3(la.x, y, la.y), Vector3(lb.x, y, lb.y), Vector3(rb.x, y, rb.y), Vector3(ra.x, y, ra.y)], Vector3.UP)
			for s in [0, 1]:
				var a: Vector2 = e[0][s]
				var b: Vector2 = e[1][s]
				var out: Vector2 = e[0][2] * (1.0 if s == 0 else -1.0)
				# Ufermauer zeigt zum Wasser
				_poly(wall, [Vector3(a.x, y - 0.5, a.y), Vector3(b.x, y - 0.5, b.y), Vector3(b.x, 0.0, b.y), Vector3(a.x, 0.0, a.y)], Vector3(-out.x, 0, -out.y))
				var ob: Vector2 = e[1][2] * (1.0 if s == 0 else -1.0)
				_poly(top, [Vector3(a.x, 0.03, a.y), Vector3(b.x, 0.03, b.y), Vector3(b.x + ob.x * 2.2, 0.03, b.y + ob.y * 2.2),
					Vector3(a.x + out.x * 2.2, 0.03, a.y + out.y * 2.2)], Vector3.UP)
		for pair in [[water, wm], [wall, quay_m], [top, top_m]]:
			var mi := MeshInstance3D.new()
			mi.mesh = (pair[0] as SurfaceTool).commit()
			mi.material_override = pair[1]
			root.add_child(mi)
	for b in track["bridges"]:
		_road_bridge(root, track, b)


## Straßenbrücke: Fahrbahnplatte mit Gesims, Pfeiler im Wasser, Steinbrüstung mit Laternen
static func _road_bridge(root: Node3D, track: Dictionary, b: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var groups := {}
	var stone := Builder.mat(Color(0.42, 0.38, 0.32), 0.0, 0.85, Color(0.42, 0.38, 0.32), 0.12)
	var dark := Builder.mat(Color(0.05, 0.05, 0.055), 0.0, 0.9)
	var lamp := Builder.mat(Color(1.0, 0.85, 0.6), 0.0, 0.4, Color(1.0, 0.8, 0.5), 3.5)
	var iron := Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.5)
	var d: float = b["d0"]
	var k := 0
	while d < b["d1"]:
		var f := frame_at(curve, d + 1.5)
		var bf := Basis.looking_at(f["fwd"], Vector3.UP)
		var c: Vector3 = f["pos"]
		var wdt: float = (hw(track, d) + WALK + 0.5) * 2.0
		var in_water := _river_clearance(track, c) < -4.0
		_part(groups, stone, Builder.box(Vector3(wdt, 1.4, 3.05)), Transform3D(bf, c + Vector3(0, -0.75, 0)))
		for s in [-1.0, 1.0]:
			var side: Vector3 = c + f["right"] * s * (wdt / 2.0 - 0.3)
			_part(groups, stone, Builder.box(Vector3(0.6, 1.1, 3.05)), Transform3D(bf, side + Vector3(0, CURB_H + 0.55, 0)))
			if in_water:
				_part(groups, dark, Builder.box(Vector3(0.1, 2.0, 3.05)), Transform3D(bf, c + f["right"] * s * (wdt / 2.0 + 0.02) + Vector3(0, -1.6, 0)))
			if k % 6 == 3:
				_part(groups, iron, Builder.box(Vector3(0.18, 3.6, 0.18)), Transform3D(bf, side + Vector3(0, CURB_H + 1.8, 0)))
				_part(groups, lamp, Builder.box(Vector3(0.45, 0.6, 0.45)), Transform3D(bf, side + Vector3(0, CURB_H + 3.8, 0)))
		if in_water and k % 8 == 0:
			_part(groups, stone, Builder.box(Vector3(wdt + 1.0, 4.0, 4.0)), Transform3D(bf, c + Vector3(0, RIVER_Y - 0.3, 0)))
		d += 3.0
		k += 1
	_bake(root, groups)
	var mid := frame_at(curve, b["d"])
	for s in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.position = mid["pos"] + mid["right"] * s * (hw(track, b["d"]) + WALK) + Vector3(0, 4.5, 0)
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 2.0
		l.omni_range = 26.0
		root.add_child(l)


static func _plan_hills(track: Dictionary) -> void:
	for h in track["city"]["hills"]:
		track["hills"].append({"c": Vector2(h["x"], h["z"]), "r": h["r"], "h": h["h"], "kind": h["kind"]})


## Höhe der Hügel an pos: oben ein flaches Plateau, zur Straße und zum Fluss hin läuft der Hang aus
static func hill_h(track: Dictionary, pos: Vector3) -> float:
	var y := 0.0
	for h in track["hills"]:
		var k: float = Vector2(pos.x, pos.z).distance_to(h["c"]) / h["r"]
		if k < 1.0:
			var kk := clampf((k - 0.22) / 0.78, 0.0, 1.0)
			y = maxf(y, h["h"] * (0.5 + 0.5 * cos(PI * kk)))
	if y <= 0.0:
		return 0.0
	y *= smoothstep(6.0, 80.0, _main_clearance(track, pos) - WALK)
	if not track["rivers"].is_empty():
		y *= smoothstep(3.0, 45.0, _river_clearance(track, pos))
	return y


## Hügel als Höhengitter: Weinberg (Rebzeilen), Wald (Bäume), Park
static func _build_hills(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var trees := []
	var lights := []
	for h in track["hills"]:
		var c: Vector2 = h["c"]
		var r: float = h["r"]
		var cells := clampi(int(r * 2.0 / 10.0), 24, 70)
		var cs := r * 2.0 / cells
		var o := c - Vector2(r, r)
		var hgt := []
		for j in cells + 1:
			var row := PackedFloat32Array()
			for i in cells + 1:
				row.append(hill_h(track, Vector3(o.x + i * cs, 0, o.y + j * cs)))
			hgt.append(row)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in cells:
			for i in cells:
				var y00: float = hgt[j][i]
				var y10: float = hgt[j][i + 1]
				var y01: float = hgt[j + 1][i]
				var y11: float = hgt[j + 1][i + 1]
				if maxf(maxf(y00, y10), maxf(y01, y11)) < 0.05:
					continue
				var p00 := Vector3(o.x + i * cs, y00 - 0.06, o.y + j * cs)
				var p10 := Vector3(o.x + (i + 1) * cs, y10 - 0.06, o.y + j * cs)
				var p01 := Vector3(o.x + i * cs, y01 - 0.06, o.y + (j + 1) * cs)
				var p11 := Vector3(o.x + (i + 1) * cs, y11 - 0.06, o.y + (j + 1) * cs)
				for v in [p00, p10, p11, p00, p11, p01]:
					st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var hm := ShaderMaterial.new()
		hm.shader = HILL_SHADER
		hm.set_shader_parameter("kind", ["vineyard", "forest", "park"].find(h["kind"]))
		mi.material_override = hm
		root.add_child(mi)
		for t in int(r * r / (900.0 if h["kind"] != "vineyard" else 9000.0)):
			var p := c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
			var y := hill_h(track, Vector3(p.x, 0, p.y))
			if y < 2.0:
				continue
			var s := rng.randf_range(0.8, 1.4)
			trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(p.x, y, p.y)))
		for t in int(r / 14.0):
			var p := c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
			var y := hill_h(track, Vector3(p.x, 0, p.y))
			if y > 4.0:
				lights.append(Transform3D(Basis.IDENTITY, Vector3(p.x, y + 1.5, p.y)))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.6
	cone.height = 8.0
	cone.radial_segments = 6
	cone.rings = 1
	var tm := ArrayMesh.new()
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	cst.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, 5.5, 0)))
	tm = cst.commit()
	_multi(root, tm, Builder.mat(Color(0.02, 0.07, 0.035), 0.0, 0.95), trees)
	var bulb := SphereMesh.new()
	bulb.radius = 0.35
	bulb.height = 0.7
	bulb.radial_segments = 6
	bulb.rings = 3
	_multi(root, bulb, Builder.mat(Color(1.0, 0.8, 0.5), 0.0, 0.4, Color(1.0, 0.75, 0.4), 4.0), lights)


## Wahrzeichen an ihren echten Positionen. Liegt eins unter der (breiten) Spielstraße, rückt es zur Seite.
## Lange Bauten liegen parallel zur Straße, die Schauseite zeigt zur Straße.
static func _build_city_landmarks(root: Node3D, track: Dictionary) -> Array:
	var curve: Curve3D = track["curve"]
	var occupied := []
	for lm in track["city"]["landmarks"]:
		var kind: String = lm["kind"]
		var info: Dictionary = City.INFO.get(kind, {"hd": 10.0, "hl": 10.0})
		var hd: float = info["hd"]
		var hl: float = info["hl"]
		var pos := Vector3(lm["x"], 0, lm["z"])
		var extra := {}
		var basis := Basis.IDENTITY
		if kind == "oberbaumbruecke":
			# steht auf der Fahrbahn über der Spree: Mitte der Brücke, die der echten Lage am nächsten ist
			var bd := curve.get_closest_offset(pos)
			for br in track["bridges"]:
				if absf(br["d"] - bd) < 400.0:
					bd = br["d"]
			var fb := frame_at(curve, bd)
			pos = Vector3(fb["pos"].x, 0, fb["pos"].z)
			basis = Basis.looking_at(fb["fwd"], Vector3.UP)
			extra["hw"] = hw(track, bd) + WALK
			var nb := Node3D.new()
			nb.name = kind
			nb.transform = Transform3D(basis, pos)
			root.add_child(nb)
			City.new(nb).make(kind, extra)
			continue
		if kind == "fernsehturm":
			# echt 1,7 km entfernt, weiter als die Kamera sieht: in derselben Richtung näher und kleiner, damit er gleich groß wirkt
			var qf := curve.get_closest_point(pos)
			var df := Vector3(pos.x - qf.x, 0, pos.z - qf.z)
			var k := 1.0
			if df.length() > 560.0:
				k = 560.0 / df.length()
				pos = Vector3(qf.x, 0, qf.z) + df * k
			var nf := Node3D.new()
			nf.name = kind
			nf.position = pos
			nf.scale = Vector3.ONE * clampf(k * 2.2, 0.6, 1.0)
			root.add_child(nf)
			City.new(nf).make(kind, extra)
			continue
		if kind == "mainbruecke":
			# quer über den Fluss an der echten Stelle, Ufer bis Ufer
			var best := {}
			var bd := 1e9
			for rv in track["rivers"]:
				var pts: PackedVector2Array = rv["pts"]
				for i in pts.size() - 1:
					var dd := pts[i].distance_to(Vector2(pos.x, pos.z))
					if dd < bd:
						bd = dd
						best = {"p": pts[i], "dir": (pts[i + 1] - pts[i]).normalized(), "hw": rv["hw"][i]}
			if best.is_empty() or bd > 120.0:
				continue
			var bp: Vector2 = best["p"]
			pos = Vector3(bp.x, 0, bp.y)
			extra["len"] = best["hw"] * 2.0 + 3.0
			basis = Basis.looking_at(Vector3(best["dir"].x, 0, best["dir"].y), Vector3.UP)
			hl = extra["len"] / 2.0
		else:
			for it in 80:
				var q := curve.get_closest_point(pos)
				var away := Vector2(pos.x - q.x, pos.z - q.z)
				if away.length() < 0.5:
					var fr := frame_at(curve, curve.get_closest_offset(pos))
					away = Vector2(fr["right"].x, fr["right"].z)
				away = away.normalized()
				basis = Basis.looking_at(Vector3(-away.x, 0, -away.y), Vector3.UP)
				var ok := _main_clearance(track, pos) - WALK > hd + 3.0 and _branch_clearance(track, pos) > hd + 2.0
				for s in [-1.0, 1.0]:
					var e: Vector3 = pos + basis.x * s * hl * 0.9 - basis.z * 0.0
					ok = ok and _main_clearance(track, e) - WALK > hd * 0.4 + 2.0
				if kind != "alter_kranen":
					ok = ok and not _in_river(track, pos, hd * 0.7)
				if ok:
					break
				pos += Vector3(away.x, 0, away.y) * 3.0
				if _in_river(track, pos, hd * 0.7) and kind != "alter_kranen":
					pos -= Vector3(away.x, 0, away.y) * 1.5
		var y := hill_h(track, pos) if info.get("hill", false) else 0.0
		var n := Node3D.new()
		n.name = kind
		n.transform = Transform3D(basis, Vector3(pos.x, y, pos.z))
		root.add_child(n)
		City.new(n).make(kind, extra)
		if kind == "saaleck":
			n.scale = Vector3.ONE * 1.4
		if not info.get("hill", false):
			# Platz bzw. Sichtschneise zwischen Straße und Wahrzeichen: dort keine Häuser
			var q := curve.get_closest_point(pos)
			var to := Vector3(pos.x - q.x, 0, pos.z - q.z)
			var dist_road := to.length()
			to = to.normalized()
			var near := dist_road < 160.0
			var half_w := minf(hl, 45.0) if near else 14.0
			var reach := dist_road - hd if near else HALF_W + WALK + 45.0
			var sd := HALF_W + WALK + 4.0
			while sd < reach:
				var x := -half_w
				while x <= half_w:
					var c := q + to * sd + basis.x * x
					occupied.append({"pos": Vector3(c.x, 0, c.z), "r": 8.0})
					x += 12.0
				sd += 10.0
		var steps := maxi(int(ceil(hl / maxf(hd, 6.0))), 1)
		for i in range(-steps, steps + 1):
			var cp: Vector3 = pos + basis.x * (hl * float(i) / steps)
			occupied.append({"pos": Vector3(cp.x, 0, cp.z), "r": hd + 6.0})
	return occupied


## Echte Gebäude (Grundrisse aus OpenStreetMap, als Quader) hinter der Straßenfront, mit Satteldach im Stil des Viertels
static func _build_osm_buildings(root: Node3D, track: Dictionary, rng: RandomNumberGenerator, blockers: Array) -> Array:
	var curve: Curve3D = track["curve"]
	var data: Array = track["city"].get("buildings", [])
	var mobile := OS.has_feature("web_android") or OS.has_feature("web_ios")
	var placed := []
	var grid := {}
	for o in blockers:
		_grid_add(grid, o)
	for i in range(0, data.size(), 6):
		var pos := Vector3(data[i], 0, data[i + 1])
		var L: float = data[i + 2]
		var W: float = data[i + 3]
		var ang: float = data[i + 4]
		var h: float = data[i + 5]
		var r := Vector2(L, W).length() * 0.5
		var mc := _main_clearance(track, pos)
		if mc < WALK + 4.0 + W * 0.5:
			continue
		if mobile and mc > 110.0:
			continue  # Handy: nur die Häuser nahe der Strecke
		if not track["hills"].is_empty() and hill_h(track, pos) > 0.5:
			continue
		var along := Vector3(cos(ang), 0, sin(ang))
		var basis := Basis(Vector3.UP.cross(along), Vector3.UP, along)
		var foot := _foot(pos, basis, W, L)
		# echte Grundrisse als umschließende Rechtecke überlappen sich (Winkelbauten): bis 2,5 m ist das ein Häuserblock,
		# mehr hieße, ein Haus steckt im anderen; an der Straßenfront und am Wasser zählt jeder Meter
		if not _lot_free(track, foot, grid, WALK + 4.0, 0.3, 2.5):
			continue
		var dist := _district_at(track, curve.get_closest_offset(pos))
		_box_id += 1
		var styles: Array = dist["styles"]
		var tints: Array = dist["tints"]
		var style: float = styles[rng.randi() % styles.size()]
		var tint: Color = tints[rng.randi() % tints.size()]
		var v := rng.randf_range(0.75, 1.15)
		var tv := Vector3(tint.r * v, tint.g * v, tint.b * v)
		var seed := rng.randf() * 100.0
		var lit: float = dist["lit"] * rng.randf_range(0.6, 1.2)
		_bb_box(Transform3D(basis * Basis.from_scale(Vector3(W, h, L)), pos + Vector3(0, h / 2.0, 0)), tv, lit, seed, style,
			1.0 if rng.randf() < dist["shop"] * 0.4 else 0.0)
		if dist.has("roof") and L * W < 2500.0 and h < 30.0 and rng.randf() < dist["roof"]:
			var rt: Array = dist["roof_tints"]
			var rc: Color = rt[rng.randi() % rt.size()]
			var rk := rng.randf_range(0.8, 1.15)
			_bb_roof(pos, basis, L, W, h, false, Vector3(rc.r * rk, rc.g * rk, rc.b * rk), tv, style, seed, lit)
		var bl := {"pos": pos, "r": r * 0.8, "foot": foot, "soft": true}
		placed.append(bl)
		_grid_add(grid, bl)
	return placed


## Kreuzberg: die U1 fährt als Hochbahn über der Skalitzer Straße, mit Halt am Kottbusser Tor
static func _plan_kreuzberg_el(track: Dictionary) -> void:
	# Der Start liegt mitten auf der Skalitzer, darum zwei Abschnitte: vor dem Ziel (Kotti) und nach dem Start (Schlesisches Tor)
	var stations := ["KOTTBUSSER TOR", "SCHLESISCHES TOR"]
	for stt in track["city"]["streets"]:
		if stt[2] == "Skalitzer Straße" and stt[1] - stt[0] > 300.0 and not stations.is_empty():
			var d0: float = maxf(stt[0] + 40.0, track["start"] + 130.0)
			var d1: float = minf(minf(stt[1] - 40.0, d0 + 1300.0), track["length"] - 90.0)
			if d1 - d0 > 250.0 and _range_free(track, d0 - 25.0, d1 + 25.0):
				track["el"].append({"from": d0, "to": d1, "side": -1.0, "station": stations.pop_front()})


## East Side Gallery: bemalte Mauerreste an der Mühlenstraße, auf der Spreeseite der Straße
static func _east_side_gallery(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	for stt in track["city"]["streets"]:
		if stt[2] != "Mühlenstraße":
			continue
		var d0: float = stt[0] + 20.0
		var d1: float = stt[1] - 20.0
		# Seite zur Spree: dort ist der Fluss näher
		var fm := frame_at(curve, (d0 + d1) / 2.0)
		var side := 1.0
		if _river_clearance(track, fm["pos"] - fm["right"] * 60.0) < _river_clearance(track, fm["pos"] + fm["right"] * 60.0):
			side = -1.0
		var groups := {}
		var concrete := Builder.mat(Color(0.55, 0.55, 0.52), 0.0, 0.9)
		var cols := [Color(0.9, 0.15, 0.3), Color(0.1, 0.6, 0.95), Color(0.98, 0.8, 0.1), Color(0.2, 0.85, 0.4), Color(0.95, 0.45, 0.1),
			Color(0.7, 0.2, 0.9), Color(0.95, 0.95, 0.95), Color(0.1, 0.1, 0.12)]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1989
		var d := d0
		while d < d1:
			var f := frame_at(curve, d + 0.6)
			var bf := Basis.looking_at(f["fwd"], Vector3.UP)
			var base: Vector3 = f["pos"] + f["right"] * side * (hw(track, d) + WALK + 2.0)
			# Mauersegment (1,2 m breit, 3,6 m hoch) mit rundem Kopf, Wandbild aus Farbfeldern
			_part(groups, concrete, Builder.box(Vector3(0.25, 3.6, 1.18)), Transform3D(bf, base + Vector3(0, 1.8, 0)))
			_part(groups, concrete, Builder.box(Vector3(0.4, 0.3, 1.18)), Transform3D(bf, base + Vector3(0, 3.65, 0)))
			var face: Vector3 = -f["right"] * side * 0.14
			var c1: Color = cols[rng.randi() % cols.size()]
			var c2: Color = cols[rng.randi() % cols.size()]
			var m1 := Builder.mat(c1, 0.0, 0.7, c1, 0.25)
			var m2 := Builder.mat(c2, 0.0, 0.7, c2, 0.25)
			_part(groups, m1, Builder.box(Vector3(0.02, rng.randf_range(1.2, 3.2), 1.16)), Transform3D(bf, base + face + Vector3(0, 1.0, 0)))
			_part(groups, m2, Builder.box(Vector3(0.03, rng.randf_range(0.4, 1.4), rng.randf_range(0.3, 1.0))),
				Transform3D(bf, base + face * 1.3 + Vector3(0, rng.randf_range(1.2, 2.8), 0)))
			d += 1.2
		_bake(root, groups)


## Gelbes Ortsschild hinter dem Start, Straßenschilder an jedem Straßenwechsel
static func _build_city_signs(root: Node3D, track: Dictionary, race: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var city: Dictionary = track["city"]
	var groups := {}
	var post := Builder.mat(Color(0.5, 0.52, 0.55), 0.6, 0.4)
	var yellow := Builder.mat(Color(1.0, 0.8, 0.05), 0.0, 0.5, Color(1.0, 0.8, 0.05), 0.25)
	var black := Builder.mat(Color(0.02, 0.02, 0.02), 0.0, 0.6)
	var white := Builder.mat(Color(0.92, 0.92, 0.9), 0.0, 0.5, Color(0.92, 0.92, 0.9), 0.2)
	var town: String = race.get("town", city.get("label", ""))
	var region: String = race.get("region", city.get("region", ""))
	var d0: float = track["start"] + 55.0
	var f := frame_at(curve, d0)
	var bf := Basis.looking_at(f["fwd"], Vector3.UP)
	var base: Vector3 = f["pos"] + f["right"] * (hw(track, d0) + WALK - 1.2)
	var pw := maxf(2.2, town.length() * 0.24 + 0.6)
	for s in [-1.0, 1.0]:
		_part(groups, post, Builder.box(Vector3(0.08, 2.9, 0.08)), Transform3D(bf, base + bf.x * s * (pw * 0.35) + Vector3(0, CURB_H + 1.45, 0)))
	_part(groups, black, Builder.box(Vector3(pw + 0.12, 1.32, 0.05)), Transform3D(bf, base + Vector3(0, CURB_H + 2.35, 0.04)))
	_part(groups, yellow, Builder.box(Vector3(pw, 1.2, 0.06)), Transform3D(bf, base + Vector3(0, CURB_H + 2.35, 0)))
	for txt in [[town, 0.2, 96], [region, -0.32, 34]]:
		if txt[0] == "":
			continue
		var l := Label3D.new()
		l.text = txt[0]
		l.font_size = txt[2]
		l.pixel_size = 0.0042
		l.modulate = Color(0.02, 0.02, 0.02)
		l.outline_size = 0
		l.shaded = true
		l.double_sided = false
		l.transform = Transform3D(bf, base + Vector3(0, CURB_H + 2.35 + txt[1], 0) + bf.z * 0.04)
		root.add_child(l)
	var sl := OmniLight3D.new()
	sl.position = base + Vector3(0, 4.5, 0) - f["fwd"] * 3.0
	sl.light_color = Color(1.0, 0.85, 0.6)
	sl.light_energy = 1.5
	sl.omni_range = 9.0
	root.add_child(sl)
	# Straßennamensschilder (weiß, schwarze Schrift) am rechten Gehweg, kurz nach jeder Einmündung
	var last := -1e9
	for stt in city.get("streets", []):
		var d: float = stt[0] + 12.0
		if d < 40.0 or d > track["length"] - 20.0 or d - last < 60.0 or not bridge_at(track, d).is_empty():
			continue
		var sf := frame_at(curve, d)
		var sp: Vector3 = sf["pos"] + sf["right"] * (hw(track, d) + WALK - 0.6)
		if _branch_clearance(track, sp) < 2.0:
			continue
		last = d
		var name: String = stt[2]
		var sb := Basis.looking_at(sf["fwd"], Vector3.UP)
		var w := name.length() * 0.16 + 0.4
		_part(groups, post, Builder.box(Vector3(0.07, 3.0, 0.07)), Transform3D(sb, sp + Vector3(0, CURB_H + 1.5, 0)))
		_part(groups, black, Builder.box(Vector3(w + 0.06, 0.5, 0.04)), Transform3D(sb, sp + Vector3(0, CURB_H + 2.75, 0) - sb.x * w * 0.45))
		_part(groups, white, Builder.box(Vector3(w, 0.44, 0.06)), Transform3D(sb, sp + Vector3(0, CURB_H + 2.75, 0) - sb.x * w * 0.45))
		for side in [1.0, -1.0]:
			var l := Label3D.new()
			l.text = name
			l.font_size = 64
			l.pixel_size = 0.0045
			l.modulate = Color(0.02, 0.02, 0.02)
			l.outline_size = 0
			l.shaded = true
			l.double_sided = false
			var lb := sb if side > 0.0 else sb.rotated(Vector3.UP, PI)
			l.transform = Transform3D(lb, sp + Vector3(0, CURB_H + 2.75, 0) - sb.x * w * 0.45 + sb.z * side * 0.04)
			root.add_child(l)
	_bake(root, groups)


## Bahnübergang nur dort, wo die echten Gleise die Strecke kreuzen (und die Straße dort gerade genug ist)
static func _plan_city_crossing(track: Dictionary, race: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	for d in track["city"].get("rail", []):
		if d < 0.12 * L or d > 0.88 * L or _in_zone(track, d, 120.0):
			continue
		var f0 := frame_at(curve, d - 45.0)
		var f1 := frame_at(curve, d + 80.0)
		if (f0["fwd"] as Vector3).angle_to(f1["fwd"]) > 0.2:
			continue
		_set_crossing(track, d)
		return


# --- Bebauung --------------------------------------------------------------

static func _district_at(track: Dictionary, d: float) -> Dictionary:
	var arr: Array = track["districts"]
	var i := clampi(int(d / DISTRICT_LEN), 0, arr.size() - 1)
	return DISTRICTS[arr[i]]


static func _build_city(root: Node3D, track: Dictionary, rng: RandomNumberGenerator, occupied: Array) -> Array:
	var placed := []  # [{pos, r, foot}]
	var grid := {}  # Rasterzelle -> Grundrisse und belegte Kreise (schnelle Nachbarsuche)
	for o in occupied:
		_grid_add(grid, o)
	for b in track.get("el_blocks", []):
		_grid_add(grid, {"pos": Vector3(b[0].x, 0, b[0].y), "r": 0.0, "foot": b})
	# Häuserzeilen: an der Hauptstraße beidseitig, an den Abkürzungen ebenfalls
	var frontages := []
	for side in [-1.0, 1.0]:
		frontages.append({"path": track["paths"][0], "side": side, "edge": HALF_W + WALK})
	for p in track["paths"]:
		if p["kind"] == "alley" or p["kind"] == "lake" or p["kind"] == "fork":
			for side in [-1.0, 1.0]:
				frontages.append({"path": p, "side": side, "edge": p["half_w"] + (3.5 if p["kind"] == "fork" else 0.8)})
	for fr in frontages:
		var p: Dictionary = fr["path"]
		var c: Curve3D = p["curve"]
		var len: float = p["length"]
		var side: float = fr["side"]
		var d := rng.randf_range(0.0, 8.0)
		while d < len:
			var dist: Dictionary = _district_at(track, d if p["id"] == 0 else p["from"])
			var edge: float = (hw(track, d) + WALK + dist.get("setback", 0.0)) if p["id"] == 0 else fr["edge"]
			var tall: bool = rng.randf() < dist["tall_p"]
			var shop: bool = not tall and rng.randf() < dist["shop"]
			var w := rng.randf_range(8.0, 15.0) if not tall else rng.randf_range(14.0, 26.0)
			var depth := rng.randf_range(10.0, 16.0) if not tall else rng.randf_range(14.0, 24.0)
			var hr: Array = dist["tall"] if tall else dist["low"]
			var h := rng.randf_range(hr[0], hr[1])
			if shop and rng.randf() < 0.25:
				h = rng.randf_range(5.0, 8.0)  # flacher Laden (Imbiss, Markt); sonst Wohn- und Geschäftshaus mit Läden unten
			var f := frame_at(c, d)
			var gap := rng.randf_range(0.4, 2.0)
			var basis := Basis.looking_at(f["fwd"], Vector3.UP)
			# passt das Haus nicht (Kurveninnenseite, Einmündung, Ufer), erst ein schmaleres und flacheres versuchen
			var center := Vector3.ZERO
			var ok := false
			for attempt in 3:
				if attempt > 0:
					w *= 0.7
					depth = maxf(depth * 0.8, 8.0)
					if w < 6.0:
						break
				center = f["pos"] + f["right"] * side * (edge + gap + depth / 2)
				# am Fuß eines Hügels (Festung, Weinberg) keine Häuser: der Hang soll von der Straße aus zu sehen sein
				ok = (track["hills"].is_empty() or hill_h(track, center + f["right"] * side * 50.0) < 6.0) \
					and _lot_free(track, _foot(center, basis, depth, w), grid, WALK + 0.2, 0.25)
				if ok:
					break
			if not ok:
				d += 4.0
				continue
			var radius := Vector2(w, depth).length() / 2
			if dist.has("cranes") and p["id"] == 0 and rng.randf() < dist["cranes"] \
					and _main_clearance(track, center + f["right"] * side * 10.0) > 20.0:
				_crane(root, center + f["right"] * side * 10.0, -f["right"] * side, rng)
				var cr := {"pos": center + f["right"] * side * 10.0, "r": 13.0}
				placed.append(cr)
				_grid_add(grid, cr)
				d += 14.0
			elif dist.has("containers") and f["y"] < 0.3 and rng.randf() < 0.3:
				_containers(root, center, basis, rng)
				var ct := {"pos": center, "r": radius * 0.8, "foot": _foot(center, basis, depth, w)}
				placed.append(ct)
				_grid_add(grid, ct)
			else:
				var face_dir: Vector3 = -f["right"] * side  # zeigt zur Straße
				var lift: float = f["y"] + CURB_H if f["y"] > 0.3 else 0.0
				# am Hang: Haus steht auf Straßenhöhe, darunter reicht es mit dunklen Geschossen bis zum Boden
				_building(root, center + Vector3(0, lift, 0), basis, w, depth, h, tall, shop, dist, face_dir, f["right"] * side, rng)
				if lift > 0.0:
					_bb_box(Transform3D(basis * Basis.from_scale(Vector3(depth, lift + 0.1, w)), center + Vector3(0, lift / 2.0, 0)),
						Vector3(0.1, 0.1, 0.11), 0.15, rng.randf() * 100.0, 4.0, 0.0, -lift, FACE_WALL)
				var bl := {"pos": center, "r": radius * 0.8, "foot": _foot(center, basis, depth, w)}
				placed.append(bl)
				_grid_add(grid, bl)
			d += w + rng.randf_range(0.5, 3.5)
	# Orts-Strecken: dahinter stehen die echten Häuser (OpenStreetMap). Sonst zwei Reihen dahinter, damit man wie in
	# einer Häuserschlucht fährt und zwischen den Häusern Stadt sieht statt leerer Fläche
	if track["city"].is_empty():
		for side in [-1.0, 1.0]:
			for row in [1, 2]:
				_back_row(root, track, rng, grid, placed, side, row)
	return placed


## Hintere Häuserreihe (row 1: direkt hinter der Straßenfront, row 2: noch eine dahinter): ohne Läden und Schilder,
## Türme im Bankenviertel überragen die Front wie eine Skyline
static func _back_row(root: Node3D, track: Dictionary, rng: RandomNumberGenerator, grid: Dictionary, placed: Array,
		side: float, row: int) -> void:
	var c: Curve3D = track["curve"]
	var len: float = track["length"]
	var d := rng.randf_range(0.0, 12.0)
	while d < len:
		var dist := _district_at(track, d)
		var f := frame_at(c, d)
		var tall: bool = rng.randf() < dist["tall_p"] * (1.0 + 0.3 * row)
		var w := rng.randf_range(10.0, 18.0) if not tall else rng.randf_range(14.0, 24.0)
		var depth := rng.randf_range(10.0, 16.0) if not tall else rng.randf_range(14.0, 22.0)
		var hr: Array = dist["tall"] if tall else dist["low"]
		var h := rng.randf_range(hr[0], hr[1])
		var basis := Basis.looking_at(f["fwd"], Vector3.UP)
		var lat: float = hw(track, d) + WALK + dist.get("setback", 0.0) + [0.0, 18.0, 38.0][row] + rng.randf_range(0.0, 3.0)
		var center := Vector3.ZERO
		var ok := false
		for attempt in 4:
			center = f["pos"] + f["right"] * side * (lat + attempt * 4.0 + depth / 2.0)
			ok = _lot_free(track, _foot(center, basis, depth, w), grid, WALK + 6.0, 0.25)
			if ok:
				break
		if not ok:
			d += 5.0
			continue
		var lift: float = f["y"] + CURB_H if f["y"] > 0.3 else 0.0
		_building(root, center + Vector3(0, lift, 0), basis, w, depth, h, tall, false, dist, -f["right"] * side, f["right"] * side, rng, true)
		if lift > 0.0:
			_bb_box(Transform3D(basis * Basis.from_scale(Vector3(depth, lift + 0.1, w)), center + Vector3(0, lift / 2.0, 0)),
				Vector3(0.1, 0.1, 0.11), 0.15, rng.randf() * 100.0, 4.0, 0.0, -lift, FACE_WALL)
		var bl := {"pos": center, "r": Vector2(w, depth).length() * 0.4, "foot": _foot(center, basis, depth, w)}
		placed.append(bl)
		_grid_add(grid, bl)
		d += w + rng.randf_range(1.0, 4.0)


## Grundriss eines Hauses: [Mitte 2D, Achse quer (x), Achse entlang (z), halbe Tiefe, halbe Breite]
static func _foot(center: Vector3, basis: Basis, depth: float, w: float) -> Array:
	return [Vector2(center.x, center.z), Vector2(basis.x.x, basis.x.z).normalized(), Vector2(basis.z.x, basis.z.z).normalized(),
		depth / 2.0, w / 2.0]


const LOT_CELL := 40.0


## Raster für die Platzsuche: Grundrisse ("feet", mit Umkreis fr) und belegte Kreise ("circ") getrennt, damit die
## Suche nur so weit reicht wie der größte Eintrag seiner Art
static func _grid_add(grid: Dictionary, o: Dictionary) -> void:
	if grid.is_empty():
		grid.merge({"feet": {}, "circ": {}, "fmax": 0.0, "cmax": 0.0})
	var key := Vector2i(floori(o["pos"].x / LOT_CELL), floori(o["pos"].z / LOT_CELL))
	var kind := "feet" if o.has("foot") else "circ"
	if kind == "feet":
		o["fr"] = Vector2(o["foot"][3], o["foot"][4]).length()
		grid["fmax"] = maxf(grid["fmax"], o["fr"])
	else:
		grid["cmax"] = maxf(grid["cmax"], o["r"])
	var cells: Dictionary = grid[kind]
	if not cells.has(key):
		cells[key] = []
	cells[key].append(o)


## Abstand zur Fahrbahnkante der Hauptstraße (wie _main_clearance, eine Suche statt zwei)
static func _main_clear_fast(track: Dictionary, pos: Vector3) -> float:
	var c: Curve3D = track["curve"]
	var off := c.get_closest_offset(pos)
	return _flat(pos - c.sample_baked(off)).length() - hw(track, off)


## Eindringtiefe zweier gedrehter Rechtecke (Trennachsen-Test), 0 wenn getrennt
static func _foot_pen(a: Array, b: Array) -> float:
	var best := 1e9
	for ax in [a[1], a[2], b[1], b[2]]:
		var ra: float = a[3] * absf(ax.dot(a[1])) + a[4] * absf(ax.dot(a[2]))
		var rb: float = b[3] * absf(ax.dot(b[1])) + b[4] * absf(ax.dot(b[2]))
		var pen: float = ra + rb - absf((b[0] - a[0]).dot(ax))
		if pen <= 0.0:
			return 0.0
		best = minf(best, pen)
	return best


## Darf hier ein Haus stehen? Der ganze Rand des Grundrisses (Ecken, Kantenpunkte) muss hinter dem Gehweg der
## Hauptstraße (walk = Mindestabstand zur Fahrbahnkante) liegen, neben Nebenstraßen, außerhalb von Flüssen, Seen,
## Parks und Bahngelände; Wahrzeichen (Kreise) und andere Häuser (mehr als overlap Meter Überschneidung) sind tabu.
static func _lot_free(track: Dictionary, foot: Array, grid: Dictionary, walk: float, overlap: float, soft := -1.0) -> bool:
	var c2: Vector2 = foot[0]
	var c := Vector3(c2.x, 0, c2.y)
	var r := Vector2(foot[3], foot[4]).length()
	var key := Vector2i(floori(c.x / LOT_CELL), floori(c.z / LOT_CELL))
	if not grid.is_empty():
		var reach := int(ceil((r + grid["fmax"]) / LOT_CELL))
		var cells: Dictionary = grid["feet"]
		for gx in range(key.x - reach, key.x + reach + 1):
			for gz in range(key.y - reach, key.y + reach + 1):
				for o in cells.get(Vector2i(gx, gz), []):
					if c2.distance_to(o["foot"][0]) < r + o["fr"] \
							and _foot_pen(foot, o["foot"]) > (soft if soft >= 0.0 and o.has("soft") else overlap):
						return false
		reach = int(ceil((r + grid["cmax"]) / LOT_CELL))
		cells = grid["circ"]
		for gx in range(key.x - reach, key.x + reach + 1):
			for gz in range(key.y - reach, key.y + reach + 1):
				for o in cells.get(Vector2i(gx, gz), []):
					if _flat(c - o["pos"]).length() < o["r"] + r * 0.65:
						return false
	var pts := []
	for su in [-1.0, 0.0, 1.0]:
		for sv in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			if su != 0.0 or absf(sv) == 1.0:
				var q: Vector2 = c2 + foot[1] * foot[3] * su + foot[2] * foot[4] * sv
				pts.append(Vector3(q.x, 0, q.y))
	pts.append(c)
	var curve: Curve3D = track["curve"]
	var d0 := curve.get_closest_offset(c)
	if _flat(c - curve.sample_baked(d0)).length() - hw(track, d0) < r + walk + 1.0:
		var corner := [0, 4, 5, 9]  # Ecken: Suche über die ganze Strecke (falls ein anderer Teil der Straße nahe kommt)
		var L: float = curve.get_baked_length()
		for i in pts.size():
			var q: Vector3 = pts[i]
			var dq := d0
			if i in corner:
				dq = curve.get_closest_offset(q)
			else:
				# Kantenpunkte: zwei Newton-Schritte entlang der Straße vom Hausmittelpunkt aus
				for it in 2:
					var a := curve.sample_baked(maxf(dq - 1.0, 0.0))
					var b := curve.sample_baked(minf(dq + 1.0, L))
					var tg := _flat(b - a).normalized()
					dq = clampf(dq + _flat(q - curve.sample_baked(dq)).dot(tg), 0.0, L)
			if _flat(q - curve.sample_baked(dq)).length() - hw(track, dq) < walk:
				return false
	if _branch_clearance(track, c) < r + 4.0:
		for pth in track["paths"]:
			if pth["id"] == 0:
				continue
			var need: float = {"fork": 3.0, "spur": 1.0}.get(pth["kind"], 0.3)
			for q in pts:
				if _flat(q - (pth["curve"] as Curve3D).get_closest_point(q)).length() - pth["half_w"] < need:
					return false
	if not track["rivers"].is_empty() and _river_near(track, c, r + 1.0) < r + 1.0:
		for q in pts:
			if _river_near(track, q, 1.0) < 1.0:
				return false
	for lk in track["lakes"]:
		var au: Vector3 = lk["au"]
		var av: Vector3 = lk["av"]
		var lf := [Vector2(lk["center"].x, lk["center"].z), Vector2(au.x, au.z).normalized(), Vector2(av.x, av.z).normalized(),
			lk["hu"] + 0.5, lk["hv"] + 0.5]
		if _foot_pen(foot, lf) > 0.0:
			return false
	if _rail_clearance(track, c) < r + 2.5:
		for q in pts:
			if _rail_clearance(track, q) < 2.0:
				return false
	for tri in track["parks"]:
		for q in pts:
			if Geometry2D.point_is_inside_triangle(Vector2(q.x, q.z), Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z),
					Vector2(tri[2].x, tri[2].z)):
				return false
	return true


## Ein Gebäude mit Fassade, ggf. Sockel + Turm + Krone, Dachaufbauten, Werbung, Laden
static func _building(root: Node3D, center: Vector3, basis: Basis, w: float, depth: float, h: float,
		tall: bool, shop: bool, dist: Dictionary, face_dir: Vector3, away: Vector3, rng: RandomNumberGenerator, back := false) -> void:
	_box_id += 1
	var styles: Array = dist["styles"]
	var tints: Array = dist["tints"]
	var style: float = styles[rng.randi() % styles.size()]
	var tint: Color = tints[rng.randi() % tints.size()]
	var v := rng.randf_range(0.8, 1.2)
	var tv := Vector3(tint.r * v, tint.g * v, tint.b * v)
	var seed := rng.randf() * 100.0
	var lit: float = dist["lit"] * rng.randf_range(0.7, 1.3)
	var top_h := h
	var top_center := center
	var top_w := w
	var top_d := depth
	if tall and h > 26.0 and rng.randf() < 0.55:
		# Sockelbau + zurückgesetzter Turm
		var ph := rng.randf_range(6.0, 9.0)
		_box_building(root, center, basis, w, depth, ph, 0.0, tv * 0.9, seed + 1.0, 1.0, lit)
		top_w = w * 0.7
		top_d = depth * 0.7
		top_center = center + away * depth * 0.1
		_box_building(root, top_center, basis, top_w, top_d, h, style, tv, seed, 0.0, lit)
	else:
		# Schaufenster im Erdgeschoss: im Marktviertel fast überall, im Hafen selten (Speicher, Hallen)
		_box_building(root, center, basis, w, depth, h, style, tv, seed,
			1.0 if not back and (shop or rng.randf() < 0.2 + 0.6 * dist["shop"]) else 0.0, lit)
	if tall and h > 45.0 and rng.randf() < 0.45:
		# Krone
		var ch := rng.randf_range(5.0, 12.0)
		_box_building(root, top_center, basis, top_w * 0.55, top_d * 0.55, ch, style, tv * 1.1, seed + 2.0, 0.0, lit, top_h)
		top_h += ch
		top_w *= 0.55
		top_d *= 0.55
	var roof_y := top_h
	var pitched: bool = dist.has("roof") and top_center == center and h < 26.0 and rng.randf() < dist["roof"]
	if pitched:
		var rt: Array = dist["roof_tints"]
		var rc: Color = rt[rng.randi() % rt.size()]
		var rk := rng.randf_range(0.85, 1.15)
		_bb_roof(center, basis, w, depth, top_h, rng.randf() < dist.get("gable", 0.0), Vector3(rc.r * rk, rc.g * rk, rc.b * rk),
			tv, style, seed, lit)
	if back:
		return  # hintere Reihe: nur der Baukörper (im Häuser-Batch), keine Einzelteile
	var grey := Builder.mat(Color(0.25, 0.25, 0.27), 0.5, 0.5)
	var eaves: bool = not tall and h < 15.0 and rng.randf() < dist.get("eaves", 0.0)
	if eaves:
		# Geschwungenes Walmdach (Chinatown)
		var roof_cols := [Color(0.05, 0.24, 0.13), Color(0.35, 0.06, 0.04), Color(0.08, 0.08, 0.09)]
		var roof := MeshInstance3D.new()
		roof.mesh = Builder.tapered_box(Vector2(depth + 2.2, w + 2.2), Vector2(depth * 0.4, w * 0.75), 2.6, 0.0)
		roof.material_override = Builder.mat(roof_cols[rng.randi() % roof_cols.size()], 0.2, 0.5)
		roof.transform = Transform3D(basis, center + Vector3(0, h, 0))
		root.add_child(roof)
		Builder._add(root, Builder.box(Vector3(depth * 0.4 + 0.3, 0.25, w * 0.75 + 0.6)),
			Builder.mat(Color(0.9, 0.62, 0.18), 0.7, 0.3, Color(1.0, 0.55, 0.1), 0.6), center + Vector3(0, h + 2.7, 0)).basis = basis
	if tall and top_h == h and h > 30.0 and rng.randf() < dist.get("screens", 0.0):
		# LED-Videowand an der Turmfassade
		var sw := minf(top_w * 0.8, 14.0)
		var sh := sw * 0.5625
		var q := QuadMesh.new()
		q.size = Vector2(sw, sh)
		var sm := ShaderMaterial.new()
		sm.shader = SCREEN_SHADER
		var sy := rng.randf_range(14.0, top_h - sh - 4.0)
		var scr := Builder._add(root, q, sm, top_center + face_dir * (top_d * 0.5 + 0.12) + Vector3(0, sy, 0))
		scr.basis = Basis.looking_at(-face_dir, Vector3.UP)
	for i in (0 if eaves or pitched else rng.randi_range(0, 3)):
		var off := basis * Vector3(rng.randf_range(-top_d, top_d) * 0.3, 0, rng.randf_range(-top_w, top_w) * 0.3)
		Builder._add(root, Builder.box(Vector3(1.6, 1.0, 1.2)), grey, top_center + off + Vector3(0, roof_y + 0.5, 0)).basis = basis
	if not shop and rng.randf() < dist.get("stacks", 0.0):
		# Fabrikschornstein mit rot-weißem Kopf und Blinklicht
		var sh := rng.randf_range(16.0, 32.0)
		var sp := top_center + basis * Vector3(rng.randf_range(-0.25, 0.25) * top_d, 0, rng.randf_range(-0.3, 0.3) * top_w)
		var bands := [Builder.mat(Color(0.3, 0.16, 0.12), 0.0, 0.8), Builder.mat(Color(0.75, 0.08, 0.05), 0.2, 0.6), Builder.mat(Color(0.85, 0.85, 0.85), 0.2, 0.6)]
		var segs := [[sh - 3.0, 0], [1.5, 1], [1.5, 2]]
		var y0 := roof_y
		for sg in segs:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.1
			cyl.bottom_radius = 1.4 if sg[1] == 0 else 1.1
			cyl.height = sg[0]
			cyl.radial_segments = 10
			Builder._add(root, cyl, bands[sg[1]], sp + Vector3(0, y0 + sg[0] / 2.0, 0))
			y0 += sg[0]
		var sbm := ShaderMaterial.new()
		sbm.shader = BLINK_SHADER
		var sbl := SphereMesh.new()
		sbl.radius = 0.3
		sbl.height = 0.6
		Builder._add(root, sbl, sbm, sp + Vector3(0, y0 + 0.3, 0))
	if tall and rng.randf() < 0.6:
		# Antenne mit rotem Blinklicht
		var ah := rng.randf_range(5.0, 14.0)
		var ap := top_center + Vector3(0, roof_y + ah / 2.0, 0)
		Builder._add(root, Builder.box(Vector3(0.15, ah, 0.15)), grey, ap)
		var bm := ShaderMaterial.new()
		bm.shader = BLINK_SHADER
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		Builder._add(root, sm, bm, top_center + Vector3(0, roof_y + ah, 0))
	if rng.randf() < dist["billboard"] and h < 40.0 and top_center == center:
		_billboard(root, center + face_dir * (depth * 0.5 - 1.5), face_dir, roof_y, rng)
	if rng.randf() < dist["neon_edge"]:
		var nc: Color = NEON[rng.randi() % NEON.size()]
		var nm := Builder.mat(nc, 0.0, 0.4, nc, 2.5)
		var along := basis.z
		for s in [-1.0, 1.0]:
			var corner: Vector3 = top_center + face_dir * (top_d * 0.5 + 0.08) + along * s * (top_w * 0.5 + 0.08)
			Builder._add(root, Builder.box(Vector3(0.15, top_h - 6.0, 0.15)), nm, corner + Vector3(0, 4.0 + (top_h - 6.0) / 2.0, 0))
	var face_pos := center + face_dir * (depth / 2 + 0.15)
	var face_basis := Basis.looking_at(-face_dir, Vector3.UP)  # +Z zeigt zur Straße
	if shop:
		var awning_cols := [Color(0.6, 0.05, 0.05), Color(0.05, 0.35, 0.15), Color(0.1, 0.15, 0.5), Color(0.5, 0.3, 0.05), Color(0.35, 0.05, 0.4)]
		var aw := MeshInstance3D.new()
		aw.mesh = Builder.box(Vector3(w * 0.85, 0.15, 1.6))
		aw.material_override = Builder.mat(awning_cols[rng.randi() % awning_cols.size()], 0.1, 0.6)
		aw.transform = Transform3D(face_basis, face_pos + Vector3(0, 3.6, 0) + face_dir * 0.8)
		root.add_child(aw)
		if rng.randf() < 0.35:
			_sign_box(root, "GEÖFFNET", Color(1.0, 0.15, 0.55), 32, 0.012,
				Transform3D(face_basis, face_pos + Vector3(0, 2.4, 0) + basis.z * w * 0.25), w * 0.4)
	var names: Array = dist.get("names", SHOPS)
	if dist.has("de") and not _city_names.is_empty():
		names = _city_names + _city_names + names
	if shop and dist.has("lanterns"):
		# Zwei Lampions vor dem Laden
		var lm := Builder.mat(Color(0.9, 0.1, 0.05), 0.0, 0.5, Color(1.0, 0.15, 0.05), 1.8)
		var ls := SphereMesh.new()
		ls.radius = 0.32
		ls.height = 0.8
		ls.radial_segments = 8
		ls.rings = 5
		for s in [-1.0, 1.0]:
			Builder._add(root, ls, lm, face_pos + face_dir * 1.2 + basis.z * s * w * 0.3 + Vector3(0, 3.1, 0))
	if h > 8.0 and rng.randf() < dist.get("blade", 0.0):
		# Senkrechtes Leuchtschild, quer zur Fassade (von der Straße aus lesbar)
		var word: String = names[rng.randi() % names.size()].replace(" ", "")
		word = word.substr(0, 6)
		var hs := 0.74 * word.length() + 0.6
		if 4.6 + hs < h:
			var bc: Color = NEON[rng.randi() % NEON.size()]
			var bp := face_pos + face_dir * 0.8 + basis.z * rng.randf_range(-w * 0.35, w * 0.35) + Vector3(0, 4.6 + hs / 2.0, 0)
			Builder._add(root, Builder.box(Vector3(0.25, hs, 1.3)), Builder.mat(Color(0.04, 0.04, 0.05), 0.3, 0.5, bc, 0.3), bp).basis = Basis.looking_at(-face_dir, Vector3.UP)
			var vt := ""
			for ch in word:
				vt += ch + "\n"
			for s in [1.0, -1.0]:
				var bl := Label3D.new()
				bl.text = vt.strip_edges()
				bl.font_size = 40
				bl.pixel_size = 0.018
				bl.line_spacing = -6.0
				bl.modulate = Color(bc.r * 1.8, bc.g * 1.8, bc.b * 1.8)
				bl.shaded = false
				bl.double_sided = false
				bl.transform = Transform3D(basis if s > 0.0 else basis.rotated(Vector3.UP, PI), bp + basis.z * s * 0.14)
				root.add_child(bl)
	if shop:
		# Ladenschild über der Markise, im Stil der Ladenart (Apotheke, Friseur, Imbiss ...)
		_shop_sign(root, names[rng.randi() % names.size()], Transform3D(face_basis, face_pos + Vector3(0, 4.75, 0)), w * 0.8, rng)
	if style == 4.0 and h > 10.0 and rng.randf() < dist.get("fire_escape", 0.0):
		_fire_escape(root, face_pos + basis.z * rng.randf_range(-w * 0.25, w * 0.25), Basis.looking_at(-face_dir, Vector3.UP),
			mini(int((h - 4.2) / 3.2), 6))
	elif style == 4.0 and rng.randf() < 0.5:
		# Balkone übereinander
		var bc := Builder.mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
		var floors := int((h - 4.2) / 3.2)
		var off := basis.z * rng.randf_range(-w * 0.3, w * 0.3)
		for k in mini(floors, 6):
			Builder._add(root, Builder.box(Vector3(2.4, 0.12, 1.0)), bc, face_pos + off + face_dir * 0.5 + Vector3(0, 4.2 + k * 3.2, 0)).basis = face_basis
			Builder._add(root, Builder.box(Vector3(2.4, 0.9, 0.05)), bc, face_pos + off + face_dir * 1.0 + Vector3(0, 4.65 + k * 3.2, 0)).basis = face_basis


static func _box_building(root: Node3D, center: Vector3, basis: Basis, w: float, depth: float, h: float,
		style: float, tint: Vector3, seed: float, shop_glass: float, lit: float, base_y := 0.0) -> void:
	_bb_box(Transform3D(basis * Basis.from_scale(Vector3(depth, h, w)), center + Vector3(0, base_y + h / 2, 0)),
		tint, lit, seed, style, shop_glass, base_y)


## Fassadenkoordinaten für building.gdshader: UV = (Strecke ab der linken Kante der Fläche, Höhe über der Straße),
## CUSTOM0 = (Breite der Fläche, Oberkante über der Straße, Art). Art: 0 Dach/Boden, 1 Fassade mit Fenstern,
## 2 Wand ohne Fenster (Sockel am Hang, Mauern), 3 Giebel. So richten sich Fenster nach der Fassade (gleiche Ränder
## an beiden Ecken, ganze Geschosse unter der Dachkante), egal wie das Haus gedreht ist.
enum { FACE_TOP, FACE_WINDOWS, FACE_WALL, FACE_GABLE }


static func _bb_new() -> SurfaceTool:
	var nst := SurfaceTool.new()
	nst.begin(Mesh.PRIMITIVE_TRIANGLES)
	nst.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	return nst


## Quader mit Fassaden-Shader in den Häuser-Batch legen (xf skaliert einen Einheitswürfel). base_h: Höhe der
## Unterkante über der Straße (Turmkrone auf dem Turm; negativ, wenn das Haus am Hang tiefer hinunterreicht).
static func _bb_box(xf: Transform3D, tint := Vector3(0.08, 0.08, 0.1), lit := 0.4, seed := 0.0, style := 0.0, shop_glass := 1.0,
		base_h := 0.0, kind := FACE_WINDOWS) -> void:
	if _box_arrays.is_empty():
		_box_arrays = BoxMesh.new().get_mesh_arrays()
	if box_log != null and _box_tag != "":
		box_log.append([xf, _box_id, _box_tag])
	var verts: PackedVector3Array = _box_arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = _box_arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = _box_arrays[Mesh.ARRAY_INDEX]
	var key := Vector2i(floori(xf.origin.x / BATCH_CELL), floori(xf.origin.z / BATCH_CELL))
	if not _bb.has(key):
		_bb[key] = _bb_new()
	var st: SurfaceTool = _bb[key]
	var nb := xf.basis.inverse().transposed()
	var col := Color(tint.x, tint.y, tint.z, lit)
	var u2 := Vector2(seed, style + 10.0 * shop_glass)
	var sc := xf.basis.get_scale()
	var top := sc.y + base_h
	for i in idx:
		var v := verts[i]
		var n := norms[i]
		var uv := Vector2.ZERO
		var cu := Color(0.0, top, FACE_TOP)
		if absf(n.y) < 0.5:
			# Seitenfläche: "links" ist von außen gesehen links (Blick gegen die Normale)
			var along := (-v.z * n.x) * sc.z if absf(n.x) > 0.5 else (v.x * n.z) * sc.x
			var width := sc.z if absf(n.x) > 0.5 else sc.x
			uv = Vector2(along + width * 0.5, (v.y + 0.5) * sc.y + base_h)
			cu = Color(width, top, kind)
		else:
			uv = Vector2(v.x * sc.x, v.z * sc.z)
		st.set_normal((nb * n).normalized())
		st.set_color(col)
		st.set_uv(uv)
		st.set_uv2(u2)
		st.set_custom(0, cu)
		st.add_vertex(xf * v)


static func _bb_st(pos: Vector3) -> SurfaceTool:
	var key := Vector2i(floori(pos.x / BATCH_CELL), floori(pos.z / BATCH_CELL))
	if not _bb.has(key):
		_bb[key] = _bb_new()
	return _bb[key]


## Vieleck in den Häuser-Batch; origin/ax: Bezugspunkt und Richtung für die Fassadenkoordinaten (Strecke entlang ax,
## Höhe über origin.y + base_h), face: CUSTOM0 der Fläche (Breite, Oberkante, Art)
static func _bb_poly(st: SurfaceTool, v: Array, nrm: Vector3, col: Color, u2: Vector2, origin := Vector3.ZERO, ax := Vector3.RIGHT,
		base_h := 0.0, face := Color(0, 0, 0)) -> void:
	if (v[1] - v[0]).cross(v[2] - v[0]).dot(nrm) > 0.0:
		v = v.duplicate()
		v.reverse()
	for i in range(1, v.size() - 1):
		for q in [v[0], v[i], v[i + 1]]:
			st.set_normal(nrm)
			st.set_color(col)
			st.set_uv(Vector2((q - origin).dot(ax), q.y - origin.y + base_h))
			st.set_uv2(u2)
			st.set_custom(0, face)
			st.add_vertex(q)


## Satteldach in den Häuser-Batch: Dachflächen als Ziegel (Stil 7), Giebeldreiecke im Fassadenstil des Hauses.
## basis wie beim Haus: x quer zur Straße (Tiefe), z entlang (Breite). gable_front: First quer, Giebel zur Straße.
static func _bb_roof(center: Vector3, basis: Basis, w: float, depth: float, h: float, gable_front: bool,
		roof_tint: Vector3, wall_tint: Vector3, style: float, seed: float, lit: float) -> void:
	var st := _bb_st(center)
	var ax: Vector3 = (basis.z if gable_front else basis.x).normalized()
	var bx: Vector3 = (basis.x if gable_front else basis.z).normalized()
	var span := w if gable_front else depth
	var len := depth if gable_front else w
	var rh := clampf(span * 0.55, 2.5, 9.0)
	var ov := 0.5
	var drop := ov * rh / (span * 0.5)
	var base := center + Vector3(0, h, 0)
	var top := base + Vector3(0, rh, 0)
	var hb := len * 0.5 + 0.3
	var rcol := Color(roof_tint.x, roof_tint.y, roof_tint.z, 0.0)
	var ru := Vector2(seed, 7.0)
	for s in [-1.0, 1.0]:
		var eave: Vector3 = base + ax * s * (span * 0.5 + ov) - Vector3(0, drop, 0)
		var nrm: Vector3 = (ax * s * rh + Vector3(0, span * 0.5, 0)).normalized()
		_bb_poly(st, [eave - bx * hb, eave + bx * hb, top + bx * hb, top - bx * hb], nrm, rcol, ru, base - bx * hb, bx, h,
			Color(len, h + rh, FACE_GABLE))
	var wcol := Color(wall_tint.x, wall_tint.y, wall_tint.z, lit)
	var wu := Vector2(seed, style)
	for s in [-1.0, 1.0]:
		var g0: Vector3 = base + bx * s * len * 0.5
		_bb_poly(st, [g0 - ax * span * 0.5, g0 + ax * span * 0.5, top + bx * s * len * 0.5], bx * s, wcol, wu, g0 - ax * span * 0.5,
			ax, h, Color(span, h + rh, FACE_GABLE))


static func _bb_flush(root: Node3D) -> void:
	var m := ShaderMaterial.new()
	m.shader = BUILDING_SHADER
	for key in _bb:
		var mi := MeshInstance3D.new()
		mi.mesh = (_bb[key] as SurfaceTool).commit()
		mi.material_override = m
		mi.set_meta("no_merge", true)  # schon je Zelle ein Mesh: nicht noch einmal zusammenfassen
		root.add_child(mi)
	_bb = {}


## Leuchtende Werbetafel auf dem Dach, zur Straße gedreht
static func _billboard(root: Node3D, pos: Vector3, face_dir: Vector3, roof_y: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(-face_dir, Vector3.UP), pos + Vector3(0, roof_y, 0))
	root.add_child(n)
	var dark := Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.4)
	var col: Color = NEON[rng.randi() % NEON.size()]
	Builder._add(n, Builder.box(Vector3(9.0, 3.6, 0.3)), Builder.mat(col * 0.25, 0.0, 0.5, col * 0.5, 1.2), Vector3(0, 4.2, 0))
	Builder._add(n, Builder.box(Vector3(9.3, 0.2, 0.4)), dark, Vector3(0, 2.3, 0))
	for x in [-3.5, 3.5]:
		Builder._add(n, Builder.box(Vector3(0.2, 2.4, 0.2)), dark, Vector3(x, 1.2, 0))
	var l := Label3D.new()
	l.text = BRANDS[rng.randi() % BRANDS.size()]
	l.font_size = 120 if l.text.length() <= 13 else 76
	l.pixel_size = 0.012
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = 8.4 / l.pixel_size
	l.modulate = Color(2.5, 2.5, 2.5)
	l.outline_modulate = Color(col.r, col.g, col.b, 1.0)
	l.outline_size = 16
	l.shaded = false
	l.position = Vector3(0, 4.2, 0.17)
	n.add_child(l)
	if rng.randf() < 0.5:
		return  # nur jede zweite Tafel mit Strahler (Lichter sind im Browser teuer)
	var sl := SpotLight3D.new()
	sl.position = Vector3(0, 2.4, 1.5)
	sl.rotation_degrees.x = 60
	sl.light_color = Color(1, 0.95, 0.85)
	sl.light_energy = 2.0
	sl.spot_range = 6.0
	sl.spot_angle = 50.0
	n.add_child(sl)


## Containerstapel im Industrieviertel
static func _containers(root: Node3D, center: Vector3, basis: Basis, rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.6, 0.12, 0.08), Color(0.08, 0.2, 0.5), Color(0.75, 0.4, 0.05), Color(0.1, 0.4, 0.2), Color(0.5, 0.5, 0.52)]
	for i in 2:
		for j in 3:
			var stack := rng.randi_range(1, 3)
			for k in stack:
				var pos := center + basis * Vector3((i - 0.5) * 2.8, 0, (j - 1) * 6.4) + Vector3(0, 1.3 + k * 2.6, 0)
				Builder._add(root, Builder.box(Vector3(2.4, 2.55, 6.1)), Builder.mat(cols[rng.randi() % cols.size()], 0.4, 0.6), pos).basis = basis


## Lichtkarte der Straße: unter jeder Lampe der Strecke (Laternen, Tunnel, Brücken, Flutlicht ...) ein weicher
## Lichtkreis, als Bild über der ganzen Strecke (STREET_CELL Meter je Bildpunkt). Fahrbahn, Gehweg und Tunnelwände
## lesen es im Shader (street_light.gdshaderinc): jede Laterne beleuchtet sichtbar die Straße, auch im Browser, wo
## jedes Objekt nur von wenigen echten Lampen Licht bekommt. Kostet beim Fahren nur einen Texturzugriff.
const STREET_CELL := 2.0
const STREET_GAIN := 5.0  # Helligkeit der Lichtkreise bei voller Sättigung
const STREET_FLOOR := Vector3(0.1, 0.085, 0.07)  # Grundhelligkeit zwischen den Laternen: nirgends pechschwarz


static func _bake_street_light(root: Node3D, track: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var pools: Array = track["pools"].duplicate()
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		for c in (e[0] as Node).get_children():
			if not c is Node3D:
				continue
			var xf: Transform3D = e[1] * (c as Node3D).transform
			if c is OmniLight3D:
				var l := c as OmniLight3D
				if l.has_meta("no_pool") or l.omni_range > 40.0:
					continue
				var p := xf.origin
				var loc := locate(track, p)
				var h := p.y - elev_at((loc["path"] as Dictionary)["curve"], loc["d"])
				if h < 0.5 or h > 18.0:
					continue
				# Kreis so weit, wie das Licht den Boden erreicht; hohe Lampen streuen breiter und schwächer
				var r := clampf(sqrt(maxf(l.omni_range * l.omni_range - h * h, 16.0)) * 1.05, 6.0, 28.0)
				var k := l.light_energy * 0.55 * clampf(1.4 - h / 14.0, 0.5, 1.2)
				pools.append([p.x, p.z, r, l.light_color * k])
			if c.get_child_count() > 0:
				stack.append([c, xf])
	Builder.street = {}
	if pools.is_empty():
		for m in _road_mats.values():
			m.set_shader_parameter("street_gain", 0.0)  # sonst blieben die Lichtkreise der vorigen Strecke
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for pl in pools:
		lo = Vector2(minf(lo.x, pl[0] - pl[2]), minf(lo.y, pl[1] - pl[2]))
		hi = Vector2(maxf(hi.x, pl[0] + pl[2]), maxf(hi.y, pl[1] + pl[2]))
	lo -= Vector2(4.0, 4.0)
	hi += Vector2(4.0, 4.0)
	# Texturdetails Normal: höchstens 1024 Bildpunkte (ein Viertel des Speichers), Hoch: 2048
	var cell := maxf(STREET_CELL, maxf(hi.x - lo.x, hi.y - lo.y) / (2048.0 if GameState.gv("tex") == 1 else 1024.0))
	var w := int(ceil((hi.x - lo.x) / cell))
	var h := int(ceil((hi.y - lo.y) / cell))
	# Summe je Bildpunkt (nur berührte Punkte), danach ins 8-Bit-Bild
	var acc := {}
	for pl in pools:
		var r: float = pl[2]
		var col: Color = pl[3]
		var cx := (float(pl[0]) - lo.x) / cell - 0.5
		var cz := (float(pl[1]) - lo.y) / cell - 0.5
		var rr := r / cell
		for iz in range(maxi(int(floor(cz - rr)), 0), mini(int(ceil(cz + rr)), h - 1) + 1):
			for ix in range(maxi(int(floor(cx - rr)), 0), mini(int(ceil(cx + rr)), w - 1) + 1):
				var x2 := (Vector2(ix - cx, iz - cz) / rr).length_squared()
				if x2 >= 1.0:
					continue
				# flacher heller Kern, weicher Rand; direkt unter der Lampe etwas heller
				var x := sqrt(x2)
				var f := (1.0 - smoothstep(0.3, 1.0, x)) * (0.8 + 0.2 * exp(-x2 * 6.0))
				var idx := iz * w + ix
				acc[idx] = acc.get(idx, Color(0, 0, 0)) + col * f
	# weiche Sättigung: wo sich viele Kreise überlagern (Boulevard mit Doppel-Laternen), wird es nicht grell
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for idx in acc:
		var v: Color = acc[idx]
		img.set_pixel(idx % w, idx / w, Color(1.0 - exp(-v.r * 0.9), 1.0 - exp(-v.g * 0.9), 1.0 - exp(-v.b * 0.9)))
	var tex := ImageTexture.create_from_image(img)
	var rect := Vector4(lo.x, lo.y, 1.0 / (w * cell), 1.0 / (h * cell))
	for m in _road_mats.values():
		m.set_shader_parameter("street_light", tex)
		m.set_shader_parameter("street_rect", rect)
		m.set_shader_parameter("street_gain", STREET_GAIN)
		m.set_shader_parameter("street_floor", STREET_FLOOR)
	track["street_light"] = tex
	Builder.street = {"tex": tex, "rect": rect, "gain": STREET_GAIN}
	if OS.get_cmdline_user_args().has("--lightlog"):
		print("LICHTKARTE %dx%d (%.1f m) Kreise=%d Punkte=%d %.0f ms" % [w, h, cell, pools.size(), acc.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lightpng="):  # Test: Lichtkarte als Bild speichern
			img.save_png(a.substr(11))


## Laternen: fliegen weg, wenn man sie trifft (und gehen aus). Form und Lichtfarbe je Viertel.
static func _build_lamps(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var mats := {}
	var d := 20.0
	var side := 1.0
	while d < length:
		var f := frame_at(curve, d)
		# am Trog stehen die Laternen oben auf dem Gehweg hinter der Mauer
		var off: float = (TUN_W + 1.3) if _trough_at(track, d) == 1 else (hw(track, d) + 0.8)
		var base: Vector3 = f["pos"] + f["right"] * side * off
		var ok: bool = _branch_clearance(track, base) > 2.5 and (track["crossing_d"] < 0.0 or absf(d - track["crossing_d"]) > 14.0)
		ok = ok and tunnel_at(track, d, 4.0).is_empty() and _el_side(track, d, 12.0) != side and not _near_post(track, d, 4.0)
		if ok:
			_lamp(root, _district_at(track, d), f, side, base, mats)
		d += LAMP_STEP
		side = -side


## modern: Ausleger mit flachem Kopf. classic: Altstadt-Laterne. sodium: hoher Mast, orange. lantern: roter Lampion.
static func _lamp(root: Node3D, dist: Dictionary, f: Dictionary, side: float, base: Vector3, mats: Dictionary) -> void:
	var kind: String = dist["lamp_kind"]
	var lc: Color = dist["lamp"]
	var key := kind + str(lc)
	if not mats.has(key):
		var pole_c := Color(0.45, 0.05, 0.04) if kind == "lantern" else (Color(0.08, 0.12, 0.1) if kind == "classic" else Color(0.2, 0.2, 0.22))
		mats[key] = {"head": Builder.mat(lc, 0.0, 0.3, lc, 3.0), "pole": Builder.mat(pole_c, 0.6, 0.4)}
	var m: Dictionary = mats[key]
	var h := 8.0
	var arm := 2.4
	var energy := 2.2
	var reach := 20.0
	match kind:
		"classic":
			h = 5.2
			arm = 0.0
			energy = 1.8
			reach = 16.0
		"sodium":
			h = 10.0
			arm = 3.4
			energy = 2.6
			reach = 24.0
		"lantern":
			h = 6.6
			arm = 1.5
			energy = 1.8
			reach = 16.0
	var lamp := Knockable.new()
	lamp.mass = 60.0
	lamp.slowdown = 0.9
	lamp.set_meta("clang", true)
	lamp.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	lamp.center_of_mass = Vector3(0, h / 4.0, 0)
	lamp.transform = Transform3D(Basis.looking_at(-f["right"] * side, Vector3.UP), Vector3(base.x, base.y + CURB_H, base.z))
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.09 if kind == "classic" else 0.12
	cyl.bottom_radius = 0.16
	cyl.height = h
	cyl.radial_segments = 8
	Builder._add(lamp, cyl, m["pole"], Vector3(0, h / 2.0, 0))
	var light_pos := Vector3(0, h - 0.7, -arm)
	match kind:
		"classic":
			Builder._add(lamp, Builder.box(Vector3(0.42, 0.6, 0.42)), m["head"], Vector3(0, h + 0.3, 0))
			Builder._add(lamp, Builder.tapered_box(Vector2(0.75, 0.75), Vector2(0.12, 0.12), 0.4, 0.0), m["pole"], Vector3(0, h + 0.6, 0))
			light_pos = Vector3(0, h + 0.2, -0.4)
		"lantern":
			Builder._add(lamp, Builder.box(Vector3(0.12, 0.12, arm + 0.1)), m["pole"], Vector3(0, h, -arm / 2.0))
			Builder._add(lamp, Builder.box(Vector3(0.03, 0.35, 0.03)), m["pole"], Vector3(0, h - 0.18, -arm))
			var sm := SphereMesh.new()
			sm.radius = 0.38
			sm.height = 0.95
			sm.radial_segments = 10
			sm.rings = 6
			Builder._add(lamp, sm, m["head"], Vector3(0, h - 0.8, -arm))
			light_pos = Vector3(0, h - 0.9, -arm)
		_:
			Builder._add(lamp, Builder.box(Vector3(0.15, 0.15, arm)), m["pole"], Vector3(0, h, -arm / 2.0 + 0.1))
			var hs := Vector3(0.5, 0.12, 0.9) if kind == "modern" else Vector3(0.6, 0.18, 1.3)
			Builder._add(lamp, Builder.box(hs), m["head"], Vector3(0, h - 0.1, -arm))
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = h
	cs.shape = shape
	cs.position.y = h / 2.0
	lamp.add_child(cs)
	var light := OmniLight3D.new()
	light.light_color = lc
	light.light_energy = energy * 0.8
	light.omni_range = reach
	light.omni_attenuation = 1.2
	light.position = light_pos
	lamp.add_child(light)
	root.add_child(lamp)


## Gehweg-Möblierung: leichte Sachen fliegen weg, schwere (Hydrant, Poller, Kübel, Haltestelle, Bäume) sind hart.
## 0/1 Mülltonne, 2 Leitkegel, 3 Briefkasten, 4 Parkscheinautomat, 5 Bank, 6 Hydrant, 7 Poller, 8 Pflanzkübel,
## 9 Haltestelle, 10 Telefonzelle, 11 Zeitungsboxen, 12 Parkuhr, 13 Verkehrsschild, 14 Müllcontainer, 15 Betonleitwand
static func _build_props(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var green := Builder.mat(Color(0.1, 0.35, 0.15), 0.2, 0.6)
	var orange := Builder.mat(Color(1, 0.4, 0.05), 0, 0.5, Color(1, 0.35, 0.0), 0.6)
	var blue := Builder.mat(Color(0.1, 0.2, 0.6), 0.3, 0.5)
	var yellow := Builder.mat(Color(1, 0.8, 0.05), 0.2, 0.5)
	var wood := Builder.mat(Color(0.35, 0.22, 0.12), 0.0, 0.8)
	var red := Builder.mat(Color(0.8, 0.05, 0.05), 0.3, 0.4)
	var dark := Builder.mat(Color(0.12, 0.12, 0.13), 0.5, 0.5)
	var concrete := Builder.mat(Color(0.35, 0.35, 0.36), 0.0, 0.9)
	var bush := Builder.mat(Color(0.05, 0.25, 0.08), 0.0, 0.9)
	var glass := Builder.mat(Color(0.3, 0.4, 0.5), 0.6, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.3
	var ad := Builder.mat(Color(1, 1, 1), 0, 0.4, Color(0.9, 0.95, 1.0), 2.5)
	var grey_m := Builder.mat(Color(0.45, 0.46, 0.48), 0.6, 0.4)
	var sign_w := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.5)

	for side in [-1.0, 1.0]:
		var d := rng.randf_range(5.0, 12.0)
		while d < length - 10.0:
			var lamp_phase := fmod(d - 20.0 + LAMP_STEP * 2.0, LAMP_STEP)
			var f := frame_at(curve, d)
			var hwd := hw(track, d)
			if lamp_phase < 3.0 or lamp_phase > LAMP_STEP - 3.0 or _in_zone(track, d, 4.0) \
					or _el_side(track, d, 6.0) == side or _near_post(track, d, 3.0) \
					or _branch_clearance(track, f["pos"] + f["right"] * side * (hwd + 2.5)) < 4.0:
				d += 4.0
				continue
			var dist: Dictionary = _district_at(track, d)
			if rng.randf() < dist["trees"]:
				# an der Bordsteinkante: der Streifen an der Mauer bleibt frei zum Entlangschrammen
				var tp: Vector3 = f["pos"] + f["right"] * side * (hwd + 1.5)
				var ring := CylinderMesh.new()
				ring.top_radius = 0.7
				ring.bottom_radius = 0.7
				ring.height = 0.25
				ring.radial_segments = 8
				Builder._add(root, ring, concrete, tp + Vector3(0, CURB_H + 0.12, 0))
				_tree(root, tp + Vector3(0, CURB_H, 0), rng, true)
				d += rng.randf_range(8.0, 14.0)
				continue
			var kinds: Array = dist["props"]
			var kind: int = kinds[rng.randi() % kinds.size()]
			var off := hwd + rng.randf_range(1.0, WALK - 0.9)
			if kind == 15:
				off = hwd + 0.55
			var pos: Vector3 = f["pos"] + f["right"] * side * off
			var basis := Basis.looking_at(-f["right"] * side, Vector3.UP)
			var xf := Transform3D(basis, Vector3(pos.x, CURB_H, pos.z))
			if kind <= 5 or kind == 11 or kind == 12 or kind == 13:
				var k := Knockable.new()
				k.transform = xf
				var sz := Vector3.ONE
				match kind:
					0, 1:
						var c := CylinderMesh.new()
						c.top_radius = 0.35
						c.bottom_radius = 0.3
						c.height = 1.0
						c.radial_segments = 10
						Builder._add(k, c, green, Vector3(0, 0.5, 0))
						sz = Vector3(0.7, 1.0, 0.7)
						k.mass = 15.0
					2:
						var c := CylinderMesh.new()
						c.top_radius = 0.04
						c.bottom_radius = 0.25
						c.height = 0.7
						c.radial_segments = 8
						Builder._add(k, c, orange, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 0.7, 0.5)
						k.mass = 3.0
						k.slowdown = 0.99
					3:
						Builder._add(k, Builder.box(Vector3(0.5, 1.1, 0.5)), blue, Vector3(0, 0.55, 0))
						sz = Vector3(0.5, 1.1, 0.5)
						k.mass = 20.0
					4:
						Builder._add(k, Builder.box(Vector3(0.5, 0.6, 0.35)), yellow, Vector3(0, 1.0, 0))
						Builder._add(k, Builder.box(Vector3(0.08, 0.7, 0.08)), dark, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 1.3, 0.4)
						k.mass = 25.0
					5:
						Builder._add(k, Builder.box(Vector3(1.8, 0.1, 0.5)), wood, Vector3(0, 0.45, 0))
						Builder._add(k, Builder.box(Vector3(1.8, 0.5, 0.08)), wood, Vector3(0, 0.75, 0.22))
						sz = Vector3(1.8, 0.9, 0.5)
						k.mass = 40.0
					11:
						Builder._add(k, Builder.box(Vector3(0.5, 1.0, 0.45)), red, Vector3(-0.3, 0.5, 0))
						Builder._add(k, Builder.box(Vector3(0.5, 0.9, 0.45)), blue, Vector3(0.3, 0.45, 0))
						sz = Vector3(1.1, 1.0, 0.45)
						k.mass = 18.0
					12:
						Builder._add(k, Builder.box(Vector3(0.08, 1.0, 0.08)), dark, Vector3(0, 0.5, 0))
						Builder._add(k, Builder.box(Vector3(0.24, 0.34, 0.2)), grey_m, Vector3(0, 1.15, 0))
						sz = Vector3(0.3, 1.35, 0.3)
						k.mass = 6.0
						k.slowdown = 0.99
					13:
						Builder._add(k, Builder.box(Vector3(0.07, 2.4, 0.07)), grey_m, Vector3(0, 1.2, 0))
						var disc := CylinderMesh.new()
						disc.top_radius = 0.36
						disc.bottom_radius = 0.36
						disc.height = 0.04
						disc.radial_segments = 14
						Builder._add(k, disc, red, Vector3(0, 2.3, 0)).rotation = Vector3(0, 0, PI / 2.0)
						var inner := CylinderMesh.new()
						inner.top_radius = 0.27
						inner.bottom_radius = 0.27
						inner.height = 0.05
						inner.radial_segments = 14
						Builder._add(k, inner, sign_w, Vector3(0, 2.3, 0)).rotation = Vector3(0, 0, PI / 2.0)
						sz = Vector3(0.3, 2.6, 0.3)
						k.mass = 8.0
						k.slowdown = 0.98
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = sz
				cs.shape = bs
				cs.position.y = sz.y / 2.0
				k.add_child(cs)
				root.add_child(k)
			else:
				# Schwere Sachen: fliegen auch weg, kosten aber deutlich mehr Tempo (kein abrupter Stopp)
				var s := Knockable.new()
				s.transform = xf
				var heavy := {6: [90.0, 0.75], 7: [120.0, 0.7], 8: [150.0, 0.65], 9: [250.0, 0.55], 10: [160.0, 0.65],
					14: [220.0, 0.6], 15: [300.0, 0.55]}
				s.mass = heavy[kind][0]
				s.slowdown = heavy[kind][1]
				root.add_child(s)
				match kind:
					6:
						var c := CylinderMesh.new()
						c.top_radius = 0.16
						c.bottom_radius = 0.2
						c.height = 0.8
						c.radial_segments = 8
						Builder._add(s, c, red, Vector3(0, 0.4, 0))
						_knock_shape(s, Vector3(0.45, 1.0, 0.45), Vector3(0, 0.5, 0))
					7:
						for i in 3:
							var c := CylinderMesh.new()
							c.top_radius = 0.12
							c.bottom_radius = 0.12
							c.height = 0.9
							c.radial_segments = 8
							Builder._add(s, c, dark, Vector3(-1.5 + i * 1.5, 0.45, 0))
							_knock_shape(s, Vector3(0.3, 1.0, 0.3), Vector3(-1.5 + i * 1.5, 0.5, 0))
					8:
						Builder._add(s, Builder.box(Vector3(1.4, 0.6, 1.4)), concrete, Vector3(0, 0.3, 0))
						var sm := SphereMesh.new()
						sm.radius = 0.75
						sm.height = 1.2
						sm.radial_segments = 8
						sm.rings = 4
						Builder._add(s, sm, bush, Vector3(0, 1.0, 0))
						_knock_shape(s, Vector3(1.4, 1.2, 1.4), Vector3(0, 0.6, 0))
					9:
						s.transform.origin = Vector3(pos.x, CURB_H, pos.z) + f["right"] * side * (hwd + WALK - 1.1 - off)
						Builder._add(s, Builder.box(Vector3(3.6, 0.12, 1.5)), dark, Vector3(0, 2.5, 0))
						Builder._add(s, Builder.box(Vector3(3.6, 2.4, 0.06)), glass, Vector3(0, 1.25, 0.7))
						Builder._add(s, Builder.box(Vector3(0.06, 2.4, 1.4)), ad, Vector3(1.75, 1.25, 0))
						Builder._add(s, Builder.box(Vector3(2.4, 0.08, 0.4)), wood, Vector3(-0.3, 0.45, 0.45))
						_knock_shape(s, Vector3(3.6, 2.5, 1.5), Vector3(0, 1.25, 0))
					10:
						for cx in [-0.52, 0.52]:
							for cz in [-0.52, 0.52]:
								Builder._add(s, Builder.box(Vector3(0.08, 2.4, 0.08)), dark, Vector3(cx, 1.2, cz))
						Builder._add(s, Builder.box(Vector3(1.0, 2.1, 1.0)), glass, Vector3(0, 1.1, 0))
						Builder._add(s, Builder.box(Vector3(1.14, 0.12, 1.14)), dark, Vector3(0, 2.45, 0))
						var tc: Color = NEON[rng.randi() % NEON.size()]
						Builder._add(s, Builder.box(Vector3(1.1, 0.28, 1.1)), Builder.mat(tc, 0.0, 0.4, tc, 2.0), Vector3(0, 2.25, 0))
						_label(s, "TELEFON", Color(0.05, 0.05, 0.05), 12, Vector3(0, 2.25, -0.57), 1.0)
						_knock_shape(s, Vector3(1.1, 2.5, 1.1), Vector3(0, 1.25, 0))
					14:
						s.transform.origin = Vector3(pos.x, CURB_H, pos.z) + f["right"] * side * (hwd + WALK - 1.0 - off)
						var dc := Builder.mat(Color(0.05, 0.25, 0.12) if rng.randf() < 0.5 else Color(0.08, 0.15, 0.4), 0.4, 0.6)
						Builder._add(s, Builder.box(Vector3(1.9, 1.2, 1.1)), dc, Vector3(0, 0.65, 0))
						Builder._add(s, Builder.box(Vector3(1.96, 0.08, 1.16)), dark, Vector3(0, 1.3, 0.05)).rotation.x = 0.12
						_knock_shape(s, Vector3(2.0, 1.4, 1.2), Vector3(0, 0.7, 0))
					15:
						Builder._add(s, Builder.tapered_box(Vector2(3.6, 0.6), Vector2(3.6, 0.22), 0.85, 0.0), concrete, Vector3.ZERO)
						_knock_shape(s, Vector3(3.6, 1.0, 0.6), Vector3(0, 0.5, 0))
			d += rng.randf_range(7.0, 15.0) * dist.get("prop_gap", 1.0)


## Zuschauer (Figuren aus people.gd, im Shader bewegt): jubeln, winken, filmen mit dem Handy. people.gd teilt sie in
## kleine Zellen (nah detailliert, fern als Blockfigur); ab ~220 m ausgeblendet.
static func _build_spectators(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var chunks := {}
	for e in track["spectators"]:
		var k := int(e[1] / 300.0)
		if not chunks.has(k):
			chunks[k] = []
		chunks[k].append(e[0])
	for k in chunks:
		People.crowd(root, chunks[k], [People.CHEER, People.WAVE, People.CLAP, People.PHONE, People.WAIT, People.CHEER], rng, 220.0)


## Dampf aus Gullys
static func _build_steam(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.25, 0.35, 0.0)
	pm.scale_min = 1.6
	pm.scale_max = 3.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.14)
	# weiche, runde Schwaden statt harter Quadrate
	var puff := GradientTexture2D.new()
	puff.width = 64
	puff.height = 64
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	var pg := Gradient.new()
	pg.set_color(0, Color(1, 1, 1, 1))
	pg.set_color(1, Color(1, 1, 1, 0))
	pg.add_point(0.45, Color(1, 1, 1, 0.5))
	puff.gradient = pg
	m.albedo_texture = puff
	quad.material = m
	var cover := Builder.mat(Color(0.08, 0.08, 0.08), 0.6, 0.5)
	var d := rng.randf_range(80.0, 160.0)
	while d < length - 50.0:
		if not _in_zone(track, d, 10.0):
			var f := frame_at(curve, d)
			var pos: Vector3 = f["pos"] + f["right"] * lane_lat(track, d, LANES[rng.randi() % 4])
			var gp := GPUParticles3D.new()
			gp.amount = 20
			gp.lifetime = 3.5
			gp.preprocess = 3.0
			gp.process_material = pm
			gp.draw_pass_1 = quad
			gp.position = pos + Vector3(0, 0.1, 0)
			root.add_child(gp)
			var disc := CylinderMesh.new()
			disc.top_radius = 0.45
			disc.bottom_radius = 0.45
			disc.height = 0.02
			disc.radial_segments = 12
			Builder._add(root, disc, cover, pos + Vector3(0, 0.01, 0))
		d += rng.randf_range(160.0, 280.0)


## Drag: Entfernungstafeln am Rand (alle 200 m) und eine leuchtende Viertelmeile
static func _drag_boards(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var post := Builder.mat(Color(0.2, 0.2, 0.22), 0.6, 0.4)
	var board := Builder.mat(Color(0.05, 0.05, 0.06), 0.2, 0.5, Color(1.0, 0.85, 0.2), 0.6)
	var k := 1
	while track["start"] + k * 200.0 < track["finish"] - 30.0:
		var d: float = track["start"] + k * 200.0
		var f := frame_at(curve, d)
		if _trough_at(track, d) == 0:
			for s in [-1.0, 1.0]:
				var n := Node3D.new()
				n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + f["right"] * s * (hw(track, d) + 1.2) + Vector3(0, CURB_H, 0))
				root.add_child(n)
				Builder._add(n, Builder.box(Vector3(0.12, 2.6, 0.12)), post, Vector3(0, 1.3, 0))
				Builder._add(n, Builder.box(Vector3(1.6, 0.8, 0.08)), board, Vector3(0, 2.6, 0))
				var l := _label(n, "%d m" % (k * 200), Color(1.0, 0.85, 0.2), 40, Vector3(0, 2.6, 0.05), 2.0)
				l.rotation.y = 0.0  # zum ankommenden Fahrer
		k += 1
	var qd: float = track["start"] + 402.0
	if qd < track["finish"] - 40.0 and _trough_at(track, qd) == 0 and not _near_post(track, qd, 12.0):
		_gate(root, track, qd, "1/4 MEILE", Color(1.0, 0.75, 0.15))


static func _gate(root: Node3D, track: Dictionary, d: float, text: String, col: Color) -> void:
	var f := frame_at(track["curve"], d)
	var basis := Basis.looking_at(f["fwd"], Vector3.UP)
	var em := Builder.mat(col, 0.0, 0.4, col, 3.0)
	var dark := Builder.mat(Color(0.1, 0.1, 0.12), 0.5, 0.4)
	var half := hw(track, d) + 1.4  # Pfeiler immer neben der Fahrbahn (Drift-Kurse sind breiter)
	for s in [-1, 1]:
		var pillar := Node3D.new()
		pillar.transform = Transform3D(basis, f["pos"] + f["right"] * s * half)
		root.add_child(pillar)
		Builder._add(pillar, Builder.box(Vector3(0.8, 7.0, 0.8)), dark, Vector3(0, 3.5, 0))
		_solid(pillar, Vector3(0.8, 7.0, 0.8), Vector3(0, 3.5, 0))
	var beam := MeshInstance3D.new()
	beam.mesh = Builder.box(Vector3(half * 2.0 + 0.8, 1.4, 0.6))
	beam.material_override = dark
	beam.transform = Transform3D(basis, f["pos"] + Vector3(0, 7.2, 0))
	root.add_child(beam)
	var strip := MeshInstance3D.new()
	strip.mesh = Builder.box(Vector3(half * 2.0 + 0.8, 0.15, 0.65))
	strip.material_override = em
	strip.transform = Transform3D(basis, f["pos"] + Vector3(0, 6.5, 0))
	root.add_child(strip)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 128
	lbl.pixel_size = 0.012
	lbl.modulate = Color(col.r * 2.5, col.g * 2.5, col.b * 2.5)
	lbl.shaded = false
	lbl.double_sided = true
	lbl.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + Vector3(0, 7.25, 0) - f["fwd"] * 0.35)
	root.add_child(lbl)
	var tile_m := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.4)
	for i in 16:
		for row in 2:
			if (i + row) % 2 == 0:
				continue
			var tile := MeshInstance3D.new()
			tile.mesh = Builder.box(Vector3(HALF_W * 2 / 16.0, 0.02, 0.9))
			tile.material_override = tile_m
			var lat := -HALF_W + (i + 0.5) * HALF_W * 2 / 16.0
			tile.transform = Transform3D(basis, f["pos"] + f["right"] * lat + f["fwd"] * (row * 0.9) + Vector3(0, 0.01, 0))
			root.add_child(tile)


# --- Hilfen: Teile bündeln --------------------------------------------------------

## Teil [mesh, Transform3D] unter einem Material sammeln (für _bake)
static func _part(groups: Dictionary, m: Material, mesh: Mesh, xf: Transform3D) -> void:
	if not groups.has(m):
		groups[m] = []
	groups[m].append([mesh, xf])


## Gesammelte Teile je Material zu einem Mesh zusammenfassen (spart tausende Knoten)
static func _bake(parent: Node3D, groups: Dictionary, xf := Transform3D.IDENTITY) -> void:
	for m in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in groups[m]:
			st.append_from(p[0], 0, p[1])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		mi.transform = xf
		parent.add_child(mi)


static func _multi(parent: Node3D, mesh: Mesh, m: Material, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = m
	parent.add_child(mmi)


## Senkrechte Wand von a nach b mit UV in Metern (u entlang, v Höhe)
static func _wall_uv(st: SurfaceTool, a: Vector3, b: Vector3, h: float, u0: float, u1: float, flip: bool) -> void:
	var up := Vector3(0, h, 0)
	var vs := [[a, Vector2(u0, 0)], [b + up, Vector2(u1, h)], [b, Vector2(u1, 0)], [a, Vector2(u0, 0)], [a + up, Vector2(u0, h)], [b + up, Vector2(u1, h)]] \
		if flip else [[a, Vector2(u0, 0)], [b, Vector2(u1, 0)], [b + up, Vector2(u1, h)], [a, Vector2(u0, 0)], [b + up, Vector2(u1, h)], [a + up, Vector2(u0, h)]]
	for v in vs:
		st.set_uv(v[1])
		st.add_vertex(v[0])


# --- Abfragen: Tunnel, Hochbahn, Masten ------------------------------------------

## Tunnel an Position d der Hauptstraße (oder leeres Dictionary)
static func tunnel_at(track: Dictionary, d: float, margin := 0.0) -> Dictionary:
	for t in track["tunnels"]:
		if d > t["from"] - margin and d < t["to"] + margin:
			return t
	return {}


## Seite (-1/1), auf der bei d die Hochbahn steht, sonst 0
static func _el_side(track: Dictionary, d: float, margin := 0.0) -> float:
	for e in track["el"]:
		if d > e["from"] - margin and d < e["to"] + margin:
			return e["side"]
	return 0.0


## Steht bei d ein Mast quer über die Straße (Schilderbrücke, Tor)?
static func _near_post(track: Dictionary, d: float, r: float) -> bool:
	for pd in track["posts"]:
		if absf(d - pd) < r:
			return true
	return false


## Darf bei d etwas über die Straße gespannt werden?
static func _overhead_free(track: Dictionary, d: float, margin: float) -> bool:
	return not _in_zone(track, d, margin) and _el_side(track, d, margin + 8.0) == 0.0 \
		and d > track["start"] + 30.0 and d < track["finish"] - 15.0


## Ist der Abschnitt a..b frei von Kreuzungen, Abkürzungen, Bahnübergang, Tunneln und Hochbahn?
static func _range_free(track: Dictionary, a: float, b: float) -> bool:
	var end: float = (track["length"] - 60.0) if track["loop"] else (track["finish"] - 40.0)
	if a < track["start"] + 100.0 or b > end:
		return false
	for z in track["zones"]:
		if z["to"] > a and z["from"] < b:
			return false
	for p in track["paths"]:
		if (p["kind"] == "alley" or p["kind"] == "lake") and p["to"] + 40.0 > a and p["from"] - 40.0 < b:
			return false
	for e in track["el"]:
		if e["to"] > a and e["from"] < b:
			return false
	return true


## Liegt zwischen a und b irgendwo ein Mittelstreifen?
static func _near_median(track: Dictionary, a: float, b: float) -> bool:
	for r in track["medians"]:
		if r["to"] > a and r["from"] < b:
			return true
	return false


## Boulevards: Mittelstreifen in Boulevard-Vierteln (immer), auf Schnellstraße und in Downtown (manchmal).
## Nicht an Kreuzungen, Abzweigen, Tunneln, Hochbahn, Bahnübergang, Start und Ziel.
static func _plan_medians(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var L: float = track["length"]
	var end: float = (L - 60.0) if track["loop"] else (track["finish"] - 50.0)
	var blocked := [[-1e9, track["start"] + 90.0], [end, 1e9]]
	for z in track["zones"]:
		blocked.append([z["from"] - 15.0, z["to"] + 15.0])
	for e in track["el"]:
		blocked.append([e["from"] - 25.0, e["to"] + 25.0])
	for r in track["medians"]:
		blocked.append([r["from"] - 40.0, r["to"] + 40.0])
	var arr: Array = track["districts"]
	for i in arr.size():
		var dist: Dictionary = DISTRICTS[arr[i]]
		if rng.randf() >= dist.get("median", 0.0):
			continue
		# freie Stücke des Viertels finden
		var pieces := [[i * DISTRICT_LEN + 20.0, (i + 1) * DISTRICT_LEN - 20.0]]
		for bl in blocked:
			var next := []
			for pc in pieces:
				if bl[1] <= pc[0] or bl[0] >= pc[1]:
					next.append(pc)
					continue
				if bl[0] > pc[0]:
					next.append([pc[0], bl[0]])
				if bl[1] < pc[1]:
					next.append([bl[1], pc[1]])
			pieces = next
		for pc in pieces:
			if pc[1] - pc[0] >= 130.0:
				track["medians"].append({"from": pc[0], "to": pc[1]})
	# Benachbarte Stücke (nur durch die Viertelgrenze getrennt) zu einem Boulevard verbinden
	track["medians"].sort_custom(func(a, b): return a["from"] < b["from"])
	var merged := []
	for r in track["medians"]:
		if not merged.is_empty() and r["from"] - merged[-1]["to"] < 45.0:
			var free := true
			for bl in blocked:
				if bl[1] > merged[-1]["to"] and bl[0] < r["from"]:
					free = false
			if free:
				merged[-1]["to"] = maxf(merged[-1]["to"], r["to"])
				continue
		merged.append(r)
	track["medians"] = merged


## 1–2 Tunnel pro Strecke. Die Fahrbahn taucht davor in einem offenen Trog ab (r0..from) und kommt dahinter
## wieder hoch (to..r1); die Stadt bleibt oben, der Tunnel liegt unter einem Häuserblock.
static func _plan_tunnels(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var L: float = track["length"]
	var name_i := rng.randi() % TUNNEL_NAMES.size()
	var count := (1 + int(L > 2200.0)) if track["loop"] else (2 + int(L > 3500.0))
	for k in count:
		for attempt in 150:
			var len := rng.randf_range(170.0, 280.0)
			var d0 := rng.randf_range(0.08, 0.92) * L
			if not _range_free(track, d0 - DIP_RAMP - 30.0, d0 + len + DIP_RAMP + 30.0):
				continue
			var t := {"from": d0, "to": d0 + len, "name": TUNNEL_NAMES[(name_i + k) % TUNNEL_NAMES.size()],
				"sodium": rng.randf() < 0.65, "r0": d0 - DIP_RAMP, "r1": d0 + len + DIP_RAMP}
			track["tunnels"].append(t)
			track["zones"].append({"from": t["r0"] - 18.0, "to": t["r1"] + 18.0})
			track["elev0"].append({"a": t["r0"], "b": d0 + 4.0, "c": t["to"] - 4.0, "e": t["r1"], "h": -DIP})
			break


## Trog/Tunnel bei d: 0 = nichts, 1 = offener Trog (Rampe), 2 = im Tunnel
static func _trough_at(track: Dictionary, d: float) -> int:
	for t in track["tunnels"]:
		if d >= t["from"] and d <= t["to"]:
			return 2
		if d > t["r0"] and d < t["r1"]:
			return 1
	return 0


## Hochbahn: ein Viadukt über Gehweg und Außenspur, in Markt-, China-, Docks- oder Downtown-Vierteln
static func _plan_el(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var arr: Array = track["districts"]
	var cands := []
	for i in arr.size():
		if arr[i] in ["shops", "chinatown", "industrial", "downtown"]:
			cands.append(i)
	if cands.is_empty():
		return
	for attempt in 60:
		var i: int = cands[rng.randi() % cands.size()]
		var len := rng.randf_range(240.0, 340.0)
		var d0 := i * DISTRICT_LEN + rng.randf_range(-60.0, DISTRICT_LEN - len)
		if not _range_free(track, d0 - 25.0, d0 + len + 25.0):
			continue
		track["el"].append({"from": d0, "to": d0 + len, "side": 1.0 if rng.randf() < 0.5 else -1.0,
			"station": STATIONS[rng.randi() % STATIONS.size()]})
		return


# --- Tunnel ---------------------------------------------------------------------

## Tunnel unter einem Häuserblock: Kachelwände, Lichtbänder, Strahlventilatoren, Notausgänge, Portale.
static func _build_tunnels(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	if track["tunnels"].is_empty():
		return
	var curve: Curve3D = track["curve"]
	var tile := ShaderMaterial.new()
	tile.shader = TUNNEL_SHADER
	_road_mats[Vector3(-2.0, 0.0, 0.0)] = tile  # bekommt mit Fahrbahn und Gehweg die Lichtkarte
	var ceil_m := Builder.mat(Color(0.05, 0.05, 0.055), 0.0, 0.9)
	var steel := Builder.mat(Color(0.32, 0.33, 0.35), 0.7, 0.4)
	var panel := ShaderMaterial.new()
	panel.shader = PANEL_SHADER
	var warn := Builder.mat(Color(0.9, 0.62, 0.05), 0.0, 0.5)
	var exit_m := Builder.mat(Color(0.1, 0.9, 0.3), 0.0, 0.4, Color(0.1, 1.0, 0.35), 3.0)
	var walls := StaticBody3D.new()
	root.add_child(walls)
	for t in track["tunnels"]:
		var col: Color = Color(1.0, 0.6, 0.25) if t["sodium"] else Color(0.75, 0.9, 1.0)
		var lamp_m := Builder.mat(col, 0.0, 0.3, col, 6.0)
		var d0: float = t["from"]
		var len: float = t["to"] - d0

		# Wände + Decke + Kollision
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sc := SurfaceTool.new()
		sc.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := int(ceil(len / 3.0))
		var prev := {}
		for i in n + 1:
			var u := len * i / n
			var f := frame_at(curve, d0 + u)
			var c: Vector3 = f["pos"] + Vector3(0, f["y"], 0)
			var r: Vector3 = f["right"]
			var cur := {"l": c - r * TUN_W, "r": c + r * TUN_W, "u": u, "dir": r}
			if not prev.is_empty():
				# Kollision der Seitenwände kommt aus _build_road (durchgehend mit dem Trog)
				_wall_uv(st, prev["l"], cur["l"], TUN_H, prev["u"], u, true)
				_wall_uv(st, prev["r"], cur["r"], TUN_H, prev["u"], u, false)
				var up := Vector3(0, TUN_H, 0)
				for v in [prev["l"] + up, prev["r"] + up, cur["l"] + up, prev["r"] + up, cur["r"] + up, cur["l"] + up]:
					sc.set_uv(Vector2.ZERO)
					sc.add_vertex(v)
				if i % 10 == 0 or i == n:  # 30-m-Stücke, damit jedes Stück seine Tunnellampen abbekommt
					_flush(root, st, tile)
					_flush(root, sc, ceil_m)
					st = SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					sc = SurfaceTool.new()
					sc.begin(Mesh.PRIMITIVE_TRIANGLES)
			prev = cur

		# Lichtbänder an der Decke (der Rhythmus beim Durchfahren macht Tempo spürbar)
		var strips := []
		var u := 2.0
		while u < len:
			var f := frame_at(curve, d0 + u)
			if fmod(u, 3.0) < 1.6:
				# der ganze Tunnel gleichmäßig hell (Lichtkarte), wie unter durchgehenden Leuchtbändern
				track["pools"].append([f["pos"].x, f["pos"].z, TUN_W + 0.5, col * 0.3])
			var b := Basis.looking_at(f["fwd"], Vector3.UP)
			for s in [-1.0, 1.0]:
				strips.append(Transform3D(b, f["pos"] + f["right"] * s * (TUN_W - 0.45) + Vector3(0, f["y"] + TUN_H - 0.3, 0)))
			u += 4.5
		_multi(root, Builder.box(Vector3(0.3, 0.12, 2.6)), lamp_m, strips)
		var side := 1.0
		u = 10.0
		while u < len - 5.0:
			var f := frame_at(curve, d0 + u)
			var light := OmniLight3D.new()
			light.light_color = col
			light.light_energy = 1.5
			light.omni_range = 15.0
			light.omni_attenuation = 1.0
			light.position = f["pos"] + f["right"] * side * (TUN_W - 1.6) + Vector3(0, f["y"] + TUN_H - 0.8, 0)
			root.add_child(light)
			side = -side
			u += 22.0

		# Strahlventilatoren und Notausgänge
		var g := {}
		u = 35.0
		while u < len - 20.0:
			var f := frame_at(curve, d0 + u)
			var b := Basis.looking_at(f["fwd"], Vector3.UP)
			for s in [-1.0, 1.0]:
				var fan := CylinderMesh.new()
				fan.top_radius = 0.6
				fan.bottom_radius = 0.6
				fan.height = 3.6
				fan.radial_segments = 12
				var p: Vector3 = f["pos"] + f["right"] * s * 3.2 + Vector3(0, f["y"] + TUN_H - 0.85, 0)
				_part(g, steel, fan, Transform3D(b * Basis(Vector3.RIGHT, PI / 2.0), p))
				_part(g, steel, Builder.box(Vector3(0.1, 0.3, 0.1)), Transform3D(b, p + Vector3(0, 0.7, 0)))
			u += 70.0
		u = 25.0
		side = -1.0
		while u < len - 10.0:
			var f := frame_at(curve, d0 + u)
			var wb := Basis.looking_at(f["right"] * side, Vector3.UP)  # +Z zeigt zur Fahrbahn
			var p: Vector3 = f["pos"] + f["right"] * side * (TUN_W - 0.06) + Vector3(0, f["y"] + 2.6, 0)
			_part(g, exit_m, Builder.box(Vector3(1.4, 0.4, 0.1)), Transform3D(wb, p))
			var l := Label3D.new()
			l.text = "NOTAUSGANG"
			l.font_size = 32
			l.pixel_size = 0.008
			l.modulate = Color(0.0, 0.05, 0.0)
			l.shaded = false
			l.double_sided = false
			l.transform = Transform3D(wb, p + wb.z * 0.06)
			root.add_child(l)
			side = -side
			u += 55.0
		_bake(root, g)

		# Portale: Betonfront mit Warnstreifen, Lichtern und Namen
		for end in 2:
			var d: float = d0 if end == 0 else t["to"]
			var f := frame_at(curve, d)
			var out_dir: Vector3 = -f["fwd"] if end == 0 else f["fwd"]
			var pn := Node3D.new()
			pn.transform = Transform3D(Basis.looking_at(-out_dir, Vector3.UP), f["pos"] + Vector3(0, f["y"], 0))  # +Z zeigt aus dem Tunnel
			root.add_child(pn)
			var pg := {}
			var half := HALF_W + WALK + 12.0
			var ph := 14.0
			for s in [-1.0, 1.0]:
				var w := half - TUN_W
				_part(pg, panel, Builder.box(Vector3(w, ph, 2.6)), Transform3D(Basis(), Vector3(s * (TUN_W + w / 2.0), ph / 2.0, -1.0)))
				_part(pg, warn, Builder.box(Vector3(0.35, TUN_H, 0.1)), Transform3D(Basis(), Vector3(s * (TUN_W + 0.18), TUN_H / 2.0, 0.33)))
				_wall_shape(walls, f["pos"] + f["right"] * s * TUN_W, f["pos"] + f["right"] * s * (HALF_W + WALK + 0.6))
			_part(pg, panel, Builder.box(Vector3(TUN_W * 2.0, ph - TUN_H, 2.6)), Transform3D(Basis(), Vector3(0, (ph + TUN_H) / 2.0, -1.0)))
			_part(pg, warn, Builder.box(Vector3(TUN_W * 2.0 + 0.7, 0.35, 0.1)), Transform3D(Basis(), Vector3(0, TUN_H + 0.18, 0.33)))
			for k in 7:
				_part(pg, lamp_m, Builder.box(Vector3(0.6, 0.15, 0.3)), Transform3D(Basis(), Vector3(-7.5 + k * 2.5, TUN_H + 0.65, 0.45)))
			_bake(pn, pg)
			for s in [-1.0, 1.0]:
				var fl := OmniLight3D.new()
				fl.light_color = Color(1.0, 0.9, 0.75)
				fl.light_energy = 2.5
				fl.omni_range = 18.0
				fl.position = Vector3(s * 8.0, TUN_H + 3.0, 6.0)
				pn.add_child(fl)
			# Schräge Leitwand vom Gehweg zur Trogmauer: wer außen an der Mauer entlangschrammt, wird in den
			# Trog gelenkt statt frontal gegen die Mauerkante zu prallen (am Ende des Trogs gespiegelt)
			var dr: float = t["r0"] if end == 0 else t["r1"]
			var fr := frame_at(curve, dr)
			var fa := frame_at(curve, dr - 16.0 if end == 0 else dr + 16.0)
			for s in [-1.0, 1.0]:
				var a: Vector3 = fa["pos"] + fa["right"] * s * (HALF_W + WALK + 0.2)
				var b: Vector3 = fr["pos"] + fr["right"] * s * (TUN_W + 0.1)
				_wall_shape(walls, a, b, 3.0)
				var seg := b - a
				seg.y = 0.0
				var jn := Node3D.new()
				jn.transform = Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), (a + b) / 2.0 + Vector3(0, CURB_H, 0))
				root.add_child(jn)
				Builder._add(jn, Builder.tapered_box(Vector2(0.62, seg.length() + 0.4), Vector2(0.24, seg.length() + 0.4), PARAPET, 0.0),
					Builder.mat(Color(0.5, 0.5, 0.5), 0.0, 0.85), Vector3.ZERO)
				Builder._add(jn, Builder.box(Vector3(0.26, 0.06, seg.length())), warn, Vector3(0, PARAPET, 0))
			# Licht im Trog
			var k := 0
			var ur := 24.0
			while ur < DIP_RAMP - 6.0:
				var fl2 := frame_at(curve, (t["r0"] + ur) if end == 0 else (t["r1"] - ur))
				var tl := OmniLight3D.new()
				tl.light_color = col
				tl.light_energy = 1.4
				tl.omni_range = 16.0
				tl.omni_attenuation = 1.0
				tl.position = fl2["pos"] + fl2["right"] * (1.0 if k % 2 == 0 else -1.0) * (TUN_W - 1.4) + Vector3(0, fl2["y"] + 4.5, 0)
				root.add_child(tl)
				k += 1
				ur += 26.0
			if end == 0:
				var l := Label3D.new()
				l.text = t["name"]
				l.font_size = 110
				l.pixel_size = 0.022
				l.modulate = Color(col.r * 2.2, col.g * 2.2, col.b * 2.2)
				l.shaded = false
				l.double_sided = false
				l.position = Vector3(0, TUN_H + 2.7, 0.36)
				pn.add_child(l)

		# Häuserblock oben drauf
		var dist := _district_at(track, d0 + len / 2.0)
		var styles: Array = dist["styles"]
		var tints: Array = dist["tints"]
		var segs := int(ceil(len / 24.0))
		for i in segs:
			var a: float = d0 + len * i / segs
			var b: float = d0 + len * (i + 1) / segs
			var f := frame_at(curve, (a + b) / 2.0)
			var tint: Color = tints[rng.randi() % tints.size()]
			var h := rng.randf_range(20.0, 48.0) if i % 3 == 1 else rng.randf_range(5.0, 22.0)
			_box_building(root, f["pos"], Basis.looking_at(f["fwd"], Vector3.UP), b - a + 1.5, (HALF_W + WALK) * 2.0 + 1.0,
				h, styles[rng.randi() % styles.size()], Vector3(tint.r, tint.g, tint.b), rng.randf() * 100.0, 0.0, dist["lit"],
				maxf(f["y"] + TUN_H, 0.3))


# --- Hochbahn --------------------------------------------------------------------

## Stahlviadukt über Gehweg und Außenspur, mit Stützen, Licht darunter, Station und Zug.
static func _build_el(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	if track["el"].is_empty():
		return
	var curve: Curve3D = track["curve"]
	var steel := Builder.mat(Color(0.17, 0.23, 0.2), 0.6, 0.45)
	steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rib_m := Builder.mat(Color(0.12, 0.15, 0.13), 0.6, 0.5)
	var trim_m := Builder.mat(Color(1.0, 0.55, 0.2), 0.0, 0.4, Color(1.0, 0.5, 0.15), 3.5)
	var roof_m := Builder.mat(Color(0.2, 0.22, 0.24), 0.5, 0.5)
	var light_m := Builder.mat(Color(1, 0.75, 0.45), 0.0, 0.3, Color(1, 0.7, 0.4), 5.0)
	var sta_m := Builder.mat(Color(0.9, 0.95, 1.0), 0.0, 0.3, Color(0.85, 0.95, 1.0), 5.0)
	for e in track["el"]:
		var side: float = e["side"]
		var a_lat := side * (HALF_W - 3.2)  # Innenkante über der Außenspur
		var b_lat := side * (HALF_W + WALK - 0.4)
		var mid_lat := (a_lat + b_lat) / 2.0
		var width := absf(b_lat - a_lat)
		var d0: float = e["from"]
		var len: float = e["to"] - d0

		# Trog: Unterseite, Seitenträger, Oberseite
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := int(ceil(len / 3.0))
		var prev := {}
		var y0 := Vector3(0, EL_H, 0)
		var y1 := Vector3(0, EL_H + 1.5, 0)
		for i in n + 1:
			var f := frame_at(curve, d0 + len * i / n)
			var cur := {"a": f["pos"] + f["right"] * a_lat, "b": f["pos"] + f["right"] * b_lat}
			if not prev.is_empty():
				_strip(st, prev["a"] + y0, prev["b"] + y0, cur["a"] + y0, cur["b"] + y0, 0.0, 0.0)
				_strip(st, prev["a"] + y1, prev["b"] + y1, cur["a"] + y1, cur["b"] + y1, 0.0, 0.0)
				_strip_v(st, prev["a"] + y0, cur["a"] + y0, 1.5, true)
				_strip_v(st, prev["b"] + y0, cur["b"] + y0, 1.5, false)
				if i % 12 == 0 or i == n:
					_flush(root, st, steel)
					st = SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
			prev = cur

		# Querrippen, Stützen, Lampen
		var ribs := []
		var pillars := []
		var lamps := []
		var trims := []
		var u := 1.0
		while u < len:
			var f := frame_at(curve, d0 + u)
			var b := Basis.looking_at(f["fwd"], Vector3.UP)
			ribs.append(Transform3D(b, f["pos"] + f["right"] * mid_lat + Vector3(0, EL_H - 0.2, 0)))
			trims.append(Transform3D(b, f["pos"] + f["right"] * (a_lat - side * 0.05) + Vector3(0, EL_H + 0.1, 0)))
			if fmod(u, 16.0) < 1.0 and u > 3.0 and u < len - 3.0:
				var base: Vector3 = f["pos"] + f["right"] * side * (HALF_W + 1.0)
				pillars.append(Transform3D(b, base + Vector3(0, EL_H / 2.0, 0)))
				_solid(root, Vector3(0.7, WALL_H, 0.7), Vector3(base.x, WALL_H / 2.0, base.z))
			if fmod(u, 8.0) < 1.0:
				lamps.append(Transform3D(b, f["pos"] + f["right"] * side * (HALF_W - 1.0) + Vector3(0, EL_H - 0.45, 0)))
			if fmod(u, 24.0) < 1.0:
				var light := OmniLight3D.new()
				light.light_color = Color(1.0, 0.72, 0.45)
				light.light_energy = 2.0
				light.omni_range = 14.0
				light.position = f["pos"] + f["right"] * side * (HALF_W - 0.5) + Vector3(0, EL_H - 0.9, 0)
				root.add_child(light)
			u += 4.0

		# Endblöcke: die Bahn verschwindet in Häusern, die über den Gehweg gebaut sind
		for end in 2:
			var d: float = d0 - 7.0 if end == 0 else e["to"] + 7.0
			var f := frame_at(curve, d)
			var lo := HALF_W - 3.8
			var hi := HALF_W + WALK + 9.0
			var dist := _district_at(track, d)
			var tint: Color = dist["tints"][rng.randi() % dist["tints"].size()]
			_box_building(root, f["pos"] + f["right"] * side * (lo + hi) / 2.0, Basis.looking_at(f["fwd"], Vector3.UP), 14.0,
				hi - lo, rng.randf_range(9.0, 16.0), dist["styles"][0], Vector3(tint.r, tint.g, tint.b), rng.randf() * 100.0, 0.0,
				dist["lit"], EL_H - 0.6)
			if not track.has("el_blocks"):
				track["el_blocks"] = []
			track["el_blocks"].append(_foot(f["pos"] + f["right"] * side * (lo + hi) / 2.0, Basis.looking_at(f["fwd"], Vector3.UP), hi - lo, 14.0))
			for k in [-4.5, 4.5]:
				var pf := frame_at(curve, d + k)
				var base: Vector3 = pf["pos"] + pf["right"] * side * (HALF_W + 1.0)
				pillars.append(Transform3D(Basis.looking_at(pf["fwd"], Vector3.UP), base + Vector3(0, (EL_H - 0.6) / 2.0, 0)))
				_solid(root, Vector3(0.7, WALL_H, 0.7), Vector3(base.x, WALL_H / 2.0, base.z))
		_multi(root, Builder.box(Vector3(width + 0.4, 0.4, 0.35)), rib_m, ribs)
		_multi(root, Builder.box(Vector3(0.6, EL_H, 0.6)), rib_m, pillars)
		_multi(root, Builder.box(Vector3(0.5, 0.12, 1.3)), light_m, lamps)
		_multi(root, Builder.box(Vector3(0.12, 0.12, 4.1)), trim_m, trims)

		# Station mit Dach und Schild
		var g := {}
		var s0 := len / 2.0 - 24.0
		u = s0
		while u <= s0 + 48.0:
			var f := frame_at(curve, d0 + u)
			var b := Basis.looking_at(f["fwd"], Vector3.UP)
			_part(g, roof_m, Builder.box(Vector3(width + 1.0, 0.3, 6.2)), Transform3D(b, f["pos"] + f["right"] * mid_lat + Vector3(0, EL_H + 6.3, 0)))
			for lat in [a_lat + side * 0.4, b_lat - side * 0.4]:
				_part(g, rib_m, Builder.box(Vector3(0.25, 4.8, 0.25)), Transform3D(b, f["pos"] + f["right"] * lat + Vector3(0, EL_H + 3.9, 0)))
			_part(g, sta_m, Builder.box(Vector3(0.2, 0.12, 5.6)), Transform3D(b, f["pos"] + f["right"] * (a_lat + side * 0.3) + Vector3(0, EL_H + 6.1, 0)))
			u += 6.0
		_bake(root, g)
		var sf := frame_at(curve, d0 + s0 - 6.0)
		var sn := Node3D.new()
		sn.transform = Transform3D(Basis.looking_at(sf["fwd"], Vector3.UP), sf["pos"] + sf["right"] * side * (HALF_W - 1.4) + Vector3(0, EL_H - 1.0, 0))
		root.add_child(sn)
		Builder._add(sn, Builder.box(Vector3(5.6, 1.1, 0.12)), Builder.mat(Color(0.05, 0.2, 0.6), 0.0, 0.4, Color(0.1, 0.3, 0.9), 1.2), Vector3.ZERO)
		Builder._add(sn, Builder.box(Vector3(0.08, 0.5, 0.08)), rib_m, Vector3(0, 0.75, 0))
		var l := Label3D.new()
		l.text = "HOCHBAHN  " + e["station"]
		l.font_size = 40
		l.pixel_size = 0.016
		l.modulate = Color(2.0, 2.0, 2.0)
		l.shaded = false
		l.double_sided = false
		l.position = Vector3(0, 0, 0.07)
		sn.add_child(l)

		var train := ElevatedRail.new()
		root.add_child(train)
		train.setup(curve, d0 - 10.0, e["to"] + 10.0, [side * (HALF_W - 1.25), side * (HALF_W + 2.65)], EL_H + 1.5, rng.randi())


# --- Viertel-Ausstattung ------------------------------------------------------------

## Pro Viertel: Tor und Laternenketten (Chinatown), Lichterketten (Marktviertel), Schilderbrücken (Downtown,
## Schnellstraße), Lärmschutzwände (Schnellstraße), Brücken (Schnellstraße, Docks).
## Liefert belegte Flächen (Brückenpfeiler, Brückenschneisen) für die Bebauung.
static func _build_structures(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> Array:
	var length: float = track["length"]
	var arr: Array = track["districts"]
	var occupied := []
	var strings := {"lantern": [], "gold": [], "bulb": [], "cable": [], "lights": []}
	for i in arr.size():
		var d0 := i * DISTRICT_LEN
		var d1 := minf(d0 + DISTRICT_LEN, length)
		if d0 >= d1:
			break
		var key: String = arr[i]
		var dist: Dictionary = DISTRICTS[key]
		if dist.has("lanterns"):
			if i == 0 or arr[i - 1] != key:
				for k in 10:
					var gd := d0 + 6.0 + k * 12.0
					if _overhead_free(track, gd, 8.0) and not _near_post(track, gd, 20.0):
						_china_gate(root, track, gd)
						break
			var d := d0 + 12.0
			while d < d1 - 6.0:
				if _overhead_free(track, d, 3.0) and not _near_post(track, d, 5.0):
					_string_lights(track, d, strings, "lantern")
				d += 15.0
		if dist.has("bulbs"):
			var d := d0 + 20.0
			while d < d1 - 10.0:
				if _overhead_free(track, d, 3.0) and not _near_post(track, d, 5.0) and rng.randf() < 0.7:
					_string_lights(track, d, strings, "bulb")
				d += 32.0
		if dist.has("soundwall"):
			_sound_walls(root, track, d0, d1)
		if rng.randf() < dist.get("gantry", 0.0):
			var count := 2 if key == "highway" else 1
			for c in count:
				var target := d0 + DISTRICT_LEN * (c + 0.5) / count
				# zwischen zwei Laternen, damit sich Masten nicht in die Quere kommen
				var gd := 39.0 + roundf((target - 39.0) / LAMP_STEP) * LAMP_STEP
				if _overhead_free(track, gd, 12.0) and not _near_post(track, gd, 25.0):
					_gantry(root, track, gd, rng)
		if rng.randf() < dist.get("overpass", 0.0):
			for off in [0.0, 30.0, -30.0, 60.0, -60.0, 90.0]:
				var od: float = d0 + DISTRICT_LEN * 0.5 + off
				if _overhead_free(track, od, 25.0) and not _near_post(track, od, 18.0) and _main_clear_across(track, od):
					occupied.append_array(_overpass(root, track, od, rng))
					break

	var red_m := Builder.mat(Color(0.9, 0.1, 0.05), 0.0, 0.5, Color(1.0, 0.15, 0.05), 1.8)
	var gold_m := Builder.mat(Color(1.0, 0.7, 0.2), 0.0, 0.5, Color(1.0, 0.6, 0.12), 1.8)
	var bulb_m := Builder.mat(Color(1.0, 0.85, 0.6), 0.0, 0.4, Color(1.0, 0.8, 0.5), 3.0)
	var cable_m := Builder.mat(Color(0.03, 0.03, 0.03), 0.0, 0.8)
	var lantern := SphereMesh.new()
	lantern.radius = 0.42
	lantern.height = 0.84
	lantern.radial_segments = 10
	lantern.rings = 6
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.2
	bulb.radial_segments = 6
	bulb.rings = 3
	_multi(root, lantern, red_m, strings["lantern"])
	_multi(root, lantern, gold_m, strings["gold"])
	_multi(root, bulb, bulb_m, strings["bulb"])
	_multi(root, Builder.box(Vector3(0.04, 0.04, 1.0)), cable_m, strings["cable"])
	for lp in strings["lights"]:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.3, 0.15)
		light.light_energy = 1.3
		light.omni_range = 14.0
		light.position = lp
		root.add_child(light)
	return occupied


## Kein anderer Teil der Hauptstraße quert die Brückenachse (sonst stünde ein Pfeiler mitten auf der Fahrbahn)
static func _main_clear_across(track: Dictionary, d: float) -> bool:
	var f := frame_at(track["curve"], d)
	for s in [-1.0, 1.0]:
		var x := hw(track, d) + WALK + 2.0
		while x < 60.0:
			var p: Vector3 = f["pos"] + f["right"] * s * x
			if _main_clearance(track, p) < WALK + 1.0 or _branch_clearance(track, p) < 2.0 or _in_lake(track, p, 4.0):
				return false
			x += 4.0
	return true


## Leine quer über die Straße mit Lampions (Chinatown) oder Glühbirnen (Marktviertel)
static func _string_lights(track: Dictionary, d: float, strings: Dictionary, kind: String) -> void:
	var f := frame_at(track["curve"], d)
	var r: Vector3 = f["right"]
	var c: Vector3 = f["pos"]
	var span := hw(track, d) + WALK - 0.6
	var lantern := kind == "lantern"
	var top := 9.4 if lantern else 8.0
	var sag := 0.9 if lantern else 0.6
	var pts := []
	for k in 9:
		var x := -span + span * 2.0 * k / 8.0
		pts.append(c + r * x + Vector3(0, top - sag * (1.0 - pow(x / span, 2.0)), 0))
	for k in 8:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var dir := b - a
		strings["cable"].append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, dir.length())), (a + b) / 2.0))
	if lantern:
		for k in range(1, 8):
			var p: Vector3 = pts[k] - Vector3(0, 0.6, 0)
			strings["gold" if k % 3 == 0 else "lantern"].append(Transform3D(Basis.from_scale(Vector3(1, 1.25, 1)), p))
		if int(d / 15.0) % 3 == 0:
			strings["lights"].append(c + Vector3(0, top - sag - 1.2, 0))
	else:
		for k in 8:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			for j in 3:
				strings["bulb"].append(Transform3D(Basis(), a.lerp(b, (j + 0.5) / 3.0) - Vector3(0, 0.15, 0)))


## Chinatown-Tor: rote Säulen, Balken mit Namenstafel, grünes Walmdach in zwei Stufen
static func _china_gate(root: Node3D, track: Dictionary, d: float) -> void:
	var f := frame_at(track["curve"], d)
	var xf := Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"])
	var red := Builder.mat(Color(0.6, 0.04, 0.03), 0.1, 0.5)
	var green := Builder.mat(Color(0.05, 0.26, 0.14), 0.2, 0.5)
	var gold := Builder.mat(Color(0.9, 0.62, 0.18), 0.7, 0.3, Color(1.0, 0.55, 0.1), 0.8)
	var stone := Builder.mat(Color(0.35, 0.34, 0.33), 0.0, 0.9)
	var glow := Builder.mat(Color(0.9, 0.1, 0.05), 0.0, 0.5, Color(1.0, 0.15, 0.05), 1.8)
	var px := hw(track, d) + 1.3
	var g := {}
	for s in [-1.0, 1.0]:
		_part(g, red, Builder.box(Vector3(0.9, 9.4, 0.9)), Transform3D(Basis(), Vector3(s * px, 4.7, 0)))
		_part(g, stone, Builder.box(Vector3(1.5, 0.9, 1.5)), Transform3D(Basis(), Vector3(s * px, 0.45, 0)))
		_part(g, gold, Builder.box(Vector3(1.05, 0.25, 1.05)), Transform3D(Basis(), Vector3(s * px, 6.9, 0)))
		var wp: Vector3 = f["pos"] + f["right"] * s * px
		_solid(root, Vector3(1.2, WALL_H, 1.2), Vector3(wp.x, WALL_H / 2.0, wp.z))
		var lan := SphereMesh.new()
		lan.radius = 0.45
		lan.height = 1.1
		lan.radial_segments = 10
		lan.rings = 6
		_part(g, glow, lan, Transform3D(Basis(), Vector3(s * 4.5, 6.6, 0)))
	_part(g, red, Builder.box(Vector3(px * 2.0 + 2.4, 1.0, 0.8)), Transform3D(Basis(), Vector3(0, 8.7, 0)))
	_part(g, red, Builder.box(Vector3(px * 2.0 + 0.9, 0.45, 0.6)), Transform3D(Basis(), Vector3(0, 7.25, 0)))
	_part(g, gold, Builder.box(Vector3(6.4, 1.2, 0.9)), Transform3D(Basis(), Vector3(0, 7.95, 0)))
	_part(g, gold, Builder.box(Vector3(px * 2.0 + 1.0, 0.2, 0.3)), Transform3D(Basis(), Vector3(0, 10.75, 0)))
	_part(g, gold, Builder.box(Vector3(4.2, 0.2, 0.3)), Transform3D(Basis(), Vector3(0, 12.1, 0)))
	_bake(root, g, xf)
	for spec in [[Vector2(px * 2.0 + 5.0, 3.4), Vector2(px * 2.0 + 0.6, 0.6), 1.5, 9.2], [Vector2(8.0, 2.6), Vector2(4.0, 0.5), 1.25, 10.85]]:
		var roof := MeshInstance3D.new()
		roof.mesh = Builder.tapered_box(spec[0], spec[1], spec[2], 0.0)
		roof.material_override = green
		roof.transform = xf * Transform3D(Basis(), Vector3(0, spec[3], 0))
		root.add_child(roof)
	for s in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "CHINATOWN"
		l.font_size = 64
		l.pixel_size = 0.014
		l.modulate = Color(2.4, 0.25, 0.1)
		l.outline_size = 0
		l.shaded = false
		l.double_sided = false
		l.transform = xf * Transform3D(Basis(Vector3.UP, 0.0 if s > 0.0 else PI), Vector3(0, 7.95, s * 0.47))
		root.add_child(l)
	track["posts"].append(d)


## Schilderbrücke mit zwei grünen Wegweisern über den Spuren
static func _gantry(root: Node3D, track: Dictionary, d: float, rng: RandomNumberGenerator, texts := [], subs := []) -> void:
	var f := frame_at(track["curve"], d)
	var xf := Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"])
	var steel := Builder.mat(Color(0.45, 0.46, 0.48), 0.8, 0.35)
	var green := Builder.mat(Color(0.02, 0.3, 0.13), 0.1, 0.4, Color(0.02, 0.3, 0.12), 0.5)
	var white := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.4, Color(1, 1, 1), 0.6)
	var lamp := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 0.95, 0.8), 4.0)
	var px := hw(track, d) + 1.0
	var g := {}
	for s in [-1.0, 1.0]:
		_part(g, steel, Builder.box(Vector3(0.45, 8.2, 0.45)), Transform3D(Basis(), Vector3(s * px, 4.1, 0)))
		var wp: Vector3 = f["pos"] + f["right"] * s * px
		_solid(root, Vector3(0.6, WALL_H, 0.6), Vector3(wp.x, WALL_H / 2.0, wp.z))
	for y in [6.0, 7.9]:
		_part(g, steel, Builder.box(Vector3(px * 2.0 + 0.6, 0.3, 0.3)), Transform3D(Basis(), Vector3(0, y, 0)))
	if texts.is_empty():
		texts = GANTRY_SIGNS[rng.randi() % GANTRY_SIGNS.size()]
	var m := median_at(track, d)
	for k in 2:
		var x := (-4.6 - m) if k == 0 else (4.6 + m)
		_part(g, white, Builder.box(Vector3(7.2, 2.5, 0.1)), Transform3D(Basis(), Vector3(x, 6.95, 0.22)))
		_part(g, green, Builder.box(Vector3(7.0, 2.3, 0.1)), Transform3D(Basis(), Vector3(x, 6.95, 0.28)))
		for lx in [-2.0, 2.0]:
			_part(g, lamp, Builder.box(Vector3(0.5, 0.1, 0.3)), Transform3D(Basis(), Vector3(x + lx, 8.3, 0.55)))
		var l := Label3D.new()
		l.text = texts[k]
		l.font_size = 48
		l.pixel_size = 0.02
		l.modulate = Color(1.7, 1.7, 1.7)
		l.shaded = false
		l.double_sided = false
		l.transform = xf * Transform3D(Basis(), Vector3(x, 6.95 if subs.is_empty() else 7.25, 0.35))
		root.add_child(l)
		if not subs.is_empty():
			var sl := Label3D.new()
			sl.text = subs[k]
			sl.font_size = 26
			sl.pixel_size = 0.02
			sl.modulate = Color(1.4, 1.4, 1.2)
			sl.shaded = false
			sl.double_sided = false
			sl.transform = xf * Transform3D(Basis(), Vector3(x, 6.35, 0.35))
			root.add_child(sl)
	_bake(root, g, xf)
	track["posts"].append(d)


## Straßenbrücke quer über die Hauptstraße, mit Laternen und stehenden Autos. Liefert belegte Flächen.
static func _overpass(root: Node3D, track: Dictionary, d: float, rng: RandomNumberGenerator) -> Array:
	var f := frame_at(track["curve"], d)
	var ang := rng.randf_range(-0.3, 0.3)
	var across: Vector3 = (f["right"] as Vector3).rotated(Vector3.UP, ang)
	var xf := Transform3D(Basis.looking_at(across, Vector3.UP), f["pos"])  # lokal Z = quer, X = längs
	var panel := ShaderMaterial.new()
	panel.shader = PANEL_SHADER
	var pole := Builder.mat(Color(0.4, 0.42, 0.45), 0.7, 0.4)
	var lamp_m := Builder.mat(Color(1.0, 0.6, 0.28), 0.0, 0.3, Color(1.0, 0.6, 0.28), 5.0)
	var car_m := Builder.mat(Color(0.12, 0.13, 0.16), 0.6, 0.35)
	var tail := Builder.mat(Color(0.8, 0.0, 0.0), 0.0, 0.3, Color(1.0, 0.05, 0.02), 3.0)
	var head := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 0.97, 0.85), 3.0)
	var span := 110.0
	var y := 8.0
	var g := {}
	_part(g, panel, Builder.box(Vector3(12.0, 1.4, span)), Transform3D(Basis(), Vector3(0, y + 0.7, 0)))
	for s in [-1.0, 1.0]:
		_part(g, panel, Builder.box(Vector3(0.4, 1.0, span)), Transform3D(Basis(), Vector3(s * 5.8, y + 1.9, 0)))
	var occ := []
	var reach := (hw(track, d) + WALK + 2.5) / cos(ang)
	for s in [-1.0, 1.0]:
		for x in [-3.5, 3.5]:
			_part(g, panel, Builder.box(Vector3(1.4, y, 1.4)), Transform3D(Basis(), Vector3(x, y / 2.0, s * reach)))
			occ.append({"pos": xf * Vector3(x, 0, s * reach), "r": 3.0})
		_part(g, panel, Builder.box(Vector3(11.0, 1.0, 1.8)), Transform3D(Basis(), Vector3(0, y - 0.5, s * reach)))
		var z := reach + 8.0
		while z < span / 2.0:
			occ.append({"pos": xf * Vector3(0, 0, s * z), "r": 6.5})
			z += 10.0
	for z in [-24.0, 0.0, 24.0]:
		_part(g, pole, Builder.box(Vector3(0.15, 5.0, 0.15)), Transform3D(Basis(), Vector3(5.5, y + 3.9, z)))
		_part(g, pole, Builder.box(Vector3(1.4, 0.12, 0.12)), Transform3D(Basis(), Vector3(4.9, y + 6.4, z)))
		_part(g, lamp_m, Builder.box(Vector3(0.9, 0.15, 0.4)), Transform3D(Basis(), Vector3(4.4, y + 6.35, z)))
	for k in 4:
		var x := -2.6 if k % 2 == 0 else 2.6
		var z := -30.0 + k * 17.0 + rng.randf_range(-3.0, 3.0)
		var dirz := 1.0 if x < 0.0 else -1.0
		_part(g, car_m, Builder.box(Vector3(1.8, 0.8, 4.2)), Transform3D(Basis(), Vector3(x, y + 1.8, z)))
		_part(g, car_m, Builder.box(Vector3(1.6, 0.6, 2.2)), Transform3D(Basis(), Vector3(x, y + 2.5, z + 0.2 * dirz)))
		_part(g, tail, Builder.box(Vector3(1.5, 0.15, 0.05)), Transform3D(Basis(), Vector3(x, y + 1.95, z + 2.12 * dirz)))
		_part(g, head, Builder.box(Vector3(1.5, 0.12, 0.05)), Transform3D(Basis(), Vector3(x, y + 1.9, z - 2.12 * dirz)))
	_bake(root, g, xf)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.35)
	light.light_energy = 1.1
	light.omni_range = 13.0
	light.position = f["pos"] + Vector3(0, y - 1.2, 0)
	root.add_child(light)
	return occ


## Lärmschutzwand mit Graffiti am Rand der Schnellstraße (in 60-m-Stücken)
static func _sound_walls(root: Node3D, track: Dictionary, d0: float, d1: float) -> void:
	var curve: Curve3D = track["curve"]
	var pm := ShaderMaterial.new()
	pm.shader = PANEL_SHADER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	var d := d0
	while d < d1:
		var e := minf(d + 3.0, d1)
		if tunnel_at(track, (d + e) / 2.0, 2.0).is_empty():
			var fa := frame_at(curve, d)
			var fb := frame_at(curve, e)
			for s in [-1.0, 1.0]:
				var a: Vector3 = fa["pos"] + fa["right"] * s * (hw(track, d) + WALK + 0.35)
				var b: Vector3 = fb["pos"] + fb["right"] * s * (hw(track, e) + WALK + 0.35)
				var m := (a + b) / 2.0
				if _branch_clearance(track, m) > 1.0 and _rail_clearance(track, m) > 2.0 and not _in_lake(track, m, 2.0):
					_wall_uv(st, a, b, 4.5, d, e, s < 0.0)
					quads += 1
		d = e
		if quads >= 40 or (d >= d1 and quads > 0):
			_flush(root, st, pm)
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			quads = 0


# --- Stadion, Kräne, Feuertreppen --------------------------------------------------

## Stadion mit LED-Bändern, Flutlichtmasten und Parkplatz. n: lokales -Z zeigt zur Straße.
static func _stadium(n: Node3D, front: float, rng: RandomNumberGenerator) -> void:
	var concrete := Builder.mat(Color(0.15, 0.15, 0.17), 0.2, 0.7)
	var white := Builder.mat(Color(0.7, 0.72, 0.75), 0.3, 0.5)
	var led := Builder.mat(Color(0.1, 0.8, 1.0), 0.0, 0.4, Color(0.1, 0.7, 1.0), 4.0)
	var led2 := Builder.mat(Color(1.0, 0.1, 0.6), 0.0, 0.4, Color(1.0, 0.1, 0.55), 3.5)
	var flood := Builder.mat(Color(1, 1, 1), 0.0, 0.3, Color(0.95, 0.97, 1.0), 9.0)
	var steel := Builder.mat(Color(0.35, 0.36, 0.38), 0.7, 0.4)
	var asphalt := Builder.mat(Color(0.05, 0.05, 0.055), 0.2, 0.35)
	var line := Builder.mat(Color(0.8, 0.8, 0.8), 0.0, 0.6)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 50.0
	bowl.bottom_radius = 45.0
	bowl.height = 18.0
	bowl.radial_segments = 40
	Builder._add(n, bowl, concrete, Vector3(0, 9, 0))
	for spec in [[49.9, 50.3, 16.6, led], [47.0, 47.2, 6.0, led2]]:
		var band := CylinderMesh.new()
		band.bottom_radius = spec[0]
		band.top_radius = spec[1]
		band.height = 1.0
		band.radial_segments = 40
		Builder._add(n, band, spec[3], Vector3(0, spec[2], 0))
	var roof := TorusMesh.new()
	roof.inner_radius = 42.0
	roof.outer_radius = 53.0
	roof.rings = 40
	roof.ring_segments = 6
	Builder._add(n, roof, white, Vector3(0, 19.5, 0)).scale = Vector3(1, 0.18, 1)
	var g := {}
	for k in 32:
		var a := TAU * k / 32.0
		var p := Vector3(sin(a), 0, cos(a))
		_part(g, white, Builder.box(Vector3(0.6, 18.8, 0.6)), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.27), p * 47.9 + Vector3(0, 9.2, 0)))
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := Vector3(sin(a), 0, cos(a)) * 57.0
		_part(g, steel, Builder.box(Vector3(1.2, 44.0, 1.2)), Transform3D(Basis(), p + Vector3(0, 22.0, 0)))
		_part(g, flood, Builder.box(Vector3(8.0, 4.5, 0.6)), Transform3D(Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.45), p + Vector3(0, 45.0, 0)))
	# Parkplatz zwischen Straße und Stadion
	var pz := -(front + 50.0) / 2.0
	var depth := front - 50.0
	_part(g, asphalt, Builder.box(Vector3(100.0, 0.06, depth)), Transform3D(Basis(), Vector3(0, 0.03, pz)))
	var car_cols := [Builder.mat(Color(0.6, 0.05, 0.05), 0.5, 0.35), Builder.mat(Color(0.75, 0.77, 0.8), 0.6, 0.3),
		Builder.mat(Color(0.05, 0.1, 0.35), 0.5, 0.35), Builder.mat(Color(0.08, 0.08, 0.09), 0.5, 0.35)]
	for row in [-1.0, 1.0]:
		var rz: float = pz + row * depth * 0.22
		var x := -46.0
		while x < 46.0:
			_part(g, line, Builder.box(Vector3(0.12, 0.02, 5.0)), Transform3D(Basis(), Vector3(x, 0.07, rz)))
			if rng.randf() < 0.45:
				var cm: Material = car_cols[rng.randi() % car_cols.size()]
				_part(g, cm, Builder.box(Vector3(1.8, 0.8, 4.2)), Transform3D(Basis(), Vector3(x + 1.5, 0.75, rz)))
				_part(g, cm, Builder.box(Vector3(1.6, 0.55, 2.1)), Transform3D(Basis(), Vector3(x + 1.5, 1.4, rz + 0.2)))
			x += 3.0
	for x in [-35.0, 0.0, 35.0]:
		_part(g, steel, Builder.box(Vector3(0.3, 10.0, 0.3)), Transform3D(Basis(), Vector3(x, 5.0, pz)))
		_part(g, flood, Builder.box(Vector3(1.6, 0.2, 0.8)), Transform3D(Basis(), Vector3(x, 10.0, pz)))
		var pl := OmniLight3D.new()
		pl.light_color = Color(0.9, 0.95, 1.0)
		pl.light_energy = 1.8
		pl.omni_range = 24.0
		pl.position = Vector3(x, 9.0, pz)
		n.add_child(pl)
	_bake(n, g)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.85, 0.92, 1.0)
	glow.light_energy = 1.2
	glow.omni_range = 95.0
	glow.position = Vector3(0, 32.0, 0)
	n.add_child(glow)
	_label(n, "STADION", Color(0.5, 0.9, 1.0), 220, Vector3(0, 11.5, -48.8), 3.0)
	var crowd := AmbientSound.new()
	crowd.sound = "crowd"
	crowd.radius = 260.0
	crowd.base_db = -9.0
	n.add_child(crowd)


## Containerkran der Docks; der Ausleger ragt hoch über die Straße. -Z der Basis zeigt zur Straße.
static func _crane(root: Node3D, center: Vector3, face_dir: Vector3, rng: RandomNumberGenerator) -> void:
	var xf := Transform3D(Basis.looking_at(face_dir, Vector3.UP), center)
	var cols := [Color(0.75, 0.12, 0.06), Color(0.85, 0.6, 0.05), Color(0.1, 0.3, 0.6)]
	var paint := Builder.mat(cols[rng.randi() % cols.size()], 0.5, 0.45)
	var dark := Builder.mat(Color(0.12, 0.12, 0.13), 0.5, 0.5)
	var box_c := Builder.mat(Color(0.1, 0.35, 0.2) if rng.randf() < 0.5 else Color(0.6, 0.3, 0.05), 0.4, 0.6)
	var g := {}
	for x in [-6.0, 6.0]:
		for z in [-7.0, 7.0]:
			_part(g, paint, Builder.box(Vector3(1.0, 27.0, 1.0)), Transform3D(Basis(), Vector3(x, 13.5, z)))
		_part(g, paint, Builder.box(Vector3(1.2, 1.2, 15.0)), Transform3D(Basis(), Vector3(x, 26.5, 0)))
		_part(g, paint, Builder.box(Vector3(0.8, 14.0, 0.8)), Transform3D(Basis(), Vector3(x * 0.6, 34.0, 5.0)))
	for z in [-7.0, 7.0]:
		_part(g, paint, Builder.box(Vector3(13.0, 1.2, 1.2)), Transform3D(Basis(), Vector3(0, 26.5, z)))
		_part(g, paint, Builder.box(Vector3(13.0, 0.8, 0.8)), Transform3D(Basis(), Vector3(0, 8.0, z)))
	_part(g, paint, Builder.box(Vector3(2.2, 1.8, 66.0)), Transform3D(Basis(), Vector3(0, 30.0, -9.0)))
	_part(g, dark, Builder.box(Vector3(5.0, 3.5, 6.0)), Transform3D(Basis(), Vector3(0, 32.6, 2.0)))
	# Abspannseile von der Spitze zum Ausleger
	for tz in [-40.0, 22.0]:
		var a := Vector3(0, 41.0, 5.0)
		var b := Vector3(0, 30.9, tz)
		var dir := b - a
		_part(g, dark, Builder.box(Vector3(0.15, 0.15, 1.0)), Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis.from_scale(Vector3(1, 1, dir.length())), (a + b) / 2.0))
	# Container am Haken über dem Gehweg
	var hz := -22.0
	_part(g, dark, Builder.box(Vector3(0.08, 8.0, 0.08)), Transform3D(Basis(), Vector3(-0.8, 25.0, hz)))
	_part(g, dark, Builder.box(Vector3(0.08, 8.0, 0.08)), Transform3D(Basis(), Vector3(0.8, 25.0, hz)))
	_part(g, box_c, Builder.box(Vector3(2.5, 2.6, 6.1)), Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 19.7, hz)))
	_bake(root, g, xf)
	var bm := ShaderMaterial.new()
	bm.shader = BLINK_SHADER
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	for p in [Vector3(0, 31.2, -41.5), Vector3(0, 41.3, 5.0)]:
		Builder._add(root, sm, bm, xf * p)


## Feuertreppe an einer Backsteinfassade (ein Mesh). fb: +Z zeigt zur Straße.
static func _fire_escape(root: Node3D, pos: Vector3, fb: Basis, floors: int) -> void:
	var iron := Builder.mat(Color(0.07, 0.07, 0.08), 0.7, 0.5)
	var g := {}
	for k in floors:
		var y := 4.0 + k * 3.2
		_part(g, iron, Builder.box(Vector3(3.4, 0.08, 1.2)), Transform3D(Basis(), Vector3(0, y, 0.6)))
		for ry in [0.45, 0.95]:
			_part(g, iron, Builder.box(Vector3(3.4, 0.05, 0.05)), Transform3D(Basis(), Vector3(0, y + ry, 1.18)))
		for x in [-1.7, 1.7]:
			_part(g, iron, Builder.box(Vector3(0.05, 0.95, 1.2)), Transform3D(Basis(), Vector3(x, y + 0.48, 0.6)))
		if k < floors - 1:
			var s := 1.0 if k % 2 == 0 else -1.0
			_part(g, iron, Builder.box(Vector3(4.4, 0.08, 0.6)), Transform3D(Basis(Vector3.BACK, s * 0.82), Vector3(0, y + 1.6, 0.35)))
	_part(g, iron, Builder.box(Vector3(0.5, 2.6, 0.06)), Transform3D(Basis(), Vector3(1.2, 2.8, 1.15)))
	_bake(root, g, Transform3D(fb, pos))
