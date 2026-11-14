shader_type sky;
// Nachthimmel: Verlauf, Lichtglocke der Stadt, Sterne, Mond, ferne Skyline mit Fenstern.

// Farben je Stimmung (scripts/moods.gd): Zenit, Horizont, Lichtglocke, Sternmenge
uniform vec3 top_col = vec3(0.008, 0.01, 0.03);
uniform vec3 hor_col = vec3(0.09, 0.05, 0.14);
uniform vec3 glow_col = vec3(0.3, 0.14, 0.32);
uniform float stars = 1.0;
// Tag-Nacht-Wechsel (world.gd): 0 Nacht, 1 Tag; Richtung zur Sonne (am Tag Sonnenscheibe statt Mond)
uniform float day = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.5, -0.86);
// Open World (seit 2.29): ferne Hügelketten statt Skyline rundum, die Skyline nur in zwei Richtungen (land = 1)
uniform float land = 0.0;

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
	float city_dir = smoothstep(0.55, 0.75, sin(az * 2.0 + 0.7));
	if (land > 0.5) {
		bh *= city_dir;
		// Hügelketten in zwei Lagen: hinten heller (Dunst), vorn dunkler
		float back = 0.016 + 0.012 * sin(az * 4.0 + 1.3) + 0.007 * sin(az * 11.0 + 0.4) + 0.003 * sin(az * 29.0);
		float front = 0.008 + 0.009 * sin(az * 6.0 + 2.1) + 0.005 * sin(az * 17.0 + 1.1) + 0.002 * sin(az * 41.0 + 3.0);
		if (h < back && h > -0.2 && h >= bh) {
			col = mix(mix(vec3(0.02, 0.025, 0.04), hor_col, 0.5), mix(hor_col, vec3(0.45, 0.55, 0.62), 0.35), day);
		}
		if (h < front && h > -0.2 && h >= bh) {
			col = mix(mix(vec3(0.012, 0.016, 0.022), hor_col, 0.3), mix(hor_col, vec3(0.33, 0.43, 0.42), 0.55), day);
			// Dorflichter in der Nacht
			vec2 lv = vec2(az * 900.0, h * 300.0);
			col += step(0.985, hash(floor(lv))) * vec3(1.0, 0.75, 0.45) * 0.6 * (1.0 - day);
		}
	}
	if (h < bh && h > -0.2) {
		col = mix(vec3(0.012, 0.012, 0.025), hor_col * 0.55, day);
		vec2 wv = vec2(az * 1400.0, h * 500.0);
		float w = step(0.78, hash(floor(wv))) * step(0.35, fract(wv.x)) * step(0.4, fract(wv.y));
		col += w * vec3(1.0, 0.75, 0.45) * 0.5 * (1.0 - day);
		float tip = step(bh - 0.0015, h) * step(0.85, hash(vec2(cell, 9.0))) * step(0.5, fract(TIME * 0.5 + hash(vec2(cell, 4.0))));
		col += tip * vec3(1.0, 0.1, 0.05) * 3.0;
	}
	vec3 md = normalize(vec3(-0.45, 0.32, -0.83));
	float m = dot(d, md);
	col += vec3(0.95, 0.95, 1.0) * smoothstep(0.99935, 0.9996, m) * 2.0 * step(0.05, stars) * (1.0 - day);
	col += vec3(0.2, 0.25, 0.45) * pow(max(m, 0.0), 120.0) * 0.6 * (1.0 - day);
	float sm = dot(d, normalize(sun_dir));
	col += vec3(1.0, 0.95, 0.8) * smoothstep(0.9990, 0.9994, sm) * 6.0 * day;
	col += vec3(1.0, 0.8, 0.55) * pow(max(sm, 0.0), 40.0) * 0.5 * day;
	COLOR = col;
}
