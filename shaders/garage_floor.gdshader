shader_type spatial;
// Hallenboden der Garage (seit 2.38, garage_set.gd): geschliffener Beton mit Flecken und Plattenfugen, eine abgenutzte
// weiße Linie um den Prüfstand, an beiden Enden schraffierte Felder, wo die Autos auf- und abfahren, und dunkle
// Reifenspuren entlang der Fahrspur. Glanz wechselt leicht (polierte und stumpfe Stellen). Alles in Weltkoordinaten.

uniform vec2 bay_half = vec2(2.25, 4.4);  // Linie um den Prüfstand (halbe Breite, halbe Länge)
uniform vec2 deck_half = vec2(1.55, 3.5);  // Rahmen des Laufbands
uniform float track_x = 0.78;  // Reifenspuren links und rechts der Mitte

varying vec3 wp;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float n = noise(p * 0.55) * 0.55 + noise(p * 2.1 + 3.1) * 0.3 + noise(p * 8.0 + 7.7) * 0.15;
	vec3 col = vec3(0.066, 0.068, 0.073) * (0.78 + 0.44 * n);
	float rough = mix(0.26, 0.6, noise(p * 0.3 + 11.0));
	// Fugen der Betonplatten alle 4 m
	vec2 j = abs(fract(p / 4.0 + 0.5) - 0.5) * 4.0;
	float jw = max(fwidth(p.x), fwidth(p.y));
	float joint = 1.0 - smoothstep(0.006, 0.006 + jw * 1.5 + 0.004, min(j.x, j.y));
	col *= 1.0 - 0.5 * joint;
	// Reifenspuren: zwei weiche dunkle Bänder entlang der Fahrspur, zu den Seiten auslaufend
	float tq = (abs(p.x) - track_x) / 0.16;  // quadriert statt pow(): pow mit negativer Basis ist in GLSL undefiniert
	float tr = exp(-tq * tq) * (0.5 + 0.5 * noise(vec2(p.x * 6.0, p.y * 0.7)));
	tr *= 1.0 - smoothstep(6.0, 10.0, abs(p.y));
	col *= 1.0 - 0.32 * tr;
	rough = mix(rough, 0.42, tr * 0.5);
	// Linie um den Prüfstand (Rechteck-Abstand), abgenutzt
	vec2 q = abs(p) - bay_half;
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float lw = 0.035;
	float line = 1.0 - smoothstep(lw - jw, lw + jw, abs(sd));
	float wear = smoothstep(0.22, 0.62, noise(p * 3.3 + 5.0) * 0.7 + noise(p * 17.0) * 0.3);
	col = mix(col, vec3(0.5, 0.5, 0.48), line * wear * 0.8);
	// Schraffur an den Enden (zwischen Rahmen und Linie), gedämpftes Gelb
	float zone = step(abs(p.x), bay_half.x - 0.12) * step(deck_half.y + 0.12, abs(p.y)) * step(abs(p.y), bay_half.y - 0.12);
	float hatch = step(0.5, fract((p.x + p.y * sign(p.y)) / 0.36));
	col = mix(col, vec3(0.3, 0.235, 0.07), zone * hatch * wear * 0.55);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.45;
}
