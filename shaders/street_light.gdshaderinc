// Gebackenes Laternenlicht (track_builder._bake_street_light): die Lichtkreise aller Laternen und Tunnellampen als
// Bild über der Strecke (x/z in Metern). Wirkt wie Licht auf der Oberfläche (Albedo mal Lichtfarbe), unabhängig
// davon, wie viele echte Lampen der Renderer je Objekt berücksichtigt; im Browser sind das nur wenige, und lange
// Straßenstücke blieben dort stellenweise schwarz.
uniform sampler2D street_light : hint_default_black, filter_linear, repeat_disable;
uniform vec4 street_rect = vec4(0.0);  // x0, z0, 1/Breite, 1/Tiefe (Meter)
uniform float street_gain = 0.0;
uniform vec3 street_floor = vec3(0.0);  // Grundhelligkeit überall auf der Straße (Streulicht der Stadt)

vec3 street_light_at(vec3 wp) {
	vec3 l = max(texture(street_light, (wp.xz - street_rect.xy) * street_rect.zw).rgb, street_floor) * street_gain;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Browser: ohne Bildschirm-Spiegelungen bleibt dunkler Asphalt sonst auch im Lichtkreis fast schwarz
	l *= 2.2;
#endif
	return l;
}

// Licht für eine Oberfläche mit Albedo col: helle Flächen (Markierungen, Kacheln) nur begrenzt, sonst gleißen sie
vec3 street_lit(vec3 col, vec3 wp) {
	return min(col, vec3(0.25)) * street_light_at(wp);
}
