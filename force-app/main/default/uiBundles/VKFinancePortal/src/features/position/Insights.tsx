import { useState } from "react";
import { Link } from "react-router";
import { addDays, format, getISODay, parseISO } from "date-fns";
import { AlertTriangle, CalendarDays, CheckCircle2, ChevronRight, Info, OctagonAlert } from "lucide-react";
import { ProgressRing } from "@/components/finance/motion";
import { Panel } from "@/components/finance/ui";
import type { MoneyPosition } from "@/api/positionTypes";
import { formatMoney, formatPercent } from "@/lib/format";
import { alerts, dueEvents, type DueEvent, type Tone } from "@/lib/position";
import { cn } from "@/lib/utils";

const TONE_TEXT: Record<Tone, string> = {
	good: "text-emerald-800 dark:text-emerald-200",
	warning: "text-amber-800 dark:text-amber-200",
	critical: "text-red-700 dark:text-red-300",
};
const TONE_ICON = { good: CheckCircle2, warning: AlertTriangle, critical: OctagonAlert } as const;

/** One sentence that says what a section's numbers mean. */
export function Headline({ text, tone }: { text: string; tone: Tone }) {
	const Icon = TONE_ICON[tone];
	return (
		<p className={cn("mb-4 flex items-start gap-2 rounded-xl px-3 py-2 text-sm font-medium", TONE_TEXT[tone], tone === "good" ? "bg-emerald-50 dark:bg-emerald-950/30" : tone === "warning" ? "bg-amber-50 dark:bg-amber-950/30" : "bg-red-50 dark:bg-red-950/30")}>
			<Icon className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
			<span>{text}</span>
		</p>
	);
}

/** What needs attention now, at the top of the page. */
export function AlertStrip({ data, currency }: { data: MoneyPosition; currency: string }) {
	const list = alerts(data, currency);
	const [open, setOpen] = useState(false);
	if (list.length === 0) return null;
	const shown = open ? list : list.slice(0, 3);
	return (
		<section aria-label="Needs attention" className="mb-4 space-y-2">
			{shown.map((a, i) => {
				const Icon = TONE_ICON[a.tone];
				return (
					<Link
						key={i}
						to={a.link}
						className={cn(
							"vk-rise flex items-center gap-3 rounded-xl px-4 py-2.5 text-sm font-medium ring-1 transition-colors",
							a.tone === "critical"
								? "bg-red-50 dark:bg-red-950/40 text-red-800 dark:text-red-200 ring-red-200/70 dark:ring-red-900/60 hover:bg-red-100/70 dark:hover:bg-red-950/60"
								: "bg-amber-50 dark:bg-amber-950/40 text-amber-900 dark:text-amber-100 ring-amber-200/70 dark:ring-amber-900/60 hover:bg-amber-100/70 dark:hover:bg-amber-950/60",
						)}
						style={{ animationDelay: `${i * 50}ms` }}
					>
						<Icon className="size-4 shrink-0" aria-hidden="true" />
						<span className="flex-1">{a.text}</span>
						<ChevronRight className="size-4 shrink-0 opacity-60" aria-hidden="true" />
					</Link>
				);
			})}
			{list.length > 3 && (
				<button type="button" className="px-1 text-xs font-medium text-slate-600 dark:text-slate-400 hover:underline" onClick={() => setOpen(!open)}>
					{open ? "Show fewer" : `Show ${list.length - 3} more`}
				</button>
			)}
		</section>
	);
}

interface Ring {
	label: string;
	pct: number;
	tone: Tone;
	centre: string;
	caption: string;
}

function rings(p: MoneyPosition, currency: string): Ring[] {
	const out: Ring[] = [];
	const s = p.summary;
	if (p.bank && p.isCurrent && s.liquid > 0 && s.leftAfterDues !== undefined) {
		const pct = Math.max(0, (s.leftAfterDues / s.liquid) * 100);
		out.push({ label: "Free after dues", pct, tone: s.leftAfterDues < 0 ? "critical" : pct < 20 ? "warning" : "good", centre: formatPercent(pct), caption: `${formatMoney(Math.max(0, s.leftAfterDues), currency)} free` });
	}
	if (p.cards && p.cards.totalLimit > 0) {
		const pct = p.cards.utilisationPct ?? 0;
		out.push({ label: "Card limit used", pct, tone: pct > 70 ? "critical" : pct > 30 ? "warning" : "good", centre: formatPercent(pct), caption: `${formatMoney(p.cards.available, currency)} free` });
	}
	if (p.bills && p.bills.due > 0) {
		const pct = (p.bills.paid / p.bills.due) * 100;
		out.push({ label: "Bills paid", pct, tone: p.bills.overdueCount > 0 ? "critical" : "good", centre: `${p.bills.paidCount}/${p.bills.count}`, caption: `${formatMoney(p.bills.remaining, currency)} to pay` });
	}
	if (p.loans && p.loans.borrowed > 0) {
		const pct = p.loans.repaidPct ?? 0;
		out.push({ label: "Loans repaid", pct, tone: p.loans.overdueCount > 0 ? "critical" : "good", centre: formatPercent(pct), caption: `${formatMoney(p.loans.outstanding, currency)} left` });
	}
	return out;
}

/** The month's health in four rings: green is fine, amber needs a look, red needs action. */
export function RingRow({ data, currency }: { data: MoneyPosition; currency: string }) {
	const list = rings(data, currency);
	if (list.length === 0) return null;
	return (
		<div className={cn("mt-4 grid gap-3", list.length >= 4 ? "grid-cols-2 lg:grid-cols-4" : list.length === 3 ? "grid-cols-2 sm:grid-cols-3" : "grid-cols-2")}>
			{list.map((r, i) => (
				<div key={r.label} className="vk-rise vk-lift flex items-center gap-3 rounded-2xl bg-white dark:bg-slate-900 p-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10" style={{ animationDelay: `${120 + i * 60}ms` }}>
					<span className="text-slate-100 dark:text-slate-800">
						<ProgressRing value={r.pct} size={64} stroke={7} color={`var(--status-${r.tone})`} track="currentColor" label={`${r.label}: ${r.centre}`}>
							<span className="text-xs font-semibold tabular-nums text-slate-900 dark:text-slate-100">{r.centre}</span>
						</ProgressRing>
					</span>
					<div className="min-w-0">
						<p className="text-sm font-semibold text-slate-900 dark:text-slate-100">{r.label}</p>
						<p className="truncate text-xs text-slate-500 dark:text-slate-400">{r.caption}</p>
						<p className={cn("mt-0.5 text-[11px] font-medium", TONE_TEXT[r.tone])}>{r.tone === "good" ? "On track" : r.tone === "warning" ? "Keep an eye" : "Needs action"}</p>
					</div>
				</div>
			))}
		</div>
	);
}

const KIND: Record<DueEvent["kind"], { dot: string; label: string }> = {
	bill: { dot: "bg-amber-500", label: "Bill" },
	emi: { dot: "bg-sky-500", label: "EMI" },
	card: { dot: "bg-violet-500", label: "Card bill" },
};
const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** The family month as a calendar, with a dot on every day something is due. */
export function DueCalendar({ data, currency }: { data: MoneyPosition; currency: string }) {
	const events = dueEvents(data);
	const byDay = new Map<string, DueEvent[]>();
	for (const e of events) byDay.set(e.date, [...(byDay.get(e.date) ?? []), e]);
	const start = parseISO(data.periodStart);
	const end = parseISO(data.periodEnd);
	const daysInPeriod: string[] = [];
	for (let d = start; d <= end; d = addDays(d, 1)) daysInPeriod.push(format(d, "yyyy-MM-dd"));
	const today = data.asOf;
	const firstOpen = events.find((e) => !e.done)?.date;
	const [selected, setSelected] = useState<string | undefined>(data.isCurrent && byDay.has(today) ? today : (firstOpen ?? events[0]?.date));
	const picked = selected ? (byDay.get(selected) ?? []) : [];
	const total = events.filter((e) => !e.done).reduce((s, e) => s + e.amount, 0);

	return (
		<Panel
			title={
				<span className="flex items-center gap-2">
					<span className="flex size-7 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300 [&_svg]:size-4" aria-hidden="true">
						<CalendarDays />
					</span>
					When money goes out
				</span>
			}
			description={events.length ? `${events.length} due dates · ${formatMoney(total, currency)} still to pay` : "Nothing is due this month"}
			action={
				<ul className="hidden flex-wrap gap-3 text-[11px] text-slate-500 dark:text-slate-400 sm:flex">
					{Object.values(KIND).map((k) => (
						<li key={k.label} className="inline-flex items-center gap-1.5">
							<span className={cn("size-2 rounded-full", k.dot)} aria-hidden="true" />
							{k.label}
						</li>
					))}
				</ul>
			}
		>
			<div className="grid gap-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
				<div>
					<div className="grid grid-cols-7 gap-1 text-center text-[10px] font-medium uppercase tracking-wide text-slate-400">
						{WEEKDAYS.map((w) => (
							<span key={w}>{w}</span>
						))}
					</div>
					<div className="mt-1 grid grid-cols-7 gap-1">
						{Array.from({ length: getISODay(start) - 1 }, (_, i) => (
							<span key={`pad-${i}`} />
						))}
						{daysInPeriod.map((iso, i) => {
							const dayEvents = byDay.get(iso) ?? [];
							const date = parseISO(iso);
							const late = dayEvents.some((e) => e.late);
							const allDone = dayEvents.length > 0 && dayEvents.every((e) => e.done);
							const isToday = data.isCurrent && iso === today;
							const isPast = data.isCurrent && iso < today;
							return (
								<button
									key={iso}
									type="button"
									disabled={dayEvents.length === 0}
									onClick={() => setSelected(iso)}
									aria-pressed={selected === iso}
									aria-label={`${format(date, "d MMMM")}${dayEvents.length ? `: ${dayEvents.length} due` : ""}`}
									className={cn(
										"relative flex aspect-square flex-col items-center justify-center rounded-xl text-xs tabular-nums transition-colors",
										dayEvents.length ? "bg-slate-50 dark:bg-slate-800/60 font-semibold text-slate-900 dark:text-slate-100 hover:bg-brand-50 dark:hover:bg-brand-950/40" : "text-slate-400 dark:text-slate-500",
										isPast && !dayEvents.length && "opacity-50",
										late && "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
										allDone && "bg-emerald-50/70 dark:bg-emerald-950/30",
										selected === iso && "ring-2 ring-brand-500",
										isToday && selected !== iso && "ring-2 ring-slate-400 dark:ring-slate-500",
									)}
								>
									<span>{date.getDate()}</span>
									{(i === 0 || date.getDate() === 1) && <span className="text-[8px] font-medium uppercase leading-none text-slate-400">{format(date, "MMM")}</span>}
									{dayEvents.length > 0 && (
										<span className="absolute bottom-1 flex gap-0.5" aria-hidden="true">
											{dayEvents.slice(0, 3).map((e, j) => (
												<span key={j} className={cn("size-1.5 rounded-full", e.done ? "bg-emerald-500" : KIND[e.kind].dot)} />
											))}
										</span>
									)}
								</button>
							);
						})}
					</div>
				</div>
				<div className="rounded-2xl bg-slate-50 dark:bg-slate-800/40 p-4">
					{selected && picked.length ? (
						<>
							<p className="text-sm font-semibold text-slate-900 dark:text-slate-100">{format(parseISO(selected), "EEEE, d MMMM")}</p>
							<ul className="mt-3 space-y-2">
								{picked.map((e, i) => (
									<li key={i} className="flex items-center gap-2.5 rounded-xl bg-white dark:bg-slate-900 px-3 py-2 ring-1 ring-slate-900/5 dark:ring-white/10">
										<span className={cn("size-2.5 shrink-0 rounded-full", KIND[e.kind].dot)} aria-hidden="true" />
										<div className="min-w-0 flex-1">
											<p className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">{e.title}</p>
											<p className={cn("text-[11px]", e.late ? "text-red-700 dark:text-red-300" : e.done ? "text-emerald-700 dark:text-emerald-300" : "text-slate-500 dark:text-slate-400")}>
												{KIND[e.kind].label} · {e.done ? "paid" : e.late ? "overdue" : "to pay"}
											</p>
										</div>
										<span className={cn("text-sm font-semibold tabular-nums", e.done ? "text-slate-400 line-through" : "text-slate-900 dark:text-slate-100")}>{formatMoney(e.amount, currency)}</span>
									</li>
								))}
							</ul>
						</>
					) : (
						<p className="flex items-start gap-2 text-sm text-slate-500 dark:text-slate-400">
							<Info className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
							{events.length ? "Tap a day with a dot to see what's due." : "No bills, EMIs or card bills fall in this month."}
						</p>
					)}
				</div>
			</div>
		</Panel>
	);
}
