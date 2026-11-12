extends Node
## Motorklang wie in großen Rennspielen: nahtlose Schleifen aus echten Motoraufnahmen bei festen Drehzahlen (RPMS),
## einmal unter Last (Gas) und einmal im Schiebebetrieb (tools/engine_rec/build_banks.sh -> assets/engine/<aufnahme>/,
## Quellen und Urheber in CREDITS.md). Mehrere Autos teilen sich eine Aufnahme (CAR_BANK), jedes in eigener Tonhöhe.
## Gespielt werden immer die beiden Drehzahlen um die echte herum, gleich laut überblendet, jede in der Tonhöhe auf
## die echte Drehzahl gezogen; Gas und Schub werden genauso überblendet. Beim Hochschalten nimmt der Motor kurz die
## Zündung weg (klingt kurz nach Schub), Fehlzündungen (backfire, von player_car ausgelöst) knallen im Auspuff.
## Dazu der Turbo (Pfeifen unter Last; Gas weg: Blow-off-Ventil "Pschhh" beim nachgerüsteten Lader, Flattern beim
## Serienlader). Alles andere kommt aus Schleifen (tools/make_sfx.py): road.wav (Abrollen), wind.wav (Fahrtwind),
## scrub.wav (Schrubben, schon bei leichtem Rutschen), skid.wav (Quietschen erst im echten Drift), scrape.wav (Blech
## an der Wand), nitro_on.wav (Zünden), nitro.wav (Fauchen, solange Nitro läuft), nitro_off.wav (Abblasen),
## turbo.wav (Pfeifen).
## Bis 2.21 rechnete das Skript den Klang Sample für Sample aus Sinustönen (klang nach Orgel), 2.22 aus einem
## Rohr-Modell (klang blechern und heulend). Gegner und Verkehr nutzen dieselben Schleifen (bank(), traffic_loop()).
## Alle Player laufen im Stream-Modus: im Browser spielt Godot sonst fertige Samples ab, deren Lautstärke und
## Tonhöhe sich nicht zuverlässig in jedem Bild nachführen lassen.

const RATE := 22050.0
## Drehzahlen der Schleifen (Leerlauf zuerst; dort gibt es nur eine Schleife für Gas und Schub)
const RPMS := [900.0, 1300.0, 1850.0, 2500.0, 3250.0, 4100.0, 5000.0, 6100.0, 7400.0]
const DIR := "res://assets/engine/"
const BASE_DB := -8.5  # 2.23: echte Aufnahmen sind dichter als die gerechneten Schleifen; so bleibt die Lautstärke wie in 2.22
## Aufnahme je Auto und Drehzahl-Faktor: die Schleifen werden so gespielt, als drehte der Motor Faktor x so hoch.
## Kleine Dreizylinder tiefer (drei statt vier Zündungen je zwei Umdrehungen), sonst kleine Unterschiede, damit
## Autos mit derselben Aufnahme nicht gleich klingen.
const CAR_BANK := {
	"chibi": ["i4_turbo", 0.8], "hotaru": ["i4_sauger", 0.82], "tanuki": ["i4_turbo", 0.78],
	"kaizen": ["i4_turbo", 1.0], "hachi": ["i4_hoch", 1.0], "sakura": ["i4_sauger", 1.04], "hayate": ["i4_turbo", 0.95],
	"kitsune": ["i4_turbo", 1.07], "tsubame": ["i4_hoch", 1.06], "mirai": ["i4_sauger", 0.97], "tenshi": ["i4_hoch", 0.95],
	"raijin": ["boxer", 1.0],
	"kumo": ["i6", 1.0], "vortex": ["f6", 0.96], "kaze": ["f6", 1.04], "kaido": ["i6", 0.94], "hakone": ["i6", 1.05],
	"ryujin": ["f6", 0.9], "shiden": ["f6", 0.86], "falke": ["f6", 1.0],
	"ronin": ["wankel", 1.0], "kagura": ["v10", 1.0], "furia": ["v12", 1.0],
}

var bus := "Master":
	set(v):
		bus = v
		for a in _all_players():
			a.bus = v
var rpm := 900.0
var throttle := 0.0
var nitro := false
var slip := 0.0  # 0..1 Driftstärke
var speed := 0.0  # m/s
var scrape := 0.0  # 0..1 Schrammen an der Wand

var car := ""
var turbo_amount := 0.0
var bov_sound := "flutter"  # Gas weg mit Turbo: "bov" (Ventil, nachgerüstet) oder "flutter" (Serienlader)

var _bank := {}
var _k := 1.0  # Drehzahl-Faktor der Aufnahme (CAR_BANK)
var _voices := {}  # "on3" -> AudioStreamPlayer (gerade hörbare Schleifen)
var _pool: Array[AudioStreamPlayer] = []
var _load := 0.0  # 0 = Schub, 1 = Gas (geglättet)
var _last_throttle := 0.0
var _cut := 0.0  # Zündunterbrechung beim Hochschalten (Restzeit s)
var _cut_k := 0.0
var _turbo := 0.0
var _skid: AudioStreamPlayer
var _skid_k := 0.0
var _scrub: AudioStreamPlayer
var _scrub_k := 0.0
var _nos: AudioStreamPlayer
var _nos_k := 0.0
var _nos_was := false
var _scr: AudioStreamPlayer
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _whistle: AudioStreamPlayer
var _whine: AudioStreamPlayer
## Leben im Dauerton (seit Open World): bei konstant hoher Drehzahl liefen sonst immer dieselben zwei Schleifen in
## fester Tonhöhe, das klang nach Endlosschleife. Echte Motoren klingen von Arbeitsspiel zu Arbeitsspiel etwas anders
## (Vorbild: AngeTheGreat, "Adding Mechanical Sound Simulation to My Audio Engine"). Darum wandern Drehzahl,
## Mischung der Schleifen und Pegel langsam, eine dritte Schleife kommt ab und zu dazu, und ein Getriebesingen läuft mit.
var _wand := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])  # langsame Schwankungen -1..1: Tonhöhe, Mischung, Pegel, dritte Schleife
var _wand_to := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _wand_t := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _steady := 0.0  # 0..1: wie gleichmäßig die Drehzahl gerade ist
var _rpm_prev := 900.0
var live := 1.0  # Stärke der Schwankungen (1 = normal; 0 = aus, für Vergleichsaufnahmen)


## profile: Klangdaten aus dem Katalog, dazu "car" (Auto-Kennung für die Schleifen)
func configure(profile: Dictionary) -> void:
	car = profile.get("car", "")
	turbo_amount = profile.get("turbo", 0.0)
	bov_sound = profile.get("bov", bov_sound)
	_bank = bank(car)
	_k = _bank.get("k", 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_skid = _loop("skid")
	_scrub = _loop("scrub")
	_nos = _loop("nitro")
	_scr = _loop("scrape")
	_road = _loop("road")
	_wind = _loop("wind")
	_whistle = _loop("turbo")
	_whine = _loop("whine")


func _loop(sound: String) -> AudioStreamPlayer:
	var a := Sfx.looping(sound)
	a.volume_db = -80.0
	a.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	a.bus = bus
	add_child(a)
	a.play()
	return a


func _all_players() -> Array:
	var out := []
	for c in get_children():
		if c is AudioStreamPlayer:
			out.append(c)
	return out


static var bench_us := 0  # Rechenzeit des Motorklangs (nur für --bench)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_sound(delta)
	bench_us += Time.get_ticks_usec() - t0


func _process_sound(delta: float) -> void:
	_update_skid(delta)
	_update_nitro(delta)
	_update_road()
	if turbo_amount > 0.0 and _last_throttle > 0.6 and throttle < 0.2 and _turbo > 0.5:
		_blow(clampf(_turbo, 0.5, 1.0))
	_last_throttle = throttle
	_cut = maxf(_cut - delta, 0.0)
	_turbo = move_toward(_turbo, throttle * clampf((rpm - 2500.0) / 4000.0, 0.0, 1.0), delta * (1.5 if throttle > 0.5 else 4.0))
	# Gas und Schub: Gas kommt schnell, geht etwas weicher; beim Hochschalten kurz Schub (Zündung weg)
	var want := 0.0 if _cut > 0.0 else clampf(throttle, 0.0, 1.0)
	_load = move_toward(_load, want, delta * (9.0 if want > _load else 6.0))
	_cut_k = move_toward(_cut_k, 1.0 if _cut > 0.0 else 0.0, delta * 25.0)
	_update_life(delta)
	_update_engine()
	# Turbo pfeift unter Last, Tonhöhe mit der Drehzahl
	var wl := _turbo * turbo_amount
	_whistle.volume_db = -80.0 if wl < 0.02 else linear_to_db(wl) - 17.0
	_whistle.pitch_scale = clampf((700.0 + rpm / 10.0) / 1100.0, 0.5, 1.6)


## Langsame Zufallskurven (je eine neue Zielmarke alle 0,3–1,1 s, weich angefahren) und wie gleichmäßig die Drehzahl
## ist: beim Beschleunigen und Schalten ändert sich der Klang ohnehin, dort bleibt alles wie gehabt.
func _update_life(delta: float) -> void:
	for k in 4:
		_wand_t[k] -= delta
		if _wand_t[k] <= 0.0:
			_wand_t[k] = randf_range(0.3, 1.1)
			_wand_to[k] = randf_range(-1.0, 1.0)
		_wand[k] = lerpf(_wand[k], _wand_to[k], 1.0 - exp(-delta * 2.2))
	var drpm := absf(rpm - _rpm_prev) / maxf(delta, 0.001)
	_rpm_prev = rpm
	_steady = move_toward(_steady, 1.0 if drpm < 600.0 else 0.0, delta * (0.8 if drpm < 600.0 else 4.0))
	# Getriebesingen: Tonhöhe folgt dem Tempo, hörbar erst schnell und unter Last
	var v := clampf(speed / 75.0, 0.0, 1.0)
	var wl := v * v * (0.45 + 0.55 * _load) * live
	_whine.bus = bus
	_whine.volume_db = -80.0 if wl < 0.01 else linear_to_db(wl) - 25.0
	_whine.pitch_scale = clampf(0.35 + 1.0 * v + 0.01 * _wand[0], 0.3, 1.5)


## Die zwei Schleifen um die Drehzahl herum (Gas und Schub je zwei) hörbar machen, alle anderen stoppen
func _update_engine() -> void:
	if _bank.is_empty():
		return
	# Leben im Dauerton: nur bei gleichmäßiger, hoher Drehzahl (dort fällt die Wiederholung auf)
	var life := _steady * smoothstep(3500.0, 6000.0, rpm * _k) * live
	var r0 := rpm * _k * (1.0 + life * (0.011 * _wand[0] + randf_range(-0.003, 0.003)))
	var r := clampf(r0, RPMS[0] * 0.8, RPMS[RPMS.size() - 1] * 1.15)
	var i := 0
	while i < RPMS.size() - 2 and r > RPMS[i + 1]:
		i += 1
	var t := clampf(log(r / RPMS[i]) / log(RPMS[i + 1] / RPMS[i]) + life * 0.22 * _wand[1], 0.0, 1.0)
	var lo := cos(t * PI * 0.5)
	var hi := sin(t * PI * 0.5)
	var g_on := sin(_load * PI * 0.5)
	var g_off := cos(_load * PI * 0.5)
	var lvl := (1.0 - 0.45 * _cut_k) * (1.0 + life * 0.09 * _wand[2])  # Zündung weg: leiser
	var want := {}
	for ld in ["on", "off"]:
		var g := g_on if ld == "on" else g_off
		want[ld + str(i)] = lo * g
		want[ld + str(i + 1)] = hi * g
	# dritte Schleife (eine Stufe darunter) zeitweise leise dazu: ihre andere Länge bricht das Muster
	var x3 := life * maxf(_wand[3], 0.0) * 0.35
	if i > 0 and x3 > 0.01:
		want["on" + str(i - 1)] = x3 * g_on
	for key in _voices.keys():
		if want.get(key, 0.0) < 0.002:
			var a: AudioStreamPlayer = _voices[key]
			a.stop()
			_pool.append(a)
			_voices.erase(key)
	for key in want:
		var w: float = want[key]
		if w < 0.002:
			continue
		var p := int(key.substr(2)) if key.begins_with("on") else int(key.substr(3))
		var ld: String = "on" if key.begins_with("on") else "off"
		var a: AudioStreamPlayer = _voices.get(key)
		if a == null:
			var s: AudioStreamWAV = _bank[ld][p]
			if s == null:
				continue
			a = _pool.pop_back() if not _pool.is_empty() else _new_voice()
			a.stream = s
			a.volume_db = -80.0
			a.play(randf() * s.get_length())
			_voices[key] = a
		a.volume_db = linear_to_db(w * lvl) + BASE_DB
		a.pitch_scale = clampf(r / exact_rpm(RPMS[p]), 0.5, 2.0)


func _new_voice() -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	a.bus = bus
	add_child(a)
	return a


## Reifen: Schrubben setzt schon bei leichtem Rutschen ein (Kurve am Limit), das Quietschen erst im echten Drift oder
## bei durchdrehenden Rädern. Beides weich ein- und schnell ausblenden, sobald die Reifen wieder greifen; das
## Quietschen wird mit Rutschen und Tempo etwas höher.
func _update_skid(delta: float) -> void:
	if _skid == null:
		return
	var target := clampf(slip, 0.0, 1.0)
	var sq := clampf((target - 0.3) / 0.5, 0.0, 1.0)
	var sc := clampf(target / 0.35, 0.0, 1.0)
	_skid_k = move_toward(_skid_k, sq, delta * (4.0 if sq > _skid_k else 3.0))
	_scrub_k = move_toward(_scrub_k, sc, delta * (6.0 if sc > _scrub_k else 4.0))
	var speed_n := clampf(speed / 50.0, 0.0, 1.0)
	for a in [_skid, _scrub, _scr, _road, _wind]:
		(a as AudioStreamPlayer).bus = bus
	# Blech an der Wand: lauter und heller, je schneller es entlangschrammt
	_scr.volume_db = -80.0 if scrape < 0.01 else linear_to_db(scrape) - 3.0
	_scr.pitch_scale = 0.8 + 0.35 * speed_n
	_skid.volume_db = -80.0 if _skid_k < 0.01 else linear_to_db(_skid_k) * 1.4 - 5.0
	_skid.pitch_scale = 0.93 + 0.08 * _skid_k + 0.07 * speed_n
	# Schrubben tritt zurück, wenn das Quietschen voll da ist
	var scrub_lvl := _scrub_k * (1.0 - 0.45 * _skid_k) * (0.5 + 0.5 * speed_n)
	_scrub.volume_db = -80.0 if scrub_lvl < 0.01 else linear_to_db(scrub_lvl) - 7.5
	_scrub.pitch_scale = 0.85 + 0.3 * speed_n


## Nitro: beim Zünden ein Zischen mit dumpfem Stoß, danach Fauchen, solange es läuft; beim Loslassen bläst es
## kurz ab. Der Motor klingt dabei heller (Filter weiter offen). Bis 2.15 lag das Fauchen etwa so laut wie der
## Motor und ging unter der Musik unter; jetzt steht es gut 4 dB darüber.
func _update_nitro(delta: float) -> void:
	if _nos == null:
		return
	if nitro and not _nos_was:
		var a := Sfx.play("nitro_on", 1.0, randf_range(0.96, 1.04))
		if a:
			a.bus = bus
	elif _nos_was and not nitro and _nos_k > 0.5:
		var b := Sfx.play("nitro_off", -3.0, randf_range(0.95, 1.05))
		if b:
			b.bus = bus
	_nos_was = nitro
	_nos_k = move_toward(_nos_k, 1.0 if nitro else 0.0, delta * (5.0 if nitro else 3.0))
	_nos.bus = bus
	_nos.volume_db = -80.0 if _nos_k < 0.01 else linear_to_db(_nos_k) - 1.5
	_nos.pitch_scale = 0.94 + 0.12 * clampf(speed / 75.0, 0.0, 1.0)


## Abrollen und Fahrtwind: das Brummen der Reifen ist schon bei Stadttempo da und wird mit dem Tempo höher, der Wind
## kommt erst bei hohem Tempo richtig (wächst mit dem Quadrat). In der Luft rollt nichts.
func _update_road() -> void:
	var v := clampf(speed / 75.0, 0.0, 1.0)
	var roll := 0.0 if speed < 1.0 else (0.12 + 0.88 * v) * (1.0 - 0.6 * clampf(slip, 0.0, 1.0))
	_road.volume_db = -80.0 if roll < 0.01 else linear_to_db(roll) - 17.0
	_road.pitch_scale = 0.7 + 0.6 * v
	var w := v * v
	_wind.volume_db = -80.0 if w < 0.005 else linear_to_db(w) - 15.0
	_wind.pitch_scale = 0.85 + 0.35 * v


## Hochschalten: die Zündung ist kurz weg (Motor klingt kurz nach Schub und leiser, dann setzt er im nächsten Gang
## wieder ein). Mit Turbo bläst dabei das Ventil kurz ab.
func shift() -> void:
	_cut = 0.08
	if turbo_amount > 0.3 and _turbo > 0.4:
		_blow(0.45)


## Fehlzündung (Stärke 0..1): Knall im Auspuff
func backfire(strength: float, pitch := 1.0) -> void:
	if strength > 0.3:
		var a := Sfx.play("backfire", linear_to_db(strength) - 6.0, randf_range(0.88, 1.12) * pitch)
		if a:
			a.bus = bus


## Gas weg mit Turbo: Blow-off-Ventil oder Flattern des Serienladers
func _blow(strength: float) -> void:
	var a := Sfx.play(bov_sound, linear_to_db(strength * turbo_amount) - 10.0, randf_range(0.94, 1.06))
	if a:
		a.bus = bus


var _crash_t := 0  # ms des letzten Aufprall-Tons (nicht jedes Bild einen neuen)


## Dumpfer Aufprall, Stärke 0..1
func crash(strength: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _crash_t < 120:
		return
	_crash_t = now
	var a := Sfx.play("thud", linear_to_db(clampf(strength, 0.05, 1.0)) + 1.0, randf_range(0.85, 1.05))
	if a:
		a.bus = bus


## Tatsächliche Drehzahl einer Schleife: eine ganze Zahl Samples je Arbeitsspiel (zwei Umdrehungen)
static func exact_rpm(nominal: float) -> float:
	return RATE * 120.0 / roundf(RATE * 120.0 / nominal)


static var _banks := {}


## Schleifen eines Autos: {"on": [je RPMS eine], "off": [...], "k": Drehzahl-Faktor}; im Leerlauf gilt dieselbe
## für beide. Jede Aufnahme wird einmal geladen, auch wenn mehrere Autos sie nutzen.
static func bank(id: String) -> Dictionary:
	var spec: Array = CAR_BANK.get(id, ["i4_turbo", 1.0])
	var src: String = spec[0]
	if not _banks.has(src):
		var b := {"on": [], "off": []}
		for ld in ["on", "off"]:
			for r in RPMS:
				var name: String = "on" if r == RPMS[0] else ld
				b[ld].append(_looped("%s%s/%s_%d.wav" % [DIR, src, name, int(r)]))
		if b["on"][0] == null:
			b = {}
		_banks[src] = b
	var out: Dictionary = _banks[src].duplicate()
	if not out.is_empty():
		out["k"] = spec[1]
	return out


## Verkehr: "car" oder "bus" (eine Schleife mit Abrollen), Drehzahl der Schleife in meta "rpm"
static func traffic_loop(kind: String) -> AudioStreamWAV:
	var key := "traffic_" + kind
	if _banks.has(key):
		return _banks[key]
	var r := 900.0 if kind == "bus" else 2100.0  # Bus: Stadtbus im Leerlauf, Tonhöhe folgt dem Tempo
	var w := _looped("%straffic_%s_%d.wav" % [DIR, kind, int(r)])
	if w:
		w.set_meta("rpm", exact_rpm(r))
	_banks[key] = w
	return w


static func _looped(path: String) -> AudioStreamWAV:
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStreamWAV = (load(path) as AudioStreamWAV).duplicate()
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(round(s.get_length() * s.mix_rate))
	return s
