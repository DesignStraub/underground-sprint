shader_type spatial;
// Dorfhäuser der Landschaft (MultiMesh, Farbe je Haus über COLOR): Putzwand mit Fensterraster in Weltmaßen
// (Fenster alle 3,2 m, Geschosse 2,9 m). Nachts brennt in einem Teil der Fenster warmes Licht (night 0..1).
render_mode diffuse_burley;

uniform float night = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying float base_y;
varying float top_y;
varying float seed;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	base_y = (MODEL_MATRIX * vec4(0.0, -0.5, 0.0, 1.0)).y;
	top_y = (MODEL_MATRIX * vec4(0.0, 0.5, 0.0, 1.0)).y;
	seed = h21(MODEL_MATRIX[3].xz);
}

void fragment() {
	vec3 col = COLOR.rgb;
	float side = 1.0 - abs(wnrm.y);
	float u = dot(wpos.xz, vec2(-wnrm.z, wnrm.x));
	float ly = wpos.y - base_y;
	vec2 cell = vec2(floor(u / 3.2), floor(ly / 2.9));
	vec2 f = vec2(fract(u / 3.2), fract(ly / 2.9));
	float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.78) * step(0.6, ly) * step(ly, top_y - base_y - 0.6) * step(0.5, side);
	float lit = step(0.62, h21(cell + seed * 91.0 + floor(wnrm.xz * 3.0)));
	col = mix(col, vec3(0.08, 0.09, 0.11), win);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.2, win);
	EMISSION = vec3(1.0, 0.72, 0.4) * win * lit * night * 2.2;
}
