extends Node
## Musik wie ein durchgehender Mix: alle Tracks aus res://music/ (mp3, ogg, wav) in zufälliger Reihenfolge, über alle
## Szenen hinweg. Ein Track läuft bis zum Ende (ein neues Rennen schneidet ihn nicht ab); kurz vor Schluss blendet
## der nächste weich über. Ist die Liste einmal durch, wird neu gemischt (ohne denselben Track zweimal hintereinander).
## Die Tracks sind gleich laut gemacht (gemessen mit ffmpeg ebur128, Ziel -11 LUFS), Stille am Anfang und Ende wird
## übersprungen. Taste M springt mit kurzer Überblendung zum nächsten Track.

signal track_changed(title: String)

const DIR := "res://music/"
const BASE_DB := -7.0
const FADE := 6.0  # Überblendung am Ende eines Tracks (s)
const FADE_SKIP := 1.2  # Überblendung beim Weiterschalten mit M
## Je Track (Pixabay-Nummer am Ende des Dateinamens): [Angleich dB, Musik beginnt bei s, Musik endet bei s (0 = Datei-Ende)]
## Unbekannte Tracks laufen ohne Angleich von Anfang bis Ende.
const TRACKS := {
	"529766": [4.2, 0.0, 0.0],  # absolutesound hard phonk (-15,2 LUFS)
	"223224": [-1.0, 0.0, 116.1],  # artissizm hard drift phonk
	"607579": [-1.3, 0.0, 130.4],  # sub_clair drift phonk
	"510715": [-4.3, 0.0, 103.9],  # alexzavesa dark trap (-6,7 LUFS)
	"10944": [-1.1, 0.0, 0.0],  # alexzavesa devil forces
	"116392": [0.1, 0.0, 0.0],  # kontraa uk drill
	"495946": [-2.6, 0.8, 150.8],  # audiodollar rap beat
}

var playlist: Array[String] = []
var current_title := ""
var _index := -1
var _players: Array[AudioStreamPlayer] = []
var _cur := 0  # Player des laufenden Tracks
var _gain := [0.0, 0.0]  # Angleich je Player (dB)
var _end := 0.0  # Ende der Musik im laufenden Track (s)
var _fade := 0.0  # 0..1 Fortschritt der Überblendung, 1 = keine
var _fade_len := FADE
var _paused := false
var _last_ms := 0
var _age := 0.0  # Sekunden seit dem Start des laufenden Tracks


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	_fade = 1.0
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
		if ext in ["mp3", "ogg", "wav"] and not playlist.has(DIR + name):
			playlist.append(DIR + name)
	playlist.shuffle()


## Nächster Track; fade: Dauer der Überblendung (s)
func next(fade := FADE_SKIP) -> void:
	if playlist.is_empty():
		current_title = ""
		return
	_index += 1
	if _index >= playlist.size():
		# einmal durch: neu mischen, aber nicht mit dem gerade laufenden Track anfangen
		var last := playlist[playlist.size() - 1]
		playlist.shuffle()
		if playlist.size() > 1 and playlist[0] == last:
			playlist.append(playlist.pop_front())
		_index = 0
	var path := playlist[_index]
	var s := _load(path)
	if s == null:
		return
	var info: Array = TRACKS.get(_track_id(path), [0.0, 0.0, 0.0])
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
	# Pixabay-Dateinamen: "kuenstler-titel-123456.mp3" -> "kuenstler titel"
	var re := RegEx.create_from_string("[-_ ]\\d+$")
	current_title = re.sub(path.get_file().get_basename(), "").replace("-", " ").replace("_", " ")
	track_changed.emit(current_title)


func set_paused(p: bool) -> void:
	_paused = p
	for pl in _players:
		pl.stream_paused = p


func _process(_dt: float) -> void:
	# Echtzeit statt dt: in der Zeitlupe (Sprungkamera) soll die Überblendung nicht langsamer werden
	var now := Time.get_ticks_msec()
	var dt := (now - _last_ms) / 1000.0
	_last_ms = now
	if _paused or playlist.is_empty():
		return
	var cur := _players[_cur]
	var old := _players[1 - _cur]
	_age += dt
	if _fade < 1.0:
		_fade = minf(_fade + dt / _fade_len, 1.0)
		# gleiche Leistung: in der Mitte nicht leiser
		cur.volume_db = BASE_DB + _gain[_cur] + linear_to_db(maxf(sin(_fade * PI * 0.5), 0.0001))
		old.volume_db = BASE_DB + _gain[1 - _cur] + linear_to_db(maxf(cos(_fade * PI * 0.5), 0.0001))
		if _fade >= 1.0:
			old.stop()
			old.stream = null
	elif (not cur.playing and _age > 2.0) or cur.get_playback_position() >= _end - FADE:
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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_track"):
		next(FADE_SKIP)
