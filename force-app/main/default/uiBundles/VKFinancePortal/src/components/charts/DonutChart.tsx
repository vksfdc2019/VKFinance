import { useState, type ReactNode } from "react";
import { formatMoney, formatPercent } from "@/lib/format";
import { cn } from "@/lib/utils";

export interface Slice {
	key: string;
	label: string;
	value: number;
	color: string;
	/** Optional link or action when the slice or its legend row is chosen. */
	onSelect?: () => void;
}

const SIZE = 200;
const GAP = 2;

function arc(cx: number, cy: number, r: number, inner: number, start: number, end: number) {
	const large = end - start > Math.PI ? 1 : 0;
	const p = (rad: number, radius: number) => [cx + radius * Math.sin(rad), cy - radius * Math.cos(rad)];
	const [x1, y1] = p(start, r);
	const [x2, y2] = p(end, r);
	if (inner <= 0) return `M${cx},${cy}L${x1},${y1}A${r},${r} 0 ${large} 1 ${x2},${y2}Z`;
	const [x3, y3] = p(end, inner);
	const [x4, y4] = p(start, inner);
	return `M${x1},${y1}A${r},${r} 0 ${large} 1 ${x2},${y2}L${x3},${y3}A${inner},${inner} 0 ${large} 0 ${x4},${y4}Z`;
}

/**
 * A donut (or, with `pie`, a pie): slices with a 2px surface gap, the hovered slice lifts and is
 * named in the centre, and a legend beside it labels every slice with its amount and share,
 * so nothing depends on colour. Slices past `limit` fold into "Other".
 */
export function DonutChart({
	slices,
	currency,
	label,
	centreLabel,
	centreValue,
	pie,
	limit = 7,
}: {
	slices: Slice[];
	currency: string;
	label: string;
	centreLabel?: string;
	centreValue?: ReactNode;
	pie?: boolean;
	limit?: number;
}) {
	const [active, setActive] = useState<string | null>(null);
	const positive = slices.filter((s) => s.value > 0);
	const shown = positive.slice(0, limit);
	const rest = positive.slice(limit);
	const rows = rest.length ? [...shown, { key: "other", label: `Other (${rest.length})`, value: rest.reduce((s, r) => s + r.value, 0), color: "#94a3b8" }] : shown;
	const total = rows.reduce((s, r) => s + r.value, 0);
	if (total <= 0) return <p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">Nothing to chart for this period.</p>;

	const r = SIZE / 2 - 6;
	const inner = pie ? 0 : r * 0.64;
	const sweep = (v: number) => (v / total) * Math.PI * 2;
	const arcs = rows.map((row, i) => {
		const start = rows.slice(0, i).reduce((s, r) => s + sweep(r.value), 0);
		return { row, start, end: start + sweep(row.value) };
	});
	const focus = rows.find((x) => x.key === active);

	return (
		<div className="@container">
		<div className="flex flex-col items-center gap-5 @lg:flex-row @lg:items-center">
			<div className="relative shrink-0" style={{ width: SIZE, height: SIZE }}>
				<svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`} role="img" aria-label={`${label}: ${rows.map((x) => `${x.label} ${formatPercent((x.value / total) * 100)}`).join(", ")}`}>
					{arcs.map(({ row, start, end }) => {
						const mid = (start + end) / 2;
						const lift = active === row.key ? 5 : 0;
						const full = rows.length === 1;
						return (
							<path
								key={row.key}
								d={full ? arc(SIZE / 2, SIZE / 2, r, inner, 0, Math.PI * 2 - 0.0001) : arc(SIZE / 2, SIZE / 2, r, inner, start, end)}
								fill={row.color}
								stroke="var(--chart-surface)"
								strokeWidth={full ? 0 : GAP}
								strokeLinejoin="round"
								transform={`translate(${lift * Math.sin(mid)} ${-lift * Math.cos(mid)})`}
								className={cn("cursor-pointer transition-[transform,opacity] duration-200", active && active !== row.key && "opacity-45")}
								onMouseEnter={() => setActive(row.key)}
								onMouseLeave={() => setActive(null)}
								onClick={() => (row as Slice).onSelect?.()}
							/>
						);
					})}
				</svg>
				{!pie && (
					<div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center px-8 text-center">
						<span className="text-[11px] text-slate-500 dark:text-slate-400">{focus ? focus.label : (centreLabel ?? "Total")}</span>
						<span className="text-lg font-semibold tracking-tight tabular-nums text-slate-900 dark:text-slate-100">
							{focus ? formatMoney(focus.value, currency) : (centreValue ?? formatMoney(total, currency))}
						</span>
						{focus && <span className="text-[11px] font-medium tabular-nums text-slate-500 dark:text-slate-400">{formatPercent((focus.value / total) * 100)}</span>}
					</div>
				)}
			</div>
			<ul className="w-full min-w-0 flex-1 space-y-1">
				{rows.map((row) => {
					const share = (row.value / total) * 100;
					const select = (row as Slice).onSelect;
					return (
						<li key={row.key}>
							<button
								type="button"
								onMouseEnter={() => setActive(row.key)}
								onMouseLeave={() => setActive(null)}
								onFocus={() => setActive(row.key)}
								onBlur={() => setActive(null)}
								onClick={() => select?.()}
								className={cn("flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left transition-colors", active === row.key ? "bg-slate-100 dark:bg-slate-800" : "hover:bg-slate-50 dark:hover:bg-slate-800/60", !select && "cursor-default")}
							>
								<span className="size-2.5 shrink-0 rounded-sm" style={{ backgroundColor: row.color }} aria-hidden="true" />
								<span className="min-w-0 flex-1 truncate text-sm text-slate-700 dark:text-slate-300">{row.label}</span>
								<span className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(row.value, currency)}</span>
								<span className="w-11 text-right text-xs tabular-nums text-slate-500 dark:text-slate-400">{formatPercent(share)}</span>
							</button>
						</li>
					);
				})}
			</ul>
		</div>
		</div>
	);
}
