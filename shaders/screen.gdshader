shader_type spatial;
// Große LED-Videowand an Hochhäusern: wechselt alle paar Sekunden das Motiv, sichtbares Pixelraster.

instance uniform float seed = 0.0;

float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
vec3 pal(float t) { return 0.5 + 0.5 * cos(6.2831 * (t + vec3(0.0, 0.33, 0.67))); }

void fragment() {
	vec2 grid = vec2(48.0, 27.0);
	vec2 px = (floor(UV * grid) + 0.5) / grid;
	float t = TIME + seed * 17.0;
	float scene = floor(t / 5.0);
	float k = hash(scene + seed * 3.1);
	vec3 c;
	if (k < 0.33) {
		// Farbverlauf mit Wellen
		c = pal(px.x * 0.6 + t * 0.15 + k) * (0.55 + 0.45 * sin(px.y * 14.0 - t * 3.0));
	} else if (k < 0.66) {
		// Pulsierender Ring
		float r = length((px - 0.5) * vec2(1.78, 1.0));
		c = pal(k * 3.0) * smoothstep(0.06, 0.0, abs(r - 0.28 - 0.05 * sin(t * 4.0))) + pal(k + 0.5) * 0.12;
	} else {
		// Laufschrift-Balken
		float row = floor(px.y * 6.0);
		float bar = step(hash(row + scene) * 0.7 + 0.15, fract(px.x * 1.5 + t * 0.35 * (hash(row) + 0.3)));
		c = mix(vec3(0.02), pal(k + row * 0.12), bar);
	}
	vec2 g = fract(UV * grid);
	float led = smoothstep(0.55, 0.3, length(g - 0.5));
	ALBEDO = vec3(0.0);
	ROUGHNESS = 0.3;
	EMISSION = c * (0.3 + 0.7 * led) * 2.4;
}
