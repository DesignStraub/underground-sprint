class_name SignIcons
extends RefCounted
## Piktogramme und ausgedachte Logos für Ladenschilder (seit 2.29; davor stand auf jedem Schild nur Text). Alles als
## kleine SVG-Zeichnung (64×64, weiß) im Code, beim ersten Gebrauch zu einer Textur mit Mipmaps gerastert. Gefärbt wird
## über die Materialfarbe, so passt dasselbe Zeichen auf hellen und dunklen Schildern.

const S := "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64' width='128' height='128'><g fill='#fff' stroke='#fff' stroke-linecap='round' stroke-linejoin='round' stroke-width='0'>%s</g></svg>"

## Ladenart -> Zeichen
const ICONS := {
	"brezel": "<path d='M20 46 C4 42 6 16 21 15 C31 14 34 26 32 35 C30 26 33 14 43 15 C58 16 60 42 44 46 M21 50 L43 28 M43 50 L21 28' fill='none' stroke-width='6'/>",
	"schere": "<circle cx='19' cy='48' r='8' fill='none' stroke-width='5'/><circle cx='45' cy='48' r='8' fill='none' stroke-width='5'/><path d='M24 41 L46 6 M40 41 L18 6' fill='none' stroke-width='5'/>",
	"beil": "<path d='M6 12 H44 V38 H14 Q6 38 6 30 Z'/><rect x='44' y='21' width='16' height='8' rx='3'/>",
	"pizza": "<path fill-rule='evenodd' d='M32 60 L8 16 Q32 4 56 16 Z M23 22 a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0 Z M34 32 a4 4 0 1 0 8 0 a4 4 0 1 0 -8 0 Z M27 42 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 Z'/><path d='M5 12 Q32 -1 59 12' fill='none' stroke-width='5'/>",
	"doener": "<path d='M32 3 V61' fill='none' stroke-width='4'/><path d='M16 10 H48 L42 50 H22 Z'/><path d='M14 58 H50' fill='none' stroke-width='5'/>",
	"burger": "<path d='M9 27 Q9 9 32 9 Q55 9 55 27 Z'/><rect x='6' y='31' width='52' height='6' rx='3'/><path d='M9 41 H55 Q55 54 45 54 H19 Q9 54 9 41 Z'/>",
	"klee": "<circle cx='23' cy='21' r='10'/><circle cx='41' cy='21' r='10'/><circle cx='23' cy='39' r='10'/><circle cx='41' cy='39' r='10'/><path d='M32 32 Q36 50 46 60' fill='none' stroke-width='5'/>",
	"flasche": "<path d='M27 3 H37 V16 Q47 22 47 32 V60 H17 V32 Q17 22 27 16 Z'/>",
	"eis": "<circle cx='32' cy='19' r='14'/><path d='M18 27 L32 61 L46 27 Z'/>",
	"tasse": "<path d='M8 24 H46 V40 Q46 56 27 56 Q8 56 8 40 Z'/><path d='M46 29 Q59 28 57 39 Q55 47 44 45' fill='none' stroke-width='5'/><path d='M19 6 Q15 12 19 17 M29 6 Q25 12 29 17 M39 6 Q35 12 39 17' fill='none' stroke-width='3'/>",
	"diamant": "<path fill-rule='evenodd' d='M16 10 H48 L60 24 L32 58 L4 24 Z M12 25 H52 L32 50 Z'/>",
	"euro": "<path d='M46 17 Q40 10 32 10 Q15 10 15 32 Q15 54 32 54 Q40 54 46 47' fill='none' stroke-width='6'/><path d='M6 27 H34 M6 37 H32' fill='none' stroke-width='5'/>",
	"horn": "<path d='M6 42 Q6 18 31 18 Q53 18 53 34 Q53 47 40 47 Q29 47 29 37 Q29 28 38 28' fill='none' stroke-width='5'/><path d='M50 31 L61 21 V47 Z'/><circle cx='8' cy='44' r='5'/>",
	"brille": "<circle cx='17' cy='36' r='11' fill='none' stroke-width='5'/><circle cx='47' cy='36' r='11' fill='none' stroke-width='5'/><path d='M28 33 Q32 28 36 33 M6 33 L3 22 M58 33 L61 22' fill='none' stroke-width='4'/>",
	"blume": "<circle cx='32' cy='12' r='9'/><circle cx='45' cy='22' r='9'/><circle cx='40' cy='37' r='9'/><circle cx='24' cy='37' r='9'/><circle cx='19' cy='22' r='9'/><path d='M32 40 V62 M32 54 Q24 48 18 52' fill='none' stroke-width='4'/>",
	"buch": "<path d='M30 15 Q19 8 5 11 V52 Q18 49 30 56 Z'/><path d='M34 15 Q45 8 59 11 V52 Q46 49 34 56 Z'/>",
	"handy": "<path fill-rule='evenodd' d='M21 3 H43 Q48 3 48 8 V56 Q48 61 43 61 H21 Q16 61 16 56 V8 Q16 3 21 3 Z M21 10 V50 H43 V10 Z M29 53 H35 V57 H29 Z'/>",
	"waschen": "<path fill-rule='evenodd' d='M10 4 H54 V60 H10 Z M16 36 a16 16 0 1 0 32 0 a16 16 0 1 0 -32 0 Z M16 9 H28 V14 H16 Z'/><circle cx='32' cy='36' r='10'/>",
	"reifen": "<path fill-rule='evenodd' d='M4 32 a28 28 0 1 0 56 0 a28 28 0 1 0 -56 0 Z M18 32 a14 14 0 1 0 28 0 a14 14 0 1 0 -28 0 Z'/><circle cx='32' cy='32' r='6'/><path d='M32 22 V18 M42 32 H46 M32 42 V46 M22 32 H18' fill='none' stroke-width='3'/>",
	"hantel": "<rect x='4' y='18' width='9' height='28' rx='2'/><rect x='14' y='12' width='9' height='40' rx='2'/><rect x='41' y='12' width='9' height='40' rx='2'/><rect x='51' y='18' width='9' height='28' rx='2'/><rect x='22' y='29' width='20' height='6'/>",
	"bier": "<path d='M11 18 H43 V58 H11 Z'/><path d='M43 26 H50 Q57 26 57 33 V41 Q57 49 50 49 H43' fill='none' stroke-width='5'/><circle cx='15' cy='15' r='7'/><circle cx='26' cy='11' r='8'/><circle cx='38' cy='15' r='7'/>",
	"wein": "<path d='M17 5 H47 Q50 31 32 37 Q14 31 17 5 Z'/><path d='M32 37 V56 M19 59 H45' fill='none' stroke-width='5'/>",
	"schuh": "<path d='M5 28 L21 24 L33 37 Q51 37 59 45 V53 H5 Z'/><path d='M5 57 H59' fill='none' stroke-width='4'/>",
	"buegel": "<path d='M32 22 Q32 11 39 11 Q46 11 46 18 Q46 24 32 29 L5 49 H59 L32 29' fill='none' stroke-width='5'/>",
	"tropfen": "<path d='M32 3 Q53 30 53 42 Q53 61 32 61 Q11 61 11 42 Q11 30 32 3 Z'/>",
	"flugzeug": "<path d='M32 3 Q36 3 36 11 V25 L60 38 V45 L36 38 V51 L45 57 V62 L32 58 L19 62 V57 L28 51 V38 L4 45 V38 L28 25 V11 Q28 3 32 3 Z'/>",
	"note": "<circle cx='19' cy='50' r='9'/><circle cx='47' cy='44' r='9'/><path d='M26 50 V13 L54 6 V44' fill='none' stroke-width='5'/>",
	"pad": "<path fill-rule='evenodd' d='M16 18 H48 Q61 18 61 37 Q61 53 50 53 Q43 53 39 45 H25 Q21 53 14 53 Q3 53 3 37 Q3 18 16 18 Z M12 33 H24 V38 H12 Z M43 30 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 Z M49 38 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 Z'/>",
	"schale": "<path d='M5 30 H59 Q59 54 32 56 Q5 54 5 30 Z'/><path d='M28 26 L50 4 M37 26 L58 10' fill='none' stroke-width='4'/>",
	"lack": "<rect x='26' y='3' width='12' height='19' rx='2'/><path d='M17 25 H47 V56 Q47 61 42 61 H22 Q17 61 17 56 Z'/>",
	"cocktail": "<path d='M6 8 H58 L32 35 Z'/><path d='M32 35 V56 M19 59 H45' fill='none' stroke-width='5'/><circle cx='51' cy='9' r='7'/>",
	"stern": "<path d='M32 3 L40 23 L61 24 L45 38 L50 60 L32 48 L14 60 L19 38 L3 24 L24 23 Z'/>",
	"schluessel": "<path fill-rule='evenodd' d='M4 26 a14 14 0 1 0 28 0 a14 14 0 1 0 -28 0 Z M12 26 a6 6 0 1 0 12 0 a6 6 0 1 0 -12 0 Z'/><path d='M30 26 H60 M50 26 V36 M58 26 V34' fill='none' stroke-width='6'/>",
	"wurst": "<path d='M8 22 Q32 50 56 22' fill='none' stroke-width='14'/><path d='M4 18 L10 24 M60 18 L54 24' fill='none' stroke-width='3'/>",
	"pfeil_unten": "<path d='M24 4 H40 V36 H54 L32 60 L10 36 H24 Z'/>",
	"pfeil_links": "<path d='M60 24 V40 H28 V54 L4 32 L28 10 V24 Z'/>",
	"pfeil_rechts": "<path d='M4 24 V40 H36 V54 L60 32 L36 10 V24 Z'/>",
	"fisch": "<path d='M4 32 Q24 10 44 32 Q24 54 4 32 Z M42 32 L60 18 V46 Z'/>",
}

## Ausgedachte Markenzeichen für Läden ohne eigene Art (Ketten, Marken): je Name fest gewählt
const MARKS := [
	"<path d='M6 44 Q30 4 58 20 Q30 14 14 50 Z'/>",
	"<path d='M4 56 L22 22 L32 38 L44 14 L60 56 Z'/>",
	"<path d='M6 14 L22 32 L6 50 H18 L34 32 L18 14 Z M30 14 L46 32 L30 50 H42 L58 32 L42 14 Z'/>",
	"<path fill-rule='evenodd' d='M32 3 L57 17 V47 L32 61 L7 47 V17 Z M32 18 L44 25 V39 L32 46 L20 39 V25 Z'/>",
	"<path d='M2 36 Q12 22 22 36 T42 36 T62 36' fill='none' stroke-width='8'/><path d='M2 20 Q12 6 22 20 T42 20 T62 20' fill='none' stroke-width='5'/>",
	"<path fill-rule='evenodd' d='M4 32 a28 28 0 1 0 56 0 a28 28 0 1 0 -56 0 Z M32 4 V60 A28 28 0 0 0 32 4 Z'/>",
	"<rect x='4' y='4' width='24' height='24' rx='4'/><rect x='36' y='4' width='24' height='24' rx='12'/><rect x='4' y='36' width='24' height='24' rx='12'/><rect x='36' y='36' width='24' height='24' rx='4'/>",
	"<path d='M32 2 L38 26 L62 32 L38 38 L32 62 L26 38 L2 32 L26 26 Z'/>",
	"<path fill-rule='evenodd' d='M4 32 a28 28 0 1 0 56 0 a28 28 0 1 0 -56 0 Z M14 32 a18 18 0 1 0 36 0 a18 18 0 1 0 -36 0 Z'/><path d='M22 32 L30 40 L44 24' fill='none' stroke-width='6'/>",
	"<path d='M6 58 V6 L32 34 L58 6 V58 H46 V34 L32 50 L18 34 V58 Z'/>",
]

## Schlüsselwörter im Ladennamen -> Zeichen (Reihenfolge zählt: Spezielleres zuerst)
const KEYS := [
	[["BÄCKER", "KONDITOR", "BACKSTUBE", "BACKHAUS", "BROT"], "brezel"],
	[["FRISEUR", "BARBIER", "HAIR", "SALON"], "schere"],
	[["METZGER", "FLEISCH"], "beil"],
	[["CURRYWURST", "WURST"], "wurst"],
	[["PIZZA", "PIZZERIA", "TRATTORIA"], "pizza"],
	[["DÖNER", "KEBAP", "KEBAB", "IMBISS", "GRILL", "SCHNITZEL"], "doener"],
	[["BURGER"], "burger"],
	[["LOTTO"], "klee"],
	[["KIOSK", "SPÄTI", "SPÄTKAUF", "24/7", "GETRÄNKE", "PFAND"], "flasche"],
	[["EISCAFÉ", "EISDIELE", "GELATO"], "eis"],
	[["CAFÉ", "KAFFEE", "TEEHAUS", "ESPRESSO", "RÖSTEREI"], "tasse"],
	[["JUWELIER", "GOLD", "JADE", "UHREN", "SCHMUCK"], "diamant"],
	[["BANK", "SPARKASSE", "WECHSEL", "PFANDLEIH"], "euro"],
	[["POST"], "horn"],
	[["OPTIK", "BRILLE"], "brille"],
	[["BLUMEN", "GARTEN", "FLORIST"], "blume"],
	[["BUCH", "PRESSE", "ZEITUNG"], "buch"],
	[["HANDY", "TELEFON", "MOBIL"], "handy"],
	[["WÄSCHE", "REINIGUNG", "WASCH"], "waschen"],
	[["TUNING", "REIFEN", "AUTOTEILE", "WERKSTATT", "MOTORS", "GARAGE", "AUTO"], "reifen"],
	[["FITNESS", "BOXEN", "GYM", "KAMPF"], "hantel"],
	[["BRAUHAUS", "BIERGARTEN", "KNEIPE", "WIRTSHAUS", "GASTHAUS", "BIER", "PILS", "STUBE"], "bier"],
	[["WEIN"], "wein"],
	[["SCHUH", "SNEAKER"], "schuh"],
	[["MODE", "BOUTIQUE", "TEXTIL", "JEANS"], "buegel"],
	[["DROGERIE", "PARFÜM"], "tropfen"],
	[["REISE"], "flugzeug"],
	[["MUSIK", "PLATTEN", "VINYL", "KARAOKE"], "note"],
	[["SPIELE", "GAMES", "VIDEO"], "pad"],
	[["SUSHI", "RAMEN", "NUDEL", "DIM SUM", "PHO", "ASIA", "WOK", "DRACHE", "LOTUS", "PANDA", "TOFU", "FEUERTOPF"], "schale"],
	[["NAGEL", "KOSMETIK", "BEAUTY"], "lack"],
	[["BAR", "CLUB", "LOUNGE", "SHISHA", "COCKTAIL"], "cocktail"],
	[["SPIELHALLE", "WETT", "CASINO", "GLÜCKS", "MAHJONG"], "stern"],
	[["SCHLÜSSEL", "SCHLOSS"], "schluessel"],
	[["FISCH", "NORDSEE", "MATJES"], "fisch"],
]

static var _tex := {}
static var _mats := {}
static var _lock := Mutex.new()


## Zeichen für einen Ladennamen ("" = keins gefunden)
static func icon_for(name: String) -> String:
	var n := name.to_upper()
	for k in KEYS:
		for w in k[0]:
			if w in n:
				return k[1]
	return ""


## Markenzeichen für einen Ladennamen ohne eigene Art (fest je Name, damit Ketten überall gleich aussehen)
static func mark_for(name: String) -> String:
	return "mark%d" % (absi(name.hash()) % MARKS.size())


static func texture(id: String) -> Texture2D:
	_lock.lock()
	var t: Texture2D = _tex.get(id)
	if t == null:
		var body: String = ICONS.get(id, "")
		if id.begins_with("mark"):
			body = MARKS[int(id.substr(4)) % MARKS.size()]
		var img := Image.new()
		img.load_svg_from_string(S % body, 1.0)
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
		_tex[id] = t
	_lock.unlock()
	return t


## Unschattiertes Material für das Zeichen in Farbe col (wie die Schrift daneben: Leuchtkasten bleibt nachts hell)
static func material(id: String, col: Color) -> Material:
	var key := "%s|%s" % [id, col.to_html()]
	_lock.lock()
	var m: StandardMaterial3D = _mats.get(key)
	_lock.unlock()
	if m != null:
		return m
	m = StandardMaterial3D.new()
	m.albedo_texture = texture(id)
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lock.lock()
	_mats[key] = m
	_lock.unlock()
	return m


## Alle Texturen vorab im Hauptthread anlegen (Aufbau läuft in Hintergrund-Threads)
static func warm() -> void:
	for id in ICONS:
		texture(id)
	for i in MARKS.size():
		texture("mark%d" % i)
