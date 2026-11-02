import { vkf } from "./vkfClient";
import type { CreditGroupInput, CreditOverview } from "./creditTypes";
import type { CloseDepositInput, Deposit, DepositInput, DepositPortfolio, RenewDepositInput } from "./depositTypes";
import type {
	CompletedLogin,
	CreatedMember,
	FamilySettings,
	DeviceSession,
	LoginResult,
	Member,
	MemberInput,
	MfaSetup,
	Profile,
	SecurityOverview,
} from "./types";
import type {
	Account,
	AccountInput,
	AccountRef,
	BudgetView,
	Category,
	CategoryInput,
	Dashboard,
	EntryInput,
	Transfer,
	TransferInput,
	Txn,
	TxnPage,
	TxnQuery,
} from "./financeTypes";
import type {
	AppNotification,
	Bill,
	BillInput,
	BillInstance,
	BillsView,
	Loan,
	LoanInput,
	LoanSchedule,
	LoanUpdate,
	RateChange,
	RateChangeInput,
	RecurringRule,
	RuleInput,
	Statement,
} from "./commitmentTypes";
import type { LayoutWidget, Report, ReportFilters, ReportType, SavedReport } from "./reportTypes";
import type { MoneyPosition } from "./positionTypes";
import type { Analytics } from "./analyticsTypes";
import type { Appearance, FamilyTheme, PersonalTheme } from "@/theme/themes";

type Message = { message: string };

export const authApi = {
	login: (username: string, password: string) => vkf<LoginResult>("POST", "/auth/login", { username, password }),
	verifyMfa: (challenge: string, code: string) => vkf<CompletedLogin>("POST", "/auth/mfa", { challenge, code }),
	logout: () => vkf<void>("POST", "/auth/logout", {}),
	session: () => vkf<Profile>("GET", "/auth/session"),
	firstLogin: (newPassword: string) => vkf<CompletedLogin>("POST", "/auth/first-login", { newPassword }),
	changePassword: (currentPassword: string, newPassword: string) =>
		vkf<Message>("PUT", "/auth/password", { currentPassword, newPassword }),
	forgot: (identifier: string) => vkf<Message>("POST", "/auth/forgot", { identifier }),
	reset: (token: string, newPassword: string) => vkf<Message>("POST", "/auth/reset", { token, newPassword }),
};

export const profileApi = {
	me: () => vkf<Profile>("GET", "/profile/me"),
	sessions: () => vkf<DeviceSession[]>("GET", "/profile/sessions"),
	signOutOtherDevices: () => vkf<{ revoked: number }>("DELETE", "/profile/sessions"),
	signOutDevice: (sessionId: string) => vkf<void>("DELETE", `/profile/sessions/${encodeURIComponent(sessionId)}`),
	security: () => vkf<SecurityOverview>("GET", "/profile/security"),
	startMfa: (currentPassword: string) => vkf<MfaSetup>("POST", "/profile/mfa/setup", { currentPassword }),
	confirmMfa: (code: string) => vkf<{ recoveryCodes: string[] }>("POST", "/profile/mfa/confirm", { code }),
	disableMfa: (currentPassword: string, code: string) => vkf<void>("POST", "/profile/mfa/disable", { currentPassword, code }),
	renewRecoveryCodes: (currentPassword: string, code: string) =>
		vkf<{ recoveryCodes: string[] }>("POST", "/profile/mfa/recovery-codes", { currentPassword, code }),
};

/** Themes: your own (anyone) and the family default (Family Admin or Co-Admin). */
export const appearanceApi = {
	savePersonal: (theme: PersonalTheme) => vkf<Appearance>("PUT", "/profile/appearance", theme),
	resetPersonal: () => vkf<Appearance>("DELETE", "/profile/appearance"),
	saveFamily: (theme: FamilyTheme) => vkf<Appearance>("PUT", "/family/appearance", theme),
	resetFamily: () => vkf<Appearance>("DELETE", "/family/appearance"),
};

export const familyApi = {
	settings: () => vkf<FamilySettings>("GET", "/family/settings"),
	/** Family Admin only. */
	saveSettings: (input: { monthStartDay: number }) => vkf<FamilySettings>("PUT", "/family/settings", input),
	members: () => vkf<Member[]>("GET", "/family/members"),
	addMember: (input: MemberInput) => vkf<CreatedMember>("POST", "/family/members", input),
	updateMember: (id: string, input: MemberInput) =>
		vkf<Member>("PATCH", `/family/members/${encodeURIComponent(id)}`, input),
	unlock: (id: string) => vkf<void>("POST", `/family/members/${encodeURIComponent(id)}/unlock`, {}),
	resetPassword: (id: string, currentPassword: string, code?: string) =>
		vkf<{ temporaryPassword: string }>("POST", `/family/members/${encodeURIComponent(id)}/reset-password`, {
			currentPassword,
			code,
		}),
	resetMfa: (id: string, currentPassword: string, code?: string) =>
		vkf<void>("POST", `/family/members/${encodeURIComponent(id)}/reset-mfa`, { currentPassword, code }),
	signOutMember: (id: string) => vkf<{ revoked: number }>("DELETE", `/family/members/${encodeURIComponent(id)}/sessions`),
};

const id = (value: string) => encodeURIComponent(value);

/** Builds a query string, skipping empty values. */
export function queryString(params: object): string {
	const search = new URLSearchParams();
	for (const [key, value] of Object.entries(params)) {
		if (value !== undefined && value !== null && value !== "" && value !== false) search.set(key, String(value));
	}
	const text = search.toString();
	return text ? `?${text}` : "";
}

export const financeApi = {
	creditGroups: () => vkf<CreditOverview>("GET", "/accounts/credit-groups"),
	createCreditGroup: (input: CreditGroupInput) => vkf<CreditOverview>("POST", "/accounts/credit-groups", input),
	updateCreditGroup: (groupId: string, input: CreditGroupInput) => vkf<CreditOverview>("PATCH", `/accounts/credit-groups/${id(groupId)}`, input),
	archiveCreditGroup: (groupId: string, expectedVersion: number) => vkf<CreditOverview>("POST", `/accounts/credit-groups/${id(groupId)}/archive`, { expectedVersion }),
	accounts: (includeClosed = false) => vkf<Account[]>("GET", `/accounts${queryString({ includeClosed })}`),
	transferTargets: () => vkf<AccountRef[]>("GET", "/accounts/targets"),
	createAccount: (input: AccountInput) => vkf<Account>("POST", "/accounts", input),
	updateAccount: (accountId: string, input: AccountInput) => vkf<Account>("PATCH", `/accounts/${id(accountId)}`, input),
	reconcile: (accountId: string, actualBalance: number, note?: string) =>
		vkf<Account>("POST", `/accounts/${id(accountId)}/reconcile`, { actualBalance, note }),
	deposits: () => vkf<DepositPortfolio>("GET", "/deposits"),
	deposit: (accountId: string) => vkf<Deposit>("GET", `/deposits/${id(accountId)}`),
	saveDeposit: (accountId: string, input: DepositInput) => vkf<Deposit>("PATCH", `/deposits/${id(accountId)}`, input),
	closeDeposit: (accountId: string, input: CloseDepositInput) => vkf<Deposit>("POST", `/deposits/${id(accountId)}/close`, input),
	renewDeposit: (accountId: string, input: RenewDepositInput) => vkf<Deposit>("POST", `/deposits/${id(accountId)}/renew`, input),

	categories: () => vkf<Category[]>("GET", "/categories"),
	createCategory: (input: CategoryInput) => vkf<Category>("POST", "/categories", input),
	updateCategory: (categoryId: string, input: CategoryInput) =>
		vkf<Category>("PATCH", `/categories/${id(categoryId)}`, input),

	transactions: (query: TxnQuery) => vkf<TxnPage>("GET", `/transactions${queryString(query)}`),
	createEntry: (input: EntryInput) => vkf<Txn>("POST", "/transactions", input),
	updateTransaction: (txnId: string, input: EntryInput) => vkf<Txn>("PATCH", `/transactions/${id(txnId)}`, input),
	voidTransaction: (txnId: string) => vkf<void>("DELETE", `/transactions/${id(txnId)}`),
	transfer: (input: TransferInput) => vkf<Transfer>("POST", "/transfers", input),

	budget: (month: string) => vkf<BudgetView>("GET", `/budgets/${id(month)}`),
	saveBudget: (month: string, lines: { categoryId: string; planned: number }[]) =>
		vkf<BudgetView>("PUT", `/budgets/${id(month)}`, { lines }),
	copyBudget: (month: string) => vkf<BudgetView>("POST", `/budgets/${id(month)}/copy-previous`, {}),

	dashboard: (month: string, memberId?: string) => vkf<Dashboard>("GET", `/dashboard${queryString({ month, memberId })}`),
	analytics: (month: string, months: number, memberId?: string) =>
		vkf<Analytics>("GET", `/dashboard/analytics${queryString({ month, months, memberId })}`),
	position: (month: string) => vkf<MoneyPosition>("GET", `/dashboard/position${queryString({ month })}`),
};

export const commitmentApi = {
	bills: () => vkf<BillsView>("GET", "/bills"),
	createBill: (input: BillInput) => vkf<Bill>("POST", "/bills", input),
	updateBill: (billId: string, input: BillInput) => vkf<Bill>("PATCH", `/bills/${id(billId)}`, input),
	deleteBill: (billId: string) => vkf<void>("DELETE", `/bills/${id(billId)}`),
	payBill: (instanceId: string, input: { amount?: number; accountId?: string; date?: string; paymentMode?: string }) =>
		vkf<BillInstance>("POST", `/bills/instances/${id(instanceId)}/pay`, input),
	skipBill: (instanceId: string) => vkf<void>("POST", `/bills/instances/${id(instanceId)}/skip`, {}),

	loans: () => vkf<Loan[]>("GET", "/loans"),
	schedule: (loanId: string) => vkf<LoanSchedule>("GET", `/loans/${id(loanId)}/schedule`),
	createLoan: (input: LoanInput) => vkf<Loan>("POST", "/loans", input),
	/** Details just change; corrected terms (amount, rate, tenure, EMIs paid, EMI, outstanding) re-price the loan. null clears a bank figure. */
	updateLoan: (loanId: string, input: LoanUpdate) => vkf<Loan>("PATCH", `/loans/${id(loanId)}`, input),
	deleteLoan: (loanId: string) => vkf<void>("DELETE", `/loans/${id(loanId)}`),
	payEmi: (loanId: string, input: { accountId?: string; date?: string }) => vkf<Loan>("POST", `/loans/${id(loanId)}/pay`, input),
	prepay: (loanId: string, input: { amount: number; accountId?: string; date?: string }) =>
		vkf<Loan>("POST", `/loans/${id(loanId)}/prepay`, input),
	rateChanges: (loanId: string) => vkf<RateChange[]>("GET", `/loans/${id(loanId)}/rates`),
	changeRate: (loanId: string, input: RateChangeInput) => vkf<Loan>("POST", `/loans/${id(loanId)}/rate`, input),

	statements: (accountId: string) => vkf<Statement[]>("GET", `/accounts/${id(accountId)}/statements`),

	rules: () => vkf<RecurringRule[]>("GET", "/recurring"),
	createRule: (input: RuleInput) => vkf<RecurringRule>("POST", "/recurring", input),
	updateRule: (ruleId: string, input: RuleInput) => vkf<RecurringRule>("PATCH", `/recurring/${id(ruleId)}`, input),
	postRule: (ruleId: string, skip = false) => vkf<RecurringRule>("POST", `/recurring/${id(ruleId)}/${skip ? "skip" : "post"}`, {}),

	notifications: () => vkf<{ items: AppNotification[]; unread: number }>("GET", "/notifications"),
	markRead: (ids: string[] = []) => vkf<{ marked: number }>("POST", "/notifications/read", { ids }),
};

export const reportApi = {
	run: (type: ReportType, filters: ReportFilters) =>
		vkf<Report>("GET", `/reports/${id(type)}${queryString({ from: filters.from, to: filters.to, memberId: filters.memberId, accountId: filters.accountId, categoryId: filters.categoryId })}`),
	saved: () => vkf<SavedReport[]>("GET", "/reports/saved"),
	save: (input: { name: string; reportType: ReportType; filters: ReportFilters; shared: boolean }) => vkf<SavedReport>("POST", "/reports/saved", input),
	remove: (reportId: string) => vkf<void>("DELETE", `/reports/saved/${id(reportId)}`),
	layout: () => vkf<{ widgets: LayoutWidget[] }>("GET", "/reports/layout"),
	saveLayout: (widgets: LayoutWidget[]) => vkf<{ widgets: LayoutWidget[] }>("PUT", "/reports/layout", { widgets }),
};
