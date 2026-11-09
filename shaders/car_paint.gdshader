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

varying vec3 obj_pos;
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	obj_pos = VERTEX;
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
