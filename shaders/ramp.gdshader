shader_type spatial;
// Sprungrampe: Riffelblech oben, Warnstreifen an den Seiten.

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float top = step(0.3, wn.y);
	float s = step(0.5, fract((wpos.x + wpos.z + wpos.y) * 0.9));
	vec3 hazard = mix(vec3(0.02), vec3(1.0, 0.72, 0.05), s);
	float rib = step(0.5, fract((wpos.x - wpos.z) * 2.5));
	vec3 metal = vec3(0.2, 0.2, 0.22) * (0.85 + 0.3 * rib);
	ALBEDO = mix(hazard, metal, top);
	METALLIC = mix(0.2, 0.8, top);
	ROUGHNESS = mix(0.5, 0.35, top);
	EMISSION = hazard * (1.0 - top) * 0.25;
}
