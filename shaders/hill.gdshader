shader_type spatial;
// Hügel der Orts-Strecken bei Nacht: Weinberg mit Rebzeilen, Wald, Park.

uniform int kind = 0;  // 0 Weinberg, 1 Wald, 2 Park
varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col;
	if (kind == 0) {
		// Rebzeilen den Hang hinunter, dazwischen heller Boden; Weinbergsmauern als Querbänder
		float row = smoothstep(0.55, 0.75, abs(fract(wpos.x / 2.2) - 0.5) * 2.0);
		float wall = step(0.94, fract(wpos.y / 9.0));
		col = mix(vec3(0.07, 0.1, 0.04), vec3(0.17, 0.14, 0.1), row);
		col = mix(col, vec3(0.3, 0.27, 0.22), wall);
	} else if (kind == 1) {
		col = vec3(0.035, 0.08, 0.04) * (0.7 + 0.6 * hash(floor(wpos.xz / 3.0)));
	} else {
		col = vec3(0.05, 0.1, 0.045) * (0.85 + 0.3 * hash(floor(wpos.xz / 2.0)));
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
