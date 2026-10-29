/**
 * Colour maths for themes: hex <-> OKLCH, a Tailwind-like shade ladder from any one colour,
 * and WCAG contrast. OKLCH keeps a hue looking the same as it gets lighter or darker.
 */
import { SHADES, type Oklch, type Palette, type Shade } from "./tailwindPalettes";

type Rgb = [number, number, number];

const HEX = /^#([0-9a-f]{6})$/i;

export function isHex(value: string): boolean {
	return HEX.test(value.trim());
}

/** "#0F766E", "0f766e" or "#0f766e" -> "#0f766e"; null if it isn't a 6-digit colour. */
export function normalizeHex(value: string): string | null {
	const v = value.trim().replace(/^#?/, "#").toLowerCase();
	return HEX.test(v) ? v : null;
}

function hexToRgb(hex: string): Rgb {
	const n = parseInt(hex.slice(1), 16);
	return [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => c / 255) as Rgb;
}

function rgbToHex([r, g, b]: Rgb): string {
	return `#${[r, g, b].map((c) => Math.round(Math.min(1, Math.max(0, c)) * 255).toString(16).padStart(2, "0")).join("")}`;
}

const toLinear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const fromLinear = (c: number) => (c <= 0.0031308 ? c * 12.92 : 1.055 * c ** (1 / 2.4) - 0.055);

export function hexToOklch(hex: string): Oklch {
	const [r, g, b] = hexToRgb(hex).map(toLinear);
	const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
	const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
	const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
	const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
	const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
	const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
	const C = Math.hypot(A, B);
	const H = C < 1e-4 ? 0 : ((Math.atan2(B, A) * 180) / Math.PI + 360) % 360;
	return [L, C, H];
}

/** OKLCH -> sRGB, unclamped (values outside 0-1 mean the colour is outside sRGB). */
function oklchToRgb([L, C, H]: Oklch): Rgb {
	const h = (H * Math.PI) / 180;
	const A = C * Math.cos(h);
	const B = C * Math.sin(h);
	const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
	const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
	const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
	return [
		fromLinear(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		fromLinear(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		fromLinear(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
	];
}

const inGamut = (rgb: Rgb) => rgb.every((c) => c >= -0.0005 && c <= 1.0005);

/** Lowers chroma until the colour fits sRGB, keeping its lightness and hue. */
export function fitGamut([L, C, H]: Oklch): Oklch {
	if (inGamut(oklchToRgb([L, C, H]))) return [L, C, H];
	let lo = 0;
	let hi = C;
	for (let i = 0; i < 20; i++) {
		const mid = (lo + hi) / 2;
		if (inGamut(oklchToRgb([L, mid, H]))) lo = mid;
		else hi = mid;
	}
	return [L, lo, H];
}

export function oklchToHex(color: Oklch): string {
	return rgbToHex(oklchToRgb(fitGamut(color)));
}

export function cssOklch([L, C, H]: Oklch): string {
	return `oklch(${(L * 100).toFixed(1)}% ${C.toFixed(3)} ${H.toFixed(2)})`;
}

/** WCAG 2 relative luminance and contrast ratio (1-21). */
function luminance(hex: string): number {
	const [r, g, b] = hexToRgb(hex).map(toLinear);
	return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrastRatio(a: string, b: string): number {
	const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
	return (hi + 0.05) / (lo + 0.05);
}

/** Lightness of each shade, averaged from Tailwind's own palettes. */
const LADDER: Record<Shade, number> = {
	50: 0.978, 100: 0.952, 200: 0.903, 300: 0.835, 400: 0.745, 500: 0.665,
	600: 0.585, 700: 0.508, 800: 0.44, 900: 0.388, 950: 0.276,
};
/** How much of the colour's chroma each shade keeps: pale tints and deep shades are calmer. */
const CHROMA: Record<Shade, number> = {
	50: 0.1, 100: 0.24, 200: 0.45, 300: 0.72, 400: 0.92, 500: 1, 600: 1,
	700: 0.92, 800: 0.8, 900: 0.66, 950: 0.5,
};

/**
 * A full 50-950 palette around one colour. The colour itself replaces the shade closest to its
 * lightness, so the swatch you picked appears exactly; the rest follow Tailwind's ladder.
 */
export function paletteFrom(hex: string, hueShift = 0): Palette {
	const [L, C, H] = hexToOklch(hex);
	const hue = (H + hueShift + 360) % 360;
	const peak = Math.max(C, 0.012);
	const palette = {} as Record<Shade, Oklch>;
	for (const shade of SHADES) palette[shade] = fitGamut([LADDER[shade], peak * CHROMA[shade], hue]);
	if (hueShift === 0) {
		const nearest = SHADES.reduce((best, s) => (Math.abs(LADDER[s] - L) < Math.abs(LADDER[best] - L) ? s : best), 500 as Shade);
		if (nearest >= 400 && nearest <= 800) palette[nearest] = [L, C, H];
	}
	return palette;
}

/** White text needs 4.5:1 on a button. Darkens the colour just enough to get there. */
export function readableOnWhiteText(hex: string, minimum = 4.5): { hex: string; adjusted: boolean } {
	if (contrastRatio(hex, "#ffffff") >= minimum) return { hex, adjusted: false };
	const [L, C, H] = hexToOklch(hex);
	for (let next = L - 0.01; next > 0.05; next -= 0.01) {
		const candidate = oklchToHex([next, C, H]);
		if (contrastRatio(candidate, "#ffffff") >= minimum) return { hex: candidate, adjusted: true };
	}
	return { hex: "#000000", adjusted: true };
}
