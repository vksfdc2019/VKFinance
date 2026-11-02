/** Shape of GET /vkf/v1/dashboard/position. Balances are as of today; flows follow the family month. */

import type { BillInstance, Loan } from "./commitmentTypes";
import type { AccountColor, AccountType, CardNetwork } from "./financeTypes";

export interface PositionSummary {
	liquid: number;
	cardAvailable: number;
	owed: number;
	duesRemaining: number;
	/** Only for the current month. */
	leftAfterDues?: number;
	moneyIn: number;
	moneyOut: number;
}

export interface PositionAccount {
	id: string;
	name: string;
	type: AccountType;
	institution?: string;
	last4?: string;
	color?: AccountColor;
	ownerName?: string;
	isShared?: boolean;
	liquid: boolean;
	balance: number;
	moneyIn: number;
	moneyOut: number;
	maturityDate?: string;
	maturityAmount?: number;
}

export interface BankPosition {
	available: number;
	locked: number;
	moneyIn: number;
	moneyOut: number;
	lowestBalance?: number;
	accounts: PositionAccount[];
}

export interface PositionCard {
	id: string;
	name: string;
	institution?: string;
	last4?: string;
	network?: CardNetwork;
	color?: AccountColor;
	ownerName?: string;
	creditLimit?: number;
	used: number;
	available?: number;
	utilisationPct?: number;
	sharedLimitName?: string;
	spent: number;
	paid: number;
	statementAmount?: number;
	minimumDue?: number;
	amountPaid?: number;
	dueRemaining: number;
	dueDate?: string;
	lateFeeAfter?: string;
	statementStatus?: string;
	nextStatementDate?: string;
}

export interface CardPosition {
	totalLimit: number;
	used: number;
	available: number;
	utilisationPct?: number;
	spent: number;
	paid: number;
	dueNow: number;
	minimumDue: number;
	nextDueDate?: string;
	overdueCount: number;
	cards: PositionCard[];
}

export interface BillPosition {
	due: number;
	paid: number;
	remaining: number;
	overdue: number;
	count: number;
	paidCount: number;
	overdueCount: number;
	items: BillInstance[];
}

export interface PositionLoan {
	loan: Loan;
	emiThisMonth: number;
	paidThisMonth: number;
	dueThisMonth?: string;
	monthStatus: "Paid" | "Due" | "Overdue" | "None";
}

export interface LoanPosition {
	borrowed: number;
	outstanding: number;
	repaid: number;
	repaidPct?: number;
	monthlyEmi: number;
	emiDue: number;
	emiPaid: number;
	emiRemaining: number;
	interestRemaining: number;
	activeCount: number;
	overdueCount: number;
	loans: PositionLoan[];
}

export interface MoneyPosition {
	month: string;
	periodStart: string;
	periodEnd: string;
	asOf: string;
	isCurrent: boolean;
	currencyCode?: string;
	summary: PositionSummary;
	bank?: BankPosition;
	cards?: CardPosition;
	bills?: BillPosition;
	loans?: LoanPosition;
}
