extends RefCounted
## Alle Inhalte des Spiels: Autos, Tuningteile und Rennen.
## "wins" = so viele Siege braucht man, um es freizuschalten.

const CARS := {
	"kaizen": {
		"name": "Kaizen Rally S", "wins": 0,
		"length": 4.0, "width": 1.75, "height": 0.6, "cabin_len": 2.1, "cabin_off": 0.25, "cabin_h": 0.5,
		"accel": 9.5, "top_speed": 58.0, "grip": 26.0, "steer": 2.3,
		"desc": "Kompakter Fronttriebler. Leicht, wendig, verzeiht viel.",
		# Hochdrehender Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.45, 0.2, 0.08], "sub": 0.3, "turbo": 0.0, "rough": 0.2},
	},
	"mirai": {
		"name": "Mirai 240R", "wins": 2,
		"length": 4.45, "width": 1.78, "height": 0.52, "cabin_len": 1.8, "cabin_off": 0.45, "cabin_h": 0.44,
		"accel": 11.0, "top_speed": 66.0, "grip": 22.0, "steer": 2.2,
		"desc": "Heckantrieb-Coupé. Liebt Drifts.",
		# Bollernder Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.6, 0.3, 0.1], "sub": 0.55, "turbo": 0.7, "rough": 0.35},
	},
	"vortex": {
		"name": "Vortex GT-R", "wins": 5,
		"length": 4.6, "width": 1.85, "height": 0.55, "cabin_len": 1.9, "cabin_off": 0.35, "cabin_h": 0.46,
		"accel": 12.5, "top_speed": 74.0, "grip": 28.0, "steer": 2.05,
		"desc": "Allrad-Monster. Brutal auf der Geraden.",
		# Seidiger Reihensechser mit großem Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.12, "turbo": 1.0, "rough": 0.12},
	},
}

const CAR_ORDER := ["kaizen", "mirai", "vortex"]

## Jede Kategorie: Liste von Optionen {name, wins, ...}.
const PARTS := {
	"paint": {
		"label": "Lack",
		"options": [
			{"name": "Silber", "wins": 0, "color": Color(0.75, 0.77, 0.8)},
			{"name": "Schwarz", "wins": 0, "color": Color(0.05, 0.05, 0.06)},
			{"name": "Rot", "wins": 0, "color": Color(0.75, 0.05, 0.05)},
			{"name": "Gelb", "wins": 1, "color": Color(0.95, 0.75, 0.05)},
			{"name": "Toxic Grün", "wins": 2, "color": Color(0.35, 0.9, 0.1)},
			{"name": "Candy Blau", "wins": 3, "color": Color(0.05, 0.2, 0.9)},
			{"name": "Neon Pink", "wins": 4, "color": Color(0.95, 0.1, 0.6)},
		],
	},
	"rims": {
		"label": "Felgen",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(0.5, 0.5, 0.52), "radius": 0.2, "spokes": 0},
			{"name": "Fünfspeichen", "wins": 1, "color": Color(0.85, 0.85, 0.9), "radius": 0.25, "spokes": 5},
			{"name": "Mesh Gold", "wins": 2, "color": Color(0.85, 0.65, 0.2), "radius": 0.26, "spokes": 10},
			{"name": "Deep Dish Schwarz", "wins": 4, "color": Color(0.08, 0.08, 0.08), "radius": 0.28, "spokes": 6},
		],
	},
	"spoiler": {
		"label": "Spoiler",
		"options": [
			{"name": "Keiner", "wins": 0},
			{"name": "Lippe", "wins": 1},
			{"name": "GT-Flügel", "wins": 3},
			{"name": "Monster-Flügel", "wins": 5},
		],
	},
	"bodykit": {
		"label": "Bodykit",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Seitenschweller", "wins": 2},
			{"name": "Widebody", "wins": 4},
		],
	},
	"vinyl": {
		"label": "Vinyl",
		"options": [
			{"name": "Keins", "wins": 0},
			{"name": "Rennstreifen", "wins": 2},
			{"name": "Seitenstreifen", "wins": 3},
		],
	},
	"neon": {
		"label": "Unterbodenneon",
		"options": [
			{"name": "Aus", "wins": 0},
			{"name": "Blau", "wins": 1, "color": Color(0.1, 0.4, 1.0)},
			{"name": "Pink", "wins": 2, "color": Color(1.0, 0.1, 0.7)},
			{"name": "Grün", "wins": 3, "color": Color(0.1, 1.0, 0.3)},
		],
	},
	"engine": {
		"label": "Motor",
		"options": [
			{"name": "Serie", "wins": 0, "accel": 1.0, "top": 1.0},
			{"name": "Stufe 1", "wins": 1, "accel": 1.08, "top": 1.04},
			{"name": "Stufe 2", "wins": 3, "accel": 1.16, "top": 1.08},
			{"name": "Stufe 3", "wins": 6, "accel": 1.25, "top": 1.12},
		],
	},
	"nitro": {
		"label": "Nitro",
		"options": [
			{"name": "Serie", "wins": 0, "power": 1.0, "capacity": 1.0},
			{"name": "Stufe 1", "wins": 2, "power": 1.2, "capacity": 1.25},
			{"name": "Stufe 2", "wins": 5, "power": 1.4, "capacity": 1.5},
		],
	},
}

const PART_ORDER := ["paint", "rims", "spoiler", "bodykit", "vinyl", "neon", "engine", "nitro"]

## Sprintstrecken: werden aus dem Seed prozedural erzeugt.
## bulges: Segment-Index -> Abkürzung ("alley" = kurvige Gasse, "lake" = Seesprung über eine Schanze).
## districts: Gewichte der Stadtviertel entlang der Strecke.
const RACES := [
	{"name": "Downtown Sprint", "wins": 0, "seed": 11, "segments": 18, "max_turn": 50.0,
		"bulges": {4: "alley", 11: "lake"},
		"districts": {"downtown": 0.45, "shops": 0.35, "residential": 0.2}},
	{"name": "Harbor Run", "wins": 1, "seed": 42, "segments": 24, "max_turn": 65.0,
		"bulges": {5: "lake", 13: "alley", 19: "alley"},
		"districts": {"industrial": 0.5, "shops": 0.25, "residential": 0.25}},
	{"name": "Highway Rush", "wins": 3, "seed": 7, "segments": 30, "max_turn": 30.0,
		"bulges": {7: "alley", 17: "lake", 24: "alley"},
		"districts": {"downtown": 0.3, "industrial": 0.3, "residential": 0.4}},
]
