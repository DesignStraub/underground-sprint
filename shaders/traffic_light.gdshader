shader_type spatial;
render_mode unshaded;
// Ampel: Zyklus grün 5 s, gelb 1.5 s, rot 5 s, rot-gelb 0.5 s. which: 0 rot, 1 gelb, 2 grün.

instance uniform float which = 0.0;
instance uniform float phase = 0.0;

void fragment() {
	float t = mod(TIME + phase, 12.0);
	float green = step(t, 5.0);
	float yellow = step(5.0, t) * step(t, 6.5) + step(11.5, t);
	float red = step(6.5, t);
	vec3 c = which < 0.5 ? vec3(1.0, 0.08, 0.05) : (which < 1.5 ? vec3(1.0, 0.65, 0.05) : vec3(0.1, 1.0, 0.35));
	float on = which < 0.5 ? red : (which < 1.5 ? yellow : green);
	ALBEDO = c * (0.08 + on * 4.0);
}
