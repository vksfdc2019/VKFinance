/**
 * Puts a theme on the page: brand colour variables, the `dark` class, corner and text-size
 * attributes on <html>. The last theme is remembered on this device so the next visit (and the
 * sign-in page) opens in it without a flash.
 */
import { cssOklch } from "./color";
import { DEFAULT_THEME, themeColors, type ResolvedTheme, type ThemeMode } from "./themes";
import { SHADES } from "./tailwindPalettes";

const STORAGE_KEY = "vkf.theme.v1";
const DARK_QUERY = "(prefers-color-scheme: dark)";

let current: ResolvedTheme = DEFAULT_THEME;
let applied = false;
let watchingSystem = false;
let printing = false;
let fadeTimer: ReturnType<typeof setTimeout> | undefined;

const sameLook = (a: ResolvedTheme, b: ResolvedTheme) =>
	a.preset === b.preset && a.brand === b.brand && a.mode === b.mode && a.radius === b.radius && a.text === b.text;

/** Fades colours for a moment when the theme really changes (never on first paint or with reduced motion). */
function fadeColours() {
	if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
	const root = document.documentElement;
	root.classList.add("vk-theme-transition");
	clearTimeout(fadeTimer);
	fadeTimer = setTimeout(() => root.classList.remove("vk-theme-transition"), 300);
}

function systemPrefersDark(): boolean {
	return typeof window !== "undefined" && window.matchMedia?.(DARK_QUERY).matches === true;
}

export function isDarkMode(mode: ThemeMode): boolean {
	return mode === "dark" || (mode === "system" && systemPrefersDark());
}

function setDark(dark: boolean) {
	const root = document.documentElement;
	root.classList.toggle("dark", dark && !printing);
	root.style.colorScheme = dark && !printing ? "dark" : "light";
}

function setMetaThemeColor(color: string) {
	let meta = document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
	if (!meta) {
		meta = document.createElement("meta");
		meta.name = "theme-color";
		document.head.appendChild(meta);
	}
	meta.content = color;
}

function watchSystem() {
	if (watchingSystem || typeof window === "undefined") return;
	watchingSystem = true;
	window.matchMedia?.(DARK_QUERY).addEventListener?.("change", () => {
		if (current.mode === "system") setDark(systemPrefersDark());
	});
	// Paper is white: print in the light theme, then put the person's choice back.
	window.addEventListener("beforeprint", () => {
		printing = true;
		setDark(false);
	});
	window.addEventListener("afterprint", () => {
		printing = false;
		setDark(isDarkMode(current.mode));
	});
}

export function applyTheme(theme: ResolvedTheme, { remember = true } = {}) {
	if (applied && !sameLook(current, theme)) fadeColours();
	applied = true;
	current = theme;
	const root = document.documentElement;
	const { palette, alt, primary } = themeColors(theme);
	for (const shade of SHADES) {
		root.style.setProperty(`--brand-${shade}`, cssOklch(palette[shade]));
		root.style.setProperty(`--brand-alt-${shade}`, cssOklch(alt[shade]));
	}
	root.style.setProperty("--brand-primary", primary);
	root.dataset.radius = theme.radius;
	root.dataset.text = theme.text;
	root.dataset.theme = theme.preset;
	setDark(isDarkMode(theme.mode));
	setMetaThemeColor(primary);
	watchSystem();
	if (remember) {
		try {
			localStorage.setItem(STORAGE_KEY, JSON.stringify(theme));
		} catch {
			// Private mode or storage full: the theme still applies for this visit.
		}
	}
}

/** The theme last used on this device, for the first paint before anyone signs in. */
export function rememberedTheme(): ResolvedTheme {
	try {
		const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "null") as Partial<ResolvedTheme> | null;
		if (saved && typeof saved.preset === "string") return { ...DEFAULT_THEME, ...saved };
	} catch {
		// Unreadable: fall back to the default.
	}
	return DEFAULT_THEME;
}

export function currentTheme(): ResolvedTheme {
	return current;
}
