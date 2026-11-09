shader_type spatial;
// Feuerball an der Rohrmündung (car_builder, zur Flamme): eine Scheibe, die immer zur Kamera zeigt. Von hinten sieht
// man die Flamme fast genau von vorn, der Kegel allein wirkt dann dünn; der Ball zeigt, dass es dort brennt.
// Weißer Kern, blauer (Fehlzündung: orangefarbener) Schein, flackernd, mit kurzen Strahlen.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float power = 1.0;
uniform float kick = 0.0;
uniform float fire = 0.0;
uniform float size = 0.32;  // Radius in m

void vertex() {
	// Billboard: Lage vom Rohr, Ausrichtung von der Kamera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX *= size * (1.0 + 0.6 * kick + 0.25 * fire);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float flick = 0.85 + 0.15 * sin(TIME * 53.0 + a * 3.0) * sin(TIME * 31.0);
	// kurze Strahlen, die sich drehen
	float rays = pow(abs(sin(a * 4.0 + TIME * 2.5)), 8.0) * smoothstep(1.0, 0.2, r) * 0.35;
	float glow = exp(-r * r * 9.0) * 1.0 + exp(-r * 3.2) * 0.45 + rays;
	glow *= smoothstep(1.0, 0.8, r);
	vec3 col = mix(vec3(0.12, 0.38, 1.0), vec3(1.0, 0.45, 0.1), fire);
	col = mix(col, vec3(0.9, 0.95, 1.0), exp(-r * r * 70.0));
	ALBEDO = col * glow * flick * power * (1.0 + 0.8 * kick);
	ALPHA = 1.0;
}
