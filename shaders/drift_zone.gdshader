shader_type spatial;
// Drift-Bonuszone (race.gd _build_drift_zones): leuchtender Streifen am Außenrand einer Kurve, Pfeile laufen in
// Fahrtrichtung. UV.x quer (0 innen, 1 an der Bande), UV.y Meter entlang; COLOR.a blendet an den Enden aus.
// active: Spieler driftet gerade in einer Zone (grün statt orange, heller).
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled;

uniform float active = 0.0;

void fragment() {
	float chev = fract(UV.y * 0.22 + abs(UV.x - 0.5) * 0.7 - TIME * (0.5 + active));
	float stripe = smoothstep(0.45, 0.5, chev) * (1.0 - smoothstep(0.75, 0.8, chev));
	float band = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.06, 1.0 - UV.x);
	float edge = smoothstep(0.82, 0.95, UV.x) * (1.0 - smoothstep(0.97, 1.0, UV.x));
	vec3 c = mix(vec3(1.0, 0.5, 0.05), vec3(0.25, 1.0, 0.45), active);
	float a = band * (0.07 + 0.3 * stripe) + edge * 0.5;
	ALBEDO = c * a * COLOR.a * (1.0 + 0.6 * active);
}
