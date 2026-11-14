shader_type spatial;
// Nebelbank über Wiesen und Senken (Landschaft): waagerechte Schicht mit ziehenden Schwaden, weich zum Rand und
// dort, wo sie Boden oder Bäume schneidet. strength: nachts und morgens kräftig, tagsüber fast weg.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.0;
uniform vec3 tint : source_color = vec3(0.6, 0.65, 0.75);
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

varying vec3 wpos;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), u.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(p / 70.0 + vec2(TIME * 0.012, TIME * 0.007)) * 0.65 + vnoise(p / 23.0 - vec2(TIME * 0.02, 0.0)) * 0.35;
	float r = length(UV - 0.5) * 2.0;
	float a = smoothstep(1.0, 0.45, r) * smoothstep(0.25, 0.75, n);
	// weich, wo die Schicht in Boden oder Bäume schneidet, und nah an der Kamera
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -vp.z / vp.w;
	float my_z = -VERTEX.z;
	a *= clamp((scene_z - my_z) / 6.0, 0.0, 1.0) * smoothstep(2.0, 12.0, my_z);
	ALBEDO = tint;
	ALPHA = a * strength;
}
