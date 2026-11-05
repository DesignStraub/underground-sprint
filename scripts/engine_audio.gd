extends AudioStreamPlayer
## Synthetischer Motorsound in Echtzeit. Grundton aus Drehzahl und Zylinderzahl, Obertöne je nach Auto, dazu die
## Druckstöße im Auspuff (schmale Pulse je Zündung: das gibt den kernigen, hellen Anteil) und ein leises Rasseln
## (Rauschen im Takt der Zündungen) unter Last. Tiefpass bis gut 2 kHz: klar, aber nicht schrill. Lautstärke steigt
## mit Drehzahl und Gas; beim Gaswegnehmen bei hoher Drehzahl ploppt es ab und zu im Auspuff.
## Dazu leise: Turbo, Blow-off, Fahrtwind, Nitro. Reifenquietschen kommt aus einer eigenen Schleife (skid.wav),
## Lautstärke und Tonhöhe nach Rutschen und Tempo.

## Abtastrate: am Rechner 22 kHz, auf Handy/Tablet die Hälfte (der Klang liegt ohnehin unter 1,5 kHz, und die
## Berechnung läuft Sample für Sample im Skript). k gleicht die Glättung je Sample an die Rate an.
var rate := 22050.0
var k := 1.0

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
var _n_top := 0.0
var _pop := 0.0
var _wind_lp := 0.0
var _bov := 0.0
var _last_throttle := 0.0
var _turbo := 0.0
var _phase2 := 0.0
var _crash := 0.0
var _crash_lp := 0.0
var _skid: AudioStreamPlayer
var _skid_k := 0.0


func configure(profile: Dictionary) -> void:
	cylinders = profile.get("cyl", 4)
	harmonics = profile.get("harm", harmonics)
	sub = profile.get("sub", sub)
	turbo_amount = profile.get("turbo", 0.0)
	rough = profile.get("rough", rough)


func _ready() -> void:
	if GameState.is_mobile():
		rate = 11025.0
	k = 22050.0 / rate
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.08
	stream = gen
	volume_db = -6.0
	# Im Browser spielt Godot Sounds sonst als fertige Samples ab; ein Generator braucht den Stream-Modus
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	play()
	_pb = get_stream_playback()
	_skid = Sfx.looping("skid")
	_skid.volume_db = -80.0
	add_child(_skid)
	_skid.play()


func _process(delta: float) -> void:
	_update_skid(delta)
	if _pb == null:
		return
	if turbo_amount > 0.0 and _last_throttle > 0.6 and throttle < 0.2 and _turbo > 0.5:
		_bov = 1.0
	# Plopp im Auspuff: Gas weg bei hoher Drehzahl
	if _last_throttle > 0.5 and throttle < 0.1 and rpm > 4500.0 and randf() < 0.5:
		_pop = 0.6 + randf() * 0.4
	_last_throttle = throttle
	_turbo = move_toward(_turbo, throttle * clampf((rpm - 2500.0) / 4000.0, 0.0, 1.0), delta * (1.5 if throttle > 0.5 else 4.0))

	# Pro Block konstante Werte
	var fire := rpm / 60.0 * cylinders / 2.0
	# Obere Frequenzgrenze wächst mit Drehzahl und Last: unter Gas hell und offen (bis ~2,2 kHz), im Schiebebetrieb
	# dumpfer. Bis 2.12 lag sie unter 1 kHz, das klang wie durch eine Wand.
	var cutoff := clampf(fire * 3.0 + throttle * 500.0, 300.0, 1800.0)
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var h0: float = harmonics[0]
	var h1: float = harmonics[1]
	var h2: float = harmonics[2]
	var h3: float = harmonics[3]
	var norm := 1.0 / (sub + h0 + h1 + h2 + h3)
	var turbo_amp := _turbo * turbo_amount * 0.01
	var speed_n := clampf(speed / 75.0, 0.0, 1.0)
	var wind_amp := speed_n * speed_n * 0.25
	var a_lo := 1.0 - exp(-TAU * 350.0 / rate)
	var a_hi := 1.0 - exp(-TAU * 1400.0 / rate)
	var a_top := 1.0 - exp(-TAU * minf(3600.0, rate * 0.4) / rate)
	var k_pop := pow(0.9985, k)
	var k_bov := pow(0.9997, k)
	var k_crash := pow(0.9996, k)
	var n := _pb.get_frames_available()
	var buf := PackedVector2Array()
	buf.resize(n)

	for i in n:
		_rpm_s += (rpm - _rpm_s) * 0.002 * k
		_thr_s += (throttle - _thr_s) * 0.002 * k
		_slip_s += (slip - _slip_s) * 0.001 * k
		var rpm_n := clampf((_rpm_s - 800.0) / 7200.0, 0.0, 1.0)
		_phase = fmod(_phase + (_rpm_s / 60.0 * cylinders / 2.0) / rate, 2.0)
		var p := _phase * TAU
		var x := sub * sin(0.5 * p) + h0 * sin(p) + h1 * sin(2.0 * p + 0.4) + h2 * sin(3.0 * p + 0.9) + h3 * sin(4.0 * p + 1.3)
		# Zweite, minimal verstimmte Stimme (Auspuff) macht den Klang voller
		_phase2 = fmod(_phase2 + (_rpm_s / 60.0 * cylinders / 2.0) * 1.004 / rate, 2.0)
		var p2 := _phase2 * TAU
		x += 0.35 * (h0 * sin(p2) + h1 * sin(2.0 * p2 + 1.1))
		x *= norm * 0.8
		# Druckstöße: ein schmaler Puls je Zündung (viele Obertöne), unter Last kräftiger
		var sp := maxf(sin(p), 0.0)
		var sp2 := sp * sp
		var pulse := sp2 * sp2 * sp2
		x += (pulse - 0.12) * (0.15 + 0.2 * _thr_s)
		# Leichte Unruhe über langsam schwankende Amplitude statt kratzigem Rauschen
		var noise := randf() * 2.0 - 1.0
		_rough_lp += 0.015 * k * (noise - _rough_lp)
		x *= 1.0 + _rough_lp * rough * 3.0 * (1.0 - rpm_n * 0.7)
		x = x / (1.0 + absf(x) * 0.25)  # sanfte Sättigung
		_lp1 += a * (x - _lp1)
		_lp2 += a * (_lp1 - _lp2)
		var s := _lp2 * (0.14 + 0.4 * sqrt(rpm_n) * (0.55 + 0.45 * _thr_s))

		# Bandbegrenztes Rauschen (350–1400 Hz) für Zischen, Reifen, Nitro: kein schrilles Hochtonrauschen
		_n_lo += a_lo * (noise - _n_lo)
		_n_hi += a_hi * (noise - _n_hi)
		_n_top += a_top * (noise - _n_top)
		var band := _n_hi - _n_lo
		# Rasseln: helles Rauschen (1,4–3,6 kHz) im Takt der Zündungen, nur unter Last und mit Drehzahl
		s += (_n_top - _n_hi) * pulse * (0.02 + 0.07 * _thr_s) * (0.3 + rpm_n) * (0.6 + rough)
		if _pop > 0.01:
			s += (_n_top - _n_lo) * _pop * pulse * 0.9
			_pop *= k_pop

		if turbo_amp > 0.0001:
			_turbo_phase = fmod(_turbo_phase + (700.0 + _rpm_s * 0.1) / rate, 1.0)
			s += sin(_turbo_phase * TAU) * turbo_amp
		if _bov > 0.001:
			s += band * _bov * 0.25
			_bov *= k_bov
		if nitro:
			s += band * 0.12
		if _slip_s > 0.02:
			s += band * _slip_s * 0.3
		if _crash > 0.001:
			_crash_lp += 0.08 * k * (noise - _crash_lp)
			s += _crash_lp * _crash * 2.5
			_crash *= k_crash
		_wind_lp += 0.03 * k * (noise - _wind_lp)
		s += _wind_lp * wind_amp

		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	if n > 0:
		_pb.push_buffer(buf)


## Reifenquietschen: setzt weich ein (kein Klick), höher und lauter, je stärker das Auto quer rutscht und je
## schneller es ist; fällt schnell ab, sobald die Reifen wieder greifen
func _update_skid(delta: float) -> void:
	if _skid == null:
		return
	var target := clampf(slip, 0.0, 1.0)
	_skid_k = move_toward(_skid_k, target, delta * (5.0 if target > _skid_k else 3.0))
	_skid.bus = bus
	_skid.volume_db = -80.0 if _skid_k < 0.01 else linear_to_db(_skid_k) * 1.3 - 10.0
	var speed_n := clampf(speed / 50.0, 0.0, 1.0)
	_skid.pitch_scale = 0.86 + 0.18 * _skid_k + 0.12 * speed_n


## Dumpfer Aufprall, Stärke 0..1
func crash(strength: float) -> void:
	_crash = maxf(_crash, clampf(strength, 0.0, 1.0))
