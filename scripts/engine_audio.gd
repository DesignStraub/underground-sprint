extends AudioStreamPlayer
## Synthetischer Motorsound in Echtzeit. Grundton aus Drehzahl und Zylinderzahl, Obertöne je nach Auto,
## alles durch einen weichen Tiefpass. Lautstärke steigt mit Drehzahl und Gas.
## Dazu leise: Turbo, Blow-off, Reifen, Fahrtwind, Nitro.

const RATE := 22050.0

var rpm := 900.0
var throttle := 0.0
var nitro := false
var slip := 0.0  # 0..1 Driftstärke
var speed := 0.0  # m/s

# Motorcharakter (per configure() aus dem Katalog)
var cylinders := 4.0
var harmonics := [1.0, 0.45, 0.2, 0.08]  # Anteile 1x..4x Zündfrequenz
var sub := 0.35  # halber Takt, macht den Leerlauf "bollernd"
var turbo_amount := 0.0
var rough := 0.25

var _pb: AudioStreamGeneratorPlayback
var _phase := 0.0
var _turbo_phase := 0.0
var _rpm_s := 900.0
var _thr_s := 0.0
var _slip_s := 0.0
var _lp1 := 0.0
var _lp2 := 0.0
var _rough_lp := 0.0
var _n_lo := 0.0
var _n_hi := 0.0
var _wind_lp := 0.0
var _bov := 0.0
var _last_throttle := 0.0
var _turbo := 0.0
var _phase2 := 0.0
var _crash := 0.0
var _crash_lp := 0.0


func configure(profile: Dictionary) -> void:
	cylinders = profile.get("cyl", 4)
	harmonics = profile.get("harm", harmonics)
	sub = profile.get("sub", sub)
	turbo_amount = profile.get("turbo", 0.0)
	rough = profile.get("rough", rough)


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.08
	stream = gen
	volume_db = -6.0
	play()
	_pb = get_stream_playback()


func _process(delta: float) -> void:
	if _pb == null:
		return
	if turbo_amount > 0.0 and _last_throttle > 0.6 and throttle < 0.2 and _turbo > 0.5:
		_bov = 1.0
	_last_throttle = throttle
	_turbo = move_toward(_turbo, throttle * clampf((rpm - 2500.0) / 4000.0, 0.0, 1.0), delta * (1.5 if throttle > 0.5 else 4.0))

	# Pro Block konstante Werte
	var fire := rpm / 60.0 * cylinders / 2.0
	# Obere Frequenzgrenze wächst mit der Drehzahl, bleibt aber unter ~1 kHz: warm statt schrill
	var cutoff := clampf(fire * 2.6 + throttle * 250.0, 200.0, 1000.0)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var h0: float = harmonics[0]
	var h1: float = harmonics[1]
	var h2: float = harmonics[2]
	var h3: float = harmonics[3]
	var norm := 1.0 / (sub + h0 + h1 + h2 + h3)
	var turbo_amp := _turbo * turbo_amount * 0.01
	var speed_n := clampf(speed / 75.0, 0.0, 1.0)
	var wind_amp := speed_n * speed_n * 0.25
	var a_lo := 1.0 - exp(-TAU * 350.0 / RATE)
	var a_hi := 1.0 - exp(-TAU * 1400.0 / RATE)

	for i in _pb.get_frames_available():
		_rpm_s += (rpm - _rpm_s) * 0.002
		_thr_s += (throttle - _thr_s) * 0.002
		_slip_s += (slip - _slip_s) * 0.001
		var rpm_n := clampf((_rpm_s - 800.0) / 7200.0, 0.0, 1.0)
		_phase = fmod(_phase + (_rpm_s / 60.0 * cylinders / 2.0) / RATE, 2.0)
		var p := _phase * TAU
		var x := sub * sin(0.5 * p) + h0 * sin(p) + h1 * sin(2.0 * p + 0.4) + h2 * sin(3.0 * p + 0.9) + h3 * sin(4.0 * p + 1.3)
		# Zweite, minimal verstimmte Stimme (Auspuff) macht den Klang voller
		_phase2 = fmod(_phase2 + (_rpm_s / 60.0 * cylinders / 2.0) * 1.004 / RATE, 2.0)
		var p2 := _phase2 * TAU
		x += 0.35 * (h0 * sin(p2) + h1 * sin(2.0 * p2 + 1.1))
		x *= norm * 0.8
		# Leichte Unruhe über langsam schwankende Amplitude statt kratzigem Rauschen
		var noise := randf() * 2.0 - 1.0
		_rough_lp += 0.015 * (noise - _rough_lp)
		x *= 1.0 + _rough_lp * rough * 3.0 * (1.0 - rpm_n * 0.7)
		x = x / (1.0 + absf(x) * 0.25)  # sanfte Sättigung
		_lp1 += a * (x - _lp1)
		_lp2 += a * (_lp1 - _lp2)
		var s := _lp2 * (0.14 + 0.4 * sqrt(rpm_n) * (0.55 + 0.45 * _thr_s))

		# Bandbegrenztes Rauschen (350–1400 Hz) für Zischen, Reifen, Nitro: kein schrilles Hochtonrauschen
		_n_lo += a_lo * (noise - _n_lo)
		_n_hi += a_hi * (noise - _n_hi)
		var band := _n_hi - _n_lo

		if turbo_amp > 0.0001:
			_turbo_phase = fmod(_turbo_phase + (700.0 + _rpm_s * 0.1) / RATE, 1.0)
			s += sin(_turbo_phase * TAU) * turbo_amp
		if _bov > 0.001:
			s += band * _bov * 0.25
			_bov *= 0.9997
		if nitro:
			s += band * 0.12
		if _slip_s > 0.02:
			s += band * _slip_s * 0.3
		if _crash > 0.001:
			_crash_lp += 0.08 * (noise - _crash_lp)
			s += _crash_lp * _crash * 2.5
			_crash *= 0.9996
		_wind_lp += 0.03 * (noise - _wind_lp)
		s += _wind_lp * wind_amp

		s = clampf(s, -1.0, 1.0)
		_pb.push_frame(Vector2(s, s))


## Dumpfer Aufprall, Stärke 0..1
func crash(strength: float) -> void:
	_crash = maxf(_crash, clampf(strength, 0.0, 1.0))
