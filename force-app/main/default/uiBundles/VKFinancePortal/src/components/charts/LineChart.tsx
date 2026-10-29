import { useId, useLayoutEffect, useRef, useState } from "react";
import { formatCompact, formatMoney, formatShortDate } from "@/lib/format";

const HEIGHT = 260;
const PAD = { top: 16, right: 12, bottom: 26, left: 56 };

/**
 * One series over time (projected or running balance): a 2px line with a soft area,
 * a crosshair + tooltip on hover, and a dashed zero line when the series dips below it.
 */
export function LineChart({ points, currency, label }: { points: { label: string; value: number }[]; currency: string; label: string }) {
	const ref = useRef<HTMLDivElement>(null);
	const [width, setWidth] = useState(0);
	const [active, setActive] = useState<number | null>(null);
	const gradient = useId().replace(/:/g, "");

	useLayoutEffect(() => {
		const el = ref.current;
		if (!el) return;
		const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
		observer.observe(el);
		setWidth(el.getBoundingClientRect().width);
		return () => observer.disconnect();
	}, []);

	if (points.length === 0) return <p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">Nothing to chart for this period.</p>;
	const values = points.map((p) => p.value);
	const min = Math.min(0, ...values);
	const max = Math.max(1, ...values);
	const span = max - min || 1;
	const innerW = Math.max(0, width - PAD.left - PAD.right);
	const innerH = HEIGHT - PAD.top - PAD.bottom;
	const x = (i: number) => PAD.left + (points.length === 1 ? innerW / 2 : (innerW * i) / (points.length - 1));
	const y = (v: number) => PAD.top + innerH * (1 - (v - min) / span);
	const line = points.map((p, i) => `${i ? "L" : "M"}${x(i)},${y(p.value)}`).join("");
	const area = `${line}L${x(points.length - 1)},${y(min)}L${x(0)},${y(min)}Z`;
	const ticks = [0, 1, 2, 3].map((i) => min + (span * i) / 3);
	const tip = active === null ? null : points[active];

	return (
		<div ref={ref} className="relative" onMouseLeave={() => setActive(null)}>
			{width > 0 && (
				<svg width={width} height={HEIGHT} role="img" aria-label={label}>
					<defs>
						<linearGradient id={gradient} x1="0" x2="0" y1="0" y2="1">
							<stop offset="0%" stopColor="var(--series-magnitude)" stopOpacity="0.22" />
							<stop offset="100%" stopColor="var(--series-magnitude)" stopOpacity="0" />
						</linearGradient>
					</defs>
					{ticks.map((t) => (
						<g key={t}>
							<line x1={PAD.left} x2={width - PAD.right} y1={y(t)} y2={y(t)} stroke="var(--chart-grid)" strokeDasharray="2 4" />
							<text x={PAD.left - 8} y={y(t)} dy="0.32em" textAnchor="end" className="fill-[var(--ink-muted)] text-[11px] tabular-nums">
								{formatCompact(t, currency)}
							</text>
						</g>
					))}
					{min < 0 && <line x1={PAD.left} x2={width - PAD.right} y1={y(0)} y2={y(0)} stroke="var(--status-critical)" strokeDasharray="4 3" />}
					<path d={area} fill={`url(#${gradient})`} />
					<path d={line} fill="none" stroke="var(--series-magnitude)" strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
					{[0, Math.floor((points.length - 1) / 2), points.length - 1].map((i) => (
						<text key={i} x={x(i)} y={HEIGHT - 8} textAnchor={i === 0 ? "start" : i === points.length - 1 ? "end" : "middle"} className="fill-[var(--ink-muted)] text-[11px]">
							{/^\d{4}-\d{2}-\d{2}$/.test(points[i].label) ? formatShortDate(points[i].label) : points[i].label}
						</text>
					))}
					{tip && active !== null && (
						<g>
							<line x1={x(active)} x2={x(active)} y1={PAD.top} y2={PAD.top + innerH} stroke="var(--chart-axis)" />
							<circle cx={x(active)} cy={y(tip.value)} r={5} className="fill-white dark:fill-slate-900" stroke="var(--series-magnitude)" strokeWidth={2} />
						</g>
					)}
					<rect
						x={PAD.left}
						y={PAD.top}
						width={innerW}
						height={innerH}
						fill="transparent"
						onMouseMove={(e) => {
							const box = (e.currentTarget as SVGRectElement).getBoundingClientRect();
							const ratio = (e.clientX - box.left) / box.width;
							setActive(Math.max(0, Math.min(points.length - 1, Math.round(ratio * (points.length - 1)))));
						}}
					/>
				</svg>
			)}
			{tip && active !== null && (
				<div
					className="pointer-events-none absolute top-0 z-10 -translate-x-1/2 rounded-xl bg-slate-900/95 px-3 py-2 text-xs text-white shadow-lg"
					style={{ left: Math.min(Math.max(x(active), 70), width - 70) }}
				>
					<p className="font-semibold">{/^\d{4}-\d{2}-\d{2}$/.test(tip.label) ? formatShortDate(tip.label) : tip.label}</p>
					<p className="tabular-nums">{formatMoney(tip.value, currency)}</p>
				</div>
			)}
		</div>
	);
}
