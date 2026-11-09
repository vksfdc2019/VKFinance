/** Shapes of /vkf/v1/savings: schemes (PPF, SSY, NSC, ...), insurance policies and per-person tax savings. */

export const SCHEME_CODES = ["PPF", "SSY", "NSC", "KVP", "SCSS", "POMIS", "PO_TD", "PO_RD", "NPS", "EPF", "SGB", "OTHER"] as const;
export type SchemeCode = (typeof SCHEME_CODES)[number];
export type SchemeKind = "lump" | "yearly" | "monthly" | "market";

export interface Scheme {
	id: string;
	accountId: string;
	name: string;
	scheme: SchemeCode;
	schemeLabel: string;
	kind: SchemeKind;
	institution?: string;
	ownerId?: string;
	ownerName?: string;
	accountNumber?: string;
	accountNumberMasked?: string;
	beneficiary?: string;
	nominee?: string;
	startDate?: string;
	maturityDate?: string;
	tenureMonths?: number;
	rate?: number;
	principal?: number;
	plannedContribution?: number;
	payout?: string;
	status: "Active" | "Matured" | "Closed";
	balance: number;
	valueAsOf?: string;
	maturityValue?: number;
	payoutAmount?: number;
	contributedThisYear: number;
	roomThisYear?: number;
	depositsOpen?: boolean;
	progressPct?: number;
	daysToMaturity?: number;
	taxSection?: string;
	taxNote?: string;
	canManage?: boolean;
	canDelete?: boolean;
	notes?: string;
}

export interface SchemeInput {
	scheme?: SchemeCode;
	name?: string;
	institution?: string;
	ownerId?: string;
	accountNumber?: string;
	beneficiary?: string;
	nominee?: string;
	startDate?: string;
	tenureMonths?: number | null;
	maturityDate?: string;
	rate?: number | null;
	principal?: number | null;
	plannedContribution?: number | null;
	balance?: number | null;
	notes?: string;
}

export const POLICY_TYPES = ["Term", "Endowment", "Money-back", "Whole life", "ULIP", "Pension", "Health", "Vehicle", "Home", "Other"] as const;
export type PolicyType = (typeof POLICY_TYPES)[number];
export const PREMIUM_MODES = ["Yearly", "Half-yearly", "Quarterly", "Monthly", "Single"] as const;
export type PremiumMode = (typeof PREMIUM_MODES)[number];
export const POLICY_STATUSES = ["Active", "Lapsed", "Paid-up", "Matured", "Surrendered"] as const;
export type PolicyStatus = (typeof POLICY_STATUSES)[number];

export interface Policy {
	id: string;
	insurer: string;
	planName?: string;
	policyType: PolicyType;
	policyNumber?: string;
	policyNumberMasked?: string;
	ownerId?: string;
	ownerName?: string;
	insuredName?: string;
	sumAssured?: number;
	premium?: number;
	frequency: PremiumMode;
	yearlyPremium: number;
	startDate?: string;
	nextDueDate?: string;
	graceDays: number;
	graceEnds?: string;
	premiumState: "Upcoming" | "Due" | "In grace" | "Overdue" | "Finished" | "None";
	policyTermYears?: number;
	premiumTermYears?: number;
	premiumsEnd?: string;
	maturityDate?: string;
	maturityValue?: number;
	nominee?: string;
	taxSection?: "80C" | "80D";
	taxWarnings: string[];
	payFromAccountId?: string;
	payFromAccountName?: string;
	billId?: string;
	openInstanceId?: string;
	status: PolicyStatus;
	canManage?: boolean;
	notes?: string;
}

export interface PolicyInput {
	insurer?: string;
	planName?: string;
	policyType?: PolicyType;
	policyNumber?: string;
	ownerId?: string;
	insuredName?: string;
	sumAssured?: number | null;
	premium?: number | null;
	frequency?: PremiumMode;
	startDate?: string;
	nextDueDate?: string;
	policyTermYears?: number | null;
	premiumTermYears?: number | null;
	maturityValue?: number | null;
	nominee?: string;
	taxSection?: string;
	payFromAccountId?: string;
	status?: PolicyStatus;
	notes?: string;
}

export interface TaxLine {
	label: string;
	amount: number;
}

export interface TaxSummary {
	ownerId: string;
	ownerName?: string;
	financialYear: string;
	section80C: number;
	limit80C: number;
	items80C: TaxLine[];
	section80CCD1B: number;
	limit80CCD1B: number;
	section80D: number;
	limit80D: number;
	items80D: TaxLine[];
}

export interface SavingsPortfolio {
	currencyCode?: string;
	financialYear: string;
	schemes: Scheme[];
	policies: Policy[];
	taxes: TaxSummary[];
	schemesValue: number;
	schemesMaturityValue: number;
	lifeCover: number;
	healthCover: number;
	yearlyPremiums: number;
	canEdit: boolean;
}
