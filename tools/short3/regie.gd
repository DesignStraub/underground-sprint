extends SceneTree
## Regie für die Shorts zu 2.39 (tools/short3): lädt die Welt, setzt das Auto an den Anfang eines Ablaufs und fährt ihn
## wie ein Spieler (Gas, Bremse, Lenken über die Eingaben, während der Fahrt kein Versetzen), bei Bedarf mit eigener
## Kamera. Das Spiel bleibt unverändert: die Welt liest ihre Argumente (--tod, --nozoom, --zkind, --wstart ...) wie sonst.
## Aufruf über rec.sh: godot --path . -s res://tools/short3/regie.gd -- --regie=<ablauf> [Welt-Argumente]
## Abläufe:
##   anflug:<i>[:d] Start wie aus der Garage in Stadt i (dazu --wstart=<i>) oder auf der Hauptstraße bei d (dann mit
##                  --zkind=start): Anflug von oben, danach die Hauptstraße entlang (Gas schon während des Anflugs
##                  gehalten: fährt los, sobald die Kamera hinter dem Auto ist)
##   kreuzung       Rostock: Parallelstraße zur Kreuzung mit Ampel und Zebrastreifen, Halt bei Rot, bei Grün geradeaus
##                  über die Hauptstraße in die Gasse mit Kopfsteinpflaster und hindurch (Kamera hebt am Ende ab:
##                  --rkran=<s> nach s Sekunden Gasse, 0 = aus)
##   golf           Querspange, auf der Gegenfahrbahn: am Wegweiser "Ausfahrt Golfplatz" vorbei, links über den offenen
##                  Mittelstreifen abbiegen, durchs Tor, aufs Fairway, dort quer (Spuren, Staub)
##   schild:<i>     am gelben Ortsschild von Stadt i vorbei, Kamera fest am Straßenrand (HUD aus)
##   einfahrt:<i>   von der Autobahn über die Auffahrt in Stadt i: oben der Ortsname, bei Stadt-Tracks unten Titel und
##                  Künstler (mit --nomusic stumm, die Einblendung kommt trotzdem)
##   dom            Aachen: auf dem Grabenring am Dom vorbei, Kamera hinter dem Auto auf der Linie zum Dom: vorn das
##                  Auto, dahinter Dom, Rathaus und Elisenbrunnen
##   kies[:n]       Kiesgrube: mit 75 km/h über den n-ten hohen Haufen (Standard 1, wie offroad_test kuppen:1),
##                  Kamera fest hinter der Landestelle, schaut dem Auto nach: es kommt über die Spitze auf die Kamera zu
##   fahrt:<i>:<d>[:m] Stadt i: Hauptstraße ab d (m Meter, Standard 400) rechts in der Spur, Verfolgerkamera
##   garage[:t]     Garage im Autohaus: das Auto fährt auf dem Band, nach t Sekunden (Standard 3) das nächste Auto
##                  (es fährt herein, das bisherige hinaus); --rhud=0 ohne Menü
##   frei           nur Kamera und Anzeigen einstellen, die Welt fährt selbst (z. B. mit --otest=rampen:0)
## Schalter: --rquit=<s> Ende nach s Sekunden, --rlog Lage alle 0,5 s ("R ..."), --rhud=0 HUD aus, --rui=<k> Oberfläche
## k-fach größer (Ortsname, Musiktitel lesbar im Hochformat), --rwait=<s> vor dem Losfahren warten, --rcam=<0|1>
## Verfolgerkamera (1 = weit), --rkam=ampel (Kreuzung: feste Kamera vor der Ampel der Querstraße), --rvor=<m> (Start so
## weit vor dem Schild, dem Ende der Auffahrt, der Golfplatz-Ausfahrt bzw. dem Dom), --rv0=<m/s> (Anfangstempo),
## --rschild=<m>:<fov> (Schild: Kamera so weit davor, Bildwinkel), --rtoast=<s> (Titel des laufenden Tracks nach s
## Sekunden noch einmal einblenden), --rtoastk=<k> (Titel-Einblendung k-fach größer, unten in der Mitte verankert:
## im Hochformat sonst kaum lesbar). Level-Leiste unten und Tastenhilfe oben sind aus. Die Titel-Einblendung der Musik
## läuft hier in Spielzeit (music.gd zählt sonst Echtzeit: bei --write-movie lief sie zu schnell oder war schon vorbei).
## Fürs Schneiden: "REGIE MARKE <was> t=<s> bild=<n>" im Log (start, aktiv <Strecke>, anflug, ampel, halt, weiter, kran,
## wegweiser, gelaende, drift, flug, sprungkamera, weg <art>, autowechsel); Bild n-1 ist das Bild in der Aufnahme.

# Spielskripte erst zur Laufzeit laden (nach dem Start der Autoloads, die sie benutzen)
var Layout
var Track
var Offroad
var Streets
var Catalog

var shot := ""
var arg := PackedStringArray()  # Teile von --regie (nach dem Namen)
var w = null  # world.gd
var t := 0.0  # Zeit seit Programmstart (bei fester Bildrate wie TIME im Shader: Ampeln)
var rt := -1.0  # Zeit seit Beginn des Ablaufs (-1: Welt lädt noch)
var quit_after := 40.0
var log_on := false
var _log_t := 0.0
var hud_on := true
var wait0 := 0.0
var route: Array = []  # [{p: Vector3 (Welt), v: m/s, stop: Callable (optional: wartet hier, bis sie true liefert)}]
var ri := 0
var halt := false
var halt_t := 0.0
var done := false
var phase := ""
var cam: Camera3D
var cam_fn := Callable()  # setzt die eigene Kamera je Bild
var info := {}  # Daten des Ablaufs (Ampelphase, Lage des Schilds ...)
var drift_t := -1.0
var drift_at := -1  # Routenindex, ab dem gedriftet wird
var _spawn := Transform3D.IDENTITY
var _has_spawn := false
var _quiet := false
var cam_mode := -1
var kam := ""
var vor := -1.0
var v0 := 0.0
var schild_m := 30.0
var schild_fov := 32.0
var toast_at := -1.0
var toast_k := 1.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--regie="):
			var p := a.substr(8).split(":")
			shot = p[0]
			arg = p.slice(1)
		elif a.begins_with("--rquit="):
			quit_after = float(a.substr(8))
		elif a == "--rlog":
			log_on = true
		elif a == "--rhud=0":
			hud_on = false
		elif a.begins_with("--rwait="):
			wait0 = float(a.substr(8))
		elif a.begins_with("--rcam="):
			cam_mode = int(a.substr(7))
		elif a.begins_with("--rkam="):
			kam = a.substr(7)
		elif a.begins_with("--rvor="):
			vor = float(a.substr(7))
		elif a.begins_with("--rv0="):
			v0 = float(a.substr(6))
		elif a.begins_with("--rschild="):
			var sp := a.substr(10).split(":")
			schild_m = float(sp[0])
			schild_fov = float(sp[1]) if sp.size() > 1 else 32.0
		elif a.begins_with("--rtoast="):
			toast_at = float(a.substr(9))
		elif a.begins_with("--rtoastk="):
			toast_k = float(a.substr(10))
	await process_frame
	if cam_mode >= 0:
		root.get_node("GameState").cam_mode = cam_mode  # 1 = Verfolger weit: im Hochformat wirkt das Auto sonst riesig
	Layout = load("res://scripts/world_layout.gd")
	Track = load("res://scripts/track_builder.gd")
	Offroad = load("res://scripts/offroad.gd")
	Streets = load("res://scripts/street_net.gd")
	Catalog = load("res://scripts/catalog.gd")
	_plan_spawn()
	if _has_spawn:
		# wie die Rückkehr aus einem Rennen: die Welt baut hinter dem Ladebild alles um diese Stelle und setzt das Auto dort hin
		var ws = load("res://scripts/world.gd")
		ws.return_xf = _spawn
		ws.has_return = true
	if shot == "garage":
		root.get_node("GameState").world_menu = "cars"  # Garage öffnet direkt im Autohaus (wie aus der Welt)
	var scene: Node = (load("res://scenes/garage.tscn" if shot == "garage" else "res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	w = scene
	if _quiet:
		w.set("quiet", true)  # kein Verkehr, keine Herausforderer (wird in _ready vor dem ersten Bau gesetzt, hier überschrieben)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rui="):
			root.content_scale_factor = float(a.substr(6))
	print("REGIE %s %s spawn=%s" % [shot, str(arg), str(_spawn.origin) if _has_spawn else "-"])


# --- Startpunkt vor dem Laden ---------------------------------------------------------------------------------------

func _plan_spawn() -> void:
	var lay: Dictionary = Layout.build()
	match shot:
		"kreuzung":
			var c := _layout_city(lay, 13)
			var tr := _plan_track(c["race"])
			var k := _crossing(tr)
			var p9: Dictionary = tr["paths"][k["in"]]
			var L: float = (p9["curve"] as Curve3D).get_baked_length()
			_spawn = c["xf"] * Track.xform_at(p9["curve"], L - 122.0, 1.6)
			_spawn.origin.y += 0.4
			_has_spawn = true
		"golf":
			_quiet = true
			var a: Dictionary = lay["offroad"][0]
			var sg := _layout_host(lay, a)
			var tr := _plan_track(sg["race"])
			var g := _golf_geo(a, tr)
			_spawn = Track.xform_at(tr["curve"], g["d0"] - g["dir"] * (vor if vor > 0.0 else 360.0), 11.25 * g["dir"])
			if g["dir"] < 0.0:
				_spawn.basis = _spawn.basis * Basis(Vector3.UP, PI)
			_spawn.origin.y += 0.4
			_has_spawn = true
		"schild", "dom", "fahrt":
			var ci := 15 if shot == "dom" else int(arg[0])
			var c := _layout_city(lay, ci)
			var tr := _plan_track(c["race"])
			var d := _sign_d(tr) - (vor if vor > 0.0 else 135.0) if shot == "schild" else _dom_d(tr) - (vor if vor > 0.0 else 150.0)
			if shot == "fahrt":
				d = float(arg[1])
			_spawn = c["xf"] * Track.xform_at(tr["curve"], d, Track.lane_lat(tr, d, 8.0 if shot == "schild" else 2.25))
			if shot == "fahrt" and arg.size() > 2 and float(arg[2]) < 0.0:
				_spawn.basis = _spawn.basis * Basis(Vector3.UP, PI)  # gegen die Streckenrichtung
			_spawn.origin.y += 0.4
			_has_spawn = true
		"kies":
			var a: Dictionary = lay["offroad"][1]
			var k := _kies_try(a, int(arg[0]) if arg.size() > 0 else 1)
			var st: Vector2 = k["start"]
			var dd: Vector2 = k["dir"]
			var gl: Vector2 = Offroad.local(a, st)
			_spawn = Transform3D(Basis.looking_at(Vector3(dd.x, 0, dd.y), Vector3.UP), Vector3(st.x, float(Offroad.base_h(a, gl)) + 0.05, st.y))
			_has_spawn = true
			_quiet = true
			if v0 <= 0.0:
				v0 = 75.0 / 3.6
		"anflug":
			if arg.size() > 1:
				var c := _layout_city(lay, int(arg[0]))
				var tr := _plan_track(c["race"])
				var d := float(arg[1])
				_spawn = c["xf"] * Track.xform_at(tr["curve"], d, Track.lane_lat(tr, d, 2.25))
				_spawn.origin.y += 0.4
				_has_spawn = true
		"einfahrt":
			var c := _layout_city(lay, int(arg[0]))
			var town: String = Catalog.RACES[int(arg[0])].get("town", "")
			for sg in lay["segments"]:
				for r in sg["race"].get("ramps", []):
					if str(r.get("name", "")) == town and not r.has("c1") and not r.get("gelaende", false):
						if vor > 0.0:
							# auf der Auffahrt (gerade von der Mittellinie zur Ausfahrt der Stadt), vor m vor ihrem Ende
							var a3: Vector3 = r["from"]
							var b3: Vector3 = r["end"]
							var dir3 := Vector3(b3.x - a3.x, 0.0, b3.z - a3.z).normalized()
							vor = minf(vor, Vector2(b3.x - a3.x, b3.z - a3.z).length() - 20.0)  # nicht auf die Autobahn
							_spawn = Transform3D(Basis.looking_at(dir3, Vector3.UP), Vector3(b3.x, 0.4, b3.z) - dir3 * vor)
						else:
							var tr := _plan_track(sg["race"])
							var g := _ramp_geo(tr, town)
							_spawn = Track.xform_at(tr["curve"], g["d0"] - g["dir"] * 230.0, 11.25 * g["side"])
							if g["dir"] < 0.0:
								_spawn.basis = _spawn.basis * Basis(Vector3.UP, PI)
							_spawn.origin.y += 0.4
						_has_spawn = true
						return
			push_warning("REGIE keine Auffahrt nach %s (Stadt %s)" % [town, str(c.get("race_index", -1))])


func _layout_city(lay: Dictionary, ri_: int) -> Dictionary:
	for c in lay["cities"]:
		if c["race_index"] == ri_:
			return c
	return {}


## Gelände a: das Autobahnstück mit seiner Ausfahrt
func _layout_host(lay: Dictionary, a: Dictionary) -> Dictionary:
	for sg in lay["segments"]:
		for r in sg["race"].get("ramps", []):
			if r.get("gelaende", false) and str(r.get("name", "")) == str(a["exit"]):
				return sg
	return {}


## Strecke nur planen (Wege, Einmündungen), ohne sie in die Welt zu hängen
func _plan_track(race: Dictionary) -> Dictionary:
	var job: Dictionary = Track.begin(race)
	(job["root"] as Node).free()
	return job["track"]


# --- Geometrie ------------------------------------------------------------------------------------------------------

## Kreuzung mit Ampel, an der eine Straße (mit Zebrastreifen) ankommt und gegenüber eine Gasse mit Kopfsteinpflaster
## beginnt: {in: Weg der Straße (endet an der Hauptstraße), out: Weg der Gasse, d: Stelle an der Hauptstraße}
func _crossing(tr: Dictionary) -> Dictionary:
	for j in tr.get("junctions", []):
		if not j["x"] or j["start"]:
			continue
		var pi: Dictionary = tr["paths"][j["path"]]
		if pi.get("cls", "") == "gasse":
			continue
		for o in tr["junctions"]:
			if o["x"] and o["start"] and o["path"] != j["path"] and absf(float(o["d"]) - float(j["d"])) < 14.0:
				var po: Dictionary = tr["paths"][o["path"]]
				if po.get("cls", "") == "gasse" and float(po.get("cobble", 0.0)) > 0.5:
					return {"in": j["path"], "out": o["path"], "d": float(j["d"])}
	return {}


## Ausfahrt eines Geländes: Stelle d0 auf dem Stück, Seite (+1 rechts in Streckenrichtung) und Fahrtrichtung: auf der
## Gegenfahrbahn, die Ausfahrt liegt dann links (über den offenen Mittelstreifen). Grund: auf der Fahrbahn mit der
## Ausfahrt rechts zeigt der Wegweiser 260 m davor in Aufnahmen seine Rückseite (siehe Bericht: track_builder._exit_signs
## versetzt Tafel und Schrift in Welt- statt Schild-Richtung, nur nach Süden gewandte Schilder stimmen)
func _golf_geo(a: Dictionary, tr: Dictionary) -> Dictionary:
	var c: Curve3D = tr["curve"]
	var d0: float = a["exit_d"]
	var gate: Vector2 = Offroad.world(a, Vector2(a["gate_s"], 0.0))
	var f: Dictionary = Track.frame_at(c, d0)
	var side := signf((Vector3(gate.x, 0, gate.y) - (f["pos"] as Vector3)).dot(f["right"]))
	return {"d0": d0, "side": side, "dir": -side}


## Auffahrt vom Autobahnstück zur Stadt town: Stelle an der Mittellinie, Seite, Fahrtrichtung (Ausfahrt rechts)
func _ramp_geo(tr: Dictionary, town: String) -> Dictionary:
	for p in tr["paths"]:
		if p["kind"] == "ramp" and str(p.get("name", "")) == town and not p.get("conn", false):
			var side: float = p["side"]
			return {"d0": float(p["from"]), "side": side, "dir": side, "path": p["id"]}
	return {"d0": 0.0, "side": 1.0, "dir": 1.0, "path": -1}


## Gelbes Ortsschild: track_builder._build_city_signs stellt es 55 m hinter den Start
func _sign_d(tr: Dictionary) -> float:
	return float(tr["start"]) + 55.0


func _dom_d(tr: Dictionary) -> float:
	for lm in tr["city"].get("landmarks", []):
		if lm["kind"] == "aachen_dom":
			return (tr["curve"] as Curve3D).get_closest_offset(Vector3(lm["x"], 0, lm["z"]))
	return 0.0


## Eintrag der Welt (gebaut) zur Stadt i
func _city(i: int) -> Dictionary:
	for e in w.entries:
		if e["kind"] == "city" and e["race_index"] == i:
			return e
	return {}


## Punkte entlang eines Wegs (Weltkoordinaten) von d0 nach d1 (rückwärts, wenn d1 < d0), lat m rechts der
## Fahrtrichtung (Hauptstraße: Spur-Koordinate, der Mittelstreifen wird herausgerechnet)
func _along(e: Dictionary, pid: int, d0: float, d1: float, lat: float, v: float, step := 3.0) -> Array:
	var tr: Dictionary = e["track"]
	var xf: Transform3D = e["xf"]
	var c: Curve3D = tr["paths"][pid]["curve"]
	var L := c.get_baked_length()
	var dir := 1.0 if d1 >= d0 else -1.0
	var n := maxi(int(absf(d1 - d0) / step), 1)
	var out := []
	for i in n + 1:
		var d := lerpf(d0, d1, float(i) / n)
		var dd := fposmod(d, L) if bool(tr["loop"]) and pid == 0 else clampf(d, 0.0, L)
		var f: Dictionary = Track.frame_at(c, dd)
		var l := lat * dir
		if pid == 0:
			l = Track.lane_lat(tr, dd, lat * dir)
		var q: Vector3 = (f["pos"] as Vector3) + (f["right"] as Vector3) * l + Vector3(0, f["y"], 0)
		out.append({"p": xf * q, "v": v})
	return out


func _pt(p: Vector3, v: float) -> Dictionary:
	return {"p": p, "v": v}


# --- Ablauf ---------------------------------------------------------------------------------------------------------

func _process(delta: float) -> bool:
	t += delta
	# Titel-Einblendung der Musik in Spielzeit (music.gd rechnet mit Echtzeit; Aufnahmen laufen langsamer als Echtzeit)
	var mu = root.get_node_or_null("Music")
	if mu:
		mu._last_ms = Time.get_ticks_msec() - int(round(delta * 1000.0))
		if toast_k != 1.0 and mu._toast != null:
			# Ebene der Einblendung vergrößern, Anker unten in der Mitte (music._draw_toast: Mitte der Blase 28 px über dem Rand)
			var lay: CanvasLayer = mu._toast.get_parent()
			var vs: Vector2 = mu._toast.get_viewport_rect().size
			lay.scale = Vector2(toast_k, toast_k)
			lay.offset = Vector2(vs.x / 2.0, vs.y - 28.0) * (1.0 - toast_k)
		if toast_at >= 0.0 and rt >= toast_at:
			toast_at = -1.0
			mu._start_toast()
			print("REGIE Titel eingeblendet bei rt=%.2f: %s" % [rt, mu.current_title])
	if w != null and shot == "garage":
		return _garage(delta)
	if w == null or not bool(w.get("_ready_done")):
		return false
	var pl = w.player
	if rt < 0.0:
		rt = 0.0
		_mark("start")  # erstes Bild ohne Ladebild
		_begin(pl)
		if v0 > 0.0:
			var f0: Vector3 = -pl.global_basis.z
			pl.velocity = Vector3(f0.x, 0.0, f0.z).normalized() * v0
			pl.speed_fwd = v0
		if not hud_on:
			(w.hud["root"] as Control).visible = false
		if w.hud.has("help"):
			(w.hud["help"] as Control).visible = false  # Tastenhilfe oben rechts: im Video nur Unruhe
		# Level-Leiste unten (Test-Spielstand: Level 99 mit unsinnigen XP-Zahlen): Text, Füllung und Hintergrund aus
		if w.hud.has("lvl"):
			var fill: Control = w.hud["lvl_fill"]
			var bg := fill.get_parent().get_child(fill.get_index() - 1)
			if bg is ColorRect:
				(bg as ColorRect).visible = false
			fill.visible = false
			(w.hud["lvl"] as Control).visible = false
	rt += delta
	_events(pl)
	if cam_fn.is_valid():
		cam_fn.call(pl)
	if log_on:
		_log_t -= delta
		if _log_t <= 0.0:
			_log_t = 0.5
			var p: Vector3 = pl.global_position
			print("R t=%.2f rt=%.2f pos=(%.1f, %.1f, %.1f) v=%.1f ri=%d/%d halt=%s phase=%s weg=%s %s" % [t, rt, p.x, p.y, p.z,
				float(pl.speed_fwd) * 3.6, ri, route.size(), halt, phase, str(pl.loc.get("path", {}).get("kind", "-")),
				_light_txt()])
	if rt > quit_after:
		# nicht beenden, solange im Hintergrund gebaut wird (Strecke, Landschaft, Gelände): beim Beenden warten
		# world/landscape/offroad_build in _exit_tree auf ihren Bau, und das Programm hing dann (Aufnahme ohne Abschluss)
		if _busy() and rt < quit_after + 12.0:
			return false
		print("REGIE ENDE %s nach %.1f s" % [shot, rt])
		quit()
	return false


func _physics_process(_delta: float) -> bool:
	if rt < 0.0 or done or shot == "garage" or shot == "frei":
		return false  # Garage und "frei": keine eigenen Eingaben (die Welt bzw. der Gelände-Test fährt selbst)
	var pl = w.player
	for a in ["steer_left", "steer_right", "accelerate", "brake", "handbrake", "nitro"]:
		Input.action_release(a)
	if rt < wait0:
		return false
	if drift_t >= 0.0:
		_drift(pl, _delta)
		return false
	if not route.is_empty() and bool(pl.controls_enabled):
		_follow(pl)
	elif not route.is_empty():
		Input.action_press("accelerate")  # Anflug: Gas halten, fährt los, sobald die Kamera hinter dem Auto ist
	return false


func _begin(pl) -> void:
	match shot:
		"anflug":
			var e := _city(int(arg[0]))
			var tr: Dictionary = e["track"]
			var d0: float = tr["curve"].get_closest_offset((e["xf"] as Transform3D).affine_inverse() * pl.global_position)
			route = [_pt(pl.global_position, 8.0)] + _along(e, 0, d0 + 12.0, d0 + 600.0, 2.25, 17.0)
		"kreuzung":
			_begin_kreuzung(pl)
		"golf":
			_begin_golf(pl)
		"schild":
			_begin_schild(pl)
		"einfahrt":
			_begin_einfahrt(pl)
		"dom":
			_begin_dom(pl)
		"frei":
			pass
		"kies":
			_begin_kies(pl)
		"fahrt":
			var e := _city(int(arg[0]))
			var tr: Dictionary = e["track"]
			var d0: float = tr["curve"].get_closest_offset((e["xf"] as Transform3D).affine_inverse() * pl.global_position)
			var m := float(arg[2]) if arg.size() > 2 else 400.0
			route = _along(e, 0, d0 + 3.0 * signf(m), d0 + m, 2.25, 16.0)
		_:
			push_warning("REGIE unbekannter Ablauf %s" % shot)
			quit()


## Rostock: auf der Straße (rechte Spur) zur Kreuzung, vor dem Zebrastreifen halten, bis die Ampel für die Querstraße
## grün zeigt (traffic_light.gdshader: grün 5 s, gelb 1,5 s, rot 5 s, rot-gelb 0,5 s; Phase wie street_net._signal),
## dann geradeaus über die Hauptstraße in die Gasse
func _begin_kreuzung(pl) -> void:
	var e := _city(13)
	var tr: Dictionary = e["track"]
	var k := _crossing(tr)
	var pin: Dictionary = tr["paths"][k["in"]]
	var pout: Dictionary = tr["paths"][k["out"]]
	var Li: float = (pin["curve"] as Curve3D).get_baked_length()
	var Lo: float = (pout["curve"] as Curve3D).get_baked_length()
	# Zebrastreifen wie street_net.build_junctions: erste Stelle von der Hauptstraße aus, die frei vom Gehweg ist
	var at := Li
	var dd := 0.0
	while dd < minf(Li, 60.0):
		if Streets.main_clear(tr, (pin["curve"] as Curve3D).sample_baked(Li - dd)) > Track.WALK + 1.5:
			at = Li - dd
			break
		dd += 1.0
	var stop_d := at - 4.2  # Wagenmitte: die Front steht knapp vor dem Zebrastreifen
	info["ph"] = 3.0 * float(posmod(int(k["d"]), 4)) + 6.0  # Ampel der Querstraße
	info["zebra"] = e["xf"] * (pin["curve"] as Curve3D).sample_baked(at)
	var d_pl: float = (pin["curve"] as Curve3D).get_closest_offset((e["xf"] as Transform3D).affine_inverse() * pl.global_position)
	route = _along(e, k["in"], d_pl + 4.0, stop_d - 22.0, 1.6, 9.0)
	route += _along(e, k["in"], stop_d - 19.0, stop_d, 1.6, 4.0)
	route[-1]["v"] = 0.0
	route[-1]["stop"] = func() -> bool: return rt - halt_t > 2.5 and _green_for(0.45)
	route += _along(e, k["in"], stop_d + 4.0, Li - 3.0, 1.2, 7.0)
	route += _along(e, k["out"], 3.0, Lo - 6.0, 0.0, 9.5)
	print("REGIE kreuzung d=%.0f Straße=%d Gasse=%d (%.0f m) halt bei %.1f von %.1f, Zebrastreifen %s" % [k["d"], k["in"], k["out"],
		Lo, stop_d, Li, str(info["zebra"])])
	if kam == "ampel":
		# Ampel der Querstraße wie street_net.build_junctions: an der rechten Ecke, Kopf auf 3,1 m, schaut der Straße entgegen
		var cv: Curve3D = pin["curve"]
		var fs: Dictionary = Track.frame_at(cv, at)
		var toward: Vector3 = fs["fwd"]
		var right_side: Vector3 = toward.cross(Vector3.UP).normalized()
		var corner: Vector3 = (fs["pos"] as Vector3) + right_side * (float(pin["half_w"]) + 0.9) - toward * 0.5
		var head: Vector3 = e["xf"] * (corner + Vector3(0, Track.CURB_H + 3.25, 0))
		var wdir: Vector3 = (e["xf"] as Transform3D).basis * toward
		var wr: Vector3 = (e["xf"] as Transform3D).basis * right_side
		var cp := head - wdir * 4.2 - wr * 1.6 - Vector3.UP * 1.1
		info["cam_xf"] = Transform3D(Basis.IDENTITY, cp).looking_at(head + wdir * 0.8 - wr * 0.1, Vector3.UP)
		info["cam_fov"] = 44.0
		cam_fn = _fixed_cam
	var kran := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rkran="):
			kran = float(a.substr(8))
	if kran > 0.0:
		info["kran_from"] = route.size() - _along(e, k["out"], 3.0, Lo - 6.0, 0.0, 9.5).size()
		info["kran_after"] = kran
		cam_fn = _kran_cam


## Ampel der Querstraße: seit wann (s) grün? -1 = nicht grün
func _green_age() -> float:
	if not info.has("ph"):
		return -1.0
	var m := fposmod(t + float(info["ph"]), 12.0)
	return m if m < 5.0 else -1.0


func _green_for(s: float) -> bool:
	var g := _green_age()
	return g >= s and g < s + 0.8


func _light_txt() -> String:
	if not info.has("ph"):
		return ""
	var m := fposmod(t + float(info["ph"]), 12.0)
	return "licht=" + ("grün" if m < 5.0 else ("gelb" if m < 6.5 else ("rot" if m < 11.5 else "rotgelb"))) + " %.1f" % m


## Kran: ab info.kran_after Sekunden in der Gasse hebt die Kamera hinter dem Auto ab (in gut 3 s auf 55 m, Blick über
## die Dächer nach vorn): die Stadt geht hinter der Häuserfront weiter
func _kran_cam(pl) -> void:
	if ri < int(info["kran_from"]):
		info["kran_t0"] = -1.0
		return
	if float(info.get("kran_t0", -1.0)) < 0.0:
		info["kran_t0"] = rt
	var u := clampf((rt - float(info["kran_t0"]) - float(info["kran_after"])) / 3.4, 0.0, 1.0)
	if u <= 0.0:
		return
	if not _ev.has("kran"):
		_ev["kran"] = true
		_mark("kran")
	if cam == null:
		cam = Camera3D.new()
		cam.far = 3000.0
		w.world.add_child(cam)
	var k := u * u * (3.0 - 2.0 * u)
	var pc: Transform3D = pl.cam.global_transform
	var fwd: Vector3 = -pl.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p: Vector3 = pl.global_position
	var top := p - fwd * 30.0 + Vector3.UP * 55.0
	var look := p + fwd * 70.0
	var xf := Transform3D(Basis.IDENTITY, top).looking_at(look, Vector3.UP)
	cam.global_transform = Transform3D(pc.basis.slerp(xf.basis, k), pc.origin.lerp(top, k))
	cam.fov = lerpf(pl.cam.fov, 62.0, k)
	cam.make_current()
	if hud_on:
		(w.hud["root"] as Control).modulate.a = 1.0 - k


## Querspange: rechte Spur mit 80 km/h am Wegweiser vorbei, vor der Ausfahrt abbremsen, eng einbiegen (wie
## offroad_test._route_in), durchs Tor über den Parkplatz aufs Fairway der ersten Bahn, dort mit Gas und Lenkung quer
func _begin_golf(pl) -> void:
	var a: Dictionary = w.layout["offroad"][0]
	var host := {}
	for e in w.entries:
		if e["kind"] == "seg" and e["state"] == "ready":
			for p in e["track"]["paths"]:
				if p.get("gelaende", false) and str(p.get("name", "")) == str(a["exit"]):
					host = e
	var tr: Dictionary = host["track"]
	var c: Curve3D = tr["curve"]
	var g := _golf_geo(a, tr)
	var d0: float = g["d0"]
	var side: float = g["side"]
	var dir: float = g["dir"]
	var lane := func(dd: float, lat: float) -> Vector3:
		var ff: Dictionary = Track.frame_at(c, dd)
		return (ff["pos"] as Vector3) + (ff["right"] as Vector3) * lat
	# auf der Gegenfahrbahn (rechte Spur: 11,25 * dir), vor der Ausfahrt abbremsen, links über den offenen
	# Mittelstreifen und die andere Fahrbahn auf die Zufahrt (sie liegt auf der Seite side)
	route = []
	var s := 460.0
	while s > 95.0:
		route.append(_pt(lane.call(d0 - dir * s, 11.25 * dir), 22.0))
		s -= 6.0
	route += [_pt(lane.call(d0 - dir * 62.0, 6.75 * dir), 15.0), _pt(lane.call(d0 - dir * 30.0, 2.25 * dir), 9.0),
		_pt(lane.call(d0 - dir * 12.0, 1.5 * side), 7.0), _pt(lane.call(d0 - dir * 3.0, 8.0 * side), 6.5),
		_pt(lane.call(d0, 15.0 * side), 6.5), _pt(lane.call(d0, 24.0 * side), 8.0), _pt(lane.call(d0, 46.0 * side), 15.0)]
	var gs: float = a["gate_s"]
	# wie offroad_test._route_in: am Parkplatz zwischen den Laternen hindurch, an der Baumgruppe vorbei aufs Fairway
	for q in [[Vector2(gs, -6.0), 11.0], [Vector2(gs, 16.0), 13.0], [Vector2(-112, 38), 16.0], [Vector2(-86, 66), 19.0],
			[Vector2(-60, 92), 21.0], [Vector2(-30, 102), 22.0], [Vector2(0, 108), 22.0], [Vector2(30, 115), 22.0],
			[Vector2(60, 122), 20.0], [Vector2(90, 150), 16.0]]:
		var wq: Vector2 = Offroad.world(a, q[0])
		route.append(_pt(Vector3(wq.x, 0, wq.y), q[1]))
	drift_at = route.size() - 5  # auf dem Fairway quer
	info["wegweiser"] = lane.call(d0 - dir * 260.0, 11.25 * dir)  # Wegweiser "Ausfahrt Golfplatz" (track_builder._exit_signs)
	print("REGIE golf d0=%.0f Seite %d, Tor %s" % [d0, int(side), str(Offroad.world(a, Vector2(gs, 0.0)))])


## Quer auf dem Gras: kurz Handbremse mit vollem Einschlag, dann Vollgas halb eingelenkt (das Heck kommt, Staub)
func _drift(pl, dt: float) -> void:
	drift_t += dt
	var dir := -1.0 if info.get("drift_left", true) else 1.0
	var act := "steer_left" if dir < 0.0 else "steer_right"
	var cnt := "steer_right" if dir < 0.0 else "steer_left"
	if drift_t < 0.55:
		Input.action_press("handbrake")
		Input.action_press(act)
		Input.action_press("accelerate", 0.7)
	elif drift_t < 2.2:
		Input.action_press("accelerate")
		Input.action_press(act, 0.75)
	elif drift_t < 2.9:
		Input.action_press("accelerate")
		Input.action_press(cnt, 0.45)
	else:
		drift_t = -1.0
		drift_at = -1
		# danach wieder dem Weg folgen, ab dem nächsten Punkt vor dem Auto
		var p: Vector3 = pl.global_position
		var best := ri
		var bd := INF
		for k in range(ri, route.size()):
			var dd := Vector2(route[k]["p"].x - p.x, route[k]["p"].z - p.z).length()
			if dd < bd:
				bd = dd
				best = k
		ri = mini(best + 1, route.size() - 1)


## Anlauf über einen hohen Haufen der Kiesgrube wie offroad_test._next_try (Richtung mit dem meisten Platz davor und
## dahinter, Anlauf auf ebenem Boden bis 75 m): {start, dir, tip (Fuß des Haufens), c (Mitte), r, h} in Welt-xz
func _kies_try(a: Dictionary, n: int) -> Dictionary:
	var piles := []
	for pr in a["prims"]:
		if (pr["k"] == "hill" or pr["k"] == "pile") and float(pr["h"]) >= 2.4:
			piles.append(pr)
	var pr: Dictionary = piles[clampi(n - 1, 0, piles.size() - 1)]
	var c: Vector2 = pr["c"]
	var rr: Vector2 = pr["r"]
	var best_d := Vector2(1, 0)
	var best_room := -1e9
	for k in 16:
		var dl := Vector2.from_angle(TAU * k / 16.0)
		if rr.x > rr.y * 1.8 and absf(dl.dot(Vector2.from_angle(float(pr["a"])))) > 0.35:
			continue
		var room := 0.0
		while room < 70.0 and float(Offroad.area_sd(a, c + dl * (room + 2.0))) < -6.0:
			room += 2.0
		var back := 0.0
		while back < 70.0 and float(Offroad.area_sd(a, c - dl * (back + 2.0))) < -6.0:
			back += 2.0
		if minf(room, back) > best_room:
			best_room = minf(room, back)
			best_d = dl
	var foot := maxf(rr.x, rr.y) * 1.2 + 2.0
	var tip_l := c - best_d * foot
	var h0: float = Offroad.base_h(a, tip_l)
	var run := 10.0
	while run < 75.0:
		var ql := tip_l - best_d * (run + 2.0)
		if absf(float(Offroad.base_h(a, ql)) - h0) > 0.25 or float(Offroad.area_sd(a, ql)) > -8.0:
			break
		run += 2.0
	var dir_w: Vector2 = Offroad.wdir(a, best_d)
	return {"start": Offroad.world(a, tip_l - best_d * run), "dir": dir_w, "tip": Offroad.world(a, tip_l),
		"c": Offroad.world(a, c), "r": maxf(rr.x, rr.y), "h": float(pr["h"]), "base": h0, "a": a}


## Kiesgrube: geradeaus über den Haufen; Kamera steht fest hinter der Landestelle (gut 40 m hinter der Spitze, etwas
## seitlich, knapp über dem Boden) und schaut dem Auto nach wie ein Zuschauer
func _begin_kies(pl) -> void:
	var a: Dictionary = w.layout["offroad"][1]
	var k := _kies_try(a, int(arg[0]) if arg.size() > 0 else 1)
	var d: Vector2 = k["dir"]
	var c: Vector2 = k["c"]
	var p0 := Vector2(pl.global_position.x, pl.global_position.z)
	route = []
	var s := 4.0
	while s < 150.0:
		var q := p0 + d * s
		route.append(_pt(Vector3(q.x, 0, q.y), 21.0))
		s += 4.0
	var side := Vector2(-d.y, d.x)
	var cp := c + d * 44.0 + side * 9.0
	info["cam_pos"] = Vector3(cp.x, float(k["base"]) + 1.4, cp.y)
	info["cam_fov"] = 46.0
	cam_fn = _track_cam
	print("REGIE kies Haufen h=%.1f bei %s, Anlauf ab %s" % [k["h"], str(c), str(p0)])


## Am gelben Ortsschild vorbei: Kamera fest am rechten Bordstein schild_m vor dem Schild, lange Brennweite (schild_fov),
## schaut knapp links am Schild vorbei die Straße entlang. Das Auto fährt auf der rechten Spur dicht am Bordstein, kommt
## von hinten links ins Bild und fährt am Schild vorbei; Schrift groß genug zum Lesen
func _begin_schild(pl) -> void:
	var e := _city(int(arg[0]))
	var tr: Dictionary = e["track"]
	var xf: Transform3D = e["xf"]
	var ds := _sign_d(tr)
	var d_pl: float = (tr["curve"] as Curve3D).get_closest_offset(xf.affine_inverse() * pl.global_position)
	route = _along(e, 0, d_pl + 3.0, ds + 160.0, 8.0, 17.0)
	var f: Dictionary = Track.frame_at(tr["curve"], ds)
	var sign_p: Vector3 = xf * ((f["pos"] as Vector3) + (f["right"] as Vector3) * (Track.hw(tr, ds) + Track.WALK - 1.2) + Vector3(0, 2.6, 0))
	var dc := ds - schild_m
	var fc: Dictionary = Track.frame_at(tr["curve"], dc)
	var cam_p: Vector3 = xf * ((fc["pos"] as Vector3) + (fc["right"] as Vector3) * (Track.hw(tr, dc) + 1.0) + Vector3(0, 1.6, 0))
	var fa: Dictionary = Track.frame_at(tr["curve"], ds + 12.0)
	var aim: Vector3 = xf * ((fa["pos"] as Vector3) + (fa["right"] as Vector3) * (Track.hw(tr, ds + 12.0) + 0.5) + Vector3(0, 1.9, 0))
	info["cam_xf"] = Transform3D(Basis.IDENTITY, cam_p).looking_at(aim.lerp(sign_p, 0.25), Vector3.UP)
	info["cam_fov"] = schild_fov
	cam_fn = _fixed_cam
	print("REGIE schild %s d=%.0f Schild %s Kamera %s" % [Catalog.RACES[int(arg[0])].get("town", ""), ds, str(sign_p), str(cam_p)])


## Feste Kamera, die dem Auto nachschaut (weich)
func _track_cam(pl) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.fov = float(info.get("cam_fov", 50.0))
		w.world.add_child(cam)
		cam.global_position = info["cam_pos"]
		cam.make_current()
		(w.hud["root"] as Control).visible = false
		info["look"] = (pl.global_position as Vector3) + Vector3.UP * 0.8
	info["look"] = (info["look"] as Vector3).lerp((pl.global_position as Vector3) + Vector3.UP * 0.8, 0.35)
	cam.look_at(info["look"], Vector3.UP)


func _fixed_cam(_pl) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.fov = float(info.get("cam_fov", 54.0))
		w.world.add_child(cam)
		cam.global_transform = info["cam_xf"]
		cam.make_current()
		(w.hud["root"] as Control).visible = false


## Von der Autobahn in die Stadt: rechte Spur, abbremsen, auf die Auffahrt (gerade von der Mittellinie zur Stadt), dann
## die Ausfahrt der Stadt hinein bis zur Hauptstraße und ein Stück die Hauptstraße entlang
func _begin_einfahrt(pl) -> void:
	var ci := int(arg[0])
	var town: String = Catalog.RACES[ci].get("town", "")
	var host := {}
	var rp := {}
	for e in w.entries:
		if e["kind"] == "seg" and e["state"] == "ready":
			for p in e["track"]["paths"]:
				if p["kind"] == "ramp" and str(p.get("name", "")) == town and not p.get("conn", false):
					host = e
					rp = p
	if host.is_empty():
		push_warning("REGIE Auffahrt nach %s nicht gebaut" % town)
		quit()
		return
	var tr: Dictionary = host["track"]
	var c: Curve3D = tr["curve"]
	var g := _ramp_geo(tr, town)
	var d0: float = g["d0"]
	var side: float = g["side"]
	var dir: float = g["dir"]
	var lane := func(dd: float, lat: float) -> Vector3:
		var ff: Dictionary = Track.frame_at(c, dd)
		return (ff["pos"] as Vector3) + (ff["right"] as Vector3) * lat
	route = []
	var rc: Curve3D = rp["curve"]
	var RL := rc.get_baked_length()
	var k := 18.0
	if vor > 0.0:
		k = maxf(RL - vor + 4.0, 18.0)  # Start auf der Auffahrt (siehe _plan_spawn)
	else:
		var s := 220.0
		while s > 80.0:
			route.append(_pt(lane.call(d0 - dir * s, 11.25 * side), 20.0))
			s -= 6.0
		route += [_pt(lane.call(d0 - dir * 50.0, 11.25 * side), 14.0), _pt(lane.call(d0 - dir * 20.0, 11.25 * side), 8.0),
			_pt(lane.call(d0 - dir * 6.0, 14.0 * side), 7.0)]
	# Auffahrt: gerade von der Mittellinie zur Ausfahrt der Stadt (ab dem Rand der Fahrbahn)
	while k < RL:
		route.append(_pt(rc.sample_baked(k), 13.0))
		k += 5.0
	# Ausfahrt der Stadt (Weg "ramp" der Stadt, endet außen an der Ausfahrt) rückwärts bis zur Hauptstraße
	var ce := _city(ci)
	var ctr: Dictionary = ce["track"]
	var cx: Transform3D = ce["xf"]
	var ex := -1
	var best := 1e9
	var end_w: Vector3 = rc.sample_baked(RL)
	for p in ctr["paths"]:
		if p["kind"] == "ramp":
			var pc: Curve3D = p["curve"]
			var de := (cx * pc.sample_baked(pc.get_baked_length())).distance_to(end_w)
			if de < best:
				best = de
				ex = p["id"]
	if ex >= 0:
		var ep: Dictionary = ctr["paths"][ex]
		var EL: float = (ep["curve"] as Curve3D).get_baked_length()
		route += _along(ce, ex, EL - 3.0, 2.0, 2.0, 13.0)
		var dm: float = ep["from"]
		# auf der Hauptstraße rechts abbiegen (Richtung so, dass die Einmündung rechts liegt)
		var f0: Dictionary = Track.frame_at(ctr["curve"], dm)
		var into: Vector3 = cx.basis * ((ep["curve"] as Curve3D).sample_baked(0.0) - (ep["curve"] as Curve3D).sample_baked(10.0))
		var sgn := 1.0 if into.dot(cx.basis * (f0["right"] as Vector3)) < 0.0 else -1.0
		route += _along(ce, 0, dm + sgn * 14.0, dm + sgn * 400.0, 2.25, 15.0)
	print("REGIE einfahrt %s Auffahrt %d (%.0f m), Ausfahrt der Stadt %d" % [town, rp["id"], RL, ex])


## Aachen: Grabenring am Dom vorbei, Kamera 16 m hinter und 9 m über dem Auto, Blick halb zum Auto, halb zum Dom
func _begin_dom(pl) -> void:
	var e := _city(15)
	var tr: Dictionary = e["track"]
	var xf: Transform3D = e["xf"]
	var dd := _dom_d(tr)
	var d_pl: float = (tr["curve"] as Curve3D).get_closest_offset(xf.affine_inverse() * pl.global_position)
	route = _along(e, 0, d_pl + 3.0, dd + 200.0, 2.25, 15.0)
	for lm in tr["city"].get("landmarks", []):
		if lm["kind"] == "aachen_dom":
			info["dom"] = xf * Vector3(lm["x"], 0, lm["z"])
	cam_fn = _dom_cam


## Kamera auf der dem Dom abgewandten Seite des Autos, etwas zurück und erhöht: vorn das Auto, dahinter über den
## Dächern Dom und Rathaus (weich nachgeführt)
func _dom_cam(pl) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.fov = 50.0
		w.world.add_child(cam)
		cam.make_current()
		(w.hud["root"] as Control).visible = false
	var p: Vector3 = pl.global_position
	var dom: Vector3 = info["dom"]
	var to_dom := (dom - p)
	to_dom.y = 0.0
	to_dom = to_dom.normalized()
	# Kamera 16 m hinter dem Auto auf der Linie zum Dom, 7 m hoch, Blick 8° nach unten: vorn das Auto, oben der Dom
	var want := p - to_dom * 16.0 + Vector3.UP * 7.0
	if not info.has("cam_p"):
		info["cam_p"] = want
		info["cam_dir"] = to_dom
	info["cam_p"] = (info["cam_p"] as Vector3).lerp(want, 0.12)
	info["cam_dir"] = (info["cam_dir"] as Vector3).lerp(to_dom, 0.12).normalized()
	cam.global_position = info["cam_p"]
	cam.look_at(cam.global_position + (info["cam_dir"] as Vector3) * 100.0 + Vector3.DOWN * 14.0, Vector3.UP)


# --- Garage ---------------------------------------------------------------------------------------------------------

## Autohaus: nach t Sekunden das nächste Auto (garage._cycle_car wie Rechts), es fährt herein, das bisherige hinaus
func _garage(delta: float) -> bool:
	if rt < 0.0:
		rt = 0.0
		_mark("start")
		if not hud_on and w.get("_ui") != null:
			(w._ui as Control).visible = false
	rt += delta
	var tc := float(arg[0]) if arg.size() > 0 else 3.0
	if rt >= tc and not info.has("cycled"):
		info["cycled"] = true
		w._cycle_car(1)
		print("REGIE garage: nächstes Auto bei %.2f s" % rt)
		_mark("autowechsel")
	if rt > quit_after:
		print("REGIE ENDE garage nach %.1f s" % rt)
		quit()
	return false


func _busy() -> bool:
	for n in [w, w.get("land"), w.get("offroad_node")]:
		if n != null and n.get("_task") != null and int(n.get("_task")) >= 0:
			return true
	return false


# --- Marken fürs Schneiden: "REGIE MARKE <was> t=<s>" (t = Sekunde im Video, Bild = Engine.get_frames_drawn) ---------

var _ev := {}


func _mark(what: String) -> void:
	print("REGIE MARKE %s t=%.3f bild=%d" % [what, t, Engine.get_frames_drawn()])


func _events(pl) -> void:
	var act: Dictionary = w.active
	var nm := str(act.get("race", {}).get("name", "-")) if not act.is_empty() else "-"
	if nm != str(_ev.get("aktiv", "")):
		_ev["aktiv"] = nm
		_mark("aktiv " + nm)
	var intro = w.get("_intro")
	var running := intro != null and bool(intro.running)
	if running != bool(_ev.get("intro", false)):
		_ev["intro"] = running
		_mark("anflug " + ("beginnt" if running else "endet"))
	var off := not (pl.offroad as Dictionary).is_empty()
	if off != bool(_ev.get("off", false)):
		_ev["off"] = off
		_mark("gelaende " + ("rein" if off else "raus"))
	if bool(pl.airborne) != bool(_ev.get("air", false)):
		_ev["air"] = bool(pl.airborne)
		_mark("flug " + ("ab" if pl.airborne else "landung"))
	if bool(pl.jump_cam) != bool(_ev.get("jc", false)):
		_ev["jc"] = bool(pl.jump_cam)
		_mark("sprungkamera " + ("an" if pl.jump_cam else "aus"))
	if info.has("ph"):
		var lt := _light_txt().split(" ")[0]
		if lt != str(_ev.get("licht", "")):
			_ev["licht"] = lt
			_mark("ampel " + lt)
	if drift_t >= 0.0 and not _ev.has("drift"):
		_ev["drift"] = true
		_mark("drift")
	if info.has("wegweiser") and not _ev.has("wegweiser"):
		var q: Vector3 = info["wegweiser"]
		if Vector2(q.x - pl.global_position.x, q.z - pl.global_position.z).length() < 6.0:
			_ev["wegweiser"] = true
			_mark("wegweiser")
	var pk := str(pl.loc.get("path", {}).get("kind", "-")) if not (pl.loc as Dictionary).is_empty() else "-"
	if pk != str(_ev.get("weg", "")):
		_ev["weg"] = pk
		_mark("weg " + pk)


# --- Fahren ---------------------------------------------------------------------------------------------------------

## Dem Weg folgen wie ein Spieler: Ziel voraus (5 m + halbe Geschwindigkeit), Lenken nach dem Winkel dorthin, Tempo
## nach dem Weg mit Vorausschau (Bremsweg mit 4,5 m/s²); an Haltepunkten stehen bleiben, bis die Bedingung erfüllt ist
func _follow(pl) -> void:
	var p: Vector3 = pl.global_position
	var bd := INF
	var best := ri
	for k in range(ri, mini(ri + 30, route.size())):
		var dk := Vector2(route[k]["p"].x - p.x, route[k]["p"].z - p.z).length()
		if dk < bd:
			bd = dk
			best = k
	# Haltepunkt nicht überspringen
	for k in range(ri, best + 1):
		if route[k].has("stop") and k < best:
			best = k
			break
	ri = best
	if drift_at >= 0 and ri >= drift_at:
		drift_t = 0.0
		return
	if ri >= route.size() - 1:
		if not done:
			done = true
			print("REGIE Weg zu Ende nach %.1f s" % rt)
			if quit_after > rt + 2.5:
				quit_after = rt + 2.5
		return
	var v: float = pl.speed_fwd
	# Halt
	if route[ri].has("stop") or (ri + 1 < route.size() and route[ri + 1].has("stop") and bd < 2.5):
		var si := ri if route[ri].has("stop") else ri + 1
		var sp: Vector3 = route[si]["p"]
		var dist := Vector2(sp.x - p.x, sp.z - p.z).length()
		if not halt and (dist < 1.2 or (absf(v) < 0.4 and dist < 4.0)):
			halt = true
			halt_t = rt
			print("REGIE Halt bei t=%.2f rt=%.2f %s" % [t, rt, _light_txt()])
			_mark("halt")
		if halt:
			if absf(v) > 0.3:
				Input.action_press("brake", 0.6)
			if (route[si]["stop"] as Callable).call():
				route[si].erase("stop")
				route[si]["v"] = route[mini(si + 1, route.size() - 1)]["v"]
				halt = false
				print("REGIE weiter bei t=%.2f rt=%.2f nach %.1f s %s" % [t, rt, rt - halt_t, _light_txt()])
				_mark("weiter")
			return
	var look := 5.0 + absf(v) * 0.45
	var k2 := ri
	var acc := 0.0
	while k2 < route.size() - 1 and acc < look:
		acc += (route[k2]["p"] as Vector3).distance_to(route[k2 + 1]["p"])
		k2 += 1
	var tgt: Vector3 = route[k2]["p"]
	var fwd: Vector3 = -pl.global_basis.z
	var fd := Vector2(fwd.x, fwd.z).normalized()
	var to := Vector2(tgt.x - p.x, tgt.z - p.z).normalized()
	var ang := fd.angle_to(to)  # > 0: Ziel rechts
	var st := clampf(ang * 2.3, -1.0, 1.0)
	if st > 0.02:
		Input.action_press("steer_right", st)
	elif st < -0.02:
		Input.action_press("steer_left", -st)
	# Tempo: das kleinste erlaubte der nächsten 80 m
	var vt: float = route[ri]["v"]
	var s := 0.0
	var k3 := ri
	while k3 < route.size() - 1 and s < 80.0:
		s += (route[k3]["p"] as Vector3).distance_to(route[k3 + 1]["p"])
		k3 += 1
		var vk: float = route[k3]["v"]
		vt = minf(vt, sqrt(vk * vk + 2.0 * 4.5 * maxf(s - 1.5, 0.0)))
		if route[k3].has("stop"):
			vt = minf(vt, sqrt(2.0 * 3.0 * maxf(s - 0.8, 0.0)))
			break
	vt = minf(vt, lerpf(vt, 6.0, clampf(absf(ang) / 0.9, 0.0, 1.0)))  # stark abbiegen: langsam
	if v < vt - 1.0:
		Input.action_press("accelerate", 1.0)
	elif v > vt + 1.5:
		Input.action_press("brake", clampf((v - vt) / 6.0, 0.25, 1.0))
	elif v < vt:
		Input.action_press("accelerate", 0.45)
