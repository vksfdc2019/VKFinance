/** Shapes of the /vkf/v1/deposits endpoints. */

export const COMPOUNDING = ["Quarterly", "Monthly", "Half-yearly", "Yearly"] as const;
export type Compounding = (typeof COMPOUNDING)[number];

export const PAYOUTS = ["On maturity", "Monthly", "Quarterly", "Half-yearly", "Yearly"] as const;
export type Payout = (typeof PAYOUTS)[number];

export const ON_MATURITY = ["Credit to account", "Renew principal", "Renew principal and interest"] as const;
export type OnMaturity = (typeof ON_MATURITY)[number];

export type DepositKind = "FD" | "RD";
export type DepositStatus = "Active" | "Matured" | "Closed Early";

export interface Deposit {
	id: string;
	accountId: string;
	accountName?: string;
	institution?: string;
	ownerId?: string;
	ownerName?: string;
	kind: DepositKind;
	/** Full for the owner and admins; masked for everyone else. */
	depositNumber?: string;
	depositNumberMasked?: string;
	principal?: number;
	instalment?: number;
	rate: number;
	seniorCitizen: boolean;
	compounding: Compounding;
	payout: Payout;
	startDate: string;
	tenureMonths: number;
	tenureDays: number;
	maturityDate: string;
	maturityAmount: number;
	maturityQuoted: boolean;
	calculatedMaturity: number;
	onMaturity: OnMaturity;
	payoutAccountId?: string;
	payoutAccountName?: string;
	fundingAccountId?: string;
	fundingAccountName?: string;
	scheduleRuleId?: string;
	nominee?: string;
	taxSaver: boolean;
	penaltyRate: number;
	form15Submitted: boolean;
	status: DepositStatus;
	closedOn?: string;
	amountReceived?: number;
	notes?: string;
	invested: number;
	interestAtMaturity: number;
	currentValue: number;
	interestThisFy: number;
	payoutPerPeriod?: number;
	instalmentsDue?: number;
	daysToMaturity: number;
	progressPct: number;
	prematureValue?: number;
	lockedIn: boolean;
	effectiveYield?: number;
}

export interface DepositInput {
	depositNumber?: string | null;
	principal?: number | null;
	instalment?: number | null;
	rate?: number | null;
	seniorCitizen?: boolean;
	compounding?: Compounding;
	payout?: Payout;
	startDate?: string;
	tenureMonths?: number | null;
	tenureDays?: number | null;
	/** The bank's figure; null goes back to the calculated one. */
	maturityAmount?: number | null;
	onMaturity?: OnMaturity;
	payoutAccountId?: string | null;
	fundingAccountId?: string | null;
	/** Post RD instalments and FD interest automatically (otherwise suggested for confirmation). */
	autoPost?: boolean;
	nominee?: string | null;
	taxSaver?: boolean;
	penaltyRate?: number | null;
	form15Submitted?: boolean;
	notes?: string | null;
}

export interface CloseDepositInput {
	date?: string;
	amountReceived?: number;
	toAccountId?: string;
}

export interface RenewDepositInput {
	date?: string;
	amountReceived?: number;
	includeInterest?: boolean;
	toAccountId?: string;
	rate?: number;
	tenureMonths?: number;
	tenureDays?: number;
	maturityAmount?: number | null;
}

export interface TdsLine {
	ownerName: string;
	institution?: string;
	interest: number;
	threshold: number;
	estimatedTds: number;
	form15Submitted: boolean;
}

export interface CoverLine {
	ownerName: string;
	institution?: string;
	amount: number;
	uncovered: number;
}

export interface DepositPortfolio {
	deposits: Deposit[];
	invested: number;
	currentValue: number;
	maturityValue: number;
	interestThisFy: number;
	financialYear: string;
	maturingIn30Days: number;
	tds: TdsLine[];
	cover: CoverLine[];
	tdsThreshold: number;
	tdsThresholdSenior: number;
	tdsRate: number;
	dicgcCover: number;
}
