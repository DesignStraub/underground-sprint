shader_type canvas_item;
// Tempogefühl wie in NFS Underground: Zoom-Unschärfe vom Fluchtpunkt aus, zum Bildrand immer stärker, die Bildmitte
// mit dem eigenen Auto bleibt scharf. Seit 2.26 näher am Vorbild: setzt schon ab gut 90 km/h ein und wird bis zur
// Höchstgeschwindigkeit deutlich, helle Lichter (Laternen, Rücklichter, Leuchtreklamen) ziehen dabei Lichtspuren,
// und der Bildrand dunkelt mit dem Tempo leicht ab (Tunnelblick). Beim Einlenken verwischt das Bild zusätzlich
// seitlich. Nitro: stärker, dazu ein blauer Schimmer und leichte Farbsäume am Rand. Alles abschaltbar
// (Einstellungen > Kamera & Tempo); aus = race.gd blendet das ganze Rechteck aus, dann kostet es nichts.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur = 0.0;  // Länge der Zoom-Unschärfe als Anteil des Abstands zum Fluchtpunkt
uniform float swing = 0.0;  // seitliches Verwischen (Bildanteil, Vorzeichen = Richtung)
uniform float nitro = 0.0;  // 0..1
uniform float speed = 0.0;  // 0..1 (Tunnelblick, Lichtspuren)
uniform vec2 focus = vec2(0.5, 0.46);  // Fluchtpunkt (etwa der Horizont vor dem Auto)

const int TAPS = 10;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	float r = length(d * vec2(1.78, 1.0));
	// scharfe Mitte (Auto, Straße direkt davor), nach außen immer stärker
	float m = smoothstep(0.15, 0.62, r);
	float amt = blur * m;
	float sw = swing * smoothstep(0.08, 0.42, abs(d.x));
	vec3 col;
	if (amt + abs(sw) < 0.0004) {
		col = texture(screen_tex, uv).rgb;
	} else {
		// versetzte Proben je Bildpunkt (Rauschen statt sichtbarer Doppelbilder), Schweif läuft weich aus; helle
		// Proben zählen mehr: Lichter ziehen Spuren wie auf einem Foto mit langer Belichtung
		float j = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = 0; i < TAPS; i++) {
			float t = (float(i) + j) / float(TAPS);
			vec2 p = focus + d * (1.0 - amt * t) - vec2(sw * t, 0.0);
			vec3 c = texture(screen_tex, p).rgb;
			float lum = dot(c, vec3(0.3, 0.55, 0.15));
			float w = (1.0 - 0.6 * t) * (1.0 + 2.2 * speed * smoothstep(0.55, 1.0, lum));
			acc += c * w;
			wsum += 1.0 - 0.6 * t;
		}
		col = acc / (wsum * (1.0 + 0.55 * speed * 0.6));
	}
	// Tunnelblick: Rand leicht dunkler, je schneller
	col *= 1.0 - 0.22 * speed * smoothstep(0.45, 1.15, r);
	if (nitro > 0.001) {
		// Farbsäume am Rand und blauer Schimmer
		float e = smoothstep(0.35, 1.0, r) * nitro;
		vec2 off = d * 0.012 * e;
		col.r = mix(col.r, texture(screen_tex, uv + off).r, e * 0.6);
		col.b = mix(col.b, texture(screen_tex, uv - off).b, e * 0.6);
		col = mix(col, vec3(0.1, 0.35, 1.0), smoothstep(0.5, 1.1, r) * nitro * 0.3);
	}
	COLOR = vec4(col, 1.0);
}
