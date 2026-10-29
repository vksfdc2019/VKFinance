import { useId, useState } from "react";
import { Check, Pipette, Users } from "lucide-react";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { useDraft } from "@/lib/useDraft";
import { contrastRatio, cssOklch, normalizeHex, oklchToHex } from "@/theme/color";
import { DEFAULT_CUSTOM_BRAND, PRESETS, themeColors, type PresetId } from "@/theme/themes";
import { SHADES } from "@/theme/tailwindPalettes";

export type PickerValue = { preset: PresetId | "family"; brand?: string };

/** Colours that make good brands and aren't already a preset. */
const SUGGESTIONS = ["#1e3a8a", "#0e7490", "#4d7c0f", "#a16207", "#b91c1c", "#be185d", "#7e22ce", "#334155"];

function Swatches({ preset, brand }: { preset: PresetId; brand?: string }) {
	const { palette } = themeColors({ preset, brand });
	return (
		<span className="flex overflow-hidden rounded-md ring-1 ring-black/5" aria-hidden="true">
			{([100, 300, 500, 700, 900] as const).map((s) => (
				<span key={s} className="h-3 flex-1" style={{ backgroundColor: cssOklch(palette[s]) }} />
			))}
		</span>
	);
}

function Banner({ preset, brand }: { preset: PresetId; brand?: string }) {
	const { palette, alt } = themeColors({ preset, brand });
	return (
		<span
			aria-hidden="true"
			className="relative block h-14 overflow-hidden rounded-xl"
			style={{ backgroundImage: `linear-gradient(135deg, ${cssOklch(palette[600])}, ${cssOklch(palette[800])} 55%, ${cssOklch(alt[800])})` }}
		>
			<span className="absolute -top-5 -right-5 size-16 rounded-full bg-white/15" />
			<span className="absolute bottom-2 left-2.5 h-1.5 w-10 rounded-full bg-white/70 dark:bg-white/70" />
			<span className="absolute bottom-5 left-2.5 h-1.5 w-6 rounded-full bg-white/40" />
		</span>
	);
}

function Selected({ on }: { on: boolean }) {
	return on ? (
		<span className="vk-pop absolute top-2 right-2 flex size-6 items-center justify-center rounded-full bg-white text-slate-900 shadow-md ring-1 ring-black/5 dark:bg-white dark:text-slate-900">
			<Check className="size-3.5" strokeWidth={3} aria-hidden="true" />
		</span>
	) : null;
}

const cardClass = (on: boolean, disabled?: boolean) =>
	cn(
		"relative flex flex-col gap-2.5 rounded-2xl bg-white dark:bg-slate-900 p-2.5 text-left shadow-sm ring-1 transition-all",
		on ? "ring-2 ring-brand-600 dark:ring-brand-400" : "ring-slate-900/5 dark:ring-white/10 hover:-translate-y-0.5 hover:shadow-md",
		disabled && "pointer-events-none opacity-50",
	);

/**
 * The theme gallery: presets, optionally "follow the family", and a custom colour.
 * Works as one radio group so screen readers hear one choice.
 */
export function ThemePicker({
	value,
	onChange,
	familyOption,
	disabled,
	label,
}: {
	value: PickerValue;
	onChange(value: PickerValue): void;
	/** Shown for members: keep using whatever the family picks. */
	familyOption?: { name: string; preset: PresetId; brand?: string };
	disabled?: boolean;
	label: string;
}) {
	// Remembers the last custom colour, so switching to a preset and back doesn't lose it.
	const [lastCustom, setLastCustom] = useState(value.brand ?? DEFAULT_CUSTOM_BRAND);
	const customBrand = value.preset === "custom" && value.brand ? value.brand : lastCustom;

	return (
		<div className="space-y-4">
			<div role="radiogroup" aria-label={label} className="grid grid-cols-2 gap-3 sm:grid-cols-3">
				{familyOption && (
					<button
						type="button"
						role="radio"
						aria-checked={value.preset === "family"}
						disabled={disabled}
						onClick={() => onChange({ preset: "family" })}
						className={cardClass(value.preset === "family", disabled)}
					>
						<Banner preset={familyOption.preset} brand={familyOption.brand} />
						<span className="px-0.5">
							<span className="flex items-center gap-1.5 text-sm font-semibold text-slate-900 dark:text-slate-100">
								<Users className="size-3.5 text-brand-700 dark:text-brand-300" aria-hidden="true" />
								Family theme
							</span>
							<span className="block text-xs text-slate-500 dark:text-slate-400">Follow {familyOption.name}, set by your admin</span>
						</span>
						<Selected on={value.preset === "family"} />
					</button>
				)}
				{PRESETS.map((p) => (
					<button
						key={p.id}
						type="button"
						role="radio"
						aria-checked={value.preset === p.id}
						disabled={disabled}
						onClick={() => onChange({ preset: p.id })}
						className={cardClass(value.preset === p.id, disabled)}
					>
						<Banner preset={p.id} />
						<span className="px-0.5">
							<span className="block text-sm font-semibold text-slate-900 dark:text-slate-100">{p.name}</span>
							<span className="block text-xs text-slate-500 dark:text-slate-400">{p.description}</span>
						</span>
						<Swatches preset={p.id} />
						<Selected on={value.preset === p.id} />
					</button>
				))}
				<button
					type="button"
					role="radio"
					aria-checked={value.preset === "custom"}
					disabled={disabled}
					onClick={() => onChange({ preset: "custom", brand: customBrand })}
					className={cardClass(value.preset === "custom", disabled)}
				>
					<span
						aria-hidden="true"
						className="relative flex h-14 items-center justify-center overflow-hidden rounded-xl"
						style={{ backgroundImage: "conic-gradient(from 200deg, #ef4444, #f59e0b, #22c55e, #06b6d4, #6366f1, #d946ef, #ef4444)" }}
					>
						<span className="flex size-8 items-center justify-center rounded-full bg-white/90 text-slate-900 shadow dark:bg-white/90 dark:text-slate-900">
							<Pipette className="size-4" />
						</span>
					</span>
					<span className="px-0.5">
						<span className="block text-sm font-semibold text-slate-900 dark:text-slate-100">Custom</span>
						<span className="block text-xs text-slate-500 dark:text-slate-400">Any colour you like</span>
					</span>
					<Swatches preset="custom" brand={customBrand} />
					<Selected on={value.preset === "custom"} />
				</button>
			</div>

			{value.preset === "custom" && !disabled && (
				<CustomColor
					value={customBrand}
					onChange={(brand) => {
						setLastCustom(brand);
						onChange({ preset: "custom", brand });
					}}
				/>
			)}
		</div>
	);
}

/** Colour well, hex field, suggestions, the generated palette and a readability check. */
function CustomColor({ value, onChange }: { value: string; onChange(hex: string): void }) {
	const id = useId();
	const [text, setText] = useDraft(value);
	const { palette, primary, adjusted } = themeColors({ preset: "custom", brand: value });
	const ratio = contrastRatio(primary, "#ffffff");
	const invalid = normalizeHex(text) === null;

	return (
		<div className="vk-rise space-y-4 rounded-2xl bg-slate-50 dark:bg-slate-800/40 p-4 ring-1 ring-slate-900/5 dark:ring-white/10">
			<div className="flex flex-wrap items-end gap-4">
				<label className="group relative block size-14 shrink-0 cursor-pointer overflow-hidden rounded-2xl shadow-sm ring-1 ring-black/10" style={{ backgroundColor: value }}>
					<span className="sr-only">Pick a colour</span>
					<input
						type="color"
						value={value}
						onChange={(e) => onChange(e.target.value.toLowerCase())}
						className="absolute inset-0 size-full cursor-pointer opacity-0"
					/>
					<Pipette className="absolute right-1.5 bottom-1.5 size-3.5 text-white drop-shadow" aria-hidden="true" />
				</label>
				<div className="grid gap-1.5">
					<label htmlFor={id} className="text-sm font-medium text-slate-900 dark:text-slate-100">
						Hex colour
					</label>
					<Input
						id={id}
						value={text}
						maxLength={7}
						spellCheck={false}
						aria-invalid={invalid}
						className="h-10 w-32 font-mono uppercase"
						onChange={(e) => {
							setText(e.target.value);
							const hex = normalizeHex(e.target.value);
							if (hex) onChange(hex);
						}}
					/>
				</div>
				<div className="grid gap-1.5">
					<span className="text-sm font-medium text-slate-900 dark:text-slate-100">Ideas</span>
					<div className="flex flex-wrap gap-1.5">
						{SUGGESTIONS.map((hex) => (
							<button
								key={hex}
								type="button"
								aria-label={`Use ${hex}`}
								onClick={() => onChange(hex)}
								className={cn(
									"size-7 rounded-full ring-offset-2 ring-offset-slate-50 dark:ring-offset-slate-900 transition-transform hover:scale-110",
									value === hex && "ring-2 ring-slate-900 dark:ring-white",
								)}
								style={{ backgroundColor: hex }}
							/>
						))}
					</div>
				</div>
			</div>
			{invalid && <p className="text-xs text-red-700 dark:text-red-300">Use six hex digits, like #0F766E.</p>}

			<div>
				<p className="mb-1.5 text-xs font-medium text-slate-500 dark:text-slate-400">Your palette</p>
				<div className="grid grid-cols-11 overflow-hidden rounded-xl ring-1 ring-black/5">
					{SHADES.map((s) => (
						<span
							key={s}
							title={`${s} · ${oklchToHex(palette[s])}`}
							className="flex h-10 items-end justify-center pb-1 text-[9px] font-medium"
							style={{ backgroundColor: cssOklch(palette[s]), color: s >= 500 ? "#fff" : "#0f172a" }}
						>
							{s}
						</span>
					))}
				</div>
			</div>

			<p className="text-xs text-slate-600 dark:text-slate-400">
				Buttons use <span className="font-mono">{primary.toUpperCase()}</span> - white text contrast {ratio.toFixed(1)}:1.{" "}
				{adjusted ? "Darkened a little from your colour so button text stays easy to read." : "Easy to read."}
			</p>
		</div>
	);
}
