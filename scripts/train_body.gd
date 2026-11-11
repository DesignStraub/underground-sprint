extends CharacterBody3D
## Kollisionskörper des Zugs. Verhält sich für Autos wie Verkehr (harter Crash), lässt sich aber nicht wegschieben.

var velocity_vec := Vector3.ZERO
var mass := 1000.0  # player_car._hit_traffic: wer gegen den Zug fährt, prallt ab
var wrecked := false
var length := 90.0


func knock(_v: Vector3) -> void:
	pass


func push(_dv: Vector3) -> void:
	pass
