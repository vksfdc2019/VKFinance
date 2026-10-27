/** Shapes of the /vkf/v1 ledger endpoints. The server omits null fields, so most are optional. */

export const ACCOUNT_TYPES = [
	"Savings",
	"Current",
	"Cash",
	"UPI Wallet",
	"Credit Card",
	"Fixed Deposit",
	"Investment",
	"Loan",
] as const;
export type AccountType = (typeof ACCOUNT_TYPES)[number];

export const ACCOUNT_COLORS = ["teal", "emerald", "sky", "indigo", "violet", "rose", "amber", "orange", "slate", "zinc"] as const;
export type AccountColor = (typeof ACCOUNT_COLORS)[number];

export const PAYMENT_MODES = [
	"UPI",
	"Cash",
	"Debit Card",
	"Credit Card",
	"NEFT/IMPS",
	"Net Banking",
	"Cheque",
	"Auto-debit",
	"Other",
] as const;
export type PaymentMode = (typeof PAYMENT_MODES)[number];

export type TxnType =
	| "Income"
	| "Expense"
	| "Refund"
	| "Transfer Out"
	| "Transfer In"
	| "Card Payment"
	| "Bill Payment"
	| "EMI Payment"
	| "Adjustment";
export type EntryType = "Income" | "Expense" | "Refund";

export interface CardCycle {
	lastStatementDate: string;
	nextStatementDate: string;
	dueDate: string;
	cycleSpend: number;
	available?: number;
	utilisationPct?: number;
}

export interface Account {
	id: string;
	name: string;
	type: AccountType;
	institution?: string;
	last4?: string;
	openingBalance?: number;
	openingDate?: string;
	balance: number;
	isLiability: boolean;
	creditLimit?: number;
	statementDay?: number;
	paymentDueDays?: number;
	minDuePct?: number;
	isShared: boolean;
	status: "Active" | "Closed";
	color?: AccountColor;
	ownerId?: string;
	ownerName?: string;
	canManage: boolean;
	canUse: boolean;
	card?: CardCycle;
}

export interface AccountRef {
	id: string;
	name: string;
	type: AccountType;
	ownerName?: string;
	isLiability: boolean;
	color?: AccountColor;
}

export interface AccountInput {
	name?: string;
	type?: AccountType;
	institution?: string | null;
	last4?: string | null;
	openingBalance?: number | null;
	openingDate?: string | null;
	creditLimit?: number | null;
	statementDay?: number | null;
	paymentDueDays?: number | null;
	minDuePct?: number | null;
	isShared?: boolean;
	color?: AccountColor | null;
	ownerId?: string | null;
	status?: "Active" | "Closed";
}

export interface Category {
	id: string;
	name: string;
	kind: "Income" | "Expense" | "System";
	parentId?: string;
	essential: boolean;
	taxRelevant: boolean;
	icon?: string;
	color?: string;
	sortOrder?: number;
	active: boolean;
	systemKey?: string;
}

export interface CategoryInput {
	name?: string;
	kind?: "Income" | "Expense";
	parentId?: string;
	essential?: boolean;
	taxRelevant?: boolean;
	icon?: string;
	color?: string;
	active?: boolean;
}

export interface Txn {
	id: string;
	name: string;
	type: TxnType;
	direction: "Debit" | "Credit";
	amount: number;
	txnDate: string;
	accountId: string;
	accountName?: string;
	accountType?: AccountType;
	categoryId?: string;
	categoryName?: string;
	parentCategoryName?: string;
	icon?: string;
	color?: string;
	memberId?: string;
	memberName?: string;
	payee?: string;
	notes?: string;
	paymentMode?: PaymentMode;
	referenceNo?: string;
	status: "Cleared" | "Pending" | "Void";
	transferGroupId?: string;
	counterAccountName?: string;
	source?: string;
	canEdit: boolean;
	isPayment?: boolean;
	createdAt?: string;
}

export interface TxnTotals {
	income: number;
	expenses: number;
	transfers: number;
	count: number;
}

export interface TxnPage {
	items: Txn[];
	nextCursor?: string;
	totals?: TxnTotals;
}

export interface TxnQuery {
	month?: string;
	from?: string;
	to?: string;
	type?: string;
	accountId?: string;
	categoryId?: string;
	memberId?: string;
	q?: string;
	includeVoid?: boolean;
	cursor?: string;
	limit?: number;
}

export interface EntryInput {
	type?: EntryType;
	amount?: number;
	date?: string;
	accountId?: string;
	categoryId?: string;
	memberId?: string;
	payee?: string | null;
	notes?: string | null;
	paymentMode?: PaymentMode | null;
	referenceNo?: string | null;
}

export interface TransferInput {
	fromAccountId: string;
	toAccountId: string;
	amount: number;
	date: string;
	notes?: string;
	paymentMode?: PaymentMode;
	referenceNo?: string;
	memberId?: string;
}

export interface Transfer {
	groupId: string;
	outLeg: Txn;
	inLeg: Txn;
}

export interface BudgetLine {
	categoryId: string;
	name: string;
	icon?: string;
	color?: string;
	essential?: boolean;
	planned: number;
	spent: number;
}

export interface BudgetView {
	month: string;
	exists: boolean;
	canEdit: boolean;
	totalPlanned: number;
	totalSpent: number;
	daysInMonth: number;
	daysElapsed: number;
	lines: BudgetLine[];
	unbudgeted: BudgetLine[];
}

export interface Dashboard {
	month: string;
	currencyCode: string;
	memberId?: string;
	wholeFamily: boolean;
	kpis: {
		income: number;
		expenses: number;
		net: number;
		savingsRate?: number;
		prevIncome: number;
		prevExpenses: number;
		essential: number;
		discretionary: number;
	};
	netWorth: { assets: number; liabilities: number; net: number };
	byCategory: { categoryId: string; name: string; icon?: string; color?: string; amount: number }[];
	trend: { month: string; income: number; expenses: number }[];
	budget?: { planned: number; spent: number; overCount: number };
	accounts: Account[];
	recent: Txn[];
	members: { id: string; name: string }[];
	upcoming: import("./commitmentTypes").DueItem[];
}
