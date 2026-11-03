shader_type spatial;
// Gehweg wie in NFSU: große Betonplatten mit dunklen Fugen, Flecken und Kaugummi-Punkten, an beiden Rändern eine
// Reihe heller Bordsteine; senkrechte Flächen (Bordsteinkanten) als heller Beton. Nass glänzen die Fugen zuerst.
// UV.x = quer (0..1), UV.y = Meter längs; walk_w = Breite in Metern. Detail-Textur wie beim Asphalt.

uniform float walk_w = 5.0;
uniform float wet = 0.0;
uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 w_pos;
varying vec3 w_nrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// Fugen eines Rasters (Abstand s), geglättet; 1 = Fuge
float joints(vec2 p, vec2 s, float w) {
	vec2 q = abs(fract(p / s + 0.5) - 0.5) * s;  // Abstand zur nächsten Fuge in Metern
	vec2 aa = fwidth(p) * 0.8;
	vec2 j = 1.0 - smoothstep(vec2(w) - aa, vec2(w) + aa, q);
	return max(j.x, j.y);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 col;
	float rough;
	if (abs(normalize(w_nrm).y) < 0.5) {
		// Bordsteinkante: heller Beton, Fugen alle 1 m
		float along = w_pos.x + w_pos.z;
		vec4 dt = texture(detail, vec2(along, w_pos.y * 2.0) / 3.0);
		col = vec3(0.3, 0.3, 0.31) * (0.75 + 0.4 * dt.r) * (0.85 + 0.3 * dt.g);
		col *= 1.0 - 0.6 * joints(vec2(along, 0.5), vec2(1.0, 10.0), 0.01);
		rough = mix(0.8, 0.5, wet);
	} else {
		float xm = UV.x * walk_w;
		float y = UV.y;
		vec4 dt = texture(detail, vec2(xm, y) / 5.0);
		vec4 dt2 = texture(detail, vec2(y, xm) / 19.0 + 0.61);
		float stain = mix(dt.g, dt2.g, 0.6);
		float edge = min(xm, walk_w - xm);
		if (edge < 0.32) {
			// Bordsteine: helle Granitreihe mit Stößen alle 1 m
			col = vec3(0.27, 0.27, 0.28) * (0.75 + 0.45 * dt.r);
			col *= 1.0 - 0.6 * joints(vec2(0.5, y), vec2(10.0, 1.0), 0.012);
			rough = mix(0.72, 0.42, wet);
		} else {
			// Betonplatten 1,5 x 1,5 m, jede etwas anders getönt, dazu Flecken und Kaugummi
			vec2 p = vec2(xm - 0.32, y);
			vec2 cell = floor(p / 1.5);
			float tone = 0.85 + 0.3 * hash(cell + 7.7);
			col = vec3(0.155, 0.155, 0.165) * tone * (0.8 + 0.35 * dt.r) * (0.7 + 0.5 * stain);
			float gum = smoothstep(0.86, 0.9, texture(detail, vec2(xm, y) / 1.7).r) * step(0.55, dt2.a);
			col *= 1.0 - 0.45 * gum;
			float j = joints(p, vec2(1.5), 0.012);
			col *= 1.0 - 0.65 * j;
			rough = mix(0.78, 0.45, wet) + (dt.a - 0.5) * 0.12 - j * 0.25 * wet;
		}
		// am Bordstein sammelt sich Dreck
		col *= mix(0.8, 1.0, smoothstep(0.32, 0.8, edge));
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	col *= 1.35;
#endif
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.4;
}
