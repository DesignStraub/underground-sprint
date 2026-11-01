extends AudioStreamPlayer
## Spielt alle Tracks aus res://music/ (mp3, ogg, wav) in zufälliger Reihenfolge, über alle Szenen hinweg.
## Taste M springt zum nächsten Track.

signal track_changed(title: String)

const DIR := "res://music/"

var playlist: Array[String] = []
var current_title := ""
var _index := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	volume_db = -7.0
	finished.connect(next)
	_scan()
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


func next() -> void:
	if playlist.is_empty():
		current_title = ""
		return
	_index = (_index + 1) % playlist.size()
	var path := playlist[_index]
	var s := _load(path)
	if s == null:
		return
	stream = s
	play()
	# Pixabay-Dateinamen: "kuenstler-titel-123456.mp3" -> "kuenstler titel"
	var re := RegEx.create_from_string("[-_ ]\\d+$")
	current_title = re.sub(path.get_file().get_basename(), "").replace("-", " ").replace("_", " ")
	track_changed.emit(current_title)


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
		next()
