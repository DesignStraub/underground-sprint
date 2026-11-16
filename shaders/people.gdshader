shader_type spatial;
// Leute (Zuschauer, Fans, Starterin, Wartende), Modelle aus scripts/people.gd. Der Körper ist eine Haut aus
// Querschnitten; der Shader biegt sie an den Gelenken (Becken -> Rumpf -> Kopf / Oberarm -> Unterarm, Becken ->
// Oberschenkel -> Unterschenkel -> Fuß). Ecken nahe am Gelenk drehen nur anteilig mit (UV2.y), so knicken Ellbogen,
// Knie und Schultern weich statt als Kugelgelenk. Dazu formt er die Statur und malt Kleidung und Gesicht.
// UV.x = Körperteil (0 Rumpf, 1/2 Oberarm l/r, 3/4 Oberschenkel l/r, 5 Kopf mit Hals, 6/7 Unterarm mit Hand l/r,
//        8/9 Unterschenkel l/r, 10 Becken, 11/12 Fuß l/r)
// UV.y = Farbgruppe (0 Rumpf: oben Oberteil, unten Hose; 1 Bein: Hose oder Haut; 2 Haut; 3 Haare; 4 Schuh mit Sohle;
//        5 Leuchtstab; 6 Arm: Ärmel oder Haut; 7 Jacke; 8 Kappe/Mütze/Haargummi; 9 Handy; 10 Bildschirm; 11 Rock;
//        12 Tasche/Rucksack; 13 Kapuze)
// UV2.x = Variante (0 immer, 1 Haare oben, 2 lange Haare, 3 Zopf, 4 Dutt, 5 Kappe, 6 Mütze, 7 Kapuze, 8 Rock,
//        9 Jacke, 10 Leuchtstäbe, 11 Handy, 12 Haare im Nacken, 13 Rucksack, 14 Umhängetasche). Nicht gewählte Teile
//        fallen auf einen Punkt zusammen. UV2.y = Anteil der eigenen Gelenkdrehung (1 ganz, 0 wie das Elternteil).
// CUSTOM0.xy = vorab gerechnete Formdaten für die Statur (people.gd, _shape_all)
// Instanzfarbe = Oberteil. INSTANCE_CUSTOM: r Hautton, g Haare/Hose, b Bewegung/10, a Takt; daraus werden außerdem
// Geschlecht, Statur, Frisur, Kopfbedeckung, Kleidung, Brille, Bart und Zubehör gewürfelt.
// Bewegungen: 0 jubeln, 1 tanzen, 2 warten, 3 winken, 4 klatschen, 5 rennen, 6 Handy, 7 Starterin

uniform float energy = 1.0;
// Für einzelne Figuren ohne MultiMesh (Starterin, Fans): Werte statt INSTANCE_CUSTOM / Instanzfarbe. custom als Vector4
// setzen, nicht als Color (die rechnet Godot von sRGB in linear um).
uniform vec4 custom = vec4(-1.0);
uniform vec3 shirt = vec3(1.0);
// Starterin: Armhaltung (Bogenmaß, 0 = hängend, 2.9 = senkrecht hoch) und Vorbeugen
uniform float arm = 0.0;
uniform float bow = 0.0;

// Gelenke in der Ruhelage (Mann, 1,745 m; rechte Seite, links gespiegelt), passend zu people.gd
const vec3 J_PELVIS = vec3(0.0, 0.92, 0.0);
const vec3 J_WAIST = vec3(0.0, 1.03, 0.008);
const vec3 J_NECK = vec3(0.0, 1.555, 0.014);
const vec3 J_SHOULDER = vec3(0.178, 1.415, 0.005);
const vec3 J_ELBOW = vec3(0.205, 1.105, 0.012);
const vec3 J_HIP = vec3(0.09, 0.9, 0.0);
const vec3 J_KNEE = vec3(0.096, 0.495, -0.004);
const vec3 J_ANKLE = vec3(0.1, 0.085, 0.025);

// Wenige Varyings (13 Werte je Ecke): jede Ecke schreibt sie, bei Tausenden Figuren kostet das mehr als die Rechnung
varying vec3 rest;  // Lage im Modell vor der Bewegung (für Gesicht, Säume und Muster)
varying vec3 col;  // Farbe der Gruppe
varying vec3 col2;  // zweite Farbe: Haut unter Ärmel und Hosenbein, Hose unter dem Oberteil, Sohle, Brauen/Bart
// x: Farbgruppe + 16 * Oberteil-Art, y: Trennhöhe der Gruppe (Saum, Ärmelende, Hosenende), z: Merkmale (1 Brille,
// 2 Bart, 4 Lächeln, 8 Strumpfhose, 16 * Aufdruck 1-3), w: Hautton
varying flat vec4 meta;

// Drehungen als fertige Matrix (je Ecke gerechnet, darum ohne Matrix-Produkte):
// rx = vor/zurück (positiv: hängendes Glied nach vorn), ry = um die Hochachse, rz = seitlich
mat3 rx(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c));
}

// rx(a) * rz(b) * ry(c): Schulter (vor heben, seitlich heben, nach innen drehen)
mat3 rot_xzy(float a, float b, float c) {
	float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b), cc = cos(c), sc = sin(c);
	return mat3(vec3(cb * cc, ca * sb * cc + sa * sc, sa * sb * cc - ca * sc), vec3(-sb, ca * cb, sa * cb),
		vec3(cb * sc, ca * sb * sc - sa * cc, sa * sb * sc + ca * cc));
}

// rx(a) * rz(b): Hüfte
mat3 rot_xz(float a, float b) {
	float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
	return mat3(vec3(cb, ca * sb, sa * sb), vec3(-sb, ca * cb, sa * cb), vec3(0.0, -sa, ca));
}

// rx(a) * ry(b): Ellbogen (beugen, Unterarm drehen)
mat3 rot_xy(float a, float b) {
	float ca = cos(a), sa = sin(a), cb = cos(b), sb = sin(b);
	return mat3(vec3(cb, sa * sb, -ca * sb), vec3(0.0, ca, sa), vec3(sb, -sa * cb, ca * cb));
}

// sin und cos kleiner Winkel (|a| < 0,8) als Polynom: billiger als sin()/cos(), genau auf 0,0004
vec2 sc_small(float a) {
	float a2 = a * a;
	return vec2(a * (1.0 - a2 * (0.16666667 - a2 * 0.00833333)), 1.0 - a2 * (0.5 - a2 * 0.04166667));
}

// ry(a) * rx(b) * rz(c) für kleine Winkel: Wirbelsäule und Kopf (drehen, nicken, neigen)
mat3 rot_yxz_small(float a, float b, float c) {
	vec2 qa = sc_small(a), qb = sc_small(b), qc = sc_small(c);
	float sa = qa.x, ca = qa.y, sb = qb.x, cb = qb.y, sc = qc.x, cc = qc.y;
	return mat3(vec3(ca * cc + sa * sb * sc, cb * sc, ca * sb * sc - sa * cc), vec3(sa * sb * cc - ca * sc, cb * cc, sa * sc + ca * sb * cc),
		vec3(sa * cb, -sb, ca * cb));
}

// ry(a) * rz(b) für kleine Winkel: Becken
mat3 rot_yz_small(float a, float b) {
	vec2 qa = sc_small(a), qb = sc_small(b);
	return mat3(vec3(qa.y * qb.y, qb.x, -qa.x * qb.y), vec3(-qa.y * qb.x, qb.y, qa.x * qb.x), vec3(qa.x, 0.0, qa.y));
}

// Gewicht auf ein Bein (w > 0: rechts): Becken zur Seite und gekippt, Schultern dagegen
void stand_body(float w, inout float shift, inout float ptilt, inout vec3 sp) {
	shift += 0.03 * w;
	ptilt += 0.05 * w;
	sp.y += 0.085 * w;
}

// dazu das Bein dieser Seite: die Hüfte gleicht aus, damit der Fuß stehen bleibt; das Spielbein ist locker gebeugt
// mit angehobener Ferse
void stand_leg(float w, float side, inout vec2 hp, inout float kn, inout float fl) {
	hp.y -= side * 0.075 * w / 0.86;
	float free = max(-side * w, 0.0);
	kn += 0.3 * free;
	hp.x += 0.1 * free;
	fl -= 0.65 * free;
}

// Hautton 0..1: hell, mittel, dunkel
vec3 skin_of(float r) {
	float sk = r * (0.72 + 0.28 * r);  // mehr helle als dunkle Töne
	return sk < 0.5 ? mix(vec3(0.86, 0.66, 0.53), vec3(0.7, 0.48, 0.34), sk * 2.0) : mix(vec3(0.7, 0.48, 0.34), vec3(0.3, 0.19, 0.13), sk * 2.0 - 1.0);
}

vec3 pick4(float h, vec3 a, vec3 b, vec3 c, vec3 d) {
	return h < 0.25 ? a : (h < 0.5 ? b : (h < 0.75 ? c : d));
}

void vertex() {
	float part = floor(UV.x + 0.5);
	float grp = floor(UV.y + 0.5);
	float opt = floor(UV2.x + 0.5);
	float kw = UV2.y;
	vec4 cu = custom.x >= 0.0 ? custom : INSTANCE_CUSTOM;
	vec3 top = custom.x >= 0.0 ? shirt : COLOR.rgb;
	float mode = floor(cu.b * 10.0 + 0.5);
	bool starter = mode > 6.5;
	float t = TIME;
	float ph = cu.a * 6.2831;

	// Aussehen würfeln (fest je Figur)
	float h1 = fract(cu.a * 7.31 + cu.g * 3.17);
	float h2 = fract(cu.r * 5.71 + cu.a * 2.39);
	float h3 = fract(cu.g * 11.3 + cu.a * 1.73);
	float h4 = fract(cu.r * 3.37 + cu.g * 7.77 + cu.a * 0.53);
	float h5 = fract(cu.a * 13.1 + cu.r * 1.9);
	float h6 = fract(cu.r * 17.3 + cu.g * 0.7 + cu.a * 3.1);
	float h7 = fract(cu.g * 19.1 + cu.a * 0.37);
	float h8 = fract(cu.a * 23.7 + cu.r * 0.91);
	float h9 = fract(cu.a * 31.3 + cu.g * 2.3 + cu.r * 0.17);
	float h10 = fract(cu.g * 29.7 + cu.r * 4.1 + cu.a * 0.77);
	float h11 = fract(cu.a * 41.9 + cu.r * 6.3);
	float fem = (h9 < 0.5 || starter) ? 1.0 : 0.0;
	float wt = h10 * 2.0 - 1.0;  // Statur -1 schlank .. 1 kräftig, meist dazwischen
	wt = starter ? -0.35 : wt * abs(wt);
	float hw = h2 < 0.13 ? 1.0 : (h2 < 0.23 ? 2.0 : 0.0);  // Kopfbedeckung: 1 Kappe, 2 Mütze
	if (fem > 0.5 && hw == 1.0 && h2 > 0.07) {
		hw = 0.0;
	}
	float hair;  // 0 Glatze, 1 kurz, 2 lang, 3 Zopf, 4 Dutt
	if (fem > 0.5) {
		hair = h1 < 0.17 ? 1.0 : (h1 < 0.6 ? 2.0 : (h1 < 0.86 ? 3.0 : 4.0));
	} else {
		hair = h1 < 0.1 ? 0.0 : (h1 < 0.95 ? 1.0 : (h1 < 0.98 ? 2.0 : 4.0));
	}
	float topk = h3 < 0.26 ? 0.0 : (h3 < 0.48 ? 1.0 : (h3 < 0.76 ? 2.0 : 3.0));  // 0 T-Shirt, 1 Hoodie, 2 Jacke, 3 Langarm
	float bottom = fem > 0.5 ? (h4 < 0.27 ? 2.0 : (h4 < 0.36 ? 1.0 : 0.0)) : (h4 < 0.09 ? 1.0 : 0.0);  // 0 Hose, 1 kurz, 2 Rock
	if (starter) {
		hair = 2.0;
		hw = 0.0;
		topk = 0.0;
		bottom = 2.0;
	}
	bool backpack = h6 < 0.13 && topk != 1.0 && !starter;
	bool bag = h6 >= 0.13 && h6 < 0.24 && !starter;
	bool glasses = h7 < 0.17 && !starter;
	bool beard = fem < 0.5 && h8 < 0.3;
	bool cap_back = h8 > 0.72;
	float wst = starter ? 0.3 : h5;  // Art der Bewegung (und des Aufdrucks; die Starterin trägt ein schlichtes Shirt)
	bool phone = mode == 6.0 || (mode == 2.0 && wst >= 0.56 && wst < 0.76);
	bool show = opt < 0.5;
	show = show || (opt == 1.0 && hw == 0.0 && hair > 0.5);
	show = show || (opt == 2.0 && hair == 2.0);
	show = show || (opt == 3.0 && hair == 3.0);
	show = show || (opt == 4.0 && hair == 4.0 && hw == 0.0);
	show = show || (opt == 5.0 && hw == 1.0) || (opt == 6.0 && hw == 2.0);
	show = show || (opt == 7.0 && topk == 1.0);
	show = show || (opt == 8.0 && bottom == 2.0);
	show = show || (opt == 9.0 && topk == 2.0);
	show = show || (opt == 10.0 && starter);
	show = show || (opt == 11.0 && phone);
	show = show || (opt == 12.0 && hair > 0.5 && hair != 2.0);
	show = show || (opt == 13.0 && backpack) || (opt == 14.0 && bag);

	// Säume: Oberteil endet über der Hose, Ärmel kurz oder bis zum Handgelenk, Hosenbein lang, kurz oder nackt (Rock)
	float hem = topk == 1.0 ? 0.93 : (topk == 2.0 ? 0.955 : 0.95);
	float sleeve = topk == 0.0 ? 1.275 : 0.866;
	float pants = bottom == 0.0 ? 0.05 : (bottom == 1.0 ? 0.585 : 9.0);
	bool tights = bottom == 2.0 && h4 < 0.11 && !starter;

	vec3 v = VERTEX;
	vec3 n = NORMAL;
	rest = v;
	if (show) {
		// --- Haltung je Bewegung ---
		// Becken: heben, zur Seite, kippen (links runter positiv), drehen; Wirbelsäule sp: x vor, y seitlich (rechts),
		// z drehen; Kopf hd: x nicken (vor), y neigen, z drehen. Je Ecke nur das eigene Glied (Teile liegen am Stück,
		// die Abfragen verzweigen also einheitlich): Schulter sh (x vor heben, y seitlich heben, z nach innen drehen:
		// bei gebeugtem Ellbogen kommt die Hand zur Mitte), Ellbogen el (x beugen, y Unterarm drehen), Hüfte hp (x vor,
		// y seitlich), Knie kn, Fuß fl (1 flach am Boden, 0 locker).
		float side = (part == 1.0 || part == 3.0 || part == 6.0 || part == 8.0 || part == 11.0) ? -1.0 : 1.0;
		bool armc = part == 1.0 || part == 2.0 || part == 6.0 || part == 7.0;
		bool legc = part == 3.0 || part == 4.0 || part == 8.0 || part == 9.0 || part == 11.0 || part == 12.0;
		float spd = 0.88 + 0.24 * h11;
		float lift = 0.0, shift = 0.0, ptilt = 0.0, pturn = 0.0, kb = 0.0;
		vec3 sp = vec3(0.0), hd = vec3(0.0);
		vec3 sh = vec3(0.02, 0.07, 0.06);
		vec2 el = vec2(0.22, 0.0);
		vec2 hp = vec2(0.0);
		float kn = 0.04, fl = 1.0;
		if (mode < 0.5) {
			// jubeln: Arme hoch (Fäuste pumpen), im Takt federn; manche springen, manche reißen eine Faust hoch
			float s = t * (5.4 + 1.8 * h11) + ph;
			float s2 = sin(s * 2.0);
			kb = (0.08 + 0.2 * max(-s2, 0.0)) * energy;
			hd.x = -0.1;
			sp.x -= 0.04;
			if (wst < 0.42) {
				if (armc) {
					float pp = side > 0.0 ? max(s2, 0.0) : max(sin(s * 2.0 + 1.7), 0.0);
					sh = vec3(0.32, 2.4 + 0.12 * pp * energy, -1.3);
					el = vec2(0.35 + 0.85 * pp * energy, 0.0);
				}
			} else if (wst < 0.75) {
				if (armc) {
					sh = side > 0.0 ? vec3(0.35, 2.5, -1.35) : vec3(0.45, 0.45, 0.35);
					el = side > 0.0 ? vec2(0.25 + 1.15 * max(s2, 0.0) * energy, 0.0) : vec2(1.35, 0.0);
				}
				float w = 0.55 * sin(s * 0.5);
				stand_body(w, shift, ptilt, sp);
				if (legc) {
					stand_leg(w, side, hp, kn, fl);
				}
			} else {
				float s1 = sin(s);
				float hop = max(s1, 0.0);
				lift = 0.12 * hop * (1.3 - 0.3 * hop) * energy;
				kb = 0.4 * max(-s1, 0.0) * energy;
				if (armc) {
					sh = vec3(0.25, 2.55 - 0.3 * hop, -1.2);
					el = vec2(0.3 + 0.35 * hop, 0.0);
				}
				fl = 1.0 - 0.8 * hop;
			}
		} else if (mode < 1.5) {
			// tanzen, drei Arten: Arme angewinkelt im Wechsel, Faust pumpen mit Kopfnicken, Schritt zur Seite mit Hüfte
			float s = t * 6.5 + ph;
			float s2 = sin(s * 2.0);
			kb = (0.15 + 0.1 * cos(s * 2.0)) * energy;
			hd.x = 0.05 + 0.08 * s2;
			if (wst < 0.4) {
				float s1 = sin(s);
				sp.z = 0.15 * s1;
				pturn = -0.07 * s1;
				if (armc) {
					sh = vec3(0.55 - 0.35 * side * s1, 0.3, 0.4);
					el = vec2(1.45 - 0.3 * side * s1, 0.0);
				}
				stand_body(0.45 * s1, shift, ptilt, sp);
				if (legc) {
					stand_leg(0.45 * s1, side, hp, kn, fl);
				}
			} else if (wst < 0.7) {
				if (armc) {
					sh = side > 0.0 ? vec3(0.3, 2.3 + 0.15 * s2, -1.25) : vec3(0.35, 0.25, 0.5);
					el = side > 0.0 ? vec2(0.3 + 0.85 * max(s2, 0.0), 0.0) : vec2(1.5, 0.0);
				}
				hd.x = 0.1 + 0.18 * max(s2, 0.0);
			} else {
				float w = sin(s * 0.5);
				stand_body(w, shift, ptilt, sp);
				if (legc) {
					stand_leg(w, side, hp, kn, fl);
				}
				ptilt += 0.04 * w;
				if (armc) {
					sh = vec3(0.5 - 0.2 * side * sin(s), 0.35, 0.45);
					el = vec2(1.5, 0.0);
				}
			}
		} else if (mode < 2.5) {
			// warten: Standbein wechseln, umschauen; Arme verschränkt, Hände in den Taschen oder Hüften, aufs Handy
			// schauen oder locker
			float w = clamp(1.7 * sin(t * 0.21 * spd + ph * 3.0), -1.0, 1.0);
			stand_body(w, shift, ptilt, sp);
			if (legc) {
				stand_leg(w, side, hp, kn, fl);
			}
			if (part == 5.0) {
				hd.z = 0.4 * sin(t * 0.17 + ph * 5.0) * smoothstep(0.3, 0.9, abs(sin(t * 0.09 + ph)));
				hd.x = 0.04 + 0.03 * sin(t * 0.3 + ph);
			}
			if (wst < 0.22) {
				// verschränkt: linker Unterarm etwas höher, beide knapp vor der Brust
				if (armc) {
					sh = side < 0.0 ? vec3(0.35, 0.02, 1.5) : vec3(0.4, 0.0, 1.5);
					el = vec2(side < 0.0 ? 1.72 : 1.6, 0.0);
				}
			} else if (wst < 0.42) {
				// Hände in den Hosentaschen (Ellbogen locker nach außen), beim Hoodie in der Bauchtasche
				if (armc) {
					sh = topk == 1.0 ? vec3(-0.1, 0.4, 1.2) : vec3(-0.2, 0.3, 1.0);
					el = vec2(topk == 1.0 ? 1.6 : 0.9, 0.0);
				}
			} else if (wst < 0.56) {
				// Hände in die Hüften
				if (armc) {
					sh = vec3(-0.65, 0.4, 0.6);
					el = vec2(1.7, 0.0);
				}
			} else if (wst < 0.76) {
				// aufs Handy schauen: beide Hände vor dem Bauch, Bildschirm nach oben
				if (armc) {
					sh = side > 0.0 ? vec3(0.2, 0.2, 0.75) : vec3(0.2, 0.16, 0.85);
					el = side > 0.0 ? vec2(1.8, -1.8) : vec2(1.72, -1.6);
				}
				hd.x = 0.42;
				hd.z *= 0.2;
			} else if (armc) {
				sh.x -= side * 0.04 * sin(t * 0.9 + ph);
			}
		} else if (mode < 3.5) {
			// winken mit rechts: Oberarm seitlich hoch, Unterarm schwingt hin und her
			float s = t * 7.0 * spd + ph;
			if (armc && side > 0.0) {
				sh = vec3(0.25, 2.0, -1.2);
				el = vec2(0.75 + 0.38 * sin(s), 0.0);
			}
			float sh5 = sin(s * 0.5);
			stand_body(0.6 + 0.15 * sh5, shift, ptilt, sp);
			if (legc) {
				stand_leg(0.6 + 0.15 * sh5, side, hp, kn, fl);
			}
			hd.y = 0.05 * sh5;
			lift = 0.008 * abs(sh5);
		} else if (mode < 4.5) {
			// klatschen: Hände vor der Brust, Unterarme schwingen zur Mitte
			float sc = sin(t * (8.5 + 2.0 * h11) + ph);
			if (armc) {
				sh = vec3(0.3, 0.02, 0.72 + 0.18 * sc);
				el = vec2(1.7, -0.2);
			}
			kb = 0.04 + 0.04 * abs(sc);
			float w = 0.5 * sin(t * 0.3 + ph);
			stand_body(w, shift, ptilt, sp);
			if (legc) {
				stand_leg(w, side, hp, kn, fl);
			}
		} else if (mode < 5.5) {
			// rennen: Knie hoch, Ferse zum Gesäß, Arme angewinkelt gegengleich, Oberkörper vor
			float s = t * 9.0 * spd + ph;
			float sn = sin(s);
			if (legc) {
				hp = vec2(-0.55 * side * sn, 0.0);
				float c = max(-side * cos(s + 0.3), 0.0);
				kn = 0.3 + 1.3 * c * c;
				fl = 0.35;
			}
			if (armc) {
				sh = vec3(0.6 * side * sn, 0.12, 0.3);
				el = vec2(1.55, 0.0);
			}
			sp.x = 0.2;
			sp.z = 0.1 * sn;
			pturn = -0.08 * sn;
			hd.x = -0.12;
			lift = 0.045 * abs(sn);
		} else if (mode < 6.5) {
			// Handy: filmen (vor dem Gesicht hochhalten), telefonieren (am Ohr) oder tippen (vor dem Bauch)
			float w = 0.7 * sin(t * 0.25 + ph);
			stand_body(w, shift, ptilt, sp);
			if (legc) {
				stand_leg(w, side, hp, kn, fl);
			}
			if (wst < 0.5) {
				// filmen: Handy in Augenhöhe vor dem Gesicht, Bildschirm zum Gesicht, langsam schwenken
				if (armc && side > 0.0) {
					sh = vec3(1.4, 0.2 + 0.06 * sin(t * 0.6 + ph), 0.8);
					el = vec2(1.65, -1.6);
				}
				hd.x = 0.06;
			} else if (wst < 0.75) {
				// telefonieren: Ellbogen vor, Hand an der Wange, Kopf neigt sich zum Handy
				if (armc && side > 0.0) {
					sh = vec3(1.3, 0.0, 0.6);
					el = vec2(2.6, 0.5);
				}
				hd.y = 0.12;
				hd.x = 0.05 + 0.06 * sin(t * 0.7 + ph);
			} else {
				if (armc) {
					sh = side > 0.0 ? vec3(0.2, 0.2, 0.75) : vec3(0.2, 0.16, 0.85);
					el = side > 0.0 ? vec2(1.8, -1.8) : vec2(1.72, -1.6);
				}
				hd.x = 0.42;
			}
		} else {
			// Starterin: Arme per Uniform (seitlich hoch, oben Handflächen nach vorn), bei GO nach vorn beugen
			float up = smoothstep(0.8, 2.4, arm);
			if (armc) {
				sh = vec3(0.12 + bow * 1.15, arm, -1.1 * up);
				el = vec2(0.12 + 0.25 * (1.0 - up), 0.0);
			}
			sp.x = bow * 0.45;
			hd.x = bow * 0.15 - 0.05 * up;
			float w = (0.65 + 0.15 * sin(t * 0.8)) * (1.0 - bow);
			stand_body(w, shift, ptilt, sp);
			if (legc) {
				stand_leg(w, side, hp, kn, fl);
			}
			lift = abs(sin(t * 4.0)) * 0.01 * (1.0 - bow);
		}
		// in die Knie: Oberschenkel vor, Unterschenkel zurück, Becken so viel tiefer, dass die Füße am Boden bleiben
		hp.x += kb * 0.5;
		kn += kb;
		float kh = kb * 0.5;
		lift -= 0.81 * kh * kh * (0.5 - 0.0417 * kh * kh) + 0.005 * abs(shift) / 0.03;  // 0,81 * (1 - cos(kh))
		sp.x += kb * 0.3;
		float an = fl * (kn - hp.x);

		// --- Statur: Frau schmalere Schultern, breitere Hüfte, schmale Taille; kräftig mit Bauch, schlank dünner ---
		float shw = 1.0 - 0.1 * fem + 0.03 * wt;
		float hipw = 1.0 + 0.045 * fem + 0.06 * max(wt, 0.0) + 0.03 * min(wt, 0.0);
		float dsh = (shw - 1.0) * 0.185;
		float dhp = (hipw - 1.0) * 0.09;
		float limb = 1.0 - 0.06 * fem + 0.12 * wt;
		// Formdaten aus people.gd (_shape_all): Breitenzone und Polster am Rumpf, Abstand zur Achse an Arm und Bein,
		// Merkmale am Kopf
		vec2 cs = CUSTOM0.xy;
		bool body = grp == 0.0 || grp == 7.0 || grp == 11.0 || grp == 12.0 || grp == 13.0;
		if (body) {
			float waistw = 1.0 - 0.1 * fem + 0.13 * wt;
			float chest = 1.0 + 0.05 * wt - 0.03 * fem;
			v.x *= mix(mix(mix(hipw, waistw, clamp(cs.x, 0.0, 1.0)), chest, clamp(cs.x - 1.0, 0.0, 1.0)), shw, clamp(cs.x - 2.0, 0.0, 1.0));
			float belly = floor(cs.y * 0.5) / 127.0;
			float bump = cs.y - 2.0 * floor(cs.y * 0.5);  // Brust vorn, Gesäß hinten
			float wp = max(wt, 0.0);
			v.z = v.z * (1.0 + 0.07 * wt) - wp * (0.045 - 0.02 * fem) * belly + fem * bump * (v.z < 0.0 ? -0.024 * (1.0 + 0.4 * wp) : 0.014);
		} else if (armc) {
			v.x += side * dsh;
			if (grp == 6.0) {
				// dicker oder dünner um die Armachse (nicht die Hand); lange Ärmel und Jackenärmel tragen etwas auf
				v.xz += cs * ((limb - 1.0) * smoothstep(0.84, 0.9, v.y));
				if (v.y > sleeve) {
					v += NORMAL * (topk == 2.0 ? 0.006 : (topk == 0.0 ? 0.0025 : 0.004));
				}
			}
		} else if (legc) {
			v.x += side * dhp;
			if (grp == 1.0) {
				vec2 d = cs * (limb + 0.04 * wt * smoothstep(0.5, 0.8, v.y));
				if (v.y > pants && v.y < 0.52) {
					// Hosenbein vom Knie an als gerades Rohr (Wade zeichnet sich nicht ab), Normale passend
					vec2 dn = cs / max(length(cs), 0.001);
					float f = 1.0 - smoothstep(0.47, 0.52, v.y);
					d = mix(d, dn * (0.052 + 0.006 * wt), f);
					n = normalize(mix(n, vec3(dn.x, 0.0, dn.y), f));
				}
				v.xz += d - cs;
			}
		} else if (part == 5.0) {
			float neck = mod(cs.x, 2.0);
			if (grp == 2.0 && neck < 0.5 && v.y < 1.6) {
				v.x *= 1.0 - 0.1 * fem * (1.0 - smoothstep(1.53, 1.6, v.y));  // Frauen: schmaleres Kinn
			}
			// Hals bei Frauen schlanker, bei kräftigen dicker
			v.xz += vec2(v.x, v.z - 0.014) * ((0.07 * wt - 0.13 * fem) * neck * (1.0 - smoothstep(1.5, 1.575, v.y)));
			v.y -= 0.009 * fem * step(1.5, mod(cs.x, 4.0));  // Haaransatz bei Frauen etwas tiefer
			if (grp == 2.0) {
				v += NORMAL * ((beard ? 0.004 : 0.0) * step(3.5, cs.x));  // Bart trägt etwas auf
			} else if (grp == 3.0 && (opt == 1.0 || opt == 12.0)) {
				v += NORMAL * ((h5 < 0.25 ? 0.007 : 0.0) * smoothstep(1.6, 1.7, v.y));  // volles, lockiges Haar
			}
			if (opt == 5.0 && cap_back) {
				v.xz = vec2(-v.x, 0.008 - v.z);  // Kappe verkehrt herum
				n.xz = -n.xz;
			}
		}

		// --- Gelenke von innen nach außen: Ecke und Normale je Gelenk um dessen Drehpunkt drehen (billiger als die
		// Matrizen zu verketten) ---
		if (legc) {
			if (part > 10.5) {
				mat3 r_an = rx(an * kw);
				vec3 j_an = vec3(side * (J_ANKLE.x + dhp), J_ANKLE.yz);
				v = r_an * (v - j_an) + j_an;
				n = r_an * n;
			}
			if (part > 7.5) {
				mat3 r_kn = rx(-kn * (part < 9.5 ? kw : 1.0));
				vec3 j_kn = vec3(side * (J_KNEE.x + dhp), J_KNEE.yz);
				v = r_kn * (v - j_kn) + j_kn;
				n = r_kn * n;
			}
			float k = part < 4.5 ? kw : 1.0;
			mat3 r_hp = rot_xz(hp.x * k, side * hp.y * k);
			vec3 j_hp = vec3(side * (J_HIP.x + dhp), J_HIP.yz);
			v = r_hp * (v - j_hp) + j_hp;
			n = r_hp * n;
		} else if (part != 10.0) {
			if (part == 5.0) {
				mat3 r_hd = rot_yxz_small(hd.z * kw, -hd.x * kw, -hd.y * kw);
				v = r_hd * (v - J_NECK) + J_NECK;
				n = r_hd * n;
			} else if (armc) {
				if (part > 5.5) {
					mat3 r_el = el.y == 0.0 ? rx(el.x * kw) : rot_xy(el.x * kw, side * el.y * kw);
					vec3 j_el = vec3(side * (J_ELBOW.x + dsh), J_ELBOW.yz);
					v = r_el * (v - j_el) + j_el;
					n = r_el * n;
				}
				float k2 = part < 2.5 ? kw : 1.0;
				mat3 r_sh = rot_xzy(sh.x * k2, side * sh.y * k2, side * sh.z * k2);
				vec3 j_sh = vec3(side * (J_SHOULDER.x + dsh), J_SHOULDER.yz);
				v = r_sh * (v - j_sh) + j_sh;
				n = r_sh * n;
			}
			float k = part == 0.0 ? kw : 1.0;
			mat3 r_sp = rot_yxz_small(sp.z * k, -sp.x * k, -sp.y * k);
			v = r_sp * (v - J_WAIST) + J_WAIST;
			n = r_sp * n;
		}
		mat3 r_pv = rot_yz_small(pturn, ptilt);
		v = r_pv * (v - J_PELVIS) + J_PELVIS + vec3(shift, lift, 0.0);
		n = r_pv * n;
		v *= 1.0 - 0.06 * fem;
	} else {
		v = vec3(0.0);
	}
	VERTEX = v;
	NORMAL = n;

	// --- Farben: je Gruppe nur die nötigen (ausgeblendete Ecken brauchen keine) ---
	vec3 skin = show ? skin_of(cu.r) : vec3(0.0);
	col = skin;
	col2 = skin;
	if (!show) {
		grp = -1.0;
	}
	if (grp > -0.5 && (grp < 0.5 || grp == 6.0 || grp == 13.0)) {
		// Oberteil: Farben der Gruppe etwas gedämpft, jedes dritte dunkel
		vec3 shirt_c = mix(top, vec3(dot(top, vec3(0.33))), 0.18) * 0.92;
		if (h11 < 0.3 && !starter) {
			shirt_c = h11 < 0.12 ? vec3(0.05, 0.05, 0.055) : (h11 < 0.22 ? vec3(0.2, 0.2, 0.21) : vec3(0.07, 0.09, 0.17));
		}
		col = grp == 13.0 ? shirt_c * 0.92 : shirt_c;
	}
	if (grp < -0.5) {
	} else if (grp < 1.5) {
		// Hose (Jeans dunkel, mittel, hell, Schwarz, Grau, Beige, Oliv), kurze Hose oder Rock (Schwarz, Rot, Navy, Grau)
		vec3 pants_c;
		if (bottom == 2.0) {
			pants_c = starter ? vec3(0.03) : pick4(fract(cu.r * 6.1 + cu.g), vec3(0.04), vec3(0.45, 0.06, 0.1), vec3(0.12, 0.16, 0.3), vec3(0.2, 0.2, 0.22));
		} else {
			float pg = fract(cu.g * 7.3);
			pants_c = pg < 0.42 ? (pg < 0.22 ? vec3(0.09, 0.12, 0.22) : vec3(0.17, 0.25, 0.4)) : (pg < 0.74 ? (pg < 0.52 ? vec3(0.3, 0.4, 0.55) : vec3(0.05, 0.05, 0.055)) : (pg < 0.84 ? vec3(0.25, 0.25, 0.27) : (pg < 0.93 ? vec3(0.45, 0.39, 0.28) : vec3(0.22, 0.25, 0.16))));
		}
		if (grp < 0.5) {
			col2 = pants_c;
		} else {
			col = bottom == 1.0 ? pants_c * 1.15 + 0.03 : pants_c;
			col2 = tights ? vec3(0.04) : skin;
		}
	} else if (grp == 2.0 || grp == 3.0) {
		// Haare, Brauen und Bart (Schwarz, Dunkelbraun, Braun, Blond); manche gefärbt (Bart dann natürlich), ältere Männer grau
		vec3 beard_c = cu.g < 0.68 ? (cu.g < 0.45 ? vec3(0.035, 0.03, 0.028) : vec3(0.16, 0.09, 0.05)) : (cu.g < 0.8 ? vec3(0.36, 0.22, 0.11) : vec3(0.62, 0.5, 0.3));
		vec3 hair_c = cu.g > 0.95 ? vec3(0.75, 0.24, 0.5) : beard_c;
		if (cu.g > 0.9 && cu.g <= 0.95 && fem < 0.5) {
			hair_c = vec3(0.5);
			beard_c = hair_c;
		}
		col = grp == 3.0 ? (starter ? vec3(0.06, 0.04, 0.035) : hair_c) : skin;
		col2 = beard_c;
	} else if (grp == 4.0) {
		// Schuhe: weiße Sneaker, schwarz, grau, braune Stiefel, rot; Sohle hell oder dunkel
		float sg = fract(cu.g * 13.1);
		col = sg < 0.62 ? (sg < 0.35 ? vec3(0.85) : vec3(0.05)) : (sg < 0.75 ? vec3(0.35, 0.36, 0.38) : (sg < 0.87 ? vec3(0.3, 0.18, 0.1) : vec3(0.6, 0.08, 0.08)));
		col2 = (sg < 0.35 || sg > 0.87) ? vec3(0.9) : vec3(0.1);
		col = starter ? vec3(0.04) : col;
		col2 = starter ? vec3(0.1) : col2;
	} else if (grp == 5.0) {
		col = vec3(1.0, 0.2, 0.5);
	} else if (grp == 6.0 || grp == 7.0) {
		if (grp == 7.0 || topk == 2.0) {
			// Jacken: Schwarz, braunes Leder, Navy, Oliv, Grau, Rot
			float jg = fract(cu.a * 5.3 + cu.r);
			col = jg < 0.45 ? (jg < 0.3 ? vec3(0.04, 0.04, 0.045) : vec3(0.22, 0.12, 0.06)) : (jg < 0.76 ? (jg < 0.62 ? vec3(0.06, 0.08, 0.17) : vec3(0.2, 0.23, 0.13)) : (jg < 0.88 ? vec3(0.25, 0.26, 0.28) : vec3(0.55, 0.08, 0.1)));
		}
	} else if (grp == 8.0) {
		col = opt == 3.0 ? vec3(0.08) : pick4(fract(cu.g * 4.7 + cu.a), vec3(0.05), top, vec3(0.85), vec3(0.08, 0.12, 0.3));
	} else if (grp == 9.0) {
		col = vec3(0.03);
	} else if (grp == 10.0) {
		col = vec3(0.45, 0.7, 1.0);
	} else if (grp == 11.0) {
		col = starter ? vec3(0.03) : pick4(fract(cu.r * 6.1 + cu.g), vec3(0.04), vec3(0.45, 0.06, 0.1), vec3(0.12, 0.16, 0.3), vec3(0.2, 0.2, 0.22));
	} else if (grp == 12.0) {
		col = pick4(fract(cu.r * 4.9 + cu.a * 2.2), vec3(0.04), vec3(0.3, 0.17, 0.08), vec3(0.08, 0.16, 0.38), vec3(0.32, 0.33, 0.3));
	}
	float smile = (mode < 1.5 || mode == 3.0 || mode == 4.0) ? 1.0 : 0.0;
	float prt = (topk == 0.0 && wst > 0.5) ? (wst > 0.8 ? 1.0 : (wst > 0.65 ? 2.0 : 3.0)) : 0.0;  // Aufdruck
	float split = grp < 0.5 ? hem : (grp == 1.0 ? pants : sleeve);
	meta = vec4(max(grp, 0.0) + 16.0 * topk, split, (glasses ? 1.0 : 0.0) + (beard ? 2.0 : 0.0) + smile * 4.0 + (tights ? 8.0 : 0.0) + prt * 16.0, cu.r);
}

// weiche Kante: 1 innen (d > 0), 0 außen, Breite ein Bildpunkt (ipw = Bildpunkte je Meter)
float edge(float d, float ipw) {
	return clamp(d * ipw + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 c = col;
	float grp = mod(meta.x, 16.0);
	float topk = floor(meta.x / 16.0);
	float split = meta.y;
	float flags = meta.z;
	float rough = 0.82;
	vec3 p = rest;
	float pw = max(length(fwidth(rest)), 0.0003);  // Meter je Bildpunkt
	float ipw = 1.0 / pw;
	float fine = 1.0 - smoothstep(0.003, 0.01, pw);  // feine Muster in der Ferne ausblenden statt flimmern
	float ax = abs(p.x);
	if (grp < 0.5) {
		// Rumpf: Oberteil oben, Hose unten
		vec3 sh = col;
		if (p.z < -0.05) {
			if (topk == 1.0) {
				// Hoodie: Bauchtasche mit Kanten, zwei Kordeln
				float pk = 0.105 - ax - (p.y - 0.98) * 0.25;
				float pocket = edge(pk, ipw) * edge(1.11 - p.y, ipw) * edge(p.y - 0.965, ipw);
				sh *= 1.0 - 0.1 * pocket - 0.25 * pocket * (1.0 - edge(pk - 0.006, ipw)) * fine;
				float cord = edge(0.003 - abs(ax - 0.032), ipw) * edge(p.y - 1.34, ipw) * edge(1.45 - p.y, ipw);
				sh = mix(sh, vec3(0.72), cord * 0.8 * fine);
			} else if (flags >= 16.0) {
				// Aufdruck: Kreis, Streifen oder Schriftzug, hell auf dunklem Shirt, dunkel auf hellem
				float prt = floor(flags / 16.0);
				vec3 detail_col = dot(col, vec3(0.33)) > 0.45 ? vec3(0.08) : vec3(0.88);
				float pr;
				if (prt == 1.0) {
					pr = edge(0.048 - length(p.xy - vec2(0.0, 1.25)), ipw);
				} else if (prt == 2.0) {
					pr = edge(0.02 - abs(p.y - 1.23), ipw) * edge(0.13 - ax, ipw);
				} else {
					pr = edge(0.011 - abs(p.y - 1.26), ipw) * edge(0.07 - ax, ipw) * (0.55 + 0.45 * step(0.5, fract(p.x * 55.0)));
				}
				sh = mix(sh, detail_col, pr);
			}
		}
		// Bündchen am Saum (Hoodie, Langarm), unten am Oberteil etwas Schatten
		if (topk == 1.0 || topk == 3.0) {
			sh *= 1.0 - 0.1 * edge(split + 0.035 - p.y, ipw);
		}
		sh *= 0.88 + 0.12 * smoothstep(1.0, 1.28, p.y);
		// Hose: Gürtel, Naht vorn, Gesäßtaschen, Schatten im Schritt
		vec3 pa = col2;
		pa *= 1.0 - 0.5 * edge(0.011 - abs(p.y - split + 0.012), ipw) * (topk == 1.0 ? 0.0 : 1.0);
		pa *= 1.0 - 0.25 * edge(0.0025 - ax, ipw) * step(p.z, -0.05) * edge(0.94 - p.y, ipw) * fine;
		pa *= 1.0 - 0.16 * edge(0.042 - abs(ax - 0.085), ipw) * edge(0.038 - abs(p.y - 0.9), ipw) * step(0.06, p.z);
		pa *= 1.0 - 0.3 * (1.0 - smoothstep(0.8, 0.87, p.y)) * (1.0 - smoothstep(0.0, 0.07, ax));
		c = mix(pa, sh, edge(p.y - split, ipw));
		// Halsausschnitt: Haut über dem Kragen (vorn rund und tiefer), Kragen als feine Kante
		float neck = p.z < 0.0 ? 1.452 + 6.0 * p.x * p.x : 1.478;
		neck += topk == 1.0 ? 0.012 : 0.0;
		c *= 1.0 - 0.22 * edge(0.004 - abs(p.y - neck + 0.004), ipw);
		c = mix(c, skin_of(meta.w), edge(p.y - neck, ipw));
		// Achseln etwas dunkler
		c *= 1.0 - 0.2 * smoothstep(0.12, 0.165, ax) * smoothstep(1.2, 1.3, p.y) * (1.0 - smoothstep(1.32, 1.4, p.y));
	} else if (grp < 1.5) {
		// Bein: Hose bis split, darunter Haut oder Strumpfhose; Jeans mit Außennaht, hellerem Knie, Saum
		float pn = edge(p.y - split, ipw);
		vec3 pa = col;
		pa *= 1.0 - 0.22 * edge(0.0025 - abs(ax - 0.145), ipw * 0.667) * fine;
		pa *= 1.0 + 0.1 * (1.0 - smoothstep(0.0, 0.12, abs(p.y - 0.6))) * step(p.z, -0.02);
		pa *= 1.0 - 0.3 * edge(0.006 - abs(p.y - split - 0.005), ipw) * step(0.1, split);
		pa *= 1.0 - 0.25 * (1.0 - smoothstep(0.8, 0.87, p.y)) * (1.0 - smoothstep(0.0, 0.06, ax));
		vec3 sk = col2;
		if (mod(flags, 16.0) >= 8.0) {
			rough = 0.5;
		}
		c = mix(sk, pa, pn);
	} else if (grp < 2.5) {
		// Haut; Gesicht vorn am Kopf
		if (p.z < -0.03 && p.y > 1.5 && p.y < 1.7) {
			float fx = ax;
			float fy = p.y;
			float detail = 1.0 - smoothstep(0.0035, 0.009, pw);  // in der Ferne nur Augenhöhlen und Nase
			vec3 hairc = col2;
			// Augenhöhlen und Brauenschatten (weich, auch aus der Ferne sichtbar)
			vec2 so = vec2((fx - 0.031) / 0.021, (fy - 1.636) / 0.013);
			float sock = exp(-dot(so, so));
			c *= 1.0 - 0.2 * sock;
			// Augen: dunkle Iris, wenig Weiß, Oberlid als Linie
			float ex = (fx - 0.031) / 0.0105;
			float ey = (fy - 1.6335) / 0.0048;
			float eye = ex * ex + ey * ey;
			c = mix(c, mix(c, vec3(0.86, 0.83, 0.8), 0.3), (1.0 - smoothstep(0.7, 1.0, eye)) * detail);
			float ir = length(vec2((fx - 0.031) / 0.0052, (fy - 1.6335) / 0.0048));
			c = mix(c, vec3(0.07, 0.05, 0.04), (1.0 - smoothstep(0.75, 1.0, ir)) * detail);
			float lid = smoothstep(0.55, 0.95, eye) * (1.0 - smoothstep(1.0, 1.7, eye)) * step(1.6335, fy);
			c = mix(c, c * 0.45, lid * detail);
			// Brauen
			float bx = fx - 0.033;
			float brow = edge(0.0024 - abs(fy - (1.6585 - 18.0 * bx * bx)), ipw) * edge(0.019 - abs(bx), ipw);
			c = mix(c, hairc * 0.9, brow * 0.85 * detail);
			// Mund: Lippen etwas dunkler, beim Jubeln ein leichtes Lächeln
			float sm = mod(flags, 8.0) >= 4.0 ? 1.0 : 0.0;
			float my = fy - (1.5745 + sm * 14.0 * fx * fx);
			c = mix(c, c * vec3(0.8, 0.62, 0.6), edge(0.0042 - abs(my + 0.0005), ipw) * edge(0.024 - fx, ipw) * 0.8 * detail);
			c = mix(c, c * 0.45, edge(0.0011 - abs(my), ipw) * edge(0.022 - fx, ipw) * detail);
			// Schatten unter der Nase, Wangen etwas wärmer
			c *= 1.0 - 0.15 * edge(0.004 - abs(fy - 1.589), ipw) * edge(0.014 - fx, ipw);
			vec2 ch = vec2((fx - 0.046) / 0.015, (fy - 1.603) / 0.012);
			c *= vec3(1.0, 0.97, 0.97) + vec3(0.03, 0.0, 0.0) * exp(-dot(ch, ch));
			// Bart: Haarfarbe auf Kinn, Kiefer und Oberlippe
			if (mod(flags, 4.0) >= 2.0) {
				float bz = (1.0 - smoothstep(1.598, 1.607, fy)) * (1.0 - smoothstep(0.06, 0.075, fx));
				float mouth = edge(0.0035 - abs(my + 0.0005), ipw) * edge(0.02 - fx, ipw);
				c = mix(c, hairc * 1.05, bz * 0.88 * (1.0 - mouth));
			}
			// Brille: dünner dunkler Rahmen um die Augen, Steg, Bügel zum Ohr
			if (mod(flags, 2.0) >= 1.0) {
				vec2 q = abs(vec2(fx - 0.032, fy - 1.634)) - vec2(0.018, 0.0105);
				float bx2 = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.004;
				float rim = edge(0.0016 - abs(bx2), ipw);
				rim = max(rim, edge(0.0013 - abs(fy - 1.637), ipw) * edge(0.011 - fx, ipw));
				rim = max(rim, edge(0.0013 - abs(fy - 1.638), ipw) * step(0.06, fx));
				c = mix(c, vec3(0.03), rim);
				c = mix(c, c * 0.88, edge(-bx2, ipw));
			}
		}
		if (p.y > 1.44 && p.y < 1.545 && p.z > -0.05) {
			c *= 0.84;  // Hals im Schatten des Kinns
		}
		rough = 0.65;
	} else if (grp < 3.5) {
		// Haare: feine Strähnen
		c *= 0.9 + 0.1 * sin(atan(p.x, p.z) * 38.0 + p.y * 60.0) * fine;
		rough = 0.55;
	} else if (grp < 4.5) {
		// Schuh: Sohle mit feiner Kante
		c = mix(c, col2, edge(0.021 - p.y, ipw));
		c *= 1.0 - 0.3 * edge(0.0025 - abs(p.y - 0.021), ipw) * fine;
		rough = 0.6;
	} else if (grp > 5.5 && grp < 6.5) {
		// Arm: Ärmel bis split (lang mit Bündchen, kurz mit Saum), darunter Haut
		float sl = edge(p.y - split, ipw);
		vec3 sv = col;
		if (topk != 0.0) {
			sv *= 1.0 - 0.12 * edge(split + 0.03 - p.y, ipw);
		} else {
			sv *= 1.0 - 0.25 * edge(0.006 - abs(p.y - split - 0.003), ipw);
		}
		sv *= 0.9 + 0.1 * smoothstep(1.0, 1.35, p.y);
		c = mix(col2, sv, sl);
		if (topk == 2.0) {
			rough = mix(0.82, 0.5, sl);
		}
	} else if (grp > 6.5 && grp < 7.5) {
		// Jacke: unten etwas dunkler, Taschen schräg, glatter Stoff
		c *= 0.88 + 0.12 * smoothstep(0.95, 1.35, p.y);
		c *= 1.0 - 0.45 * edge(0.004 - abs(ax - 0.11 + (p.y - 1.0) * 0.4), ipw) * edge(0.045 - abs(p.y - 1.04), ipw) * step(p.z, -0.04) * fine;
		rough = 0.5;
	} else if (grp > 7.5 && grp < 8.5) {
		// Kappe, Mütze: feine Rippen
		c *= 0.92 + 0.08 * sin(atan(p.x, p.z) * 30.0) * fine;
		rough = 0.7;
	} else if (grp > 10.5 && grp < 11.5) {
		// Rock: leichte Falten
		c *= 0.9 + 0.1 * sin(atan(p.x, p.z) * 14.0);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	float glow = grp == 5.0 ? 1.0 : (grp == 10.0 ? 0.6 : 0.0);  // Leuchtstab, Handy-Bildschirm
	EMISSION = c * glow * 4.0 + c * 0.06;
}
