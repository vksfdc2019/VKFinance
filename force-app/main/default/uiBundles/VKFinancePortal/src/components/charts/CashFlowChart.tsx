import { useLayoutEffect, useRef, useState } from "react";
import { BarChart3, Table2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { formatCompact, formatMoney, monthLabel } from "@/lib/format";

interface Point {
	month: string;
	income: number;
	expenses: number;
}

const HEIGHT = 290;
const PAD = { top: 12, right: 4, bottom: 26, left: 48 };

function useWidth(ref: React.RefObject<HTMLElement | null>) {
	const [width, setWidth] = useState(0);
	useLayoutEffect(() => {
		const el = ref.current;
		if (!el) return;
		const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
		observer.observe(el);
		setWidth(el.getBoundingClientRect().width);
		return () => observer.disconnect();
	}, [ref]);
	return width;
}

/** Rounds the axis maximum up to 1, 2, 2.5 or 5 times a power of ten, so ticks are friendly numbers. */
export function niceMax(value: number, ticks = 4): number {
	if (value <= 0) return ticks;
	const raw = value / ticks;
	const power = 10 ** Math.floor(Math.log10(raw));
	const step = [1, 2, 2.5, 5, 10].map((m) => m * power).find((s) => s * ticks >= value) ?? 10 * power;
	return step * ticks;
}

/** A bar with 4px rounded ends at the top, anchored square to the baseline. */
function barPath(x: number, y: number, w: number, h: number) {
	if (h <= 0) return "";
	const r = Math.min(4, w / 2, h);
	return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
}

/**
 * Income vs spending per month: grouped bars on one axis, hover tooltip per month,
 * legend above, and a table view (the income colour is below 3:1 on white, so the
 * numbers must be reachable without colour).
 */
export function CashFlowChart({ data, currency, highlight }: { data: Point[]; currency: string; highlight?: string }) {
	const ref = useRef<HTMLDivElement>(null);
	const width = useWidth(ref);
	const [active, setActive] = useState<number | null>(null);
	const [table, setTable] = useState(false);

	const max = niceMax(Math.max(1, ...data.flatMap((d) => [d.income, d.expenses])));
	const innerW = Math.max(0, width - PAD.left - PAD.right);
	const innerH = HEIGHT - PAD.top - PAD.bottom;
	const band = data.length ? innerW / data.length : 0;
	const barW = Math.max(4, Math.min(22, (band - 18) / 2));
	const y = (v: number) => PAD.top + innerH * (1 - v / max);
	const ticks = [0, 1, 2, 3, 4].map((i) => (max / 4) * i);
	const tip = active === null ? null : data[active];

	return (
		<div>
			<div className="mb-3 flex items-center justify-between gap-3">
				<ul className="flex items-center gap-4 text-xs text-slate-600 dark:text-slate-400" aria-label="Legend">
					<li className="inline-flex items-center gap-1.5">
						<span className="size-2.5 rounded-sm" style={{ backgroundColor: "var(--series-income)" }} />
						Income
					</li>
					<li className="inline-flex items-center gap-1.5">
						<span className="size-2.5 rounded-sm" style={{ backgroundColor: "var(--series-spend)" }} />
						Spending
					</li>
				</ul>
				<Button variant="ghost" size="xs" onClick={() => setTable((t) => !t)} aria-pressed={table}>
					{table ? <BarChart3 /> : <Table2 />}
					{table ? "Chart" : "Table"}
				</Button>
			</div>

			{table ? (
				<table className="w-full text-sm">
					<thead>
						<tr className="text-left text-xs text-slate-500 dark:text-slate-400">
							<th className="py-1.5 font-medium">Month</th>
							<th className="py-1.5 text-right font-medium">Income</th>
							<th className="py-1.5 text-right font-medium">Spending</th>
							<th className="py-1.5 text-right font-medium">Saved</th>
						</tr>
					</thead>
					<tbody className="tabular-nums">
						{data.map((d) => (
							<tr key={d.month} className="border-t border-slate-100 dark:border-slate-800">
								<td className="py-1.5 text-slate-700 dark:text-slate-300">{monthLabel(d.month)}</td>
								<td className="py-1.5 text-right">{formatMoney(d.income, currency)}</td>
								<td className="py-1.5 text-right">{formatMoney(d.expenses, currency)}</td>
								<td className="py-1.5 text-right font-medium">{formatMoney(d.income - d.expenses, currency)}</td>
							</tr>
						))}
					</tbody>
				</table>
			) : (
				<div ref={ref} className="relative" onMouseLeave={() => setActive(null)}>
					{width > 0 && (
						<svg width={width} height={HEIGHT} role="group" aria-label="Income and spending by month">
							{ticks.map((t) => (
								<g key={t}>
									<line
										x1={PAD.left}
										x2={width - PAD.right}
										y1={y(t)}
										y2={y(t)}
										stroke={t === 0 ? "var(--chart-axis)" : "var(--chart-grid)"}
										strokeWidth={1}
										strokeDasharray={t === 0 ? undefined : "2 4"}
									/>
									<text x={PAD.left - 8} y={y(t)} dy="0.32em" textAnchor="end" className="fill-[var(--ink-muted)] text-[11px] tabular-nums">
										{formatCompact(t, currency)}
									</text>
								</g>
							))}
							{data.map((d, i) => {
								const cx = PAD.left + band * i + band / 2;
								const isActive = active === i;
								const isCurrent = d.month === highlight;
								return (
									<g key={d.month} role="img" aria-label={`${monthLabel(d.month)}: income ${formatMoney(d.income, currency)}, spending ${formatMoney(d.expenses, currency)}`}>
										{(isActive || isCurrent) && (
											<rect
												x={PAD.left + band * i + 4}
												y={PAD.top}
												width={band - 8}
												height={innerH}
												rx={8}
												className={isActive ? "fill-slate-100 dark:fill-slate-800" : "fill-slate-50 dark:fill-slate-800/50"}
											/>
										)}
										<path d={barPath(cx - barW - 1, y(d.income), barW, y(0) - y(d.income))} fill="var(--series-income)" />
										<path d={barPath(cx + 1, y(d.expenses), barW, y(0) - y(d.expenses))} fill="var(--series-spend)" />
										<text
											x={cx}
											y={HEIGHT - 8}
											textAnchor="middle"
											className={isCurrent ? "fill-slate-900 dark:fill-slate-100 text-[11px] font-semibold" : "fill-[var(--ink-muted)] text-[11px]"}
										>
											{monthLabel(d.month, "short")}
										</text>
										{/* Hit target: the whole month column, wider than the bars. */}
										<rect
											x={PAD.left + band * i}
											y={PAD.top}
											width={band}
											height={innerH + PAD.bottom}
											fill="transparent"
											onMouseEnter={() => setActive(i)}
											onFocus={() => setActive(i)}
											onBlur={() => setActive(null)}
											tabIndex={0}
											className="cursor-default outline-none"
										/>
									</g>
								);
							})}
						</svg>
					)}
					{tip && active !== null && (
						<div
							className="pointer-events-none absolute top-0 z-10 w-44 -translate-x-1/2 rounded-xl bg-slate-900/95 px-3 py-2 text-xs text-white shadow-lg"
							style={{ left: Math.min(Math.max(PAD.left + band * active + band / 2, 88), width - 88) }}
						>
							<p className="mb-1 font-semibold">{monthLabel(tip.month)}</p>
							<p className="flex justify-between gap-2">
								<span className="inline-flex items-center gap-1.5">
									<span className="size-2 rounded-sm" style={{ backgroundColor: "var(--series-income)" }} />
									Income
								</span>
								<span className="tabular-nums">{formatMoney(tip.income, currency)}</span>
							</p>
							<p className="flex justify-between gap-2">
								<span className="inline-flex items-center gap-1.5">
									<span className="size-2 rounded-sm" style={{ backgroundColor: "var(--series-spend)" }} />
									Spending
								</span>
								<span className="tabular-nums">{formatMoney(tip.expenses, currency)}</span>
							</p>
							<p className="mt-1 flex justify-between gap-2 border-t border-white/15 pt-1 font-medium">
								<span>Saved</span>
								<span className="tabular-nums">{formatMoney(tip.income - tip.expenses, currency)}</span>
							</p>
						</div>
					)}
				</div>
			)}
		</div>
	);
}
