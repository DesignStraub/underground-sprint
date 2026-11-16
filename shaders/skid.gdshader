shader_type spatial;
// Reifenspuren (tire_fx.gd): ein Stück je Instanz, Zeitpunkt, Stärke und Untergrund in INSTANCE_CUSTOM. Dunkler
// Gummiabrieb mit weichen Rändern, verblasst über "life" Sekunden. Im Gelände (seit 2.39) Spuren in der Farbe des
// zerwühlten Bodens: dunkel im Gras, Fahrrinnen in Sand und Erde, grau im Kies.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float now = 0.0;
uniform float life = 45.0;
uniform float day = 1.0;
varying float fade;
varying vec3 col;
varying float strength;
varying float soil;

void vertex() {
	float age = now - INSTANCE_CUSTOM.x;
	fade = INSTANCE_CUSTOM.y * clamp(1.0 - age / life, 0.0, 1.0);
	int si = int(INSTANCE_CUSTOM.z + 0.5);
	// Asphalt, Gras, Rasen, Sand, Kies, Erde
	col = vec3(0.025, 0.025, 0.03);
	strength = 0.55;
	// immer dunkler als der Boden darunter (zerwühlt, feucht, im Schatten der Rinne)
	if (si == 1) { col = vec3(0.06, 0.075, 0.03); strength = 0.62; }
	else if (si == 2) { col = vec3(0.07, 0.1, 0.035); strength = 0.5; }
	else if (si == 3) { col = vec3(0.16, 0.13, 0.09); strength = 0.6; }
	else if (si == 4) { col = vec3(0.075, 0.07, 0.065); strength = 0.5; }
	else if (si == 5) { col = vec3(0.075, 0.055, 0.035); strength = 0.62; }
	soil = si > 0 ? 1.0 : 0.0;
}

void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
	// Gelände-Spuren sind Boden (nachts dunkel wie er), Gummi bleibt schwarz
	ALBEDO = col * mix(1.0, mix(0.16, 1.0, day), soil);
	ALPHA = fade * edge * strength;
}
