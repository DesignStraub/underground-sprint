shader_type canvas_item;
// Tempogefühl wie in NFS Underground: Bewegungsunschärfe statt gezeichneter Tempolinien. Die Umgebung verwischt zum
// Bildrand hin entlang der Fahrtrichtung (Zoom-Unschärfe vom Fluchtpunkt aus), die Bildmitte mit dem eigenen Auto
// bleibt scharf. Beim Einlenken verwischt das Bild zusätzlich seitlich. Nitro: stärker, dazu ein blauer Schimmer
// und leichte Farbsäume am Rand. Alles abschaltbar (Einstellungen > Kamera & Tempo); aus = race.gd blendet das
// ganze Rechteck aus, dann kostet es nichts.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur = 0.0;  // Länge der Zoom-Unschärfe als Anteil des Abstands zum Fluchtpunkt
uniform float swing = 0.0;  // seitliches Verwischen (Bildanteil, Vorzeichen = Richtung)
uniform float nitro = 0.0;  // 0..1
uniform vec2 focus = vec2(0.5, 0.46);  // Fluchtpunkt (etwa der Horizont vor dem Auto)

const int TAPS = 10;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	float r = length(d * vec2(1.78, 1.0));
	// scharfe Mitte (Auto, Straße direkt davor), nach außen immer stärker
	float m = smoothstep(0.16, 0.6, r);
	float amt = blur * m;
	float sw = swing * smoothstep(0.08, 0.42, abs(d.x));
	vec3 col;
	if (amt + abs(sw) < 0.0004) {
		col = texture(screen_tex, uv).rgb;
	} else {
		// versetzte Proben je Bildpunkt (Rauschen statt sichtbarer Doppelbilder), Schweif läuft weich aus
		float j = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < TAPS; i++) {
			float t = (float(i) + j) / float(TAPS);
			vec2 p = focus + d * (1.0 - amt * t) - vec2(sw * t, 0.0);
			float w = 1.0 - 0.6 * t;
			acc += texture(screen_tex, p).rgb * w;
			wsum += w;
		}
		col = acc / wsum;
	}
	if (nitro > 0.001) {
		// Farbsäume am Rand und blauer Schimmer
		float e = smoothstep(0.35, 1.0, r) * nitro;
		vec2 off = d * 0.012 * e;
		col.r = mix(col.r, texture(screen_tex, uv + off).r, e * 0.6);
		col.b = mix(col.b, texture(screen_tex, uv - off).b, e * 0.6);
		col = mix(col, vec3(0.1, 0.35, 1.0), smoothstep(0.5, 1.1, r) * nitro * 0.35);
	}
	COLOR = vec4(col, 1.0);
}
