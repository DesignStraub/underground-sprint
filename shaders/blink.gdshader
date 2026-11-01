shader_type spatial;
render_mode unshaded;
// Blinklicht (Antennen, Bahnübergang): leuchtet periodisch auf.

uniform vec3 col : source_color = vec3(1.0, 0.05, 0.02);
uniform float rate = 0.7;
uniform float phase = -1.0;  // < 0: aus der Position, so blinkt jede Antenne anders
uniform float active = 1.0;

void fragment() {
	float ph = phase >= 0.0 ? phase : fract(sin(dot(NODE_POSITION_WORLD.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float on = step(0.5, fract(TIME * rate + ph)) * active;
	ALBEDO = col * (0.15 + on * 5.0);
}
