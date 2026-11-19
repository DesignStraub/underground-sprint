extends Node
## Motorklang bei Höchstgeschwindigkeit aufnehmen (Vergleich: wie gleichförmig ist der Dauerton?).
##   Godot --headless --path . res://tools/engine_snd.tscn -- --car=sakura --live=1 --out=/pfad/vmax.wav
## Spielt 1 s Anlauf, nimmt dann 8 s im 6. Gang bei Höchsttempo auf (Vollgas, konstante Drehzahl) und beendet sich.
## --sweep: stattdessen Vollgas von 3.000 bis an den Schaltpunkt hochdrehen (8 s), mit dem Serien-Turbo des Autos aus
## dem Katalog (Vergleich: welches Auto klingt oben heraus schrill?).

const EngineAudioScript := preload("res://scripts/engine_audio.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const Catalog := preload("res://scripts/catalog.gd")

var audio
var rec: AudioEffectRecord
var out := "user://vmax.wav"
var t := 0.0
var sweep := false


func _ready() -> void:
	var car := "sakura"
	var live := 1.0
	var turbo := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car = a.substr(6)
		elif a.begins_with("--live="):
			live = float(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a == "--sweep":
			sweep = true
	if sweep and Catalog.CARS.has(car):
		turbo = float(Catalog.CARS[car]["sound"].get("turbo", 0.0))
	audio = EngineAudioScript.new()
	add_child(audio)
	audio.configure({"car": car, "turbo": turbo})
	audio.live = live
	audio.throttle = 1.0
	audio.rpm = PlayerCar.TOP_RPM * PlayerCar.VMAX_K
	audio.speed = 58.0 * PlayerCar.VMAX_K
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	# stumm aufnehmen: die Lautstärke des Busses wirkt erst nach seinen Effekten, die Aufnahme bleibt voll
	AudioServer.set_bus_effect_enabled(0, 0, false)  # Limiter aus: er würde laute Autos angleichen
	AudioServer.set_bus_volume_db(0, -80.0)


func _process(dt: float) -> void:
	t += dt
	if rec == null:
		get_tree().quit(1)
		return
	if sweep:
		var k := clampf((t - 1.0) / 8.0, 0.0, 1.0)
		audio.rpm = lerpf(3000.0, PlayerCar.SHIFT_RPM - 300.0, k)
		audio.speed = lerpf(20.0, 70.0, k)
	if t > 1.0 and not rec.is_recording_active():
		rec.set_recording_active(true)
	if t > 30.0:
		get_tree().quit(2)
	if t > 9.0 and rec.is_recording_active():
		rec.set_recording_active(false)
		var w := rec.get_recording()
		w.save_to_wav(out)
		print("SND gespeichert ", out, " ", w.get_length())
		get_tree().quit()
