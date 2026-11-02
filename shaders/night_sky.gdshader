shader_type sky;
// Nachthimmel: Verlauf, Lichtglocke der Stadt, Sterne, Mond, ferne Skyline mit Fenstern.

// Farben je Stimmung (scripts/moods.gd): Zenit, Horizont, Lichtglocke, Sternmenge
uniform vec3 top_col = vec3(0.008, 0.01, 0.03);
uniform vec3 hor_col = vec3(0.09, 0.05, 0.14);
uniform vec3 glow_col = vec3(0.3, 0.14, 0.32);
uniform float stars = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(hor_col, top_col, smoothstep(0.0, 0.45, h));
	col += glow_col * exp(-abs(h) * 12.0) * 0.35;
	if (h > 0.03 && stars > 0.01) {
		vec2 uv = d.xz / (h + 0.2) * 70.0;
		float s = step(1.0 - 0.004 * stars, hash(floor(uv)));
		col += s * smoothstep(0.05, 0.35, h) * (0.4 + 0.6 * hash(floor(uv) + 1.0));
	}
	float az = atan(d.x, d.z);
	float cell = floor(az * 90.0);
	float bh = 0.012 + hash(vec2(cell, 3.0)) * 0.05 * (0.6 + 0.4 * sin(az * 3.0 + 1.0));
	if (h < bh && h > -0.2) {
		col = vec3(0.012, 0.012, 0.025);
		vec2 wv = vec2(az * 1400.0, h * 500.0);
		float w = step(0.78, hash(floor(wv))) * step(0.35, fract(wv.x)) * step(0.4, fract(wv.y));
		col += w * vec3(1.0, 0.75, 0.45) * 0.5;
		float tip = step(bh - 0.0015, h) * step(0.85, hash(vec2(cell, 9.0))) * step(0.5, fract(TIME * 0.5 + hash(vec2(cell, 4.0))));
		col += tip * vec3(1.0, 0.1, 0.05) * 3.0;
	}
	vec3 md = normalize(vec3(-0.45, 0.32, -0.83));
	float m = dot(d, md);
	col += vec3(0.95, 0.95, 1.0) * smoothstep(0.99935, 0.9996, m) * 2.0 * step(0.05, stars);
	col += vec3(0.2, 0.25, 0.45) * pow(max(m, 0.0), 120.0) * 0.6;
	COLOR = col;
}
