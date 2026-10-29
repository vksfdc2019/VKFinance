import type { ReactNode } from "react";
import { AlertTriangle, CheckCircle2, ChevronLeft, ChevronRight, OctagonAlert } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { formatMoney, monthKey, monthLabel, shiftMonth } from "@/lib/format";

export function PageHeader({
	title,
	description,
	actions,
}: {
	title: ReactNode;
	description?: ReactNode;
	actions?: ReactNode;
}) {
	return (
		<div className="mb-6 flex flex-wrap items-end justify-between gap-4">
			<div className="min-w-0">
				<h1 className="text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100 sm:text-3xl">{title}</h1>
				{description && <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">{description}</p>}
			</div>
			{actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
		</div>
	);
}

/** A white surface with a soft ring - the building block of every page. */
export function Panel({
	title,
	description,
	action,
	children,
	className,
	bodyClassName,
}: {
	title?: ReactNode;
	description?: ReactNode;
	action?: ReactNode;
	children: ReactNode;
	className?: string;
	bodyClassName?: string;
}) {
	return (
		<section className={cn("rounded-2xl bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10", className)}>
			{(title || action) && (
				<header className="flex items-start justify-between gap-3 px-5 pt-5">
					<div className="min-w-0">
						{title && <h2 className="text-base font-semibold text-slate-900 dark:text-slate-100">{title}</h2>}
						{description && <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">{description}</p>}
					</div>
					{action}
				</header>
			)}
			<div className={cn("p-5", bodyClassName)}>{children}</div>
		</section>
	);
}

export function MonthSwitcher({ value, onChange }: { value: string; onChange: (month: string) => void }) {
	const current = monthKey();
	return (
		<div className="inline-flex items-center rounded-xl bg-white dark:bg-slate-900 p-1 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
			<Button variant="ghost" size="icon-sm" aria-label="Previous month" onClick={() => onChange(shiftMonth(value, -1))}>
				<ChevronLeft />
			</Button>
			<button
				type="button"
				className="min-w-32 rounded-lg px-2 text-center text-sm font-medium text-slate-800 dark:text-slate-200 hover:bg-slate-50 dark:hover:bg-slate-800/60"
				onClick={() => onChange(current)}
				title="Jump to this month"
			>
				{monthLabel(value)}
			</button>
			<Button
				variant="ghost"
				size="icon-sm"
				aria-label="Next month"
				disabled={value >= current}
				onClick={() => onChange(shiftMonth(value, 1))}
			>
				<ChevronRight />
			</Button>
		</div>
	);
}

/** An amount in ink colours: income-like credits read as positive, never colour alone. */
export function Amount({
	value,
	currency,
	direction,
	muted,
	className,
}: {
	value: number;
	currency?: string;
	direction?: "Debit" | "Credit";
	muted?: boolean;
	className?: string;
}) {
	const credit = direction === "Credit";
	return (
		<span
			className={cn(
				"font-semibold tabular-nums",
				muted ? "text-slate-400 line-through" : credit ? "text-emerald-700 dark:text-emerald-300" : "text-slate-900 dark:text-slate-100",
				className,
			)}
		>
			{direction ? (credit ? "+" : "−") : ""}
			{formatMoney(value, currency)}
		</span>
	);
}

export function EmptyState({
	icon,
	title,
	children,
	action,
	className,
}: {
	icon: ReactNode;
	title: string;
	children?: ReactNode;
	action?: ReactNode;
	className?: string;
}) {
	return (
		<div className={cn("flex flex-col items-center justify-center px-6 py-12 text-center", className)}>
			<div className="mb-4 flex size-14 items-center justify-center rounded-2xl bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300 [&_svg]:size-6">
				{icon}
			</div>
			<h3 className="text-base font-semibold text-slate-900 dark:text-slate-100">{title}</h3>
			{children && <p className="mt-1 max-w-sm text-sm text-slate-500 dark:text-slate-400">{children}</p>}
			{action && <div className="mt-5">{action}</div>}
		</div>
	);
}

export function SegmentedControl<T extends string>({
	value,
	options,
	onChange,
	label,
	className,
}: {
	value: T;
	options: { value: T; label: string; disabled?: boolean }[];
	onChange: (value: T) => void;
	label: string;
	className?: string;
}) {
	return (
		<div role="radiogroup" aria-label={label} className={cn("inline-flex rounded-xl bg-slate-100 dark:bg-slate-800 p-1", className)}>
			{options.map((option) => (
				<button
					key={option.value}
					type="button"
					role="radio"
					aria-checked={value === option.value}
					disabled={option.disabled}
					onClick={() => onChange(option.value)}
					className={cn(
						"flex-1 rounded-lg px-3 py-1.5 text-sm font-medium transition-all disabled:opacity-40",
						value === option.value ? "bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 shadow-sm" : "text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200",
					)}
				>
					{option.label}
				</button>
			))}
		</div>
	);
}

export type MeterStatus = "good" | "warning" | "critical";

const STATUS = {
	good: { color: "var(--status-good)", icon: CheckCircle2, text: "text-emerald-800 dark:text-emerald-200" },
	warning: { color: "var(--status-warning)", icon: AlertTriangle, text: "text-amber-800 dark:text-amber-200" },
	critical: { color: "var(--status-critical)", icon: OctagonAlert, text: "text-red-700 dark:text-red-300" },
} as const;

/** A progress bar whose colour is a status - always paired with an icon and a label. */
export function StatusMeter({
	value,
	max,
	status,
	label,
	className,
}: {
	value: number;
	max: number;
	status: MeterStatus;
	label: string;
	className?: string;
}) {
	const pct = max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : value > 0 ? 100 : 0;
	const s = STATUS[status];
	const Icon = s.icon;
	return (
		<div className={className}>
			<div
				className="h-2 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800"
				role="progressbar"
				aria-valuemin={0}
				aria-valuemax={100}
				aria-valuenow={Math.round(pct)}
				aria-label={label}
			>
				<div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${pct}%`, backgroundColor: s.color }} />
			</div>
			<p className={cn("mt-1.5 inline-flex items-center gap-1 text-xs font-medium", s.text)}>
				<Icon className="size-3.5" aria-hidden="true" />
				{label}
			</p>
		</div>
	);
}

export function budgetStatus(spent: number, planned: number, monthProgress: number): MeterStatus {
	if (planned <= 0) return spent > 0 ? "critical" : "good";
	const used = spent / planned;
	if (used > 1) return "critical";
	// Ahead of the calendar (e.g. 80% used a third into the month) deserves a heads-up.
	if (used >= 0.8 || used > monthProgress + 0.15) return "warning";
	return "good";
}

export function utilisationStatus(pct: number): MeterStatus {
	return pct > 70 ? "critical" : pct > 30 ? "warning" : "good";
}

export function DeltaPill({ change, goodWhenUp }: { change?: number; goodWhenUp: boolean }) {
	if (change === undefined || !Number.isFinite(change)) {
		return <span className="text-xs text-slate-400">No data last month</span>;
	}
	const up = change >= 0;
	const good = up === goodWhenUp;
	return (
		<span
			className={cn(
				"inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-xs font-medium tabular-nums",
				good ? "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-800 dark:text-emerald-200" : "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
			)}
		>
			{up ? "▲" : "▼"} {Math.abs(change).toFixed(0)}%<span className="sr-only"> vs last month</span>
		</span>
	);
}

export function MoneyStat({ label, value, currency }: { label: string; value: number; currency?: string }) {
	return (
		<div>
			<p className="text-xs text-slate-500 dark:text-slate-400">{label}</p>
			<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(value, currency)}</p>
		</div>
	);
}
