import { useState } from "react";
import { format, getISODay, parseISO } from "date-fns";
import { formatMoney } from "@/lib/format";
import { cn } from "@/lib/utils";

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
/** Sequential steps of one hue, mixed into the chart surface - light is little, dark is a lot. */
const STEPS = [14, 32, 52, 74, 100];

function step(amount: number, max: number): number {
	if (amount <= 0 || max <= 0) return -1;
	return Math.min(STEPS.length - 1, Math.floor((amount / max) * STEPS.length));
}

function fill(i: number) {
	return i < 0 ? undefined : `color-mix(in oklab, var(--series-magnitude) ${STEPS[i]}%, var(--chart-surface))`;
}

/** Each day of the month shaded by what was spent, Monday first; hover or focus a day for its amount. */
export function SpendHeatmap({ days, currency, today }: { days: { day: string; amount: number }[]; currency: string; today?: string }) {
	const [active, setActive] = useState<number | null>(null);
	if (days.length === 0) return null;
	const max = Math.max(0, ...days.map((d) => d.amount));
	const total = days.reduce((s, d) => s + Math.max(0, d.amount), 0);
	const spentDays = days.filter((d) => d.amount > 0).length;
	const top = days.reduce((best, d) => (d.amount > best.amount ? d : best), days[0]);
	const pad = getISODay(parseISO(days[0].day)) - 1;
	const focus = active === null ? null : days[active];

	return (
		<div className="grid gap-5 lg:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
			<div>
				<div className="grid grid-cols-7 gap-1.5 text-center text-[10px] font-medium uppercase tracking-wide text-slate-400">
					{WEEKDAYS.map((w) => (
						<span key={w}>{w}</span>
					))}
				</div>
				<div className="mt-1.5 grid grid-cols-7 gap-1.5" onMouseLeave={() => setActive(null)}>
					{Array.from({ length: pad }, (_, i) => (
						<span key={`pad-${i}`} />
					))}
					{days.map((d, i) => {
						const s = step(d.amount, max);
						const date = parseISO(d.day);
						return (
							<button
								key={d.day}
								type="button"
								onMouseEnter={() => setActive(i)}
								onFocus={() => setActive(i)}
								onBlur={() => setActive(null)}
								aria-label={`${format(date, "d MMMM")}: ${formatMoney(d.amount, currency)}`}
								className={cn(
									"flex aspect-square items-center justify-center rounded-lg text-[11px] tabular-nums ring-1 ring-slate-900/5 dark:ring-white/5 transition-transform hover:scale-110",
									s < 0 && "bg-slate-50 dark:bg-slate-800/50 text-slate-400",
									s >= 0 && s < 3 && "text-slate-800 dark:text-slate-100",
									s >= 3 && "text-white",
									d.day === today && "ring-2 ring-slate-500 dark:ring-slate-300",
								)}
								style={{ backgroundColor: fill(s) }}
							>
								{date.getDate()}
							</button>
						);
					})}
				</div>
				<div className="mt-3 flex items-center justify-end gap-1.5 text-[10px] text-slate-500 dark:text-slate-400" aria-hidden="true">
					Less
					{STEPS.map((_, i) => (
						<span key={i} className="size-3 rounded" style={{ backgroundColor: fill(i) }} />
					))}
					More
				</div>
			</div>
			<dl className="grid content-start gap-2">
				<div className="rounded-xl bg-slate-50 dark:bg-slate-800/50 px-4 py-3">
					<dt className="text-[11px] text-slate-500 dark:text-slate-400">{focus ? format(parseISO(focus.day), "EEEE, d MMMM") : "Everyday spending"}</dt>
					<dd className="text-xl font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(focus ? focus.amount : total, currency)}</dd>
				</div>
				<div className="grid grid-cols-2 gap-2">
					<div className="rounded-xl bg-slate-50 dark:bg-slate-800/50 px-3 py-2">
						<dt className="text-[11px] text-slate-500 dark:text-slate-400">Days you spent</dt>
						<dd className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">
							{spentDays} of {days.length}
						</dd>
					</div>
					<div className="rounded-xl bg-slate-50 dark:bg-slate-800/50 px-3 py-2">
						<dt className="text-[11px] text-slate-500 dark:text-slate-400">Daily average</dt>
						<dd className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(Math.round(total / days.length), currency)}</dd>
					</div>
				</div>
				{top.amount > 0 && (
					<div className="rounded-xl bg-slate-50 dark:bg-slate-800/50 px-3 py-2">
						<dt className="text-[11px] text-slate-500 dark:text-slate-400">Biggest day</dt>
						<dd className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">
							{format(parseISO(top.day), "EEE d MMM")} · {formatMoney(top.amount, currency)}
						</dd>
					</div>
				)}
			</dl>
		</div>
	);
}
