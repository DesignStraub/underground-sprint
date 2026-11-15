shader_type spatial;
// Reifenspuren (tire_fx.gd): ein Stück je Instanz, Zeitpunkt und Stärke in INSTANCE_CUSTOM. Dunkler Gummiabrieb mit
// weichen Rändern, verblasst über "life" Sekunden.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float now = 0.0;
uniform float life = 45.0;
varying float fade;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	fade = INSTANCE_CUSTOM.y * clamp(1.0 - age / life, 0.0, 1.0);
}

void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	ALBEDO = vec3(0.025, 0.025, 0.03);
	ALPHA = fade * edge * 0.55;
}
