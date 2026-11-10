shader_type spatial;
// Autoscheiben (car_builder.gd, seit 2.25): dunkel getönt, sehr glatt, dazu eine leichte, falsche Spiegelung der
// Stadt (heller Streifen um den Horizont, oben etwas Himmel), stärker im flachen Blickwinkel (Fresnel). Bis 2.24 waren
// die Scheiben fast schwarz und wirkten wie aufgemalt. Die Lichter der Szene geben zusätzlich echte Glanzpunkte.
render_mode cull_back;

uniform vec3 tint : source_color = vec3(0.04, 0.05, 0.06);
uniform float mirror = 0.0;  // Verspiegelte Tönung: kräftigere Spiegelung

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	float horizon = exp(-pow(r.y * 5.0, 2.0));
	float sky = smoothstep(-0.05, 0.7, r.y);
	// Lichter der Stadt im Horizontstreifen: ein paar warme Flecken, die mit der Blickrichtung wandern
	float lights = smoothstep(0.55, 1.0, sin(atan(r.x, r.z) * 23.0) * sin(atan(r.x, r.z) * 7.0 + 1.3));
	vec3 refl = vec3(0.07, 0.085, 0.12) * sky + vec3(0.22, 0.2, 0.19) * horizon + vec3(0.45, 0.32, 0.18) * horizon * lights;
	ALBEDO = tint;
	METALLIC = mirror * 0.6;
	ROUGHNESS = 0.04;
	SPECULAR = 0.7;
	EMISSION = refl * (0.15 + 0.85 * fres) * (0.3 + 0.5 * mirror);
}
