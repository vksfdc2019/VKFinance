import { OctagonAlert } from "lucide-react";
import { CategoryChip } from "@/components/finance/icons";
import { formatMoney, formatPercent } from "@/lib/format";
import { cn } from "@/lib/utils";

/**
 * Budget against actual: the track is the plan, the bar is what was spent, and a tick marks how
 * far through the month we are. Over-budget rows turn red with an icon and say by how much.
 */
export function BulletBars({
	rows,
	currency,
	progress,
}: {
	rows: { key: string; name: string; icon?: string; color?: string; planned: number; spent: number }[];
	currency: string;
	/** 0-1: how much of the month has gone. */
	progress: number;
}) {
	return (
		<ul className="space-y-3.5">
			{rows.map((r) => {
				const over = r.spent > r.planned && r.planned >= 0;
				const scale = Math.max(r.planned, r.spent, 1);
				const plannedPct = (r.planned / scale) * 100;
				const spentPct = (r.spent / scale) * 100;
				return (
					<li key={r.key}>
						<div className="mb-1.5 flex items-center gap-2.5">
							<CategoryChip icon={r.icon} color={r.color} size="sm" />
							<span className="min-w-0 flex-1 truncate text-sm font-medium text-slate-800 dark:text-slate-200">{r.name}</span>
							<span className="text-sm tabular-nums">
								<span className={cn("font-semibold", over ? "text-red-700 dark:text-red-300" : "text-slate-900 dark:text-slate-100")}>{formatMoney(r.spent, currency)}</span>
								<span className="text-slate-500 dark:text-slate-400"> / {formatMoney(r.planned, currency)}</span>
							</span>
						</div>
						<div className="relative h-2.5 rounded-full bg-slate-100 dark:bg-slate-800" role="img" aria-label={`${r.name}: spent ${formatMoney(r.spent, currency)} of ${formatMoney(r.planned, currency)} planned`}>
							<div className="absolute inset-y-0 left-0 rounded-full bg-slate-200 dark:bg-slate-700" style={{ width: `${plannedPct}%` }} />
							<div
								className="absolute inset-y-0.5 left-0 rounded-full transition-[width] duration-700"
								style={{ width: `${spentPct}%`, backgroundColor: over ? "var(--status-critical)" : "var(--series-magnitude)" }}
							/>
							{progress > 0 && progress < 1 && <div className="absolute -inset-y-1 w-0.5 rounded bg-slate-500 dark:bg-slate-400" style={{ left: `${plannedPct * progress}%` }} aria-hidden="true" />}
						</div>
						{over && (
							<p className="mt-1 inline-flex items-center gap-1 text-[11px] font-medium text-red-700 dark:text-red-300">
								<OctagonAlert className="size-3" aria-hidden="true" />
								{formatMoney(r.spent - r.planned, currency)} over budget
							</p>
						)}
					</li>
				);
			})}
		</ul>
	);
}

/** Ranked amounts as bars of one hue, each labelled with its value and share. */
export function RankBars({ rows, currency }: { rows: { name: string; amount: number; note?: string }[]; currency: string }) {
	const total = rows.reduce((s, r) => s + r.amount, 0);
	const max = Math.max(1, ...rows.map((r) => r.amount));
	return (
		<ol className="space-y-3">
			{rows.map((r, i) => (
				<li key={r.name}>
					<div className="mb-1 flex items-baseline gap-2 text-sm">
						<span className="w-5 text-xs font-semibold tabular-nums text-slate-400">{i + 1}</span>
						<span className="min-w-0 flex-1 truncate font-medium text-slate-800 dark:text-slate-200">{r.name}</span>
						{r.note && <span className="text-[11px] text-slate-500 dark:text-slate-400">{r.note}</span>}
						<span className="font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(r.amount, currency)}</span>
						<span className="w-10 text-right text-xs tabular-nums text-slate-500 dark:text-slate-400">{total > 0 ? formatPercent((r.amount / total) * 100) : ""}</span>
					</div>
					<div className="ml-7 h-2 rounded-full bg-slate-100 dark:bg-slate-800">
						<div className="h-full rounded-full transition-[width] duration-700" style={{ width: `${(r.amount / max) * 100}%`, backgroundColor: "var(--series-magnitude)" }} />
					</div>
				</li>
			))}
		</ol>
	);
}
