extends RefCounted
## Alle Inhalte des Spiels: Autos, Tuningteile und Events.
## Autos: "unlock" = {"race": n} Rennsiege und/oder {"drift": n} Driftsiege (eins von beiden reicht).
## Teile: "wins" = so viele Siege insgesamt (Rennen + Drift).
## "drift" (0..1): wie willig das Auto quer geht und im Drift bleibt.

const CARS := {
	"kaizen": {
		"name": "Kaizen Rally S", "style": "hatch", "unlock": {}, "drift": 0.35,
		"length": 4.25, "width": 1.74,
		"accel": 9.5, "top_speed": 58.0, "grip": 26.0, "steer": 2.3,
		"desc": "Kompakter Keil-Sportler. Leicht, wendig, verzeiht viel.",
		# Hochdrehender Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.45, 0.2, 0.08], "sub": 0.3, "turbo": 0.0, "rough": 0.2},
	},
	"mirai": {
		"name": "Mirai 240R", "style": "coupe", "unlock": {"race": 2, "drift": 1}, "drift": 0.65,
		"length": 4.35, "width": 1.82,
		"accel": 11.0, "top_speed": 66.0, "grip": 22.0, "steer": 2.2,
		"desc": "Heckantrieb-Coupé. Liebt Drifts.",
		# Bollernder Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.6, 0.3, 0.1], "sub": 0.55, "turbo": 0.7, "rough": 0.35},
	},
	"vortex": {
		"name": "Vortex GT-R", "style": "sedan", "unlock": {"race": 5}, "drift": 0.3,
		"length": 4.6, "width": 1.8,
		"accel": 12.5, "top_speed": 74.0, "grip": 28.0, "steer": 2.05,
		"desc": "Turbo-Limousine. Brutal auf der Geraden.",
		# Seidiger Reihensechser mit großem Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.12, "turbo": 1.0, "rough": 0.12},
	},
	"sakura": {
		"name": "Sakura D2", "style": "hatch", "unlock": {"drift": 1}, "drift": 0.9,
		"length": 4.3, "width": 1.72,
		"accel": 10.2, "top_speed": 60.0, "grip": 21.0, "steer": 2.5,
		"desc": "Leichter Hecktriebler. Gebaut zum Querfahren.",
		# Kurzhubiger Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.55, 0.28, 0.12], "sub": 0.4, "turbo": 0.5, "rough": 0.28},
	},
	"ronin": {
		"name": "Ronin DR", "style": "coupe", "unlock": {"drift": 3}, "drift": 1.0,
		"length": 4.3, "width": 1.78,
		"accel": 12.2, "top_speed": 69.0, "grip": 20.0, "steer": 2.45,
		"desc": "Drift-Monster mit V8-Swap. Steht quer, wann immer du willst.",
		# Tiefer, grollender V8
		"sound": {"cyl": 8, "harm": [1.0, 0.7, 0.35, 0.15], "sub": 0.6, "turbo": 0.0, "rough": 0.4},
	},
	"hachi": {
		"name": "Hachi Touge", "style": "hatch", "unlock": {"race": 1, "drift": 1}, "drift": 0.85,
		"length": 4.2, "width": 1.66,
		"accel": 9.0, "top_speed": 56.0, "grip": 22.0, "steer": 2.6,
		"desc": "Leichtes 80er-Fließheck mit Heckantrieb. Wenig Leistung, viel Gefühl.",
		# Kleiner, drehfreudiger Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.5, 0.26, 0.12], "sub": 0.22, "turbo": 0.0, "rough": 0.3},
	},
	"tsubame": {
		"name": "Tsubame Spyder", "style": "roadster", "unlock": {"race": 3}, "drift": 0.6,
		"length": 4.1, "width": 1.75,
		"accel": 10.6, "top_speed": 62.0, "grip": 25.0, "steer": 2.55,
		"desc": "Offener Zweisitzer mit langer Haube. Flink und präzise.",
		# Kreischender Hochdrehzahl-Sauger
		"sound": {"cyl": 4, "harm": [1.0, 0.38, 0.3, 0.16], "sub": 0.12, "turbo": 0.0, "rough": 0.12},
	},
	"raijin": {
		"name": "Raijin RS-4", "style": "sedan", "unlock": {"race": 7}, "drift": 0.25,
		"length": 4.45, "width": 1.8,
		"accel": 12.6, "top_speed": 70.0, "grip": 29.0, "steer": 2.15,
		"desc": "Rallye-Limousine mit Allrad-Gefühl. Klebt auf der Straße.",
		# Rauer Turbo-Vierzylinder mit Ladedruck-Zischen
		"sound": {"cyl": 4, "harm": [1.0, 0.65, 0.4, 0.2], "sub": 0.6, "turbo": 0.9, "rough": 0.5},
	},
	"kaze": {
		"name": "Kaze TT", "style": "coupe", "unlock": {"race": 9, "drift": 4}, "drift": 0.55,
		"length": 4.5, "width": 1.81,
		"accel": 12.8, "top_speed": 76.0, "grip": 25.0, "steer": 2.1,
		"desc": "Langes Biturbo-Coupé mit Bügelflügel. Das schnellste Auto der Stadt.",
		# Reihensechser mit zwei Turbos
		"sound": {"cyl": 6, "harm": [1.0, 0.55, 0.32, 0.14], "sub": 0.2, "turbo": 1.0, "rough": 0.15},
	},
}

const CAR_ORDER := ["kaizen", "hachi", "mirai", "sakura", "tsubame", "vortex", "raijin", "ronin", "kaze"]

## Jede Kategorie: Liste von Optionen {name, wins, ...}.
const PARTS := {
	"paint": {
		"label": "Lack",
		"options": [
			{"name": "Silber", "wins": 0, "color": Color(0.75, 0.77, 0.8)},
			{"name": "Schwarz", "wins": 0, "color": Color(0.05, 0.05, 0.06)},
			{"name": "Rot", "wins": 0, "color": Color(0.75, 0.05, 0.05)},
			{"name": "Gelb", "wins": 1, "color": Color(0.95, 0.75, 0.05)},
			{"name": "Giftgrün", "wins": 2, "color": Color(0.35, 0.9, 0.1)},
			{"name": "Bonbonblau", "wins": 3, "color": Color(0.05, 0.2, 0.9)},
			{"name": "Neonpink", "wins": 4, "color": Color(0.95, 0.1, 0.6)},
		],
	},
	"rims": {
		"label": "Felgen",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(0.5, 0.5, 0.52), "radius": 0.2, "spokes": 0},
			{"name": "Fünfspeichen", "wins": 1, "color": Color(0.85, 0.85, 0.9), "radius": 0.25, "spokes": 5},
			{"name": "Gitter Gold", "wins": 2, "color": Color(0.85, 0.65, 0.2), "radius": 0.26, "spokes": 10},
			{"name": "Tiefbett Schwarz", "wins": 4, "color": Color(0.08, 0.08, 0.08), "radius": 0.28, "spokes": 6},
		],
	},
	"spoiler": {
		"label": "Spoiler",
		"options": [
			{"name": "Keiner", "wins": 0},
			{"name": "Lippe", "wins": 1},
			{"name": "GT-Flügel", "wins": 3},
			{"name": "Scheunentor", "wins": 5},
		],
	},
	"bodykit": {
		"label": "Bodykit",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Seitenschweller", "wins": 2},
			{"name": "Breitbau", "wins": 4},
		],
	},
	"vinyl": {
		"label": "Folierung",
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
## type: "sprint" (A nach B), "circuit" (Rundkurs, laps Runden), "drift" (Rundkurs allein, Punkte fürs Querfahren),
## "drag" (gerade, Spurwechsel und Handschaltung).
## tier: Schwierigkeit 1..3. bulges: Segment-Index -> "alley" (kurvige Gasse), "lake" (Seesprung),
## "fork" (echte Gabelung: kurz mit Gegenverkehr oder breiter Boulevard außen herum).
## districts: Gewichte der Stadtviertel. Rundkurse: corners = Eckpunkte, radius = ungefähre Größe.
const RACES := [
	{"name": "Bankenviertel-Sprint", "type": "sprint", "tier": 1, "seed": 11, "segments": 18, "max_turn": 50.0,
		"bulges": {4: "alley", 11: "lake"},
		"districts": {"downtown": 0.35, "chinatown": 0.25, "shops": 0.25, "residential": 0.15}},
	{"name": "Feierabendverkehr", "type": "sprint", "tier": 1, "seed": 23, "segments": 20, "max_turn": 40.0,
		"bulges": {5: "fork", 13: "fork"},
		"districts": {"boulevard": 0.45, "downtown": 0.25, "shops": 0.3}},
	{"name": "Hafenrunde", "type": "sprint", "tier": 2, "seed": 42, "segments": 24, "max_turn": 65.0,
		"bulges": {5: "lake", 13: "fork", 19: "alley"},
		"districts": {"industrial": 0.45, "chinatown": 0.15, "shops": 0.2, "residential": 0.2}},
	{"name": "Chinatown-Express", "type": "sprint", "tier": 2, "seed": 5, "segments": 22, "max_turn": 60.0,
		"bulges": {4: "fork", 10: "alley", 17: "fork"},
		"districts": {"chinatown": 0.5, "shops": 0.25, "boulevard": 0.25}},
	{"name": "Schnellstraßen-Raserei", "type": "sprint", "tier": 3, "seed": 7, "segments": 30, "max_turn": 30.0,
		"bulges": {7: "alley", 17: "lake", 24: "fork"},
		"districts": {"highway": 0.4, "downtown": 0.2, "industrial": 0.2, "boulevard": 0.2}},
	{"name": "Innenstadtring", "type": "circuit", "tier": 1, "laps": 2, "seed": 101, "corners": 9, "radius": 260.0,
		"bulges": {3: "alley"},
		"districts": {"downtown": 0.4, "boulevard": 0.3, "shops": 0.3}},
	{"name": "Hafenring", "type": "circuit", "tier": 2, "laps": 2, "seed": 202, "corners": 10, "radius": 300.0,
		"bulges": {2: "fork", 6: "lake"},
		"districts": {"industrial": 0.5, "highway": 0.25, "chinatown": 0.25}},
	{"name": "Nachtschicht", "type": "circuit", "tier": 3, "laps": 2, "seed": 303, "corners": 11, "radius": 360.0,
		"bulges": {2: "fork", 7: "alley"},
		"districts": {"highway": 0.3, "boulevard": 0.3, "downtown": 0.4}},
	{"name": "Chinatown-Drift", "type": "drift", "tier": 1, "laps": 2, "seed": 401, "corners": 12, "radius": 140.0,
		"bulges": {},
		"districts": {"chinatown": 0.7, "shops": 0.3}},
	{"name": "Hafen-Drift", "type": "drift", "tier": 2, "laps": 2, "seed": 502, "corners": 12, "radius": 155.0,
		"bulges": {},
		"districts": {"industrial": 0.7, "highway": 0.3}},
	{"name": "Stadion-Drift", "type": "drift", "tier": 3, "laps": 2, "seed": 603, "corners": 14, "radius": 175.0,
		"bulges": {}, "stadium": true,
		"districts": {"downtown": 0.4, "boulevard": 0.6}},
	# --- neu: Drag-Rennen (geradeaus, Handschaltung) und weitere Strecken; hinten angehängt, damit gespeicherte
	# Event-Nummern gültig bleiben
	{"name": "Hafenmeile", "type": "drag", "tier": 1, "seed": 701, "segments": 8, "max_turn": 4.0,
		"districts": {"industrial": 0.6, "shops": 0.4}},
	{"name": "Neon-Gerade", "type": "drag", "tier": 2, "seed": 702, "segments": 10, "max_turn": 6.0,
		"districts": {"downtown": 0.5, "chinatown": 0.5}},
	{"name": "Viertelmeile ohne Tempolimit", "type": "drag", "tier": 3, "seed": 703, "segments": 13, "max_turn": 5.0,
		"districts": {"highway": 0.6, "boulevard": 0.4}},
	{"name": "Altstadt-Hügel", "type": "sprint", "tier": 2, "seed": 61, "segments": 22, "max_turn": 55.0,
		"bulges": {4: "fork", 11: "fork", 17: "alley"},
		"districts": {"residential": 0.45, "shops": 0.3, "chinatown": 0.25}},
	{"name": "Hafen-Sprint", "type": "sprint", "tier": 3, "seed": 77, "segments": 26, "max_turn": 70.0,
		"bulges": {5: "lake", 12: "alley", 19: "fork"},
		"districts": {"industrial": 0.5, "highway": 0.3, "residential": 0.2}},
	{"name": "Chinatown-Runde", "type": "circuit", "tier": 1, "laps": 3, "seed": 121, "corners": 8, "radius": 220.0,
		"bulges": {3: "fork"},
		"districts": {"chinatown": 0.6, "shops": 0.4}},
	{"name": "Altstadtring", "type": "circuit", "tier": 2, "laps": 2, "seed": 131, "corners": 10, "radius": 290.0,
		"bulges": {2: "fork", 6: "alley"},
		"districts": {"residential": 0.5, "boulevard": 0.3, "downtown": 0.2}},
	# --- Orts-Strecken: echte Straßenverläufe (OpenStreetMap, tools/osm_city.py), Wahrzeichen an ihrem Platz.
	# city = Schlüssel in city_data.gd, town = Ortsschild, shops = Ladennamen der Stadt, station = Haltestelle am Bahnübergang
	{"name": "Aachen Grabenring", "type": "circuit", "tier": 2, "laps": 2, "seed": 801, "city": "aachen", "town": "Aachen",
		"shops": ["PRINTEN", "ÖCHER BRAUHAUS", "CAMPUS BAR", "DOMCAFÉ", "PONTSTRASSE", "THERMALBAD", "MENSA", "KAISERCAFÉ"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "campus_de": 0.2},
		"desc": "Über den Grabenring am SuperC der RWTH, am Elisenbrunnen und am Theater vorbei. In der Mitte Dom und Rathaus."},
	{"name": "Würzburg Mainufer", "type": "sprint", "tier": 3, "seed": 802, "city": "wuerzburg", "town": "Würzburg",
		"shops": ["BOCKSBEUTEL", "FRANKENWEIN", "BRÜCKENSCHOPPEN", "WEINHAUS", "KILIANI", "MAINFRANKEN", "SCHOPPEN"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "vorstadt_de": 0.2},
		"desc": "Rennweg an der Residenz, über die Ludwigsbrücke, unter der Festung Marienberg entlang, über die Friedensbrücke zum Alten Kranen."},
	{"name": "Bad Kissingen Kurmeile", "type": "sprint", "tier": 1, "seed": 803, "city": "badkissingen", "town": "Bad Kissingen",
		"shops": ["KURCAFÉ", "KURAPOTHEKE", "RAKOCZY", "TRINKHALLE", "KONZERTCAFÉ", "KURHAUS", "SALINE"],
		"districts": {"kurviertel_de": 0.55, "innenstadt_de": 0.2, "vorstadt_de": 0.25},
		"desc": "Vom Regentenbau am Kurgarten über die Saale, dann am Fluss entlang zum Gradierbau der Oberen Saline."},
	{"name": "Tauberbischofsheim Altstadt", "type": "circuit", "tier": 1, "laps": 3, "seed": 804, "city": "tbb", "town": "Tauberbischofsheim",
		"shops": ["FECHTCLUB", "TAUBERWEIN", "FECHTERSTADT", "TAUBERTAL", "LIOBA CAFÉ", "SCHLOSSCAFÉ"],
		"districts": {"altstadt_de": 0.6, "vorstadt_de": 0.4},
		"desc": "Rund um die Altstadt der Fechterstadt, Türmersturm, Rathaus und St. Martin immer im Blick."},
	{"name": "Hammelburg Saaleck", "type": "sprint", "tier": 2, "seed": 805, "city": "hammelburg", "town": "Hammelburg",
		"station": "HAMMELBURG",
		"shops": ["WEINSTADT", "HÄCKERWIRTSCHAFT", "SAALETAL", "WEINFEST", "WINZERSTUBE", "STADTSCHÄNKE"],
		"districts": {"altstadt_de": 0.5, "vorstadt_de": 0.5},
		"desc": "Über die Bahnlinie in die Altstadt, am Rathaus mit Marktbrunnen vorbei, über die Saale hinauf zu Schloss Saaleck."},
]

const EVENT_TYPES := {
	"sprint": {"label": "Sprint", "desc": "Von A nach B gegen 3 Gegner. Gabelungen und Abkürzungen: du entscheidest. * ohne Verkehr, ** wenig, *** voll."},
	"circuit": {"label": "Rundkurs", "desc": "2 Runden gegen 3 Gegner. Wer die beste Linie findet, gewinnt. * ohne Verkehr, ** wenig, *** voll."},
	"drift": {"label": "Drift", "desc": "Allein auf der Strecke. Querfahren gibt Punkte, Ketten geben Multiplikator, Crash kostet die Kette."},
	"drag": {"label": "Drag", "desc": "Geradeaus gegen 3 Gegner. A/D wechselt die Spur, E/Q schaltet: im grünen Bereich perfekt. Zu lange im Begrenzer: Motorschaden. Crash mit Verkehr: Totalschaden."},
}
const TYPE_ORDER := ["sprint", "circuit", "drag", "drift"]
## Früher englische Eventnamen: Bestzeiten im Spielstand werden beim Laden umgeschrieben
const RENAMED := {
	"Downtown Sprint": "Bankenviertel-Sprint",
	"Boulevard Run": "Feierabendverkehr",
	"Harbor Run": "Hafenrunde",
	"Chinatown Express": "Chinatown-Express",
	"Highway Rush": "Schnellstraßen-Raserei",
	"City Loop": "Innenstadtring",
	"Dock Ring": "Hafenring",
	"Night Ring": "Nachtschicht",
	"Chinatown Drift": "Chinatown-Drift",
	"Dock Drift": "Hafen-Drift",
	"Stadion Drift": "Stadion-Drift",
	"Highway Drag": "Viertelmeile ohne Tempolimit",
	"Altstadt Hills": "Altstadt-Hügel",
	"Docks Sprint": "Hafen-Sprint",
	"Chinatown Loop": "Chinatown-Runde",
	"Altstadt Ring": "Altstadtring",
}
## Orts-Strecken stehen im Menü unter eigener Rubrik (nicht zusätzlich unter Sprint/Rundkurs)
const CITY_EVENTS := {"label": "Städte", "desc": "Echte Straßen aus Aachen, Würzburg, Bad Kissingen, Tauberbischofsheim und Hammelburg, die Wahrzeichen stehen an ihrem Platz. Kartendaten © OpenStreetMap-Mitwirkende."}
