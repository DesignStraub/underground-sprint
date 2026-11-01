shader_type canvas_item;
// Geschwindigkeitsgefühl: radiale Unschärfe (Nitro), Speedlines am Rand, blaue Vignette.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float lines = 0.0;
uniform float blur = 0.0;
uniform float nitro = 0.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = vec2(0.5, 0.5);
	vec2 d = uv - c;
	vec3 col = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		float k = 1.0 - blur * 0.07 * float(i) / 7.0;
		col += textureLod(screen_tex, c + d * k, 0.0).rgb;
	}
	col /= 8.0;
	float r = length(d * vec2(1.78, 1.0));
	float ang = atan(d.y, d.x);
	float seg = floor(ang * 45.0);
	float t = floor(TIME * 20.0);
	float h = hash(seg * 13.1 + t * 7.7);
	float streak = step(0.92, h) * smoothstep(0.45, 0.95, r) * lines;
	col = mix(col, vec3(0.9, 0.95, 1.0), streak * 0.4);
	float vig = smoothstep(0.5, 1.1, r);
	col = mix(col, vec3(0.1, 0.35, 1.0), vig * nitro * 0.4);
	COLOR = vec4(col, 1.0);
}
