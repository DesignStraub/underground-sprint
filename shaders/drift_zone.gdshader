shader_type spatial;
// Drift-Bonuszone (race.gd _build_drift_zones): Außenspur am Kurvenrand, aufgemalt wie eine Fahrbahnmarkierung:
// durchgezogene weiße Linie innen, dazu zur Bande hin schwache schräge Schraffur (Sperrfläche). Kein Leuchten mehr
// (bis 2.23 ein orange leuchtendes Band mit laufenden Pfeilen, zu grell). UV.x quer (0 innen, 1 an der Bande),
// UV.y Meter entlang; COLOR.a blendet an den Enden aus. active: Spieler driftet gerade in der Zone (Farbe wird
// etwas heller und leicht warm, wie angestrahlt).
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float active = 0.0;

void fragment() {
	// Linie innen: 14 cm breit (Streifen ist 2,4 m breit)
	float line = smoothstep(0.0, 0.01, UV.x) * (1.0 - smoothstep(0.05, 0.06, UV.x));
	// schräge Schraffur alle 1,6 m, gut 25 cm breit, nur zwischen Linie und Bande
	float h = fract((UV.y + UV.x * 2.4) / 1.6);
	float hatch = smoothstep(0.0, 0.02, h) * (1.0 - smoothstep(0.15, 0.17, h)) * step(0.08, UV.x) * (1.0 - smoothstep(0.93, 0.97, UV.x));
	// abgefahrene Farbe: nicht ganz deckend, mit leichtem Rauschen entlang
	float wear = 0.82 + 0.18 * sin(UV.y * 3.1 + sin(UV.y * 0.7) * 2.0);
	float a = max(line * 0.85, hatch * 0.32) * wear * COLOR.a;
	vec3 paint = mix(vec3(0.86, 0.86, 0.82), vec3(1.0, 0.93, 0.78), active);
	ALBEDO = paint;
	ROUGHNESS = 0.75;
	EMISSION = paint * a * 0.25 * active;
	ALPHA = a;
}
