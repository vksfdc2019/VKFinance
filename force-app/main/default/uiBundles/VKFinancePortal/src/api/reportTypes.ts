/** The generic report shape returned by /reports/{type}. */
export type ReportType =
	| "summary"
	| "category"
	| "members"
	| "trend"
	| "budget"
	| "forecast"
	| "account"
	| "cards"
	| "loans"
	| "bills"
	| "modes"
	| "annual"
	| "security";

export type CellFormat = "money" | "percent" | "number" | "date" | "datetime" | "month" | "text";

export interface ReportKpi {
	label: string;
	value?: number;
	format: CellFormat;
	caption?: string;
}

export interface ReportPoint {
	label: string;
	id?: string;
	icon?: string;
	color?: string;
	target?: number;
	values: Record<string, number>;
}

export interface ReportTable {
	title?: string;
	columns: { key: string; label: string; format: CellFormat }[];
	rows: Record<string, string | number | null | undefined>[];
}

export interface Report {
	type: ReportType;
	title: string;
	subtitle?: string;
	fromDate: string;
	toDate: string;
	kpis: ReportKpi[];
	chart?: { kind: "ranked" | "columns" | "line"; series: { key: string; label: string }[]; points: ReportPoint[] };
	table?: ReportTable;
	detail?: ReportTable;
	note?: string;
	drill?: "category" | "transactions" | "member";
}

export interface ReportFilters {
	from?: string;
	to?: string;
	preset?: string;
	memberId?: string;
	accountId?: string;
	categoryId?: string;
}

export interface SavedReport {
	id: string;
	name: string;
	reportType: ReportType;
	filters: ReportFilters;
	shared: boolean;
	mine: boolean;
	ownerName?: string;
}

export interface LayoutWidget {
	key: string;
	hidden?: boolean;
}
