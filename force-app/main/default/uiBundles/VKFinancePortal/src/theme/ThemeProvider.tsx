import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { appearanceApi } from "@/api/endpoints";
import { useAuth } from "@/features/auth/AuthContext";
import { useDraft } from "@/lib/useDraft";
import { applyTheme, currentTheme, isDarkMode } from "./engine";
import { resolveTheme, type Appearance, type FamilyTheme, type PersonalTheme, type ResolvedTheme, type ThemeMode } from "./themes";

interface ThemeContextValue {
	/** What's saved for this person and their family. */
	appearance: Appearance;
	/** The theme in effect (or being previewed). */
	theme: ResolvedTheme;
	isDark: boolean;
	previewing: boolean;
	/** Shows a theme without saving it; null goes back to the saved one. */
	preview(theme: ResolvedTheme | null): void;
	savePersonal(theme: PersonalTheme | null): Promise<void>;
	saveFamily(theme: FamilyTheme | null): Promise<void>;
	/** Quick light/dark switch that keeps everything else. */
	setMode(mode: ThemeMode): Promise<void>;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);
const NONE: Appearance = {};

function useSystemDark(): boolean {
	const query = "(prefers-color-scheme: dark)";
	const [dark, setDark] = useState(() => window.matchMedia?.(query).matches === true);
	useEffect(() => {
		const media = window.matchMedia?.(query);
		const onChange = () => setDark(media.matches);
		media?.addEventListener?.("change", onChange);
		return () => media?.removeEventListener?.("change", onChange);
	}, []);
	return dark;
}

export function ThemeProvider({ children }: { children: ReactNode }) {
	const { profile } = useAuth();
	// Saves update this copy; a new sign-in or refreshed profile brings the server's version again.
	const [appearance, setAppearance] = useDraft<Appearance>(profile?.appearance ?? NONE);
	const [previewTheme, setPreviewTheme] = useState<ResolvedTheme | null>(null);
	const systemDark = useSystemDark();

	const saved = useMemo(() => (profile ? resolveTheme(appearance) : currentTheme()), [profile, appearance]);
	const theme = previewTheme ?? saved;

	useEffect(() => {
		// Previews aren't remembered on the device; only what's saved is.
		applyTheme(theme, { remember: !previewTheme });
	}, [theme, previewTheme]);

	const preview = useCallback((next: ResolvedTheme | null) => setPreviewTheme(next), []);

	const savePersonal = useCallback(async (next: PersonalTheme | null) => {
		const result = next ? await appearanceApi.savePersonal(next) : await appearanceApi.resetPersonal();
		setPreviewTheme(null);
		setAppearance(result);
	}, [setAppearance]);

	const saveFamily = useCallback(async (next: FamilyTheme | null) => {
		const result = next ? await appearanceApi.saveFamily(next) : await appearanceApi.resetFamily();
		setAppearance(result);
	}, [setAppearance]);

	const setMode = useCallback(
		async (mode: ThemeMode) => {
			// Someone following the family colours keeps following them; only the mode becomes theirs.
			const next: PersonalTheme = appearance.personal
				? { ...appearance.personal, mode }
				: { preset: "family", radius: "default", text: "default", mode };
			const before = appearance;
			setAppearance({ ...appearance, personal: next });
			try {
				setAppearance(await appearanceApi.savePersonal(next));
			} catch (error) {
				setAppearance(before);
				throw error;
			}
		},
		[appearance, setAppearance],
	);

	const value = useMemo<ThemeContextValue>(
		() => ({
			appearance,
			theme,
			isDark: theme.mode === "system" ? systemDark : isDarkMode(theme.mode),
			previewing: previewTheme !== null,
			preview,
			savePersonal,
			saveFamily,
			setMode,
		}),
		[appearance, theme, systemDark, previewTheme, preview, savePersonal, saveFamily, setMode],
	);
	return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
	const ctx = useContext(ThemeContext);
	if (!ctx) throw new Error("useTheme must be used inside ThemeProvider");
	return ctx;
}

/** For components that may render outside the provider (e.g. the toaster): just light or dark. */
export function useIsDark(): boolean {
	return useContext(ThemeContext)?.isDark ?? false;
}
