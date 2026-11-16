shader_type sky;
// Garage: Himmel nur für Spiegelungen (der Hintergrund bleibt die dunkle Halle). Er zeigt, was in einer hellen Werkstatt
// im Lack steht: drei Lichtbänder an der Decke über dem Prüfstand, ein weiches Lichtfeld an der Stirnwand, eine hohe
// schmale Softbox auf der Seite der Kamera (seit 2.38), ein Aufhelllicht vorn rechts und den dunklen Boden. Seit 2.35
// neutral weiß statt der pinken und blauen Neonröhren.

uniform float ceiling_e = 2.4;
uniform float wall_e = 0.35;
uniform float softbox_e = 1.5;

float box1(float x, float c, float w, float soft) {
	return 1.0 - smoothstep(w, w + soft, abs(x - c));
}

void sky() {
	vec3 d = EYEDIR;
	vec3 col = vec3(0.008, 0.009, 0.012);
	if (d.y < 0.0) {
		// Boden: dunkel, zum Horizont minimal heller (Hallenboden in der Ferne)
		col = mix(vec3(0.026, 0.027, 0.031), vec3(0.006, 0.006, 0.008), smoothstep(0.0, 0.35, -d.y));
	} else {
		// Decke ~5 m über dem Auto: drei Lichtbänder längs, je ~0,5 m breit und 7 m lang
		vec2 p = d.xz / max(d.y, 0.02) * 5.2;
		float strips = 0.0;
		for (int k = -1; k <= 1; k++) {
			strips += box1(p.x, float(k) * 1.3, 0.25, 0.08) * box1(p.y, 0.3, 3.5, 0.4);
		}
		col += vec3(1.0, 0.98, 0.95) * ceiling_e * strips * smoothstep(0.15, 0.35, d.y);
		// Rückwand (-Z, 6,75 m): weiches Lichtfeld des Wandstrahlers
		if (d.z < 0.0) {
			float t = d.y / -d.z * 6.75;
			float x = d.x / -d.z * 6.75;
			col += vec3(0.9, 0.93, 1.0) * wall_e * box1(x, -1.8, 3.0, 3.5) * box1(t, 0.8, 1.0, 1.8);
		}
		// Seite der Kamera (+X, 7,75 m, seit 2.38; vorher die linke Wand, als das Auto sich drehte): hohe schmale Softbox,
		// gibt eine klare Lichtkante auf die Flanke und die Scheiben, die man sieht
		if (d.x > 0.0) {
			float t = d.y / d.x * 7.75;
			float z = d.z / d.x * 7.75;
			col += vec3(0.95, 0.97, 1.0) * softbox_e * box1(z, 0.5, 0.55, 0.3) * box1(t, 1.2, 1.3, 0.35);
		}
		// weiches Aufhelllicht vorn rechts (wie das OmniLight bei (4, 2, 4))
		float a = max(dot(d, normalize(vec3(0.69, 0.22, 0.69))), 0.0);
		col += vec3(1.0, 0.97, 0.93) * 0.25 * pow(a, 24.0);
	}
	COLOR = col;
}
