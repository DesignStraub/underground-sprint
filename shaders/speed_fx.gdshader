shader_type canvas_item;
// Tempogefühl wie in NFS Underground: Bewegungsunschärfe statt gezeichneter Tempolinien. Die Umgebung verwischt zum
// Bildrand hin entlang der Fahrtrichtung (Zoom-Unschärfe vom Fluchtpunkt aus), die Bildmitte mit dem eigenen Auto
// bleibt scharf. Beim Einlenken verwischt das Bild zusätzlich seitlich. Nitro: stärker, helle Lichter (Laternen,
// Neon, Rücklichter) ziehen lange Streifen, Farbsäume am Rand und ein flackernder blauer Schein; beim Zünden läuft
// eine Druckwelle von der Mitte nach außen über das Bild. Alles abschaltbar (Einstellungen > Kamera & Tempo);
// aus = race.gd blendet das ganze Rechteck aus, dann kostet es nichts.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float blur = 0.0;  // Länge der Zoom-Unschärfe als Anteil des Abstands zum Fluchtpunkt
uniform float swing = 0.0;  // seitliches Verwischen (Bildanteil, Vorzeichen = Richtung)
uniform float nitro = 0.0;  // 0..1
uniform float kick = 0.0;  // 0..1 Zündstoß (klingt in gut einer halben Sekunde ab)
uniform vec2 focus = vec2(0.5, 0.46);  // Fluchtpunkt (etwa der Horizont vor dem Auto)

const int TAPS = 10;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	float r = length(d * vec2(1.78, 1.0));
	// scharfe Mitte (Auto, Straße direkt davor), nach außen immer stärker
	float m = smoothstep(0.16, 0.6, r);
	// Druckwelle beim Zünden: ein Ring läuft nach außen und verzerrt das Bild dort kurz
	float ring = 0.0;
	if (kick > 0.001) {
		float rr = mix(1.25, 0.12, kick);
		ring = exp(-pow((r - rr) * 9.0, 2.0)) * kick;
		uv -= d * ring * 0.05;
	}
	float amt = blur * m * (1.0 + 1.2 * kick);
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
			vec2 p = focus + (uv - focus) * (1.0 - amt * t) - vec2(sw * t, 0.0);
			float w = 1.0 - 0.6 * t;
			vec3 c = texture(screen_tex, p).rgb;
			// Nitro: helle Punkte zählen mehr -> sie ziehen Lichtstreifen
			float hl = 1.0 + nitro * 5.0 * max(dot(c, vec3(0.3, 0.5, 0.2)) - 0.55, 0.0);
			acc += c * w * hl;
			wsum += w * mix(1.0, hl, 0.6);
		}
		col = acc / wsum;
	}
	if (nitro > 0.001) {
		// Farbsäume am Rand, blauer Schein, der wie die Flamme flackert, und ein dunklerer Rand (Tunnelblick)
		float e = smoothstep(0.3, 1.0, r) * nitro;
		vec2 off = d * (0.011 + 0.02 * kick) * e;
		col.r = mix(col.r, texture(screen_tex, uv + off).r, e * 0.6);
		col.b = mix(col.b, texture(screen_tex, uv - off).b, e * 0.6);
		float flick = 0.85 + 0.15 * sin(TIME * 37.0) * sin(TIME * 23.0 + 1.0);
		col *= 1.0 - 0.28 * nitro * smoothstep(0.55, 1.2, r);
		col = mix(col, vec3(0.12, 0.35, 1.0), smoothstep(0.5, 1.15, r) * nitro * 0.42 * flick);
	}
	// Druckwelle hell aufleuchten lassen
	col += vec3(0.45, 0.65, 1.0) * ring * 0.35;
	COLOR = vec4(col, 1.0);
}
