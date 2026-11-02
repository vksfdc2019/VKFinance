import { useEffect, useState } from "react";
import { AlertTriangle, CheckCircle2, OctagonAlert } from "lucide-react";
import { prefersReducedMotion } from "@/components/finance/motion";
import { formatPercent } from "@/lib/format";
import { cn } from "@/lib/utils";
import type { MeterStatus } from "@/components/finance/ui";

const W = 200;
const H = 116;
const R = 84;
const STROKE = 14;
const ICON = { good: CheckCircle2, warning: AlertTriangle, critical: OctagonAlert } as const;
const TEXT = {
	good: "text-emerald-800 dark:text-emerald-200",
	warning: "text-amber-800 dark:text-amber-200",
	critical: "text-red-700 dark:text-red-300",
} as const;

function point(pct: number, r = R) {
	const a = Math.PI * (1 - Math.min(100, Math.max(0, pct)) / 100);
	return [W / 2 + r * Math.cos(a), H - 10 - r * Math.sin(a)];
}

function arc(from: number, to: number) {
	const [x1, y1] = point(from);
	const [x2, y2] = point(to);
	return `M${x1},${y1}A${R},${R} 0 0 1 ${x2},${y2}`;
}

/**
 * A half-circle gauge for a ratio with a target - savings rate, EMI burden, card use. The arc
 * wears its status colour, a tick marks the target, and an icon plus words say what it means.
 */
export function Gauge({
	value,
	max = 100,
	target,
	status,
	title,
	verdict,
	hint,
}: {
	value?: number;
	max?: number;
	target: number;
	status: MeterStatus;
	title: string;
	verdict: string;
	hint: string;
}) {
	const pct = value === undefined ? 0 : (Math.min(max, Math.max(0, value)) / max) * 100;
	const [drawn, setDrawn] = useState(prefersReducedMotion() ? pct : 0);
	useEffect(() => {
		const id = requestAnimationFrame(() => setDrawn(pct));
		return () => cancelAnimationFrame(id);
	}, [pct]);
	const length = Math.PI * R;
	const [tx1, ty1] = point((target / max) * 100, R - STROKE / 2 - 3);
	const [tx2, ty2] = point((target / max) * 100, R + STROKE / 2 + 3);
	const Icon = ICON[status];
	return (
		<div className="flex flex-col items-center text-center">
			<p className="text-sm font-semibold text-slate-900 dark:text-slate-100">{title}</p>
			<div className="relative mt-1" style={{ width: W, height: H }}>
				<svg width={W} height={H} role="img" aria-label={`${title}: ${value === undefined ? "no data" : formatPercent(value)}, target ${formatPercent(target)}. ${verdict}`}>
					<path d={arc(0, 100)} fill="none" stroke="var(--chart-grid)" strokeWidth={STROKE} strokeLinecap="round" />
					<path
						d={arc(0, 100)}
						fill="none"
						stroke={`var(--status-${status})`}
						strokeWidth={STROKE}
						strokeLinecap="round"
						strokeDasharray={length}
						strokeDashoffset={length * (1 - drawn / 100)}
						style={{ transition: "stroke-dashoffset 1s cubic-bezier(0.2, 0.8, 0.2, 1)" }}
					/>
					<line x1={tx1} y1={ty1} x2={tx2} y2={ty2} stroke="currentColor" strokeWidth={2} className="text-slate-700 dark:text-slate-300" />
				</svg>
				<div className="absolute inset-x-0 bottom-1 flex flex-col items-center">
					<span className="text-2xl font-semibold tracking-tight tabular-nums text-slate-900 dark:text-slate-100">{value === undefined ? "–" : formatPercent(value)}</span>
					<span className="text-[10px] text-slate-500 dark:text-slate-400">target {formatPercent(target)}</span>
				</div>
			</div>
			<p className={cn("mt-2 inline-flex items-center gap-1 text-xs font-medium", TEXT[status])}>
				<Icon className="size-3.5" aria-hidden="true" />
				{verdict}
			</p>
			<p className="mt-0.5 max-w-52 text-[11px] text-slate-500 dark:text-slate-400">{hint}</p>
		</div>
	);
}
