extends Node
## Motorklang bei Höchstgeschwindigkeit aufnehmen (Vergleich: wie gleichförmig ist der Dauerton?).
##   Godot --headless --path . res://tools/engine_snd.tscn -- --car=sakura --live=1 --out=/pfad/vmax.wav
## Spielt 1 s Anlauf, nimmt dann 8 s im 6. Gang bei Höchsttempo auf (Vollgas, konstante Drehzahl) und beendet sich.

const EngineAudioScript := preload("res://scripts/engine_audio.gd")
const PlayerCar := preload("res://scripts/player_car.gd")

var audio
var rec: AudioEffectRecord
var out := "user://vmax.wav"
var t := 0.0


func _ready() -> void:
	var car := "sakura"
	var live := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car="):
			car = a.substr(6)
		elif a.begins_with("--live="):
			live = float(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
	audio = EngineAudioScript.new()
	add_child(audio)
	audio.configure({"car": car, "turbo": 0.0})
	audio.live = live
	audio.throttle = 1.0
	audio.rpm = PlayerCar.TOP_RPM * PlayerCar.VMAX_K
	audio.speed = 58.0 * PlayerCar.VMAX_K
	rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)


func _process(dt: float) -> void:
	t += dt
	if rec == null:
		get_tree().quit(1)
		return
	if t > 1.0 and not rec.is_recording_active():
		rec.set_recording_active(true)
	if t > 9.0:
		rec.set_recording_active(false)
		var w := rec.get_recording()
		w.save_to_wav(out)
		print("SND gespeichert ", out, " ", w.get_length())
		get_tree().quit()
