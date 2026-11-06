shader_type spatial;
// Fassaden in mehreren Stilen. style: 0 Raster, 1 Bandfenster (Büro), 2 Halle/Industrie, 3 Glasturm,
// 4 Backstein-Wohnhaus, 5 Fachwerk, 6 Putzfassade (Altbau, Barock), 7 Ziegeldach, 8 Altbau mit Graffiti, 9 Laden.
// Die Häuser einer Gegend sind ein gemeinsames Mesh; die Werte je Haus stehen in den Vertexdaten
// (COLOR = Farbton + Anteil beleuchteter Fenster, UV2 = Seed, Stil + 10 * Schaufenster).
// Seit 2.15 in Fassadenkoordinaten (track_builder._bb_box): UV = Strecke ab der linken Kante und Höhe über der
// Straße, CUSTOM0 = Breite der Fläche, Oberkante, Art (0 Dach, 1 Fassade, 2 Wand ohne Fenster, 3 Giebel). Die
// Fensterachsen werden auf die Breite verteilt (gleiche Ränder an beiden Ecken), nur ganze Geschosse unter der
// Dachkante bekommen Fenster, Erdgeschoss und Schaufenster sitzen auf Straßenhöhe (auch am Hang).
// Licht: ganze Wohnungen (zwei Fenster) oder Büros sind an oder aus, mit einer Lichtfarbe je Haus.
// In der Ferne geht das Fenstermuster in seinen Mittelwert über (kein Flimmern, keine Moiré-Muster).

uniform float window_light = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
varying vec3 tint;
varying float lit_chance;
varying float seed;
varying float style;
varying float shop_glass;
varying vec2 fc;
varying vec3 face;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Rechteck in Zellkoordinaten f (0..1) mit weichen Kanten (eine Pixelbreite fw): r = x0, x1, y0, y1
float rect(vec2 f, vec4 r, vec2 fw) {
	return smoothstep(r.x - fw.x, r.x + fw.x, f.x) * (1.0 - smoothstep(r.y - fw.x, r.y + fw.x, f.x))
		* smoothstep(r.z - fw.y, r.z + fw.y, f.y) * (1.0 - smoothstep(r.w - fw.y, r.w + fw.y, f.y));
}

// weiche Linie: 1 auf den Fugen (Abstand < width vom ganzzahligen Raster)
float lines(float x, float width, float fw) {
	float d = abs(fract(x + 0.5) - 0.5);
	return 1.0 - smoothstep(width - fw, width + fw, d);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
	lit_chance = COLOR.a * 0.7;  // weniger erleuchtete Fenster: dunklere Nacht
	seed = UV2.x;
	shop_glass = floor(UV2.y / 10.0 + 0.01);
	style = UV2.y - shop_glass * 10.0;
	fc = UV;
	face = CUSTOM0.xyz;
}

void fragment() {
	float wall = 1.0 - step(0.9, abs(wnorm.y));
	int st = int(style + 0.5);
	bool graffiti = st == 8;
	if (graffiti) {
		st = 6;
	}
	float kind = floor(face.z + 0.5);
	float W = face.x;
	float H = face.y;
	// Fassadenkoordinaten (ohne Daten: wie früher aus der Welt, dann ohne Fenster)
	float u = kind > 0.5 ? fc.x : (abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x);
	float y = kind > 0.5 ? fc.y : wpos.y;
	float facade = (kind > 0.5 && kind < 1.5) ? wall : 0.0;

	// Raster je Stil: Achsabstand sp, Geschosshöhe fh, Erdgeschoss g, Fenster in der Zelle wr (x0, x1, y0, y1)
	float sp = 3.2;
	float fh = 3.3;
	float g = 4.2;
	vec4 wr = vec4(0.2, 0.8, 0.25, 0.8);
	float apt = 2.0;  // Fenster je Wohnung/Büro (gemeinsam an oder aus)
	if (st == 1) {
		sp = 1.6; fh = 3.6; wr = vec4(0.0, 1.0, 0.3, 0.85); apt = 4.0;
	} else if (st == 2) {
		sp = 6.0; fh = 4.5; wr = vec4(0.3, 0.7, 0.55, 0.82); apt = 1.0;
	} else if (st == 3) {
		sp = 1.5; fh = 3.6; wr = vec4(0.0, 1.0, 0.12, 1.0); apt = 5.0;
	} else if (st == 4) {
		sp = 3.0; fh = 3.2; wr = vec4(0.3, 0.7, 0.24, 0.76);
	} else if (st == 5) {
		sp = 1.5; fh = 3.0; g = 3.0; wr = vec4(0.25, 0.8, 0.52, 0.88); apt = 1.0;
	} else if (st == 6) {
		sp = 2.8; fh = 3.5; wr = vec4(0.3, 0.7, 0.2, 0.78);
	}
	float m = (st == 1 || st == 3) ? 0.3 : (st == 5 ? 0.0 : 0.7);  // Rand an den Ecken
	float usable = max(W - 2.0 * m, sp);
	float ncol = max(1.0, floor(usable / sp + 0.3));
	float s = kind > 0.5 ? usable / ncol : sp;  // Achsabstand: Fenster gleichmäßig über die Breite verteilt
	float cx = kind > 0.5 ? (u - m) / s : u / sp;
	float in_cols = kind > 0.5 ? step(0.0, cx) * step(cx, ncol) : 1.0;
	float up = (y - g) / fh;
	float nfl = floor((H - g - 0.6) / fh);  // ganze Geschosse unter der Oberkante (Rest = Attika)
	float row = floor(up);
	float in_rows = step(0.0, up) * step(row, nfl - 1.0);
	vec2 f = vec2(fract(cx), fract(up));
	vec2 cell = vec2(floor(cx), row);
	vec2 fw = vec2(fwidth(cx), fwidth(up));
	// Ableitungen einmal außerhalb der Verzweigungen (dort sind sie nicht zuverlässig)
	float fu = fwidth(u);
	float fy = fwidth(y);
	// Detail: Zellen unter ~4 Pixeln werden zum Mittelwert (in der Ferne kein Flimmern)
	float detail = 1.0 - smoothstep(0.1, 0.25, max(fw.x, fw.y));
	vec2 fwa = fw * 0.75 + 0.002;

	// Fenster der Obergeschosse
	float area = (wr.y - wr.x) * (wr.w - wr.z);
	float wmask = rect(f, wr, fwa);
	vec2 wl = (f - wr.xz) / (wr.yw - wr.xz);  // Lage im Fenster 0..1
	// Erdgeschoss ohne Laden: Fenster etwas tiefer und kleiner
	float ground = facade * step(0.0, y) * (1.0 - step(g, y)) * (1.0 - shop_glass);
	vec2 gf = vec2(f.x, y / g);
	vec4 gr = vec4(wr.x, wr.y, 0.3, 0.78);
	float gmask = st == 2 || st == 3 ? 0.0 : rect(gf, gr, vec2(fwa.x, fy / g * 0.75 + 0.002));
	if (ground > 0.5) {
		wl = (gf - gr.xz) / (gr.yw - gr.xz);
		cell = vec2(floor(cx), -1.0);
	}
	vec2 fwl = vec2(fu / (s * (wr.y - wr.x)), fy / (fh * (wr.w - wr.z)));
	float win_upper = mix(area, wmask, detail) * in_cols * in_rows * facade;
	float win_ground = mix(area * 0.48, gmask, detail) * in_cols * ground;
	float win = win_upper + win_ground;

	// Licht je Wohnung, Farbe je Haus (Wohnhäuser warm, Büros kühl), wenig Streuung je Wohnung
	vec2 aid = vec2(floor(cell.x / apt), cell.y);
	float lit_k = st == 2 ? 0.6 : (st == 3 ? 0.8 : (st == 1 ? 1.0 : 1.2));
	float lit_one = step(1.0 - lit_chance * lit_k, hash(aid + seed));
	float lit = mix(lit_chance * lit_k, lit_one, detail);
	bool office = st == 1 || st == 3;
	vec3 house_light = office ? mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.7), step(0.7, hash(vec2(seed, 3.0))))
		: mix(vec3(1.0, 0.72, 0.4), vec3(1.0, 0.82, 0.55), hash(vec2(seed, 4.0)));
	float av = hash(aid * 1.31 + seed);
	vec3 wcol = house_light * (0.8 + 0.3 * av);
	if (!office && av > 0.85) {
		wcol = vec3(0.6, 0.75, 1.0) * 0.9;  // hier und da kaltes Licht (Bad, Küche)
	}
	// Raum hinter dem Fenster: Deckenlicht (oben heller), Vorhänge bzw. Jalousien
	float interior = 0.72 + 0.4 * wl.y;
	float deco = hash(cell * 1.7 + seed);
	if (!office && deco > 0.45) {
		float curtain = 1.0 - smoothstep(0.12, 0.2, wl.x) * smoothstep(0.12, 0.2, 1.0 - wl.x);
		interior *= 1.0 - 0.55 * curtain;
	} else if (office && deco > 0.6) {
		interior *= 0.55 + 0.45 * smoothstep(0.3, 0.7, abs(fract(wl.y * 9.0) - 0.5) * 2.0);
	}
	wcol *= mix(1.0, interior, detail);
	// Leben hinter den Fenstern: Fernseher flackert (bläulich), jemand steht am Fenster (Silhouette)
	float who = hash(cell * 3.7 + seed * 1.3);
	if (detail > 0.01 && who > 0.93) {
		float ph = hash(cell + seed * 2.1) * 40.0;
		float fl = 0.55 + 0.25 * sin(TIME * 7.3 + ph) + 0.2 * sin(TIME * 17.9 + ph * 2.3) * step(0.5, fract(TIME * 0.8 + ph));
		wcol = mix(wcol, vec3(0.45, 0.6, 1.0) * fl, detail);
	} else if (detail > 0.01 && who > 0.88 && !office) {
		float body = step(abs(wl.x - 0.5), 0.12) * step(wl.y, 0.62);
		float head = step(length((wl - vec2(0.5, 0.74)) * vec2(1.0, 1.4)), 0.09);
		wcol *= 1.0 - 0.85 * max(body, head) * detail;
	}
	// Fensterkreuz bei Altbau/Backstein/Raster, Pfosten bei Glas und Bandfenstern
	float bars = 0.0;
	if (st == 0 || st == 4 || st == 6) {
		bars = max(lines(wl.x - 0.5, 0.03, fwl.x), lines(wl.y - 0.68, 0.025, fwl.y) * step(0.3, wl.y));
		bars *= step(0.05, wl.x) * step(wl.x, 0.95);
	} else if (st == 1 || st == 3) {
		bars = lines(f.x, 0.035, fwa.x);
	}
	bars *= detail;

	// Wandmaterial je Stil
	vec3 albedo = tint;
	float metal = 0.0;
	if (st == 2) {
		// Trapezblech: senkrechte Sicken
		float rib = 0.5 + 0.5 * sin(u * 6.2832 * 1.4);
		float dr = 1.0 - smoothstep(0.15, 0.4, fu * 1.4);
		albedo *= mix(0.9, 0.8 + 0.2 * rib, dr);
	} else if (st == 3) {
		metal = 0.6;
		// Brüstungen zwischen den Glasbändern
		albedo = mix(tint * 0.6, tint, 0.5);
	} else if (st == 4) {
		vec2 b = vec2(u * 4.0 + step(0.5, fract(y * 2.5)) * 0.5, y * 2.5);
		float dm = 1.0 - smoothstep(0.15, 0.4, max(fu * 4.0, fy * 2.5));
		float mortar = max(lines(b.x, 0.06, fu * 4.0), lines(b.y, 0.08, fy * 2.5));
		vec3 brick = tint * (0.85 + 0.3 * hash(floor(b) + seed));
		albedo = mix(tint * 0.92, mix(brick, tint * 0.45, mortar), dm);
		// Fensterbänke
		float sill = rect(f, vec4(wr.x - 0.03, wr.y + 0.03, wr.z - 0.05, wr.z), fwa) * in_cols * in_rows;
		albedo = mix(albedo, vec3(0.35), sill * facade * detail);
	} else if (st == 5) {
		// Fachwerk: dunkle Balken auf hellem Putz, Erdgeschoss aus Sandstein; Ständer auf die Breite verteilt
		float h1 = hash(cell + seed);
		float upper = step(g, y);
		float beam = max(lines(cx, 0.06, fwa.x), max(lines(up, 0.05, fwa.y), lines(up - 0.47, 0.03, fwa.y)));
		bool window = h1 > 0.45;
		float diag = h1 < 0.3 ? 1.0 - smoothstep(0.05, 0.08, abs(f.x - f.y)) : (h1 < 0.45 ? 1.0 - smoothstep(0.05, 0.08, abs(1.0 - f.x - f.y)) : 0.0);
		beam = clamp(beam + diag, 0.0, 1.0) * upper * detail * facade;
		if (!window) {
			win -= win_upper;
		}
		beam *= 1.0 - win;
		vec3 stone = vec3(0.32, 0.26, 0.2) * (0.85 + 0.3 * hash(floor(vec2(u * 2.0, y * 3.0)) + seed));
		albedo = mix(stone, mix(tint, vec3(0.09, 0.05, 0.03), beam), upper);
	} else if (st == 6) {
		// Putzfassade mit Fenstergewänden, Gesimsen und gequadertem Erdgeschoss
		float frame = rect(f, vec4(wr.x - 0.06, wr.y + 0.06, wr.z - 0.07, wr.w + 0.07), fwa) * (1.0 - wmask) * in_cols * in_rows;
		albedo = mix(tint, tint * 1.35 + vec3(0.04), frame * facade * detail);
		float cornice = smoothstep(0.95 - fwa.y, 0.95 + fwa.y, f.y) * step(0.0, up) * step(row, nfl - 1.0);
		albedo = mix(albedo, tint * 0.6, cornice * facade * detail);
		float socle = (1.0 - step(g, y)) * (1.0 - shop_glass) * facade;
		float block = max(lines(y * 1.5, 0.05, fy * 1.5), lines(u * 0.7, 0.03, fu * 0.7));
		albedo = mix(albedo, mix(tint * 0.8, tint * 0.5, block * detail), socle);
	} else if (st == 7) {
		// Dachziegel: Reihen quer zum Gefälle, leicht unregelmäßig
		float rowt = fract(y * 3.2);
		vec2 tc = floor(vec2(u * 3.0 + floor(y * 3.2) * 0.5, y * 3.2));
		float dt = 1.0 - smoothstep(0.15, 0.4, fy * 3.2);
		albedo = tint * mix(0.85, (0.7 + 0.45 * hash(tc + seed)) * (0.75 + 0.25 * smoothstep(0.0, 0.25, rowt)), dt);
	}
	if (st == 0 || st == 4 || st == 6) {
		// Geschossdecken leicht abgesetzt
		float slab = smoothstep(0.95 - fwa.y, 0.95 + fwa.y, f.y) * step(0.0, up) * step(row, nfl - 1.0);
		albedo *= 1.0 - 0.18 * slab * facade * detail;
	}
	if (graffiti) {
		// Stücke von 3–4 m Breite in Hüfthöhe: bauchige Buchstaben (schmale, hohe Formen) mit dunkler Kontur und
		// hellem Glanz, je Stück eine Farbe; dazwischen freie Wand
		float piece = floor(u / 3.6);
		float pu = fract(u / 3.6);
		float on = step(0.3, hash(vec2(piece, seed))) * smoothstep(0.02, 0.1, pu) * smoothstep(0.02, 0.1, 1.0 - pu);
		float band = smoothstep(0.3, 0.5, y) * (1.0 - smoothstep(1.9, 2.3 + hash(vec2(piece, seed + 2.0)) * 0.6, y));
		float n = noise(vec2(u * 2.4, y * 1.1) + seed * 3.0 + piece * 7.0) * band * on;
		float fill = smoothstep(0.42, 0.46, n);
		float rim = smoothstep(0.36, 0.4, n) * (1.0 - fill);
		float shine = smoothstep(0.62, 0.66, n) * step(0.5, fract(y * 3.0 + u * 0.5));
		float hsel = hash(vec2(piece, seed + 5.0));
		vec3 tc = hsel < 0.2 ? vec3(0.9, 0.2, 0.55) : (hsel < 0.4 ? vec3(0.15, 0.7, 0.9) : (hsel < 0.6 ? vec3(0.95, 0.8, 0.15) : (hsel < 0.8 ? vec3(0.3, 0.85, 0.35) : vec3(0.85, 0.85, 0.85))));
		vec3 gcol = mix(tc * 0.75, vec3(0.95), shine * 0.6);
		albedo = mix(albedo, vec3(0.03), rim * wall * detail);
		albedo = mix(albedo, gcol, fill * wall * mix(0.5, 1.0, detail));
	}
	// Fassade nicht ganz gleichmäßig: leichte Flecken, Schmutzfahnen unter den Fenstern
	albedo *= 0.88 + 0.24 * noise(vec2(u * 0.12, y * 0.08) + seed);
	float streak = smoothstep(0.55, 1.0, noise(vec2(u * 1.2, y * 0.12) + seed * 1.7)) * (1.0 - f.y) * in_rows * in_cols;
	albedo *= 1.0 - 0.1 * streak * facade * detail;

	// Erdgeschoss: Schaufenster in gleichmäßigen Feldern, meist beleuchtet, bunt
	float bays = max(1.0, floor((W - 1.0) / 5.5 + 0.3));
	float bw = kind > 0.5 ? (W - 1.0) / bays : 6.0;
	float bx = (u - 0.5) / bw;
	float shop_cell = floor(bx);
	float sf = fract(bx);
	float in_bays = kind > 0.5 ? step(0.0, bx) * step(bx, bays) : 1.0;
	float shop_m = rect(vec2(sf, y), vec4(0.06, 0.94, 0.5, 3.4), vec2(fu / bw, fy) * 0.75 + 0.002);
	float shop = wall * in_bays * shop_glass * mix(0.88 * 0.73, shop_m, detail) * step(0.0, y) * (kind > 1.5 ? 0.0 : 1.0);
	float shop_lit = step(0.2, hash(vec2(shop_cell, seed)));
	float hue = hash(vec2(shop_cell * 3.1, seed + 1.0));
	vec3 scol = hue < 0.5 ? vec3(1.0, 0.85, 0.6) : (hue < 0.7 ? vec3(0.6, 0.9, 1.0) : (hue < 0.85 ? vec3(1.0, 0.4, 0.7) : vec3(0.6, 1.0, 0.6)));
	// Laden von innen: oben heller (Deckenlicht), Regalböden als dunkle Linien, Theke unten dunkler, ab und zu ein
	// Regal quer davor; in der Ferne nur der Mittelwert
	float shelf_line = lines(y * 1.7, 0.06, fy * 1.7) * step(1.0, y) * step(y, 3.0);
	float rack = step(0.72, hash(vec2(floor(u * 0.8), seed + 7.0))) * step(y, 2.6);
	float inside = (0.55 + 0.45 * smoothstep(0.5, 3.4, y)) * (1.0 - 0.6 * shelf_line) * (1.0 - 0.45 * rack) * (y < 1.1 ? 0.55 : 1.0);
	float shelf = mix(0.75, inside, detail);

	win = clamp(win * (1.0 - bars), 0.0, 1.0);
	float glass = max(win, shop);
	// unbeleuchtetes Glas spiegelt etwas Nachthimmel (oben heller)
	vec3 glass_col = st == 3 ? vec3(0.02, 0.04, 0.07) : vec3(0.02, 0.025, 0.035) + vec3(0.01, 0.015, 0.03) * wl.y * detail;
	vec3 frame_col = st == 6 ? tint * 1.4 + vec3(0.05) : (st == 4 ? vec3(0.85) : vec3(0.08));
	vec3 col = mix(albedo, glass_col, glass);
	col = mix(col, frame_col, bars * (win_upper + win_ground) * (1.0 - shop));
	// Dach: dunkler Kies (Ziegeldächer bleiben Ziegel)
	float roof = (1.0 - wall) * (st == 7 ? 0.0 : 1.0);
	col = mix(col, vec3(0.05) * (0.6 + 0.8 * noise(wpos.xz * 0.6)), roof);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, st == 3 ? 0.05 : 0.12, glass);
	METALLIC = glass * 0.5 + metal * glass;
	// zurückhaltend: Nachtstadt wie in Underground, Fenster glimmen statt zu strahlen
	EMISSION = wcol * win * lit * 0.95 * window_light + scol * shop * shop_lit * 0.5 * shelf;
}
