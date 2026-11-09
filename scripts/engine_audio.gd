extends AudioStreamPlayer
## Synthetischer Motorsound in Echtzeit. Grundton aus Drehzahl und Zylinderzahl, Obertöne je nach Auto, dazu die
## Druckstöße im Auspuff (schmale Pulse je Zündung: das gibt den kernigen, hellen Anteil) und ein leises Rasseln
## (Rauschen im Takt der Zündungen) unter Last. Tiefpass bis gut 2 kHz: klar, aber nicht schrill. Lautstärke steigt
## mit Drehzahl und Gas. Beim Hochschalten nimmt der Motor kurz die Zündung weg (shift), Fehlzündungen (backfire,
## von player_car ausgelöst) knallen und blubbern im Auspuff. Mit Nitro klingt er voller und heller.
## Dazu der Turbo (Pfeifen unter Last; Gas weg: Blow-off-Ventil "Pschhh" beim nachgerüsteten Lader, Flattern beim
## Serienlader). Alles andere kommt aus Schleifen (tools/make_sfx.py): road.wav (Abrollen), wind.wav (Fahrtwind),
## scrub.wav (Schrubben, schon bei leichtem Rutschen), skid.wav (Quietschen erst im echten Drift), scrape.wav (Blech
## an der Wand), nitro_on.wav (Zünden), nitro.wav (Fauchen, solange Nitro läuft), nitro_off.wav (Abblasen).
## render_loop() rechnet denselben Klang einmal als kurze Schleife vor (Gegner und Verkehr, ai_car/traffic_car).
## Die Schleifen laufen im Stream-Modus wie der Motor: im Browser spielt Godot sonst fertige Samples ab, deren
## Lautstärke und Tonhöhe sich nicht zuverlässig in jedem Bild nachführen lassen.

## Abtastrate: am Rechner 22 kHz, auf Handy/Tablet die Hälfte (der Klang liegt ohnehin unter 1,5 kHz, und die
## Berechnung läuft Sample für Sample im Skript). k gleicht die Glättung je Sample an die Rate an.
var rate := 22050.0
var k := 1.0

var rpm := 900.0
var throttle := 0.0
var nitro := false
var slip := 0.0  # 0..1 Driftstärke
var speed := 0.0  # m/s
var scrape := 0.0  # 0..1 Schrammen an der Wand

# Motorcharakter (per configure() aus dem Katalog)
var cylinders := 4.0
var harmonics := [1.0, 0.45, 0.2, 0.08]  # Anteile 1x..4x Zündfrequenz
var sub := 0.35  # halber Takt, macht den Leerlauf "bollernd"
var turbo_amount := 0.0
var rough := 0.25
var bov_sound := "flutter"  # Gas weg mit Turbo: "bov" (Ventil, nachgerüstet) oder "flutter" (Serienlader)

var _pb: AudioStreamGeneratorPlayback
## Eine Periode des Klangs (zwei Zündungen, wegen des Halbtakts) als Tabelle: die Schleife liest nur noch nach,
## statt je Sample zehnmal den Sinus zu rechnen (im Browser läuft das Skript deutlich langsamer als am Rechner)
const TAB_N := 1024
var _tab := PackedFloat32Array()  # Grundton, Halbtakt und Obertöne (schon mit norm * 0.8)
var _tab2 := PackedFloat32Array()  # zweite Stimme (Auspuff), auf der leicht verstimmten Phase gelesen
var _tabp := PackedFloat32Array()  # Druckstoß je Zündung (schmaler Puls)
var _tabs := PackedFloat32Array()  # Halbtakt allein (Nitro: tiefer, voller)
var _phase := 0.0
var _turbo_phase := 0.0
var _rpm_s := 900.0
var _thr_s := 0.0
var _lp1 := 0.0
var _lp2 := 0.0
var _rough_lp := 0.0
var _n_lo := 0.0
var _n_hi := 0.0
var _n_top := 0.0
var _pop := 0.0
var _last_throttle := 0.0
var _cut := 0.0  # Zündunterbrechung beim Hochschalten (Restzeit s)
var _cut_s := 1.0
var _turbo := 0.0
var _phase2 := 0.0
var _crash := 0.0
var _crash_lp := 0.0
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


func configure(profile: Dictionary) -> void:
	cylinders = profile.get("cyl", 4)
	harmonics = profile.get("harm", harmonics)
	sub = profile.get("sub", sub)
	turbo_amount = profile.get("turbo", 0.0)
	rough = profile.get("rough", rough)
	bov_sound = profile.get("bov", bov_sound)
	_build_tables()


## Tabellen für eine Periode (Phase 0..2, p = Phase * TAU): dieselben Formeln wie bis 2.19 je Sample
func _build_tables() -> void:
	var h0: float = harmonics[0]
	var h1: float = harmonics[1]
	var h2: float = harmonics[2]
	var h3: float = harmonics[3]
	var norm := 1.0 / (sub + h0 + h1 + h2 + h3) * 0.8
	_tab.resize(TAB_N + 1)  # einzeln: Packed-Arrays sind Werte, in einer Liste würde nur eine Kopie wachsen
	_tab2.resize(TAB_N + 1)
	_tabp.resize(TAB_N + 1)
	_tabs.resize(TAB_N + 1)
	for j in TAB_N + 1:
		var p := float(j) / TAB_N * 2.0 * TAU
		_tab[j] = (sub * sin(0.5 * p) + h0 * sin(p) + h1 * sin(2.0 * p + 0.4) + h2 * sin(3.0 * p + 0.9) + h3 * sin(4.0 * p + 1.3)) * norm
		_tab2[j] = 0.35 * (h0 * sin(p) + h1 * sin(2.0 * p + 1.1)) * norm
		var sp := maxf(sin(p), 0.0)
		_tabp[j] = pow(sp, 6.0)
		_tabs[j] = sin(0.5 * p)


func _ready() -> void:
	if GameState.is_mobile():
		rate = 11025.0
	k = 22050.0 / rate
	if _tab.is_empty():
		_build_tables()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = rate
	gen.buffer_length = 0.08
	stream = gen
	volume_db = -6.0
	# Im Browser spielt Godot Sounds sonst als fertige Samples ab; ein Generator braucht den Stream-Modus
	playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	play()
	_pb = get_stream_playback()
	_skid = _loop("skid")
	_scrub = _loop("scrub")
	_nos = _loop("nitro")
	_scr = _loop("scrape")
	_road = _loop("road")
	_wind = _loop("wind")


func _loop(sound: String) -> AudioStreamPlayer:
	var a := Sfx.looping(sound)
	a.volume_db = -80.0
	a.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(a)
	a.play()
	return a


static var bench_us := 0  # Rechenzeit des Motorklangs (nur für --bench)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_sound(delta)
	bench_us += Time.get_ticks_usec() - t0


func _process_sound(delta: float) -> void:
	_update_skid(delta)
	_update_nitro(delta)
	_update_road()
	if _pb == null:
		return
	if turbo_amount > 0.0 and _last_throttle > 0.6 and throttle < 0.2 and _turbo > 0.5:
		_blow(clampf(_turbo, 0.5, 1.0))
	_last_throttle = throttle
	_cut = maxf(_cut - delta, 0.0)
	_turbo = move_toward(_turbo, throttle * clampf((rpm - 2500.0) / 4000.0, 0.0, 1.0), delta * (1.5 if throttle > 0.5 else 4.0))

	# Pro Block konstante Werte
	var n := _pb.get_frames_available()
	if n <= 0:
		return
	# Drehzahl und Gas glätten (Zeitkonstante wie bisher je Sample, hier für den Block auf einmal) und im Block
	# linear überblenden: so rechnet die Schleife nur noch Additionen statt Glättung, Wurzel und Begrenzung je Sample
	var dec := pow(1.0 - 0.002 * k, n)
	var rpm0 := _rpm_s
	var thr0 := _thr_s
	_rpm_s = rpm + (rpm0 - rpm) * dec
	_thr_s = throttle + (thr0 - throttle) * dec
	var fire := rpm / 60.0 * cylinders / 2.0
	# Obere Frequenzgrenze wächst mit Drehzahl und Last: unter Gas hell und offen (bis ~2,2 kHz), im Schiebebetrieb
	# dumpfer. Bis 2.12 lag sie unter 1 kHz, das klang wie durch eine Wand.
	var cutoff := clampf(fire * 3.0 + throttle * 500.0, 300.0, 1800.0) + _nos_k * 600.0
	if _cut > 0.0:
		cutoff *= 0.6  # Zündung kurz weg: dumpfer
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var turbo_amp := _turbo * turbo_amount * 0.01
	var nos_sub := _nos_k * 0.3  # Nitro: tiefer, voller
	var nos_gain := 1.0 + 0.3 * _nos_k
	var cut_t := 0.3 if _cut > 0.0 else 1.0
	var a_lo := 1.0 - exp(-TAU * 350.0 / rate)
	var a_hi := 1.0 - exp(-TAU * 1400.0 / rate)
	var a_top := 1.0 - exp(-TAU * minf(3600.0, rate * 0.4) / rate)
	var k_pop := pow(0.9985, k)
	var k_crash := pow(0.9996, k)
	var rk := 0.015 * k
	var ck := 0.004 * k
	var crk := 0.08 * k
	# Werte am Anfang und Ende des Blocks: Lautstärke, Druckstöße, Unruhe, Rasseln
	var rn0 := clampf((rpm0 - 800.0) / 7200.0, 0.0, 1.0)
	var rn1 := clampf((_rpm_s - 800.0) / 7200.0, 0.0, 1.0)
	var g := (0.14 + 0.4 * sqrt(rn0) * (0.55 + 0.45 * thr0)) * nos_gain
	var dg := ((0.14 + 0.4 * sqrt(rn1) * (0.55 + 0.45 * _thr_s)) * nos_gain - g) / n
	var pa := 0.15 + 0.2 * thr0
	var dpa := 0.2 * (_thr_s - thr0) / n
	var rf := rough * 3.0 * (1.0 - rn0 * 0.7)
	var drf := (rough * 3.0 * (1.0 - rn1 * 0.7) - rf) / n
	var ra := (0.02 + 0.07 * thr0) * (0.3 + rn0) * (0.6 + rough)
	var dra := ((0.02 + 0.07 * _thr_s) * (0.3 + rn1) * (0.6 + rough) - ra) / n
	var pk := cylinders / 120.0 / rate  # Phase (0..2 = zwei Zündungen) je Sample und U/min
	var inc := rpm0 * pk
	var dinc := (_rpm_s - rpm0) * pk / n
	var t1 := _tab
	var t2 := _tab2
	var tp := _tabp
	var ts := _tabs
	var tk := float(TAB_N) / 2.0
	var t700 := 700.0 / rate
	var tpk := 0.1 / pk / rate
	var buf := PackedVector2Array()
	buf.resize(n)

	for i in n:
		inc += dinc
		_phase += inc
		if _phase >= 2.0:
			_phase -= 2.0
		# Zweite, minimal verstimmte Stimme (Auspuff) macht den Klang voller
		_phase2 += inc * 1.004
		if _phase2 >= 2.0:
			_phase2 -= 2.0
		# Grundton und Obertöne aus der Tabelle (_build_tables), linear zwischen zwei Einträgen
		var fi := _phase * tk
		var ii := int(fi)
		var fr := fi - ii
		var v0 := t1[ii]
		var x := v0 + (t1[ii + 1] - v0) * fr
		var fi2 := _phase2 * tk
		var i2 := int(fi2)
		var w0 := t2[i2]
		x += w0 + (t2[i2 + 1] - w0) * (fi2 - i2)
		if nos_sub > 0.0:
			var u0 := ts[ii]
			x += nos_sub * (u0 + (ts[ii + 1] - u0) * fr)
		# Druckstöße: ein schmaler Puls je Zündung (viele Obertöne), unter Last kräftiger
		var q0 := tp[ii]
		var pulse := q0 + (tp[ii + 1] - q0) * fr
		g += dg
		pa += dpa
		rf += drf
		ra += dra
		x += (pulse - 0.12) * pa
		# Leichte Unruhe über langsam schwankende Amplitude statt kratzigem Rauschen
		var noise := randf() * 2.0 - 1.0
		_rough_lp += rk * (noise - _rough_lp)
		x *= 1.0 + _rough_lp * rf
		x = x / (1.0 + absf(x) * 0.25)  # sanfte Sättigung
		_lp1 += a * (x - _lp1)
		_lp2 += a * (_lp1 - _lp2)
		_cut_s += (cut_t - _cut_s) * ck
		var s := _lp2 * g * _cut_s

		# Bandbegrenztes Rauschen (350–1400 Hz) für Zischen, Reifen, Nitro: kein schrilles Hochtonrauschen
		_n_lo += a_lo * (noise - _n_lo)
		_n_hi += a_hi * (noise - _n_hi)
		_n_top += a_top * (noise - _n_top)
		# Rasseln: helles Rauschen (1,4–3,6 kHz) im Takt der Zündungen, nur unter Last und mit Drehzahl
		s += (_n_top - _n_hi) * pulse * ra
		if _pop > 0.01:
			s += (_n_top - _n_lo) * _pop * pulse * 0.9
			_pop *= k_pop

		if turbo_amp > 0.0001:
			_turbo_phase += t700 + inc * tpk  # Pfeifton 700 Hz + Drehzahl / 10
			if _turbo_phase >= 1.0:
				_turbo_phase -= 1.0
			s += sin(_turbo_phase * TAU) * turbo_amp
		if _crash > 0.001:
			_crash_lp += crk * (noise - _crash_lp)
			s += _crash_lp * _crash * 2.5
			_crash *= k_crash

		s = clampf(s, -1.0, 1.0)
		buf[i] = Vector2(s, s)
	_pb.push_buffer(buf)


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


## Hochschalten: die Zündung ist kurz weg (Motor leiser und dumpfer, dann setzt er im nächsten Gang wieder ein). Mit
## Turbo bläst dabei das Ventil kurz ab.
func shift() -> void:
	_cut = 0.075
	if turbo_amount > 0.3 and _turbo > 0.4:
		_blow(0.45)


## Fehlzündung (Stärke 0..1): Knall mit Druckschlag, dazu blubbert der Motorklang kurz (Rauschen im Zündtakt)
func backfire(strength: float, pitch := 1.0) -> void:
	_pop = maxf(_pop, 0.4 + 0.5 * strength)
	if strength > 0.5:
		var a := Sfx.play("backfire", linear_to_db(strength) - 5.0, randf_range(0.88, 1.12) * pitch)
		if a:
			a.bus = bus


## Gas weg mit Turbo: Blow-off-Ventil oder Flattern des Serienladers
func _blow(strength: float) -> void:
	var a := Sfx.play(bov_sound, linear_to_db(strength * turbo_amount) - 10.0, randf_range(0.94, 1.06))
	if a:
		a.bus = bus


## Dumpfer Aufprall, Stärke 0..1
func crash(strength: float) -> void:
	_crash = maxf(_crash, clampf(strength, 0.0, 1.0))


static var _loops := {}


## Derselbe Motorklang wie im Spiel als kurze, nahtlose Schleife (Gegner, Verkehr): rpm und Gas fest, im Spiel folgt
## die Tonhöhe der Drehzahl (pitch_scale = Drehzahl / rpm). Das Rauschen wird am Ende in den Anfang überblendet;
## die Töne gehen in der Schleifenlänge genau auf. tire: Abrollgeräusch dazumischen (Verkehr). Je Klang nur einmal
## gerechnet (gut 20 ms im Skript).
static func render_loop(profile: Dictionary, rpm: float, thr: float, tire := 0.0) -> AudioStreamWAV:
	var key := "%s|%d|%.2f|%.2f" % [str(profile), int(rpm), thr, tire]
	if _loops.has(key):
		return _loops[key]
	var rate := 11025.0 if GameState.is_mobile() else 22050.0
	var kk := 22050.0 / rate
	var cyl: float = profile.get("cyl", 4)
	var harm: Array = profile.get("harm", [1.0, 0.45, 0.2, 0.08])
	var sub: float = profile.get("sub", 0.35)
	var rough: float = profile.get("rough", 0.25)
	var n := int(rate * 0.6)
	var xf := int(rate * 0.08)
	var warm := int(rate * 0.05)
	# Phase läuft in 0..2 (Halbtakt für das Bollern): ganze Zahl Durchläufe in n Samples -> nahtlos
	var fire := rpm / 60.0 * cyl / 2.0
	var cycles := maxf(roundf(fire * n / rate / 2.0), 1.0)
	var inc := cycles * 2.0 / n
	var rpm_n := clampf((rpm - 800.0) / 7200.0, 0.0, 1.0)
	var cutoff := clampf(fire * 3.0 + thr * 500.0, 300.0, 1800.0)
	var a := 1.0 - exp(-TAU * cutoff / rate)
	var a_lo := 1.0 - exp(-TAU * 300.0 / rate)
	var a_hi := 1.0 - exp(-TAU * 1100.0 / rate)
	var a_top := 1.0 - exp(-TAU * minf(3600.0, rate * 0.4) / rate)
	var h0: float = harm[0]
	var h1: float = harm[1]
	var h2: float = harm[2]
	var h3: float = harm[3]
	var norm := 1.0 / (sub + h0 + h1 + h2 + h3)
	var gain := 0.14 + 0.4 * sqrt(rpm_n) * (0.55 + 0.45 * thr)
	var buf := PackedFloat32Array()
	buf.resize(n + xf)
	var lp1 := 0.0
	var lp2 := 0.0
	var rl := 0.0
	var n_lo := 0.0
	var n_hi := 0.0
	var n_top := 0.0
	var peak := 0.001
	for j in n + xf + warm:
		var i := j - warm
		var p := fmod(float(i) * inc, 2.0) * TAU
		var x := sub * sin(0.5 * p) + h0 * sin(p) + h1 * sin(2.0 * p + 0.4) + h2 * sin(3.0 * p + 0.9) + h3 * sin(4.0 * p + 1.3)
		x += 0.35 * (h0 * sin(p + 0.7) + h1 * sin(2.0 * p + 1.8))
		x *= norm * 0.8
		var sp := maxf(sin(p), 0.0)
		var sp2 := sp * sp
		var pulse := sp2 * sp2 * sp2
		x += (pulse - 0.12) * (0.15 + 0.2 * thr)
		var noise := randf() * 2.0 - 1.0
		rl += 0.015 * kk * (noise - rl)
		x *= 1.0 + rl * rough * 3.0 * (1.0 - rpm_n * 0.7)
		x = x / (1.0 + absf(x) * 0.25)
		lp1 += a * (x - lp1)
		lp2 += a * (lp1 - lp2)
		var s := lp2 * gain
		n_lo += a_lo * (noise - n_lo)
		n_hi += a_hi * (noise - n_hi)
		n_top += a_top * (noise - n_top)
		s += (n_top - n_hi) * pulse * (0.02 + 0.07 * thr) * (0.3 + rpm_n) * (0.6 + rough)
		s += (n_hi - n_lo) * tire
		if i >= 0:
			buf[i] = s
			peak = maxf(peak, absf(s))
	# Ende in den Anfang überblenden (gleiche Leistung)
	for i in xf:
		var t := float(i) / xf
		buf[i] = buf[i] * sqrt(t) + buf[n + i] * sqrt(1.0 - t)
	var data := PackedByteArray()
	data.resize(n * 2)
	var g := 0.85 / peak
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = int(rate)
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	w.set_meta("rpm", inc * rate * 120.0 / cyl)  # tatsächliche Drehzahl der Schleife (Zündfrequenz * 120 / Zylinder)
	_loops[key] = w
	return w
