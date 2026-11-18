shader_type spatial;
render_mode cull_disabled;
// Betonwand (Lärmschutzwand, Brücke, Tunnelportal) mit Fugen und Schmutzschlieren, in Weltkoordinaten (beliebige
// Meshes). Bis 2.43 lagen bunte Graffiti-Flecken darauf (sahen nach Müll aus); seit 2.44 auf den Lärmschutzwänden
// (deco = 1, UV.x = Meter entlang der Straße, UV.y = Höhe) stattdessen Efeu in Flecken, der vom Boden hochwächst, und
// selten das ONE-HUMANITY-Herz als weißes Wandbild (assets/murals/onehumanity_heart.png). Das Bild ist von beiden
// Seiten der Straße lesbar (nicht gespiegelt): die Richtung von UV.x auf dem Bildschirm entscheidet.

uniform float deco = 0.0;
uniform float ivy = 0.45;  // Anteil der Wand mit Efeu
uniform float murals = 0.015;  // Anteil der 7-m-Felder mit Wandbild
uniform sampler2D mural : source_color, filter_linear_mipmap, repeat_disable;
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
	float rough = 0.85;
	float side = 1.0 - step(0.9, abs(wnorm.y));
	if (deco > 0.5 && side > 0.5) {
		float s = UV.x;
		float h = UV.y;
		float sec = floor(s / 7.0);
		float lx = fract(s / 7.0) * 7.0;
		// Wandbild: das Herz, 3 m hoch, mittig im Feld; auf dem Bildschirm nie gespiegelt
		float has_m = step(hash(vec2(sec, 9.1)), murals);
		float mir = dFdx(s) < 0.0 ? -1.0 : 1.0;
		vec2 mp = vec2((lx - 3.5) * mir / 3.0 + 0.5, 1.0 - (h - 0.8) / 3.0);
		float inside = step(0.0, mp.x) * step(mp.x, 1.0) * step(0.0, mp.y) * step(mp.y, 1.0);
		float paint = texture(mural, clamp(mp, 0.0, 1.0)).a * inside * has_m;
		paint *= 0.82 + 0.18 * noise(vec2(s * 6.0, h * 6.0));  // etwas verwittert
		col = mix(col, vec3(0.86, 0.86, 0.84), paint);
		rough = mix(rough, 0.7, paint);
		// Efeu: Flecken entlang der Wand, vom Boden unterschiedlich hoch, mit blättrigem Rand (nicht über dem Bild)
		float grow = noise(vec2(s * 0.09, 5.3)) * 0.65 + noise(vec2(s * 0.37, 1.7)) * 0.35;
		float top = (grow - (1.0 - ivy)) / ivy * 4.6;
		float leaf = noise(vec2(s * 5.0, h * 5.0)) * 0.6 + noise(vec2(s * 13.0, h * 13.0)) * 0.4;
		float cover = (1.0 - smoothstep(top - 0.35, top, h + (leaf - 0.5) * 0.9)) * step(0.0, top) * (1.0 - has_m);
		cover *= smoothstep(0.25, 0.5, leaf + 0.35);  // Lücken zwischen den Blättern
		vec3 green = mix(vec3(0.05, 0.12, 0.045), vec3(0.15, 0.27, 0.09), leaf);
		green *= 0.8 + 0.4 * noise(vec2(s * 1.3, h * 1.3));
		col = mix(col, green, cover);
		rough = mix(rough, 0.75, cover);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
}
