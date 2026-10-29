/**
 * Theme choices and how a person's theme is worked out. Colours and corners come from the family
 * when it has locked them, otherwise from the person, then the family, then VK Teal. Light/dark
 * and text size are always the person's own - they're about comfort, not branding.
 */
import { oklchToHex, paletteFrom, readableOnWhiteText } from "./color";
import { TAILWIND_PALETTES, type Palette, type PaletteName, type Shade } from "./tailwindPalettes";

export type ThemeMode = "light" | "dark" | "system";
export type Radius = "sharp" | "default" | "round";
export type TextSize = "default" | "large";
export type PresetId = "teal" | "ocean" | "indigo" | "grape" | "berry" | "sunset" | "gold" | "forest" | "graphite" | "custom";

/** Matches AppearanceService on the server. preset "family" = use the family's colours and corners. */
export interface PersonalTheme {
	preset: PresetId | "family";
	brand?: string;
	mode: ThemeMode;
	radius: Radius;
	text: TextSize;
}

export interface FamilyTheme {
	preset: PresetId;
	brand?: string;
	radius: Radius;
	locked: boolean;
}

export interface Appearance {
	personal?: PersonalTheme;
	family?: FamilyTheme;
	locked?: boolean;
}

export interface ResolvedTheme {
	preset: PresetId;
	brand?: string;
	mode: ThemeMode;
	radius: Radius;
	text: TextSize;
	/** Where the colours came from, for the Appearance page. */
	source: "personal" | "family" | "default";
}

export interface Preset {
	id: Exclude<PresetId, "custom">;
	name: string;
	description: string;
	palette: PaletteName;
	/** The second colour in gradients (avatars, banners). */
	alt: PaletteName;
	/** Shade used for buttons; dark enough for white text. */
	primary: Shade;
}

export const PRESETS: readonly Preset[] = [
	{ id: "teal", name: "VK Teal", description: "Calm and trusted - the original", palette: "teal", alt: "emerald", primary: 800 },
	{ id: "ocean", name: "Ocean", description: "Clear, confident blue", palette: "blue", alt: "sky", primary: 700 },
	{ id: "indigo", name: "Indigo", description: "Deep and focused", palette: "indigo", alt: "violet", primary: 700 },
	{ id: "grape", name: "Grape", description: "Rich and playful", palette: "violet", alt: "fuchsia", primary: 700 },
	{ id: "berry", name: "Berry", description: "Bold and warm", palette: "rose", alt: "pink", primary: 700 },
	{ id: "sunset", name: "Sunset", description: "Bright and energetic", palette: "orange", alt: "red", primary: 700 },
	{ id: "gold", name: "Gold", description: "Warm, prosperous amber", palette: "amber", alt: "orange", primary: 700 },
	{ id: "forest", name: "Forest", description: "Fresh and growing", palette: "green", alt: "emerald", primary: 700 },
	{ id: "graphite", name: "Graphite", description: "Minimal and quiet", palette: "slate", alt: "zinc", primary: 800 },
];

export const DEFAULT_PRESET: Preset = PRESETS[0];
export const DEFAULT_CUSTOM_BRAND = "#0f766e";

export const DEFAULT_THEME: ResolvedTheme = { preset: "teal", mode: "system", radius: "default", text: "default", source: "default" };

export const MODE_LABELS: Record<ThemeMode, string> = { light: "Light", dark: "Dark", system: "Match device" };
export const RADIUS_LABELS: Record<Radius, string> = { sharp: "Sharp", default: "Soft", round: "Round" };
export const TEXT_LABELS: Record<TextSize, string> = { default: "Standard", large: "Large" };

export function presetById(id: PresetId): Preset | undefined {
	return PRESETS.find((p) => p.id === id);
}

export function resolveTheme(appearance?: Appearance | null): ResolvedTheme {
	const personal = appearance?.personal;
	const family = appearance?.family;
	const ownColours = personal && personal.preset !== "family" ? (personal as PersonalTheme & { preset: PresetId }) : undefined;
	const chosen = appearance?.locked && family ? family : (ownColours ?? family);
	// Ignore anything this version doesn't understand rather than showing a broken theme.
	const colours = chosen && (chosen.preset === "custom" ? chosen.brand : presetById(chosen.preset)) ? chosen : undefined;
	return {
		preset: colours?.preset ?? DEFAULT_THEME.preset,
		brand: colours?.preset === "custom" ? colours.brand : undefined,
		radius: colours?.radius ?? DEFAULT_THEME.radius,
		mode: personal?.mode ?? DEFAULT_THEME.mode,
		text: personal?.text ?? DEFAULT_THEME.text,
		source: !colours ? "default" : colours === ownColours ? "personal" : "family",
	};
}

export interface ThemeColors {
	palette: Palette;
	alt: Palette;
	/** Button colour, always readable with white text. */
	primary: string;
	/** True when a custom colour was darkened to keep button text readable. */
	adjusted: boolean;
}

const colorCache = new Map<string, ThemeColors>();

export function themeColors(theme: Pick<ResolvedTheme, "preset" | "brand">): ThemeColors {
	const key = theme.preset === "custom" ? `custom:${theme.brand}` : theme.preset;
	const cached = colorCache.get(key);
	if (cached) return cached;
	let colors: ThemeColors;
	if (theme.preset === "custom" && theme.brand) {
		const { hex, adjusted } = readableOnWhiteText(theme.brand);
		colors = { palette: paletteFrom(theme.brand), alt: paletteFrom(theme.brand, 28), primary: hex, adjusted };
	} else {
		const preset = presetById(theme.preset) ?? DEFAULT_PRESET;
		const palette = TAILWIND_PALETTES[preset.palette];
		colors = { palette, alt: TAILWIND_PALETTES[preset.alt], primary: oklchToHex(palette[preset.primary]), adjusted: false };
	}
	colorCache.set(key, colors);
	return colors;
}

/** The one colour that represents a theme in pickers. */
export function swatchFor(theme: Pick<ResolvedTheme, "preset" | "brand">): string {
	return theme.preset === "custom" && theme.brand ? theme.brand : themeColors(theme).primary;
}
