import { describe, expect, it } from "vitest";
import { contrastRatio, hexToOklch, normalizeHex, oklchToHex, paletteFrom, readableOnWhiteText } from "./color";
import { PRESETS, resolveTheme, themeColors } from "./themes";
import { SHADES } from "./tailwindPalettes";

describe("colour maths", () => {
	it("normalises hex input", () => {
		expect(normalizeHex("0F766E")).toBe("#0f766e");
		expect(normalizeHex(" #ABCDEF ")).toBe("#abcdef");
		expect(normalizeHex("#abc")).toBeNull();
		expect(normalizeHex("teal")).toBeNull();
	});

	it("round-trips hex through OKLCH", () => {
		for (const hex of ["#0f766e", "#e11d48", "#facc15", "#334155", "#ffffff", "#000000"]) {
			expect(oklchToHex(hexToOklch(hex))).toBe(hex);
		}
	});

	it("measures WCAG contrast", () => {
		expect(contrastRatio("#ffffff", "#000000")).toBeCloseTo(21, 5);
		expect(contrastRatio("#777777", "#777777")).toBeCloseTo(1, 5);
	});

	it("builds a palette that gets darker shade by shade and keeps the chosen colour", () => {
		const palette = paletteFrom("#7c3aed");
		const lightness = SHADES.map((s) => palette[s][0]);
		expect([...lightness].sort((a, b) => b - a)).toEqual(lightness);
		expect(SHADES.some((s) => oklchToHex(palette[s]) === "#7c3aed")).toBe(true);
	});

	it("darkens light colours until white text is readable", () => {
		const { hex, adjusted } = readableOnWhiteText("#facc15");
		expect(adjusted).toBe(true);
		expect(contrastRatio(hex, "#ffffff")).toBeGreaterThanOrEqual(4.5);
		expect(readableOnWhiteText("#1e3a8a")).toEqual({ hex: "#1e3a8a", adjusted: false });
	});
});

describe("presets", () => {
	it.each(PRESETS.map((p) => [p.name, p.id] as const))("%s buttons pass WCAG AA with white text", (_name, id) => {
		expect(contrastRatio(themeColors({ preset: id }).primary, "#ffffff")).toBeGreaterThanOrEqual(4.5);
	});

	it("keeps VK Teal exactly as it was", () => {
		expect(themeColors({ preset: "teal" }).primary).toBe("#005f5a");
	});
});

describe("resolveTheme", () => {
	const family = { preset: "forest" as const, radius: "round" as const, locked: false };
	const mine = { preset: "berry" as const, mode: "dark" as const, radius: "sharp" as const, text: "large" as const };

	it("defaults to VK Teal, matching the device", () => {
		expect(resolveTheme(undefined)).toMatchObject({ preset: "teal", mode: "system", radius: "default", text: "default", source: "default" });
	});

	it("prefers the person's own colours, then the family's", () => {
		expect(resolveTheme({ personal: mine, family })).toMatchObject({ preset: "berry", radius: "sharp", source: "personal" });
		expect(resolveTheme({ family })).toMatchObject({ preset: "forest", radius: "round", source: "family" });
	});

	it("lets a person keep following the family colours", () => {
		const following = { preset: "family" as const, mode: "dark" as const, radius: "default" as const, text: "large" as const };
		expect(resolveTheme({ personal: following, family })).toMatchObject({ preset: "forest", radius: "round", mode: "dark", text: "large", source: "family" });
	});

	it("uses a locked family theme's colours but keeps the person's mode and text size", () => {
		expect(resolveTheme({ personal: mine, family: { ...family, locked: true }, locked: true })).toMatchObject({
			preset: "forest",
			radius: "round",
			mode: "dark",
			text: "large",
			source: "family",
		});
	});

	it("ignores themes it doesn't recognise", () => {
		expect(resolveTheme({ personal: { ...mine, preset: "neon" as never } })).toMatchObject({ preset: "teal", source: "default" });
		expect(resolveTheme({ personal: { ...mine, preset: "custom" } })).toMatchObject({ preset: "teal", source: "default" });
		expect(resolveTheme({ personal: { ...mine, preset: "custom", brand: "#7c3aed" } })).toMatchObject({ preset: "custom", brand: "#7c3aed" });
	});
});
