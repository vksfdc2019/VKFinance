import { vkf } from "./vkfClient";
import type { CreatedMember, DeviceSession, LoginResult, Member, MemberInput, Profile } from "./types";
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

type Message = { message: string };

export const authApi = {
	login: (username: string, password: string) => vkf<LoginResult>("POST", "/auth/login", { username, password }),
	logout: () => vkf<void>("POST", "/auth/logout", {}),
	session: () => vkf<Profile>("GET", "/auth/session"),
	firstLogin: (newPassword: string) => vkf<LoginResult>("POST", "/auth/first-login", { newPassword }),
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
};

export const familyApi = {
	members: () => vkf<Member[]>("GET", "/family/members"),
	addMember: (input: MemberInput) => vkf<CreatedMember>("POST", "/family/members", input),
	updateMember: (id: string, input: MemberInput) =>
		vkf<Member>("PATCH", `/family/members/${encodeURIComponent(id)}`, input),
	unlock: (id: string) => vkf<void>("POST", `/family/members/${encodeURIComponent(id)}/unlock`, {}),
	resetPassword: (id: string, currentPassword: string) =>
		vkf<{ temporaryPassword: string }>("POST", `/family/members/${encodeURIComponent(id)}/reset-password`, {
			currentPassword,
		}),
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
	accounts: (includeClosed = false) => vkf<Account[]>("GET", `/accounts${queryString({ includeClosed })}`),
	transferTargets: () => vkf<AccountRef[]>("GET", "/accounts/targets"),
	createAccount: (input: AccountInput) => vkf<Account>("POST", "/accounts", input),
	updateAccount: (accountId: string, input: AccountInput) => vkf<Account>("PATCH", `/accounts/${id(accountId)}`, input),
	reconcile: (accountId: string, actualBalance: number, note?: string) =>
		vkf<Account>("POST", `/accounts/${id(accountId)}/reconcile`, { actualBalance, note }),

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
};
