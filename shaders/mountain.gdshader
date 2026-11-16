shader_type spatial;
// Berg der entworfenen Bergstrecken (Driftberg, seit 2.36): Waldboden mit Nadeln und Moos auf flachen Hängen,
// Granit mit waagrechten Bänken und Rissen auf steilen (Einschnitte, Stützhänge zwischen den Kehren), heller Schotter
// am Fuß der Felswände. day: 0 Nacht, 1 Tag (Track.set_daytime), nachts wie der Landschaftsboden fast schwarz.
render_mode diffuse_burley, specular_disabled;

uniform float day = 0.0;
uniform float vine = 0.0;  // 1: Weinberg (Rebzeilen den Hang hinunter, Trockenmauern quer)

varying vec3 wpos;
varying vec3 wnrm;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = wpos.xz;
	float n1 = vnoise(p / 6.0);
	float n2 = vnoise(p / 37.0);
	// Waldboden: Nadelstreu, Moos, dunkle Erde, dazwischen Heidelbeerkraut (Harz)
	vec3 floor_c = mix(vec3(0.07, 0.1, 0.04), vec3(0.12, 0.09, 0.05), n1) * (0.75 + 0.5 * n2);
	floor_c = mix(floor_c, vec3(0.08, 0.13, 0.05), smoothstep(0.6, 0.8, vnoise(p / 13.0 + 4.1)) * 0.6);
	// Granit: graubraun, waagrechte Bänke, senkrechte Klüfte
	float band = smoothstep(0.42, 0.5, fract(wpos.y / 1.9 + n1 * 0.35));
	float crack = smoothstep(0.93, 0.98, vnoise(vec2(dot(p, vec2(0.7, 0.7)) / 2.3, wpos.y / 9.0)));
	vec3 rock = mix(vec3(0.2, 0.19, 0.17), vec3(0.33, 0.31, 0.27), vnoise(vec2(dot(p, vec2(0.6, -0.8)) / 3.0, wpos.y / 2.0)));
	rock *= 0.82 + 0.18 * band;
	rock *= 1.0 - crack * 0.55;
	float steep = 1.0 - smoothstep(0.5, 0.74, wnrm.y);
	// Schotter und Geröll unter den Wänden: mittlere Neigung
	vec3 scree = vec3(0.24, 0.22, 0.19) * (0.8 + 0.4 * n1);
	float mid = smoothstep(0.72, 0.84, wnrm.y) * (1.0 - smoothstep(0.84, 0.93, wnrm.y));
	vec3 col = mix(floor_c, scree, mid * 0.55);
	if (vine > 0.5) {
		vec2 contour = normalize(vec2(-wnrm.z, wnrm.x) + vec2(0.0001));
		float row = smoothstep(0.5, 0.72, abs(fract(dot(p, contour) / 2.2) - 0.5) * 2.0);
		vec3 vines = mix(vec3(0.16, 0.13, 0.09), vec3(0.06, 0.12, 0.04), row);
		float wall = smoothstep(0.9, 0.95, fract(wpos.y / 5.0));
		vines = mix(vines, vec3(0.34, 0.31, 0.26), wall);
		float slope_ok = smoothstep(0.62, 0.7, wnrm.y) * (1.0 - smoothstep(0.96, 0.99, wnrm.y));
		col = mix(col, vines, slope_ok);
	}
	col = mix(col, rock, steep);
	ALBEDO = col * mix(0.2, 1.0, day);
	ROUGHNESS = 0.93;
}
