import { formatMoney, formatPercent } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface FunnelStep {
	label: string;
	/** What remains after this step. */
	value: number;
	/** What this step took away, shown beside it. */
	minus?: { label: string; value: number; color: string };
}

/**
 * Income narrowing step by step to what was saved: each band's width is what remains, the
 * amount taken at that step sits beside it, and every band is labelled - one hue for magnitude.
 */
export function Funnel({ steps, currency, label }: { steps: FunnelStep[]; currency: string; label: string }) {
	const start = Math.max(1, steps[0]?.value ?? 0);
	return (
		<ol className="space-y-2" aria-label={label}>
			{steps.map((s, i) => {
				const pct = Math.max(0, (s.value / start) * 100);
				const last = i === steps.length - 1;
				const short = s.value < 0;
				return (
					<li key={s.label} className="vk-rise grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3" style={{ animationDelay: `${i * 70}ms` }}>
						<div className="flex flex-col items-center gap-0.5">
							<span className="text-[11px] font-medium text-slate-500 dark:text-slate-400">{s.label}</span>
							<div
								className={cn(
									"relative flex h-10 min-w-24 items-center justify-center rounded-xl px-3 text-white shadow-sm transition-[width] duration-700",
									short ? "bg-[var(--status-critical)]" : last ? "bg-[var(--viz-saved)]" : "bg-[var(--series-magnitude)]",
								)}
								style={{ width: `${Math.max(short ? 100 : 46, pct)}%`, opacity: short || last ? 1 : 1 - i * 0.12 }}
							>
								<span className="text-sm font-semibold tabular-nums">{formatMoney(s.value, currency)}</span>
							</div>
						</div>
						<div className="w-24 text-right text-xs sm:w-32">
							{s.minus ? (
								<>
									<p className="inline-flex items-center gap-1.5 font-medium text-slate-700 dark:text-slate-300">
										<span className="size-2 rounded-sm" style={{ backgroundColor: s.minus.color }} aria-hidden="true" />− {s.minus.label}
									</p>
									<p className="tabular-nums text-slate-500 dark:text-slate-400">
										{formatMoney(s.minus.value, currency)} · {formatPercent((s.minus.value / start) * 100)}
									</p>
								</>
							) : (
								<p className="font-medium text-slate-500 dark:text-slate-400">{i === 0 ? "100%" : formatPercent(pct)}</p>
							)}
						</div>
					</li>
				);
			})}
		</ol>
	);
}
