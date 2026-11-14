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

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 5; k++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Sterne (seit 2.30): runde, weich leuchtende Punkte in drei Größen, leicht farbig (bläulich bis gelblich),
// funkelnd, dazu ein schwaches Band der Milchstraße. Ein Stern je Zelle, zufällig darin versetzt.
vec3 star_layer(vec2 uv, float density, float size) {
	size *= 1.25;
	vec2 c = floor(uv);
	vec2 f = fract(uv);
	float h = hash(c);
	if (h > density) {
		return vec3(0.0);
	}
	vec2 pos = vec2(hash(c + 3.1), hash(c + 7.7)) * 0.7 + 0.15;
	float d = length(f - pos);
	float b = hash(c + 11.3);
	float tw = 0.75 + 0.25 * sin(TIME * (1.5 + b * 4.0) + h * 40.0);
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.75), hash(c + 5.5));
	return tint * smoothstep(size, 0.0, d) * (0.35 + 0.9 * b) * tw;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(hor_col, top_col, smoothstep(0.0, 0.45, h));
	col += glow_col * exp(-abs(h) * 12.0) * 0.35;
	if (h > 0.02 && stars > 0.01) {
		vec2 uv = d.xz / (h + 0.35);
		float fade = smoothstep(0.02, 0.3, h) * stars * (1.0 - smoothstep(0.1, 0.45, day));
		vec3 st = star_layer(uv * 60.0, 0.09, 0.07) + star_layer(uv * 130.0 + 17.0, 0.12, 0.09) * 0.7
			+ star_layer(uv * 26.0 + 5.0, 0.05, 0.05) * 1.6;
		// Milchstraße: schräges Band aus feinem Nebel und dichteren Sternen
		float band = exp(-pow(dot(d, normalize(vec3(0.55, 0.45, -0.7))) * 3.2, 2.0));
		float neb = fbm(uv * 3.0) * band;
		st += star_layer(uv * 220.0 + 3.0, 0.35, 0.12) * band * 0.6;
		col += (st * 1.7 + vec3(0.12, 0.13, 0.2) * neb * 0.7) * fade;
	}
	// Wolken (seit 2.30): Haufenwolken auf einer gedachten Ebene, ziehen langsam; tagsüber weiß mit grauem Bauch,
	// abends von der Sonne angestrahlt, nachts dunkel vor dem Sternenhimmel (die Lichtglocke färbt sie von unten)
	if (h > 0.0) {
		vec2 cp = d.xz / (h + 0.08) * 1.6 + vec2(TIME * 0.004, TIME * 0.0015);
		float cov = mix(0.58, 0.47, smoothstep(0.0, 0.5, day)) + 0.05 * sin(TIME * 0.01);  // nachts lockerer
		float n = fbm(cp);
		float cl = smoothstep(cov, cov + 0.22, n) * smoothstep(0.0, 0.12, h);
		float shade = smoothstep(cov, cov + 0.45, fbm(cp + vec2(0.06, 0.04)));
		vec3 sunlit = mix(vec3(1.0), glow_col * 2.2 + vec3(0.3, 0.2, 0.15), clamp(1.0 - day * 1.6, 0.0, 1.0) * step(0.05, day));
		vec3 day_c = mix(sunlit, vec3(0.62, 0.66, 0.74), shade * 0.7);
		vec3 night_c = mix(vec3(0.025, 0.028, 0.045), glow_col * 0.35, smoothstep(0.25, 0.0, h));
		col = mix(col, mix(night_c, day_c, smoothstep(0.0, 0.6, day)), cl * mix(0.85, 0.95, day));
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
