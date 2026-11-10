shader_type spatial;
// See bei Nacht: dunkel, spiegelnd, leichte Wellen.

uniform vec3 deep : source_color = vec3(0.01, 0.025, 0.04);
// Teiche im Stadtpark (seit 2.25): spiegeln stärker (fast wie ein Spiegel, die Reflexionssonde liefert das Bild)
uniform float mirror = 0.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 n = vec2(sin(p.x * 0.9 + t * 1.3) + 0.6 * sin(p.y * 1.7 - t * 0.9 + p.x * 0.3),
		cos(p.y * 0.8 + t * 1.1) + 0.5 * cos(p.x * 1.9 + t * 0.7)) * 0.05;
	vec3 wn = normalize(vec3(n.x, 1.0, n.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = deep;
	// Mondglitzern und gespiegelte Lichter: kleine, wandernde Funken (Fluss und See sind nachts sonst nur schwarz)
	float g = sin(p.x * 3.1 + t * 2.3 + sin(p.y * 1.7 + t)) * sin(p.y * 2.7 - t * 1.9 + cos(p.x * 1.3));
	EMISSION = vec3(0.55, 0.62, 0.8) * pow(max(g, 0.0), 12.0) * 0.9 + vec3(0.01, 0.02, 0.035);
	ROUGHNESS = mix(0.03, 0.015, mirror);
	METALLIC = mix(0.1, 0.8, mirror);
	SPECULAR = 0.9;
}
