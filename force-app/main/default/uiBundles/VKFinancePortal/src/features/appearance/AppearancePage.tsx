import { useEffect, useMemo, useState, type ReactNode } from "react";
import { Lock, Monitor, Moon, RotateCcw, Sun, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { PageHeader, Panel, SegmentedControl } from "@/components/finance/ui";
import { errorMessages } from "@/api/vkfClient";
import { cn } from "@/lib/utils";
import { useDraft } from "@/lib/useDraft";
import { useAuth } from "@/features/auth/AuthContext";
import { useTheme } from "@/theme/ThemeProvider";
import {
	MODE_LABELS,
	RADIUS_LABELS,
	TEXT_LABELS,
	presetById,
	resolveTheme,
	type Appearance,
	type FamilyTheme,
	type PersonalTheme,
	type PresetId,
	type Radius,
	type TextSize,
	type ThemeMode,
} from "@/theme/themes";
import { ThemePicker, type PickerValue } from "./ThemePicker";
import { ThemePreview } from "./ThemePreview";

type Tab = "me" | "family";

const DEFAULT_FAMILY: FamilyTheme = { preset: "teal", radius: "default", locked: false };

function themeName(t?: { preset: PresetId; brand?: string }): string {
	if (!t) return "VK Teal";
	if (t.preset === "custom") return `a custom colour (${t.brand?.toUpperCase()})`;
	return presetById(t.preset)?.name ?? "VK Teal";
}

/**
 * What the "For me" form starts from: the saved choice, or "follow the family" when there is one.
 * Following the family also means its corners, so the form shows those.
 */
function personalDraft(a: Appearance): PersonalTheme {
	const saved = resolveTheme(a);
	const own = a.personal;
	if (!own) return { preset: a.family ? "family" : "teal", radius: saved.radius, mode: saved.mode, text: saved.text };
	return {
		...own,
		radius: own.preset === "family" ? (a.family?.radius ?? "default") : (own.radius ?? "default"),
		mode: own.mode ?? "system",
		text: own.text ?? "default",
	};
}

/** Compares what a theme looks like, ignoring key order and the server's version number. */
type Look = { preset?: string; brand?: string; radius?: string; mode?: string; text?: string; locked?: boolean };
function same(a: Look, b: Look) {
	const look = (t: typeof a) => [t.preset, t.preset === "custom" ? t.brand : null, t.radius, t.mode ?? null, t.text ?? null, t.locked ?? null].join("|");
	return look(a) === look(b);
}

export default function AppearancePage() {
	const { profile } = useAuth();
	const { appearance, theme, preview, savePersonal, saveFamily } = useTheme();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [tab, setTab] = useState<Tab>("me");
	const [saving, setSaving] = useState(false);

	const startMe = useMemo(() => personalDraft(appearance), [appearance]);
	const startFamily = useMemo(() => ({ ...DEFAULT_FAMILY, ...appearance.family }), [appearance]);
	const [me, setMe] = useDraft(startMe);
	const [family, setFamily] = useDraft<FamilyTheme>(startFamily);

	const meDirty = !same(me, startMe);
	const familyDirty = !same(family, startFamily);
	const dirty = tab === "me" ? meDirty : familyDirty;
	const saved = useMemo(() => resolveTheme(appearance), [appearance]);
	const locked = Boolean(appearance.locked && appearance.family);
	const colourLocked = tab === "me" && locked;

	// Every change previews across the whole app straight away; leaving the page drops unsaved changes.
	useEffect(() => {
		if (tab === "me") {
			preview(meDirty ? resolveTheme({ ...appearance, personal: me }) : null);
		} else {
			const asMember: PersonalTheme = { preset: "family", radius: "default", mode: saved.mode, text: saved.text };
			preview(familyDirty ? resolveTheme({ personal: asMember, family, locked: true }) : null);
		}
	}, [tab, me, family, meDirty, familyDirty, appearance, saved, preview]);
	useEffect(() => () => preview(null), [preview]);

	async function run(action: () => Promise<void>, done: string) {
		setSaving(true);
		try {
			await action();
			toast.success(done);
		} catch (error) {
			toast.error(errorMessages(error)[0] ?? "Couldn't save your appearance.");
		} finally {
			setSaving(false);
		}
	}

	const saveMe = () => run(() => savePersonal(me), "Appearance saved");
	const saveFam = () =>
		run(() => saveFamily(family), family.locked ? "Family theme saved and applied to everyone" : "Family theme saved");
	const discard = () => (tab === "me" ? setMe(startMe) : setFamily(startFamily));

	const pickerValue: PickerValue = tab === "me" ? { preset: me.preset, brand: me.brand } : { preset: family.preset, brand: family.brand };
	const onPick = (v: PickerValue) =>
		tab === "me"
			? setMe({
					...me,
					preset: v.preset,
					brand: v.preset === "custom" ? v.brand : undefined,
					radius: v.preset === "family" ? (appearance.family?.radius ?? "default") : me.radius,
				})
			: setFamily({ ...family, preset: v.preset === "family" ? "teal" : v.preset, brand: v.preset === "custom" ? v.brand : undefined });
	const radius = tab === "me" ? me.radius : family.radius;
	const setRadius = (r: Radius) => (tab === "me" ? setMe({ ...me, radius: r }) : setFamily({ ...family, radius: r }));
	const followingFamily = tab === "me" && me.preset === "family";

	return (
		<div className="pb-24">
			<PageHeader
				title="Appearance"
				description="Make VK Finance yours. Every change previews instantly - nothing is saved until you press Save."
				actions={
					isAdmin && (
						<SegmentedControl<Tab>
							label="Whose appearance"
							value={tab}
							onChange={(t) => {
								discard();
								setTab(t);
							}}
							options={[
								{ value: "me", label: "For me" },
								{ value: "family", label: "Family default" },
							]}
						/>
					)
				}
			/>

			<div className="grid items-start gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
				<div className="space-y-6">
					{tab === "family" && (
						<Notice icon={<Users className="size-4" />}>
							Everyone in {profile?.familyName ?? "your family"} starts with this theme. Light or dark and text size stay each
							person's own choice.
						</Notice>
					)}
					{colourLocked && (
						<Notice icon={<Lock className="size-4" />}>
							Your family uses {themeName(appearance.family)}, set by your Family Admin for everyone. You can still choose light or
							dark and your text size.
						</Notice>
					)}

					{tab === "me" && (
						<Panel title="Mode" description="Dark is easier on the eyes at night. Match device follows your phone or computer.">
							<div role="radiogroup" aria-label="Mode" className="grid grid-cols-3 gap-3">
								{(["light", "dark", "system"] as ThemeMode[]).map((m) => (
									<ModeTile key={m} mode={m} on={me.mode === m} onSelect={() => setMe({ ...me, mode: m })} />
								))}
							</div>
						</Panel>
					)}

					<Panel
						title="Colour theme"
						description={
							tab === "me"
								? "Sets buttons, highlights and banners across every page. Account card colours stay as you chose them."
								: "The colours your family sees unless someone picks their own."
						}
					>
						<ThemePicker
							label="Colour theme"
							value={pickerValue}
							onChange={onPick}
							disabled={colourLocked}
							familyOption={tab === "me" && appearance.family && !locked ? { name: themeName(appearance.family), ...appearance.family } : undefined}
						/>
					</Panel>

					<div className="grid gap-6 md:grid-cols-2">
						<Panel title="Corners" description={followingFamily ? "Following the family theme." : "How rounded cards and buttons are."}>
							<div role="radiogroup" aria-label="Corners" className="grid grid-cols-3 gap-2">
								{(["sharp", "default", "round"] as Radius[]).map((r) => (
									<OptionTile
										key={r}
										on={radius === r}
										disabled={colourLocked || followingFamily}
										onSelect={() => setRadius(r)}
										label={RADIUS_LABELS[r]}
									>
										<span
											className="size-8 border-2 border-brand-600 dark:border-brand-400 bg-brand-50 dark:bg-brand-950/40"
											style={{ borderRadius: { sharp: 3, default: 9, round: 15 }[r] }}
										/>
									</OptionTile>
								))}
							</div>
						</Panel>

						{tab === "me" ? (
							<Panel title="Text size" description="Large makes every page easier to read.">
								<div role="radiogroup" aria-label="Text size" className="grid grid-cols-2 gap-2">
									{(["default", "large"] as TextSize[]).map((t) => (
										<OptionTile key={t} on={me.text === t} onSelect={() => setMe({ ...me, text: t })} label={TEXT_LABELS[t]}>
											<span className={cn("font-semibold text-slate-900 dark:text-slate-100", t === "large" ? "text-2xl" : "text-lg")}>Aa</span>
										</OptionTile>
									))}
								</div>
							</Panel>
						) : (
							<Panel title="Members' choice" description="Decide whether members can pick their own colours.">
								<label className="flex items-start gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 text-sm text-slate-700 dark:text-slate-300">
									<Checkbox
										checked={!family.locked}
										onCheckedChange={(v) => setFamily({ ...family, locked: v !== true })}
										className="mt-0.5"
									/>
									<span>
										<span className="font-medium text-slate-900 dark:text-slate-100">Let members choose their own colours</span>
										<span className="mt-0.5 block text-xs text-slate-500 dark:text-slate-400">
											Turn off to use this theme for everyone - handy for a consistent family look.
										</span>
									</span>
								</label>
							</Panel>
						)}
					</div>

					<div className="flex flex-wrap items-center gap-3">
						{tab === "me" && appearance.personal && (
							<Button variant="ghost" disabled={saving} onClick={() => void run(() => savePersonal(null), "Back to the family theme")}>
								<RotateCcw />
								Reset to {appearance.family ? "the family theme" : "default"}
							</Button>
						)}
						{tab === "family" && appearance.family && (
							<Button variant="ghost" disabled={saving} onClick={() => void run(() => saveFamily(null), "Family theme reset to VK Teal")}>
								<RotateCcw />
								Reset family to VK Teal
							</Button>
						)}
					</div>
				</div>

				<aside className="lg:sticky lg:top-8">
					<p className="mb-2 text-xs font-medium text-slate-500 dark:text-slate-400">Live preview</p>
					<ThemePreview theme={theme} currency={profile?.currencyCode} />
					<p className="mt-3 text-xs text-slate-500 dark:text-slate-400">
						{saved.source === "family" ? "Now using the family theme." : saved.source === "personal" ? "Now using your own theme." : "Now using VK Teal."}{" "}
						{MODE_LABELS[saved.mode]} mode.
					</p>
				</aside>
			</div>

			{dirty && (
				<div className="no-print fixed inset-x-0 bottom-4 z-40 flex justify-center px-4 lg:pl-64">
					<div className="vk-rise flex w-full max-w-xl items-center gap-3 rounded-2xl bg-slate-900 px-4 py-3 text-white shadow-2xl ring-1 ring-white/10 dark:bg-slate-800">
						<span className="flex-1 text-sm">{tab === "me" ? "Previewing your new look" : "Previewing the family theme"}</span>
						<Button variant="ghost" size="sm" className="text-white hover:bg-white/10 hover:text-white" onClick={discard} disabled={saving}>
							Discard
						</Button>
						<Button size="sm" className="bg-white text-slate-900 hover:bg-white/90 dark:bg-white dark:text-slate-900 dark:hover:bg-white/90" onClick={() => void (tab === "me" ? saveMe() : saveFam())} disabled={saving}>
							{saving && <Spinner />}
							Save
						</Button>
					</div>
				</div>
			)}
		</div>
	);
}

function Notice({ icon, children }: { icon: ReactNode; children: ReactNode }) {
	return (
		<p className="flex items-start gap-3 rounded-2xl bg-brand-50 dark:bg-brand-950/40 px-4 py-3 text-sm text-brand-900 dark:text-brand-100 ring-1 ring-brand-600/15">
			<span className="mt-0.5 shrink-0 text-brand-700 dark:text-brand-300">{icon}</span>
			<span>{children}</span>
		</p>
	);
}

function OptionTile({ on, onSelect, label, disabled, children }: { on: boolean; onSelect(): void; label: string; disabled?: boolean; children: ReactNode }) {
	return (
		<button
			type="button"
			role="radio"
			aria-checked={on}
			disabled={disabled}
			onClick={onSelect}
			className={cn(
				"flex flex-col items-center gap-2 rounded-xl px-2 py-3 text-xs font-medium ring-1 transition-all disabled:opacity-50",
				on
					? "bg-brand-50 dark:bg-brand-950/40 text-brand-900 dark:text-brand-100 ring-2 ring-brand-600 dark:ring-brand-400"
					: "text-slate-600 dark:text-slate-400 ring-slate-900/10 dark:ring-white/20 hover:bg-slate-50 dark:hover:bg-slate-800/60",
			)}
		>
			<span className="flex h-9 items-center justify-center">{children}</span>
			{label}
		</button>
	);
}

/** A tiny window in light, dark or half-and-half; drawn with fixed colours because it shows both modes. */
function ModeTile({ mode, on, onSelect }: { mode: ThemeMode; on: boolean; onSelect(): void }) {
	const Icon = { light: Sun, dark: Moon, system: Monitor }[mode];
	const light = { page: "#f8fafc", card: "#ffffff", line: "#e2e8f0" };
	const dark = { page: "#020617", card: "#0f172a", line: "#334155" };
	const window = (c: typeof light) => (
		<span className="flex h-full flex-1 flex-col gap-1 p-1.5" style={{ backgroundColor: c.page }}>
			<span className="h-1.5 w-1/2 rounded-full bg-brand-500" />
			<span className="flex-1 rounded" style={{ backgroundColor: c.card, boxShadow: `inset 0 0 0 1px ${c.line}` }} />
		</span>
	);
	return (
		<button
			type="button"
			role="radio"
			aria-checked={on}
			onClick={onSelect}
			className={cn(
				"overflow-hidden rounded-xl text-left ring-1 transition-all",
				on ? "ring-2 ring-brand-600 dark:ring-brand-400" : "ring-slate-900/10 dark:ring-white/20 hover:-translate-y-0.5",
			)}
		>
			<span className="flex h-16">
				{mode === "dark" ? window(dark) : window(light)}
				{mode === "system" && window(dark)}
			</span>
			<span className="flex items-center gap-1.5 px-2.5 py-2 text-xs font-medium text-slate-700 dark:text-slate-300">
				<Icon className="size-3.5" aria-hidden="true" />
				{MODE_LABELS[mode]}
			</span>
		</button>
	);
}
