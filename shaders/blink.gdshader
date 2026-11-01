shader_type spatial;
render_mode unshaded;
// Blinklicht (Antennen, Bahnübergang): leuchtet periodisch auf.

uniform vec3 col : source_color = vec3(1.0, 0.05, 0.02);
uniform float rate = 0.7;
instance uniform float phase = 0.0;
instance uniform float active = 1.0;

void fragment() {
	float on = step(0.5, fract(TIME * rate + phase)) * active;
	ALBEDO = col * (0.15 + on * 5.0);
}
