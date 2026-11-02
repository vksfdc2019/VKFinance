import { useRef, useState } from "react";
import { BarChart3, Table2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatCompact, formatMoney, monthLabel } from "@/lib/format";
import { niceMax } from "./CashFlowChart";
import { useWidth } from "./useWidth";

export interface StackSeries {
	key: string;
	label: string;
	color: string;
}

const HEIGHT = 280;
const PAD = { top: 12, right: 4, bottom: 26, left: 48 };
const GAP = 2;

/**
 * Months as stacked columns on one axis: each part a series, a 2px gap between parts, only the
 * top part rounded. Hover a month for its breakdown; a table view gives every number.
 */
export function StackedBars({
	months,
	series,
	values,
	currency,
	label,
	highlight,
}: {
	months: string[];
	series: StackSeries[];
	values: Record<string, number>[];
	currency: string;
	label: string;
	highlight?: string;
}) {
	const ref = useRef<HTMLDivElement>(null);
	const width = useWidth(ref);
	const [active, setActive] = useState<number | null>(null);
	const [table, setTable] = useState(false);
	const totals = values.map((v) => series.reduce((s, x) => s + Math.max(0, v[x.key] ?? 0), 0));
	const max = niceMax(Math.max(1, ...totals));
	const innerW = Math.max(0, width - PAD.left - PAD.right);
	const innerH = HEIGHT - PAD.top - PAD.bottom;
	const band = months.length ? innerW / months.length : 0;
	const barW = Math.max(6, Math.min(34, band * 0.56));
	const h = (v: number) => (innerH * v) / max;
	const step = months.length > 12 ? 3 : months.length > 8 ? 2 : 1;

	return (
		<div>
			<div className="mb-3 flex flex-wrap items-center justify-between gap-2">
				<ul className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600 dark:text-slate-400">
					{series.map((s) => (
						<li key={s.key} className="inline-flex items-center gap-1.5">
							<span className="size-2.5 rounded-sm" style={{ backgroundColor: s.color }} aria-hidden="true" />
							{s.label}
						</li>
					))}
				</ul>
				<Button variant="ghost" size="xs" onClick={() => setTable(!table)} aria-pressed={table}>
					{table ? <BarChart3 /> : <Table2 />}
					{table ? "Chart" : "Table"}
				</Button>
			</div>
			{table ? (
				<div className="overflow-x-auto">
					<table className="w-full text-sm tabular-nums">
						<thead>
							<tr className="text-left text-xs text-slate-500 dark:text-slate-400">
								<th className="py-1.5 pr-3 font-medium">Month</th>
								{series.map((s) => (
									<th key={s.key} className="py-1.5 pr-3 text-right font-medium">
										{s.label}
									</th>
								))}
								<th className="py-1.5 text-right font-medium">Total</th>
							</tr>
						</thead>
						<tbody className="divide-y divide-slate-100 dark:divide-slate-800">
							{months.map((m, i) => (
								<tr key={m} className="text-slate-800 dark:text-slate-200">
									<td className="py-1.5 pr-3">{monthLabel(m, "short")}</td>
									{series.map((s) => (
										<td key={s.key} className="py-1.5 pr-3 text-right">
											{formatMoney(values[i][s.key] ?? 0, currency)}
										</td>
									))}
									<td className="py-1.5 text-right font-semibold">{formatMoney(totals[i], currency)}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			) : (
				<div ref={ref} className="relative" onMouseLeave={() => setActive(null)}>
					{width > 0 && (
						<svg width={width} height={HEIGHT} role="img" aria-label={label}>
							{[0, 1, 2, 3, 4].map((i) => {
								const v = (max * i) / 4;
								const y = PAD.top + innerH - h(v);
								return (
									<g key={i}>
										<line x1={PAD.left} x2={width - PAD.right} y1={y} y2={y} stroke="var(--chart-grid)" strokeDasharray={i ? "2 4" : undefined} />
										<text x={PAD.left - 8} y={y} dy="0.32em" textAnchor="end" className="fill-[var(--ink-muted)] text-[11px] tabular-nums">
											{formatCompact(v, currency)}
										</text>
									</g>
								);
							})}
							{months.map((m, i) => {
								const x = PAD.left + band * i + (band - barW) / 2;
								let y = PAD.top + innerH;
								const parts = series.map((s) => ({ s, v: Math.max(0, values[i][s.key] ?? 0) })).filter((p) => p.v > 0);
								return (
									<g key={m} opacity={active === null || active === i ? 1 : 0.45} className="transition-opacity">
										{parts.map((p, j) => {
											const ph = h(p.v);
											y -= ph;
											const top = j === parts.length - 1;
											const gap = j > 0 ? GAP : 0;
											const r = top ? Math.min(4, barW / 2, ph) : 0;
											const hh = Math.max(0, ph - gap);
											const d = r
												? `M${x},${y + ph - gap}V${y + r}Q${x},${y} ${x + r},${y}H${x + barW - r}Q${x + barW},${y} ${x + barW},${y + r}V${y + ph - gap}Z`
												: `M${x},${y + hh}V${y}H${x + barW}V${y + hh}Z`;
											return <path key={p.s.key} d={d} fill={p.s.color} />;
										})}
										{i % step === 0 && (
											<text x={x + barW / 2} y={HEIGHT - 8} textAnchor="middle" className={m === highlight ? "fill-slate-900 dark:fill-slate-100 text-[11px] font-semibold" : "fill-[var(--ink-muted)] text-[11px]"}>
												{monthLabel(m, "short").split(" ")[0]}
											</text>
										)}
										<rect x={PAD.left + band * i} y={PAD.top} width={band} height={innerH} fill="transparent" onMouseEnter={() => setActive(i)} />
									</g>
								);
							})}
						</svg>
					)}
					{active !== null && width > 0 && (
						<div
							className="pointer-events-none absolute top-2 z-10 w-48 rounded-xl bg-white dark:bg-slate-900 p-3 text-xs shadow-lg ring-1 ring-slate-900/10 dark:ring-white/10"
							style={{ left: Math.min(Math.max(0, PAD.left + band * active + band / 2 - 96), width - 192) }}
						>
							<p className="mb-1.5 font-semibold text-slate-900 dark:text-slate-100">{monthLabel(months[active])}</p>
							{[...series].reverse().map((s) => (
								<p key={s.key} className="flex items-center justify-between gap-2 py-0.5 text-slate-600 dark:text-slate-400">
									<span className="inline-flex items-center gap-1.5">
										<span className="size-2 rounded-sm" style={{ backgroundColor: s.color }} aria-hidden="true" />
										{s.label}
									</span>
									<span className="font-medium tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(values[active][s.key] ?? 0, currency)}</span>
								</p>
							))}
							<p className="mt-1 flex justify-between border-t border-slate-100 dark:border-slate-800 pt-1.5 font-semibold text-slate-900 dark:text-slate-100">
								<span>Total</span>
								<span className="tabular-nums">{formatMoney(totals[active], currency)}</span>
							</p>
						</div>
					)}
				</div>
			)}
		</div>
	);
}
