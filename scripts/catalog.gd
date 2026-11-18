extends RefCounted
## Alle Inhalte des Spiels: Autos, Tuningteile und Events.
## Seit 2.33 schaltet nur noch das Fahrer-Level frei (GameState.level): Autos "unlock" = {"level": n}, Teile "level",
## Karriere-Stufen "level", dazu Titel, Embleme und Vinyls. level_rewards(l) sammelt, was Level l bringt (Level-Liste
## in der Garage, Meldung beim Aufstieg). "wins" an Teilen und WIN_UNLOCK sind die Schwellen bis 2.32: was ein alter
## Spielstand damit schon hatte, bleibt frei (GameState.kept_*).
## "drift" (0..1): wie willig das Auto quer geht und im Drift bleibt.

## Leistung: Jedes Auto, das du freischaltest, ist ein Stück stärker (Klasse D bis A). Die Autos der Klasse S (auch die
## drei Exoten am Ende) haben die gleiche Grundleistung (Leistungsindex ~456) und unterscheiden sich nur im Charakter:
## Grip, Antritt, Endtempo, Lenkung, Drift. "class" steht in der Garage, rating() rechnet den Index aus.
## drive: fwd, rwd, mr (Mittelmotor), rr (Heckmotor), awd.
## Schub der Gegner beim Anfahren (passend zu den entschärften unteren Gängen des Spielers, player_car.GEAR_PULL)
const ACCEL_SCALE := 0.8

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
		"drive": "rwd", "name": "Hachi Touge", "style": "hatch", "class": "D", "unlock": {"level": 2}, "drift": 0.85,
		"length": 4.2, "width": 1.66,
		"accel": 10.1, "top_speed": 58.0, "grip": 24.0, "steer": 2.6,
		"desc": "Leichtes 80er-Fließheck mit Heckantrieb. Wenig Leistung, viel Gefühl.",
		# Kleiner, drehfreudiger Sauger-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.5, 0.26, 0.12], "sub": 0.22, "turbo": 0.0, "rough": 0.3},
	},
	"sakura": {
		"drive": "rwd", "name": "Sakura D2", "style": "coupe", "class": "C", "unlock": {"level": 4}, "drift": 0.9,
		"length": 4.3, "width": 1.72,
		"accel": 10.5, "top_speed": 60.5, "grip": 23.0, "steer": 2.5,
		"desc": "Leichter Hecktriebler. Gebaut zum Querfahren.",
		# Kurzhubiger Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.55, 0.28, 0.12], "sub": 0.4, "turbo": 0.5, "rough": 0.28},
	},
	"hayate": {
		"drive": "fwd", "name": "Hayate R8", "style": "coupe", "class": "C", "unlock": {"level": 6}, "drift": 0.3, "paint": Color(0.72, 0.04, 0.05),
		"length": 4.38, "width": 1.7,
		"accel": 10.2, "top_speed": 61.5, "grip": 28.0, "steer": 2.45,
		"desc": "Leichtes Coupé, dreht bis 8.000/min. Klebt in Kurven, driftet ungern.",
		# Schreiender Sauger-Vierzylinder mit Nockenwellen-Umschaltung
		"sound": {"cyl": 4, "harm": [1.0, 0.36, 0.34, 0.22], "sub": 0.1, "turbo": 0.0, "rough": 0.1},
	},
	"kitsune": {
		"drive": "rwd", "name": "Kitsune 18S", "style": "hatch", "class": "C", "unlock": {"level": 7}, "drift": 0.85, "paint": Color(0.95, 0.42, 0.06),
		"length": 4.54, "width": 1.69,
		"accel": 11.2, "top_speed": 62.0, "grip": 23.0, "steer": 2.45,
		"desc": "Fließheck mit Klappscheinwerfern, Turbo und Heckantrieb. Liebling der Drift-Szene.",
		# Turbo-Vierzylinder mit Abblasventil
		"sound": {"cyl": 4, "harm": [1.0, 0.58, 0.3, 0.12], "sub": 0.45, "turbo": 0.8, "rough": 0.3},
	},
	"tsubame": {
		"drive": "rwd", "name": "Tsubame Spyder", "style": "roadster", "class": "B", "unlock": {"level": 8}, "drift": 0.6,
		"length": 4.1, "width": 1.75,
		"accel": 11.0, "top_speed": 64.0, "grip": 27.0, "steer": 2.55,
		"desc": "Offener Zweisitzer mit langer Haube. Flink und präzise.",
		# Kreischender Hochdrehzahl-Sauger
		"sound": {"cyl": 4, "harm": [1.0, 0.38, 0.3, 0.16], "sub": 0.12, "turbo": 0.0, "rough": 0.12},
	},
	"mirai": {
		"drive": "rwd", "name": "Mirai 240R", "style": "coupe", "class": "B", "unlock": {"level": 10}, "drift": 0.65,
		"length": 4.35, "width": 1.82,
		"accel": 11.4, "top_speed": 66.0, "grip": 23.5, "steer": 2.25,
		"desc": "Heckantrieb-Coupé. Liebt Drifts.",
		# Bollernder Turbo-Vierzylinder
		"sound": {"cyl": 4, "harm": [1.0, 0.6, 0.3, 0.1], "sub": 0.55, "turbo": 0.7, "rough": 0.35},
	},
	"tenshi": {
		"drive": "mr", "name": "Tenshi MR-T", "style": "coupe", "class": "B", "unlock": {"level": 12}, "drift": 0.5, "paint": Color(0.92, 0.7, 0.06),
		"length": 4.17, "width": 1.7,
		"accel": 11.8, "top_speed": 65.0, "grip": 27.5, "steer": 2.6,
		"desc": "Mittelmotor mit Turbo. Lenkt messerscharf ein, will aber sauber gefahren werden.",
		# Turbo-Vierzylinder direkt hinter dir
		"sound": {"cyl": 4, "harm": [1.0, 0.5, 0.32, 0.14], "sub": 0.35, "turbo": 0.85, "rough": 0.25},
	},
	"kumo": {
		"drive": "rwd", "name": "Kumo JX6", "style": "sedan", "class": "A", "unlock": {"level": 13}, "drift": 0.85, "paint": Color(0.3, 0.32, 0.36), "finish": "metal",
		"length": 4.72, "width": 1.75,
		"accel": 12.4, "top_speed": 68.0, "grip": 23.5, "steer": 2.3,
		"desc": "Viertürer mit Turbo-Reihensechser und Heckantrieb. Unauffällig, bis er quer steht.",
		# Seidiger Turbo-Reihensechser
		"sound": {"cyl": 6, "harm": [1.0, 0.52, 0.3, 0.14], "sub": 0.18, "turbo": 0.9, "rough": 0.14},
	},
	"raijin": {
		"drive": "awd", "name": "Raijin RS-4", "style": "sedan", "class": "A", "unlock": {"level": 14}, "drift": 0.25,
		"length": 4.45, "width": 1.8,
		"accel": 12.6, "top_speed": 67.0, "grip": 29.5, "steer": 2.2,
		"desc": "Rallye-Limousine mit Allrad-Gefühl. Klebt auf der Straße.",
		# Rauer Turbo-Vierzylinder mit Ladedruck-Zischen
		"sound": {"cyl": 4, "harm": [1.0, 0.65, 0.4, 0.2], "sub": 0.6, "turbo": 0.9, "rough": 0.5},
	},
	# --- seit 2.36: Evo-Gefühl und Kreiskolben-Coupé ---
	"yari": {
		"drive": "awd", "name": "Yari Shinka VIII", "style": "sedan", "class": "A", "unlock": {"level": 12}, "drift": 0.3, "paint": Color(0.08, 0.27, 0.72),
		"length": 4.49, "width": 1.77,
		"accel": 12.3, "top_speed": 65.5, "grip": 30.0, "steer": 2.3,
		"desc": "Kantige Rallye-Limousine mit Allrad, Turbo-Vierzylinder und hohem Flügel. Schießt aus jeder Kurve, auf jedem Belag.",
		# Rauer Turbo-Vierzylinder, viel Ladedruck
		"sound": {"cyl": 4, "harm": [1.0, 0.62, 0.38, 0.18], "sub": 0.55, "turbo": 0.95, "rough": 0.45},
	},
	"tatsumaki": {
		"drive": "rwd", "name": "Tatsumaki RE", "style": "coupe", "class": "A", "unlock": {"level": 14}, "drift": 0.75, "paint": Color(0.62, 0.035, 0.05),
		"length": 4.3, "width": 1.76,
		"accel": 12.4, "top_speed": 69.0, "grip": 26.5, "steer": 2.5,
		"desc": "Flaches Kreiskolben-Coupé mit Klappscheinwerfern und zwei Turbos. Dreht wie eine Turbine und lässt sich fein quer stellen.",
		# Zwei-Scheiben-Kreiskolben mit Registeraufladung
		"sound": {"cyl": 2, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.3, "turbo": 0.85, "rough": 0.2},
	},
	"vortex": {
		"drive": "awd", "name": "Vortex GT-R", "style": "sedan", "class": "S", "unlock": {"level": 15}, "drift": 0.3,
		"length": 4.6, "width": 1.8,
		"accel": 12.9, "top_speed": 72.5, "grip": 29.5, "steer": 2.05,
		"desc": "Schwere Turbo-Limousine. Liegt satt, viel Grip, zieht aus jeder Kurve.",
		# Seidiger Reihensechser mit großem Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.5, 0.3, 0.15], "sub": 0.12, "turbo": 1.0, "rough": 0.12},
	},
	"ronin": {
		"drive": "rwd", "name": "Ronin DR", "style": "coupe", "class": "S", "unlock": {"level": 16}, "drift": 1.0,
		"length": 4.3, "width": 1.78,
		"accel": 13.6, "top_speed": 72.0, "grip": 25.0, "steer": 2.5,
		"desc": "Drift-Monster mit V8-Swap. Steht quer, wann immer du willst.",
		# Tiefer, grollender V8
		"sound": {"cyl": 8, "harm": [1.0, 0.7, 0.35, 0.15], "sub": 0.6, "turbo": 0.0, "rough": 0.4},
	},
	"shiden": {
		"drive": "mr", "name": "Shiden NX-1", "style": "coupe", "class": "S", "unlock": {"level": 17}, "drift": 0.45, "paint": Color(0.36, 0.1, 0.56), "finish": "pearl",
		"length": 4.43, "width": 1.81,
		"accel": 13.2, "top_speed": 71.0, "grip": 31.0, "steer": 2.65,
		"desc": "Flacher Mittelmotor-Sportwagen. Die präziseste Lenkung und der meiste Grip im Spiel.",
		# Kreischender V6-Sauger
		"sound": {"cyl": 6, "harm": [1.0, 0.42, 0.36, 0.2], "sub": 0.12, "turbo": 0.0, "rough": 0.1},
	},
	"ryujin": {
		"drive": "rwd", "name": "Ryujin 30Z", "style": "coupe", "class": "S", "unlock": {"level": 18}, "drift": 0.4, "paint": Color(0.04, 0.3, 0.3), "finish": "metal",
		"length": 4.52, "width": 1.8,
		"accel": 13.2, "top_speed": 73.0, "grip": 25.5, "steer": 2.05,
		"desc": "Breites Biturbo-Coupé. Schiebt brutal an und bleibt bei Höchsttempo ruhig.",
		# V6 mit zwei Turbos
		"sound": {"cyl": 6, "harm": [1.0, 0.62, 0.38, 0.16], "sub": 0.35, "turbo": 1.0, "rough": 0.22},
	},
	"kaze": {
		"drive": "rwd", "name": "Kaze TT", "style": "coupe", "class": "S", "unlock": {"level": 19}, "drift": 0.55,
		"length": 4.5, "width": 1.81,
		"accel": 12.4, "top_speed": 75.5, "grip": 26.0, "steer": 2.15,
		"desc": "Langes Biturbo-Coupé mit Bügelflügel. Das schnellste Auto der Stadt.",
		# Reihensechser mit zwei Turbos
		"sound": {"cyl": 6, "harm": [1.0, 0.55, 0.32, 0.14], "sub": 0.2, "turbo": 1.0, "rough": 0.15},
	},
	# --- Kleinwagen ---
	"chibi": {
		"drive": "fwd", "name": "Chibi K-Turbo", "style": "hatch", "class": "D", "unlock": {}, "drift": 0.4, "paint": Color(0.82, 0.06, 0.08),
		"length": 3.4, "width": 1.48,
		"accel": 10.0, "top_speed": 56.0, "grip": 27.5, "steer": 2.75,
		"desc": "Winziger Kei-Wagen mit Turbo und Hutze. Wenig Endtempo, passt aber durch jede Lücke.",
		# Kleiner Turbo-Dreizylinder, kernig und surrend
		"sound": {"cyl": 3, "harm": [1.0, 0.62, 0.38, 0.2], "sub": 0.5, "turbo": 0.7, "rough": 0.42},
	},
	"hotaru": {
		"drive": "mr", "name": "Hotaru MR-K", "style": "roadster", "class": "D", "unlock": {"level": 3}, "drift": 0.55, "paint": Color(0.97, 0.82, 0.06),
		"length": 3.3, "width": 1.4,
		"accel": 10.3, "top_speed": 57.5, "grip": 29.5, "steer": 2.85,
		"desc": "Offener Kei-Roadster mit Mittelmotor. Dreht bis 8.500/min und lenkt wie ein Go-Kart.",
		# Hochdrehender Dreizylinder-Sauger direkt hinter dir
		"sound": {"cyl": 3, "harm": [1.0, 0.42, 0.34, 0.22], "sub": 0.35, "turbo": 0.0, "rough": 0.22},
	},
	"tanuki": {
		"drive": "awd", "name": "Tanuki R4", "style": "hatch", "class": "B", "unlock": {"level": 11}, "drift": 0.4, "paint": Color(0.88, 0.89, 0.9), "finish": "metal",
		"length": 3.99, "width": 1.8,
		"accel": 11.9, "top_speed": 63.5, "grip": 29.0, "steer": 2.6,
		"desc": "Kleinwagen mit Allrad, Turbo-Dreizylinder und Rallye-Genen. Schießt aus engen Kurven.",
		# Großer Turbo-Dreizylinder, rau und bassig
		"sound": {"cyl": 3, "harm": [1.0, 0.66, 0.4, 0.18], "sub": 0.6, "turbo": 0.95, "rough": 0.45},
	},
	# --- JDM-Klassiker ---
	"kaido": {
		"drive": "rwd", "name": "Kaido 2000GT", "style": "sedan", "class": "C", "unlock": {"level": 5}, "drift": 0.75, "paint": Color(0.6, 0.62, 0.64), "finish": "metal",
		"length": 4.4, "width": 1.66,
		"accel": 10.6, "top_speed": 61.0, "grip": 24.0, "steer": 2.35,
		"desc": "70er-Hardtop mit Reihensechser, Chrom und aufgeschraubten Verbreiterungen. Kantig, laut, gutmütig.",
		# Rauer Reihensechser-Sauger mit Vergasern
		"sound": {"cyl": 6, "harm": [1.0, 0.62, 0.42, 0.22], "sub": 0.28, "turbo": 0.0, "rough": 0.38},
	},
	"hakone": {
		"drive": "rwd", "name": "Hakone 240", "style": "coupe", "class": "B", "unlock": {"level": 9}, "drift": 0.7, "paint": Color(0.55, 0.12, 0.08),
		"length": 4.15, "width": 1.63,
		"accel": 11.3, "top_speed": 65.0, "grip": 24.5, "steer": 2.4,
		"desc": "Klassisches Fließheck-Coupé mit endlos langer Haube. Leicht, schmal und herrlich quer.",
		# Reihensechser-Sauger, offen und kehlig
		"sound": {"cyl": 6, "harm": [1.0, 0.56, 0.4, 0.2], "sub": 0.22, "turbo": 0.0, "rough": 0.3},
	},
	# --- Exoten ---
	"kagura": {
		"drive": "rwd", "name": "Kagura V10", "style": "coupe", "class": "S", "unlock": {"level": 20}, "drift": 0.45, "paint": Color(0.95, 0.95, 0.94), "finish": "pearl",
		"length": 4.5, "width": 1.9,
		"accel": 13.6, "top_speed": 71.5, "grip": 26.5, "steer": 2.35,
		"desc": "Japanischer Supersportwagen mit V10 vorn. Der stärkste Antritt im Spiel und ein Schrei bis 9.000/min.",
		# Kreischender V10-Sauger
		"sound": {"cyl": 10, "harm": [1.0, 0.34, 0.4, 0.26], "sub": 0.08, "turbo": 0.0, "rough": 0.08},
	},
	"falke": {
		"drive": "rr", "name": "Falke 9 RS", "style": "coupe", "class": "S", "unlock": {"level": 21}, "drift": 0.5, "paint": Color(0.45, 0.7, 0.85), "finish": "metal",
		"length": 4.55, "width": 1.85,
		"accel": 13.0, "top_speed": 71.5, "grip": 31.0, "steer": 2.55,
		"desc": "Sportwagen mit Boxer im Heck. Enorme Traktion, das Heck will aber mit Gefühl gefahren werden.",
		# Boxer-Sechszylinder-Sauger: hart, metallisch
		"sound": {"cyl": 6, "harm": [1.0, 0.48, 0.44, 0.26], "sub": 0.3, "turbo": 0.0, "rough": 0.28},
	},
	"furia": {
		"drive": "awd", "name": "Furia V12", "style": "coupe", "class": "S", "unlock": {"level": 22}, "drift": 0.35, "paint": Color(0.55, 0.85, 0.1), "finish": "pearl",
		"length": 4.8, "width": 2.03,
		"accel": 12.3, "top_speed": 75.0, "grip": 28.5, "steer": 2.0,
		"desc": "Flacher V12-Keil mit Allrad, breiter als jeder Gegner. Zieht ewig, lenkt aber träge ein.",
		# V12-Sauger: dicht, seidig, laut
		"sound": {"cyl": 12, "harm": [1.0, 0.4, 0.3, 0.2], "sub": 0.06, "turbo": 0.0, "rough": 0.06},
	},
	# --- Nur über das Fahrer-Level (seit 2.32): schneller als alles, was man mit Siegen bekommt ---
	"raiden": {
		"drive": "awd", "name": "Raiden Zero", "style": "coupe", "class": "S", "unlock": {"level": 24}, "drift": 0.4, "paint": Color(0.06, 0.16, 0.5), "finish": "metal",
		"length": 4.65, "width": 1.98,
		"accel": 13.9, "top_speed": 79.0, "grip": 31.0, "steer": 2.2,
		"desc": "Allrad-GT mit Biturbo-V6, für die Autobahn gebaut. Das höchste Endtempo im Spiel, klebt in jeder Kurve.",
		# Biturbo-V6: rau, mit viel Turbo
		"sound": {"cyl": 6, "harm": [1.0, 0.44, 0.36, 0.2], "sub": 0.2, "turbo": 0.6, "rough": 0.18},
	},
	"tengu": {
		"drive": "rwd", "name": "Tengu RS", "style": "coupe", "class": "S", "unlock": {"level": 26}, "drift": 0.9, "paint": Color(0.95, 0.42, 0.04), "finish": "pearl",
		"length": 4.45, "width": 1.95,
		"accel": 14.4, "top_speed": 77.0, "grip": 28.0, "steer": 2.5,
		"desc": "Drift-Monster mit Heckantrieb und hochgedrehtem Reihensechser. Brutaler Antritt, das Heck kommt auf Ansage.",
		# hochdrehender Reihensechser mit großem Lader
		"sound": {"cyl": 6, "harm": [1.0, 0.55, 0.42, 0.24], "sub": 0.2, "turbo": 0.5, "rough": 0.22},
	},
}

## Reihenfolge in der Garage = Reihenfolge des Freischaltens
const CAR_ORDER := ["kaizen", "chibi", "hachi", "hotaru", "sakura", "kaido", "hayate", "kitsune", "tsubame", "hakone",
	"mirai", "tanuki", "tenshi", "yari", "kumo", "raijin", "tatsumaki", "vortex", "ronin", "shiden", "ryujin", "kaze", "kagura", "falke", "furia",
	"raiden", "tengu"]
## Exoten nur über hohe Level: fahren nicht als Gegner oder Herausforderer mit (bleiben etwas Besonderes)
const EXOTICS := ["raiden", "tengu"]
## Bis 2.32 schalteten Siege die Autos frei (Rennsiege oder Driftsiege, eins reicht): was ein Spielstand damit schon
## hatte, bleibt beim Umstieg auf das Fahrer-Level frei
const WIN_UNLOCK := {"hachi": {"race": 1, "drift": 1}, "hotaru": {"race": 2, "drift": 1}, "sakura": {"race": 2, "drift": 1},
	"kaido": {"race": 3, "drift": 1}, "hayate": {"race": 3}, "kitsune": {"race": 4, "drift": 1}, "tsubame": {"race": 5},
	"hakone": {"race": 5, "drift": 2}, "mirai": {"race": 6, "drift": 2}, "tanuki": {"race": 7}, "tenshi": {"race": 7},
	"kumo": {"race": 8, "drift": 2}, "raijin": {"race": 9}, "vortex": {"race": 10}, "ronin": {"race": 11, "drift": 3},
	"shiden": {"race": 12}, "ryujin": {"race": 13}, "kaze": {"race": 14, "drift": 4}, "kagura": {"race": 14},
	"falke": {"race": 15}, "furia": {"race": 16}}
## Bis Version 2.10 galten andere Schwellen: wer damit schon ein Auto freigeschaltet hatte, behält es
const LEGACY_UNLOCK := {"hachi": {"race": 1, "drift": 1}, "mirai": {"race": 2, "drift": 1}, "sakura": {"drift": 1},
	"tsubame": {"race": 3}, "vortex": {"race": 5}, "raijin": {"race": 7}, "ronin": {"drift": 3}, "kaze": {"race": 9, "drift": 4}}

## Werksfelge je Auto (Felgen "Serie"): [Bauart, Speichen, Farbe, Zoll ab Werk, Radmuttern]. Ältere und kleine Autos
## rollen auf kleinen Felgen mit hohem Reifen, die Exoten auf großen.
const FACTORY_RIMS := {
	"kaizen": ["std", 7, Color(0.76, 0.77, 0.8), 15, 4],
	"chibi": ["cap", 8, Color(0.72, 0.73, 0.75), 13, 4],
	"hachi": ["holes", 8, Color(0.78, 0.79, 0.81), 14, 4],
	"hotaru": ["turbine", 9, Color(0.8, 0.81, 0.83), 14, 4],
	"sakura": ["split", 5, Color(0.76, 0.77, 0.8), 16, 4],
	"kaido": ["rally", 8, Color(0.55, 0.38, 0.16), 14, 4],
	"hayate": ["std", 5, Color(0.8, 0.81, 0.84), 15, 5],
	"kitsune": ["y", 5, Color(0.26, 0.27, 0.29), 15, 4],
	"tsubame": ["concave", 5, Color(0.8, 0.81, 0.84), 16, 5],
	"hakone": ["steel", 6, Color(0.5, 0.51, 0.53), 14, 4],
	"mirai": ["split", 7, Color(0.3, 0.31, 0.33), 18, 5],
	"tanuki": ["ten", 10, Color(0.07, 0.07, 0.075), 18, 5],
	"tenshi": ["mesh", 8, Color(0.78, 0.79, 0.81), 15, 4],
	"kumo": ["thin", 12, Color(0.8, 0.81, 0.84), 16, 5],
	"raijin": ["rally", 6, Color(0.8, 0.62, 0.22), 17, 5],
	"yari": ["thin", 10, Color(0.84, 0.85, 0.88), 17, 5],
	"tatsumaki": ["ten", 10, Color(0.3, 0.31, 0.33), 17, 5],
	"vortex": ["te", 6, Color(0.24, 0.25, 0.27), 18, 5],
	"ronin": ["std", 5, Color(0.8, 0.81, 0.84), 17, 5],
	"shiden": ["concave", 7, Color(0.78, 0.79, 0.82), 17, 5],
	"ryujin": ["sickle", 10, Color(0.8, 0.81, 0.84), 17, 5],
	"kaze": ["y", 5, Color(0.8, 0.81, 0.84), 18, 5],
	"kagura": ["ten", 10, Color(0.24, 0.25, 0.27), 20, 5],
	"falke": ["clover", 5, Color(0.84, 0.85, 0.87), 18, 5],
	"furia": ["holes", 5, Color(0.72, 0.6, 0.32), 19, 5],
	"raiden": ["te", 6, Color(0.1, 0.1, 0.11), 20, 5],
	"tengu": ["concave", 5, Color(0.86, 0.68, 0.2), 19, 5],
}

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
			{"name": "Giftgrün", "wins": 0, "color": Color(0.35, 0.9, 0.1)},
			{"name": "Candyblau", "wins": 0, "color": Color(0.05, 0.2, 0.9), "finish": "metal"},
			{"name": "Neonpink", "wins": 0, "color": Color(0.95, 0.1, 0.6)},
			{"name": "Weiß", "wins": 0, "color": Color(0.9, 0.9, 0.88)},
			{"name": "Silber", "wins": 0, "color": Color(0.72, 0.74, 0.77)},
			{"name": "Orange", "wins": 0, "color": Color(0.95, 0.38, 0.04)},
			{"name": "Blau", "wins": 0, "color": Color(0.07, 0.22, 0.62)},
			{"name": "Dunkelgrün", "wins": 0, "color": Color(0.03, 0.2, 0.1)},
			{"name": "Gunmetal", "wins": 0, "color": Color(0.2, 0.21, 0.23)},
			{"name": "Lila", "wins": 0, "color": Color(0.33, 0.07, 0.55)},
			{"name": "Babyblau", "wins": 0, "color": Color(0.42, 0.68, 0.95)},
			{"name": "Bronze", "wins": 0, "color": Color(0.5, 0.31, 0.13), "finish": "metal"},
			{"name": "Mattschwarz", "wins": 2, "level": 4, "color": Color(0.035, 0.035, 0.04), "finish": "matt"},
			{"name": "Mattgrau", "wins": 2, "level": 4, "color": Color(0.28, 0.29, 0.3), "finish": "matt"},
			{"name": "Perlweiß", "wins": 3, "level": 6, "color": Color(0.93, 0.92, 0.9), "finish": "pearl"},
			{"name": "Gold", "wins": 4, "level": 8, "color": Color(0.85, 0.62, 0.2), "finish": "metal"},
			{"name": "Chrom", "wins": 6, "level": 11, "color": Color(0.85, 0.86, 0.88), "finish": "chrome"},
		],
	},
	# Lackart (car_builder.FINISH): Standard nimmt die der Farbe bzw. den Werkslack des Autos
	# Seit 2.27 ist alles von Anfang an frei, nur edle Lacke kommen mit Siegen: Metallic, Matt, Perlmutt (Lackart) und
	# die besonderen Farben Mattschwarz, Mattgrau, Perlweiß, Gold, Chrom
	"finish": {
		"label": "Lackart",
		"options": [
			{"name": "Standard", "wins": 0},
			{"name": "Glanz", "wins": 0, "finish": "gloss"},
			{"name": "Metallic", "wins": 1, "level": 2, "finish": "metal"},
			{"name": "Matt", "wins": 2, "level": 3, "finish": "matt"},
			{"name": "Perlmutt", "wins": 3, "level": 5, "finish": "pearl"},
		],
	},
	# style: Bauart der Felge (car_builder._rim_build), spokes: Zahl der Speichen (bzw. Löcher, Schlitze), plus: so viel
	# Zoll größer als die Werksfelge des Autos ist die Felge in ihrer Standardgröße (Kategorie "Zoll" ändert das).
	# "Serie" ist die Werksfelge des jeweiligen Autos (FACTORY_RIMS).
	# Seit 2.37 nach echten Sportfelgen, wie sie hier auf den Autos stehen (ohne Marken): Kreuzgitter mit poliertem
	# Stufenbett und Nieten, geschmiedeter Sechsspeichen-Stern, Doppelspeichen, Tiefbett dreiteilig, Fünfblatt, Turbofächer,
	# Cup-Stern, tief konkave Zehnspeichen. Die Nummern bleiben (Spielstände speichern sie), nur die Bauart ist neu.
	"rims": {
		"label": "Felgen",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(0.62, 0.63, 0.66), "plus": 0, "spokes": 7, "style": "std"},
			{"name": "Fünfspeichen", "wins": 0, "color": Color(0.83, 0.84, 0.87), "plus": 2, "spokes": 5, "style": "std"},
			{"name": "Kreuzgitter Gold", "wins": 0, "color": Color(0.8, 0.62, 0.24), "plus": 2, "spokes": 15, "style": "mesh"},
			{"name": "Tiefbett Schwarz", "wins": 0, "color": Color(0.07, 0.07, 0.075), "plus": 2, "spokes": 6, "style": "dish"},
			{"name": "Doppelspeichen", "wins": 0, "color": Color(0.78, 0.79, 0.82), "plus": 2, "spokes": 5, "style": "split"},
			{"name": "Y-Speichen", "wins": 0, "color": Color(0.36, 0.37, 0.4), "plus": 2, "spokes": 5, "style": "y"},
			{"name": "Mehrspeichen", "wins": 0, "color": Color(0.8, 0.8, 0.83), "plus": 2, "spokes": 20, "style": "thin"},
			{"name": "Stahlfelge", "wins": 0, "color": Color(0.1, 0.1, 0.11), "plus": 0, "spokes": 6, "style": "steel"},
			{"name": "Turbofächer", "wins": 0, "color": Color(0.82, 0.83, 0.86), "plus": 1, "spokes": 18, "style": "turbine"},
			{"name": "Rennsport-Sechs", "wins": 0, "color": Color(0.55, 0.38, 0.17), "plus": 2, "spokes": 6, "style": "te"},
			{"name": "Kreuzspeichen", "wins": 0, "color": Color(0.74, 0.75, 0.78), "plus": 2, "spokes": 8, "style": "cross"},
			{"name": "Aero-Scheibe", "wins": 0, "color": Color(0.9, 0.9, 0.9), "plus": 1, "spokes": 5, "style": "aero"},
			{"name": "Tiefbett Stern", "wins": 0, "color": Color(0.85, 0.86, 0.9), "plus": 3, "spokes": 5, "style": "dish"},
			# ab 2.18
			{"name": "Konkav-Stern", "wins": 0, "color": Color(0.32, 0.33, 0.36), "plus": 3, "spokes": 5, "style": "concave"},
			{"name": "Retro-Loch", "wins": 0, "color": Color(0.8, 0.81, 0.83), "plus": 0, "spokes": 8, "style": "holes"},
			{"name": "Radkappe", "wins": 0, "color": Color(0.72, 0.73, 0.75), "plus": 0, "spokes": 10, "style": "cap"},
			{"name": "Rallye", "wins": 0, "color": Color(0.93, 0.93, 0.91), "plus": 1, "spokes": 8, "style": "rally"},
			{"name": "Sichel", "wins": 0, "color": Color(0.8, 0.81, 0.84), "plus": 2, "spokes": 10, "style": "sickle"},
			{"name": "Schmiede-Zehn", "wins": 0, "color": Color(0.5, 0.36, 0.17), "plus": 2, "spokes": 10, "style": "ten"},
			{"name": "Dreiteilig", "wins": 0, "color": Color(0.1, 0.1, 0.11), "plus": 2, "spokes": 10, "style": "3pc"},
			{"name": "Fünfblatt", "wins": 0, "color": Color(0.82, 0.83, 0.85), "plus": 1, "spokes": 5, "style": "clover"},
			{"name": "Drahtspeichen", "wins": 0, "color": Color(0.85, 0.86, 0.88), "plus": 0, "spokes": 20, "style": "wire"},
			{"name": "Zentralverschluss", "wins": 0, "color": Color(0.16, 0.16, 0.17), "plus": 2, "spokes": 5, "style": "center"},
			# ab 2.37
			{"name": "Cup-Stern", "wins": 0, "color": Color(0.8, 0.81, 0.84), "plus": 2, "spokes": 5, "style": "cup"},
			{"name": "Konkav Zehn", "wins": 0, "color": Color(0.2, 0.2, 0.22), "plus": 3, "spokes": 10, "style": "concave"},
		],
	},
	# Felgengröße seit 2.37 in festen Zoll (13" bis 24"), "Standard" ist die Felge in ihrer üblichen Größe (Werksfelge:
	# ab Werk). Der Reifen behält seinen Außendurchmesser, solange eine echte Flanke bleibt (mindestens 20er-Querschnitt);
	# darüber wächst das ganze Rad, das Auto steht entsprechend höher und die Radläufe werden größer (car_builder.rim_spec).
	# Kleiner als zwei Zoll unter Werk passt nicht über die Bremse (fehlt dann in der Garage).
	# Bis 2.36 galten die Größen relativ (-1, +1 … +4 Zoll zur Standardgröße): die Plätze 1–5 bleiben ausgeblendet stehen,
	# weil Spielstände den Index speichern; GameState rechnet sie beim Laden auf die feste Größe um.
	"rimsize": {
		"label": "Zoll",
		"options": [
			{"name": "Standard", "wins": 0, "inch": 0},
			{"name": "-1 Zoll", "wins": 0, "inch": -1, "hidden": true},
			{"name": "+1 Zoll", "wins": 0, "inch": 1, "hidden": true},
			{"name": "+2 Zoll", "wins": 0, "inch": 2, "hidden": true},
			{"name": "+3 Zoll", "wins": 0, "inch": 3, "hidden": true},
			{"name": "+4 Zoll", "wins": 0, "inch": 4, "hidden": true},
			{"name": "13\"", "wins": 0, "abs": 13},
			{"name": "14\"", "wins": 0, "abs": 14},
			{"name": "15\"", "wins": 0, "abs": 15},
			{"name": "16\"", "wins": 0, "abs": 16},
			{"name": "17\"", "wins": 0, "abs": 17},
			{"name": "18\"", "wins": 0, "abs": 18},
			{"name": "19\"", "wins": 0, "abs": 19},
			{"name": "20\"", "wins": 0, "abs": 20},
			{"name": "21\"", "wins": 0, "abs": 21},
			{"name": "22\"", "wins": 0, "abs": 22},
			{"name": "23\"", "wins": 0, "abs": 23},
			{"name": "24\"", "wins": 0, "abs": 24},
		],
	},
	# Spur (seit 2.37): wie weit die Räder unter den Kotflügeln stehen. Ab Werk sitzen sie gut 2 cm innen, Spurplatten
	# schieben sie je Seite nach außen (bündig bzw. leicht drüber), "Breit" nimmt dazu breitere Reifen (2 cm über die Kante),
	# "Extrabreit" noch breitere und steht je Seite gut 5 cm über (wie ein Breitbau für die Räder; in Kurven auch in der
	# Verfolgerkamera zu sehen, genau von hinten verdeckt das Heck die Hinterräder). Mit dem Breitbau-Kit rücken die Räder ohnehin um die Verbreiterung nach außen.
	# spacer: Meter je Seite, wide: so viel breiter ist der Reifen (m)
	"spur": {
		"label": "Spur",
		"options": [
			{"name": "Serie", "wins": 0, "spacer": 0.0},
			{"name": "Spurplatten 15 mm", "wins": 0, "level": 3, "spacer": 0.015},
			{"name": "Spurplatten 30 mm", "wins": 0, "level": 6, "spacer": 0.03},
			{"name": "Breit", "wins": 0, "level": 9, "spacer": 0.025, "wide": 0.03},
			{"name": "Extrabreit", "wins": 0, "level": 12, "spacer": 0.045, "wide": 0.05},
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
			{"name": "Gold", "wins": 0, "color": Color(0.85, 0.65, 0.2)},
			{"name": "Bronze", "wins": 0, "color": Color(0.6, 0.4, 0.16)},
			{"name": "Neongrün", "wins": 0, "color": Color(0.45, 1.0, 0.1)},
			{"name": "Chrom", "wins": 0, "color": Color(0.9, 0.9, 0.92), "chrome": true},
		],
	},
	"spoiler": {
		"label": "Spoiler",
		"options": [
			{"name": "Keiner", "wins": 0},
			{"name": "Lippe", "wins": 0},
			{"name": "GT-Flügel", "wins": 0},
			{"name": "Monster-Flügel", "wins": 0},
			{"name": "Entenbürzel", "wins": 0},
			{"name": "Street-Flügel", "wins": 0},
			{"name": "Schwanenhals", "wins": 0},
			{"name": "Doppeldecker", "wins": 0},
			{"name": "Dachspoiler", "wins": 0},
			{"name": "Bügelflügel", "wins": 0},
		],
	},
	# flare: Kotflügel verbreitert; die Anbauteile baut car_builder._bodykit
	"bodykit": {
		"label": "Bodykit",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Seitenschweller", "wins": 0},
			{"name": "Breitbau", "wins": 0, "flare": true},
			{"name": "Street", "wins": 0},
			{"name": "Rallye", "wins": 0},
			{"name": "Racing", "wins": 0},
			{"name": "Breitbau Racing", "wins": 0, "flare": true},
		],
	},
	"hood": {
		"label": "Motorhaube",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Lufthutze", "wins": 0},
			{"name": "Lamellen", "wins": 0},
			{"name": "NACA-Einlass", "wins": 0},
			{"name": "Doppelhutze", "wins": 0},
			{"name": "Carbon", "wins": 0},
			{"name": "Carbon mit Hutze", "wins": 0},
		],
	},
	"exhaust": {
		"label": "Auspuff",
		"options": [
			{"name": "Serie", "wins": 0},
			{"name": "Sport", "wins": 0},
			{"name": "Doppelrohr", "wins": 0},
			{"name": "Ovalrohr", "wins": 0},
			{"name": "Titan", "wins": 0},
			{"name": "Rennauspuff", "wins": 0},
		],
	},
	"vinyl": {
		"label": "Folierung",
		# Seit 2.36 Kategorien wie in NFS Underground (Garage > Tuning > Optik > Folierung: erst die Kategorie, dann
		# die Motive darin). Vorn die einfarbigen (Farbe unter Folienfarbe), hinten Spezial und Unikate mit festen
		# Farben. Jedes Motiv nennt seine Kategorie ("group"), darin stehen sie nach Level. "Keins" steht vor den
		# Kategorien. hidden: ausgeblendet (nicht in der Garage, nicht in der Level-Liste); der Platz bleibt, weil
		# Spielstände den Index speichern, und ohne "art" fährt ein Auto, das es noch trägt, ohne Folie.
		"groups": [
			{"id": "stripes", "label": "Streifen", "desc": "Klassische Streifen über Haube, Dach und Flanken."},
			{"id": "flames", "label": "Flammen", "desc": "Flammen in einer Farbe: von vorn, vom Schweller oder nur als Umriss."},
			{"id": "tribal", "label": "Tribal", "desc": "Geschwungene Klingen und Tigerstreifen."},
			{"id": "racing", "label": "Rennsport", "desc": "Startnummer, Zielflagge und Tempo-Grafiken wie auf der Rennstrecke."},
			{"id": "special", "label": "Spezial", "desc": "Muster und Effekte in eigenen Farben."},
			{"id": "unique", "label": "Unikate", "desc": "Einzelstücke mit Motiv, in eigenen Farben."},
		],
		"options": [
			{"name": "Keins", "wins": 0},
			{"name": "Rennstreifen", "wins": 0, "group": "stripes"},
			{"name": "Seitenstreifen", "wins": 0, "group": "stripes"},
			{"name": "Mittelstreifen", "wins": 0, "group": "stripes"},
			{"name": "Zweifarbig", "wins": 0, "group": "stripes"},
			{"name": "Flankenband", "wins": 0, "group": "stripes"},
			{"name": "Haube und Heck", "wins": 0, "group": "stripes"},
			{"name": "Kontrastdach", "wins": 0, "group": "stripes"},
			{"name": "Rallye", "wins": 0, "group": "stripes"},
			# Seit 2.33: Vinyls mit Motiv (assets/vinyls/<art>.svg, oben die Flanke, unten die Draufsicht). Sie liegen in
			# Koordinaten relativ zu Länge, Breite und Gürtellinie des Autos und passen so auf jedes Auto (Shader
			# car_paint). tint: einfarbige Maske in der Folienfarbe; mirror: rechts gespiegelt, damit das Motiv auf beiden
			# Seiten nach hinten läuft (aus bei Schrift, die sonst rechts spiegelverkehrt stünde).
			{"name": "Speedlines", "wins": 0, "level": 2, "art": "speedlines", "tint": true, "mirror": true, "group": "racing"},
			{"name": "Tribal", "wins": 0, "level": 3, "art": "tribal", "tint": true, "mirror": true, "group": "tribal"},
			{"name": "Splitter", "wins": 0, "level": 4, "art": "splitter", "tint": true, "mirror": true, "group": "racing"},
			{"name": "Sakura", "wins": 0, "level": 5, "art": "sakura", "mirror": true, "group": "unique"},
			{"name": "Tiger", "wins": 0, "level": 6, "art": "tiger", "tint": true, "mirror": true, "group": "tribal"},
			{"name": "Zielflagge", "wins": 0, "level": 7, "art": "checker", "tint": true, "mirror": true, "group": "racing"},
			# bis 2.35 "Flammen": die bunten Flammen stehen seit 2.36 unter Unikate, die Kategorie Flammen ist einfarbig
			{"name": "Hot Rod", "wins": 0, "level": 8, "art": "flames", "mirror": true, "group": "unique"},
			{"name": "Pixeltarn", "wins": 0, "level": 9, "art": "camo", "mirror": true, "group": "special"},
			{"name": "Blitze", "wins": 0, "level": 10, "art": "bolts", "mirror": true, "group": "special"},
			{"name": "Welle", "wins": 0, "level": 11, "art": "wave", "mirror": true, "group": "unique"},
			{"name": "Graffiti", "wins": 0, "level": 12, "art": "graffiti", "mirror": false, "group": "unique"},
			{"name": "Hexgitter", "wins": 0, "level": 13, "art": "hex", "mirror": true, "group": "special"},
			{"name": "Platine", "wins": 0, "level": 14, "art": "circuit", "mirror": true, "group": "special"},
			{"name": "Farbbomben", "wins": 0, "level": 15, "art": "splatter", "mirror": true, "group": "special"},
			{"name": "Koi", "wins": 0, "level": 16, "art": "koi", "mirror": true, "group": "unique"},
			{"name": "Rising Sun", "wins": 0, "level": 17, "art": "sunrays", "mirror": true, "group": "special"},
			{"name": "Glitch", "wins": 0, "level": 18, "art": "glitch", "mirror": true, "group": "special"},
			# 26, 27, 28 und 31 (Kitsune, Oni, Drache, Mecha: Masken und Köpfe) seit 2.36 ausgeblendet, siehe oben
			{"name": "Keins", "wins": 0, "hidden": true},
			{"name": "Keins", "wins": 0, "hidden": true},
			{"name": "Keins", "wins": 0, "hidden": true},
			{"name": "Engelsflügel", "wins": 0, "level": 24, "art": "wings", "mirror": true, "group": "unique"},
			{"name": "Einheit 07", "wins": 0, "level": 26, "art": "unit07", "mirror": false, "group": "unique"},
			{"name": "Keins", "wins": 0, "hidden": true},
			{"name": "Lichtengel", "wins": 0, "level": 30, "art": "angel", "mirror": true, "group": "unique"},
			{"name": "Prisma", "wins": 0, "level": 35, "art": "prism", "mirror": true, "group": "special"},
			# seit 2.36: einfarbige Flammen, ein Tribal und zwei Rennsport-Motive
			{"name": "Feuerzungen", "wins": 0, "level": 2, "art": "flamelicks", "tint": true, "mirror": true, "group": "flames"},
			{"name": "Startnummer", "wins": 0, "level": 4, "art": "racenumber", "tint": true, "mirror": false, "group": "racing"},
			{"name": "Karo-Streifen", "wins": 0, "level": 9, "art": "checkstripe", "tint": true, "mirror": true, "group": "racing"},
			{"name": "Inferno", "wins": 0, "level": 19, "art": "inferno", "tint": true, "mirror": true, "group": "flames"},
			{"name": "Geisterflammen", "wins": 0, "level": 20, "art": "ghostflames", "tint": true, "mirror": true, "group": "flames"},
			{"name": "Aufwind", "wins": 0, "level": 22, "art": "updraft", "tint": true, "mirror": true, "group": "tribal"},
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
			{"name": "Gold", "wins": 0, "color": Color(0.85, 0.63, 0.2), "metal": true},
			{"name": "Neongrün", "wins": 0, "color": Color(0.45, 1.0, 0.1)},
			{"name": "Pink", "wins": 0, "color": Color(0.98, 0.12, 0.6)},
			{"name": "Carbon", "wins": 0, "color": Color(0.07, 0.07, 0.08), "carbon": true},
		],
	},
	"neon": {
		"label": "Unterbodenneon",
		"options": [
			{"name": "Aus", "wins": 0},
			{"name": "Blau", "wins": 0, "color": Color(0.1, 0.4, 1.0)},
			{"name": "Pink", "wins": 0, "color": Color(1.0, 0.1, 0.7)},
			{"name": "Grün", "wins": 0, "color": Color(0.1, 1.0, 0.3)},
			{"name": "Rot", "wins": 0, "color": Color(1.0, 0.08, 0.05)},
			{"name": "Lila", "wins": 0, "color": Color(0.55, 0.1, 1.0)},
			{"name": "Weiß", "wins": 0, "color": Color(0.85, 0.9, 1.0)},
			{"name": "Orange", "wins": 0, "color": Color(1.0, 0.45, 0.05)},
			{"name": "Türkis", "wins": 0, "color": Color(0.05, 1.0, 0.85)},
		],
	},
	"tint": {
		"label": "Scheiben",
		"options": [
			{"name": "Klar", "wins": 0, "color": Color(0.03, 0.04, 0.06)},
			{"name": "Getönt", "wins": 0, "color": Color(0.012, 0.012, 0.016)},
			{"name": "Dunkel", "wins": 0, "color": Color(0.003, 0.003, 0.004)},
			{"name": "Blau verspiegelt", "wins": 0, "color": Color(0.02, 0.07, 0.2)},
		],
	},
	# Scheinwerfer: Lichtfarbe der Frontlichter und des Lichtkegels
	"lights": {
		"label": "Scheinwerfer",
		"options": [
			{"name": "Serie", "wins": 0, "color": Color(1.0, 0.97, 0.88)},
			{"name": "Xenon", "wins": 0, "color": Color(0.82, 0.9, 1.0)},
			{"name": "Gelb", "wins": 0, "color": Color(1.0, 0.82, 0.35)},
			{"name": "Eisblau", "wins": 0, "color": Color(0.55, 0.72, 1.0)},
		],
	},
	"engine": {
		"label": "Motor",
		"options": [
			{"name": "Serie", "wins": 0, "accel": 1.0, "top": 1.0},
			{"name": "Stufe 1", "wins": 1, "level": 3, "accel": 1.08, "top": 1.04},
			{"name": "Stufe 2", "wins": 3, "level": 6, "accel": 1.16, "top": 1.08},
			{"name": "Stufe 3", "wins": 6, "level": 11, "accel": 1.25, "top": 1.12},
		],
	},
	"nitro": {
		"label": "Nitro",
		"options": [
			{"name": "Serie", "wins": 0, "power": 1.0, "capacity": 1.0},
			{"name": "Stufe 1", "wins": 2, "level": 4, "power": 1.2, "capacity": 1.25},
			{"name": "Stufe 2", "wins": 5, "level": 10, "power": 1.4, "capacity": 1.5},
		],
	},
	# Turbo: mehr Schub und etwas mehr Endtempo, lauteres Ladedruck-Zischen
	"turbo": {
		"label": "Turbo",
		"options": [
			{"name": "Serie", "wins": 0, "accel": 1.0, "top": 1.0},
			{"name": "Stufe 1", "wins": 2, "level": 5, "accel": 1.06, "top": 1.03},
			{"name": "Stufe 2", "wins": 4, "level": 8, "accel": 1.12, "top": 1.06},
			{"name": "Stufe 3", "wins": 7, "level": 14, "accel": 1.18, "top": 1.09},
		],
	},
	# Fahrwerk: mehr Grip, direktere Lenkung, Karosserie tiefer (drop in Metern)
	"suspension": {
		"label": "Fahrwerk",
		"options": [
			{"name": "Serie", "wins": 0, "grip": 0.0, "steer": 0.0, "drop": 0.0},
			{"name": "Sport", "wins": 1, "level": 2, "grip": 1.5, "steer": 0.06, "drop": 0.025},
			{"name": "Gewinde", "wins": 3, "level": 7, "grip": 3.0, "steer": 0.12, "drop": 0.045},
			{"name": "Rennfahrwerk", "wins": 6, "level": 12, "grip": 4.5, "steer": 0.18, "drop": 0.06},
		],
	},
	# Reifen: mehr Grip in Kurven, Rennreifen kleben, driften dafür etwas unwilliger
	"tires": {
		"label": "Reifen",
		"options": [
			{"name": "Serie", "wins": 0, "grip": 0.0, "drift": 0.0},
			{"name": "Sport", "wins": 1, "level": 2, "grip": 1.0, "drift": 0.0},
			{"name": "Semi-Slicks", "wins": 4, "level": 9, "grip": 2.5, "drift": -0.04},
			{"name": "Rennreifen", "wins": 6, "level": 13, "grip": 4.0, "drift": -0.08},
		],
	},
}

## "spur" (seit 2.37) steht hinten: die Gegner würfeln ihr Tuning in dieser Reihenfolge (race.gd), so bleiben ihre übrigen
## Teile gleich
const PART_ORDER := ["paint", "finish", "rims", "rimcol", "rimsize", "spoiler", "bodykit", "hood", "exhaust", "vinyl", "vinylcol", "neon", "tint",
	"lights", "engine", "turbo", "nitro", "suspension", "tires", "spur"]
## Tuning-Menü wie in NFS: erst Optik oder Leistung, dann die Kategorie, dann das Teil
const PART_GROUPS := {"optik": ["paint", "finish", "rims", "rimcol", "rimsize", "spur", "spoiler", "bodykit", "hood", "exhaust", "vinyl", "vinylcol",
	"neon", "tint", "lights"],
	"leistung": ["engine", "turbo", "nitro", "suspension", "tires"]}


## Option der Kategorie Zoll mit dieser festen Größe (13" bis 24"), -1 wenn es sie nicht gibt
static func rimsize_index(inch: int) -> int:
	var opts: Array = PARTS["rimsize"]["options"]
	for i in opts.size():
		if int(opts[i].get("abs", 0)) == inch:
			return i
	return -1


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
	# seit 2.36 entworfen (track_design.gd, LAYOUTS["frankfurt"]): Hochhausschlucht, Theatertunnel, Mainufer, Brücke,
	# Gasse durch Alt-Sachsenhausen
	{"name": "Bankenviertel-Sprint", "town": "Frankfurt am Main", "greet": "EI GUDE!", "shops": ["APFELWEIN", "EBBELWOI", "GRIE SOSS", "HANDKÄS", "BÖRSENCAFÉ", "SACHSENHAUSEN", "MESSE-IMBISS", "BETHMÄNNCHEN"], "region": "Kreisfreie Stadt", "geo": Vector2(50.1109, 8.6821), "mood": "neon",  "type": "sprint", "tier": 1, "seed": 11, "layout": "frankfurt",
		"districts": {"downtown": 0.45, "shops": 0.3, "chinatown": 0.25}},
	# seit 2.36 entworfen (LAYOUTS["muenchen"]): Ludwigstraße durchs Siegestor, Englischer Garten, Isar, Friedensengel
	{"name": "Prachtallee-Sprint", "town": "München", "greet": "SERVUS!", "shops": ["WEISSWURST", "BIERGARTEN", "BREZN", "LEBERKAS", "OBATZDA", "TRACHTEN", "BRÄUSTÜBERL", "DIRNDL"], "region": "Landeshauptstadt", "geo": Vector2(48.1351, 11.582), "mood": "daemmerung",  "type": "sprint", "tier": 1, "seed": 23, "layout": "muenchen",
		"districts": {"boulevard": 0.45, "downtown": 0.25, "shops": 0.3}},
	# seit 2.36 entworfen (LAYOUTS["hafenrunde"]): Reeperbahn, Landungsbrücken, Speicherstadt, Köhlbrandbrücke
	{"name": "Hafenrunde", "town": "Hamburg", "greet": "MOIN MOIN!", "shops": ["FISCHBRÖTCHEN", "LABSKAUS", "FRANZBRÖTCHEN", "HAFENKNEIPE", "SCHIFFSBEDARF", "KIEZ-IMBISS", "SEEMANNSHEIM", "ALSTERCAFÉ"], "region": "Freie und Hansestadt Hamburg", "geo": Vector2(53.5459, 9.9665), "mood": "regen",  "type": "sprint", "tier": 2, "seed": 42, "layout": "hafenrunde",
		"districts": {"industrial": 0.45, "shops": 0.35, "residential": 0.2}},
	# seit 2.36 entworfen (LAYOUTS["dortmund"]): Hochofen, Schnellstraße mit Tunnel, Hochstraße übers Gleisfeld, Wall
	{"name": "Schnellstraßen-Sprint", "town": "Dortmund", "greet": "GLÜCK AUF!", "shops": ["CURRYWURST", "BÜDCHEN", "TRINKHALLE", "PILSSTUBE", "ZECHENGRILL", "STAHLWERK", "PÜTTCAFÉ"], "region": "Kreisfreie Stadt", "geo": Vector2(51.5136, 7.4653), "mood": "natrium",  "type": "sprint", "tier": 3, "seed": 7, "layout": "dortmund",
		"districts": {"highway": 0.4, "downtown": 0.2, "industrial": 0.2, "boulevard": 0.2}},
	# seit 2.36 entworfen (track_design.gd, LAYOUTS["koeln"]): Rheinufer mit Tunnel, Spitzkehre vor dem Dom, Ring
	{"name": "Innenstadtring", "town": "Köln", "greet": "KÖLLE ALAAF!", "shops": ["KÖLSCH", "BRAUHAUS", "HALVER HAHN", "BÜDCHEN", "KARNEVAL", "DOMCAFÉ", "RHEINTERRASSE", "JECKENLADEN"], "region": "Kreisfreie Stadt", "geo": Vector2(50.9375, 6.9603), "mood": "mitternacht",  "type": "circuit", "tier": 1, "laps": 2, "seed": 101, "layout": "koeln",
		"districts": {"downtown": 0.35, "boulevard": 0.25, "chinatown": 0.4}},
	# seit 2.36 entworfen (LAYOUTS["bremen"]): Schlachte an der Weser, Brücke über das Hafenbecken, Kai, Schnoor mit Roland
	{"name": "Hafenring", "town": "Bremen", "greet": "MOIN!", "shops": ["SCHNOOR-CAFÉ", "KAFFEERÖSTEREI", "KLABEN", "KNIPP", "HAFENSCHÄNKE", "STADTMUSIKANTEN", "WESERBLICK"], "region": "Freie Hansestadt Bremen", "geo": Vector2(53.0793, 8.8017), "mood": "regen",  "type": "circuit", "tier": 2, "laps": 2, "seed": 202, "layout": "bremen",
		"districts": {"industrial": 0.5, "highway": 0.25, "shops": 0.25}},
	# seit 2.36 entworfen (LAYOUTS["stuttgart"]): Kulturmeile im Kessel, Weinsteige mit zwei Kehren, Kamm am Fernsehturm
	{"name": "Nachtschicht", "town": "Stuttgart", "greet": "GRÜSS GOTT!", "shops": ["MAULTASCHEN", "BREZEL", "BESENWIRTSCHAFT", "SPÄTZLE", "WEINSTUBE", "KEHRWOCHE", "VIERTELE"], "region": "Landeshauptstadt", "geo": Vector2(48.7758, 9.1829), "mood": "mitternacht",  "type": "circuit", "tier": 3, "laps": 2, "seed": 303, "layout": "stuttgart",
		"districts": {"highway": 0.3, "boulevard": 0.3, "downtown": 0.4}},
	# seit 2.36 entworfen (LAYOUTS["hafen_drift"]): Containerterminal an der Elbe; corners bleibt für die Punkte-Ziele
	{"name": "Hafen-Drift", "town": "Hamburg", "greet": "MOIN MOIN!", "shops": ["FISCHBRÖTCHEN", "HAFENKNEIPE", "SCHIFFSBEDARF", "KAFFEEKLAPPE", "CONTAINERGRILL", "ELBBLICK"], "region": "Freie und Hansestadt Hamburg", "geo": Vector2(53.5459, 9.9665), "mood": "nebel",  "type": "drift", "tier": 2, "laps": 2, "seed": 502, "corners": 12, "layout": "hafen_drift",
		"districts": {"industrial": 0.7, "highway": 0.3}},
	# seit 2.36 entworfen (LAYOUTS["stadion_drift"]): Bogen um die Arena, Parkplatzwechsel, Parkdeck mit Kehre oben;
	# corners bleibt für die Punkte-Ziele
	{"name": "Stadion-Drift", "town": "Gelsenkirchen", "greet": "GLÜCK AUF!", "shops": ["TRINKHALLE", "POMMESBUDE", "KUMPEL-KIOSK", "STADIONGRILL", "ZECHENSTUBE", "FANSHOP"], "region": "Kreisfreie Stadt", "geo": Vector2(51.5177, 7.0857), "mood": "natrium",  "type": "drift", "tier": 3, "laps": 2, "seed": 603, "corners": 14, "layout": "stadion_drift",
		"districts": {"downtown": 0.4, "boulevard": 0.6}},
	# --- neu: Drag-Rennen (geradeaus, Handschaltung) und weitere Strecken; hinten angehängt, damit gespeicherte
	# Event-Nummern gültig bleiben
	{"name": "Hafenmeile", "town": "Kiel", "region": "Landeshauptstadt", "geo": Vector2(54.3233, 10.1228), "mood": "nebel",  "type": "drag", "tier": 1, "seed": 701, "segments": 8, "max_turn": 4.0,
		"districts": {"industrial": 0.6, "shops": 0.4}},
	{"name": "Neon-Gerade", "town": "Leipzig", "region": "Kreisfreie Stadt", "geo": Vector2(51.3397, 12.3731), "mood": "kiez",  "type": "drag", "tier": 2, "seed": 702, "segments": 10, "max_turn": 6.0,
		"districts": {"downtown": 0.5, "shops": 0.5}},
	{"name": "Schnellstraßen-Drag", "town": "Hockenheim", "region": "Rhein-Neckar-Kreis", "geo": Vector2(49.322, 8.547), "mood": "mitternacht",  "type": "drag", "tier": 3, "seed": 703, "segments": 13, "max_turn": 5.0,
		"districts": {"highway": 0.6, "boulevard": 0.4}},
	# seit 2.36 entworfen (LAYOUTS["heidelberg"]): Alte Brücke mit Brückentor, Altstadt, Schlossberg mit Kehre, Neckar
	{"name": "Altstadt-Hügel", "town": "Heidelberg", "greet": "HERZLICH WILLKOMMEN!", "shops": ["STUDENTENKUSS", "ALTSTADTCAFÉ", "UNI-KNEIPE", "SCHLOSSBLICK", "NECKARCAFÉ", "ANTIQUARIAT", "KARZER-BAR"], "region": "Kreisfreie Stadt", "geo": Vector2(49.3988, 8.6724), "mood": "daemmerung",  "type": "sprint", "tier": 2, "seed": 61, "layout": "heidelberg",
		"districts": {"residential": 0.45, "shops": 0.55}},
	# seit 2.36 entworfen (LAYOUTS["rostock"]): Kröpeliner Tor, Stadthafen, Warnowtunnel, Überseehafen, Leuchtturm
	{"name": "Hafen-Sprint", "town": "Rostock", "greet": "MOIN!", "shops": ["FISCHKUTTER", "BACKFISCH", "MATJES", "SANDDORN", "HAFENKIOSK", "WARNOW-IMBISS", "LEUCHTTURMCAFÉ"], "region": "Hanse- und Universitätsstadt", "geo": Vector2(54.0924, 12.0991), "mood": "nebel",  "type": "sprint", "tier": 3, "seed": 77, "layout": "rostock",
		"districts": {"industrial": 0.5, "highway": 0.3, "residential": 0.2}},
	# seit 2.36 entworfen (LAYOUTS["nuernberg"]): Ring an der Stadtmauer, Laufer Tor, Burgberg mit Kaiserburg, Pegnitz
	{"name": "Altstadtring", "town": "Nürnberg", "greet": "GRÜSS GOTT!", "shops": ["LEBKUCHEN", "BRATWURSTSTUBE", "SCHÄUFELE", "SPIELWAREN", "BURGCAFÉ", "PEGNITZ-STUBE", "ZWETSCHGENMÄNNLE"], "region": "Kreisfreie Stadt", "geo": Vector2(49.4521, 11.0767), "mood": "mitternacht",  "type": "circuit", "tier": 2, "laps": 2, "seed": 131, "layout": "nuernberg",
		"districts": {"residential": 0.5, "boulevard": 0.3, "downtown": 0.2}},
	# --- Orts-Strecken: echte Straßenverläufe (OpenStreetMap, tools/osm_city.py), Wahrzeichen an ihrem Platz.
	# city = Schlüssel in city_data.gd, town = Ortsschild, shops = Ladennamen der Stadt, station = Haltestelle am Bahnübergang
	# greet (seit 2.46): Gruß in Mundart unter dem Ortsschild; shops haben seit 2.46 auch die entworfenen Städte
	{"name": "Aachen Grabenring", "geo": Vector2(50.7753, 6.0839), "mood": "regen",  "type": "circuit", "tier": 2, "laps": 2, "seed": 801, "city": "aachen", "town": "Aachen", "greet": "WILLKOMMEN IN OCHE!",
		"shops": ["PRINTEN", "ÖCHER BRAUHAUS", "CAMPUS BAR", "DOMCAFÉ", "PONTSTRASSE", "THERMALBAD", "MENSA", "KAISERCAFÉ"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "campus_de": 0.2},
		"desc": "Über den Grabenring am SuperC der RWTH, am Elisenbrunnen und am Theater vorbei. In der Mitte Dom und Rathaus."},
	{"name": "Würzburg Mainufer", "geo": Vector2(49.7913, 9.9534), "mood": "daemmerung",  "type": "sprint", "tier": 3, "seed": 802, "city": "wuerzburg", "town": "Würzburg", "greet": "SERVUS!",
		"shops": ["BOCKSBEUTEL", "FRANKENWEIN", "BRÜCKENSCHOPPEN", "WEINHAUS", "KILIANI", "MAINFRANKEN", "SCHOPPEN"],
		"districts": {"altstadt_de": 0.35, "innenstadt_de": 0.45, "vorstadt_de": 0.2},
		"desc": "Rennweg an der Residenz, über die Ludwigsbrücke, unter der Festung Marienberg entlang, über die Friedensbrücke zum Alten Kranen."},
	{"name": "Bad Kissingen Kurmeile", "geo": Vector2(50.2, 10.077), "mood": "daemmerung",  "type": "sprint", "tier": 1, "seed": 803, "city": "badkissingen", "town": "Bad Kissingen", "greet": "GRÜSS GOTT!",
		"shops": ["KURCAFÉ", "KURAPOTHEKE", "RAKOCZY", "TRINKHALLE", "KONZERTCAFÉ", "KURHAUS", "SALINE"],
		"districts": {"kurviertel_de": 0.55, "innenstadt_de": 0.2, "vorstadt_de": 0.25},
		"desc": "Vom Regentenbau am Kurgarten über die Saale, dann am Fluss entlang zum Gradierbau der Oberen Saline."},
	{"name": "Tauberbischofsheim Altstadt", "geo": Vector2(49.6236, 9.6627), "mood": "nebel",  "type": "circuit", "tier": 1, "laps": 3, "seed": 804, "city": "tbb", "town": "Tauberbischofsheim", "greet": "GRÜSS GOTT!",
		"shops": ["FECHTCLUB", "TAUBERWEIN", "FECHTERSTADT", "TAUBERTAL", "LIOBA CAFÉ", "SCHLOSSCAFÉ"],
		"districts": {"altstadt_de": 0.6, "vorstadt_de": 0.4},
		"desc": "Rund um die Altstadt der Fechterstadt, Türmersturm, Rathaus und St. Martin immer im Blick."},
	{"name": "Hammelburg Saaleck", "geo": Vector2(50.1162, 9.8906), "mood": "daemmerung",  "type": "sprint", "tier": 2, "seed": 805, "city": "hammelburg", "town": "Hammelburg", "greet": "GRÜSS GOTT!",
		"station": "HAMMELBURG",
		"shops": ["WEINSTADT", "HÄCKERWIRTSCHAFT", "SAALETAL", "WEINFEST", "WINZERSTUBE", "STADTSCHÄNKE"],
		"districts": {"altstadt_de": 0.5, "vorstadt_de": 0.5},
		"desc": "Über die Bahnlinie in die Altstadt, am Rathaus mit Marktbrunnen vorbei, über die Saale hinauf zu Schloss Saaleck."},
	{"name": "Berlin Kreuzberg", "geo": Vector2(52.4990, 13.4300), "mood": "kiez", "type": "circuit", "tier": 3, "laps": 2,
		"seed": 806, "city": "kreuzberg", "town": "Berlin", "greet": "NA, ALLET JUT?",
		"shops": ["SPÄTI", "DÖNER", "CURRYWURST", "PLATTENLADEN", "VEGAN", "SHISHA BAR", "KIEZKNEIPE", "FAHRRADLADEN", "TATTOO"],
		"districts": {"kiez_de": 0.7, "innenstadt_de": 0.3},
		"desc": "Unter der Hochbahn der U1 durch die Skalitzer Straße, über die Oberbaumbrücke, an der East Side Gallery entlang und über die Schillingbrücke zurück zum Kotti."},
	# Waldstrecke (seit 2.29): Landstraße durch den Schwarzwald, keine Häuser, dichter Wald, Kuppen
	{"name": "Freudenstadt Waldpass", "town": "Freudenstadt", "greet": "GRÜSS GOTT!", "region": "Landkreis Freudenstadt", "geo": Vector2(48.4633, 8.4111),
		"mood": "nebel", "type": "sprint", "tier": 2, "seed": 901, "segments": 24, "max_turn": 62.0, "forest": true,
		"crests": [[0.12, 0.3, 8.0], [0.42, 0.58, 6.0], [0.68, 0.88, 10.0]],
		"districts": {"wald": 1.0},
		"desc": "Landstraße durch den Schwarzwald: enge Kurven zwischen Tannen, Kuppen mit Sprung, ein Bahnübergang. Nachts nur Scheinwerfer und Leitpfosten."},
	# Driftberg (seit 2.32, seit 2.36 als entworfene Passstraße statt Stern aus 16 gleichen Kehren): Start und Ziel im
	# Tal, Kehrentreppe hinauf, Kamm, Gipfel mit Aussichtspunkt, Felstunnel, schnelle Abfahrt (track_design.gd,
	# LAYOUTS["driftberg"]: Stützpunkte, Höhen, Berg). Beide Ausfahrten liegen unten im Tal.
	# Außerhalb der Karriere, immer offen ("free"); in der Welt mit zwei Ausfahrten zum Durchfahren.
	# corners bleibt für die Punkte-Ziele (Catalog.drift_targets).
	{"name": "Driftberg", "town": "Harz", "greet": "GLÜCK AUF!", "region": "Landkreis Goslar", "geo": Vector2(51.80, 10.62),
		"mood": "mitternacht", "type": "drift", "tier": 2, "laps": 2, "seed": 1207, "corners": 16, "free": true,
		"forest": true, "layout": "driftberg",
		"bulges": {}, "districts": {"wald": 1.0},
		"desc": "Passstraße im Harz: Kehrentreppe den Hang hinauf, Schlangenlinie über den Kamm, Aussichtspunkt am Gipfel, Felstunnel unter dem Sendeturm und eine schnelle Abfahrt ins Tal. Ketten durch die Kehren geben am meisten."},
]

const EVENT_TYPES := {
	"sprint": {"label": "Sprint", "goal": "Als Erster von A nach B.", "desc": "Von A nach B gegen 3 Gegner. Gabelungen und Abkürzungen: du entscheidest. Rauten: 1 ohne Verkehr, 2 wenig, 3 voll."},
	"circuit": {"label": "Rundkurs", "goal": "Nach %d Runden als Erster über die Linie.", "desc": "Rundkurs gegen 3 Gegner. Wer die beste Linie findet, gewinnt. Rauten: 1 ohne Verkehr, 2 wenig, 3 voll."},
	"drift": {"label": "Drift", "goal": "Die meisten Driftpunkte: die Marke für Platz 1 steht am Start.", "desc": "Allein auf der Strecke. Querfahren gibt Punkte, Ketten geben Multiplikator, die markierten Außenspuren an der Bande zählen doppelt, ein Crash kostet die Kette."},
	"drag": {"label": "Drag", "goal": "Als Erster über die Linie: perfekt schalten, dem Verkehr ausweichen.", "desc": "Geradeaus gegen 3 Gegner, das Auto fährt wie auf Schienen. A/D wechselt die Spur, S schaltet hoch, X runter: im grünen Bereich perfekt. Zu lange im Begrenzer: Motorschaden. Crash mit Verkehr: Totalschaden."},
}
## Drag-Rennen sind seit 2.24 vorerst draußen (passten nicht, zu viel Umbau): die Events stehen weiter in RACES und
## der Code in player_car/track_builder/race bleibt, sie stehen nur in keiner Karriere-Stufe. Letzter Stand mit Drag
## in der Karriere: Git-Tag drag-2.23.
const TYPE_ORDER := ["sprint", "circuit", "drift"]
## Karriere in Stufen wie in NFSU2: alle Events einer Stufe sind gleichzeitig offen und in beliebiger Reihenfolge
## fahrbar. Seit 2.33 öffnet das Fahrer-Level eine Stufe ("level"): Erfahrung gibt es für Siege, aber auch fürs Driften,
## Springen und Duelle in der Welt. Bis 2.32 öffneten STAGE_WINS Siege in einer Stufe die nächste (bleibt für alte
## Spielstände offen). Jede Stufe mischt die Arten, die Schwierigkeit steigt von Stufe zu Stufe.
const STAGES := [
	{"name": "Einstieg", "level": 1, "events": ["Bankenviertel-Sprint", "Tauberbischofsheim Altstadt", "Bad Kissingen Kurmeile", "Innenstadtring"]},
	{"name": "Szene", "level": 3, "events": ["Prachtallee-Sprint", "Hafen-Drift", "Hammelburg Saaleck", "Altstadt-Hügel"]},
	{"name": "Hafen und Altstadt", "level": 7, "events": ["Hafenrunde", "Aachen Grabenring", "Hafenring", "Altstadtring", "Freudenstadt Waldpass"]},
	{"name": "Großstadt", "level": 12, "events": ["Berlin Kreuzberg", "Schnellstraßen-Sprint", "Stadion-Drift"]},
	{"name": "Finale", "level": 17, "events": ["Hafen-Sprint", "Nachtschicht", "Würzburg Mainufer"]},
]
## Siege, die eine Stufe öffnen: 3, bei Stufen mit nur drei Events 2 (eins darf man auslassen)
const STAGE_WINS := 3
## Alle Karriere-Events Stufe für Stufe (Reihenfolge der Liste in der Garage)
const CAREER := ["Bankenviertel-Sprint", "Tauberbischofsheim Altstadt", "Bad Kissingen Kurmeile", "Innenstadtring",
	"Prachtallee-Sprint", "Hafen-Drift", "Hammelburg Saaleck", "Altstadt-Hügel",
	"Hafenrunde", "Aachen Grabenring", "Hafenring", "Altstadtring", "Freudenstadt Waldpass",
	"Berlin Kreuzberg", "Schnellstraßen-Sprint", "Stadion-Drift",
	"Hafen-Sprint", "Nachtschicht", "Würzburg Mainufer"]
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


## Siege in Stufe s, die die nächste öffnen
static func stage_need(s: int) -> int:
	return mini(STAGE_WINS, STAGES[s]["events"].size() - 1)


## Fahrer-Titel: kommen mit dem Level, man wählt in der Garage unter "Fahrer" einen der freien. Er steht in der
## Garage. (2.33 hatte zu jedem Titel ein Emblem, seit 2.35 nicht mehr.)
const TITLES := [
	{"level": 1, "name": "Neuling"},
	{"level": 2, "name": "Ampelstarter"},
	{"level": 4, "name": "Kurvenkratzer"},
	{"level": 6, "name": "Nachtfahrer"},
	{"level": 8, "name": "Querfahrer"},
	{"level": 10, "name": "Lückenfinder"},
	{"level": 12, "name": "Schrauber"},
	{"level": 14, "name": "Ringjäger"},
	{"level": 16, "name": "Phantom"},
	{"level": 18, "name": "Drift-Samurai"},
	{"level": 20, "name": "Asphaltkönig"},
	{"level": 22, "name": "Fuchsgeist"},
	{"level": 24, "name": "Autobahn-Engel"},
	{"level": 26, "name": "Oni"},
	{"level": 28, "name": "Einheit Null"},
	{"level": 30, "name": "Drachenreiter"},
	{"level": 35, "name": "Legende"},
	{"level": 40, "name": "Ikone"},
	{"level": 50, "name": "Unsterblich"},
]
const LEVEL_MAX := 99


## Erfahrung für einen Platz im Rennen (ohne Stilpunkte): 1. Platz 3000, 2. 1600, 3. 900, sonst 400, je Stufe mehr
## (Stufe 2 x1,35, Stufe 3 x1,7). Der erste Sieg eines Events gibt die Hälfte dazu.
static func race_xp(tier: int, place: int, first_win := false) -> int:
	var base: int = [400, 3000, 1600, 900][place if place >= 1 and place <= 3 else 0]
	var k: float = [1.0, 1.0, 1.35, 1.7][clampi(tier, 0, 3)]
	return int(round(base * k * (1.5 if first_win and place == 1 else 1.0) / 50.0)) * 50


## Was Level l freischaltet: [{kind, name, ...}] mit kind "stage" (index), "car" (id), "part" (cat, index), "vinyl"
## (index), "title" (index). Level-Liste in der Garage und Meldung beim Aufstieg.
static func level_rewards(l: int) -> Array:
	var out := []
	for s in STAGES.size():
		if s > 0 and int(STAGES[s]["level"]) == l:
			out.append({"kind": "stage", "index": s, "name": STAGES[s]["name"]})
	for id in CAR_ORDER:
		if int(CARS[id]["unlock"].get("level", 0)) == l:
			out.append({"kind": "car", "id": id, "name": CARS[id]["name"]})
	for t in TITLES.size():
		if int(TITLES[t]["level"]) == l and l > 1:
			out.append({"kind": "title", "index": t, "name": TITLES[t]["name"]})
	for cat in PART_ORDER:
		var opts: Array = PARTS[cat]["options"]
		for i in opts.size():
			if int(opts[i].get("level", 0)) == l and not opts[i].get("hidden", false):
				out.append({"kind": "vinyl" if cat == "vinyl" else "part", "cat": cat, "index": i, "name": opts[i]["name"]})
	return out


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
