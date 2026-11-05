shader_type spatial;
// Asphalt wie in NFS Underground: dunkler, körniger Belag mit Splitt, Flecken, Rissen und Teerfugen, immer etwas
// feucht glänzend. In den Fahrspuren dunkler und glatter gefahren, dazwischen Öltropfen, am Rand der Rinnstein mit
// Gullys. Abgefahrene Markierungen, Gullydeckel, Flickstellen, Pfützen, auf Wunsch Kopfsteinpflaster.
// UV.x = quer (0..1), UV.y = Meter in Fahrtrichtung. Detail-Texturen (8 x 8 m) aus tools/gen_ground_tex.gd.

uniform float lanes = 4.0;  // 4 Hauptstraße, 2 Seitenstraße, 0 ohne Markierung
uniform float road_w = 18.0;
uniform float cobble = 0.0;
uniform float wet = 0.0;  // Stimmung: 0 trocken bis 1 Regen (mehr und größere Pfützen, glänzender Asphalt)
uniform sampler2D detail : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
#include "res://shaders/street_light.gdshaderinc"

varying vec3 w_pos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Linie mit halber Breite w um c, Kanten geglättet (kein Flimmern in der Ferne)
float band(float x, float c, float w) {
	float aa = fwidth(x) * 0.8;
	return 1.0 - smoothstep(w - aa, w + aa, abs(x - c));
}

// Strichlänge on von period, geglättet
float dash(float y, float period, float on) {
	float t = fract(y / period) * period;
	float aa = fwidth(y) * 0.8;
	return smoothstep(-aa, aa, t) * (1.0 - smoothstep(on - aa, on + aa, t));
}

// Normal-Map ohne Tangenten im Mesh: Basis aus den Bildschirm-Ableitungen von Position und UV
vec3 perturb(vec3 n, vec3 pos, vec2 uv, vec3 nm) {
	vec3 dp1 = dFdx(pos);
	vec3 dp2 = dFdy(pos);
	vec2 du1 = dFdx(uv);
	vec2 du2 = dFdy(uv);
	vec3 dp2p = cross(dp2, n);
	vec3 dp1p = cross(n, dp1);
	vec3 t = dp2p * du1.x + dp1p * du2.x;
	vec3 b = dp2p * du1.y + dp1p * du2.y;
	float inv = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
	return normalize(mat3(t * inv, b * inv, n) * nm);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float xm = UV.x * road_w;  // quer in Metern
	float y = UV.y;
	vec2 tuv = vec2(xm, y) / 8.0;
	vec4 dt = texture(detail, tuv);
	// zweite, größere und gedrehte Lage: keine sichtbare Kachelung in den Flecken
	vec4 dt2 = texture(detail, vec2(y, xm) / 29.0 + 0.37);
	float grain = dt.r;
	float blot = mix(dt.g, dt2.g, 0.6);
	float tar = dt.b * (1.0 - cobble);

	// Fahrspuren: zwei glattgefahrene Radspuren je Spur, in der Mitte Öltropfen
	float nl = lanes > 3.0 ? 4.0 : (lanes > 1.0 ? 2.0 : 1.0);
	float lw = road_w / nl;
	float lc = mod(xm, lw) - lw * 0.5;
	float wheel = (1.0 - smoothstep(0.18, 0.5, abs(abs(lc) - 0.85))) * (0.75 + 0.25 * noise(vec2(xm * 0.7, y * 0.05)));
	float oil = (1.0 - smoothstep(0.08, 0.4, abs(lc))) * smoothstep(0.35, 0.75, noise(vec2(xm * 2.0, y * 0.35)));
	// Rinnstein: die letzten gut 50 cm an der Bordsteinkante, dunkler und nasser
	float edge = min(xm, road_w - xm);
	float gutter = 1.0 - smoothstep(0.25, 0.65, edge);

	// Markierungen
	float white = 0.0;
	float yellow = 0.0;
	if (lanes > 3.0) {
		white = band(xm, 0.03 * road_w, 0.12) + band(xm, 0.97 * road_w, 0.12);
		white += (band(xm, 0.25 * road_w, 0.12) + band(xm, 0.75 * road_w, 0.12)) * dash(y, 9.0, 4.0);
		yellow = band(xm, 0.488 * road_w, 0.085) + band(xm, 0.512 * road_w, 0.085);
	} else if (lanes > 1.0) {
		white = band(xm, 0.05 * road_w, 0.12) + band(xm, 0.95 * road_w, 0.12);
		white += band(xm, 0.5 * road_w, 0.12) * dash(y, 6.0, 3.0);
	}
	// abgefahren: der Splitt schaut durch, in den Radspuren mehr
	float worn = smoothstep(0.25, 0.65, grain * 0.6 + dt2.a * 0.5 + 0.15 - wheel * 0.25);
	white = clamp(white, 0.0, 1.0) * mix(0.35, 1.0, worn);
	yellow = clamp(yellow, 0.0, 1.0) * mix(0.35, 1.0, worn);
	float paint = clamp(white + yellow, 0.0, 1.0);

	// Pfützen nur hier und da: seltene, klar umrissene Flecken, bevorzugt im Rinnstein und in den Radspuren
	float pn = noise(vec2(xm * 0.33, y * 0.085)) + gutter * 0.12 + wheel * 0.05;
	float puddle = smoothstep(0.69 - wet * 0.2, 0.75 - wet * 0.18, pn) * step(0.45 - wet * 0.45, noise(vec2(y * 0.013, 7.3)));

	vec3 col = vec3(0.07, 0.07, 0.08) * (0.5 + 0.95 * grain) * (0.78 + 0.44 * blot);
	col *= 1.0 - 0.55 * tar;  // Teerfugen und Risse
	col *= 1.0 - 0.28 * wheel - 0.15 * oil - 0.25 * gutter;
	float rough_add = 0.0;
	// Flickstellen: neuer, dunklerer Belag mit Teerrand
	vec2 pc = vec2(floor(y / 14.0), floor(xm / 4.5));
	float pf = fract(y / 14.0);
	float px = fract(xm / 4.5);
	float patch = step(0.82, hash(pc + 3.1)) * step(0.1, pf) * step(pf, 0.6);
	float rim = patch * (1.0 - smoothstep(0.0, 0.07, min(min(pf - 0.1, 0.6 - pf) * 14.0, min(px, 1.0 - px) * 4.5)));
	col *= mix(1.0, 0.72, patch) * (1.0 - 0.5 * rim);
	rough_add -= 0.08 * patch;
	// Gullydeckel in der Fahrbahn
	float mc = floor(y / 31.0);
	vec2 mpos = vec2(2.0 + hash(vec2(mc, 1.0)) * (road_w - 4.0), mc * 31.0 + 10.0);
	float md = length(vec2(xm, y) - mpos);
	float manhole = 1.0 - smoothstep(0.43, 0.46, md);
	float ring = manhole * (step(0.36, md) + step(0.5, fract((xm + y) * 4.0)) * 0.4);
	col = mix(col, vec3(0.09, 0.085, 0.08) * (0.8 + ring), manhole);
	// Gully-Roste im Rinnstein, abwechselnd links und rechts
	float gc = floor(y / 24.0);
	float gx = mod(gc, 2.0) < 1.0 ? xm : road_w - xm;
	float gy = y - gc * 24.0 - 5.0;
	float grate = step(0.06, gx) * step(gx, 0.5) * step(0.0, gy) * step(gy, 0.9) * (1.0 - cobble);
	float slots = step(0.45, fract(gy * 9.0));
	col = mix(col, vec3(0.05, 0.05, 0.05) * (0.4 + slots), grate);
	if (cobble > 0.5) {
		// Kopfsteinpflaster als Bogenpflaster: runde, gewölbte Granitsteine in geschwungenen Reihen, dunkle,
		// verschmutzte Fugen. Bewusst anders als die Ziegelwände (Rechtecke im Verband mit hellem Mörtel), sonst
		// sah der Boden im Dunkeln aus wie die Hauswand dahinter.
		float aa = fwidth(xm) + fwidth(y);
		float arcw = 1.8;
		float ax = fract(xm / arcw) - 0.5;
		float yy = y + ax * ax * 1.6;  // Bögen quer über die Fahrbahn
		float rowh = 0.13;
		float row = floor(yy / rowh);
		float fy = fract(yy / rowh);
		float sw = 0.11 + 0.05 * hash(vec2(row, 3.0));
		float rx = xm / sw + hash(vec2(row, 9.0)) * 7.0;
		float cell = floor(rx);
		float fx = fract(rx);
		// jeder Stein ein Rechteck mit stark und unterschiedlich gerundeten Ecken (Abstand zum Rand, < 0 innen)
		float jit = hash(vec2(cell, row) + 1.7);
		vec2 q = vec2((fx - 0.5) * sw, (fy - 0.5) * rowh);
		vec2 hs = vec2(sw, rowh) * 0.5 - 0.011 - 0.006 * jit;
		float rr = min(hs.x, hs.y) * (0.5 + 0.35 * jit);
		vec2 dq = abs(q) - (hs - rr);
		float sd = length(max(dq, 0.0)) + min(max(dq.x, dq.y), 0.0) - rr;
		float grout = smoothstep(-0.004 - aa, 0.002, sd);
		float dome = smoothstep(0.0, 0.04, -sd);
		float tone = 0.55 + 0.75 * hash(vec2(cell, row));
		vec3 granite = mix(vec3(0.07, 0.075, 0.085), vec3(0.09, 0.08, 0.068), step(0.7, hash(vec2(row, cell) + 4.2)));
		vec3 stone = granite * tone * (0.45 + 0.55 * dome) * (0.8 + 0.4 * grain);
		vec3 cb = mix(stone, vec3(0.012), grout);
		// in der Ferne kein Flimmern: das feine Muster geht in den mittleren Farbton über
		float far = smoothstep(0.025, 0.08, aa);
		col = mix(cb, vec3(0.055, 0.056, 0.06) * (0.75 + 0.5 * grain), far);
		grout *= 1.0 - far;
		rough_add -= 0.08 * dome * (1.0 - far);  // blank gefahrene Steinkuppen glänzen
		col *= 1.0 - 0.15 * wheel;
		puddle *= 0.6;
		rough_add += 0.05 * grout;
	}
	col = mix(col, vec3(0.8, 0.8, 0.78), white);
	col = mix(col, vec3(0.85, 0.6, 0.1), yellow);
	col *= mix(1.0, 0.5, puddle);

	// Glanz: auch trocken leicht feucht wie in NFSU, nass deutlich; glatt in den Radspuren, Teer glänzt
	float rough = mix(0.42, 0.2, wet) + (dt.a - 0.5) * 0.16 - 0.14 * wheel - 0.1 * oil - 0.12 * gutter + rough_add;
	rough = mix(rough, 0.26, tar * 0.8);
	rough = mix(rough, 0.48, paint);
	float wet_rough = 0.04;
	// Relief: trocken bricht es die Lichtreflexe in Körnung auf, nass füllt Wasser die Poren und die Spiegelungen
	// werden lange, glatte Streifen wie in NFSU
	float bump = mix(0.5, 0.08, wet) * (1.0 - paint * 0.6) * (1.0 - manhole) * (1.0 - wheel * 0.4);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Browser: keine Bildschirm-Spiegelungen, also etwas heller und breitere Lichtreflexe der Laternen
	col *= 1.5;
	wet_rough = 0.2;
	rough = max(rough, 0.24);
#endif
	rough = mix(rough, wet_rough, puddle);
	bump *= 1.0 - puddle;
	vec3 nm = texture(detail_n, tuv).xyz * 2.0 - 1.0;
	nm.xy *= bump;
	nm.z = sqrt(max(1.0 - dot(nm.xy, nm.xy), 0.0));
	NORMAL = perturb(NORMAL, VERTEX, tuv, nm);
	ALBEDO = col;
	EMISSION = street_lit(col, w_pos);
	ROUGHNESS = clamp(rough * (1.0 - manhole * 0.2), 0.02, 1.0);
	METALLIC = max(manhole * 0.3, grate * 0.5);
	SPECULAR = mix(0.45, 0.6, puddle);
}
