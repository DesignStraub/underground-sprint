extends RefCounted
## Alle Inhalte des Spiels: Autos, Tuningteile und Events.
## Autos: "unlock" = {"race": n} Rennsiege und/oder {"drift": n} Driftsiege (eins von beiden reicht).
## Teile: "wins" = so viele Siege insgesamt (Rennen + Drift).
## "drift" (0..1): wie willig das Auto quer geht und im Drift bleibt.

## Leistung: Jedes Auto, das du freischaltest, ist ein Stück stärker (Klasse D bis A). Die letzten fünf (Klasse S) haben
## die gleiche Grundleistung (Leistungsindex ~456) und unterscheiden sich nur im Charakter: Grip, Antritt, Endtempo,
## Lenkung, Drift. "class" steht in der Garage, rating() rechnet den Index aus.
const CARS := {
	"kaizen": {
		"drive": "fwd", "name": "Kaizen Rally S", "style": "hatch", "class": "D", "unlock": {}, "drift": 0.35, "paint": Color(0.92, 0.92, 0.89),
		"length": 4.05, "width": 1.72,
		"accel": 9.5, "top_speed": 58.0, "grip": 26.0, "steer": 2.3,
		"desc": "JDM-Fließheck mit Hochdrehzahl-Motor. Leicht, wendig, verzeiht viel.",
		# Hochdrehender Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.45, 0.2, 0.08], "sub": 0.3, "turbo": 0.0, "rough": 0.2},
	},
	"hachi": {
		"drive": "rwd", "name": "Hachi Touge", "style": "hatch", "class": "D", "unlock": {"race": 1, "drift": 1}, "drift": 0.85,
		"length": 4.2, "width": 1.66,
		"accel": 10.1, "top_speed": 58.0, "grip": 24.0, "steer": 2.6,
		"desc": "Leichtes 80er-Fließheck mit Heckantrieb. Wenig Leistung, viel Gefühl.",
		# Kleiner, drehfreudiger Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.5, 0.26, 0.12], "sub": 0.22, "turbo": 0.0, "rough": 0.3},
	},
	"sakura": {
		"drive": "rwd", "name": "Sakura D2", "style": "coupe", "class": "C", "unlock": {"race": 2, "drift": 1}, "drift": 0.9,
		"length": 4.3, "width": 1.72,
		"accel": 10.5, "top_speed": 60.5, "grip": 23.0, "steer": 2.5,
		"desc": "Leichter Hecktriebler. Gebaut zum Querfahren.",
		# Kurzhubiger Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.55, 0.28, 0.12], "sub": 0.4, "turbo": 0.5, "rough": 0.28},
	},
	"hayate": {
		"drive": "fwd", "name": "Hayate R8", "style": "coupe", "class": "C", "unlock": {"race": 3}, "drift": 0.3, "paint": Color(0.72, 0.04, 0.05),
		"length": 4.38, "width": 1.7,
		"accel": 10.2, "top_speed": 61.5, "grip": 28.0, "steer": 2.45,
		"desc": "Leichtes Coupé, dreht bis 8.000/min. Klebt in Kurven, driftet ungern.",
		# Schreiender Sauger-Vierzylinder mit Nockenwellen-Umschaltung
		"sound": {"cyl": 4, "harm": [1.0, 0.36, 0.34, 0.22], "sub": 0.1, "turbo": 0.0, "rough": 0.1},
	},
	"kitsune": {
		"drive": "rwd", "name": "Kitsune 18S", "style": "hatch", "class": "C", "unlock": {"race": 4, "drift": 1}, "drift": 0.85, "paint": Color(0.95, 0.42, 0.06),
		"length": 4.54, "width": 1.69,
		"accel": 11.2, "top_speed": 62.0, "grip": 23.0, "steer": 2.45,
		"desc": "Fließheck mit Klappscheinwerfern, Turbo und Heckantrieb. Liebling der Drift-Szene.",
		# Turbo-Vierzylinder mit Abblasventil
		"sound": {"cyl": 4, "harm": [1.0, 0.58, 0.3, 0.12], "sub": 0.45, "turbo": 0.8, "rough": 0.3},
	},
	"tsubame": {
		"drive": "rwd", "name": "Tsubame Spyder", "style": "roadster", "class": "B", "unlock": {"race": 5}, "drift": 0.6,
		"length": 4.1, "width": 1.75,
		"accel": 11.0, "top_speed": 64.0, "grip": 27.0, "steer": 2.55,
		"desc": "Offener Zweisitzer mit langer Haube. Flink und präzise.",
		# Kreischender Hochdrehzahl-Sauger
		"sound": {"cyl": 4, "harm": [1.0, 0.38, 0.3, 0.16], "sub": 0.12, "turbo": 0.0, "rough": 0.12},
	},
	"mirai": {
		"drive": "rwd", "name": "Mirai 240R", "style": "coupe", "class": "B", "unlock": {"race": 6, "drift": 2}, "drift": 0.65,
		"length": 4.35, "width": 1.82,
		"accel": 11.4, "top_speed": 66.0, "grip": 23.5, "steer": 2.25,
		"desc": "Heckantrieb-Coupé. Liebt Drifts.",
		# Bollernder Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.6, 0.3, 0.1], "sub": 0.55, "turbo": 0.7, "rough": 0.35},
	},
	"tenshi": {
		"drive": "mr", "name": "Tenshi MR-T", "style": "coupe", "class": "B", "unlock": {"race": 7}, "drift": 0.5, "paint": Color(0.92, 0.7, 0.06),
		"length": 4.17, "width": 1.7,
		"accel": 11.8, "top_speed": 65.0, "grip": 27.5, "steer": 2.6,
		"desc": "Mittelmotor mit Turbo. Lenkt messerscharf ein, will aber sauber gefahren werden.",
		# Turbo-Vierzylinder direkt hinter dir
		"sound": {"cyl": 4, "harm": [1.0, 0.5, 0.32, 0.14], "sub": 0.35, "turbo": 0.85, "rough": 0.25},
	},
	"kumo": {
		"drive": "rwd", "name": "Kumo JX6", "style": "sedan", "class": "A", "unlock": {"race": 8, "drift": 2}, "drift": 0.85, "paint": Color(0.3, 0.32, 0.36),
		"length": 4.72, "width": 1.75,
		"accel": 12.4, "top_speed": 68.0, "grip": 23.5, "steer": 2.3,
		"desc": "Viertürer mit Turbo-Reihensechser und Heckantrieb. Unauffällig, bis er quer steht.",
		# Seidiger Turbo-Reihensechser
		"sound": {"cyl": 6, "harm": [1.0, 0.52, 0.3, 0.14], "sub": 0.18, "turbo": 0.9, "rough": 0.14},
	},
	"raijin": {
		"drive": "awd", "name": "Raijin RS-4", "style": "sedan", "class": "A", "unlock": {"race": 9}, "drift": 0.25,
		"length": 4.45, "width": 1.8,
		"accel": 12.6, "top_speed": 67.0, "grip": 29.5, "steer": 2.2,
		"desc": "Rallye-Limousine mit Allrad-Gefühl. Klebt auf der Straße.",
		# Rauer Turbo-Vierzylinder mit Ladedruck-Zischen
		"sound": {"cyl": 4, "harm": [1.0, 0.65, 0.4, 0.2], "sub": 0.6, "turbo": 0.9, "rough": 0.5},
	},
	"vortex": {
		"drive": "awd", "name": "Vortex GT-R", "style": "sedan", "class": "S", "unlock": {"race": 10}, "drift": 0.3,
		"length": 4.6, "width": 1.8,
		"accel": 12.9, "top_speed": 72.5, "grip": 29.5, "steer": 2.05,
		"desc": "Schwere Turbo-Limousine. Liegt satt, viel Grip, zieht aus jeder Kurve.",
		# Seidiger Reihensechser mit großem Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.12, "turbo": 1.0, "rough": 0.12},
	},
	"ronin": {
		"drive": "rwd", "name": "Ronin DR", "style": "coupe", "class": "S", "unlock": {"race": 11, "drift": 3}, "drift": 1.0,
		"length": 4.3, "width": 1.78,
		"accel": 13.6, "top_speed": 72.0, "grip": 25.0, "steer": 2.5,
		"desc": "Drift-Monster mit V8-Swap. Steht quer, wann immer du willst.",
		# Tiefer, grollender V8
		"sound": {"cyl": 8, "harm": [1.0, 0.7, 0.35, 0.15], "sub": 0.6, "turbo": 0.0, "rough": 0.4},
	},
	"shiden": {
		"drive": "mr", "name": "Shiden NX-1", "style": "coupe", "class": "S", "unlock": {"race": 12}, "drift": 0.45, "paint": Color(0.36, 0.1, 0.56),
		"length": 4.43, "width": 1.81,
		"accel": 13.2, "top_speed": 71.0, "grip": 31.0, "steer": 2.65,
		"desc": "Flacher Mittelmotor-Sportwagen. Die präziseste Lenkung und der meiste Grip im Spiel.",
		# Kreischender V6-Sauger
		"sound": {"cyl": 6, "harm": [1.0, 0.42, 0.36, 0.2], "sub": 0.12, "turbo": 0.0, "rough": 0.1},
	},
	"ryujin": {
		"drive": "rwd", "name": "Ryujin 30Z", "style": "coupe", "class": "S", "unlock": {"race": 13}, "drift": 0.4, "paint": Color(0.04, 0.3, 0.3),
		"length": 4.52, "width": 1.8,
		"accel": 13.2, "top_speed": 73.0, "grip": 25.5, "steer": 2.05,
		"desc": "Breites Biturbo-Coupé. Schiebt brutal an und bleibt bei Höchsttempo ruhig.",
		# V6 mit zwei Turbos
		"sound": {"cyl": 6, "harm": [1.0, 0.62, 0.38, 0.16], "sub": 0.35, "turbo": 1.0, "rough": 0.22},
	},
	"kaze": {
		"drive": "rwd", "name": "Kaze TT", "style": "coupe", "class": "S", "unlock": {"race": 14, "drift": 4}, "drift": 0.55,
		"length": 4.5, "width": 1.81,
		"accel": 12.4, "top_speed": 75.5, "grip": 26.0, "steer": 2.15,
		"desc": "Langes Biturbo-Coupé mit Bügelflügel. Das schnellste Auto der Stadt.",
		# Reihensechser mit zwei Turbos
		"sound": {"cyl": 6, "harm": [1.0, 0.55, 0.32, 0.14], "sub": 0.2, "turbo": 1.0, "rough": 0.15},
	},
}

## Reihenfolge in der Garage = Reihenfolge des Freischaltens
const CAR_ORDER := ["kaizen", "hachi", "sakura", "hayate", "kitsune", "tsubame", "mirai", "tenshi", "kumo", "raijin",
	"vortex", "ronin", "shiden", "ryujin", "kaze"]
## Bis Version 2.10 galten andere Schwellen: wer damit schon ein Auto freigeschaltet hatte, behält es
const LEGACY_UNLOCK := {"hachi": {"race": 1, "drift": 1}, "mirai": {"race": 2, "drift": 1}, "sakura": {"drift": 1},
	"tsubame": {"race": 3}, "vortex": {"race": 5}, "raijin": {"race": 7}, "ronin": {"drift": 3}, "kaze": {"race": 9, "drift": 4}}

## Jede Kategorie: Liste von Optionen {name, wins, ...}. Neue Optionen kommen hinten dazu, damit die Nummern im
## Spielstand gültig bleiben. Optik: die Grundteile sind von Anfang an frei, Besonderes kommt mit Siegen.
const PARTS := {
	# finish: "" glänzend (Klarlack), "matt", "pearl" (Perlmutt), "chrome", "metal" (stark metallisch)
	"paint": {
		"label": "Lack",
		"options": [
			{"name": "Werkslack", "wins": 0, "color": Color(0.75, 0.77, 0.8)},  # je Auto eigen (CARS.paint), sonst Silber
			{"name": "Schwarz", "wins": 0, "color": Color(0.05, 0.05, 0.06)},
			{"name": "Rot", "wins": 0, "color": Color(0.75, 0.05, 0.05)},
			{"name": "Gelb", "wins": 0, "color": Color(0.95, 0.75, 0.05)},
			{"name": "Giftgrün", "wins": 1, "color": Color(0.35, 0.9, 0.1)},
			{"name": "Candyblau", "wins": 2, "color": Color(0.05, 0.2, 0.9), "finish": "metal"},
			{"name": "Neonpink", "wins": 2, "color": Color(0.95, 0.1, 0.6)},
			{"name": "Weiß", "wins": 0, "color": Color(0.9, 0.9, 0.88)},
			{"name": "Silber", "wins": 0, "color": Color(0.72, 0.74, 0.77)},
			{"name": "Orange", "wins": 0, "color": Color(0.95, 0.38, 0.04)},
			{"name": "Blau", "wins": 0, "color": Color(0.07, 0.22, 0.62)},
			{"name": "Dunkelgrün", "wins": 0, "color": Color(0.03, 0.2, 0.1)},
			{"name": "Gunmetal", "wins": 0, "color": Color(0.2, 0.21, 0.23)},
			{"name": "Lila", "wins": 1, "color": Color(0.33, 0.07, 0.55)},
			{"name": "Babyblau", "wins": 1, "color": Color(0.42, 0.68, 0.95)},
			{"name": "Bronze", "wins": 2, "color": Color(0.5, 0.31, 0.13), "finish": "metal"},
			{"name": "Mattschwarz", "wins": 3, "color": Color(0.035, 0.035, 0.04), "finish": "matt"},
			{"name": "Mattgrau", "wins": 3, "color": Color(0.28, 0.29, 0.3), "finish": "matt"},
			{"name": "Perlweiß", "wins": 4, "color": Color(0.93, 0.92, 0.9), "finish": "pearl"},
			{"name": "Gold", "wins": 6, "color": Color(0.85, 0.62, 0.2), "finish": "metal"},
			{"name": "Chrom", "wins": 8, "color": Color(0.85, 0.86, 0.88), "finish": "chrome"},
		],
	},
	# style: Bauart der Felge (car_builder._rim), spokes: Zahl der Speichen, radius: Felgengröße
	"rims": {
		"label": "Felgen",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(0.62, 0.63, 0.66), "radius": 0.22, "spokes": 7, "style": "std"},
			{"name": "Fünfspeichen", "wins": 0, "color": Color(0.85, 0.85, 0.9), "radius": 0.27, "spokes": 5, "style": "std"},
			{"name": "Gitter Gold", "wins": 1, "color": Color(0.85, 0.65, 0.2), "radius": 0.28, "spokes": 10, "style": "mesh"},
			{"name": "Tiefbett Schwarz", "wins": 2, "color": Color(0.08, 0.08, 0.08), "radius": 0.29, "spokes": 6, "style": "dish"},
			{"name": "Doppelspeichen", "wins": 0, "color": Color(0.78, 0.79, 0.82), "radius": 0.27, "spokes": 5, "style": "split"},
			{"name": "Y-Speichen", "wins": 0, "color": Color(0.46, 0.47, 0.5), "radius": 0.28, "spokes": 5, "style": "y"},
			{"name": "Mehrspeichen", "wins": 0, "color": Color(0.8, 0.8, 0.83), "radius": 0.28, "spokes": 16, "style": "thin"},
			{"name": "Stahlfelge", "wins": 0, "color": Color(0.1, 0.1, 0.11), "radius": 0.22, "spokes": 6, "style": "steel"},
			{"name": "Turbine", "wins": 1, "color": Color(0.82, 0.83, 0.86), "radius": 0.27, "spokes": 12, "style": "turbine"},
			{"name": "Rennsport-Sechs", "wins": 2, "color": Color(0.62, 0.42, 0.16), "radius": 0.29, "spokes": 6, "style": "te"},
			{"name": "Kreuzspeichen", "wins": 3, "color": Color(0.85, 0.65, 0.25), "radius": 0.29, "spokes": 8, "style": "cross"},
			{"name": "Aero-Scheibe", "wins": 4, "color": Color(0.9, 0.9, 0.9), "radius": 0.27, "spokes": 5, "style": "aero"},
			{"name": "Tiefbett Stern", "wins": 5, "color": Color(0.85, 0.86, 0.9), "radius": 0.3, "spokes": 5, "style": "dish"},
		],
	},
	# Felgenfarbe: "Passend" behält die Farbe der Felge, "Wagenfarbe" nimmt den Lack
	"rimcol": {
		"label": "Felgenfarbe",
		"options": [
			{"name": "Passend", "wins": 0},
			{"name": "Silber", "wins": 0, "color": Color(0.78, 0.79, 0.82)},
			{"name": "Schwarz", "wins": 0, "color": Color(0.06, 0.06, 0.065)},
			{"name": "Gunmetal", "wins": 0, "color": Color(0.26, 0.27, 0.29)},
			{"name": "Weiß", "wins": 0, "color": Color(0.92, 0.92, 0.9)},
			{"name": "Wagenfarbe", "wins": 0, "paint": true},
			{"name": "Rot", "wins": 0, "color": Color(0.75, 0.05, 0.05)},
			{"name": "Gold", "wins": 1, "color": Color(0.85, 0.65, 0.2)},
			{"name": "Bronze", "wins": 1, "color": Color(0.6, 0.4, 0.16)},
			{"name": "Neongrün", "wins": 2, "color": Color(0.45, 1.0, 0.1)},
			{"name": "Chrom", "wins": 3, "color": Color(0.9, 0.9, 0.92), "chrome": true},
		],
	},
	"spoiler": {
		"label": "Spoiler",
		"options": [
			{"name": "Keiner", "wins": 0},
			{"name": "Lippe", "wins": 0},
			{"name": "GT-Flügel", "wins": 1},
			{"name": "Monster-Flügel", "wins": 5},
			{"name": "Entenbürzel", "wins": 0},
			{"name": "Street-Flügel", "wins": 0},
			{"name": "Schwanenhals", "wins": 2},
			{"name": "Doppeldecker", "wins": 3},
			{"name": "Dachspoiler", "wins": 0},
			{"name": "Bügelflügel", "wins": 1},
		],
	},
	# flare: Kotflügel verbreitert; die Anbauteile baut car_builder._bodykit
	"bodykit": {
		"label": "Bodykit",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Seitenschweller", "wins": 0},
			{"name": "Breitbau", "wins": 3, "flare": true},
			{"name": "Street", "wins": 0},
			{"name": "Rallye", "wins": 1},
			{"name": "Racing", "wins": 2},
			{"name": "Breitbau Racing", "wins": 5, "flare": true},
		],
	},
	"hood": {
		"label": "Motorhaube",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Lufthutze", "wins": 0},
			{"name": "Lamellen", "wins": 0},
			{"name": "NACA-Einlass", "wins": 0},
			{"name": "Doppelhutze", "wins": 1},
			{"name": "Carbon", "wins": 2},
			{"name": "Carbon mit Hutze", "wins": 4},
		],
	},
	"exhaust": {
		"label": "Auspuff",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Sport", "wins": 0},
			{"name": "Doppelrohr", "wins": 0},
			{"name": "Ovalrohr", "wins": 1},
			{"name": "Titan", "wins": 2},
			{"name": "Rennauspuff", "wins": 3},
		],
	},
	"vinyl": {
		"label": "Folierung",
		"options": [
			{"name": "Keins", "wins": 0},
			{"name": "Rennstreifen", "wins": 0},
			{"name": "Seitenstreifen", "wins": 0},
			{"name": "Mittelstreifen", "wins": 0},
			{"name": "Zweifarbig", "wins": 1},
			{"name": "Flankenband", "wins": 0},
			{"name": "Haube und Heck", "wins": 0},
			{"name": "Kontrastdach", "wins": 0},
			{"name": "Rallye", "wins": 2},
		],
	},
	# Folienfarbe: "Kontrast" = Weiß auf dunklem, Schwarz auf hellem Lack
	"vinylcol": {
		"label": "Folienfarbe",
		"options": [
			{"name": "Kontrast", "wins": 0},
			{"name": "Weiß", "wins": 0, "color": Color(0.93, 0.93, 0.92)},
			{"name": "Schwarz", "wins": 0, "color": Color(0.04, 0.04, 0.045)},
			{"name": "Rot", "wins": 0, "color": Color(0.8, 0.05, 0.05)},
			{"name": "Blau", "wins": 0, "color": Color(0.06, 0.25, 0.8)},
			{"name": "Gelb", "wins": 0, "color": Color(0.98, 0.78, 0.05)},
			{"name": "Gold", "wins": 1, "color": Color(0.85, 0.63, 0.2), "metal": true},
			{"name": "Neongrün", "wins": 1, "color": Color(0.45, 1.0, 0.1)},
			{"name": "Pink", "wins": 1, "color": Color(0.98, 0.12, 0.6)},
			{"name": "Carbon", "wins": 2, "color": Color(0.07, 0.07, 0.08), "carbon": true},
		],
	},
	"neon": {
		"label": "Unterbodenneon",
		"options": [
			{"name": "Aus", "wins": 0},
			{"name": "Blau", "wins": 0, "color": Color(0.1, 0.4, 1.0)},
			{"name": "Pink", "wins": 0, "color": Color(1.0, 0.1, 0.7)},
			{"name": "Grün", "wins": 1, "color": Color(0.1, 1.0, 0.3)},
			{"name": "Rot", "wins": 0, "color": Color(1.0, 0.08, 0.05)},
			{"name": "Lila", "wins": 0, "color": Color(0.55, 0.1, 1.0)},
			{"name": "Weiß", "wins": 1, "color": Color(0.85, 0.9, 1.0)},
			{"name": "Orange", "wins": 1, "color": Color(1.0, 0.45, 0.05)},
			{"name": "Türkis", "wins": 2, "color": Color(0.05, 1.0, 0.85)},
		],
	},
	"tint": {
		"label": "Scheiben",
		"options": [
			{"name": "Klar", "wins": 0, "color": Color(0.03, 0.04, 0.06)},
			{"name": "Getönt", "wins": 0, "color": Color(0.012, 0.012, 0.016)},
			{"name": "Dunkel", "wins": 1, "color": Color(0.003, 0.003, 0.004)},
			{"name": "Blau verspiegelt", "wins": 2, "color": Color(0.02, 0.07, 0.2)},
		],
	},
	# Scheinwerfer: Lichtfarbe der Frontlichter und des Lichtkegels
	"lights": {
		"label": "Scheinwerfer",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(1.0, 0.97, 0.88)},
			{"name": "Xenon", "wins": 0, "color": Color(0.82, 0.9, 1.0)},
			{"name": "Gelb", "wins": 0, "color": Color(1.0, 0.82, 0.35)},
			{"name": "Eisblau", "wins": 1, "color": Color(0.55, 0.72, 1.0)},
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
	# Turbo: mehr Schub und etwas mehr Endtempo, lauteres Ladedruck-Zischen
	"turbo": {
		"label": "Turbo",
		"options": [
			{"name": "Serie", "wins": 0, "accel": 1.0, "top": 1.0},
			{"name": "Stufe 1", "wins": 2, "accel": 1.06, "top": 1.03},
			{"name": "Stufe 2", "wins": 4, "accel": 1.12, "top": 1.06},
			{"name": "Stufe 3", "wins": 7, "accel": 1.18, "top": 1.09},
		],
	},
	# Fahrwerk: mehr Grip, direktere Lenkung, Karosserie tiefer (drop in Metern)
	"suspension": {
		"label": "Fahrwerk",
		"options": [
			{"name": "Serie", "wins": 0, "grip": 0.0, "steer": 0.0, "drop": 0.0},
			{"name": "Sport", "wins": 1, "grip": 1.5, "steer": 0.06, "drop": 0.025},
			{"name": "Gewinde", "wins": 3, "grip": 3.0, "steer": 0.12, "drop": 0.045},
			{"name": "Rennfahrwerk", "wins": 6, "grip": 4.5, "steer": 0.18, "drop": 0.06},
		],
	},
	# Reifen: mehr Grip in Kurven, Rennreifen kleben, driften dafür etwas unwilliger
	"tires": {
		"label": "Reifen",
		"options": [
			{"name": "Serie", "wins": 0, "grip": 0.0, "drift": 0.0},
			{"name": "Sport", "wins": 1, "grip": 1.0, "drift": 0.0},
			{"name": "Semi-Slicks", "wins": 4, "grip": 2.5, "drift": -0.04},
			{"name": "Rennreifen", "wins": 6, "grip": 4.0, "drift": -0.08},
		],
	},
}

const PART_ORDER := ["paint", "rims", "rimcol", "spoiler", "bodykit", "hood", "exhaust", "vinyl", "vinylcol", "neon", "tint",
	"lights", "engine", "turbo", "nitro", "suspension", "tires"]
## Tuning-Menü wie in NFS: erst Optik oder Leistung, dann die Kategorie, dann das Teil
const PART_GROUPS := {"optik": ["paint", "rims", "rimcol", "spoiler", "bodykit", "hood", "exhaust", "vinyl", "vinylcol", "neon",
	"tint", "lights"],
	"leistung": ["engine", "turbo", "nitro", "suspension", "tires"]}


## Option einer Kategorie aus einer Konfiguration (fehlende Kategorien = Serie)
static func part_of(cfg: Dictionary, cat: String) -> Dictionary:
	return PARTS[cat]["options"][clampi(int(cfg.get(cat, 0)), 0, PARTS[cat]["options"].size() - 1)]


## Fahrwerte mit Tuning: Beschleunigung, Endtempo (m/s), Grip, Lenkung, Drift
static func stats(car_id: String, cfg: Dictionary) -> Dictionary:
	var spec: Dictionary = CARS[car_id]
	var eng := part_of(cfg, "engine")
	var tur := part_of(cfg, "turbo")
	var sus := part_of(cfg, "suspension")
	var tir := part_of(cfg, "tires")
	return {
		"accel": spec["accel"] * eng["accel"] * tur["accel"],
		"top": spec["top_speed"] * eng["top"] * tur["top"],
		"grip": spec["grip"] + sus["grip"] + tir["grip"],
		"steer": spec["steer"] + sus["steer"],
		"drift": clampf(spec.get("drift", 0.3) + tir["drift"], 0.0, 1.0),
	}

## Leistungsindex (wie in NFS): Endtempo, Beschleunigung und Kurvengrip zu einer Zahl, mit Tuning. Kaizen ab Werk
## ~243, Klasse S ab Werk ~456, voll getunt ~770. Lenkung und Drift sind Charakter und zählen nicht mit.
static func rating(car_id: String, cfg: Dictionary) -> int:
	var st := stats(car_id, cfg)
	var corner := sqrt(14.0 + st["grip"] * 0.42)  # Kurventempo wächst mit der Wurzel der Querbeschleunigung
	return roundi((st["top"] * 5.0 + st["accel"] * 16.0 + corner * 42.0 - 500.0) * 1.6)

## Events: werden aus dem Seed prozedural erzeugt. Alle sind von Anfang an fahrbar.
## type: "sprint" (A nach B), "circuit" (Rundkurs, laps Runden), "drift" (Rundkurs allein, Punkte fürs Querfahren),
## "drag" (gerade, auf Schienen: Spurwechsel und Handschaltung).
## tier: Schwierigkeit 1..3. bulges: Segment-Index -> "alley" (kurvige Gasse), "lake" (Seesprung),
## "fork" (echte Gabelung: kurz mit Gegenverkehr oder breiter Boulevard außen herum).
## districts: Gewichte der Stadtviertel. Rundkurse: corners = Eckpunkte, radius = ungefähre Größe.
const RACES := [
	{"name": "Bankenviertel-Sprint", "town": "Frankfurt am Main", "region": "Kreisfreie Stadt", "geo": Vector2(50.1109, 8.6821), "mood": "neon",  "type": "sprint", "tier": 1, "seed": 11, "segments": 18, "max_turn": 50.0,
		"bulges": {4: "alley", 11: "lake"},
		"districts": {"downtown": 0.35, "shops": 0.5, "residential": 0.15}},
	{"name": "Prachtallee-Sprint", "town": "München", "region": "Landeshauptstadt", "geo": Vector2(48.1351, 11.582), "mood": "daemmerung",  "type": "sprint", "tier": 1, "seed": 23, "segments": 20, "max_turn": 40.0,
		"bulges": {5: "fork", 13: "fork"},
		"districts": {"boulevard": 0.45, "downtown": 0.25, "shops": 0.3}},
	{"name": "Hafenrunde", "town": "Hamburg", "region": "Freie und Hansestadt Hamburg", "geo": Vector2(53.5459, 9.9665), "mood": "regen",  "type": "sprint", "tier": 2, "seed": 42, "segments": 24, "max_turn": 65.0,
		"bulges": {5: "lake", 13: "fork", 19: "alley"},
		"districts": {"industrial": 0.45, "shops": 0.35, "residential": 0.2}},
	{"name": "Schnellstraßen-Sprint", "town": "Dortmund", "region": "Kreisfreie Stadt", "geo": Vector2(51.5136, 7.4653), "mood": "natrium",  "type": "sprint", "tier": 3, "seed": 7, "segments": 30, "max_turn": 30.0,
		"bulges": {7: "alley", 17: "lake", 24: "fork"},
		"districts": {"highway": 0.4, "downtown": 0.2, "industrial": 0.2, "boulevard": 0.2}},
	{"name": "Innenstadtring", "town": "Köln", "region": "Kreisfreie Stadt", "geo": Vector2(50.9375, 6.9603), "mood": "mitternacht",  "type": "circuit", "tier": 1, "laps": 2, "seed": 101, "corners": 9, "radius": 260.0,
		"bulges": {3: "alley"},
		"districts": {"downtown": 0.4, "boulevard": 0.3, "shops": 0.3}},
	{"name": "Hafenring", "town": "Bremen", "region": "Freie Hansestadt Bremen", "geo": Vector2(53.0793, 8.8017), "mood": "regen",  "type": "circuit", "tier": 2, "laps": 2, "seed": 202, "corners": 10, "radius": 300.0,
		"bulges": {2: "fork", 6: "lake"},
		"districts": {"industrial": 0.5, "highway": 0.25, "shops": 0.25}},
	{"name": "Nachtschicht", "town": "Stuttgart", "region": "Landeshauptstadt", "geo": Vector2(48.7758, 9.1829), "mood": "mitternacht",  "type": "circuit", "tier": 3, "laps": 2, "seed": 303, "corners": 11, "radius": 360.0,
		"bulges": {2: "fork", 7: "alley"},
		"districts": {"highway": 0.3, "boulevard": 0.3, "downtown": 0.4}},
	{"name": "Hafen-Drift", "town": "Hamburg", "region": "Freie und Hansestadt Hamburg", "geo": Vector2(53.5459, 9.9665), "mood": "nebel",  "type": "drift", "tier": 2, "laps": 2, "seed": 502, "corners": 12, "radius": 155.0,
		"bulges": {},
		"districts": {"industrial": 0.7, "highway": 0.3}},
	{"name": "Stadion-Drift", "town": "Gelsenkirchen", "region": "Kreisfreie Stadt", "geo": Vector2(51.5177, 7.0857), "mood": "natrium",  "type": "drift", "tier": 3, "laps": 2, "seed": 603, "corners": 14, "radius": 175.0,
		"bulges": {}, "stadium": true,
		"districts": {"downtown": 0.4, "boulevard": 0.6}},
	# --- neu: Drag-Rennen (geradeaus, Handschaltung) und weitere Strecken; hinten angehängt, damit gespeicherte
	# Event-Nummern gültig bleiben
	{"name": "Hafenmeile", "town": "Kiel", "region": "Landeshauptstadt", "geo": Vector2(54.3233, 10.1228), "mood": "nebel",  "type": "drag", "tier": 1, "seed": 701, "segments": 8, "max_turn": 4.0,
		"districts": {"industrial": 0.6, "shops": 0.4}},
	{"name": "Neon-Gerade", "town": "Leipzig", "region": "Kreisfreie Stadt", "geo": Vector2(51.3397, 12.3731), "mood": "kiez",  "type": "drag", "tier": 2, "seed": 702, "segments": 10, "max_turn": 6.0,
		"districts": {"downtown": 0.5, "shops": 0.5}},
	{"name": "Schnellstraßen-Drag", "town": "Hockenheim", "region": "Rhein-Neckar-Kreis", "geo": Vector2(49.322, 8.547), "mood": "mitternacht",  "type": "drag", "tier": 3, "seed": 703, "segments": 13, "max_turn": 5.0,
		"districts": {"highway": 0.6, "boulevard": 0.4}},
	{"name": "Altstadt-Hügel", "town": "Heidelberg", "region": "Kreisfreie Stadt", "geo": Vector2(49.3988, 8.6724), "mood": "daemmerung",  "type": "sprint", "tier": 2, "seed": 61, "segments": 22, "max_turn": 55.0,
		"bulges": {4: "fork", 11: "fork", 17: "alley"},
		"districts": {"residential": 0.45, "shops": 0.55}},
	{"name": "Hafen-Sprint", "town": "Rostock", "region": "Hanse- und Universitätsstadt", "geo": Vector2(54.0924, 12.0991), "mood": "nebel",  "type": "sprint", "tier": 3, "seed": 77, "segments": 26, "max_turn": 70.0,
		"bulges": {5: "lake", 12: "alley", 19: "fork"},
		"districts": {"industrial": 0.5, "highway": 0.3, "residential": 0.2}},
	{"name": "Altstadtring", "town": "Nürnberg", "region": "Kreisfreie Stadt", "geo": Vector2(49.4521, 11.0767), "mood": "mitternacht",  "type": "circuit", "tier": 2, "laps": 2, "seed": 131, "corners": 10, "radius": 290.0,
		"bulges": {2: "fork", 6: "alley"},
		"districts": {"residential": 0.5, "boulevard": 0.3, "downtown": 0.2}},
	# --- Orts-Strecken: echte Straßenverläufe (OpenStreetMap, tools/osm_city.py), Wahrzeichen an ihrem Platz.
	# city = Schlüssel in city_data.gd, town = Ortsschild, shops = Ladennamen der Stadt, station = Haltestelle am Bahnübergang
	{"name": "Aachen Grabenring", "geo": Vector2(50.7753, 6.0839), "mood": "regen",  "type": "circuit", "tier": 2, "laps": 2, "seed": 801, "city": "aachen", "town": "Aachen",
		"shops": ["PRINTEN", "ÖCHER BRAUHAUS", "CAMPUS BAR", "DOMCAFÉ", "PONTSTRASSE", "THERMALBAD", "MENSA", "KAISERCAFÉ"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "campus_de": 0.2},
		"desc": "Über den Grabenring am SuperC der RWTH, am Elisenbrunnen und am Theater vorbei. In der Mitte Dom und Rathaus."},
	{"name": "Würzburg Mainufer", "geo": Vector2(49.7913, 9.9534), "mood": "daemmerung",  "type": "sprint", "tier": 3, "seed": 802, "city": "wuerzburg", "town": "Würzburg",
		"shops": ["BOCKSBEUTEL", "FRANKENWEIN", "BRÜCKENSCHOPPEN", "WEINHAUS", "KILIANI", "MAINFRANKEN", "SCHOPPEN"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "vorstadt_de": 0.2},
		"desc": "Rennweg an der Residenz, über die Ludwigsbrücke, unter der Festung Marienberg entlang, über die Friedensbrücke zum Alten Kranen."},
	{"name": "Bad Kissingen Kurmeile", "geo": Vector2(50.2, 10.077), "mood": "daemmerung",  "type": "sprint", "tier": 1, "seed": 803, "city": "badkissingen", "town": "Bad Kissingen",
		"shops": ["KURCAFÉ", "KURAPOTHEKE", "RAKOCZY", "TRINKHALLE", "KONZERTCAFÉ", "KURHAUS", "SALINE"],
		"districts": {"kurviertel_de": 0.55, "innenstadt_de": 0.2, "vorstadt_de": 0.25},
		"desc": "Vom Regentenbau am Kurgarten über die Saale, dann am Fluss entlang zum Gradierbau der Oberen Saline."},
	{"name": "Tauberbischofsheim Altstadt", "geo": Vector2(49.6236, 9.6627), "mood": "nebel",  "type": "circuit", "tier": 1, "laps": 3, "seed": 804, "city": "tbb", "town": "Tauberbischofsheim",
		"shops": ["FECHTCLUB", "TAUBERWEIN", "FECHTERSTADT", "TAUBERTAL", "LIOBA CAFÉ", "SCHLOSSCAFÉ"],
		"districts": {"altstadt_de": 0.6, "vorstadt_de": 0.4},
		"desc": "Rund um die Altstadt der Fechterstadt, Türmersturm, Rathaus und St. Martin immer im Blick."},
	{"name": "Hammelburg Saaleck", "geo": Vector2(50.1162, 9.8906), "mood": "daemmerung",  "type": "sprint", "tier": 2, "seed": 805, "city": "hammelburg", "town": "Hammelburg",
		"station": "HAMMELBURG",
		"shops": ["WEINSTADT", "HÄCKERWIRTSCHAFT", "SAALETAL", "WEINFEST", "WINZERSTUBE", "STADTSCHÄNKE"],
		"districts": {"altstadt_de": 0.5, "vorstadt_de": 0.5},
		"desc": "Über die Bahnlinie in die Altstadt, am Rathaus mit Marktbrunnen vorbei, über die Saale hinauf zu Schloss Saaleck."},
	{"name": "Berlin Kreuzberg", "geo": Vector2(52.4990, 13.4300), "mood": "kiez", "type": "circuit", "tier": 3, "laps": 2,
		"seed": 806, "city": "kreuzberg", "town": "Berlin",
		"shops": ["SPÄTI", "DÖNER", "CURRYWURST", "PLATTENLADEN", "VEGAN", "SHISHA BAR", "KIEZKNEIPE", "FAHRRADLADEN", "TATTOO"],
		"districts": {"kiez_de": 0.7, "innenstadt_de": 0.3},
		"desc": "Unter der Hochbahn der U1 durch die Skalitzer Straße, über die Oberbaumbrücke, an der East Side Gallery entlang und über die Schillingbrücke zurück zum Kotti."},
]

const EVENT_TYPES := {
	"sprint": {"label": "Sprint", "goal": "Als Erster von A nach B.", "desc": "Von A nach B gegen 3 Gegner. Gabelungen und Abkürzungen: du entscheidest. Rauten: 1 ohne Verkehr, 2 wenig, 3 voll."},
	"circuit": {"label": "Rundkurs", "goal": "Nach %d Runden als Erster über die Linie.", "desc": "Rundkurs gegen 3 Gegner. Wer die beste Linie findet, gewinnt. Rauten: 1 ohne Verkehr, 2 wenig, 3 voll."},
	"drift": {"label": "Drift", "goal": "Die meisten Driftpunkte: die Marke für Platz 1 steht am Start.", "desc": "Allein auf der Strecke. Querfahren gibt Punkte, Ketten geben Multiplikator, die leuchtenden Zonen am Kurvenrand zählen doppelt, ein Crash kostet die Kette."},
	"drag": {"label": "Drag", "goal": "Als Erster über die Linie: perfekt schalten, dem Verkehr ausweichen.", "desc": "Geradeaus gegen 3 Gegner, das Auto fährt wie auf Schienen. A/D wechselt die Spur, S schaltet hoch, X runter: im grünen Bereich perfekt. Zu lange im Begrenzer: Motorschaden. Crash mit Verkehr: Totalschaden."},
}
const TYPE_ORDER := ["sprint", "circuit", "drag", "drift"]
## Karriere in Stufen wie in NFSU2: alle Events einer Stufe sind gleichzeitig offen und in beliebiger Reihenfolge
## fahrbar. STAGE_WINS Siege in einer Stufe öffnen die nächste, ein Event, das einem nicht liegt, kann man also
## auslassen. Jede Stufe mischt die Arten, die Schwierigkeit steigt von Stufe zu Stufe.
const STAGES := [
	{"name": "Einstieg", "events": ["Bankenviertel-Sprint", "Tauberbischofsheim Altstadt", "Hafenmeile", "Bad Kissingen Kurmeile"]},
	{"name": "Szene", "events": ["Prachtallee-Sprint", "Innenstadtring", "Hafen-Drift", "Hammelburg Saaleck"]},
	{"name": "Hafen und Altstadt", "events": ["Hafenrunde", "Neon-Gerade", "Aachen Grabenring", "Altstadt-Hügel", "Hafenring"]},
	{"name": "Großstadt", "events": ["Altstadtring", "Berlin Kreuzberg", "Schnellstraßen-Sprint", "Stadion-Drift"]},
	{"name": "Finale", "events": ["Schnellstraßen-Drag", "Hafen-Sprint", "Nachtschicht", "Würzburg Mainufer"]},
]
const STAGE_WINS := 3
## Alle Karriere-Events Stufe für Stufe (Reihenfolge der Liste in der Garage)
const CAREER := ["Bankenviertel-Sprint", "Tauberbischofsheim Altstadt", "Hafenmeile", "Bad Kissingen Kurmeile",
	"Prachtallee-Sprint", "Innenstadtring", "Hafen-Drift", "Hammelburg Saaleck",
	"Hafenrunde", "Neon-Gerade", "Aachen Grabenring", "Altstadt-Hügel", "Hafenring",
	"Altstadtring", "Berlin Kreuzberg", "Schnellstraßen-Sprint", "Stadion-Drift",
	"Schnellstraßen-Drag", "Hafen-Sprint", "Nachtschicht", "Würzburg Mainufer"]
## Bis 2.15 eine Kette (ein Sieg öffnete das nächste Event): was danach schon offen war, bleibt offen
const CAREER_V1 := ["Bankenviertel-Sprint", "Tauberbischofsheim Altstadt", "Hafenmeile", "Bad Kissingen Kurmeile",
	"Prachtallee-Sprint", "Innenstadtring", "Hafenrunde", "Hammelburg Saaleck", "Neon-Gerade", "Aachen Grabenring",
	"Hafen-Drift", "Altstadt-Hügel", "Hafenring", "Altstadtring", "Berlin Kreuzberg", "Schnellstraßen-Sprint",
	"Schnellstraßen-Drag", "Hafen-Sprint", "Stadion-Drift", "Nachtschicht", "Würzburg Mainufer"]


## Drift: Punkte für Platz 3, 2, 1 je nach Stufe, Schwierigkeit und Zahl der Kurven
static func drift_targets(r: Dictionary, diff: int) -> Array:
	var tier: int = r.get("tier", 1)
	var k: float = [1.0, 1.0, 1.35, 1.7][tier] * [0.65, 0.85, 1.0][diff] * r.get("laps", 2) * r.get("corners", 12) / 24.0
	return [int(700 * k / 10.0) * 10, int(1500 * k / 10.0) * 10, int(2600 * k / 10.0) * 10]


## Stufe (0..) eines Karriere-Events, -1 wenn es in keiner steht
static func stage_of(event_name: String) -> int:
	for i in STAGES.size():
		if event_name in STAGES[i]["events"]:
			return i
	return -1


static func race_index(name: String) -> int:
	for i in RACES.size():
		if RACES[i]["name"] == name:
			return i
	return -1


## Früher englische Eventnamen: Bestzeiten im Spielstand werden beim Laden umgeschrieben
const RENAMED := {
	"Downtown Sprint": "Bankenviertel-Sprint",
	"Boulevard Run": "Prachtallee-Sprint",
	"Feierabendverkehr": "Prachtallee-Sprint",
	"Harbor Run": "Hafenrunde",
	"Highway Rush": "Schnellstraßen-Sprint",
	"Schnellstraßen-Raserei": "Schnellstraßen-Sprint",
	"City Loop": "Innenstadtring",
	"Dock Ring": "Hafenring",
	"Night Ring": "Nachtschicht",
	"Dock Drift": "Hafen-Drift",
	"Stadion Drift": "Stadion-Drift",
	"Highway Drag": "Schnellstraßen-Drag",
	"Viertelmeile ohne Tempolimit": "Schnellstraßen-Drag",
	"Altstadt Hills": "Altstadt-Hügel",
	"Docks Sprint": "Hafen-Sprint",
	"Altstadt Ring": "Altstadtring",
}
## Orts-Strecken stehen im Menü unter eigener Rubrik (nicht zusätzlich unter Sprint/Rundkurs)
const CITY_EVENTS := {"label": "Städte", "desc": "Echte Straßen aus Aachen, Würzburg, Bad Kissingen, Tauberbischofsheim und Hammelburg, die Wahrzeichen stehen an ihrem Platz. Kartendaten © OpenStreetMap-Mitwirkende."}
