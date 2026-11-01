shader_type spatial;
// Hochhaus mit zufällig beleuchteten Fenstern (Weltkoordinaten, daher beliebig skalierbar).

instance uniform float seed = 0.0;
instance uniform vec3 tint = vec3(0.08, 0.08, 0.1);
instance uniform float shop_glass = 1.0;
instance uniform float window_light = 1.0;
varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
	float wall = 1.0 - step(0.9, abs(wnorm.y));
	// Obergeschosse: Fensterraster ab 4,2 m
	vec2 cell = vec2(u / 3.2, (wpos.y - 4.2) / 3.6);
	vec2 f = fract(cell);
	float win = step(0.18, f.x) * step(f.x, 0.82) * step(0.25, f.y) * step(f.y, 0.8);
	win *= wall * step(0.0, cell.y);
	float lit = step(0.6, hash(floor(cell) + seed * 13.7));
	vec3 wcol = mix(vec3(1.0, 0.72, 0.38), vec3(0.55, 0.75, 1.0), step(0.6, hash(floor(cell) * 1.31 + seed)));
	// Erdgeschoss: große Schaufenster, meist beleuchtet, bunt
	float shop_cell = floor(u / 6.0);
	float sf = fract(u / 6.0);
	float shop = wall * step(0.06, sf) * step(sf, 0.94) * step(0.5, wpos.y) * step(wpos.y, 3.4) * shop_glass;
	float shop_lit = step(0.2, hash(vec2(shop_cell, seed)));
	float hue = hash(vec2(shop_cell * 3.1, seed + 1.0));
	vec3 scol = hue < 0.5 ? vec3(1.0, 0.85, 0.6) : (hue < 0.7 ? vec3(0.6, 0.9, 1.0) : (hue < 0.85 ? vec3(1.0, 0.4, 0.7) : vec3(0.6, 1.0, 0.6)));
	float glass = max(win, shop);
	ALBEDO = mix(tint, vec3(0.02, 0.025, 0.03), glass);
	ROUGHNESS = mix(0.85, 0.1, glass);
	METALLIC = glass * 0.5;
	EMISSION = wcol * win * lit * 1.8 * window_light + scol * shop * shop_lit * 0.8;
}
