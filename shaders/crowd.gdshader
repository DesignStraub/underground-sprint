shader_type spatial;
// Publikum an der Drift-Strecke: jede Figur hüpft und jubelt in ihrem eigenen Takt. Farbe pro Figur (MultiMesh).

varying vec3 col;

void vertex() {
	float ph = float(INSTANCE_ID) * 1.618;
	float hop = max(sin(TIME * (5.0 + mod(ph, 3.0)) + ph * 6.0), 0.0);
	VERTEX.y += hop * 0.18;
	col = COLOR.rgb;
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.8;
}
