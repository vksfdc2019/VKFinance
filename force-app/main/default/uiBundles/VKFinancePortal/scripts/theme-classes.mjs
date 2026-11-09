// Keeps Tailwind colour classes theme-ready.
//
//   node scripts/theme-classes.mjs --check   report classes that would break a theme (CI / npm run theme:check)
//   node scripts/theme-classes.mjs --write   fix them in place
//
// Rules
// 1. The theme colour is `brand-*` (and `brand-alt-*` for the second colour in gradients), never teal-*.
//    Account colours in components/finance/icons.tsx are the person's own choice and stay as they are.
// 2. Every colour that sits on the page needs a dark-mode partner. Which ones is decided by what the
//    class is doing:
//      surfaces (bg/from/via/to) in light shades 50-200 and white  -> dark tints   (bg-amber-50 -> dark:bg-amber-950/40)
//      ink (text/fill/stroke) in dark shades 500-950             -> light ink    (text-slate-700 -> dark:text-slate-300)
//      lines (border/ring/divide/outline) in light shades         -> dark lines   (border-slate-200 -> dark:border-slate-800)
//    Solid fills (bg-brand-700 with white text), light ink on solid fills (text-white, text-brand-100)
//    and see-through overlays (bg-white/15, bg-black/50) look right in both modes and are left alone.
// Files whose whole component sits on a coloured card are listed in SOLID_FILES and skipped.
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

const ROOT = "src";
const write = process.argv.includes("--write");
const SOLID_FILES = new Set(["components/finance/icons.tsx", "features/accounts/AccountCard.tsx", "features/savings/SchemeCard.tsx"]);
const SKIP_DIRS = new Set(["theme"]);

const NEUTRAL = new Set(["slate", "gray", "zinc", "neutral", "stone"]);
const SURFACE = new Set(["bg", "from", "via", "to"]);
const INK = new Set(["text", "fill", "stroke", "placeholder", "decoration", "caret"]);
const LINE = /^(border(-[xytblrse])?|ring|ring-offset|outline|divide)$/;
const PALETTES =
	"white|black|brand-alt|brand|slate|gray|zinc|neutral|stone|red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose";
const TOKEN = new RegExp(
	`(?<=^|[\\s"'\`])((?:[a-z0-9-]*(?:\\[[^\\]\\s]*\\])?:)*)(bg|from|via|to|text|fill|stroke|placeholder|decoration|caret|border(?:-[xytblrse])?|ring-offset|ring|outline|divide|shadow|accent)-(${PALETTES})(?:-(\\d{2,3}))?(?:\\/(\\d+))?(?=$|[\\s"'\`])`,
	"g",
);

const withAlpha = (color, alpha) => (alpha ? `${color}/${alpha}` : color);

/** The dark-mode partner for one class, or null when it already works in dark mode. */
export function partnerFor(prop, color, shadeText, alpha, hover) {
	const shade = shadeText ? Number(shadeText) : undefined;
	const a = alpha ? Number(alpha) : undefined;
	if (color === "black") return null;
	if (color === "white") {
		if (SURFACE.has(prop)) return a !== undefined && a < 50 ? null : withAlpha(hover ? "slate-800" : "slate-900", alpha);
		if (LINE.test(prop)) return a === undefined ? "slate-900" : null;
		return null;
	}
	if (shade === undefined) return null;
	if (NEUTRAL.has(color)) {
		if (SURFACE.has(prop)) {
			if (shade <= 200) {
				const dark = { 50: "800", 100: "800", 200: "700" }[shade];
				return withAlpha(`slate-${dark}`, alpha ?? (shade === 50 ? (hover ? "60" : "40") : undefined));
			}
			if (prop === "bg" && shade >= 800 && a === undefined) return "slate-700";
			return null;
		}
		if (INK.has(prop)) {
			if (shade < 500) return null;
			return `slate-${{ 500: 400, 600: 400, 700: 300, 800: 200, 900: 100, 950: 100 }[shade]}`;
		}
		if (LINE.test(prop)) {
			if (shade <= 300) return withAlpha(`slate-${shade === 300 ? 700 : 800}`, alpha);
			if (shade >= 600 && a !== undefined) return `white/${Math.min(20, Math.max(8, a * 2))}`;
			return null;
		}
		return null;
	}
	// Chromatic colours, including brand and brand-alt.
	if (SURFACE.has(prop)) {
		if (shade > 200) return null;
		return { 50: `${color}-950/40`, 100: `${color}-900/40`, 200: `${color}-800/50` }[shade];
	}
	if (INK.has(prop)) {
		if (shade < 500) return null;
		return `${color}-${{ 500: 400, 600: 400, 700: 300, 800: 200, 900: 100, 950: 100 }[shade]}`;
	}
	if (LINE.test(prop)) {
		if (shade > 300) return null;
		return withAlpha(`${color}-${{ 50: 900, 100: 900, 200: 800, 300: 700 }[shade]}`, alpha);
	}
	return null;
}

/** teal -> brand (and the emerald end of teal gradients -> brand-alt). */
function rebrand(line) {
	let out = line.replace(/(?<=[-:\s"'`]|^)((?:[a-z0-9-]*:)*(?:bg|from|via|to|text|fill|stroke|border(?:-[xytblrse])?|ring|outline|divide|shadow|accent|placeholder|decoration|caret))-teal-(\d{2,3})/g, "$1-brand-$2");
	if (/-brand-\d/.test(out) && /(?:from|via|to)-emerald-\d/.test(out)) {
		out = out.replace(/((?:[a-z0-9-]*:)*(?:from|via|to))-emerald-(\d{2,3})/g, "$1-brand-alt-$2");
	}
	return out;
}

function propKey(variants, prop) {
	return `${variants.replace(/dark:/g, "")}|${prop}`;
}

/** Adds missing dark: partners to one line; returns [newLine, problems]. */
function darken(line) {
	const existing = new Set();
	for (const m of line.matchAll(TOKEN)) {
		if (m[1].includes("dark:")) existing.add(propKey(m[1], m[2]));
	}
	const problems = [];
	const out = line.replace(TOKEN, (token, variants, prop, color, shade, alpha) => {
		if (variants.includes("dark:") || variants.includes("print:")) return token;
		const partner = partnerFor(prop, color, shade, alpha, variants.includes("hover:"));
		if (!partner || existing.has(propKey(variants, prop))) return token;
		const added = `dark:${variants}${prop}-${partner}`;
		problems.push(`${token}  ->  ${added}`);
		return `${token} ${added}`;
	});
	return [out, problems];
}

function walk(dir, files = []) {
	for (const name of readdirSync(dir)) {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) {
			if (!SKIP_DIRS.has(name)) walk(path, files);
		} else if (/\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name)) files.push(path);
	}
	return files;
}

let total = 0;
for (const file of walk(ROOT)) {
	const rel = relative(ROOT, file).split(sep).join("/");
	if (SOLID_FILES.has(rel)) continue;
	const source = readFileSync(file, "utf8");
	const report = [];
	const lines = source.split("\n").map((line, i) => {
		const rebranded = rebrand(line);
		if (rebranded !== line) report.push(`  ${i + 1}: teal -> brand`);
		const [next, problems] = darken(rebranded);
		for (const p of problems) report.push(`  ${i + 1}: ${p}`);
		return next;
	});
	if (report.length) {
		total += report.length;
		console.log(`${rel}\n${report.join("\n")}`);
		if (write) writeFileSync(file, lines.join("\n"));
	}
}
console.log(total ? `\n${total} change(s) ${write ? "made" : "needed"}.` : "Theme classes are all good.");
if (!write && total) process.exitCode = 1;
