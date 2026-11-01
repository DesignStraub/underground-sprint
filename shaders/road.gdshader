shader_type spatial;
// Nasser Asphalt mit Fahrbahnmarkierung. UV.x = quer (0..1), UV.y = Meter in Fahrtrichtung.

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
	float lw = 0.007;
	float white = step(abs(x - 0.03), lw) + step(abs(x - 0.97), lw);
	float dash = step(fract(y / 9.0), 0.45);
	white += (step(abs(x - 0.25), lw) + step(abs(x - 0.75), lw)) * dash;
	float yellow = step(abs(x - 0.488), lw * 0.7) + step(abs(x - 0.512), lw * 0.7);
	float n = noise(vec2(x * 40.0, y * 0.5)) * 0.5 + noise(vec2(x * 120.0, y * 2.0)) * 0.5;
	float puddle = smoothstep(0.55, 0.72, noise(vec2(x * 7.0, y * 0.12)));
	vec3 col = vec3(0.055, 0.055, 0.065) * (0.7 + 0.6 * n);
	col = mix(col, vec3(0.85), clamp(white, 0.0, 1.0));
	col = mix(col, vec3(0.9, 0.65, 0.1), clamp(yellow, 0.0, 1.0));
	col *= mix(1.0, 0.6, puddle);
	ALBEDO = col;
	ROUGHNESS = mix(0.5, 0.04, puddle);
	METALLIC = 0.15;
	SPECULAR = 0.7;
}
