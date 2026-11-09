/**
 * The Indian savings schemes the app knows, mirroring SchemeRules.cls. Rates are the last notified
 * ones and only a starting point: the rate on the passbook or certificate always wins, and small
 * savings rates are reviewed every quarter.
 */

import type { SchemeCode, SchemeKind } from "@/api/savingsTypes";

export interface SchemeInfo {
	code: SchemeCode;
	short: string;
	label: string;
	kind: SchemeKind;
	blurb: string;
	rate?: number;
	months?: number;
	min?: number;
	max?: number;
	tax?: string;
	taxNote: string;
	/** The holder sets the maturity date (NPS at 60, EPF at retirement). */
	ownMaturity?: boolean;
	beneficiaryLabel?: string;
	/** What the yearly or monthly amount means for this scheme. */
	contributionLabel?: string;
}

export const SCHEMES: SchemeInfo[] = [
	{ code: "PPF", short: "PPF", label: "Public Provident Fund", kind: "yearly", rate: 7.1, months: 180, min: 500, max: 150000, tax: "80C · EEE", taxNote: "Deposits count for 80C; interest and maturity are tax-free.", blurb: "15 years, Rs 500 to Rs 1.5 lakh a year", contributionLabel: "Planned yearly deposit" },
	{ code: "SSY", short: "SSY", label: "Sukanya Samriddhi Yojana", kind: "yearly", rate: 8.2, months: 252, min: 250, max: 150000, tax: "80C · EEE", taxNote: "For a girl child under 10. 80C, and tax-free.", blurb: "Deposit 15 years, matures at 21", beneficiaryLabel: "Girl child's name", contributionLabel: "Planned yearly deposit" },
	{ code: "NSC", short: "NSC", label: "National Savings Certificate", kind: "lump", rate: 7.7, months: 60, min: 1000, tax: "80C", taxNote: "80C on the amount invested; the interest is taxable.", blurb: "5 years, compounds yearly" },
	{ code: "KVP", short: "KVP", label: "Kisan Vikas Patra", kind: "lump", rate: 7.5, months: 115, min: 1000, taxNote: "No deduction; the interest is taxable.", blurb: "Doubles your money in 115 months" },
	{ code: "SCSS", short: "SCSS", label: "Senior Citizens Savings Scheme", kind: "lump", rate: 8.2, months: 60, min: 1000, max: 3000000, tax: "80C", taxNote: "For 60 and over. 80C; the interest is taxable.", blurb: "5 years, interest every quarter, up to Rs 30 lakh" },
	{ code: "POMIS", short: "MIS", label: "Post Office Monthly Income Scheme", kind: "lump", rate: 7.4, months: 60, min: 1000, max: 900000, taxNote: "No deduction; the interest is taxable.", blurb: "5 years, interest every month" },
	{ code: "PO_TD", short: "PO TD", label: "Post Office Time Deposit", kind: "lump", rate: 7.5, months: 60, min: 1000, tax: "80C (5 yr)", taxNote: "Only the 5-year deposit counts for 80C; interest is taxable.", blurb: "1, 2, 3 or 5 years, interest yearly" },
	{ code: "PO_RD", short: "PO RD", label: "Post Office Recurring Deposit", kind: "monthly", rate: 6.7, months: 60, min: 100, taxNote: "No deduction; the interest is taxable.", blurb: "5 years of monthly instalments", contributionLabel: "Monthly instalment" },
	{ code: "NPS", short: "NPS", label: "National Pension System", kind: "market", min: 1000, tax: "80CCD(1B)", taxNote: "Up to Rs 50,000 a year over and above 80C.", blurb: "Market-linked, till age 60", ownMaturity: true, contributionLabel: "Planned yearly contribution" },
	{ code: "EPF", short: "EPF", label: "Employees' Provident Fund / VPF", kind: "yearly", rate: 8.25, tax: "80C", taxNote: "Your share counts for 80C.", blurb: "From salary; rate declared yearly", ownMaturity: true, contributionLabel: "Your yearly contribution" },
	{ code: "SGB", short: "SGB", label: "Sovereign Gold Bond", kind: "market", rate: 2.5, months: 96, taxNote: "Gains tax-free if held 8 years; the 2.5% interest is taxable.", blurb: "8 years, 2.5% a year plus gold price" },
	{ code: "OTHER", short: "Other", label: "Other scheme", kind: "market", taxNote: "", blurb: "Anything else you want to track", ownMaturity: true },
];

export const SCHEME_BY_CODE = Object.fromEntries(SCHEMES.map((s) => [s.code, s])) as Record<SchemeCode, SchemeInfo>;

/** Post Office Time Deposit rates by term, as last notified. */
export const PO_TD_RATES: Record<number, number> = { 12: 6.9, 24: 7.0, 36: 7.1, 60: 7.5 };

/** Each scheme's own colour band, used only as a tint on its card - identity, never data. */
export const SCHEME_TINT: Record<SchemeCode, string> = {
	PPF: "from-brand-alt-600 via-brand-alt-700 to-brand-800",
	SSY: "from-pink-500 via-rose-600 to-rose-800",
	NSC: "from-sky-600 via-sky-700 to-blue-800",
	KVP: "from-lime-600 via-green-700 to-emerald-800",
	SCSS: "from-amber-500 via-orange-600 to-orange-800",
	POMIS: "from-indigo-500 via-indigo-600 to-indigo-800",
	PO_TD: "from-cyan-600 via-cyan-700 to-sky-800",
	PO_RD: "from-violet-500 via-violet-600 to-purple-800",
	NPS: "from-blue-600 via-indigo-700 to-slate-800",
	EPF: "from-brand-600 via-brand-700 to-cyan-800",
	SGB: "from-yellow-500 via-amber-600 to-amber-800",
	OTHER: "from-slate-600 via-slate-700 to-slate-900",
};

/** Years and months, e.g. 115 -> "9 years 7 months". */
export function termLabel(months?: number): string {
	if (!months) return "";
	const y = Math.floor(months / 12);
	const m = months % 12;
	return [y ? `${y} ${y === 1 ? "year" : "years"}` : "", m ? `${m} ${m === 1 ? "month" : "months"}` : ""].filter(Boolean).join(" ");
}

/** The financial year label for a date, e.g. "FY 2026-27". */
export function financialYear(iso: string): string {
	const [y, m] = iso.split("-").map(Number);
	const start = m >= 4 ? y : y - 1;
	return `FY ${start}-${String(start + 1).slice(2)}`;
}
