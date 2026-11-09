shader_type sky;
// Garage: Himmel nur für Spiegelungen (der Hintergrund bleibt die dunkle Halle). Er zeigt, was in einem echten
// Showroom im Lack steht: drei Lichtbänder an der Decke über dem Drehteller, die Neonröhren an Rück- und linker
// Wand (gleiche Höhe und Farbe wie in garage.gd), ein weiches Aufhelllicht vorn rechts und den dunklen Boden.

uniform vec3 neon_a : source_color = vec3(1.0, 0.1, 0.6);
uniform vec3 neon_b : source_color = vec3(0.1, 0.7, 1.0);
uniform float ceiling_e = 2.6;
uniform float neon_e = 3.0;

float box1(float x, float c, float w, float soft) {
	return 1.0 - smoothstep(w, w + soft, abs(x - c));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = vec3(0.01, 0.01, 0.016);
	if (d.y < 0.0) {
		// Boden: dunkel, zum Horizont minimal heller (Hallenboden in der Ferne)
		col = mix(vec3(0.03, 0.03, 0.04), vec3(0.008, 0.008, 0.012), smoothstep(0.0, 0.35, -d.y));
	} else {
		// Decke ~5 m über dem Auto: drei Lichtbänder längs, je ~0,5 m breit und 7 m lang
		vec2 p = d.xz / max(d.y, 0.02) * 5.2;
		float strips = 0.0;
		for (int k = -1; k <= 1; k++) {
			strips += box1(p.x, float(k) * 1.3, 0.25, 0.06) * box1(p.y, 0.3, 3.5, 0.3);
		}
		col += vec3(1.0, 0.97, 0.92) * ceiling_e * strips * smoothstep(0.15, 0.35, d.y);
		// Rückwand (-Z, 6,75 m): Röhren auf 2,2 m (pink) und 3,0 m (cyan), 14 m lang
		if (d.z < 0.0) {
			float t = d.y / -d.z * 6.75;
			float x = d.x / -d.z * 6.75;
			float along = box1(x, 0.0, 7.0, 0.2);
			col += neon_a * neon_e * box1(t, 1.4, 0.05, 0.05) * along;
			col += neon_b * neon_e * box1(t, 2.2, 0.05, 0.05) * along;
			col += mix(neon_a, neon_b, 0.5) * 0.05 * along * box1(t, 1.8, 0.8, 0.8);  // Schein auf der Wand
		}
		// linke Wand (-X, 7,75 m): Röhre auf 2,6 m (cyan), 12 m lang
		if (d.x < 0.0) {
			float t = d.y / -d.x * 7.75;
			float z = d.z / -d.x * 7.75;
			float along = box1(z, 0.0, 6.0, 0.2);
			col += neon_b * neon_e * box1(t, 1.8, 0.05, 0.05) * along;
			col += neon_b * 0.04 * along * box1(t, 1.8, 0.8, 0.8);
		}
		// weiches Aufhelllicht vorn rechts (wie das OmniLight bei (4, 2, 4))
		float a = max(dot(d, normalize(vec3(0.69, 0.22, 0.69))), 0.0);
		col += vec3(0.9, 0.9, 1.0) * 0.25 * pow(a, 24.0);
	}
	COLOR = col;
}
