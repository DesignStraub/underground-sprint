shader_type spatial;
// Laufband des Rollenprüfstands in der Garage (seit 2.38, garage_set.gd): dunkles Gummi mit feinen Querrillen und hellen
// Strichen an beiden Rändern, die mit dem Band nach hinten wandern (offset = Weg des Bands in Metern, das Auto fährt
// nach -Z). blur: so weit rückt das Band je Bild, gemessen in Rillen (garage.gd); schnell gezogen blenden die Rillen in
// ihren Mittelwert über, statt zu flimmern oder rückwärts zu laufen, die Striche ziehen sich weich in die Länge.

uniform float offset = 0.0;
uniform float blur = 0.0;
uniform vec2 half_size = vec2(1.35, 3.3);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

// weiche Kante einer Linie der Breite w (Einheiten wie t), AA über die Bildschirmableitung plus Bewegungsunschärfe
float band(float t, float w, float soft) {
	float d = abs(t);
	return 1.0 - smoothstep(w * 0.5 - soft, w * 0.5 + soft, d);
}

void fragment() {
	float z = lp.z - offset;
	float ax = abs(lp.x);
	vec3 col = vec3(0.027, 0.028, 0.031);
	float rough = 0.72;
	// Querrillen alle 11 cm: dunkle Fuge, dazwischen leicht gewölbtes Gummi (fängt etwas Licht)
	float g = z / 0.11;
	float fw = fwidth(g);
	float k = clamp(1.0 - (blur - 0.12) / 0.22, 0.0, 1.0) * clamp(1.0 - (fw - 0.25) / 0.35, 0.0, 1.0);
	float seam = band(fract(g + 0.5) - 0.5, 0.12, fw * 0.6 + 0.02);
	float crown = 1.0 - pow(abs(fract(g) * 2.0 - 1.0), 2.0);
	col *= mix(1.0, (1.0 - 0.55 * seam) * (0.88 + 0.2 * crown), k);
	rough = mix(rough, rough - 0.12 * crown, k);
	// Striche an den Rändern (außerhalb der Spur der Räder): 50 cm lang alle 1,2 m
	float edge = smoothstep(half_size.x - 0.26, half_size.x - 0.24, ax) * (1.0 - smoothstep(half_size.x - 0.07, half_size.x - 0.05, ax));
	float s = fract(z / 1.2) * 1.2;
	float soft = 0.01 + blur * 0.11 * 0.5;
	float dash = smoothstep(0.0 - soft, 0.0 + soft, s) * (1.0 - smoothstep(0.5 - soft, 0.5 + soft, s));
	dash = max(dash, smoothstep(1.2 - soft, 1.2 + soft, s));  // Rand der Teilung ohne Naht
	col = mix(col, vec3(0.42, 0.43, 0.44), edge * dash * 0.85);
	rough = mix(rough, 0.5, edge * dash);
	// zum Rahmen hin etwas dunkler (Spalt zwischen Band und Blech)
	col *= 0.6 + 0.4 * smoothstep(half_size.x, half_size.x - 0.03, ax) * smoothstep(half_size.y, half_size.y - 0.03, abs(lp.z));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	SPECULAR = 0.4;
}
