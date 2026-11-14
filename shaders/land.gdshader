shader_type spatial;
// Landschaftsboden der Open World (seit 2.29; davor eine graue Fläche): Flickenteppich aus Feldern wie über
// Deutschland gesehen. Wiese, Weizen, Acker mit Furchen, Raps (leuchtend gelb), Mais, dazwischen Feldwege und Hecken.
// Felder in leicht gedrehten Rastern, damit es nicht wie ein Schachbrett wirkt. Steile Hänge werden dunkler.
// day: 0 Nacht, 1 Tag (die Farbe wird nachts wie der alte Boden fast schwarz).
render_mode diffuse_burley, specular_disabled;

uniform float day = 1.0;
uniform sampler2D urban_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec3 mask_rect = vec3(-10000.0, -10000.0, 20000.0);  // x0, z0, Kantenlänge

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
	// großräumig gedrehte Flurstücke (alle ~2 km eine andere Richtung)
	float ang = (vnoise(p / 2200.0) - 0.5) * 2.4;
	mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
	vec2 q = rot * p;
	vec2 size = vec2(170.0, 95.0);
	vec2 cell = floor(q / size);
	vec2 f = fract(q / size);
	float r = h21(cell);
	float r2 = h21(cell + 17.3);
	vec3 col;
	float furrow = 0.5 + 0.5 * sin(q.x * 2.1);  // Reihen entlang des Feldes
	if (r < 0.32) {
		col = mix(vec3(0.16, 0.3, 0.09), vec3(0.22, 0.36, 0.11), r2);  // Wiese
	} else if (r < 0.52) {
		col = mix(vec3(0.55, 0.45, 0.2), vec3(0.62, 0.52, 0.25), furrow * 0.6);  // Weizen
	} else if (r < 0.68) {
		col = mix(vec3(0.25, 0.17, 0.1), vec3(0.33, 0.24, 0.15), furrow);  // Acker gepflügt
	} else if (r < 0.76) {
		col = mix(vec3(0.72, 0.66, 0.08), vec3(0.8, 0.74, 0.12), furrow * 0.5);  // Raps
	} else if (r < 0.9) {
		col = mix(vec3(0.12, 0.24, 0.07), vec3(0.18, 0.3, 0.08), furrow);  // Mais
	} else {
		col = mix(vec3(0.3, 0.38, 0.16), vec3(0.36, 0.42, 0.2), r2);  // Brache
	}
	// Feldraine, Wege und Hecken an den Rändern
	float edge = min(min(f.x, 1.0 - f.x) * size.x, min(f.y, 1.0 - f.y) * size.y);
	col = mix(vec3(0.1, 0.17, 0.06), col, smoothstep(0.8, 2.5, edge));
	if (h21(cell + 3.1) < 0.25 && f.y < 0.035) {
		col = vec3(0.36, 0.33, 0.27);  // Feldweg
	}
	// Großflächige Helligkeitsunterschiede und Flecken
	col *= 0.85 + 0.3 * vnoise(p / 260.0) + 0.08 * vnoise(p / 23.0);
	// Hänge: dunkler und grüner (Wald- und Wiesenhang)
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	col = mix(col, vec3(0.13, 0.2, 0.08), smoothstep(0.08, 0.3, slope));
	// Stadt: dunkler Asphalt- und Pflasterboden (Parkplätze, Höfe), weich zu den Feldern
	vec2 mk = texture(urban_mask, (p - mask_rect.xy) / mask_rect.z).rg;
	float urb = smoothstep(0.25, 0.6, mk.r);
	// Waldboden: Nadeln, Moos, dunkle Erde (rund um Waldstrecken)
	vec3 floor_c = mix(vec3(0.07, 0.1, 0.04), vec3(0.12, 0.09, 0.05), vnoise(p / 7.0)) * (0.8 + 0.4 * vnoise(p / 40.0));
	col = mix(col, floor_c, smoothstep(0.2, 0.6, mk.g));
	vec3 town = vec3(0.055, 0.056, 0.06) * (0.8 + 0.4 * vnoise(p / 9.0)) * (0.85 + 0.3 * h21(floor(p / 14.0)));
	col = mix(col, town, urb);
	// etwas satter als gemischt (der Dunst nimmt Farbe weg)
	float l = dot(col, vec3(0.3, 0.59, 0.11));
	col = max(mix(vec3(l), col, 1.25), vec3(0.0));
	ALBEDO = col * mix(0.16, 1.0, day);
	ROUGHNESS = 0.95;
}
