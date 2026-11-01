extends RefCounted
## Alle Inhalte des Spiels: Autos, Tuningteile und Events.
## Autos: "unlock" = {"race": n} Rennsiege und/oder {"drift": n} Driftsiege (eins von beiden reicht).
## Teile: "wins" = so viele Siege insgesamt (Rennen + Drift).
## "drift" (0..1): wie willig das Auto quer geht und im Drift bleibt.

const CARS := {
	"kaizen": {
		"name": "Kaizen Rally S", "unlock": {}, "drift": 0.35,
		"length": 4.0, "width": 1.75, "height": 0.6, "cabin_len": 2.1, "cabin_off": 0.25, "cabin_h": 0.5,
		"accel": 9.5, "top_speed": 58.0, "grip": 26.0, "steer": 2.3,
		"desc": "Kompakter Fronttriebler. Leicht, wendig, verzeiht viel.",
		# Hochdrehender Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.45, 0.2, 0.08], "sub": 0.3, "turbo": 0.0, "rough": 0.2},
	},
	"mirai": {
		"name": "Mirai 240R", "unlock": {"race": 2, "drift": 1}, "drift": 0.65,
		"length": 4.45, "width": 1.78, "height": 0.52, "cabin_len": 1.8, "cabin_off": 0.45, "cabin_h": 0.44,
		"accel": 11.0, "top_speed": 66.0, "grip": 22.0, "steer": 2.2,
		"desc": "Heckantrieb-Coupé. Liebt Drifts.",
		# Bollernder Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.6, 0.3, 0.1], "sub": 0.55, "turbo": 0.7, "rough": 0.35},
	},
	"vortex": {
		"name": "Vortex GT-R", "unlock": {"race": 5}, "drift": 0.3,
		"length": 4.6, "width": 1.85, "height": 0.55, "cabin_len": 1.9, "cabin_off": 0.35, "cabin_h": 0.46,
		"accel": 12.5, "top_speed": 74.0, "grip": 28.0, "steer": 2.05,
		"desc": "Allrad-Monster. Brutal auf der Geraden.",
		# Seidiger Reihensechser mit großem Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.12, "turbo": 1.0, "rough": 0.12},
	},
	"sakura": {
		"name": "Sakura D2", "unlock": {"drift": 1}, "drift": 0.9,
		"length": 4.2, "width": 1.7, "height": 0.55, "cabin_len": 1.95, "cabin_off": 0.3, "cabin_h": 0.48,
		"accel": 10.2, "top_speed": 60.0, "grip": 21.0, "steer": 2.5,
		"desc": "Leichter Hecktriebler. Gebaut zum Querfahren.",
		# Kurzhubiger Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.55, 0.28, 0.12], "sub": 0.4, "turbo": 0.5, "rough": 0.28},
	},
	"ronin": {
		"name": "Ronin DR", "unlock": {"drift": 3}, "drift": 1.0,
		"length": 4.6, "width": 1.86, "height": 0.5, "cabin_len": 1.85, "cabin_off": 0.5, "cabin_h": 0.42,
		"accel": 12.2, "top_speed": 69.0, "grip": 20.0, "steer": 2.45,
		"desc": "Drift-Monster mit V8-Swap. Steht quer, wann immer du willst.",
		# Tiefer, grollender V8
		"sound": {"cyl": 8, "harm": [1.0, 0.7, 0.35, 0.15], "sub": 0.6, "turbo": 0.0, "rough": 0.4},
	},
}

const CAR_ORDER := ["kaizen", "mirai", "sakura", "vortex", "ronin"]

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

## Events: werden aus dem Seed prozedural erzeugt. Alle sind von Anfang an fahrbar.
## type: "sprint" (A nach B), "circuit" (Rundkurs, laps Runden), "drift" (Rundkurs allein, Punkte fürs Querfahren).
## tier: Schwierigkeit 1..3. bulges: Segment-Index -> "alley" (kurvige Gasse), "lake" (Seesprung),
## "fork" (echte Gabelung: kurz mit Gegenverkehr oder breiter Boulevard außen herum).
## districts: Gewichte der Stadtviertel. Rundkurse: corners = Eckpunkte, radius = ungefähre Größe.
const RACES := [
	{"name": "Downtown Sprint", "type": "sprint", "tier": 1, "seed": 11, "segments": 18, "max_turn": 50.0,
		"bulges": {4: "alley", 11: "lake"},
		"districts": {"downtown": 0.35, "chinatown": 0.25, "shops": 0.25, "residential": 0.15}},
	{"name": "Boulevard Run", "type": "sprint", "tier": 1, "seed": 23, "segments": 20, "max_turn": 40.0,
		"bulges": {5: "fork", 13: "fork"},
		"districts": {"boulevard": 0.45, "downtown": 0.25, "shops": 0.3}},
	{"name": "Harbor Run", "type": "sprint", "tier": 2, "seed": 42, "segments": 24, "max_turn": 65.0,
		"bulges": {5: "lake", 13: "fork", 19: "alley"},
		"districts": {"industrial": 0.45, "chinatown": 0.15, "shops": 0.2, "residential": 0.2}},
	{"name": "Chinatown Express", "type": "sprint", "tier": 2, "seed": 5, "segments": 22, "max_turn": 60.0,
		"bulges": {4: "fork", 10: "alley", 17: "fork"},
		"districts": {"chinatown": 0.5, "shops": 0.25, "boulevard": 0.25}},
	{"name": "Highway Rush", "type": "sprint", "tier": 3, "seed": 7, "segments": 30, "max_turn": 30.0,
		"bulges": {7: "alley", 17: "lake", 24: "fork"},
		"districts": {"highway": 0.4, "downtown": 0.2, "industrial": 0.2, "boulevard": 0.2}},
	{"name": "City Loop", "type": "circuit", "tier": 1, "laps": 2, "seed": 101, "corners": 9, "radius": 260.0,
		"bulges": {3: "alley"},
		"districts": {"downtown": 0.4, "boulevard": 0.3, "shops": 0.3}},
	{"name": "Dock Ring", "type": "circuit", "tier": 2, "laps": 2, "seed": 202, "corners": 10, "radius": 300.0,
		"bulges": {2: "fork", 6: "lake"},
		"districts": {"industrial": 0.5, "highway": 0.25, "chinatown": 0.25}},
	{"name": "Night Ring", "type": "circuit", "tier": 3, "laps": 2, "seed": 303, "corners": 11, "radius": 360.0,
		"bulges": {2: "fork", 7: "alley"},
		"districts": {"highway": 0.3, "boulevard": 0.3, "downtown": 0.4}},
	{"name": "Chinatown Drift", "type": "drift", "tier": 1, "laps": 2, "seed": 401, "corners": 12, "radius": 140.0,
		"bulges": {},
		"districts": {"chinatown": 0.7, "shops": 0.3}},
	{"name": "Dock Drift", "type": "drift", "tier": 2, "laps": 2, "seed": 502, "corners": 12, "radius": 155.0,
		"bulges": {},
		"districts": {"industrial": 0.7, "highway": 0.3}},
	{"name": "Stadion Drift", "type": "drift", "tier": 3, "laps": 2, "seed": 603, "corners": 14, "radius": 175.0,
		"bulges": {}, "stadium": true,
		"districts": {"downtown": 0.4, "boulevard": 0.6}},
]

const EVENT_TYPES := {
	"sprint": {"label": "Sprint", "desc": "Von A nach B gegen 3 Gegner. Gabelungen und Abkürzungen: du entscheidest."},
	"circuit": {"label": "Rundkurs", "desc": "2 Runden gegen 3 Gegner. Wer die beste Linie findet, gewinnt."},
	"drift": {"label": "Drift", "desc": "Allein auf der Strecke. Querfahren gibt Punkte, Ketten geben Multiplikator, Crash kostet die Kette."},
}
const TYPE_ORDER := ["sprint", "circuit", "drift"]
