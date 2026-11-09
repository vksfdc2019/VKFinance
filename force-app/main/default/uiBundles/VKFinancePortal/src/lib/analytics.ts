/** The numbers behind the analytics charts: splits, mixes and the three health ratios. */

import { differenceInCalendarDays, parseISO } from "date-fns";
import type { Slice } from "@/components/charts/DonutChart";
import type { MeterStatus } from "@/components/finance/ui";
import type { MonthFlow } from "@/api/analyticsTypes";
import type { Account, AccountType } from "@/api/financeTypes";

/** Income split into EMIs, spending, bills and what was saved - in the validated colour order. */
export function moneySplit(m: MonthFlow): Slice[] {
	return [
		{ key: "emis", label: "EMIs", value: m.emis, color: "var(--viz-emi)" },
		{ key: "spending", label: "Everyday spending", value: m.spending, color: "var(--viz-spend)" },
		{ key: "bills", label: "Bills", value: m.bills, color: "var(--viz-bill)" },
		{ key: "saved", label: "Saved", value: Math.max(0, m.saved), color: "var(--viz-saved)" },
	];
}

const ASSET_GROUPS: { key: string; label: string; types: AccountType[]; color: string }[] = [
	{ key: "bank", label: "Savings & current", types: ["Savings", "Current"], color: "var(--viz-asset-1)" },
	{ key: "cash", label: "Cash & UPI wallets", types: ["Cash", "UPI Wallet"], color: "var(--viz-asset-2)" },
	{ key: "deposits", label: "FDs, RDs & schemes", types: ["Fixed Deposit", "Recurring Deposit", "Savings Scheme"], color: "var(--viz-asset-3)" },
	{ key: "investments", label: "Investments", types: ["Investment"], color: "var(--viz-asset-4)" },
];

/** What you own, by kind of account. */
export function assetMix(accounts: Account[]): Slice[] {
	return ASSET_GROUPS.map((g) => ({
		key: g.key,
		label: g.label,
		color: g.color,
		value: accounts.filter((a) => !a.isLiability && g.types.includes(a.type)).reduce((s, a) => s + Math.max(0, a.balance), 0),
	})).filter((s) => s.value > 0);
}

/** Card limit in use across all cards; a shared limit counts once. */
export function cardUse(accounts: Account[]): { pct?: number; status: MeterStatus } {
	const cards = accounts.filter((a) => a.type === "Credit Card");
	let limit = 0;
	let used = 0;
	const groups = new Map<string, { creditLimit: number; outstanding: number }>();
	for (const c of cards) {
		if (c.sharedCredit) groups.set(c.sharedCredit.id, c.sharedCredit);
		else if (c.creditLimit && c.creditLimit > 0) {
			limit += c.creditLimit;
			used += Math.max(0, c.balance);
		}
	}
	for (const g of groups.values()) {
		limit += g.creditLimit;
		used += Math.max(0, g.outstanding);
	}
	if (limit <= 0) return { status: "good" };
	const pct = Math.round((used / limit) * 1000) / 10;
	return { pct, status: pct > 70 ? "critical" : pct > 30 ? "warning" : "good" };
}

/** EMIs as a share of income - what Indian lenders call FOIR; most prefer it under 40-50%. */
export function emiBurden(m: MonthFlow): { pct?: number; status: MeterStatus } {
	if (m.income <= 0) return { status: m.emis > 0 ? "critical" : "good" };
	const pct = Math.round((m.emis / m.income) * 1000) / 10;
	return { pct, status: pct > 50 ? "critical" : pct > 40 ? "warning" : "good" };
}

export function savingsRateStatus(rate?: number): MeterStatus {
	if (rate === undefined) return "warning";
	return rate >= 20 ? "good" : rate >= 10 ? "warning" : "critical";
}

/** How far through the family month `today` is: 0 before it, 1 after it. */
export function monthProgress(period: { periodStart: string; periodEnd: string }, today: string): number {
	if (today < period.periodStart) return 0;
	if (today > period.periodEnd) return 1;
	const length = differenceInCalendarDays(parseISO(period.periodEnd), parseISO(period.periodStart)) + 1;
	return (differenceInCalendarDays(parseISO(today), parseISO(period.periodStart)) + 1) / length;
}
