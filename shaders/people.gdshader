shader_type spatial;
// Leute (Zuschauer, Fans, Starterin, Wartende), Modelle aus scripts/people.gd; Bewegung, Kleidung und Gesicht macht
// der Shader.
// UV.x = Körperteil (0 Rumpf, 1/2 Oberarm l/r, 3/4 Oberschenkel l/r, 5 Kopf, 6/7 Unterarm mit Hand l/r,
//        8/9 Unterschenkel mit Schuh l/r: seit 2.24 mit Knie, die Leute federn beim Tanzen und Jubeln in die Knie)
// UV.y = Farbgruppe (0 Oberteil, 1 Hose, 2 Haut, 3 Haare, 4 Schuhe, 5 Leuchtstab, 6 Unterarm: Ärmel oder Haut,
//        7 Schienbein: Hose oder Haut, 8 Sohle, 9 Jacke, 10 Kappe/Mütze/Haargummi, 11 Handy, 12 Bildschirm, 13 Rock,
//        14 Oberschenkel unten: Hose oder Haut)
// UV2.x = Variante (0 immer, 1 Haare oben, 2 lange Haare, 3 Zopf, 4 Dutt, 5 Kappe, 6 Mütze, 7 Kapuze, 8 Rock,
//        9 Jacke, 10 Leuchtstäbe, 11 Handy, 12 Haare im Nacken). Nicht gewählte Teile fallen auf einen Punkt zusammen.
// Instanzfarbe = Oberteil. INSTANCE_CUSTOM: r Hautton, g Haare/Hose, b Bewegung/10, a Takt; aus r, g, a werden
// außerdem Frisur, Kopfbedeckung, Oberteil und Unterteil gewürfelt.
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
varying vec3 rest;  // Lage im Modell vor der Bewegung (für Gesicht und Aufdrucke)
varying flat vec4 info;  // Körperteil, Farbgruppe, Oberteil-Art, Zufall
varying flat vec3 detail_col;  // Farbe für Brauen bzw. Aufdruck

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

vec3 pick4(float h, vec3 a, vec3 b, vec3 c, vec3 d) {
	return h < 0.25 ? a : (h < 0.5 ? b : (h < 0.75 ? c : d));
}

void vertex() {
	float part = floor(UV.x + 0.5);
	float grp = floor(UV.y + 0.5);
	float opt = floor(UV2.x + 0.5);
	vec4 cu = custom.x >= 0.0 ? custom : INSTANCE_CUSTOM;
	vec3 top = custom.x >= 0.0 ? shirt : COLOR.rgb;
	float mode = floor(cu.b * 10.0 + 0.5);
	float ph = cu.a * 6.2831;
	float t = TIME;

	// Aussehen würfeln (fest je Figur)
	float h1 = fract(cu.a * 7.31 + cu.g * 3.17);
	float h2 = fract(cu.r * 5.71 + cu.a * 2.39);
	float h3 = fract(cu.g * 11.3 + cu.a * 1.73);
	float h4 = fract(cu.r * 3.37 + cu.g * 7.77 + cu.a * 0.53);
	float h5 = fract(cu.a * 13.1 + cu.r * 1.9);
	float headwear = h2 < 0.16 ? 5.0 : (h2 < 0.26 ? 6.0 : 0.0);  // Kappe, Mütze
	float hair = h1 < 0.07 ? 0.0 : floor(h1 * 4.0) + 1.0;  // 0 Glatze, 1 kurz, 2 lang, 3 Zopf, 4 Dutt
	if (headwear > 0.0) {
		hair = 1.0;
	}
	float topk = h3 < 0.22 ? 1.0 : (h3 < 0.42 ? 2.0 : (h3 < 0.74 ? 0.0 : 3.0));  // 0 T-Shirt, 1 Hoodie, 2 Jacke, 3 Langarm
	float bottom = h4 < 0.13 ? 2.0 : (h4 < 0.3 ? 1.0 : 0.0);  // 0 lange Hose, 1 Shorts, 2 Rock
	bool show = opt < 0.5;
	show = show || (opt > 0.5 && opt < 1.5 && headwear < 0.5 && hair > 0.5);
	show = show || (opt > 1.5 && opt < 4.5 && hair == opt);
	show = show || ((opt == 5.0 || opt == 6.0) && headwear == opt);
	show = show || (opt == 7.0 && topk == 1.0);
	show = show || (opt == 8.0 && bottom == 2.0);
	show = show || (opt == 9.0 && topk == 2.0);
	show = show || (opt == 10.0 && mode == 7.0);
	show = show || (opt == 11.0 && mode == 6.0);
	show = show || (opt == 12.0 && hair > 0.5 && hair != 2.0);
	// Zubehör (seit 2.29): Rucksack, Umhängetasche, Brille, Bart (nur ohne lange Haare, Zopf, Dutt, Rock)
	float h6 = fract(cu.r * 17.3 + cu.g * 0.7 + cu.a * 3.1);
	float h7 = fract(cu.g * 19.1 + cu.a * 0.37);
	float h8 = fract(cu.a * 23.7 + cu.r * 0.91);
	show = show || (opt == 13.0 && h6 < 0.2 && topk != 1.0);
	show = show || (opt == 14.0 && h6 >= 0.2 && h6 < 0.34);
	show = show || (opt == 15.0 && h7 < 0.24);
	show = show || (opt == 16.0 && h8 < 0.22 && hair < 2.5 && hair != 2.0 && bottom < 1.5);

	// Gelenkwinkel: *_z = seitlich heben (Arme), *_x = vor/zurück (positiv = nach vorn), el_* = Ellbogen beugen
	float al_z = 0.0, ar_z = 0.0, al_x = 0.0, ar_x = 0.0, ll_x = 0.0, lr_x = 0.0;
	float el_l = 0.15, el_r = 0.15;
	float lift = 0.0, sway = 0.0, nod = 0.0, lean = 0.0;
	float sq = 0.0;  // in die Knie gehen (Oberschenkel vor, Unterschenkel zurück, Körper tiefer)
	float kn_l = 0.0, kn_r = 0.0;  // Knie beugen (negativ: Unterschenkel nach hinten, wie ein echtes Knie)
	if (mode < 0.5) {
		// jubeln: hüpfen, Arme hoch, Fäuste pumpen; vor dem Absprung und nach der Landung in die Knie
		float s = t * (5.0 + fract(cu.a * 7.0) * 2.0) + ph;
		lift = max(sin(s), 0.0) * 0.22 * energy;
		sq = max(-sin(s), 0.0) * 0.32 * energy;
		al_z = -2.5 - 0.35 * sin(s * 2.0) * energy;
		ar_z = 2.5 + 0.35 * sin(s * 2.0 + 1.3) * energy;
		el_l = 0.35 + 0.35 * max(sin(s * 2.0), 0.0);
		el_r = 0.35 + 0.35 * max(sin(s * 2.0 + 1.3), 0.0);
	} else if (mode < 1.5) {
		// tanzen, drei Arten je Figur: im Takt in die Knie federn und Arme schwingen, Faust pumpen mit Kopfnicken,
		// Schritt zur Seite mit Hüfte; alle wippen auf jedem Schlag
		float s = t * 6.5 + ph;
		float beat = 0.5 + 0.5 * cos(s * 2.0);  // jeder Schlag ein Federn
		sq = (0.08 + 0.22 * beat) * energy;
		nod = sin(s) * 0.12;
		if (h5 < 0.4) {
			sway = sin(s * 0.5) * 0.1;
			al_z = -1.2 - 1.2 * max(sin(s), 0.0);
			ar_z = 1.2 + 1.2 * max(-sin(s), 0.0);
			al_x = 0.5 + sin(s) * 0.5;
			ar_x = 0.5 - sin(s) * 0.5;
			el_l = 0.9 + 0.5 * sin(s);
			el_r = 0.9 - 0.5 * sin(s);
		} else if (h5 < 0.7) {
			// Faust pumpen (rechts hoch, links locker), Kopf nickt kräftig mit
			ar_z = 2.4 + 0.25 * sin(s * 2.0);
			el_r = 0.4 + 0.5 * max(sin(s * 2.0), 0.0);
			al_x = 0.35;
			al_z = -0.25;
			el_l = 1.2;
			nod = 0.06 + sin(s * 2.0) * 0.16;
		} else {
			// Schritt zur Seite: Gewicht wechselt, ein Knie geht mit, Arme angewinkelt vor dem Körper
			float w = sin(s * 0.5);
			sway = w * 0.14;
			kn_l = -max(w, 0.0) * 0.5;
			kn_r = -max(-w, 0.0) * 0.5;
			ll_x = max(w, 0.0) * 0.25;
			lr_x = max(-w, 0.0) * 0.25;
			al_x = 0.55 + 0.25 * sin(s);
			ar_x = 0.55 - 0.25 * sin(s);
			el_l = 1.4;
			el_r = 1.4;
			al_z = 0.2;
			ar_z = -0.2;
		}
	} else if (mode < 2.5) {
		// warten: atmen, Gewicht verlagern, manche mit verschränkten Armen
		lift = sin(t * 1.3 + ph) * 0.008;
		sway = sin(t * 0.4 + ph) * 0.02;
		al_x = sin(t * 0.9 + ph) * 0.05;
		ar_x = -al_x;
		nod = sin(t * 0.3 + ph * 2.0) * 0.1;
		// Standbein und Spielbein: ein Knie leicht gebeugt
		kn_l = h4 < 0.5 ? -0.18 : 0.0;
		kn_r = h4 < 0.5 ? 0.0 : -0.18;
		if (h5 < 0.4) {
			al_x = 0.35;
			ar_x = 0.35;
			al_z = 0.35;
			ar_z = -0.35;
			el_l = 1.75;
			el_r = 1.65;
		}
	} else if (mode < 3.5) {
		// winken mit rechts: Oberarm hoch, Unterarm schwingt
		ar_z = 2.2;
		el_r = 0.5 + sin(t * 7.0 + ph) * 0.45;
		lift = abs(sin(t * 3.5 + ph)) * 0.03;
		al_x = 0.1;
	} else if (mode < 4.5) {
		// klatschen: Hände vor der Brust
		float s = sin(t * 9.0 + ph);
		al_x = 0.75;
		ar_x = 0.75;
		el_l = 1.1;
		el_r = 1.1;
		al_z = 0.38 + 0.16 * s;
		ar_z = -0.38 - 0.16 * s;
		lift = abs(s) * 0.015;
	} else if (mode < 5.5) {
		// rennen
		float s = t * 11.0 + ph;
		al_x = sin(s) * 0.9;
		ar_x = -al_x;
		el_l = 1.3;
		el_r = 1.3;
		ll_x = -sin(s) * 0.8;
		lr_x = -ll_x;
		kn_l = -0.9 * max(sin(s), 0.0) - 0.2;
		kn_r = -0.9 * max(-sin(s), 0.0) - 0.2;
		lift = abs(sin(s)) * 0.08;
		lean = 0.15;
	} else if (mode < 6.5) {
		// telefonieren: rechte Hand mit Handy am Ohr
		ar_x = 0.25;
		ar_z = 0.5;
		el_r = 2.55;
		nod = sin(t * 0.7 + ph) * 0.08;
		lift = sin(t * 1.3 + ph) * 0.008;
	} else {
		// Starterin: Arme per Uniform, leicht wippen
		al_z = -arm;
		ar_z = arm;
		al_x = bow * 1.2;
		ar_x = bow * 1.2;
		el_l = 0.05;
		el_r = 0.05;
		lean = bow * 0.35;
		lift = abs(sin(t * 4.0)) * 0.02 * (1.0 - bow);
		sway = sin(t * 2.0) * 0.03 * (1.0 - bow);
	}
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	rest = v;
	// in die Knie: Oberschenkel nach vorn, Unterschenkel doppelt zurück, Körper so viel tiefer, dass die Füße am Boden
	// bleiben (Oberschenkel 0,36 m, Unterschenkel 0,5 m)
	ll_x += sq;
	lr_x += sq;
	kn_l -= 2.0 * sq;
	kn_r -= 2.0 * sq;
	lift -= 0.86 * (1.0 - cos(sq));
	lean += sq * 0.35;
	if (part > 7.5) {
		// Unterschenkel: erst im Knie beugen, dann wie der Oberschenkel in der Hüfte drehen
		bool left = part < 8.5;
		vec3 kp = vec3(left ? -0.09 : 0.09, 0.5, 0.0);
		mat3 mk = rot_x(left ? kn_l : kn_r);
		v = kp + mk * (v - kp);
		n = mk * n;
	}
	if (part > 5.5 && part < 7.5) {
		// Unterarm: erst im Ellbogen beugen, dann wie der Oberarm in der Schulter drehen
		bool left = part < 6.5;
		vec3 ep = vec3(left ? -0.255 : 0.255, 1.13, 0.0);
		mat3 me = rot_x(left ? el_l : el_r);
		v = ep + me * (v - ep);
		n = me * n;
	}
	mat3 m = mat3(1.0);
	vec3 pivot = vec3(0.0);
	if ((part > 0.5 && part < 2.5) || (part > 5.5 && part < 7.5)) {
		bool left = part < 1.5 || (part > 5.5 && part < 6.5);
		pivot = vec3(left ? -0.22 : 0.22, 1.39, 0.0);
		m = rot_x(left ? al_x : ar_x) * rot_z(left ? al_z : ar_z);
	} else if ((part > 2.5 && part < 4.5) || part > 7.5) {
		bool left = part < 3.5 || (part > 7.5 && part < 8.5);
		pivot = vec3(left ? -0.09 : 0.09, 0.86, 0.0);
		m = rot_x(left ? ll_x : lr_x);
	} else if (part > 4.5 && part < 5.5) {
		pivot = vec3(0.0, 1.5, 0.0);
		m = rot_x(nod);
	}
	v = pivot + m * (v - pivot);
	n = m * n;
	// Oberkörper (alles über der Hüfte) neigen und wiegen
	if (part < 2.5 || (part > 4.5 && part < 7.5)) {
		mat3 b = rot_x(lean) * rot_z(sway);
		vec3 hip = vec3(0.0, 0.86, 0.0);
		v = hip + b * (v - hip);
		n = b * n;
	}
	v.y += lift;
	if (!show) {
		v = vec3(0.0);
	}
	VERTEX = v;
	NORMAL = n;

	vec3 skin = mix(vec3(0.93, 0.76, 0.62), vec3(0.32, 0.2, 0.13), cu.r);
	vec3 hair_c = mix(vec3(0.04, 0.03, 0.025), vec3(0.55, 0.38, 0.16), step(0.72, cu.g));
	if (cu.g > 0.93) {
		hair_c = vec3(1.0, 0.25, 0.65);
	} else if (cu.g > 0.86) {
		hair_c = vec3(0.85, 0.75, 0.5);  // blond
	}
	vec3 pants = pick4(fract(cu.g * 7.3), vec3(0.08, 0.11, 0.2), vec3(0.04, 0.04, 0.045), vec3(0.16, 0.24, 0.4), fract(cu.g * 2.1) > 0.5 ? vec3(0.42, 0.36, 0.24) : vec3(0.3, 0.3, 0.32));
	vec3 shoes = pick4(fract(cu.g * 13.1), vec3(0.88), vec3(0.05), vec3(0.88), vec3(0.6, 0.08, 0.08));
	vec3 jacket = pick4(fract(cu.a * 5.3 + cu.r), vec3(0.05), vec3(0.25, 0.14, 0.07), vec3(0.06, 0.08, 0.18), fract(cu.r * 9.0) > 0.5 ? vec3(0.2, 0.24, 0.12) : vec3(0.18, 0.27, 0.45));
	vec3 cap = pick4(fract(cu.g * 4.7 + cu.a), vec3(0.05), top, vec3(0.9), vec3(0.08, 0.12, 0.3));
	vec3 skirt = pick4(fract(cu.r * 6.1 + cu.g), vec3(0.05), vec3(0.55, 0.06, 0.1), vec3(0.18, 0.27, 0.45), vec3(0.15, 0.15, 0.17));
	bool arm_part = (part > 0.5 && part < 2.5) || (part > 5.5 && part < 7.5);
	glow = 0.0;
	detail_col = hair_c * 0.8;
	if (grp < 0.5) {
		col = (topk == 2.0 && arm_part) ? jacket : top;
		detail_col = dot(top, vec3(0.33)) > 0.5 ? vec3(0.06) : vec3(0.92);
	} else if (grp < 1.5) {
		col = pants;
	} else if (grp < 2.5) {
		col = skin;
	} else if (grp < 3.5) {
		col = hair_c;
	} else if (grp < 4.5) {
		col = shoes;
	} else if (grp < 5.5) {
		col = vec3(1.0, 0.2, 0.5);
		glow = 1.0;
	} else if (grp < 6.5) {
		col = topk == 0.0 ? skin : (topk == 2.0 ? jacket : top);
	} else if (grp < 7.5) {
		col = bottom > 0.5 ? skin : pants;
	} else if (grp < 8.5) {
		col = shoes.r > 0.5 ? vec3(0.75) : vec3(0.92);
	} else if (grp < 9.5) {
		col = jacket;
	} else if (grp < 10.5) {
		col = cap;
	} else if (grp < 11.5) {
		col = vec3(0.03);
	} else if (grp < 12.5) {
		col = vec3(0.35, 0.6, 1.0);
		glow = 0.5;
	} else if (grp < 13.5) {
		col = skirt;
	} else if (grp < 14.5) {
		col = bottom > 0.5 ? skin : pants;
	} else if (grp < 15.5) {
		col = pick4(fract(cu.r * 4.9 + cu.a * 2.2), vec3(0.04), vec3(0.3, 0.17, 0.08), vec3(0.08, 0.16, 0.38), vec3(0.55, 0.1, 0.08));
	} else {
		col = vec3(0.02);
	}
	info = vec4(part, grp, topk, h5);
}

void fragment() {
	vec3 c = col;
	float part = info.x;
	float grp = info.y;
	float rough = 0.75;
	if (part > 4.5 && part < 5.5 && grp > 1.5 && grp < 2.5 && rest.z < -0.04 && abs(rest.y - 1.6) < 0.08) {
		// Gesicht: Augen, Brauen, Mund
		float ax = abs(rest.x) - 0.036;
		float eye = length(vec2(ax, (rest.y - 1.632) * 0.8));
		if (eye < 0.0115) {
			c = eye < 0.0065 ? vec3(0.03) : vec3(0.85);
		}
		if (abs(ax) < 0.022 && abs(rest.y - 1.658 - ax * ax * 4.0) < 0.0042) {
			c = detail_col;
		}
		if (abs(rest.x) < 0.022 && abs(rest.y - 1.572 + rest.x * rest.x * 3.0) < 0.004) {
			c = col * vec3(0.62, 0.4, 0.4);
		}
	}
	if (grp > 0.5 && grp < 1.5 && abs(rest.y - 0.975) < 0.012) {
		c *= 0.35;  // Gürtel
	}
	if (grp < 0.5 && part < 0.5 && rest.z < -0.06) {
		if (info.z == 1.0) {
			// Hoodie: Bauchtasche und Kordeln
			if (rest.y > 1.0 && rest.y < 1.1 && abs(rest.x) < 0.1) {
				c *= 0.82;
			}
			if (abs(abs(rest.x) - 0.035) < 0.005 && rest.y > 1.26 && rest.y < 1.4) {
				c = vec3(0.9);
			}
		} else if (info.z == 0.0 && info.w > 0.55) {
			// T-Shirt mit Aufdruck: Kreis oder Streifen
			if (info.w > 0.8 ? length(rest.xy - vec2(0.0, 1.24)) < 0.05 : abs(rest.y - 1.22) < 0.025) {
				c = detail_col;
			}
		}
	}
	if (grp > 8.5 && grp < 9.5) {
		rough = 0.5;  // Jacke (Leder, Nylon)
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	EMISSION = c * glow * 4.0 + c * 0.06;
}
