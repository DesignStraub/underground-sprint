shader_type spatial;
// Hallenboden der Garage (seit 2.38, garage_set.gd): geschliffener Beton mit Flecken und Plattenfugen, dunkle
// Reifenspuren entlang der Fahrspur, Glanz wechselt leicht (polierte und stumpfe Stellen). Alles in Weltkoordinaten.
// Seit 2.39 ist das Laufband Teil des Bodens: ein bündiger Streifen von Tor zu Tor (lane_half, läuft unter beiden Toren
// durch), aus demselben Beton, nur ohne Querfugen; seine Ränder sind Plattenfugen wie alle anderen. Zwei abgenutzte
// weiße Linien weiter außen markieren die Fahrspur durch die Halle. Mit dem Band wandert nur das feine Korn (offset),
// Flecken, Glanz und Reifenspuren liegen fest. Schnell gezogen geht das Korn in feine Längsstreifen über, statt zu
// flimmern (blur): man sieht kein Band, das Auto fährt.

uniform float lane_half = 1.4;  // halbe Breite des Bands
uniform float line_x = 2.3;  // weiße Linien links und rechts der Fahrspur (Mitte der Linie)
uniform float track_x = 0.78;  // Reifenspuren links und rechts der Mitte
uniform float offset = 0.0;  // Weg des Bands in Metern (0 … 32, danach wiederholt sich das Muster nahtlos)
uniform float blur = 0.0;  // Weg des Bands je Bild in Metern

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

// wie noise, längs (y) nach per Zellen wiederholt: das Korn auf dem Band springt nicht, wenn offset umläuft, und die
// Werte für hash bleiben klein (genau auch im Browser-Renderer)
float pnoise(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float y0 = mod(i.y, per);
	float y1 = mod(i.y + 1.0, per);
	return mix(mix(hash(vec2(i.x, y0)), hash(vec2(i.x + 1.0, y0)), f.x), mix(hash(vec2(i.x, y1)), hash(vec2(i.x + 1.0, y1)), f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wp.xz;
	float ax = abs(p.x);
	float on = 1.0 - step(lane_half, ax);  // auf dem Band
	// feines Korn: neben dem Band fest, auf dem Band wandert es mit (32 m = 256 bzw. 16 Zellen). Zwischen 1 und 4 m/s
	// (bei 60 Bildern je Sekunde, gemessen am Weg je Bild) geht es in 2 m lange, 11 cm breite Längsstreifen über: so
	// sieht ein verwischtes Korn aus, und Streifen in Laufrichtung verraten die Bewegung kaum
	vec2 q = vec2(p.x, p.y - offset);
	float k = clamp(1.0 - (blur * 8.0 - 0.12) / 0.4, 0.0, 1.0);
	float moving = mix(pnoise(vec2(q.x * 9.0 + 1.3, q.y * 0.5), 16.0), pnoise(q * 8.0 + 7.7, 256.0), k);
	float grain = mix(noise(p * 8.0 + 7.7), moving, on);
	float n = noise(p * 0.55) * 0.55 + noise(p * 2.1 + 3.1) * 0.3 + grain * 0.15;
	vec3 col = vec3(0.066, 0.068, 0.073) * (0.78 + 0.44 * n);
	float rough = mix(0.26, 0.6, noise(p * 0.3 + 11.0));
	// Fugen der Betonplatten alle 4 m, gezählt von der Kante des Bands: sie ist eine Fuge wie jede andere. Das Band
	// selbst hat keine Querfugen (sie liefen sonst mit)
	float jw = max(fwidth(p.x), fwidth(p.y));
	float jx = abs(fract((ax - lane_half) / 4.0 + 0.5) - 0.5) * 4.0;
	float jz = abs(fract(p.y / 4.0) - 0.5) * 4.0 + on * 99.0;
	float joint = 1.0 - smoothstep(0.006, 0.006 + jw * 1.5 + 0.004, min(jx, jz));
	col *= 1.0 - 0.5 * joint;
	// Reifenspuren: zwei weiche dunkle Bänder entlang der Fahrspur, zu den Toren hin auslaufend
	float tq = (ax - track_x) / 0.16;  // quadriert statt pow(): pow mit negativer Basis ist in GLSL undefiniert
	float tr = exp(-tq * tq) * (0.5 + 0.5 * noise(vec2(p.x * 6.0, p.y * 0.7)));
	tr *= 1.0 - smoothstep(6.0, 11.0, abs(p.y));
	col *= 1.0 - 0.32 * tr;
	rough = mix(rough, 0.42, tr * 0.5);
	// weiße Linien links und rechts der Fahrspur, durchgehend von Tor zu Tor, abgenutzt
	float lw = 0.03;
	float line = 1.0 - smoothstep(lw - jw, lw + jw, abs(ax - line_x));
	float wear = smoothstep(0.22, 0.62, noise(p * 3.3 + 5.0) * 0.7 + noise(p * 17.0) * 0.3);
	col = mix(col, vec3(0.5, 0.5, 0.48), line * wear * 0.8);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.45;
}
