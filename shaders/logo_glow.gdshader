shader_type canvas_item;
// Färbt das (dunkle) Logo um und legt einen weichen Neon-Schein darum.

uniform vec4 tint : source_color = vec4(0.96, 0.97, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.15, 0.7, 1.0, 1.0);
uniform float glow = 1.0;
uniform float radius = 0.025;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	float g = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = float(i) * 0.3927;
		vec2 d = vec2(cos(ang), sin(ang));
		g += texture(TEXTURE, UV + d * radius).a + texture(TEXTURE, UV + d * radius * 2.2).a * 0.6;
	}
	g = clamp(g / 16.0, 0.0, 1.0) * glow;
	vec3 col = mix(glow_color.rgb * 1.6, tint.rgb, a);
	COLOR = vec4(col, max(a, g * 0.75) * COLOR.a);
}
