shader_type spatial;
// Rotes Gefahrenfeuer auf Windrädern (Landschaft): blinkt nachts im Takt (alle Anlagen zugleich, wie in echt),
// tagsüber fast aus.
render_mode unshaded, shadows_disabled;

uniform float night = 0.0;
uniform vec3 col : source_color = vec3(1.0, 0.05, 0.02);

void fragment() {
	float on = step(0.45, fract(TIME * 0.6));
	ALBEDO = col * mix(0.15, 4.0 * on, night);
}
