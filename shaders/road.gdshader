shader_type spatial;
// Matter Asphalt (oder Kopfsteinpflaster) mit Markierungen, Gullydeckeln, Flickstellen und vereinzelten Pfützen.
// UV.x = quer (0..1), UV.y = Meter in Fahrtrichtung.

uniform float lanes = 4.0;  // 4 Hauptstraße, 2 Seitenstraße, 0 ohne Markierung
uniform float road_w = 18.0;
uniform float cobble = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float x = UV.x;
	float y = UV.y;
	float xm = x * road_w;  // quer in Metern
	float lw = 0.14 / road_w;
	float white = 0.0;
	float yellow = 0.0;
	if (lanes > 3.0) {
		white = step(abs(x - 0.03), lw) + step(abs(x - 0.97), lw);
		float dash = step(fract(y / 9.0), 0.45);
		white += (step(abs(x - 0.25), lw) + step(abs(x - 0.75), lw)) * dash;
		yellow = step(abs(x - 0.488), lw * 0.7) + step(abs(x - 0.512), lw * 0.7);
	} else if (lanes > 1.0) {
		white = step(abs(x - 0.05), lw) + step(abs(x - 0.95), lw);
		white += step(abs(x - 0.5), lw) * step(fract(y / 6.0), 0.5);
	}
	float n = noise(vec2(xm * 2.2, y * 0.5)) * 0.5 + noise(vec2(xm * 6.6, y * 2.0)) * 0.5;
	// Pfützen nur hier und da: seltene, klar umrissene Flecken
	float puddle = smoothstep(0.69, 0.75, noise(vec2(xm * 0.33, y * 0.085))) * step(0.45, noise(vec2(y * 0.013, 7.3)));
	vec3 col = vec3(0.055, 0.055, 0.065) * (0.7 + 0.6 * n);
	// Flickstellen
	vec2 pc = vec2(floor(y / 14.0), floor(xm / 4.5));
	float patch = step(0.82, hash(pc + 3.1)) * step(0.1, fract(y / 14.0)) * step(fract(y / 14.0), 0.6);
	col *= mix(1.0, 0.7, patch);
	// Gullydeckel
	float mc = floor(y / 31.0);
	vec2 mpos = vec2(2.0 + hash(vec2(mc, 1.0)) * (road_w - 4.0), mc * 31.0 + 10.0);
	float md = length(vec2(xm, y) - mpos);
	float manhole = 1.0 - step(0.45, md);
	float ring = manhole * (step(0.36, md) + step(0.5, fract((xm + y) * 4.0)) * 0.4);
	col = mix(col, vec3(0.09, 0.085, 0.08) * (0.8 + ring), manhole);
	if (cobble > 0.5) {
		vec2 b = vec2(xm * 3.2 + step(0.5, fract(y * 2.2)) * 0.5, y * 2.2);
		float grout = clamp(step(0.88, fract(b.x)) + step(0.84, fract(b.y)), 0.0, 1.0);
		col = mix(vec3(0.09, 0.085, 0.08) * (0.7 + 0.6 * hash(floor(b))), vec3(0.025), grout);
		puddle *= 0.6;
	}
	col = mix(col, vec3(0.85), clamp(white, 0.0, 1.0));
	col = mix(col, vec3(0.9, 0.65, 0.1), clamp(yellow, 0.0, 1.0));
	col *= mix(1.0, 0.55, puddle);
	float wet_rough = 0.05;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Browser: keine Bildschirm-Spiegelungen, also etwas heller und breitere Lichtreflexe der Laternen
	col *= 1.7;
	wet_rough = 0.22;
#endif
	ALBEDO = col;
	ROUGHNESS = mix(0.84, wet_rough, puddle) * (1.0 - manhole * 0.2);
	METALLIC = manhole * 0.3;
	SPECULAR = mix(0.3, 0.6, puddle);
}
