shader_type spatial;
// Leute (Zuschauer, Fans, Starterin, Wartende): einfache Blockfiguren, die Bewegung macht der Shader.
// UV.x = Körperteil (0 Rumpf, 1 linker Arm, 2 rechter Arm, 3 linkes Bein, 4 rechtes Bein, 5 Kopf)
// UV.y = Farbgruppe (0 Oberteil, 1 Hose, 2 Haut, 3 Haare, 4 Schuhe, 5 Leuchtstab)
// Instanzfarbe = Oberteil. INSTANCE_CUSTOM: r Hautton, g Haare/Hose, b Bewegung/10, a Takt.
// Bewegungen: 0 jubeln, 1 tanzen, 2 warten, 3 winken, 4 klatschen, 5 rennen, 6 telefonieren, 7 Starterin

uniform float energy = 1.0;
// Für einzelne Figuren ohne MultiMesh (Starterin): Werte statt INSTANCE_CUSTOM / Instanzfarbe
uniform vec4 custom = vec4(-1.0);
uniform vec3 shirt = vec3(1.0);
// Starterin: Armhaltung (Bogenmaß, 0 = hängend, 2.9 = senkrecht hoch) und Vorbeugen
uniform float arm = 0.0;
uniform float bow = 0.0;

varying vec3 col;
varying float glow;

mat3 rot_x(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

mat3 rot_z(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0));
}

void vertex() {
	float part = floor(UV.x + 0.5);
	float grp = floor(UV.y + 0.5);
	vec4 cu = custom.x >= 0.0 ? custom : INSTANCE_CUSTOM;
	vec3 top = custom.x >= 0.0 ? shirt : COLOR.rgb;
	float mode = floor(cu.b * 10.0 + 0.5);
	float ph = cu.a * 6.2831;
	float t = TIME;
	// Gelenkwinkel: *_z = seitlich heben (Arme), *_x = vor/zurück (positiv = nach vorn)
	float al_z = 0.0, ar_z = 0.0, al_x = 0.0, ar_x = 0.0, ll_x = 0.0, lr_x = 0.0;
	float lift = 0.0, sway = 0.0, nod = 0.0, lean = 0.0;
	if (mode < 0.5) {
		// jubeln: hüpfen, Arme hoch, Fäuste pumpen
		float s = t * (5.0 + fract(cu.a * 7.0) * 2.0) + ph;
		lift = max(sin(s), 0.0) * 0.22 * energy;
		al_z = -2.5 - 0.35 * sin(s * 2.0) * energy;
		ar_z = 2.5 + 0.35 * sin(s * 2.0 + 1.3) * energy;
	} else if (mode < 1.5) {
		// tanzen: Hüfte wiegen, Arme im Takt
		float s = t * 6.5 + ph;
		sway = sin(s * 0.5) * 0.1;
		lift = abs(sin(s * 0.5)) * 0.07;
		al_z = -1.2 - 1.2 * max(sin(s), 0.0);
		ar_z = 1.2 + 1.2 * max(-sin(s), 0.0);
		al_x = 0.5 + sin(s) * 0.5;
		ar_x = 0.5 - sin(s) * 0.5;
		ll_x = sin(s * 0.5) * 0.3;
		lr_x = -ll_x;
		nod = sin(s) * 0.12;
	} else if (mode < 2.5) {
		// warten: atmen, Gewicht verlagern
		lift = sin(t * 1.3 + ph) * 0.008;
		sway = sin(t * 0.4 + ph) * 0.02;
		al_x = sin(t * 0.9 + ph) * 0.05;
		ar_x = -al_x;
		nod = sin(t * 0.3 + ph * 2.0) * 0.1;
	} else if (mode < 3.5) {
		// winken mit rechts
		ar_z = 2.5 + sin(t * 7.0 + ph) * 0.4;
		lift = abs(sin(t * 3.5 + ph)) * 0.03;
		al_x = 0.1;
	} else if (mode < 4.5) {
		// klatschen
		float s = sin(t * 9.0 + ph);
		al_x = 1.25;
		ar_x = 1.25;
		al_z = 0.25 + 0.2 * s;
		ar_z = -0.25 - 0.2 * s;
		lift = abs(s) * 0.015;
	} else if (mode < 5.5) {
		// rennen
		float s = t * 11.0 + ph;
		al_x = sin(s) * 0.9;
		ar_x = -al_x;
		ll_x = -sin(s) * 0.8;
		lr_x = -ll_x;
		lift = abs(sin(s)) * 0.08;
		lean = 0.15;
	} else if (mode < 6.5) {
		// telefonieren: rechte Hand am Ohr
		ar_x = 0.4;
		ar_z = 2.1;
		nod = sin(t * 0.7 + ph) * 0.08;
		lift = sin(t * 1.3 + ph) * 0.008;
	} else {
		// Starterin: Arme per Uniform, leicht wippen
		al_z = -arm;
		ar_z = arm;
		al_x = bow * 1.2;
		ar_x = bow * 1.2;
		lean = bow * 0.35;
		lift = abs(sin(t * 4.0)) * 0.02 * (1.0 - bow);
		sway = sin(t * 2.0) * 0.03 * (1.0 - bow);
	}
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	mat3 m = mat3(1.0);
	vec3 pivot = vec3(0.0);
	if (part > 0.5 && part < 2.5) {
		bool left = part < 1.5;
		pivot = vec3(left ? -0.25 : 0.25, 1.4, 0.0);
		m = rot_x(left ? al_x : ar_x) * rot_z(left ? al_z : ar_z);
	} else if (part > 2.5 && part < 4.5) {
		bool left = part < 3.5;
		pivot = vec3(left ? -0.09 : 0.09, 0.84, 0.0);
		m = rot_x(left ? ll_x : lr_x);
	} else if (part > 4.5) {
		pivot = vec3(0.0, 1.46, 0.0);
		m = rot_x(nod);
	}
	v = pivot + m * (v - pivot);
	n = m * n;
	// Oberkörper (alles über der Hüfte) neigen und wiegen
	if (part < 2.5 || part > 4.5) {
		mat3 b = rot_x(lean) * rot_z(sway);
		vec3 hip = vec3(0.0, 0.84, 0.0);
		v = hip + b * (v - hip);
		n = b * n;
	}
	v.y += lift;
	VERTEX = v;
	NORMAL = n;

	vec3 skin = mix(vec3(0.93, 0.76, 0.62), vec3(0.32, 0.2, 0.13), cu.r);
	vec3 hair = mix(vec3(0.04, 0.03, 0.025), vec3(0.55, 0.38, 0.16), step(0.72, cu.g));
	if (cu.g > 0.93) {
		hair = vec3(1.0, 0.25, 0.65);
	}
	vec3 pants = fract(cu.g * 7.3) > 0.45 ? vec3(0.08, 0.11, 0.2) : vec3(0.04, 0.04, 0.045);
	vec3 shoes = fract(cu.g * 13.1) > 0.5 ? vec3(0.85) : vec3(0.05);
	glow = 0.0;
	if (grp < 0.5) {
		col = top;
	} else if (grp < 1.5) {
		col = pants;
	} else if (grp < 2.5) {
		col = skin;
	} else if (grp < 3.5) {
		col = hair;
	} else if (grp < 4.5) {
		col = shoes;
	} else {
		col = vec3(1.0, 0.2, 0.5);
		glow = 1.0;
	}
}

void fragment() {
	ALBEDO = col;
	ROUGHNESS = 0.75;
	EMISSION = col * glow * 4.0 + col * 0.06;
}
