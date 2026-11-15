shader_type spatial;
// Autolack mit Lackart (car_builder.paint_mat): Glanz (Uni mit Klarlack), Metallic (Flitter, zur Seite dunkler),
// Matt (ohne Klarlack, stumpf), Perlmutt (die Farbe kippt zum Rand in einen helleren Schimmerton), Chrom.
// Keine Knoten- oder Instanzdaten: Teile mit diesem Lack lassen sich zu einer Fläche verschmelzen.
// Licht der Laternen und Tunnellampen aus der Lichtkarte der Strecke (wie Straße und Tunnelwand), sonst stünde ein
// Auto im hell erleuchteten Tunnel schwarz da.

#include "res://shaders/street_light.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.8);
uniform float metal : hint_range(0.0, 1.0) = 0.05;
uniform float rough : hint_range(0.0, 1.0) = 0.3;
uniform float coat : hint_range(0.0, 1.0) = 1.0;
uniform float coat_rough : hint_range(0.0, 1.0) = 0.05;
uniform float flakes : hint_range(0.0, 1.0) = 0.0;  // Metallic-Flitter (nur aus der Nähe)
uniform float flop : hint_range(0.0, 1.0) = 0.0;  // Metallic: frontal heller, zur Seite dunkler
uniform vec3 pearl_color : source_color = vec3(1.0);
uniform float pearl : hint_range(0.0, 1.0) = 0.0;  // Perlmutt: Anteil des Schimmertons am Rand
uniform float rim_k : hint_range(0.0, 1.0) = 0.0;
uniform float rim_tint_k : hint_range(0.0, 1.0) = 0.5;

uniform float street_car = 0.0;  // Anteil der Lichtkarte auf dem Lack (0 = Garage, keine Strecke)

// Vinyl mit Motiv (seit 2.33, car_builder.vinyl_params): ein Bild, oben die Flanke (links Bug, rechts Heck, oben die
// Gürtellinie, unten der Schweller), unten die Draufsicht (Haube, Dach, Heckdeckel; oben linke, unten rechte Seite).
// Projiziert in Koordinaten relativ zum Auto (Länge, Breite, Gürtellinie): dasselbe Motiv passt auf jedes Auto.
uniform sampler2D vinyl_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float vinyl_on = 0.0;
uniform vec4 vinyl_box = vec4(-2.2, 4.4, 0.2, 0.8);  // Bug (z), Länge, Unterkante, Gürtellinie (y)
uniform float vinyl_hw = 0.9;  // halbe Breite
uniform float vinyl_mirror = 1.0;  // 1: rechts gespiegelt (Motiv läuft auf beiden Seiten nach hinten), 0: Schrift lesbar
uniform vec4 vinyl_tint = vec4(1.0, 1.0, 1.0, 0.0);  // a = 1: einfarbige Maske in dieser Farbe
uniform float vinyl_metal = 0.1;

varying vec3 obj_pos;
varying vec3 obj_nrm;
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.11, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float edge = 1.0 - ndv;
	vec3 col = base_color;
	// Perlmutt: frontal die Grundfarbe, zum Rand hin der Schimmerton
	col = mix(col, pearl_color, pearl * smoothstep(0.3, 1.0, edge));
	// Metallic-Flop: die Plättchen werfen frontal Licht zurück, flach angesehen wirkt der Lack dunkler
	col *= mix(1.0, mix(1.12, 0.6, smoothstep(0.1, 0.9, edge)), flop);
	float r = rough;
	float m = metal;
	if (flakes > 0.0) {
		// Flitter: einzelne Zellen (gut 3 mm) glänzen schärfer und heller, sichtbar in Glanzlichtern. Blendet mit
		// der Entfernung aus (sonst flimmert es auf Fahrabstand).
		vec3 cell = floor(obj_pos * 400.0);
		float h = hash3(cell);
		float fade = flakes * (1.0 - smoothstep(1.5, 4.5, length(VERTEX)));
		float s = smoothstep(0.86, 0.98, h) * fade;
		r = mix(r, 0.12, s);
		m = mix(m, 1.0, s * 0.5);
		col *= 1.0 + s * 0.25;
	}
	if (vinyl_on > 0.5) {
		// beide Projektionen immer abtasten (keine Ableitungen in Verzweigungen), mit Masken mischen
		vec3 n = normalize(obj_nrm);
		float u = (obj_pos.z - vinyl_box.x) / vinyl_box.y;
		float sv = (vinyl_box.w - obj_pos.y) / (vinyl_box.w - vinyl_box.z);
		float su = (obj_pos.x > 0.0 && vinyl_mirror < 0.5) ? 1.0 - u : u;
		float tv = obj_pos.x / vinyl_hw * 0.5 + 0.5;
		vec4 a_side = texture(vinyl_tex, vec2(clamp(su, 0.0, 1.0), 0.004 + clamp(sv, 0.0, 1.0) * 0.492));
		vec4 a_top = texture(vinyl_tex, vec2(clamp(u, 0.0, 1.0), 0.504 + clamp(tv, 0.0, 1.0) * 0.492));
		float in_s = step(0.0, sv) * step(sv, 1.0) * step(0.0, su) * step(su, 1.0);
		float in_t = step(0.0, tv) * step(tv, 1.0) * step(0.0, u) * step(u, 1.0);
		float wt = smoothstep(0.5, 0.72, n.y) * in_t;
		float ws = (1.0 - smoothstep(0.5, 0.72, n.y)) * (1.0 - smoothstep(0.8, 0.96, abs(n.z))) * in_s;
		float as = a_side.a * ws;
		float at = a_top.a * wt;
		float va = clamp(as + at, 0.0, 1.0);
		if (va > 0.002) {
			vec3 vc = (a_side.rgb * as + a_top.rgb * at) / max(as + at, 1e-4);
			vc = mix(vc, vinyl_tint.rgb * vc, vinyl_tint.a);
			col = mix(col, vc, va);
			r = mix(r, 0.32, va);
			m = mix(m, vinyl_metal, va);
		}
	}
	ALBEDO = col;
	if (street_car > 0.0) {
		// Lichtkreis unter der Lampe (ohne die Grundhelligkeit, die gibt schon das Umgebungslicht): Dach und Haube
		// voll, Flanken weniger. Metallic wirft etwas weniger diffus zurück.
		vec3 sl = texture(street_light, (w_pos.xz - street_rect.xy) * street_rect.zw).rgb * street_gain;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		sl *= 2.0;
#endif
		float up = clamp(w_nrm.y * 0.5 + 0.5, 0.0, 1.0);
		EMISSION = min(col, vec3(0.5)) * sl * mix(0.12, 0.6, up) * (1.0 - 0.3 * m) * street_car;
	}
	METALLIC = m;
	ROUGHNESS = r;
	SPECULAR = 0.5;
	CLEARCOAT = coat;
	CLEARCOAT_ROUGHNESS = coat_rough;
	RIM = rim_k;
	RIM_TINT = rim_tint_k;
}
