shader_type canvas_item;
// Minimap: Straßen sind einmal in Weltkoordinaten (x, z) gezeichnet und werden je Bild nur verschoben und gedreht.
// Alles außerhalb des Radarkreises (Mitte = Spieler, Radius in Metern) wird ausgeblendet, am Rand weich.

uniform vec2 center = vec2(0.0);
uniform float radius = 150.0;
uniform float feather = 4.0;

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	float d = distance(world_pos, center);
	if (d > radius) {
		discard;
	}
	COLOR.a *= 1.0 - smoothstep(radius - feather, radius, d);
}
