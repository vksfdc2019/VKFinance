/** Shapes of the bills, loans, recurring, statements and notifications endpoints. */

export const BILL_FREQUENCIES = ["Monthly", "Bi-monthly", "Quarterly", "Half-yearly", "Yearly", "One-time"] as const;
export const LOAN_TYPES = ["Home", "Car", "Personal", "Education", "Gold", "Consumer Durable", "Card EMI", "Other"] as const;
export const RATE_TYPES = ["Fixed", "Floating"] as const;
export const RULE_FREQUENCIES = ["Weekly", "Monthly", "Quarterly", "Yearly"] as const;

export type DueStatus = "Upcoming" | "Due" | "Overdue" | "Partially Paid" | "Paid" | "Skipped" | "Unpaid";

export interface Bill {
	id: string;
	name: string;
	categoryId?: string;
	categoryName?: string;
	icon?: string;
	color?: string;
	consumerNo?: string;
	frequency: (typeof BILL_FREQUENCIES)[number];
	nextDueDate?: string;
	expectedAmount?: number;
	payFromAccountId?: string;
	payFromAccountName?: string;
	autoPay: boolean;
	reminderDays?: number;
	responsibleId?: string;
	responsibleName?: string;
	active: boolean;
	paidLast12Months: number;
}

export interface BillInstance {
	id: string;
	billId: string;
	billName: string;
	categoryName?: string;
	icon?: string;
	color?: string;
	dueDate: string;
	amountDue?: number;
	amountPaid?: number;
	status: DueStatus;
	autoPay: boolean;
	payFromAccountId?: string;
	responsibleName?: string;
	daysLeft: number;
	canPay: boolean;
}

export interface BillsView {
	bills: Bill[];
	open: BillInstance[];
	recentlyPaid: BillInstance[];
	dueNext30: number;
	overdue: number;
	canEdit: boolean;
}

export interface BillInput {
	name?: string;
	categoryId?: string;
	frequency?: string;
	nextDueDate?: string;
	expectedAmount?: number | null;
	payFromAccountId?: string | null;
	autoPay?: boolean;
	reminderDays?: number;
	responsibleId?: string | null;
	consumerNo?: string | null;
	active?: boolean;
}

export interface Installment {
	id?: string;
	no: number;
	dueDate: string;
	emi: number;
	principal: number;
	interest: number;
	closing: number;
	status: DueStatus;
	paidOn?: string;
}

export interface Loan {
	id: string;
	name: string;
	lender?: string;
	loanType: (typeof LOAN_TYPES)[number];
	principal: number;
	annualRate: number;
	rateType: (typeof RATE_TYPES)[number];
	tenureMonths: number;
	firstEmiDate: string;
	emi: number;
	outstanding: number;
	installmentsPaid: number;
	installmentsLeft: number;
	repaidPct: number;
	interestRemaining: number;
	payoffDate?: string;
	debitAccountId?: string;
	debitAccountName?: string;
	loanAccountId: string;
	autoDebit: boolean;
	status: "Active" | "Closed";
	borrowerId?: string;
	borrowerName?: string;
	next?: Installment;
	canPay: boolean;
}

export interface LoanInput {
	name: string;
	lender?: string;
	loanType: string;
	principal: number;
	annualRate: number;
	rateType?: string;
	tenureMonths: number;
	firstEmiDate: string;
	emiAmount?: number;
	installmentsPaid?: number;
	/** As per the bank; otherwise worked out from the EMIs already paid. */
	outstandingAmount?: number;
	debitAccountId?: string;
	autoDebit?: boolean;
	borrowerId?: string;
}

export interface RateChange {
	id: string;
	effectiveDate: string;
	oldRate: number;
	newRate: number;
	oldEmi: number;
	newEmi: number;
	oldEmisLeft?: number;
	newEmisLeft?: number;
	outstanding: number;
	adjusted: "EMI" | "Tenure";
	note?: string;
}

export interface RateChangeInput {
	annualRate: number;
	adjust: "EMI" | "Tenure";
	/** The EMI the bank quoted; overrides the calculated one. */
	emiAmount?: number;
	effectiveDate?: string;
	note?: string;
}

export interface LoanSchedule {
	loan: Loan;
	rows: Installment[];
	totalInterestRemaining: number;
}

export interface Statement {
	id: string;
	accountId: string;
	cycleStart: string;
	cycleEnd: string;
	amount: number;
	minimumDue: number;
	dueDate: string;
	amountPaid: number;
	status: "Paid" | "Partially Paid" | "Unpaid" | "Overdue";
}

export interface RecurringRule {
	id: string;
	name: string;
	type: "Expense" | "Income" | "Transfer";
	amount: number;
	accountId: string;
	accountName?: string;
	toAccountId?: string;
	toAccountName?: string;
	categoryId?: string;
	categoryName?: string;
	icon?: string;
	color?: string;
	payee?: string;
	paymentMode?: string;
	frequency: (typeof RULE_FREQUENCIES)[number];
	nextRunDate?: string;
	endDate?: string;
	mode: "Auto-post" | "Suggest";
	active: boolean;
	lastRunDate?: string;
	memberId?: string;
	memberName?: string;
	canEdit: boolean;
}

export interface RuleInput {
	name?: string;
	type?: string;
	amount?: number;
	accountId?: string;
	toAccountId?: string;
	categoryId?: string;
	payee?: string;
	paymentMode?: string;
	frequency?: string;
	nextRunDate?: string;
	endDate?: string | null;
	mode?: string;
	active?: boolean;
}

export interface DueItem {
	kind: "bill" | "emi" | "card";
	id: string;
	parentId: string;
	title: string;
	subtitle?: string;
	amount: number;
	dueDate: string;
	daysLeft: number;
	status: DueStatus;
	icon?: string;
	color?: string;
	link: string;
}

export interface AppNotification {
	id: string;
	type: string;
	severity: "info" | "success" | "warning" | "critical";
	title: string;
	message?: string;
	link?: string;
	read: boolean;
	createdAt: string;
}
