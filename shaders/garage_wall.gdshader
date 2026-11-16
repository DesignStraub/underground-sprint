shader_type spatial;
// Wände der Garage (seit 2.38, garage_set.gd): gestrichene Kalksandsteine im Verband, unten ein dunkler Sockel mit
// Schmutz zum Boden hin, auf der Rückwand eine Lochwand für das Werkzeug (board: Rechteck in Wandkoordinaten,
// z0, y0, z1, y1). Wandkoordinate u: an Wänden quer zu x die Lage in z, sonst in x.

uniform vec4 board = vec4(-3.7, 1.05, 0.5, 2.45);
uniform float board_x = -6.5;  // Rückwand (Innenseite)

varying vec3 wp;
varying vec3 wn;

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
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = abs(wn.x) > 0.5 ? wp.z : wp.x;
	float v = wp.y;
	// Steine 40 x 20 cm im Läuferverband, Fugen leicht vertieft
	float row = floor(v / 0.2);
	vec2 b = vec2(fract(u / 0.4 + 0.5 * mod(row, 2.0)), fract(v / 0.2));
	vec2 bw = vec2(fwidth(u / 0.4), fwidth(v / 0.2));
	float mx = 1.0 - smoothstep(0.012, 0.012 + bw.x * 1.5 + 0.01, min(b.x, 1.0 - b.x));
	float my = 1.0 - smoothstep(0.025, 0.025 + bw.y * 1.5 + 0.02, min(b.y, 1.0 - b.y));
	float mortar = max(mx, my) * clamp(1.0 - (max(bw.x, bw.y) - 0.08) / 0.2, 0.0, 1.0);
	float stone = hash(vec2(floor(u / 0.4 + 0.5 * mod(row, 2.0)), row));
	float n = noise(vec2(u, v) * 1.7) * 0.6 + noise(vec2(u, v) * 7.0) * 0.4;
	vec3 col = vec3(0.2, 0.208, 0.218) * (0.9 + 0.14 * stone + 0.12 * n);
	// Sockel bis 1,1 m dunkel gestrichen, darüber eine schmale helle Kante
	float plinth = 1.0 - smoothstep(1.095, 1.105, v);
	col = mix(col, vec3(0.075, 0.08, 0.088) * (0.9 + 0.2 * n), plinth);
	col = mix(col, vec3(0.34, 0.35, 0.36), (1.0 - smoothstep(0.0, 0.012, abs(v - 1.11))) * 0.6);
	col *= 1.0 - 0.3 * mortar;
	// Schmutz zum Boden hin
	col *= 0.62 + 0.38 * smoothstep(0.0, 0.45 + 0.25 * noise(vec2(u * 2.0, 0.0)), v);
	float rough = 0.86;
	// Lochwand auf der Rückwand
	if (wn.x > 0.5 && wp.x > board_x - 0.05) {
		float inb = step(board.x, u) * step(u, board.z) * step(board.y, v) * step(v, board.w);
		if (inb > 0.5) {
			vec2 c = vec2(u, v) / 0.025;
			vec2 f = fract(c) - 0.5;
			float hw = max(fwidth(c.x), fwidth(c.y));
			float hole = (1.0 - smoothstep(0.16, 0.16 + hw * 1.2, length(f))) * clamp(1.0 - (hw - 0.3) / 0.3, 0.0, 1.0);
			col = mix(vec3(0.115, 0.13, 0.15), vec3(0.015), hole * 0.85);
			// heller Rahmen der Platte
			float e = min(min(u - board.x, board.z - u), min(v - board.y, board.w - v));
			col = mix(col, vec3(0.3, 0.31, 0.32), 1.0 - smoothstep(0.02, 0.026, e));
			rough = 0.7;
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
