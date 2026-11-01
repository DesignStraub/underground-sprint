shader_type spatial;
render_mode cull_disabled;
// Betonwand (Lärmschutzwand, Brücke, Tunnelportal) mit Fugen, Schmutzschlieren und Graffiti.
// Alles in Weltkoordinaten, funktioniert auf beliebigen Meshes.

uniform float graffiti = 0.6;
varying vec3 wpos;
varying vec3 wnorm;

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
}

void fragment() {
	float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
	float v = wpos.y;
	float n = noise(vec2(u * 0.8, v * 0.8)) * 0.5 + noise(vec2(u * 3.0, v * 3.0)) * 0.5;
	vec3 col = vec3(0.27, 0.27, 0.28) * (0.75 + 0.35 * n);
	col *= 1.0 - 0.3 * noise(vec2(u * 4.0, v * 0.2));  // Regenschlieren
	col *= 1.0 - 0.5 * step(0.965, fract(u / 4.0));  // Fugen
	// Graffiti: pro Abschnitt ein farbiger Tag mit dunkler Kontur
	float sec = floor(u / 7.0);
	float has = step(1.0 - graffiti, hash(vec2(sec, 3.7))) * (1.0 - step(0.9, abs(wnorm.y)));
	vec2 lp = vec2(fract(u / 7.0) * 7.0, v);
	float blob = noise(lp * vec2(1.4, 1.8) + sec * 5.3) * 0.7 + noise(lp * 4.0 + sec) * 0.3;
	float area = step(0.4, v) * step(v, 2.7) * step(0.7, lp.x) * step(lp.x, 6.3);
	float fill = smoothstep(0.55, 0.58, blob) * area;
	float line = (smoothstep(0.5, 0.53, blob) * area - fill);
	vec3 gcol = 0.55 + 0.45 * cos(6.2831 * (hash(vec2(sec, 1.0)) + vec3(0.0, 0.33, 0.67)));
	col = mix(col, gcol * 0.75, fill * has);
	col = mix(col, vec3(0.015), clamp(line, 0.0, 1.0) * has);
	ALBEDO = col;
	ROUGHNESS = 0.85 - 0.3 * fill * has;
}
