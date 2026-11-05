shader_type spatial;
// Tunnelwand: glänzende Kacheln, dunkler Sockel, gelb-schwarzes Warnband, nach oben verrußt.
// UV.x = Meter in Fahrtrichtung, UV.y = Höhe in Metern.

#include "res://shaders/street_light.gdshaderinc"

varying vec3 w_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	vec2 t = vec2(u / 0.6, v / 0.3);
	t.x += step(0.5, fract(t.y * 0.5)) * 0.5;
	float grout = max(step(0.93, fract(t.x)), step(0.88, fract(t.y)));
	vec3 col = vec3(0.6, 0.56, 0.48) * (0.82 + 0.18 * hash(floor(t)));
	col = mix(col, vec3(0.22, 0.21, 0.19), grout);
	float rough = mix(0.18, 0.6, grout);
	if (v < 1.1) {
		col = vec3(0.16, 0.16, 0.17) * (0.75 + 0.4 * noise(vec2(u * 2.0, v * 6.0)));
		rough = 0.85;
	}
	float band = step(1.1, v) * step(v, 1.4);
	float chev = step(0.5, fract((u + v) / 1.2));
	col = mix(col, mix(vec3(0.85, 0.62, 0.05), vec3(0.03), chev), band);
	col *= 1.0 - 0.45 * smoothstep(3.0, 7.0, v) * (0.6 + 0.4 * noise(vec2(u * 0.3, v)));
	ALBEDO = col;
	EMISSION = street_lit(col, w_pos) * mix(0.8, 0.35, smoothstep(1.0, 6.0, v));
	ROUGHNESS = rough;
	SPECULAR = 0.6;
}
