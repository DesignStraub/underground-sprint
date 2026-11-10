// eng.c – Motorschleifen aus echten Aufnahmen bauen (Werkzeug, nicht Teil des Spiels)
//
//   eng track  in.wav out.csv out.ppm FPR [RPM_MIN RPM_MAX]
//       verfolgt die Zündfrequenz (FPR = Zündungen je Umdrehung: 4-Zylinder 2, 6-Zylinder 3, Wankel 2 Scheiben 2)
//       über eine harmonische Summe im Spektrum und einen Viterbi-Pfad (keine Sprünge), schreibt Zeit, Drehzahl,
//       Güte, Pegel und Steigung je Rahmen und ein Spektrogramm mit eingezeichneter Spur (zur Kontrolle).
//   eng loops  in.wav in.csv outdir RPM,RPM,... [fpr=2] [oe=0.35] [h=0.8] [T0-T1 T0-T1 ...]
//       baut je Drehzahl eine Schleife "on" (Gas, Drehzahl steigt oder hält) und "off" (Schub, Drehzahl fällt):
//       sucht passende Abschnitte (±12 % um die Drehzahl), glättet ihre Tonhöhe auf genau diese Drehzahl
//       (Zeitachse folgt der gemessenen Phase, die Wellenform bleibt echt), hängt sie ausgerichtet aneinander und
//       schließt die Schleife nach einer ganzen Zahl von Arbeitsspielen (2 Umdrehungen) mit Überblendung.
//       Optional nur Abschnitte aus den angegebenen Zeitfenstern (Sekunden), z. B. ohne Musik im Vorspann.
//   eng fill   loopdir RPM,RPM,...   fehlende Schleifen aus der nächsten vorhandenen umtasten
//   eng finish loopdir outdir RPM,RPM,...  Pegel glätten, filtern, Pegel nach Drehzahl (fertig fürs Spiel)
//   eng xloop  in.wav out.wav START LEN XF RMS_DB   Geräusch (z. B. Reifenquietschen) als nahtlose Schleife
//   eng sweep  loopdir out.wav    Probefahrt mit den Schleifen, gemischt wie im Spiel (zum Anhören und Prüfen)
//
// Bauen: cc -O2 -o eng eng.c -lm
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SR 22050
#define NFFT 4096
#define HOP 256
#define NCAND_OCT 120

typedef struct { float *x; int n; int sr; } Wav;

static Wav wav_read(const char *p) {
	Wav w = {0};
	FILE *f = fopen(p, "rb");
	if (!f) { perror(p); exit(1); }
	unsigned char h[12];
	if (fread(h, 1, 12, f) != 12) exit(1);
	int ch = 1;
	for (;;) {
		unsigned char ck[8];
		if (fread(ck, 1, 8, f) != 8) break;
		uint32_t sz = ck[4] | ck[5] << 8 | ck[6] << 16 | (uint32_t)ck[7] << 24;
		if (!memcmp(ck, "fmt ", 4)) {
			unsigned char b[256];
			if (fread(b, 1, sz, f) != sz) exit(1);
			ch = b[2] | b[3] << 8;
			w.sr = b[4] | b[5] << 8 | b[6] << 16 | b[7] << 24;
		} else if (!memcmp(ck, "data", 4)) {
			int16_t *d = malloc(sz);
			size_t got = fread(d, 1, sz, f);
			w.n = (int)(got / 2 / ch);
			w.x = malloc(sizeof(float) * w.n);
			for (int i = 0; i < w.n; i++) w.x[i] = d[i * ch] / 32768.0f;
			free(d);
			break;
		} else fseek(f, sz + (sz & 1), SEEK_CUR);
	}
	fclose(f);
	return w;
}

static void wav_write(const char *p, const float *x, int n, int sr) {
	FILE *f = fopen(p, "wb");
	if (!f) { perror(p); exit(1); }
	uint32_t dsz = n * 2, rsz = 36 + dsz, fsz = 16, br = sr * 2;
	uint16_t fmt = 1, ch = 1, ba = 2, bits = 16;
	fwrite("RIFF", 1, 4, f); fwrite(&rsz, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f); fwrite(&fsz, 4, 1, f);
	fwrite(&fmt, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&sr, 4, 1, f); fwrite(&br, 4, 1, f);
	fwrite(&ba, 2, 1, f); fwrite(&bits, 2, 1, f); fwrite("data", 1, 4, f); fwrite(&dsz, 4, 1, f);
	for (int i = 0; i < n; i++) {
		float v = x[i] * 32767.0f;
		if (v > 32767) v = 32767;
		if (v < -32768) v = -32768;
		int16_t s = (int16_t)lrintf(v);
		fwrite(&s, 2, 1, f);
	}
	fclose(f);
}

// --- FFT (radix 2) ----------------------------------------------------------
static void fft(float *re, float *im, int n) {
	for (int i = 1, j = 0; i < n; i++) {
		int bit = n >> 1;
		for (; j & bit; bit >>= 1) j ^= bit;
		j ^= bit;
		if (i < j) { float t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
	}
	for (int len = 2; len <= n; len <<= 1) {
		double a = -2 * M_PI / len;
		float wr = cos(a), wi = sin(a);
		for (int i = 0; i < n; i += len) {
			float cr = 1, ci = 0;
			for (int k = 0; k < len / 2; k++) {
				float ur = re[i + k], ui = im[i + k];
				float vr = re[i + k + len / 2] * cr - im[i + k + len / 2] * ci;
				float vi = re[i + k + len / 2] * ci + im[i + k + len / 2] * cr;
				re[i + k] = ur + vr; im[i + k] = ui + vi;
				re[i + k + len / 2] = ur - vr; im[i + k + len / 2] = ui - vi;
				float t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
			}
		}
	}
}

static float interp(const float *a, int n, float pos) {
	if (pos < 0 || pos >= n - 1) return 0;
	int i = (int)pos;
	float t = pos - i;
	return a[i] * (1 - t) + a[i + 1] * t;
}

// --- Spur -------------------------------------------------------------------
typedef struct { float t, f, rpm, score, db, slope; } Frame;

static int cmd_track(int argc, char **argv) {
	if (argc < 6) return 1;
	Wav w = wav_read(argv[2]);
	float fpr = atof(argv[5]);
	float rmin = argc > 6 ? atof(argv[6]) : 650, rmax = argc > 7 ? atof(argv[7]) : 9800;
	float fmin = rmin * fpr / 60, fmax = rmax * fpr / 60;
	int nc = (int)(log2(fmax / fmin) * NCAND_OCT) + 1;
	int nf = (w.n - NFFT) / HOP + 1;
	float *cand = malloc(sizeof(float) * nc);
	for (int i = 0; i < nc; i++) cand[i] = fmin * powf(2, (float)i / NCAND_OCT);
	float *score = malloc(sizeof(float) * (size_t)nf * nc);
	float *db = malloc(sizeof(float) * nf);
	int nb = NFFT / 2;
	float *spec = malloc(sizeof(float) * (size_t)nf * 256);  // für das Bild: 0..1200 Hz in 256 Zeilen
	float re[NFFT], im[NFFT], lm[NFFT / 2], env[NFFT / 2], pk[NFFT / 2], win[NFFT];
	for (int i = 0; i < NFFT; i++) win[i] = 0.5f - 0.5f * cosf(2 * M_PI * i / NFFT);
	float df = (float)w.sr / NFFT;
	int ew = (int)(70 / df);
	for (int fr = 0; fr < nf; fr++) {
		const float *x = w.x + (size_t)fr * HOP;
		double e = 0;
		for (int i = 0; i < NFFT; i++) { re[i] = x[i] * win[i]; im[i] = 0; e += x[i] * x[i]; }
		db[fr] = 10 * log10(e / NFFT + 1e-12);
		fft(re, im, NFFT);
		for (int k = 0; k < nb; k++) lm[k] = logf(sqrtf(re[k] * re[k] + im[k] * im[k]) + 1e-6f);
		// Hüllkurve (gleitender Mittelwert) abziehen: nur Spitzen über dem Rauschen zählen
		double acc = 0;
		int a0 = 0, a1 = 0;
		for (int k = 0; k < nb; k++) {
			while (a1 < nb && a1 <= k + ew) acc += lm[a1++];
			while (a0 < k - ew) acc -= lm[a0++];
			env[k] = acc / (a1 - a0);
			pk[k] = lm[k] - env[k];
			if (pk[k] < 0) pk[k] = 0;
		}
		for (int r = 0; r < 256; r++) spec[(size_t)fr * 256 + r] = interp(lm, nb, (r + 0.5f) * 1200.0f / 256 / df);
		for (int c = 0; c < nc; c++) {
			float f = cand[c], s = 0, si = 0, wsum = 0, wk = 1;
			int K = (int)(2600 / f);
			if (K > 14) K = 14;
			if (K < 2) K = 2;
			for (int k = 1; k <= K; k++) {
				s += wk * interp(pk, nb, k * f / df);
				si += wk * interp(pk, nb, (k - 0.5f) * f / df);
				wsum += wk;
				wk *= 0.88f;
			}
			score[(size_t)fr * nc + c] = (s - 0.45f * si) / wsum;
		}
	}
	// Viterbi: höchste Summe, Sprünge je Rahmen höchstens J Stufen (±4 %), kleine Strafe je Stufe
	int J = (int)(log2(1.04) * NCAND_OCT) + 1;
	float *acc = malloc(sizeof(float) * nc), *nacc = malloc(sizeof(float) * nc);
	signed char *bp = malloc((size_t)nf * nc);
	for (int c = 0; c < nc; c++) acc[c] = score[c];
	for (int fr = 1; fr < nf; fr++) {
		for (int c = 0; c < nc; c++) {
			float best = -1e30f;
			int bj = 0;
			for (int j = -J; j <= J; j++) {
				int p = c + j;
				if (p < 0 || p >= nc) continue;
				float v = acc[p] - 0.012f * abs(j);
				if (v > best) { best = v; bj = j; }
			}
			nacc[c] = best + score[(size_t)fr * nc + c];
			bp[(size_t)fr * nc + c] = (signed char)bj;
		}
		float m = -1e30f;
		for (int c = 0; c < nc; c++) if (nacc[c] > m) m = nacc[c];
		for (int c = 0; c < nc; c++) acc[c] = nacc[c] - m;
	}
	int *path = malloc(sizeof(int) * nf);
	int bc = 0;
	for (int c = 1; c < nc; c++) if (acc[c] > acc[bc]) bc = c;
	for (int fr = nf - 1; fr >= 0; fr--) {
		path[fr] = bc;
		if (fr > 0) bc += bp[(size_t)fr * nc + bc];
	}
	// Oktavfehler: Die Zündfrequenz trägt die stärksten Obertöne, halbe Ordnungen (Ungleichheiten zwischen den
	// Zylindern) sind schwächer. Sind die ungeraden Vielfachen der Spur kaum da, ist die Spur eine halbe Ordnung
	// (verdoppeln). Liegen zwischen den Obertönen fast gleich starke Spitzen, war es das Doppelte (halbieren).
	// Entscheidung über 1,5 s geglättet, damit eine Aufnahme nicht ständig springt.
	int *oct = malloc(sizeof(int) * nf);
	{
		float *ratio_oe = malloc(sizeof(float) * nf), *ratio_h = malloc(sizeof(float) * nf);
		for (int fr = 0; fr < nf; fr++) {
			const float *x = w.x + (size_t)fr * HOP;
			for (int i = 0; i < NFFT; i++) { re[i] = x[i] * win[i]; im[i] = 0; }
			fft(re, im, NFFT);
			for (int k = 0; k < nb; k++) lm[k] = logf(sqrtf(re[k] * re[k] + im[k] * im[k]) + 1e-6f);
			double acc2 = 0;
			int a0 = 0, a1 = 0;
			for (int k = 0; k < nb; k++) {
				while (a1 < nb && a1 <= k + ew) acc2 += lm[a1++];
				while (a0 < k - ew) acc2 -= lm[a0++];
				pk[k] = lm[k] - acc2 / (a1 - a0);
				if (pk[k] < 0) pk[k] = 0;
			}
			float f = cand[path[fr]], so = 0, se = 0, sh = 0, sk = 0;
			for (int k = 1; k <= 8; k++) {
				if (k * f > 2600) break;
				float v = interp(pk, nb, k * f / df);
				if (k & 1) so += v; else se += v;
				sk += v;
				sh += interp(pk, nb, (k - 0.5f) * f / df);
			}
			ratio_oe[fr] = so / (se + 1e-3f);
			ratio_h[fr] = sh / (sk + 1e-3f);
		}
		int R = (int)(0.75f * w.sr / HOP);
		for (int fr = 0; fr < nf; fr++) {
			double moe = 0, mh = 0;
			int c = 0;
			for (int k = fr - R; k <= fr + R; k++) {
				if (k < 0 || k >= nf) continue;
				moe += ratio_oe[k]; mh += ratio_h[k]; c++;
			}
			moe /= c; mh /= c;
			oct[fr] = mh > 0.75 ? -1 : (moe < 0.4 ? 1 : 0);
		}
		free(ratio_oe); free(ratio_h);
	}
	float *fsel = malloc(sizeof(float) * nf);
	int nd = 0, nh = 0;
	for (int fr = 0; fr < nf; fr++) {
		fsel[fr] = cand[path[fr]] * (oct[fr] > 0 ? 2.0f : oct[fr] < 0 ? 0.5f : 1.0f);
		nd += oct[fr] > 0; nh += oct[fr] < 0;
	}
	fprintf(stderr, "verdoppelt %d, halbiert %d von %d\n", nd, nh, nf);
	FILE *o = fopen(argv[3], "w");
	fprintf(o, "t,f,rpm,score,db,slope\n");
	for (int fr = 0; fr < nf; fr++) {
		int a = fr - 6 < 0 ? 0 : fr - 6, b = fr + 6 >= nf ? nf - 1 : fr + 6;
		float ra = fsel[a] * 60 / fpr, rb = fsel[b] * 60 / fpr;
		float slope = (rb - ra) / ((b - a) * (float)HOP / w.sr + 1e-6f);
		// beim Oktavwechsel ist die Steigung sinnlos: dort nicht verwenden
		int jump = oct[a] != oct[b];
		fprintf(o, "%.4f,%.3f,%.1f,%.4f,%.2f,%.0f\n", (fr * HOP + NFFT / 2) / (float)w.sr, fsel[fr],
			fsel[fr] * 60 / fpr, jump ? -1.0f : score[(size_t)fr * nc + path[fr]], db[fr], slope);
	}
	fclose(o);
	// Bild: Spektrogramm 0..1200 Hz, Spur rot (Zündfrequenz) und gelb (doppelt)
	int W = nf < 2400 ? nf : 2400, H = 256;
	FILE *pp = fopen(argv[4], "wb");
	fprintf(pp, "P6 %d %d 255\n", W, H);
	unsigned char *img = calloc((size_t)W * H * 3, 1);
	float mx = -1e9f;
	for (size_t i = 0; i < (size_t)nf * 256; i++) if (spec[i] > mx) mx = spec[i];
	for (int xg = 0; xg < W; xg++) {
		int fr = (int)((long)xg * nf / W);
		for (int r = 0; r < H; r++) {
			float v = (spec[(size_t)fr * 256 + r] - mx + 9) / 9;
			if (v < 0) v = 0;
			if (v > 1) v = 1;
			unsigned char g = (unsigned char)(v * 220);
			unsigned char *px = img + ((size_t)(H - 1 - r) * W + xg) * 3;
			px[0] = px[1] = px[2] = g;
		}
		for (int m = 1; m <= 2; m++) {
			int r = (int)(fsel[fr] * m / 1200.0f * H);
			if (r >= 0 && r < H) {
				unsigned char *px = img + ((size_t)(H - 1 - r) * W + xg) * 3;
				px[0] = 255; px[1] = m == 1 ? 40 : 220; px[2] = 0;
			}
		}
	}
	fwrite(img, 1, (size_t)W * H * 3, pp);
	fclose(pp);
	fprintf(stderr, "%d Rahmen, %d Kandidaten\n", nf, nc);
	return 0;
}


// Spektrum einer ganzen Schleife: Stärke der Obertöne der Zündfrequenz F, ungerade gegen gerade Vielfache und
// die halben Lagen dazwischen (je über dem Rauschen gemessen)
static void loop_ratios(const float *x, int n, double F, double *oe, double *hr) {
	int N = 1;
	while (N < n && N < (1 << 17)) N <<= 1;
	float *re = calloc(N, sizeof(float)), *im = calloc(N, sizeof(float));
	int m = n < N ? n : N;
	for (int i = 0; i < m; i++) re[i] = x[i] * (0.5f - 0.5f * cosf(2 * M_PI * i / m));
	fft(re, im, N);
	int nb = N / 2;
	float *lm = malloc(sizeof(float) * nb), *pk = malloc(sizeof(float) * nb);
	for (int k = 0; k < nb; k++) lm[k] = logf(sqrtf(re[k] * re[k] + im[k] * im[k]) + 1e-6f);
	float df = (float)SR / N;
	int ew = (int)(F * 0.35 / df) + 1;
	double acc = 0;
	int a0 = 0, a1 = 0;
	for (int k = 0; k < nb; k++) {
		while (a1 < nb && a1 <= k + ew) acc += lm[a1++];
		while (a0 < k - ew) acc -= lm[a0++];
		pk[k] = lm[k] - acc / (a1 - a0);
		if (pk[k] < 0) pk[k] = 0;
	}
	// Spitze in einem kleinen Fenster um die Lage suchen (Schleifen sind exakt periodisch, aber Fenster verschmiert)
	double so = 0, se = 0, sh = 0, sk = 0;
	for (int k = 1; k <= 8; k++) {
		if (k * F > 2600) break;
		float best = 0, bh = 0;
		for (int d = -2; d <= 2; d++) {
			int b = (int)lround(k * F / df) + d, c = (int)lround((k - 0.5) * F / df) + d;
			if (b > 0 && b < nb && pk[b] > best) best = pk[b];
			if (c > 0 && c < nb && pk[c] > bh) bh = pk[c];
		}
		if (k & 1) so += best; else se += best;
		sk += best;
		sh += bh;
	}
	*oe = so / (se + 1e-3);
	*hr = sh / (sk + 1e-3);
	free(re); free(im); free(lm); free(pk);
}

// --- Lücken füllen --------------------------------------------------------------
// fehlende Schleifen aus der nächsten vorhandenen (gleiche Last, sonst die andere) per Umtasten erzeugen;
// die Schleife bleibt nahtlos, weil sie als Ganzes auf die neue Länge gerechnet wird
static int cmd_fill(int argc, char **argv) {
	if (argc < 4) return 1;
	const char *dir = argv[2];
	char buf[512];
	strncpy(buf, argv[3], sizeof buf - 1);
	double rp[32];
	int nr = 0;
	for (char *t = strtok(buf, ","); t && nr < 32; t = strtok(NULL, ",")) rp[nr++] = atof(t);
	int have[2][32];
	for (int l = 0; l < 2; l++)
		for (int i = 0; i < nr; i++) {
			char p[1024];
			snprintf(p, sizeof p, "%s/%s_%d.wav", dir, l ? "off" : "on", (int)rp[i]);
			FILE *f = fopen(p, "rb");
			have[l][i] = f != NULL;
			if (f) fclose(f);
		}
	for (int l = 0; l < 2; l++)
		for (int i = 0; i < nr; i++) {
			if (have[l][i]) continue;
			// nächste vorhandene: erst gleiche Last, dann die andere; kleinster Abstand in log(Drehzahl)
			int bl = -1, bi = -1;
			double bd = 1e9;
			for (int pass = 0; pass < 2 && bi < 0; pass++) {
				int ll = pass == 0 ? l : 1 - l;
				for (int j = 0; j < nr; j++) {
					if (!have[ll][j]) continue;
					double d = fabs(log(rp[j] / rp[i]));
					if (d < bd) { bd = d; bi = j; bl = ll; }
				}
			}
			if (bi < 0) continue;
			char src[1024], dst[1024];
			snprintf(src, sizeof src, "%s/%s_%d.wav", dir, bl ? "off" : "on", (int)rp[bi]);
			snprintf(dst, sizeof dst, "%s/%s_%d.wav", dir, l ? "off" : "on", (int)rp[i]);
			Wav w = wav_read(src);
			int cs = (int)lround(SR * 120.0 / rp[bi]), cd = (int)lround(SR * 120.0 / rp[i]);
			int M = w.n / cs;
			int n = M * cd;
			float *y = malloc(sizeof(float) * n);
			for (int k = 0; k < n; k++) {
				double pos = (double)k * cs / cd;
				// kreisförmig interpolieren (nahtlos)
				int i0 = (int)floor(pos);
				double fr = pos - i0, s = 0, ws = 0;
				for (int q = -3; q <= 4; q++) {
					int ii = ((i0 + q) % w.n + w.n) % w.n;
					double d = q - fr;
					double sc = fabs(d) < 1e-9 ? 1 : sin(M_PI * d) / (M_PI * d);
					double wn = 0.5 + 0.5 * cos(M_PI * d / 4.5);
					s += w.x[ii] * sc * wn;
					ws += sc * wn;
				}
				y[k] = (float)(s / ws);
			}
			wav_write(dst, y, n, SR);
			fprintf(stderr, "gefüllt %s_%d aus %s_%d (Faktor %.2f)\\n", l ? "off" : "on", (int)rp[i], bl ? "off" : "on", (int)rp[bi], (double)cs / cd);
			free(y);
		}
	return 0;
}

// --- Schleifen ----------------------------------------------------------------
static Frame *read_track(const char *p, int *n) {
	FILE *f = fopen(p, "r");
	if (!f) { perror(p); exit(1); }
	char line[256];
	int cap = 1 << 16, k = 0;
	Frame *fr = malloc(sizeof(Frame) * cap);
	if (!fgets(line, sizeof line, f)) exit(1);
	while (fgets(line, sizeof line, f)) {
		if (k == cap) { cap *= 2; fr = realloc(fr, sizeof(Frame) * cap); }
		sscanf(line, "%f,%f,%f,%f,%f,%f", &fr[k].t, &fr[k].f, &fr[k].rpm, &fr[k].score, &fr[k].db, &fr[k].slope);
		k++;
	}
	fclose(f);
	*n = k;
	return fr;
}

// 8-Punkt-Interpolation (gefensterter Sinc)
static float sinc_at(const float *x, int n, double pos) {
	int i0 = (int)floor(pos);
	double fr = pos - i0;
	double s = 0, ws = 0;
	for (int k = -3; k <= 4; k++) {
		int i = i0 + k;
		if (i < 0 || i >= n) continue;
		double d = k - fr;
		double sc = fabs(d) < 1e-9 ? 1 : sin(M_PI * d) / (M_PI * d);
		double wn = 0.5 + 0.5 * cos(M_PI * d / 4.5);
		s += x[i] * sc * wn;
		ws += sc * wn;
	}
	return ws != 0 ? (float)(s / ws) : 0;
}

typedef struct { int a, b; float q; } Run;

static int cmp_run(const void *x, const void *y) {
	float d = ((const Run *)y)->q - ((const Run *)x)->q;
	return d > 0 ? 1 : d < 0 ? -1 : 0;
}

// Abschnitt [a,b] (Rahmen) auf die Drehzahl R glätten: Zeitachse folgt der gemessenen Phase
static float *flatten(const Wav *w, const Frame *fr, int a, int b, double R, int *outn) {
	int n = b - a + 1;
	double *ph = malloc(sizeof(double) * n);  // Arbeitsspiele (2 Umdrehungen) seit Rahmen a
	double dt = (double)HOP / w->sr;
	ph[0] = 0;
	for (int i = 1; i < n; i++) ph[i] = ph[i - 1] + 0.5 * (fr[a + i - 1].rpm + fr[a + i].rpm) / 120.0 * dt;
	double cyc = R / 120.0;  // Arbeitsspiele je Sekunde am Ausgang
	int m = (int)(ph[n - 1] / cyc * w->sr);
	float *y = malloc(sizeof(float) * (m + 1));
	int seg = 0;
	for (int j = 0; j < m; j++) {
		double target = j / (double)w->sr * cyc;
		while (seg < n - 2 && ph[seg + 1] < target) seg++;
		double u = (target - ph[seg]) / (ph[seg + 1] - ph[seg] + 1e-12);
		double t = fr[a + seg].t + (u + 0) * dt;
		y[j] = sinc_at(w->x, w->n, t * w->sr);
	}
	free(ph);
	*outn = m;
	return y;
}

static double ncc(const float *a, const float *b, int n) {
	double s = 0, ea = 0, eb = 0;
	for (int i = 0; i < n; i++) { s += a[i] * b[i]; ea += a[i] * a[i]; eb += b[i] * b[i]; }
	return s / sqrt(ea * eb + 1e-12);
}

static int cmd_loops(int argc, char **argv) {
	if (argc < 6) return 1;
	Wav w = wav_read(argv[2]);
	int nf;
	Frame *fr = read_track(argv[3], &nf);
	const char *outdir = argv[4];
	// erlaubte Zeitfenster
	float win0[32], win1[32];
	int nw = 0;
	double fpr = 2, oe_min = 0.35, h_max = 0.8;
	for (int i = 6; i < argc; i++) {
		if (!strncmp(argv[i], "fpr=", 4)) fpr = atof(argv[i] + 4);
		else if (!strncmp(argv[i], "oe=", 3)) oe_min = atof(argv[i] + 3);
		else if (!strncmp(argv[i], "h=", 2)) h_max = atof(argv[i] + 2);
		else if (nw < 32 && sscanf(argv[i], "%f-%f", &win0[nw], &win1[nw]) == 2) nw++;
	}
	// Schwellen: Güte über dem 35. Perzentil, Pegel höchstens 32 dB unter dem lautesten Rahmen
	float maxdb = -200;
	for (int i = 0; i < nf; i++) if (fr[i].db > maxdb) maxdb = fr[i].db;
	float *sc = malloc(sizeof(float) * nf);
	int ns = 0;
	for (int i = 0; i < nf; i++) if (fr[i].db > maxdb - 32) sc[ns++] = fr[i].score;
	for (int i = 1; i < ns; i++) for (int j = i; j > 0 && sc[j - 1] > sc[j]; j--) { float t = sc[j]; sc[j] = sc[j - 1]; sc[j - 1] = t; }
	float qthr = ns ? sc[(int)(ns * 0.35)] : 0;
	char *list = argv[5];
	char buf[512];
	strncpy(buf, list, sizeof buf - 1);
	for (char *tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
		double nom = atof(tok);
		int cyc_len = (int)lround(SR * 120.0 / nom);
		double R = SR * 120.0 / cyc_len;  // genaue Drehzahl: ein Arbeitsspiel = ganze Zahl Samples
		for (int load = 0; load < 2; load++) {
			// passende Rahmen
			Run *runs = malloc(sizeof(Run) * nf);
			int nr = 0, i = 0;
			while (i < nf) {
				int ok = 1;
				Frame *f = &fr[i];
				if (fabs(log(f->rpm / R)) > log(1.12)) ok = 0;
				if (f->score < qthr || f->db < maxdb - 32) ok = 0;
				if (nw) {
					int in = 0;
					for (int k = 0; k < nw; k++) if (f->t >= win0[k] && f->t <= win1[k]) in = 1;
					if (!in) ok = 0;
				}
				if (nom > 1000) {
					if (load == 0 && f->slope < -250) ok = 0;   // Gas: steigt oder hält
					if (load == 1 && f->slope > -120) ok = 0;   // Schub: fällt
				}
				if (!ok) { i++; continue; }
				int a = i;
				while (i < nf) {
					Frame *g = &fr[i];
					int ok2 = fabs(log(g->rpm / R)) <= log(1.12) && g->score >= qthr * 0.8 && g->db >= maxdb - 34;
					if (nom > 1000) {
						if (load == 0 && g->slope < -350) ok2 = 0;
						if (load == 1 && g->slope > -60) ok2 = 0;
					}
					if (!ok2) break;
					i++;
				}
				int b = i - 1;
				float dur = (b - a + 1) * (float)HOP / w.sr;
				if (dur * R / 120.0 >= 3) {  // mindestens 3 Arbeitsspiele
					float q = 0, lv = 0;
					for (int k = a; k <= b; k++) { q += fr[k].score; lv += fr[k].db; }
					q /= (b - a + 1);
					lv /= (b - a + 1);
					runs[nr].a = a;
					runs[nr].b = b;
					runs[nr].q = q * sqrtf(dur) * powf(10, (lv - maxdb) / 40);
					nr++;
				}
			}
			qsort(runs, nr, sizeof(Run), cmp_run);
			// Abschnitte aneinanderhängen, bis die Schleife lang genug ist (ca. 1,2 s, mindestens 8 Arbeitsspiele)
			int want = (int)(1.2 * SR);
			if (want < 8 * cyc_len) want = 8 * cyc_len;
			int X = cyc_len < SR / 25 ? SR / 25 : cyc_len;  // Überblendung
			if (X > SR / 6) X = SR / 6;
			float *seq = calloc(want * 3 + X * 4 + SR * 4, sizeof(float));
			int len = 0, used = 0;
			for (int r = 0; r < nr && len < want + X * 2; r++) {
				int m;
				float *y = flatten(&w, fr, runs[r].a, runs[r].b, R, &m);
				if (m < X * 2) { free(y); continue; }
				double e = 0;
				for (int k = 0; k < m; k++) e += y[k] * y[k];
				float g = 0.25f / sqrtf(e / m + 1e-9f);
				for (int k = 0; k < m; k++) y[k] *= g;
				if (len == 0) {
					memcpy(seq, y, sizeof(float) * m);
					len = m;
				} else {
					// Anfang von y so verschieben, dass er zum Ende von seq passt
					int best = 0;
					double bv = -2;
					for (int off = 0; off < cyc_len && off + X < m; off++) {
						double v = ncc(seq + len - X, y + off, X);
						if (v > bv) { bv = v; best = off; }
					}
					int start = len - X;
					for (int k = 0; k < m - best; k++) {
						float v = y[best + k];
						if (k < X) {
							float t = (float)k / X;
							seq[start + k] = seq[start + k] * (1 - t) + v * t;
						} else seq[start + k] = v;
					}
					len = start + m - best;
				}
				used++;
				free(y);
				if (len > want * 3) break;
			}
			if (len < X * 3) {
				fprintf(stderr, "%s %d: zu wenig Material\n", load ? "off" : "on", (int)nom);
				free(seq);
				free(runs);
				continue;
			}
			if (len < (int)(0.5 * SR) || (used < 2 && len < (int)(0.9 * SR))) {
				fprintf(stderr, "%s %5d: zu wenig Material (%.2f s aus %d Abschnitten)\n", load ? "off" : "on", (int)nom, len / (float)SR, used);
				free(seq);
				free(runs);
				continue;
			}
			int M = (len - X) / cyc_len;
			int Mw = want / cyc_len;
			if (M > Mw) M = Mw;
			if (M < 1) M = 1;
			int L = M * cyc_len;
			float *loop = malloc(sizeof(float) * L);
			for (int k = 0; k < L; k++) {
				float v = seq[k];
				if (k < X && L + k < len) {
					float t = (float)k / X;
					v = seq[L + k] * (1 - t) + seq[k] * t;
				}
				loop[k] = v;
			}
			// Oktav-Prüfung: Obertöne der Zündfrequenz F (k*F) gegen die halben Lagen ((k-0.5)*F) und ungerade gegen gerade k
			double oe, hr;
			loop_ratios(loop, L, R * fpr / 60.0, &oe, &hr);
			const char *bad = (oe < oe_min || hr > h_max) ? "  VERWORFEN" : "";
			fprintf(stderr, "%s %5d: %d Abschnitte, %d Arbeitsspiele, %.2f s, Läufe %d, ungerade/gerade %.2f, halbe %.2f%s\n",
				load ? "off" : "on", (int)nom, used, M, L / (float)SR, nr, oe, hr, bad);
			if (!*bad) {
				char p[1024];
				snprintf(p, sizeof p, "%s/%s_%d.wav", outdir, load ? "off" : "on", (int)nom);
				wav_write(p, loop, L, SR);
			}
			free(loop);
			free(seq);
			free(runs);
		}
	}
	return 0;
}


// --- Probefahrt ---------------------------------------------------------------
// Mischt die Schleifen eines Ordners wie engine_audio.gd: die zwei Drehzahlen um die echte herum gleich laut
// überblendet (log. Drehzahl), Gas und Schub ebenso, jede Schleife per Abspieltempo auf die echte Drehzahl gezogen.
static const double RPMS[] = {900, 1300, 1850, 2500, 3250, 4100, 5000, 6100, 7400};
#define NR 9

static double exact_rpm(double nom) { return SR * 120.0 / lround(SR * 120.0 / nom); }

static int cmd_sweep(int argc, char **argv) {
	if (argc < 4) return 1;
	Wav lp[2][NR];
	for (int l = 0; l < 2; l++)
		for (int i = 0; i < NR; i++) {
			char p[1024];
			snprintf(p, sizeof p, "%s/%s_%d.wav", argv[2], (l == 0 || i == 0) ? "on" : "off", (int)RPMS[i]);
			FILE *t = fopen(p, "rb");
			if (!t) { lp[l][i].n = 0; continue; }
			fclose(t);
			lp[l][i] = wav_read(p);
		}
	// Ablauf: Leerlauf, Vollgas im 2. Gang, Schalten, 3. Gang, Gas weg (Schub), Leerlauf
	double T = 12.0;
	int n = (int)(T * SR);
	float *out = calloc(n, sizeof(float));
	double pos[2][NR] = {{0}};
	double rpm = 900, load = 0;
	for (int j = 0; j < n; j++) {
		double t = (double)j / SR;
		double want_rpm, want_load;
		if (t < 1.5) { want_rpm = 900; want_load = 0.15; }
		else if (t < 5.0) { want_rpm = 900 + (7200 - 900) * pow((t - 1.5) / 3.5, 0.8); want_load = 1; }
		else if (t < 5.15) { want_rpm = 7200 - (7200 - 5000) * (t - 5.0) / 0.15; want_load = 0; }
		else if (t < 8.5) { want_rpm = 5000 + 2300 * (t - 5.15) / 3.35; want_load = 1; }
		else if (t < 10.8) { want_rpm = 7300 - (7300 - 1000) * pow((t - 8.5) / 2.3, 0.7); want_load = 0; }
		else { want_rpm = 900; want_load = 0.15; }
		rpm = want_rpm;
		load += (want_load - load) * (want_load > load ? 9.0 : 6.0) / SR * 3;
		if (load < 0) load = 0;
		if (load > 1) load = 1;
		double r = rpm;
		int i = 0;
		while (i < NR - 2 && r > RPMS[i + 1]) i++;
		double u = log(r / RPMS[i]) / log(RPMS[i + 1] / RPMS[i]);
		if (u < 0) u = 0;
		if (u > 1) u = 1;
		double wl[2] = {cos(u * M_PI / 2), sin(u * M_PI / 2)};
		double gl[2] = {sin(load * M_PI / 2), cos(load * M_PI / 2)};
		double acc = 0;
		for (int l = 0; l < 2; l++)
			for (int q = 0; q < 2; q++) {
				int k = i + q;
				Wav *w = &lp[l][k];
				if (w->n == 0) continue;
				double pitch = r / exact_rpm(RPMS[k]);
				double ps = pos[l][k];
				int i0 = (int)ps;
				double fr = ps - i0;
				float a = w->x[i0 % w->n], b = w->x[(i0 + 1) % w->n];
				acc += (a + (b - a) * fr) * wl[q] * gl[l];
				ps += pitch;
				while (ps >= w->n) ps -= w->n;
				pos[l][k] = ps;
			}
		out[j] = (float)acc;
	}
	float mx = 0;
	for (int j = 0; j < n; j++) if (fabsf(out[j]) > mx) mx = fabsf(out[j]);
	for (int j = 0; j < n; j++) out[j] *= 0.9f / (mx + 1e-9f);
	wav_write(argv[3], out, n, SR);
	return 0;
}

// --- Geräusch-Schleife ------------------------------------------------------------
// eng xloop in.wav out.wav START LEN XF RMS_DB: Ausschnitt START..START+LEN (s) als nahtlose Schleife, das Ende wird
// über XF Sekunden in den Anfang geblendet (gleiche Leistung, für rauschartige Klänge), Pegel auf RMS_DB
static int cmd_xloop(int argc, char **argv) {
	if (argc < 8) return 1;
	Wav w = wav_read(argv[2]);
	int s0 = (int)(atof(argv[4]) * w.sr), len = (int)(atof(argv[5]) * w.sr), xf = (int)(atof(argv[6]) * w.sr);
	double target = pow(10, atof(argv[7]) / 20);
	if (s0 + len + xf > w.n) { fprintf(stderr, "zu kurz\n"); return 1; }
	float *y = malloc(sizeof(float) * len);
	for (int i = 0; i < len; i++) {
		float v = w.x[s0 + i];
		if (i < xf) {
			double t = (double)i / xf;
			v = (float)(w.x[s0 + i] * sqrt(t) + w.x[s0 + len + i] * sqrt(1 - t));
		}
		y[i] = v;
	}
	double e = 0;
	for (int i = 0; i < len; i++) e += y[i] * y[i];
	double g = target / sqrt(e / len + 1e-12);
	for (int i = 0; i < len; i++) y[i] *= g;
	wav_write(argv[3], y, len, w.sr);
	return 0;
}

// --- Fertigstellen ----------------------------------------------------------------
// eng finish loopdir outdir RPM,RPM,...: je Schleife (kreisförmig, also nahtlos)
//   1. langsame Pegelglättung: der Pegel über ca. 0,15 s wird zu 70 % auf den Mittelwert gezogen. Sonst hört man
//      Lautstärkeschwankungen der Aufnahme (vorbeifahrend, Kamera dreht sich) bei jedem Durchlauf als Pumpen.
//   2. Hochpass 30 Hz (Rumpeln, Gleichanteil) und Tiefpass 8 kHz (Wind- und Kratzanteile der Aufnahme)
//   3. Pegel nach Drehzahl: Gas von -19 dB (Leerlauf) bis -14 dB (ab 5000/min), Schub 6 dB leiser
static void biquad(float *x, int n, double b0, double b1, double b2, double a1, double a2) {
	double z1 = 0, z2 = 0;
	for (int i = 0; i < n; i++) {
		double in = x[i], out = b0 * in + z1;
		z1 = b1 * in - a1 * out + z2;
		z2 = b2 * in - a2 * out;
		x[i] = (float)out;
	}
}

static void filt_circular(float *x, int n, int hp, double fc) {
	// dreimal hintereinander filtern und die mittlere Kopie nehmen: Einschwingen fällt weg, Anfang passt zum Ende
	float *t = malloc(sizeof(float) * n * 3);
	for (int k = 0; k < 3; k++) memcpy(t + k * n, x, sizeof(float) * n);
	double w0 = 2 * M_PI * fc / SR, c = cos(w0), al = sin(w0) / (2 * 0.7071);
	double a0 = 1 + al;
	if (hp) biquad(t, 3 * n, (1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, -2 * c / a0, (1 - al) / a0);
	else biquad(t, 3 * n, (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0, -2 * c / a0, (1 - al) / a0);
	memcpy(x, t + n, sizeof(float) * n);
	free(t);
}

static int cmd_finish(int argc, char **argv) {
	if (argc < 5) return 1;
	char buf[512];
	strncpy(buf, argv[4], sizeof buf - 1);
	for (char *tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
		double r = atof(tok);
		for (int l = 0; l < 2; l++) {
			if (l == 1 && r < 1000) continue;  // Leerlauf: nur eine Schleife
			char p[1024];
			snprintf(p, sizeof p, "%s/%s_%d.wav", argv[2], l ? "off" : "on", (int)r);
			FILE *f = fopen(p, "rb");
			if (!f) { fprintf(stderr, "fehlt: %s\n", p); continue; }
			fclose(f);
			Wav w = wav_read(p);
			int n = w.n;
			// 1. Pegelglättung (kreisförmig)
			int W = (int)(0.15 * SR);
			if (W > n / 2) W = n / 2;
			double *e = malloc(sizeof(double) * n);
			double acc = 0;
			for (int i = -W / 2; i < W / 2; i++) { float v = w.x[(i + n) % n]; acc += v * v; }
			for (int i = 0; i < n; i++) {
				e[i] = acc / W;
				float vo = w.x[((i - W / 2) % n + n) % n], vi = w.x[(i + W / 2) % n];
				acc += vi * vi - vo * vo;
			}
			double mean = 0;
			for (int i = 0; i < n; i++) mean += w.x[i] * w.x[i];
			mean /= n;
			for (int i = 0; i < n; i++) {
				double g = sqrt(mean / (e[i] + 1e-12));
				w.x[i] *= (float)pow(g, 0.7);
			}
			free(e);
			// 2. Filter
			filt_circular(w.x, n, 1, 30);
			filt_circular(w.x, n, 0, 8000);
			// 3. Pegel
			double k = log(r / 900) / log(5000.0 / 900);
			if (k > 1) k = 1;
			double db = -19 + 5 * k - (l ? 6 : 0);
			double ms = 0;
			for (int i = 0; i < n; i++) ms += w.x[i] * w.x[i];
			double g = pow(10, db / 20) / sqrt(ms / n + 1e-12);
			float pk = 0;
			for (int i = 0; i < n; i++) { w.x[i] *= (float)g; if (fabsf(w.x[i]) > pk) pk = fabsf(w.x[i]); }
			if (pk > 0.97f) for (int i = 0; i < n; i++) w.x[i] *= 0.97f / pk;  // nie übersteuern
			snprintf(p, sizeof p, "%s/%s_%d.wav", argv[3], l ? "off" : "on", (int)r);
			wav_write(p, w.x, n, SR);
			free(w.x);
		}
	}
	return 0;
}

int main(int argc, char **argv) {
	if (argc < 2) return 1;
	if (!strcmp(argv[1], "track")) return cmd_track(argc, argv);
	if (!strcmp(argv[1], "loops")) return cmd_loops(argc, argv);
	if (!strcmp(argv[1], "sweep")) return cmd_sweep(argc, argv);
	if (!strcmp(argv[1], "fill")) return cmd_fill(argc, argv);
	if (!strcmp(argv[1], "xloop")) return cmd_xloop(argc, argv);
	if (!strcmp(argv[1], "finish")) return cmd_finish(argc, argv);
	fprintf(stderr, "track | loops\n");
	return 1;
}
