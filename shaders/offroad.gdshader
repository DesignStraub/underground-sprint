shader_type spatial;
// Boden der Gelände (offroad_build.gd, seit 2.39). Untergrund aus den Vertexfarben (rgba je ein Kanal, 0,5 an der
// Grenze): Golfplatz Rough (Grund), Fairway mit Mähstreifen, Grün, Bunkersand, Schotterweg; Kiesgrube Kies (Grund),
// Sand, Erde, Gras, Schotter. Die Kanten sind scharf und leicht ausgefranst (Rauschen), obwohl die Werte nur alle 2,5 m
// vorliegen. Steile Hänge der Kiesgrube zeigen geschichtete Abbruchkanten. Außerhalb des Zauns (UV.x = 1 am Rand)
// geht der Boden in die Felder der Landschaft über: dieselbe Rechnung wie shaders/land.gdshader, so gibt es keine
// Kante zum Boden ringsum. day: 0 Nacht, 1 Tag (wie der Landschaftsboden).
render_mode diffuse_burley, specular_disabled;

uniform float day = 1.0;
uniform int kind = 0;  // 0 Golfplatz, 1 Kiesgrube
uniform vec2 stripe_dir = vec2(1.0, 0.0);  // Mährichtung (Welt x, z)

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wts;
varying float skirt;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

// Felder wie shaders/land.gdshader (ohne Stadtmaske: die Gelände liegen draußen)
vec3 land_col(vec2 p, vec3 n) {
	float ang = (vnoise(p / 2200.0) - 0.5) * 2.4;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = rot * p;
	vec2 size = vec2(170.0, 95.0);
	vec2 cell = floor(q / size);
	vec2 f = fract(q / size);
	float r = h21(cell);
	float r2 = h21(cell + 17.3);
	vec3 col;
	float furrow = 0.5 + 0.5 * sin(q.x * 2.1);
	if (r < 0.32) {
		col = mix(vec3(0.16, 0.3, 0.09), vec3(0.22, 0.36, 0.11), r2);
	} else if (r < 0.52) {
		col = mix(vec3(0.55, 0.45, 0.2), vec3(0.62, 0.52, 0.25), furrow * 0.6);
	} else if (r < 0.68) {
		col = mix(vec3(0.25, 0.17, 0.1), vec3(0.33, 0.24, 0.15), furrow);
	} else if (r < 0.76) {
		col = mix(vec3(0.72, 0.66, 0.08), vec3(0.8, 0.74, 0.12), furrow * 0.5);
	} else if (r < 0.9) {
		col = mix(vec3(0.12, 0.24, 0.07), vec3(0.18, 0.3, 0.08), furrow);
	} else {
		col = mix(vec3(0.3, 0.38, 0.16), vec3(0.36, 0.42, 0.2), r2);
	}
	float edge = min(min(f.x, 1.0 - f.x) * size.x, min(f.y, 1.0 - f.y) * size.y);
	col = mix(vec3(0.1, 0.17, 0.06), col, smoothstep(0.8, 2.5, edge));
	if (h21(cell + 3.1) < 0.25 && f.y < 0.035) {
		col = vec3(0.36, 0.33, 0.27);
	}
	col *= 0.85 + 0.3 * vnoise(p / 260.0) + 0.08 * vnoise(p / 23.0);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	return mix(col, vec3(0.13, 0.2, 0.08), smoothstep(0.08, 0.3, slope));
}

// scharfe, leicht ausgefranste Grenze eines Kanals
float edge_w(float w, float n) {
	return smoothstep(0.44, 0.56, w + (n - 0.5) * 0.16);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	wts = COLOR;
	skirt = UV.x;
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = vnoise(p / 2.3);
	float n2 = vnoise(p / 9.0);
	float n3 = vnoise(p / 31.0);
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	vec3 col;
	if (kind == 0) {
		// Rough: dunkleres, längeres Gras in Flecken; Fairway hell mit Mähstreifen; Grün fein gestreift
		// Rough etwas gelblicher und fleckiger, Fairway kräftig grün mit deutlichen Mähstreifen
		vec3 rough = mix(vec3(0.13, 0.21, 0.06), vec3(0.19, 0.27, 0.08), n2) * (0.8 + 0.3 * n1) * (0.88 + 0.22 * n3);
		float st = step(0.5, fract(dot(p, stripe_dir) / 8.0));
		vec3 fair = mix(vec3(0.15, 0.32, 0.08), vec3(0.21, 0.4, 0.11), st) * (0.94 + 0.08 * n1);
		float st2 = step(0.5, fract(dot(p, vec2(-stripe_dir.y, stripe_dir.x)) / 3.2));
		vec3 green = mix(vec3(0.24, 0.47, 0.14), vec3(0.28, 0.52, 0.16), st2) * (0.97 + 0.05 * n1);
		vec3 sand = vec3(0.4, 0.36, 0.26) * (0.9 + 0.14 * n1);
		vec3 path = vec3(0.14, 0.135, 0.125) * (0.82 + 0.28 * vnoise(p * 1.7));
		col = rough;
		col = mix(col, fair, edge_w(wts.r, n2));
		col = mix(col, green, edge_w(wts.g, n1));
		// Bunkerkante: ein schmaler dunkler Rand aus Gras über dem Sand
		float sb = edge_w(wts.b, n1);
		col = mix(col, sand, sb);
		col = mix(col, col * 0.75, sb * (1.0 - smoothstep(0.5, 0.62, wts.b + (n1 - 0.5) * 0.16)));
		col = mix(col, path, edge_w(wts.a, n1));
	} else {
		// Kies: hellgrau-beige mit Steinchen, Fahrspuren dunkler; Sandhaufen gelblich; Erde braun; Gras in Flecken
		// Helligkeit wie der Boden ringsum (Mittagssonne): Kies grau-beige, nicht weiß
		// feines Korn (Kiesel) statt großer Flecken, dazu weite, schwache Helligkeitsunterschiede
		float grain = vnoise(p * 3.1) * 0.6 + vnoise(p * 8.3) * 0.4;
		vec3 kies = mix(vec3(0.165, 0.157, 0.138), vec3(0.2, 0.19, 0.166), n1 * 0.4 + n2 * 0.6) * (0.82 + 0.34 * grain) * (0.92 + 0.12 * n3);
		vec3 sand = mix(vec3(0.27, 0.22, 0.15), vec3(0.32, 0.27, 0.18), n2) * (0.94 + 0.08 * n1);
		vec3 erde = mix(vec3(0.14, 0.1, 0.065), vec3(0.19, 0.14, 0.09), n1) * (0.9 + 0.15 * n2);
		vec3 gras = mix(vec3(0.11, 0.18, 0.055), vec3(0.17, 0.24, 0.08), n2) * (0.85 + 0.25 * n1);
		vec3 schotter = mix(vec3(0.11, 0.107, 0.1), vec3(0.15, 0.145, 0.135), vnoise(p * 1.9));
		// Reifenspuren der Muldenkipper (lange flache Rinnen), dunkler Kies in Senken (feucht)
		float rut = smoothstep(0.82, 0.95, abs(sin(dot(p, vec2(0.6, 0.8)) * 0.9 + n3 * 6.0)));
		kies *= 1.0 - 0.12 * rut * smoothstep(0.3, 0.7, n2);
		col = kies;
		col = mix(col, sand, edge_w(wts.r, n2));
		col = mix(col, erde, edge_w(wts.g, n2));
		float gp = edge_w(wts.b * (0.75 + 0.5 * n3), n2);  // Gras wächst fleckig
		col = mix(col, gras, gp);
		col = mix(col, schotter, edge_w(wts.a, n1));
		// steile Wände: geschichtete Abbruchkante (Kies- und Sandbänder), wo kein Gras wächst
		float band = smoothstep(0.38, 0.5, fract(wpos.y / 1.35 + n1 * 0.25));
		vec3 cliff = mix(vec3(0.17, 0.14, 0.1), vec3(0.24, 0.2, 0.15), band) * (0.85 + 0.25 * n2);
		col = mix(col, cliff, smoothstep(0.32, 0.5, slope) * (1.0 - gp));
	}
	col = mix(col, land_col(p, wnrm), skirt);
	// etwas satter als gemischt (wie der Landschaftsboden; der Dunst nimmt Farbe weg)
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = max(mix(vec3(l), col, 1.25), vec3(0.0));
	ALBEDO = col * mix(0.16, 1.0, day);
	ROUGHNESS = 0.95;
}
