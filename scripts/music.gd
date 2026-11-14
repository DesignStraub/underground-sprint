extends Node
## Musik (seit 2.30): Phonk, Drift-Phonk und Metal von Pixabay (TRACKS), eine gemeinsame Liste für Menü, Welt und
## Rennen. Beim Spielstart läuft zuerst ein kurzes Metal-Intro, danach die Liste in zufälliger Reihenfolge; kurz vor
## Schluss blendet der nächste weich über, ist die Liste durch, wird neu gemischt.
## Neue Tracks nur beim Spielstart und beim Start eines Rennens. Menü, Garage, Tuning und der Weg in die Welt und
## zurück lassen den laufenden Track weiterlaufen (beim Laden eines Rennens wird er nur leiser).
## Die Tracks sind gleich laut gemacht (ffmpeg ebur128, Ziel -11 LUFS), Stille am Anfang und Ende wird übersprungen.
## Taste "." springt zum nächsten Track, "," wechselt den Sender, "-" sortiert den laufenden Track aus.
## Bei jedem Trackwechsel klappt unten in der Mitte (Garage: rechts unten) kurz eine Blase mit Titel und Künstler auf
## (wie in NFS). Auf Handy und Tablet bleibt sie weg (kleiner Bildschirm).
## Stadt-Tracks (CITY_TRACKS): fährt man in die Stadt oder startet dort ein Rennen, läuft ihr Track einmal, danach
## geht es mit der Liste weiter (seit 2.30 keine Schleife mehr).

signal track_changed(title: String)

const UI := preload("res://scripts/ui_style.gd")
const DIR := "res://music/"
const TOAST_TIME := 4.8  # s: aufploppen, aufklappen, stehen, zuklappen, weg
const BASE_DB := -7.0
const FADE := 6.0  # Überblendung am Ende eines Tracks (s)
const FADE_SKIP := 1.2  # Überblendung beim Weiterschalten mit M
## Je Track (Pixabay-Nummer am Ende des Dateinamens): [Angleich dB, Musik beginnt bei s, Musik endet bei s (0 = Datei-Ende),
## Liste ("fahrt": Phonk, Trap für Rennen und Open World; "garage": Hip-Hop für Garage und Menüs; "beide"), optional
## true = darf erster Track beim Spielstart sein.
## Unbekannte Tracks laufen ohne Angleich von Anfang bis Ende in der Fahrt-Liste.
const TRACKS := {
	# Intro beim Spielstart (nur dort, nicht in der Liste)
	"595519": [-3.3, 0.0, 0.0, "intro", true],  # jonasblakewood metal (31 s)
	# Phonk und Drift-Phonk
	"573644": [-1.9, 0.0, 0.0, "beide"],  # alex-morgan phonk aggressive drift night
	"545509": [3.0, 0.0, 0.0, "beide"],  # alex-morgan brazilian phonk
	"200108": [-2.7, 0.0, 152.8, "beide"],  # artissizm drift phonk
	"503853": [-1.7, 0.0, 128.8, "beide"],  # gr0za drift drifting car music
	"593661": [-1.8, 0.0, 0.0, "beide"],  # kiravale phonk music
	"139106": [-5.8, 0.0, 143.2, "beide"],  # kontraa supra drift phonk
	"550480": [-3.6, 0.0, 82.9, "beide"],  # sub_clair drift phonk
	"594713": [-3.8, 0.0, 96.7, "beide"],  # sub_clair indian phonk
	"624946": [-5.9, 0.0, 124.8, "beide"],  # sub_clair phonk hard
	"588308": [-0.8, 0.0, 104.7, "beide"],  # sub_clair phonk instrumental
	"565487": [-1.2, 0.0, 0.0, "beide"],  # vaitsez drift drifting car music
	"616472": [3.0, 0.0, 133.8, "beide"],  # zephiramusic drift phonk
	"616925": [2.7, 0.0, 0.0, "beide"],  # zephiramusic phonk hard
	# Metal
	"591343": [-1.1, 0.0, 181.4, "beide"],  # alex-morgan thrash metal
	"366833": [-3.5, 0.0, 149.9, "beide"],  # alexgrohl void construct epic metal
	"572627": [-4.3, 0.47, 125.7, "beide"],  # strawberry_candy powerful heavy metal
	"588662": [-5.4, 0.0, 96.4, "beide"],  # williamsmyname alternative metal macfly
}

var lists := {"fahrt": [], "garage": []}  # Pfade je Liste, gemischt
## Radiosender wie in NFS (seit 2.29): "," schaltet weiter, "-" sortiert den laufenden Track für immer aus.
## mix = wie bisher (beim Fahren Funk und Beats, in der Garage Hip-Hop), sonst nur die Sorte des Senders.
const STATIONS := [["mix", "MIX"], ["phonk", "NACHTDRIFT"], ["metal", "METALWERK"]]
const GENRE := {"573644": "phonk", "545509": "phonk", "200108": "phonk", "503853": "phonk", "593661": "phonk",
	"139106": "phonk", "550480": "phonk", "594713": "phonk", "624946": "phonk", "588308": "phonk", "565487": "phonk",
	"616472": "phonk", "616925": "phonk", "591343": "metal", "366833": "metal", "572627": "metal", "588662": "metal"}
const PREFS := "user://music.json"
var station := "mix"
var banned: Array = []  # Pixabay-Nummern
var _st_lists := {}  # Sender -> Pfade (gemischt)
var _st_idx := {}
var _cur_path := ""
var intro: Array = []  # Intro-Tracks für den Spielstart
var _intro_path := ""  # noch zu spielendes Intro
const CITY_DIR := "res://music/staedte/"
## Stadt-Tracks: Stadt -> [Angleich dB, Musik beginnt bei s, endet bei s] (wie TRACKS)
const CITY_TRACKS := {
	"aachen": [1.2, 0.0, 148.0],  # Bruder Jakob x Jonas Platin "AC" (-12,2 LUFS)
}
var _town := ""  # Stadt, in der man gerade ist (Stadt-Track)
var mode := "garage"  # welche Liste gerade läuft (race_go: fahrt, menu: garage)
var current_title := ""
var _idx := {"fahrt": -1, "garage": -1}
var _players: Array[AudioStreamPlayer] = []
var _cur := 0  # Player des laufenden Tracks
var _gain := [0.0, 0.0]  # Angleich je Player (dB)
var _end := 0.0  # Ende der Musik im laufenden Track (s)
var _fade := 0.0  # 0..1 Fortschritt der Überblendung, 1 = keine
var _fade_len := FADE
var _paused := false
var _last_ms := 0
var _age := 0.0  # Sekunden seit dem Start des laufenden Tracks
var _toast: Control
var _toast_t := -1.0
var _toast_title := ""
var _toast_artist := ""
var _toast_pending := false
var _toast_hold := false
var toast_corner := false  # Garage: Blase rechts unten in der Tastenleiste (links Menü, darüber das Infofeld)
var _duck := 0.0  # dB: leiser während Laden, Kameraflug und Countdown
var _duck_to := 0.0
var _in_race := false
const DUCK_DB := -13.0


## Seit 2.30: Musik auf eigenem Bus, alles andere (Motor, Reifen, Verkehr, Menüklänge) 3 dB leiser (gut 30 %):
## der Master-Bus wird um SFX_CUT gesenkt, der Musik-Bus um dasselbe angehoben, die Musik bleibt gleich laut
const SFX_CUT := 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_index("Musik") < 0:
		AudioServer.add_bus()
		var bi := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "Musik")
		AudioServer.set_bus_send(bi, "Master")
		AudioServer.set_bus_volume_db(bi, SFX_CUT)
		AudioServer.set_bus_volume_db(0, AudioServer.get_bus_volume_db(0) - SFX_CUT)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Musik"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_fade = 1.0
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_toast = Control.new()
	_toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.draw.connect(_draw_toast)
	layer.add_child(_toast)
	if not OS.get_cmdline_user_args().has("--nomusic"):  # Tonaufnahmen beim Testen: nur Spielgeräusche
		_scan()
	_last_ms = Time.get_ticks_msec()
	next()


func _scan() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		var ext := name.get_extension().to_lower()
		if ext in ["mp3", "ogg", "wav"]:
			var info: Array = TRACKS.get(_track_id(DIR + name), [0.0, 0.0, 0.0, "beide"])
			for l in (["fahrt", "garage"] if info[3] == "beide" else ([] if info[3] == "intro" else [info[3]])):
				if not lists[l].has(DIR + name):
					lists[l].append(DIR + name)
			if info.size() > 4 and info[4] and not intro.has(DIR + name):
				intro.append(DIR + name)
	for l in lists:
		lists[l].shuffle()
	for l in ["fahrt", "garage"]:
		for path in lists[l]:
			var g: String = GENRE.get(_track_id(path), "")
			if g != "":
				if not _st_lists.has(g):
					_st_lists[g] = []
				if not _st_lists[g].has(path):
					_st_lists[g].append(path)
	for g in _st_lists:
		_st_lists[g].shuffle()
		_st_idx[g] = -1
	_load_prefs()
	# Spielstart: zuerst das Intro (zufällig eins der markierten), danach die gemischte Liste
	if not intro.is_empty():
		_intro_path = intro[randi() % intro.size()]
	lists["garage"] = lists["fahrt"]  # seit 2.30 eine gemeinsame Liste (Menü und Fahrt)


## Nächster Track; fade: Dauer der Überblendung (s)
func next(fade := FADE_SKIP) -> void:
	if _intro_path != "":
		var ip := _intro_path
		_intro_path = ""
		_play(ip, fade)
		return
	var use_st := station != "mix" and _st_lists.has(station)
	var playlist: Array = _st_lists[station] if use_st else lists["fahrt"]
	var idx: Dictionary = _st_idx if use_st else _idx
	var key: String = station if use_st else "fahrt"
	if playlist.is_empty():
		current_title = ""
		return
	# aussortierte Tracks überspringen (sind alle aussortiert, läuft die Liste trotzdem)
	for tries in playlist.size():
		idx[key] += 1
		if idx[key] >= playlist.size():
			# einmal durch: neu mischen, aber nicht mit dem gerade laufenden Track anfangen
			var last: String = playlist[playlist.size() - 1]
			playlist.shuffle()
			if playlist.size() > 1 and playlist[0] == last:
				playlist.append(playlist.pop_front())
			idx[key] = 0
		if not banned.has(_track_id(playlist[idx[key]])):
			break
	_play(playlist[idx[key]], fade)


func _play(path: String, fade: float) -> void:
	var s := _load(path)
	if s == null:
		return
	var info: Array = TRACKS.get(_track_id(path), [0.0, 0.0, 0.0])
	if path.begins_with(CITY_DIR):
		info = CITY_TRACKS.get(path.get_file().get_slice("-", 0), [0.0, 0.0, 0.0])
	_cur_path = path
	var nxt := 1 - _cur
	var p := _players[nxt]
	p.stream = s
	_gain[nxt] = info[0]
	_end = info[2] if info[2] > 0.0 else s.get_length()
	p.volume_db = -80.0
	p.play(info[1])
	p.stream_paused = _paused
	_cur = nxt
	_fade = 0.0
	_age = 0.0
	_fade_len = maxf(fade, 0.05)
	# Pixabay-Dateinamen: "kuenstler-titel-123456.mp3" -> "kuenstler titel"; Stadt-Tracks: "stadt-kuenstler-titel.mp3"
	var re := RegEx.create_from_string("[-_ ]\\d+$")
	var base := re.sub(path.get_file().get_basename(), "")
	if path.begins_with(CITY_DIR):
		base = base.substr(base.find("-") + 1)
	current_title = base.replace("-", " ").replace("_", " ")
	track_changed.emit(current_title)
	if OS.get_cmdline_user_args().has("--musiclog"):
		print("MUSIK %s (%s, Stadt %s)" % [current_title, mode, _town])
	# Künstler steht vor dem ersten Bindestrich (Pixabay: "sub_clair-drift-phonk-607579")
	var cut := base.find("-")
	_toast_artist = base.substr(0, cut).replace("_", " ") if cut > 0 else ""
	_toast_title = (base.substr(cut + 1) if cut > 0 else base).replace("-", " ").replace("_", " ").to_upper()
	if _paused:
		_toast_pending = true  # erst nach dem Intro zeigen
	else:
		_start_toast()


## Stadt-Track: fährt man in eine Stadt mit eigenem Track (Open World), läuft er einmal (nicht in Schleife), danach
## geht es mit der Liste weiter. Datei: music/staedte/<stadt>-<kuenstler>-<titel>.mp3 (Stadt klein, ohne Umlaute).
## town: Ortsname (Catalog "town"), "" = Autobahn oder Stadt ohne eigenen Track (die Musik läuft einfach weiter).
func city(town: String) -> void:
	if town == _town:
		return
	_town = town
	var path := city_track(town)
	if path != "" and path != _cur_path:
		_play(path, FADE_SKIP)


static func city_track(town: String) -> String:
	var key: String = town.to_lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss").replace(" ", "_")
	if key == "":
		return ""
	var d := DirAccess.open(CITY_DIR)
	if d == null:
		return ""
	for f in d.get_files():
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.begins_with(key + "-") and name.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			return CITY_DIR + name
	return ""


## Rennen wird geladen: Musik leiser bis zum Start
func race_loading() -> void:
	_in_race = true
	_duck_to = DUCK_DB
	hold_toast(true)  # keine Titel-Blase über dem Ladebalken
	if _toast_t >= 0.0:
		_toast_t = -1.0  # eine gerade offene Blase sofort weg
		_toast.queue_redraw()


## Start (LOS): neuer Track für das Rennen, voll; in einer Stadt mit eigenem Track dieser (läuft er schon, bleibt er)
func race_go(town := "") -> void:
	_duck_to = 0.0
	_in_race = false
	mode = "fahrt"
	_town = town
	var t := city_track(town)
	if t != "":
		if t != _cur_path:
			_play(t, 0.7)
		return
	next(0.7)


## In die Welt (Losfahren, zurück aus einem Rennen oder der Garage): der laufende Track bleibt, nur wieder voll;
## in einer Stadt mit eigenem Track beginnt dieser (einmal)
func world_go(town := "") -> void:
	_duck_to = 0.0
	_in_race = false
	hold_toast(false)
	mode = "fahrt"
	_town = ""
	city(town)
	if (lists[mode] as Array).size() > 0 and not _players[_cur].playing and _fade >= 1.0:
		next(0.7)


## Zurück im Menü: der Track läuft weiter (seit 2.30 kein Wechsel mehr), nur wieder voll
func menu() -> void:
	_in_race = false
	_duck_to = 0.0
	_town = ""
	hold_toast(false)
	mode = "garage"


func set_paused(p: bool) -> void:
	_paused = p
	for pl in _players:
		pl.stream_paused = p
	if not p and _toast_pending:
		_toast_pending = false
		_start_toast()


## Rennen: während der Startkarte (Kameraflug) keine Blase, sie käme der Karte unten in die Quere
func hold_toast(h: bool) -> void:
	_toast_hold = h
	if not h and _toast_pending and not _paused:
		_toast_pending = false
		_start_toast()


func _start_toast() -> void:
	if GameState.is_mobile() or DisplayServer.get_name() == "headless":
		return
	if _toast_hold:
		_toast_pending = true
		return
	_toast_t = 0.0
	_toast.queue_redraw()


## Blase unten in der Mitte: ploppt als Kreis mit Equalizer auf, klappt zur Seite auf (Titel, darunter klein der
## Künstler), steht gut drei Sekunden, klappt wieder zu und verschwindet
func _draw_toast() -> void:
	if _toast_t < 0.0:
		return
	var t := _toast_t
	var pop := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(TOAST_TIME - 0.2, TOAST_TIME, t))
	var open := smoothstep(0.2, 0.6, t) * (1.0 - smoothstep(TOAST_TIME - 0.65, TOAST_TIME - 0.25, t))
	if pop <= 0.0:
		return
	var vs := _toast.get_viewport_rect().size
	var h := 24.0
	var f_title := UI.font("cond", 0.2)
	var f_art := UI.font("bold", 0.12)
	var tw := maxf(f_title.get_string_size(_toast_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x,
		f_art.get_string_size(_toast_artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x)
	var full := h + 8.0 + tw + 10.0
	var w := lerpf(h, full, open) * lerpf(0.6, 1.0, pop)
	var hh := h * lerpf(0.6, 1.0, pop)
	var y0 := vs.y - h - 0.5 if toast_corner else vs.y - 40.0
	var x0 := vs.x - 12.0 - w if toast_corner else (vs.x - w) / 2.0
	var r := Rect2(Vector2(x0, y0 + (h - hh) / 2.0), Vector2(w, hh))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.72 * pop)
	sb.border_color = Color(UI.GREEN.r, UI.GREEN.g, UI.GREEN.b, 0.55 * pop)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(hh / 2.0))
	sb.anti_aliasing = true
	_toast.draw_style_box(sb, r)
	# Equalizer: drei Balken im Takt (nur Optik)
	var c := r.position + Vector2(hh / 2.0, hh / 2.0)
	var now := Time.get_ticks_msec() / 1000.0
	for i in 3:
		var bh := hh * (0.2 + 0.25 * (0.5 + 0.5 * sin(now * (7.0 + i * 2.3) + i * 1.7)))
		_toast.draw_rect(Rect2(c + Vector2(-5.0 + i * 3.6, hh * 0.28 - bh), Vector2(2.4, bh)), Color(UI.GREEN.r, UI.GREEN.g, UI.GREEN.b, pop))
	var ta := smoothstep(0.75, 1.0, open)
	if ta > 0.0:
		var x := r.position.x + hh + 4.0
		_toast.draw_string(f_title, Vector2(x, r.position.y + 11.5), _toast_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, ta))
		_toast.draw_string(f_art, Vector2(x, r.position.y + 20.0), _toast_artist, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.75, 0.85, ta))


func _process(_dt: float) -> void:
	# Echtzeit statt dt: in der Zeitlupe (Sprungkamera) soll die Überblendung nicht langsamer werden
	var now := Time.get_ticks_msec()
	var dt := (now - _last_ms) / 1000.0
	_last_ms = now
	if _toast_t >= 0.0:
		_toast_t += dt
		if _toast_t > TOAST_TIME:
			_toast_t = -1.0
		_toast.queue_redraw()
	if _paused or (lists[mode] as Array).is_empty():
		return
	var cur := _players[_cur]
	var old := _players[1 - _cur]
	_age += dt
	_duck = move_toward(_duck, _duck_to, dt * (30.0 if _duck_to > _duck else 18.0))
	if _fade < 1.0:
		_fade = minf(_fade + dt / _fade_len, 1.0)
		# gleiche Leistung: in der Mitte nicht leiser
		cur.volume_db = BASE_DB + _gain[_cur] + _duck + linear_to_db(maxf(sin(_fade * PI * 0.5), 0.0001))
		old.volume_db = BASE_DB + _gain[1 - _cur] + _duck + linear_to_db(maxf(cos(_fade * PI * 0.5), 0.0001))
		if _fade >= 1.0:
			old.stop()
			old.stream = null
	else:
		cur.volume_db = BASE_DB + _gain[_cur] + _duck
	if _fade >= 1.0 and ((not cur.playing and _age > 2.0) or cur.get_playback_position() >= _end - FADE):
		next(FADE)


static func _track_id(path: String) -> String:
	var m := RegEx.create_from_string("(\\d+)$").search(path.get_file().get_basename())
	return m.get_string(1) if m else ""


func _load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var r = load(path)
		if r is AudioStream:
			if "loop" in r:
				r.loop = false
			return r
	# Fallback, falls der Track noch nicht vom Editor importiert wurde
	var ext := path.get_extension().to_lower()
	if ext == "mp3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(path)
		return mp3
	if ext == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return null


func _load_prefs() -> void:
	if not FileAccess.file_exists(PREFS):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PREFS))
	if d is Dictionary:
		station = str(d.get("station", "mix"))
		banned = d.get("banned", [])
		if not STATIONS.any(func(st): return st[0] == station):
			station = "mix"


func _save_prefs() -> void:
	var f := FileAccess.open(PREFS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"station": station, "banned": banned}))


func station_name() -> String:
	for st in STATIONS:
		if st[0] == station:
			return st[1]
	return "MIX"


## Nächster Sender: Blase mit dem Sendernamen, dann gleich ein Track von dort
func next_station() -> void:
	var i := 0
	for k in STATIONS.size():
		if STATIONS[k][0] == station:
			i = k
	station = STATIONS[(i + 1) % STATIONS.size()][0]
	_save_prefs()
	next(FADE_SKIP)
	_toast_artist = "RADIO  " + station_name() + "  ·  , SENDER  · . WEITER  · - AUSSORTIEREN"


## Laufenden Track nie wieder spielen
func ban_current() -> void:
	var id := _track_id(_cur_path)
	if id == "" or _cur_path.begins_with(CITY_DIR):
		return
	if not banned.has(id):
		banned.append(id)
	_save_prefs()
	next(FADE_SKIP)
	_toast_artist = "AUSSORTIERT  ·  JETZT: " + _toast_artist


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("radio"):
		next_station()
		return
	if event.is_action_pressed("ban_track"):
		ban_current()
		return
	if event.is_action_pressed("next_track"):
		next(FADE_SKIP)
