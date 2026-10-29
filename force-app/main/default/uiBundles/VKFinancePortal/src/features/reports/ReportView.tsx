import { useMemo, useState, type FormEvent } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router";
import { ArrowDownUp, ChevronLeft, Download, Printer, Save } from "lucide-react";
import { endOfMonth, endOfQuarter, format, startOfMonth, startOfQuarter, startOfYear, subMonths } from "date-fns";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { CashFlowChart } from "@/components/charts/CashFlowChart";
import { LineChart } from "@/components/charts/LineChart";
import { CategoryChip } from "@/components/finance/icons";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { Panel } from "@/components/finance/ui";
import { familyApi, financeApi, reportApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { CellFormat, Report, ReportPoint, ReportTable, ReportType } from "@/api/reportTypes";
import { formatDate, formatDateTime, formatMoney, formatPercent, monthLabel } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { REPORT_INFO } from "./ReportsPage";

const PRESETS = [
	{ key: "this-month", label: "This month" },
	{ key: "last-month", label: "Last month" },
	{ key: "this-quarter", label: "This quarter" },
	{ key: "ytd", label: "Year to date" },
	{ key: "fy", label: "This financial year" },
	{ key: "last-12", label: "Last 12 months" },
	{ key: "custom", label: "Custom" },
];

const iso = (d: Date) => format(d, "yyyy-MM-dd");

export function presetRange(preset: string, today = new Date()): { from: string; to: string } | null {
	switch (preset) {
		case "this-month":
			return { from: iso(startOfMonth(today)), to: iso(endOfMonth(today)) };
		case "last-month": {
			const last = subMonths(today, 1);
			return { from: iso(startOfMonth(last)), to: iso(endOfMonth(last)) };
		}
		case "this-quarter":
			return { from: iso(startOfQuarter(today)), to: iso(endOfQuarter(today)) };
		case "ytd":
			return { from: iso(startOfYear(today)), to: iso(today) };
		case "fy": {
			const startYear = today.getMonth() >= 3 ? today.getFullYear() : today.getFullYear() - 1;
			return { from: `${startYear}-04-01`, to: `${startYear + 1}-03-31` };
		}
		case "last-12":
			return { from: iso(startOfMonth(subMonths(today, 11))), to: iso(endOfMonth(today)) };
		default:
			return null;
	}
}

const FIXED_PERIOD: ReportType[] = ["forecast", "loans"];
const MEMBER_FILTER: ReportType[] = ["summary", "category", "trend", "modes", "cards"];

export function formatCell(value: unknown, fmt: CellFormat, currency: string): string {
	if (value === null || value === undefined || value === "") return "—";
	switch (fmt) {
		case "money":
			return formatMoney(Number(value), currency);
		case "percent":
			return formatPercent(Number(value), 1);
		case "number":
			return Number(value).toLocaleString("en-IN");
		case "date":
			return formatDate(String(value));
		case "datetime":
			return formatDateTime(String(value));
		case "month":
			return monthLabel(String(value));
		default:
			return String(value);
	}
}

export function toCsv(tables: ReportTable[]): string {
	const lines: string[] = [];
	for (const t of tables) {
		if (t.title) lines.push(`"${t.title.replace(/"/g, '""')}"`);
		lines.push(t.columns.map((c) => `"${c.label}"`).join(","));
		for (const row of t.rows) {
			lines.push(t.columns.map((c) => `"${String(row[c.key] ?? "").replace(/"/g, '""')}"`).join(","));
		}
		lines.push("");
	}
	return lines.join("\r\n");
}

export default function ReportView() {
	const { type = "summary" } = useParams<{ type: ReportType }>();
	const info = REPORT_INFO[type as ReportType];
	const { profile } = useAuth();
	const { currency } = useLedger();
	const navigate = useNavigate();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [params, setParams] = useSearchParams();
	const preset = params.get("preset") ?? (params.get("from") ? "custom" : type === "annual" ? "fy" : type === "trend" ? "last-12" : "this-month");
	const range = presetRange(preset) ?? { from: params.get("from") ?? presetRange("this-month")!.from, to: params.get("to") ?? presetRange("this-month")!.to };
	const filters = {
		from: FIXED_PERIOD.includes(type as ReportType) ? undefined : range.from,
		to: FIXED_PERIOD.includes(type as ReportType) ? undefined : range.to,
		memberId: params.get("memberId") ?? undefined,
		accountId: params.get("accountId") ?? undefined,
		categoryId: params.get("categoryId") ?? undefined,
	};
	const [saving, setSaving] = useState(false);

	const { data: options } = useAsync(
		() =>
			Promise.all([isAdmin ? familyApi.members() : Promise.resolve([]), type === "account" ? financeApi.accounts(true) : Promise.resolve([])]).then(
				([members, accounts]) => ({ members, accounts }),
			),
		[type, isAdmin],
	);
	const needsAccount = type === "account" && !filters.accountId;
	const { data: report, errors, loading } = useAsync<Report | null>(
		() => (needsAccount ? Promise.resolve(null) : reportApi.run(type as ReportType, filters)),
		[type, filters.from, filters.to, filters.memberId, filters.accountId, filters.categoryId],
	);

	function setParam(changes: Record<string, string | undefined>) {
		const next = new URLSearchParams(params);
		for (const [k, v] of Object.entries(changes)) {
			if (v) next.set(k, v);
			else next.delete(k);
		}
		setParams(next, { replace: true });
	}

	function drill(id?: string, label?: string) {
		if (!id || !report?.drill) return;
		const period = preset === "custom" ? `preset=custom&from=${range.from}&to=${range.to}` : `preset=${preset}`;
		const member = filters.memberId ? `&memberId=${filters.memberId}` : "";
		if (report.drill === "category" && type === "category") setParam({ categoryId: id });
		else if (report.drill === "category") navigate(`/reports/category?categoryId=${id}&${period}${member}`);
		else if (report.drill === "member") navigate(`/reports/summary?memberId=${id}&preset=${preset}`);
		else if (report.drill === "transactions") navigate(`/transactions?category=${id}&month=${range.from.slice(0, 7)}`);
		void label;
	}

	function exportCsv() {
		if (!report) return;
		const tables = [report.table, report.detail].filter(Boolean) as ReportTable[];
		const url = URL.createObjectURL(new Blob([toCsv(tables)], { type: "text/csv;charset=utf-8" }));
		Object.assign(document.createElement("a"), { href: url, download: `vk-finance-${type}-${report.fromDate}-${report.toDate}.csv` }).click();
		URL.revokeObjectURL(url);
	}

	if (!info) {
		return <p className="text-sm text-slate-600 dark:text-slate-400">That report doesn&apos;t exist. <Link to="/reports" className="text-brand-700 dark:text-brand-300 underline">See all reports</Link></p>;
	}

	return (
		<>
			<div className="no-print mb-2">
				<Link to="/reports" className="inline-flex items-center gap-1 text-sm text-slate-500 dark:text-slate-400 hover:text-slate-800 dark:hover:text-slate-200">
					<ChevronLeft className="size-4" aria-hidden="true" />
					Reports
				</Link>
			</div>
			<div className="mb-5 flex flex-wrap items-end justify-between gap-4">
				<div>
					<h1 className="text-2xl font-semibold tracking-tight text-slate-900 dark:text-slate-100 sm:text-3xl">{report?.title ?? info.title}</h1>
					<p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
						{report?.subtitle ?? info.text}
						{report && !FIXED_PERIOD.includes(type as ReportType) && type !== "forecast" ? ` · ${formatDate(report.fromDate)} – ${formatDate(report.toDate)}` : ""}
					</p>
				</div>
				<div className="no-print flex flex-wrap gap-2">
					<Button variant="outline" onClick={exportCsv} disabled={!report?.table}>
						<Download />
						CSV
					</Button>
					<Button variant="outline" onClick={() => window.print()} disabled={!report}>
						<Printer />
						Print
					</Button>
					<Button onClick={() => setSaving(true)} disabled={!report}>
						<Save />
						Save
					</Button>
				</div>
			</div>

			<div className="no-print mb-5 flex flex-wrap items-center gap-2">
				{!FIXED_PERIOD.includes(type as ReportType) && (
					<Select value={preset} onValueChange={(v) => setParam({ preset: v === "custom" ? "custom" : v, from: v === "custom" ? range.from : undefined, to: v === "custom" ? range.to : undefined })}>
						<SelectTrigger className="h-9 w-48 rounded-xl bg-white dark:bg-slate-900" aria-label="Period">
							<SelectValue />
						</SelectTrigger>
						<SelectContent>
							{PRESETS.map((p) => (
								<SelectItem key={p.key} value={p.key}>
									{p.label}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				)}
				{preset === "custom" && !FIXED_PERIOD.includes(type as ReportType) && (
					<>
						<Input type="date" aria-label="From" className="h-9 w-40 rounded-xl bg-white dark:bg-slate-900" value={range.from} onChange={(e) => setParam({ preset: "custom", from: e.target.value, to: range.to })} />
						<Input type="date" aria-label="To" className="h-9 w-40 rounded-xl bg-white dark:bg-slate-900" value={range.to} onChange={(e) => setParam({ preset: "custom", from: range.from, to: e.target.value })} />
					</>
				)}
				{isAdmin && MEMBER_FILTER.includes(type as ReportType) && (
					<Select value={filters.memberId ?? "all"} onValueChange={(v) => setParam({ memberId: v === "all" ? undefined : v })}>
						<SelectTrigger className="h-9 w-48 rounded-xl bg-white dark:bg-slate-900" aria-label="Member">
							<SelectValue />
						</SelectTrigger>
						<SelectContent>
							<SelectItem value="all">Whole family</SelectItem>
							{options?.members.map((m) => (
								<SelectItem key={m.id} value={m.id}>
									{m.firstName} {m.lastName}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				)}
				{type === "account" && (
					<Select value={filters.accountId ?? ""} onValueChange={(v) => setParam({ accountId: v })}>
						<SelectTrigger className="h-9 w-56 rounded-xl bg-white dark:bg-slate-900" aria-label="Account">
							<SelectValue placeholder="Choose an account" />
						</SelectTrigger>
						<SelectContent>
							{options?.accounts.map((a) => (
								<SelectItem key={a.id} value={a.id}>
									{a.name}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				)}
				{filters.categoryId && (
					<Button variant="ghost" size="sm" onClick={() => setParam({ categoryId: undefined })}>
						<ChevronLeft />
						All categories
					</Button>
				)}
			</div>

			<FormErrors errors={errors} />
			{needsAccount ? (
				<Panel>
					<p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">Choose an account above to see its statement.</p>
				</Panel>
			) : !report && loading ? (
				<div className="space-y-4">
					<div className="grid gap-3 sm:grid-cols-4">
						{[0, 1, 2, 3].map((i) => (
							<Skeleton key={i} className="h-24 rounded-2xl" />
						))}
					</div>
					<Skeleton className="h-72 rounded-2xl" />
				</div>
			) : (
				report && (
					<div className={cn("space-y-4 transition-opacity", loading && "opacity-60")}>
						<div className={cn("grid gap-3 sm:grid-cols-2", report.kpis.length === 5 ? "xl:grid-cols-5" : "xl:grid-cols-4")}>
							{report.kpis.map((k, i) => (
								<Reveal key={k.label} index={i} className="rounded-2xl bg-white dark:bg-slate-900 px-5 py-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
									<p className="text-xs text-slate-500 dark:text-slate-400">{k.label}</p>
									<p className="mt-1 text-xl font-semibold tabular-nums text-slate-900 dark:text-slate-100">
										{k.format === "money" && k.value !== undefined ? (
											<AnimatedMoney value={k.value} currency={currency} />
										) : k.format === "text" ? (
											k.caption
										) : (
											formatCell(k.value, k.format, currency)
										)}
									</p>
									{k.caption && k.format !== "text" && <p className="mt-0.5 text-xs text-slate-400">{/^\d{4}-\d{2}-\d{2}$/.test(k.caption) ? `on ${formatDate(k.caption)}` : k.caption}</p>}
								</Reveal>
							))}
						</div>
						{report.chart && report.chart.points.length > 0 && (
							<Reveal index={4}>
								<Panel title={report.chart.series[0]?.label && report.chart.kind === "ranked" ? report.chart.series[0].label : undefined}>
									<ReportChart report={report} currency={currency} onDrill={drill} />
								</Panel>
							</Reveal>
						)}
						{report.table && <ReportTableView table={report.table} currency={currency} onRow={report.drill ? (row) => drill(row.id as string) : undefined} />}
						{report.detail && <ReportTableView table={report.detail} currency={currency} />}
						{report.note && <p className="text-xs text-slate-500 dark:text-slate-400">{report.note}</p>}
					</div>
				)
			)}
			{saving && (
				<SaveDialog
					onClose={() => setSaving(false)}
					onSave={async (name, shared) => {
						await reportApi.save({ name, reportType: type as ReportType, filters: { ...filters, preset }, shared });
						toast.success(`Saved "${name}"`);
						setSaving(false);
					}}
				/>
			)}
		</>
	);
}

function ReportChart({ report, currency, onDrill }: { report: Report; currency: string; onDrill: (id?: string) => void }) {
	const chart = report.chart!;
	if (chart.kind === "columns") {
		return <CashFlowChart data={chart.points.map((p) => ({ month: p.label, income: p.values.income ?? 0, expenses: p.values.expenses ?? 0 }))} currency={currency} />;
	}
	if (chart.kind === "line") {
		return <LineChart points={chart.points.map((p) => ({ label: p.label, value: p.values[chart.series[0].key] ?? 0 }))} currency={currency} label={chart.series[0]?.label ?? "Balance"} />;
	}
	const money = report.type !== "security";
	return <RankedBars points={chart.points.slice(0, 12)} money={money} currency={currency} onDrill={report.drill ? onDrill : undefined} />;
}

/** Ranked bars in one hue; an optional target (budget, limit) shows as a tick on the track. */
function RankedBars({ points, money, currency, onDrill }: { points: ReportPoint[]; money: boolean; currency: string; onDrill?: (id?: string) => void }) {
	const max = Math.max(1, ...points.map((p) => Math.max(p.values.amount ?? 0, p.target ?? 0)));
	return (
		<ul className="space-y-3">
			{points.map((p, i) => {
				const value = p.values.amount ?? 0;
				const over = p.target !== undefined && p.target !== null && value > p.target;
				const body = (
					<>
						{p.icon && <CategoryChip icon={p.icon} color={p.color} size="sm" />}
						<div className="min-w-0 flex-1">
							<div className="flex items-baseline justify-between gap-2">
								<span className="truncate text-sm font-medium text-slate-800 dark:text-slate-200">{p.label}</span>
								<span className="shrink-0 text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">
									{money ? formatMoney(value, currency) : value.toLocaleString("en-IN")}
									{p.target !== undefined && p.target !== null && <span className="font-normal text-slate-400"> / {formatMoney(p.target, currency)}</span>}
								</span>
							</div>
							<div className="relative mt-1.5 h-2 rounded-full bg-slate-100 dark:bg-slate-800">
								<div
									className="vk-rise h-full rounded-full transition-[width] duration-700"
									style={{ width: `${(Math.max(0, value) / max) * 100}%`, backgroundColor: over ? "var(--status-critical)" : "var(--series-magnitude)", animationDelay: `${i * 40}ms` }}
								/>
								{p.target !== undefined && p.target !== null && (
									<span className="absolute -top-1 h-4 w-0.5 rounded bg-slate-700" style={{ left: `${(p.target / max) * 100}%` }} aria-hidden="true" />
								)}
							</div>
						</div>
					</>
				);
				return (
					<li key={p.id ?? p.label}>
						{onDrill && p.id ? (
							<button type="button" onClick={() => onDrill(p.id)} className="-m-1.5 flex w-full items-center gap-3 rounded-xl p-1.5 text-left hover:bg-slate-50 dark:hover:bg-slate-800/60">
								{body}
							</button>
						) : (
							<div className="flex items-center gap-3">{body}</div>
						)}
					</li>
				);
			})}
		</ul>
	);
}

function ReportTableView({ table, currency, onRow }: { table: ReportTable; currency: string; onRow?: (row: Record<string, unknown>) => void }) {
	const [sort, setSort] = useState<{ key: string; desc: boolean } | null>(null);
	const rows = useMemo(() => {
		if (!sort) return table.rows;
		return [...table.rows].sort((a, b) => {
			const x = a[sort.key];
			const y = b[sort.key];
			const cmp = typeof x === "number" && typeof y === "number" ? x - y : String(x ?? "").localeCompare(String(y ?? ""));
			return sort.desc ? -cmp : cmp;
		});
	}, [table.rows, sort]);
	if (table.rows.length === 0) return null;
	return (
		<Panel title={table.title} bodyClassName="p-0">
			<div className="overflow-x-auto">
				<table className="w-full text-sm">
					<thead className="bg-slate-50 dark:bg-slate-800/40 text-left text-xs text-slate-500 dark:text-slate-400">
						<tr>
							{table.columns.map((c) => {
								const numeric = ["money", "percent", "number"].includes(c.format);
								return (
									<th key={c.key} className={cn("px-4 py-2.5 font-medium whitespace-nowrap", numeric && "text-right")}>
										<button
											type="button"
											className="inline-flex items-center gap-1 hover:text-slate-800 dark:hover:text-slate-200"
											onClick={() => setSort((s) => ({ key: c.key, desc: s?.key === c.key ? !s.desc : numeric }))}
										>
											{c.label}
											<ArrowDownUp className={cn("size-3", sort?.key === c.key ? "text-brand-700 dark:text-brand-300" : "text-slate-300")} aria-hidden="true" />
										</button>
									</th>
								);
							})}
						</tr>
					</thead>
					<tbody className="tabular-nums">
						{rows.map((row, i) => (
							<tr
								key={String(row.id ?? i)}
								className={cn("border-t border-slate-100 dark:border-slate-800", onRow && row.id && "cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800/60")}
								onClick={onRow && row.id ? () => onRow(row) : undefined}
							>
								{table.columns.map((c) => (
									<td key={c.key} className={cn("px-4 py-2 whitespace-nowrap", ["money", "percent", "number"].includes(c.format) ? "text-right" : "text-slate-800 dark:text-slate-200")}>
										{formatCell(row[c.key], c.format, currency)}
									</td>
								))}
							</tr>
						))}
					</tbody>
				</table>
			</div>
		</Panel>
	);
}

function SaveDialog({ onClose, onSave }: { onClose: () => void; onSave: (name: string, shared: boolean) => Promise<void> }) {
	const [name, setName] = useState("");
	const [shared, setShared] = useState(false);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);
	async function submit(e: FormEvent) {
		e.preventDefault();
		setBusy(true);
		try {
			await onSave(name.trim(), shared);
		} catch (error) {
			setErrors(errorMessages(error));
			setBusy(false);
		}
	}
	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-md">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>Save this report</DialogTitle>
						<DialogDescription>Saves the report and its filters. Anyone who opens it sees only the money they&apos;re allowed to see.</DialogDescription>
					</DialogHeader>
					<TextField id="saved-name" label="Name" placeholder="e.g. Food this year" maxLength={80} autoFocus value={name} onChange={(e) => setName(e.target.value)} />
					<label className="flex items-center gap-2.5 text-sm">
						<Checkbox checked={shared} onCheckedChange={(v) => setShared(v === true)} />
						Share with the family
					</label>
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={busy || !name.trim()}>
							Save
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
