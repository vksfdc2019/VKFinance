import { vkf } from "./vkfClient";

export interface ArchiveMonth {
	month: string;
	transactions: number;
}

export interface ArchiveSummary {
	archivedThrough?: string;
	months: ArchiveMonth[];
}

export interface ArchivedEntry {
	id: string;
	entryNo?: string;
	txnDate: string;
	type: string;
	direction: "Debit" | "Credit";
	amount: number;
	status: string;
	accountName?: string;
	categoryName?: string;
	memberName?: string;
	payee?: string;
	notes?: string;
	paymentMode?: string;
	reference?: string;
}

export interface ArchivedMonthView {
	month: string;
	income: number;
	spending: number;
	entries: ArchivedEntry[];
}

export const archiveApi = {
	summary: () => vkf<ArchiveSummary>("GET", "/archive"),
	month: (month: string) => vkf<ArchivedMonthView>("GET", `/archive/${encodeURIComponent(month)}`),
};
