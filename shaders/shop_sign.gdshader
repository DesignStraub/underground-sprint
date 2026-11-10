shader_type spatial;
// Ladenschild (track_builder.gd _shop_sign): Fläche mit senkrechtem Farbverlauf, optional als Leuchtkasten (die ganze
// Fläche leuchtet, wie die beleuchteten Schilder deutscher Läden) und optional mit Streifen unten (z. B. Grün-Weiß-Rot
// bei der Pizzeria). UV.y läuft auf der Vorderseite von oben (0) nach unten (1).
render_mode cull_back;

uniform vec3 top_col : source_color = vec3(0.1);
uniform vec3 bottom_col : source_color = vec3(0.05);
uniform float glow = 0.0;  // 0 = angestrahlt, 1 = Leuchtkasten
uniform int band = 0;  // 0 keiner, 1 Grün-Weiß-Rot unten, 2 Schachbrett unten
uniform float sheen = 0.25;  // heller Glanzstreifen oben (Acrylglas)

void fragment() {
	vec2 uv = UV;
	vec3 c = mix(top_col, bottom_col, smoothstep(0.0, 1.0, uv.y));
	// Acrylglas: oben etwas heller, ein weicher Glanz
	c *= 1.0 + sheen * (1.0 - smoothstep(0.0, 0.35, uv.y));
	if (band == 1 && uv.y > 0.84) {
		float x = uv.x * 3.0;
		c = x < 1.0 ? vec3(0.0, 0.45, 0.2) : (x < 2.0 ? vec3(0.92) : vec3(0.75, 0.05, 0.08));
	} else if (band == 2 && uv.y > 0.86) {
		float ch = mod(floor(uv.x * 40.0) + floor(uv.y * 40.0 * 0.28), 2.0);
		c = vec3(mix(0.05, 0.9, ch));
	}
	ALBEDO = c * (1.0 - 0.6 * glow);
	ROUGHNESS = 0.35;
	EMISSION = c * glow * 1.6;
}
