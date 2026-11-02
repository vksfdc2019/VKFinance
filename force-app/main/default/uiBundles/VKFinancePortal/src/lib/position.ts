/** Plain-language readings of the money position: headlines, alerts, a daily allowance and the month's due dates. */

import { differenceInCalendarDays, parseISO } from "date-fns";
import type { MoneyPosition } from "@/api/positionTypes";
import { formatMoney, formatPercent, formatShortDate } from "./format";

/** A spendable account below this shows a low-balance alert (many banks charge below a minimum balance). */
export const LOW_BALANCE = 5000;
/** Dues this close get an alert. */
export const SOON_DAYS = 3;

export type Tone = "good" | "warning" | "critical";

export interface Alert {
	tone: Exclude<Tone, "good">;
	text: string;
	link: string;
}

export interface DueEvent {
	date: string;
	kind: "bill" | "emi" | "card";
	title: string;
	amount: number;
	done: boolean;
	late: boolean;
}

function days(fromIso: string, toIso: string): number {
	return differenceInCalendarDays(parseISO(toIso), parseISO(fromIso));
}

function inDays(n: number): string {
	return n <= 0 ? "today" : n === 1 ? "tomorrow" : `in ${n} days`;
}

/** Days left in the month, today included; 0 outside the current month. */
export function daysLeft(p: MoneyPosition): number {
	return p.isCurrent ? Math.max(1, days(p.asOf, p.periodEnd) + 1) : 0;
}

/** What can be spent each day until month end once this month's dues are kept aside. */
export function dailyAllowance(p: MoneyPosition): number | undefined {
	const left = p.summary.leftAfterDues;
	const n = daysLeft(p);
	if (left === undefined || n === 0) return undefined;
	return Math.max(0, Math.floor(left / n));
}

export function bankHeadline(p: MoneyPosition, currency: string): { text: string; tone: Tone } | undefined {
	const b = p.bank;
	if (!b || b.accounts.length === 0) return undefined;
	const net = b.moneyIn - b.moneyOut;
	if (b.moneyIn === 0 && b.moneyOut === 0) return { text: "No money has moved this month yet.", tone: "good" };
	return net >= 0
		? { text: `${formatMoney(net, currency)} more came in than went out this month.`, tone: "good" }
		: { text: `${formatMoney(-net, currency)} more went out than came in this month.`, tone: "warning" };
}

export function cardHeadline(p: MoneyPosition, currency: string): { text: string; tone: Tone } | undefined {
	const c = p.cards;
	if (!c || c.cards.length === 0) return undefined;
	if (c.overdueCount > 0) return { text: `A card bill is overdue - pay ${formatMoney(c.dueNow, currency)} now to limit late fees and interest.`, tone: "critical" };
	const pct = c.utilisationPct ?? 0;
	const use = `You've used ${formatPercent(pct)} of your card limit`;
	const due = c.dueNow > 0 && c.nextDueDate ? ` ${formatMoney(c.dueNow, currency)} is due ${formatShortDate(c.nextDueDate)}.` : "";
	if (pct > 70) return { text: `${use} - high; it can pull your CIBIL score down.${due}`, tone: "critical" };
	if (pct > 30) return { text: `${use} - keeping it under 30% helps your CIBIL score.${due}`, tone: "warning" };
	return { text: `${use} - healthy.${due}`, tone: "good" };
}

export function billHeadline(p: MoneyPosition, currency: string): { text: string; tone: Tone } | undefined {
	const b = p.bills;
	if (!b || b.items.length === 0) return undefined;
	if (b.overdueCount > 0) {
		return { text: `${b.overdueCount} ${b.overdueCount === 1 ? "bill is" : "bills are"} overdue - ${formatMoney(b.overdue, currency)} to pay.`, tone: "critical" };
	}
	const open = b.items.filter((i) => i.status !== "Paid" && i.status !== "Skipped").sort((x, y) => x.dueDate.localeCompare(y.dueDate));
	if (open.length === 0) return { text: `All ${b.count} ${b.count === 1 ? "bill" : "bills"} paid this month.`, tone: "good" };
	const next = open[0];
	return {
		text: `${open.length} ${open.length === 1 ? "bill" : "bills"} left, ${formatMoney(b.remaining, currency)}. Next is ${next.billName} ${p.isCurrent ? inDays(days(p.asOf, next.dueDate)) : `on ${formatShortDate(next.dueDate)}`}.`,
		tone: "good",
	};
}

export function loanHeadline(p: MoneyPosition, currency: string): { text: string; tone: Tone } | undefined {
	const l = p.loans;
	if (!l || l.loans.length === 0) return undefined;
	if (l.overdueCount > 0) return { text: `An EMI is overdue - pay it soon to avoid penal charges and a hit to your CIBIL score.`, tone: "critical" };
	const active = l.loans.filter((x) => x.loan.status === "Active");
	if (active.length === 0) return { text: "All loans are closed.", tone: "good" };
	if (active.length === 1) {
		const one = active[0].loan;
		return { text: `${one.name} is ${formatPercent(one.repaidPct)} repaid - ${one.installmentsLeft} EMIs to go.`, tone: "good" };
	}
	return { text: `${formatPercent(l.repaidPct ?? 0)} of ${formatMoney(l.borrowed, currency)} repaid across ${active.length} loans.`, tone: "good" };
}

/** What needs attention now, most urgent first. Only for the current month. */
export function alerts(p: MoneyPosition, currency: string): Alert[] {
	if (!p.isCurrent) return [];
	const out: Alert[] = [];
	const left = p.summary.leftAfterDues;
	if (left !== undefined && left < 0) {
		out.push({ tone: "critical", text: `This month's dues are ${formatMoney(-left, currency)} more than your bank balance`, link: "/accounts" });
	}
	for (const c of p.cards?.cards ?? []) {
		if (c.dueRemaining <= 0 || !c.dueDate) continue;
		const n = days(p.asOf, c.dueDate);
		if (c.statementStatus === "Overdue" || n < 0) out.push({ tone: "critical", text: `${c.name} bill of ${formatMoney(c.dueRemaining, currency)} is overdue`, link: "/accounts" });
		else if (n <= SOON_DAYS) out.push({ tone: "warning", text: `${c.name} bill of ${formatMoney(c.dueRemaining, currency)} is due ${inDays(n)}`, link: "/accounts" });
	}
	for (const b of p.bills?.items ?? []) {
		if (b.status === "Paid" || b.status === "Skipped") continue;
		const owed = (b.amountDue ?? 0) - (b.amountPaid ?? 0);
		if (b.status === "Overdue") out.push({ tone: "critical", text: `${b.billName} (${formatMoney(owed, currency)}) is overdue`, link: "/bills" });
		else if (b.daysLeft <= SOON_DAYS && !b.autoPay) out.push({ tone: "warning", text: `${b.billName} (${formatMoney(owed, currency)}) is due ${inDays(b.daysLeft)}`, link: "/bills" });
	}
	for (const l of p.loans?.loans ?? []) {
		if (l.monthStatus === "Overdue") out.push({ tone: "critical", text: `${l.loan.name} EMI is overdue`, link: "/loans" });
	}
	for (const a of p.bank?.accounts ?? []) {
		if (a.liquid && (a.type === "Savings" || a.type === "Current") && a.balance < LOW_BALANCE) {
			out.push({ tone: "warning", text: `Balance is low in ${a.name}: ${formatMoney(a.balance, currency)}`, link: `/transactions?account=${a.id}` });
		}
	}
	return out.sort((x, y) => (x.tone === y.tone ? 0 : x.tone === "critical" ? -1 : 1));
}

/** Every bill, EMI and card due date in the month. */
export function dueEvents(p: MoneyPosition): DueEvent[] {
	const inMonth = (d?: string) => !!d && d >= p.periodStart && d <= p.periodEnd;
	const events: DueEvent[] = [];
	for (const b of p.bills?.items ?? []) {
		if (!inMonth(b.dueDate) || b.status === "Skipped") continue;
		events.push({ date: b.dueDate, kind: "bill", title: b.billName, amount: b.amountDue ?? 0, done: b.status === "Paid", late: b.status === "Overdue" });
	}
	for (const l of p.loans?.loans ?? []) {
		if (!inMonth(l.dueThisMonth) || l.emiThisMonth <= 0) continue;
		events.push({ date: l.dueThisMonth!, kind: "emi", title: `${l.loan.name} EMI`, amount: l.emiThisMonth, done: l.monthStatus === "Paid", late: l.monthStatus === "Overdue" });
	}
	for (const c of p.cards?.cards ?? []) {
		if (!inMonth(c.dueDate) || (c.dueRemaining <= 0 && !c.statementAmount)) continue;
		events.push({ date: c.dueDate!, kind: "card", title: `${c.name} bill`, amount: c.dueRemaining > 0 ? c.dueRemaining : (c.statementAmount ?? 0), done: c.dueRemaining <= 0, late: c.statementStatus === "Overdue" });
	}
	return events.sort((x, y) => x.date.localeCompare(y.date));
}
