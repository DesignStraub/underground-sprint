shader_type spatial;
// Spiegelung einer Laterne im Teich (track_builder.gd _pond, seit 2.25): ein schimmernder Lichtstreifen auf dem Wasser,
// der vom Ufer unter der Laterne zum Betrachter hin läuft und mit den Wellen flackert, wie nachts an jedem Teich.
// Der Streifen wird im Vertex-Shader zur Kamera gedreht; außerhalb des Teichs (Ellipse in Teich-Koordinaten) fällt er weg.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, world_vertex_coords;

uniform vec3 lamp;  // Fußpunkt der Laterne auf Wasserhöhe
uniform mat4 pond_inv;  // Welt -> Teich-Koordinaten
uniform vec3 pond_c;  // Teichmitte (Teich-Koordinaten)
uniform vec2 pond_r;  // Halbachsen x, z
uniform vec3 col : source_color = vec3(1.0, 0.75, 0.45);
uniform float len = 14.0;
uniform float wid = 0.5;

varying vec3 wp;
varying vec2 q;

void vertex() {
	q = UV;
	vec2 d = CAMERA_POSITION_WORLD.xz - lamp.xz;
	d = length(d) > 0.01 ? normalize(d) : vec2(0.0, 1.0);
	vec2 sd = vec2(-d.y, d.x);
	float u = UV.x * 2.0 - 1.0;
	float v = UV.y;
	vec2 p = lamp.xz + d * (v * len) + sd * u * wid * (0.5 + 1.2 * v);
	VERTEX = vec3(p.x, lamp.y, p.y);
	wp = VERTEX;
}

void fragment() {
	vec3 lp = (pond_inv * vec4(wp, 1.0)).xyz;
	vec2 e = (lp.xz - pond_c.xz) / pond_r;
	float inside = 1.0 - smoothstep(0.82, 0.95, dot(e, e));
	if (inside <= 0.0) {
		discard;
	}
	float across = 1.0 - abs(q.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.08, q.y) * pow(1.0 - q.y, 1.5);
	// Wellen: der Streifen zerfällt in wandernde Funken
	float ripple = 0.45 + 0.55 * sin(q.y * 46.0 - TIME * 3.1 + sin(wp.x * 1.7 + TIME) * 2.0);
	ripple *= 0.7 + 0.3 * sin(q.x * 9.0 + TIME * 2.3 + q.y * 13.0);
	ALBEDO = col * pow(across, 1.6) * along * max(ripple, 0.0) * inside * 1.4;
}
