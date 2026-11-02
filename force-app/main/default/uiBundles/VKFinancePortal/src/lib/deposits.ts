/**
 * The same deposit maths as DepositCalculator.cls, for live previews while typing. Dates are ISO
 * strings; month arithmetic clamps to the month's last day, as Apex's Date.addMonths does.
 */
import type { Compounding, DepositKind, Payout } from "@/api/depositTypes";

const SIMPLE_BELOW_MONTHS = 6;
const DAY = 86_400_000;

function parts(iso: string): [number, number, number] {
	const [y, m, d] = iso.slice(0, 10).split("-").map(Number);
	return [y, m, d];
}

function toIso(y: number, m: number, d: number): string {
	return `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}

function utc(iso: string): number {
	const [y, m, d] = parts(iso);
	return Date.UTC(y, m - 1, d);
}

export function addMonths(iso: string, months: number): string {
	const [y, m, d] = parts(iso);
	const index = m - 1 + months;
	const year = y + Math.floor(index / 12);
	const month = (((index % 12) + 12) % 12) + 1;
	const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
	return toIso(year, month, Math.min(d, last));
}

export function addDays(iso: string, days: number): string {
	const t = new Date(utc(iso) + days * DAY);
	return toIso(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

export function daysBetween(from: string, to: string): number {
	return Math.round((utc(to) - utc(from)) / DAY);
}

export function wholeMonths(from: string, to: string): number {
	const [fy, fm] = parts(from);
	const [ty, tm] = parts(to);
	const m = (ty - fy) * 12 + (tm - fm);
	return addMonths(from, m) > to ? m - 1 : m;
}

const round2 = (v: number) => Math.round(v * 100) / 100;

export function periodMonths(compounding: Compounding): number {
	return compounding === "Monthly" ? 1 : compounding === "Half-yearly" ? 6 : compounding === "Yearly" ? 12 : 3;
}

export function payoutMonths(payout: Payout): number | null {
	return payout === "Monthly" ? 1 : payout === "Quarterly" ? 3 : payout === "Half-yearly" ? 6 : payout === "Yearly" ? 12 : null;
}

export function maturityDate(start: string, months: number, days: number): string {
	return addDays(addMonths(start, months || 0), days || 0);
}

/** A cumulative FD's value on `asOf` (capped at maturity). Under 6 months: simple interest. */
export function fdValue(principal: number, rate: number, compounding: Compounding, start: string, maturity: string, asOf: string): number {
	const upTo = asOf > maturity ? maturity : asOf;
	if (upTo <= start) return principal;
	const r = rate / 100;
	if (addMonths(start, SIMPLE_BELOW_MONTHS) > maturity) return round2(principal * (1 + (r * daysBetween(start, upTo)) / 365));
	const step = periodMonths(compounding);
	let periods = 0;
	while (addMonths(start, step * (periods + 1)) <= upTo) periods++;
	const compounded = addMonths(start, step * periods);
	return round2(principal * Math.pow(1 + (r * step) / 12, periods) * (1 + (r * daysBetween(compounded, upTo)) / 365));
}

/** Interest a payout FD pays each period; monthly is the quarter's interest, discounted. */
export function payoutPerPeriod(principal: number, rate: number, payout: Payout): number {
	const r = rate / 100;
	if (payout === "Monthly") {
		const month = 1 + r / 12;
		return round2((principal * r) / 4 / (1 + month + month * month));
	}
	return round2((principal * r * (payoutMonths(payout) ?? 12)) / 12);
}

export function payoutCount(start: string, maturity: string, payout: Payout): number {
	const step = payoutMonths(payout) ?? 12;
	let n = 0;
	while (addMonths(start, step * (n + 1)) <= maturity) n++;
	return n;
}

export function brokenPeriodInterest(principal: number, rate: number, start: string, maturity: string, payout: Payout): number {
	const last = addMonths(start, (payoutMonths(payout) ?? 12) * payoutCount(start, maturity, payout));
	return round2((((principal * rate) / 100) * daysBetween(last, maturity)) / 365);
}

/** An RD's value on `asOf`: each instalment paid so far, compounded quarterly for its whole months. */
export function rdValue(instalment: number, rate: number, start: string, months: number, asOf: string): number {
	const maturity = addMonths(start, months);
	const upTo = asOf > maturity ? maturity : asOf;
	const quarter = 1 + rate / 400;
	let units = 0;
	for (let i = 0; i < months; i++) {
		const paid = addMonths(start, i);
		if (paid > upTo) break;
		units += Math.pow(quarter, wholeMonths(paid, upTo) / 3);
	}
	return round2(instalment * units);
}

export function rdMaturity(instalment: number, rate: number, months: number, start: string): number {
	return rdValue(instalment, rate, start, months, addMonths(start, months));
}

export function rdInstalmentsDue(start: string, months: number, asOf: string): number {
	if (asOf < start) return 0;
	return Math.min(months, wholeMonths(start, asOf) + 1);
}

export function effectiveYield(invested: number, maturity: number, start: string, end: string): number | undefined {
	const days = daysBetween(start, end);
	if (!(invested > 0) || !(maturity > 0) || days <= 0) return undefined;
	return round2((Math.pow(maturity / invested, 365 / days) - 1) * 100);
}

export interface DepositTerms {
	kind: DepositKind;
	principal: number;
	instalment: number;
	rate: number;
	compounding: Compounding;
	payout: Payout;
	startDate: string;
	months: number;
	days: number;
}

export interface DepositQuote {
	maturityDate: string;
	maturityAmount: number;
	invested: number;
	interest: number;
	payoutPerPeriod?: number;
	effectiveYield?: number;
}

/** The figures a bank would quote for these terms, or null until they are complete. */
/** A whole yyyy-MM-dd date - not one still being typed, and not a 5-digit year a date picker allows. */
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export function quoteDeposit(t: DepositTerms): DepositQuote | null {
	if (!t.startDate || !ISO_DATE.test(t.startDate) || !(t.rate > 0)) return null;
	const maturity = maturityDate(t.startDate, t.months, t.days);
	if (!ISO_DATE.test(maturity) || maturity <= t.startDate) return null;
	if (t.kind === "RD") {
		if (!(t.instalment > 0) || !(t.months > 0)) return null;
		const amount = rdMaturity(t.instalment, t.rate, t.months, t.startDate);
		const invested = t.instalment * t.months;
		return { maturityDate: maturity, maturityAmount: amount, invested, interest: round2(amount - invested) };
	}
	if (!(t.principal > 0)) return null;
	if (t.payout === "On maturity") {
		const amount = fdValue(t.principal, t.rate, t.compounding, t.startDate, maturity, maturity);
		return {
			maturityDate: maturity,
			maturityAmount: amount,
			invested: t.principal,
			interest: round2(amount - t.principal),
			effectiveYield: effectiveYield(t.principal, amount, t.startDate, maturity),
		};
	}
	const each = payoutPerPeriod(t.principal, t.rate, t.payout);
	const broken = brokenPeriodInterest(t.principal, t.rate, t.startDate, maturity, t.payout);
	return {
		maturityDate: maturity,
		maturityAmount: round2(t.principal + broken),
		invested: t.principal,
		interest: round2(each * payoutCount(t.startDate, maturity, t.payout) + broken),
		payoutPerPeriod: each,
	};
}

/** "1 year 3 months 10 days". */
export function tenureLabel(months: number, days: number): string {
	const y = Math.floor(months / 12);
	const m = months % 12;
	const bits = [y && `${y} ${y === 1 ? "year" : "years"}`, m && `${m} ${m === 1 ? "month" : "months"}`, days && `${days} ${days === 1 ? "day" : "days"}`];
	return bits.filter(Boolean).join(" ") || "—";
}
