shader_type spatial;
// Fassaden in mehreren Stilen, alles in Weltkoordinaten (beliebig skalierbar).
// style: 0 Raster, 1 Bandfenster (Büro), 2 Halle/Industrie, 3 Glasturm, 4 Backstein-Wohnhaus,
// 5 Fachwerk, 6 Putzfassade (Altbau, Barock), 7 Ziegeldach (geneigte Dachflächen, keine Fenster)
// Die Häuser einer Gegend sind ein gemeinsames Mesh; die Werte je Haus stehen in den Vertexdaten
// (COLOR = Farbton + Anteil beleuchteter Fenster, UV2 = Seed, Stil + 10 * Schaufenster).

uniform float window_light = 1.0;
varying vec3 wpos;
varying vec3 wnorm;
varying vec3 tint;
varying float lit_chance;
varying float seed;
varying float style;
varying float shop_glass;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = COLOR.rgb;
	lit_chance = COLOR.a * 0.7;  // weniger erleuchtete Fenster: dunklere Nacht
	seed = UV2.x;
	shop_glass = floor(UV2.y / 10.0 + 0.01);
	style = UV2.y - shop_glass * 10.0;
}

void fragment() {
	float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
	float wall = 1.0 - step(0.9, abs(wnorm.y));
	float y = wpos.y - 4.2;
	int st = int(style + 0.5);
	float win = 0.0;
	float lit = 0.0;
	vec2 cid = vec2(0.0);
	vec3 albedo = tint;
	float metal = 0.0;
	if (st == 1) {
		float fy = fract(y / 3.4);
		win = step(0.28, fy) * step(fy, 0.82) * step(0.07, fract(u / 1.6));
		cid = vec2(floor(u / 6.4), floor(y / 3.4));
		lit = step(1.0 - lit_chance, hash(cid + seed));
	} else if (st == 2) {
		vec2 f = fract(vec2(u / 6.0, y / 4.5));
		win = step(0.32, f.x) * step(f.x, 0.68) * step(0.55, f.y) * step(f.y, 0.82);
		cid = floor(vec2(u / 6.0, y / 4.5));
		lit = step(1.0 - lit_chance * 0.6, hash(cid + seed));
		albedo *= 0.8 + 0.2 * step(0.5, fract(u * 1.3));
	} else if (st == 3) {
		float fy = fract(y / 3.6);
		win = step(0.06, fract(u / 1.5)) * step(0.1, fy);
		cid = vec2(floor(u / 9.0), floor(y / 3.6));
		lit = step(1.0 - lit_chance * 0.8, hash(cid + seed));
		metal = 0.6;
	} else if (st == 4) {
		vec2 f = fract(vec2(u / 3.0, y / 3.2));
		win = step(0.3, f.x) * step(f.x, 0.7) * step(0.22, f.y) * step(f.y, 0.75);
		cid = floor(vec2(u / 3.0, y / 3.2));
		lit = step(1.0 - lit_chance * 1.2, hash(cid + seed));
		vec2 b = vec2(u * 4.0 + step(0.5, fract(wpos.y * 2.5)) * 0.5, wpos.y * 2.5);
		float mortar = clamp(step(0.92, fract(b.x)) + step(0.86, fract(b.y)), 0.0, 1.0);
		albedo = mix(tint * (0.85 + 0.3 * hash(floor(b) + seed)), tint * 0.45, mortar);
		// Fensterbänke
		float sill = step(0.18, f.y) * step(f.y, 0.22) * step(0.27, f.x) * step(f.x, 0.73);
		albedo = mix(albedo, vec3(0.35), sill * wall);
	} else if (st == 5) {
		// Fachwerk: dunkle Balken auf hellem Putz, Erdgeschoss aus Sandstein
		float fl = 3.0;
		vec2 f = fract(vec2(u / 1.5, wpos.y / fl));
		vec2 c = floor(vec2(u / 1.5, wpos.y / fl));
		float h1 = hash(c + seed);
		float upper = step(3.0, wpos.y);
		float beam = step(f.x, 0.11) + step(f.y, 0.07) + step(0.93, f.y) + step(0.44, f.y) * step(f.y, 0.5);
		bool window = h1 > 0.45;
		float diag = h1 < 0.3 ? step(abs(f.x - f.y), 0.07) : (h1 < 0.45 ? step(abs(1.0 - f.x - f.y), 0.07) : 0.0);
		beam = clamp(beam + diag, 0.0, 1.0) * upper;
		win = window ? step(0.25, f.x) * step(f.x, 0.8) * step(0.52, f.y) * step(f.y, 0.88) * upper : 0.0;
		beam *= 1.0 - win;
		cid = c;
		lit = step(1.0 - lit_chance * 1.3, hash(cid + seed * 1.7));
		vec3 stone = vec3(0.32, 0.26, 0.2) * (0.85 + 0.3 * hash(floor(vec2(u * 2.0, wpos.y * 3.0)) + seed));
		albedo = mix(stone, mix(tint, vec3(0.09, 0.05, 0.03), beam), upper);
	} else if (st == 6) {
		// Putzfassade mit Fenstergewänden, Gesimsen und gequadertem Sockel
		vec2 f = fract(vec2(u / 2.8, y / 3.5));
		cid = floor(vec2(u / 2.8, y / 3.5));
		win = step(0.3, f.x) * step(f.x, 0.7) * step(0.2, f.y) * step(f.y, 0.78);
		float frame = step(0.25, f.x) * step(f.x, 0.75) * step(0.14, f.y) * step(f.y, 0.84) * (1.0 - win);
		lit = step(1.0 - lit_chance * 1.2, hash(cid + seed));
		albedo = mix(tint, tint * 1.35 + vec3(0.04), frame);
		float cornice = step(0.95, fract(y / 3.5)) * step(0.0, y);
		albedo = mix(albedo, tint * 0.6, cornice);
		float socle = 1.0 - step(0.0, y);
		float block = step(0.9, fract(wpos.y * 1.5)) + step(0.96, fract(u * 0.7));
		albedo = mix(albedo, mix(tint * 0.8, tint * 0.5, clamp(block, 0.0, 1.0)), socle);
	} else if (st == 7) {
		// Dachziegel: Reihen quer zum Gefälle, leicht unregelmäßig; Giebelflächen bekommen eigene Vertexdaten
		float row = fract(wpos.y * 3.2);
		vec2 tc = floor(vec2(u * 3.0 + floor(wpos.y * 3.2) * 0.5, wpos.y * 3.2));
		albedo = tint * (0.7 + 0.45 * hash(tc + seed)) * (0.75 + 0.25 * smoothstep(0.0, 0.25, row));
	} else {
		vec2 f = fract(vec2(u / 3.2, y / 3.6));
		win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.8);
		cid = floor(vec2(u / 3.2, y / 3.6));
		lit = step(1.0 - lit_chance, hash(cid + seed));
	}
	win *= wall * step(0.0, y);
	// Fassade nicht ganz gleichmäßig (Flecken, Alterung), Geschossdecken leicht abgesetzt
	albedo *= 0.75 + 0.5 * noise(vec2(u * 0.12, wpos.y * 0.08) + seed);
	if (st == 0 || st == 4 || st == 6) {
		albedo *= 1.0 - 0.25 * step(0.95, fract(y / 3.6)) * wall * step(0.0, y);
	}

	vec3 wcol = mix(vec3(1.0, 0.72, 0.38), vec3(0.55, 0.75, 1.0), step(0.62, hash(cid * 1.31 + seed)));
	wcol *= 0.55 + 0.7 * hash(cid * 2.7 + seed);
	// Erdgeschoss: große Schaufenster, meist beleuchtet, bunt
	float shop_cell = floor(u / 6.0);
	float sf = fract(u / 6.0);
	float shop = wall * step(0.06, sf) * step(sf, 0.94) * step(0.5, wpos.y) * step(wpos.y, 3.4) * shop_glass;
	float shop_lit = step(0.2, hash(vec2(shop_cell, seed)));
	float hue = hash(vec2(shop_cell * 3.1, seed + 1.0));
	vec3 scol = hue < 0.5 ? vec3(1.0, 0.85, 0.6) : (hue < 0.7 ? vec3(0.6, 0.9, 1.0) : (hue < 0.85 ? vec3(1.0, 0.4, 0.7) : vec3(0.6, 1.0, 0.6)));
	// Auslage: dunkle Regale im Schaufenster
	float shelf = step(0.5, fract(wpos.y * 1.6)) * step(0.3, fract(u * 0.9));
	float glass = max(win, shop);
	vec3 glass_col = st == 3 ? vec3(0.02, 0.04, 0.07) : vec3(0.02, 0.025, 0.03);
	vec3 col = mix(albedo, glass_col, glass);
	// Dach: dunkler Kies (Ziegeldächer bleiben Ziegel)
	float roof = (1.0 - wall) * (st == 7 ? 0.0 : 1.0);
	col = mix(col, vec3(0.05) * (0.6 + 0.8 * noise(wpos.xz * 0.6)), roof);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, st == 3 ? 0.05 : 0.12, glass);
	METALLIC = glass * 0.5 + metal * glass;
	// zurückhaltend: Nachtstadt wie in Underground, Fenster glimmen statt zu strahlen
	EMISSION = wcol * win * lit * 0.95 * window_light + scol * shop * shop_lit * (0.3 + 0.2 * shelf);
}
