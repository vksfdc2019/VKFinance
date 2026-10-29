import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router";
import { Download, Plus, Receipt, Search, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { FormErrors } from "@/components/forms";
import { EmptyState, MonthSwitcher, PageHeader, Panel, SegmentedControl } from "@/components/finance/ui";
import { familyApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Txn, TxnQuery } from "@/api/financeTypes";
import { dayHeading, formatMoney, monthKey, monthLabel } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { TxnRow, txnTitle } from "@/features/ledger/TxnRow";

type Kind = "all" | "spending" | "income" | "transfers";
const KIND_TYPES: Record<Kind, string | undefined> = {
	all: undefined,
	spending: "Expense,Refund,Bill Payment",
	income: "Income",
	transfers: "Transfer Out,Transfer In,Card Payment",
};
const PAGE_SIZE = 50;

export default function TransactionsPage() {
	const { profile } = useAuth();
	const { version, openEntry, canAdd, currency, loadCategories } = useLedger();
	const [params, setParams] = useSearchParams();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";

	const month = params.get("month") ?? monthKey();
	const kind = (params.get("kind") as Kind) ?? (params.get("type") === "Expense" ? "spending" : "all");
	const accountId = params.get("account") ?? undefined;
	const categoryId = params.get("category") ?? undefined;
	const memberId = params.get("member") ?? undefined;
	const includeVoid = params.get("void") === "1";
	const [search, setSearch] = useState(params.get("q") ?? "");
	const [q, setQ] = useState(search);

	useEffect(() => {
		const timer = setTimeout(() => setQ(search.trim()), 300);
		return () => clearTimeout(timer);
	}, [search]);

	const query: TxnQuery = {
		month,
		type: KIND_TYPES[kind],
		accountId,
		categoryId,
		memberId,
		q: q || undefined,
		includeVoid,
		limit: PAGE_SIZE,
	};
	const queryKey = JSON.stringify(query);
	const { data: firstPage, errors, loading } = useAsync(() => financeApi.transactions(query), [queryKey, version]);
	const [more, setMore] = useState<Txn[]>([]);
	const [cursor, setCursor] = useState<string>();
	const [loadingMore, setLoadingMore] = useState(false);
	const [moreErrors, setMoreErrors] = useState<string[]>([]);

	useEffect(() => {
		setMore([]);
		setCursor(firstPage?.nextCursor);
	}, [firstPage]);

	const { data: filters } = useAsync(
		() =>
			Promise.all([
				financeApi.accounts(true),
				loadCategories(),
				isAdmin ? familyApi.members() : Promise.resolve([]),
			]).then(([accounts, categories, members]) => ({ accounts, categories, members })),
		[version],
	);

	const items = useMemo(() => [...(firstPage?.items ?? []), ...more], [firstPage, more]);
	const groups = useMemo(() => {
		const byDay = new Map<string, Txn[]>();
		for (const t of items) byDay.set(t.txnDate, [...(byDay.get(t.txnDate) ?? []), t]);
		return [...byDay.entries()];
	}, [items]);

	function setParam(key: string, value?: string) {
		const next = new URLSearchParams(params);
		if (value) next.set(key, value);
		else next.delete(key);
		next.delete("type");
		setParams(next, { replace: true });
	}

	async function loadMore() {
		if (!cursor) return;
		setLoadingMore(true);
		try {
			const page = await financeApi.transactions({ ...query, cursor });
			setMore((prev) => [...prev, ...page.items]);
			setCursor(page.nextCursor);
			setMoreErrors([]);
		} catch (error) {
			setMoreErrors(errorMessages(error));
		} finally {
			setLoadingMore(false);
		}
	}

	function exportCsv() {
		const header = ["Date", "Type", "Description", "Category", "Account", "Member", "Mode", "Direction", "Amount", "Status", "Notes"];
		const rows = items.map((t) => [
			t.txnDate,
			t.type,
			txnTitle(t),
			t.categoryName ?? "",
			t.accountName ?? "",
			t.memberName ?? "",
			t.paymentMode ?? "",
			t.direction,
			t.amount.toFixed(2),
			t.status,
			t.notes ?? "",
		]);
		const csv = [header, ...rows].map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(",")).join("\r\n");
		const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
		const link = Object.assign(document.createElement("a"), { href: url, download: `vk-finance-${month}.csv` });
		link.click();
		URL.revokeObjectURL(url);
	}

	const totals = firstPage?.totals;
	const activeFilters = [accountId, categoryId, memberId, q].filter(Boolean).length;
	const parents = (filters?.categories ?? []).filter((c) => !c.parentId && c.kind !== "System");

	return (
		<>
			<PageHeader
				title="Transactions"
				description="Every rupee in and out, across the accounts you can see."
				actions={
					<>
						<Button variant="outline" onClick={exportCsv} disabled={!items.length}>
							<Download />
							Export
						</Button>
						{canAdd && (
							<Button onClick={() => openEntry()}>
								<Plus />
								Add
							</Button>
						)}
					</>
				}
			/>

			<div className="mb-4 flex flex-wrap items-center gap-2">
				<MonthSwitcher value={month} onChange={(m) => setParam("month", m === monthKey() ? undefined : m)} />
				<SegmentedControl
					label="Show"
					value={kind}
					onChange={(k) => setParam("kind", k === "all" ? undefined : k)}
					options={[
						{ value: "all", label: "All" },
						{ value: "spending", label: "Spending" },
						{ value: "income", label: "Income" },
						{ value: "transfers", label: "Transfers" },
					]}
				/>
				<div className="relative min-w-48 flex-1 sm:max-w-xs">
					<Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
					<Input
						value={search}
						onChange={(e) => setSearch(e.target.value)}
						placeholder="Search payee, notes, reference"
						aria-label="Search transactions"
						className="h-9 rounded-xl bg-white dark:bg-slate-900 pl-9"
					/>
				</div>
			</div>

			<div className="mb-4 flex flex-wrap items-center gap-2">
				<Select value={accountId ?? "all"} onValueChange={(v) => setParam("account", v === "all" ? undefined : v)}>
					<SelectTrigger className="h-9 w-48 rounded-xl bg-white dark:bg-slate-900" aria-label="Account">
						<SelectValue />
					</SelectTrigger>
					<SelectContent>
						<SelectItem value="all">All accounts</SelectItem>
						{filters?.accounts.map((a) => (
							<SelectItem key={a.id} value={a.id}>
								{a.name}
								{a.status === "Closed" ? " (closed)" : ""}
							</SelectItem>
						))}
					</SelectContent>
				</Select>
				<Select value={categoryId ?? "all"} onValueChange={(v) => setParam("category", v === "all" ? undefined : v)}>
					<SelectTrigger className="h-9 w-52 rounded-xl bg-white dark:bg-slate-900" aria-label="Category">
						<SelectValue />
					</SelectTrigger>
					<SelectContent className="max-h-80">
						<SelectItem value="all">All categories</SelectItem>
						{(["Expense", "Income"] as const).map((k) => (
							<SelectGroup key={k}>
								<SelectLabel>{k}</SelectLabel>
								{parents
									.filter((c) => c.kind === k)
									.map((c) => (
										<SelectItem key={c.id} value={c.id}>
											{c.name}
										</SelectItem>
									))}
							</SelectGroup>
						))}
						{categoryId && !parents.some((c) => c.id === categoryId) && (
							<SelectItem value={categoryId}>{filters?.categories.find((c) => c.id === categoryId)?.name ?? "Selected"}</SelectItem>
						)}
					</SelectContent>
				</Select>
				{isAdmin && filters && filters.members.length > 1 && (
					<Select value={memberId ?? "all"} onValueChange={(v) => setParam("member", v === "all" ? undefined : v)}>
						<SelectTrigger className="h-9 w-44 rounded-xl bg-white dark:bg-slate-900" aria-label="Member">
							<SelectValue />
						</SelectTrigger>
						<SelectContent>
							<SelectItem value="all">Everyone</SelectItem>
							{filters.members.map((m) => (
								<SelectItem key={m.id} value={m.id}>
									{m.firstName} {m.lastName}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				)}
				<label className="ml-1 flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400">
					<Checkbox checked={includeVoid} onCheckedChange={(v) => setParam("void", v === true ? "1" : undefined)} />
					Show void
				</label>
				{activeFilters > 0 && (
					<Button
						variant="ghost"
						size="sm"
						onClick={() => {
							setSearch("");
							setParams(new URLSearchParams(month === monthKey() ? {} : { month }), { replace: true });
						}}
					>
						<X />
						Clear filters
					</Button>
				)}
			</div>

			{totals && (
				<div className="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
					<Stat label="Income" value={formatMoney(totals.income, currency)} />
					<Stat label="Spending" value={formatMoney(totals.expenses, currency)} />
					<Stat label="Moved between accounts" value={formatMoney(totals.transfers, currency)} />
					<Stat label="Transactions" value={String(totals.count)} />
				</div>
			)}

			<FormErrors errors={errors} />
			<Panel bodyClassName="p-2 sm:p-3">
				{!firstPage && loading ? (
					<div className="space-y-2 p-2">
						{Array.from({ length: 6 }, (_, i) => (
							<Skeleton key={i} className="h-12 rounded-xl" />
						))}
					</div>
				) : items.length === 0 ? (
					<EmptyState
						icon={<Receipt />}
						title={activeFilters || kind !== "all" ? "Nothing matches these filters" : `No transactions in ${monthLabel(month)}`}
						action={
							canAdd && (
								<Button onClick={() => openEntry()}>
									<Plus />
									Add a transaction
								</Button>
							)
						}
					>
						{activeFilters || kind !== "all" ? "Try another month or clear the filters." : "Add income, an expense or a transfer to get started."}
					</EmptyState>
				) : (
					<div className={loading ? "opacity-60 transition-opacity" : undefined}>
						{groups.map(([day, rows]) => {
							const net = rows.reduce((sum, t) => {
								if (t.status === "Void" || !["Income", "Expense", "Refund", "Bill Payment"].includes(t.type)) return sum;
								return sum + (t.direction === "Credit" ? t.amount : -t.amount);
							}, 0);
							return (
								<section key={day} className="mb-1">
									<header className="sticky top-14 z-10 flex items-center justify-between bg-white/90 dark:bg-slate-900/90 px-3 py-2 backdrop-blur lg:top-0">
										<h2 className="text-xs font-semibold tracking-wide text-slate-500 dark:text-slate-400 uppercase">{dayHeading(day)}</h2>
										{net !== 0 && (
											<span className="text-xs tabular-nums text-slate-400">{formatMoney(net, currency, { signed: true })}</span>
										)}
									</header>
									<div className="space-y-0.5">
										{rows.map((t) => (
											<TxnRow key={t.id} txn={t} currency={currency} showMember={isAdmin} onOpen={(txn) => openEntry({ txn })} />
										))}
									</div>
								</section>
							);
						})}
						<FormErrors errors={moreErrors} />
						{cursor && (
							<div className="flex justify-center p-3">
								<Button variant="outline" onClick={() => void loadMore()} disabled={loadingMore}>
									{loadingMore && <Spinner />}
									Load more
								</Button>
							</div>
						)}
					</div>
				)}
			</Panel>
		</>
	);
}

function Stat({ label, value }: { label: string; value: string }) {
	return (
		<div className="rounded-2xl bg-white dark:bg-slate-900 px-4 py-3 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
			<p className="text-xs text-slate-500 dark:text-slate-400">{label}</p>
			<p className="mt-0.5 text-lg font-semibold tabular-nums text-slate-900 dark:text-slate-100">{value}</p>
		</div>
	);
}
