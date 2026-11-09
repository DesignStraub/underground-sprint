shader_type spatial;
// Auspuffflamme (car_builder: Kegel je Endrohr, Spitze nach hinten). Nitro: weißblauer Kern am Rohr, außen blau bis
// violett, zur Spitze ausfransend; die Flamme lodert (Rauschen läuft das Rohr hinunter) und zeigt die rautenförmigen
// Verdichtungen eines Gasstrahls. Fehlzündung beim Schalten oder Gaswegnehmen: kurzer, dicker, orangefarbener Stoß.
// Additiv und unbeleuchtet: sie leuchtet selbst, wirft keinen Schatten und bleibt im Nebel sichtbar.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float power = 1.0;  // 0..1 Stärke (Ein- und Ausblenden)
uniform float kick = 0.0;  // 0..1 Zündstoß: heller, weißer
uniform float fire = 0.0;  // 0..1 Anteil Fehlzündung (orange statt blau)
uniform float core = 0.0;  // 1 = innerer Kern (kürzer, weißer)
uniform float half_h = 0.35;  // halbe Kegelhöhe (Mesh)
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

varying float t_len;
varying float ang;

void vertex() {
	// Kegelachse ist die Mesh-Y-Achse: Grundfläche (am Rohr) bei -half_h, Spitze bei +half_h
	t_len = clamp((VERTEX.y + half_h) / (2.0 * half_h), 0.0, 1.0);
	ang = atan(VERTEX.z, VERTEX.x);
	// Flackern der Hülle: zur Spitze hin seitlich zitternd
	float w = (vnoise(vec2(t_len * 3.0 - TIME * 9.0, seed)) - 0.5) * 0.05 * t_len;
	VERTEX.x += w;
	VERTEX.z += (vnoise(vec2(t_len * 3.0 - TIME * 8.0, seed + 7.0)) - 0.5) * 0.05 * t_len;
}

void fragment() {
	float t = t_len;
	// Lodern: Rauschen läuft schnell vom Rohr zur Spitze
	float n = vnoise(vec2(t * 7.0 - TIME * 26.0, ang * 1.5 + seed));
	n = 0.6 * n + 0.4 * vnoise(vec2(t * 15.0 - TIME * 41.0, ang * 3.0 + seed * 3.0));
	// Silhouette weich: frontal angeschaute Mitte hell, Ränder blenden aus
	float facing = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.4);
	// zur Spitze ausfransen: das Rauschen frisst die Flamme von hinten auf
	float body = smoothstep(1.0, 0.25 + 0.45 * n, t) * smoothstep(0.0, 0.06, t);
	// Verdichtungsrauten im Gasstrahl (nur Nitro)
	float diamonds = 0.82 + 0.18 * cos(t * 34.0 - TIME * 3.0);
	vec3 hot = vec3(0.85, 0.95, 1.0);
	vec3 blue = vec3(0.12, 0.38, 1.0);
	vec3 violet = vec3(0.45, 0.12, 0.95);
	vec3 col = mix(hot, blue, smoothstep(0.0, 0.35, t));
	col = mix(col, violet, smoothstep(0.45, 1.0, t));
	col = mix(col, vec3(1.0), core * 0.55 + kick * 0.3 * (1.0 - t));
	col *= mix(1.0, diamonds, 1.0 - fire);
	// Fehlzündung: gelbweiß am Rohr, orange, zur Spitze rot
	vec3 fcol = mix(vec3(1.0, 0.85, 0.5), vec3(1.0, 0.42, 0.08), smoothstep(0.0, 0.5, t));
	fcol = mix(fcol, vec3(0.8, 0.12, 0.02), smoothstep(0.5, 1.0, t));
	col = mix(col, fcol, fire);
	float e = body * facing * (0.55 + 0.6 * n) * power * (1.0 + 0.8 * kick) * mix(1.6, 2.4, core);
	ALBEDO = col * e;
	ALPHA = 1.0;
}
