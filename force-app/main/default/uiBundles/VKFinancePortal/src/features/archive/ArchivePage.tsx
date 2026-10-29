import { useMemo, useState } from "react";
import { Archive, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { FormErrors } from "@/components/forms";
import { Reveal } from "@/components/finance/motion";
import { Amount, EmptyState, MoneyStat, PageHeader, Panel } from "@/components/finance/ui";
import { archiveApi } from "@/api/archive";
import { formatDate, monthLabel } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useLedger } from "@/features/ledger/LedgerContext";

/** Read-only view of months moved out of the live ledger. Same visibility rules as Transactions. */
export default function ArchivePage() {
	const { currency } = useLedger();
	const summary = useAsync(() => archiveApi.summary(), []);
	const months = summary.data?.months ?? [];
	const [selected, setSelected] = useState<string>();
	const [query, setQuery] = useState("");
	const month = selected ?? months[0]?.month;
	const view = useAsync(() => (month ? archiveApi.month(month) : Promise.resolve(undefined)), [month]);

	const entries = useMemo(() => {
		const all = view.data?.entries ?? [];
		const q = query.trim().toLowerCase();
		if (!q) return all;
		return all.filter((e) =>
			[e.payee, e.categoryName, e.accountName, e.memberName, e.notes, e.reference, e.type].some((v) => v?.toLowerCase().includes(q)),
		);
	}, [view.data, query]);

	return (
		<>
			<PageHeader
				title="Archive"
				description={
					summary.data?.archivedThrough
						? `Entries up to ${formatDate(summary.data.archivedThrough)} are archived. They're kept safely and can be viewed here, but not changed.`
						: "Older months move here automatically, so the live ledger stays fast. Archived entries can be viewed, not changed."
				}
			/>
			<FormErrors errors={[...summary.errors, ...view.errors]} />
			{!summary.data && summary.loading ? (
				<Skeleton className="h-64 rounded-2xl" />
			) : months.length === 0 ? (
				<Panel>
					<EmptyState icon={<Archive />} title="Nothing archived yet">
						Your last three full months always stay in the live ledger. Anything older moves here automatically each night.
					</EmptyState>
				</Panel>
			) : (
				<div className="grid gap-4 lg:grid-cols-[14rem_1fr]">
					<Panel title="Months" bodyClassName="p-2">
						<ul className="flex gap-1 overflow-x-auto lg:flex-col lg:overflow-visible" role="list">
							{months.map((m) => (
								<li key={m.month}>
									<button
										type="button"
										onClick={() => {
											setSelected(m.month);
											setQuery("");
										}}
										aria-current={m.month === month ? "true" : undefined}
										className={cn(
											"flex w-full items-center justify-between gap-3 whitespace-nowrap rounded-xl px-3 py-2 text-left text-sm transition-colors",
											m.month === month ? "bg-brand-50 dark:bg-brand-950/40 font-semibold text-brand-900 dark:text-brand-100" : "text-slate-700 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800/60",
										)}
									>
										{monthLabel(m.month)}
										<span className="text-xs tabular-nums text-slate-500 dark:text-slate-400">{m.transactions}</span>
									</button>
								</li>
							))}
						</ul>
					</Panel>
					<Panel
						title={month ? monthLabel(month) : ""}
						description="Read-only. Totals follow the same rules as Reports."
						action={
							<div className="relative w-44 sm:w-56">
								<Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-slate-400" />
								<Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search this month" aria-label="Search this month" className="pl-8" />
							</div>
						}
					>
						{!view.data || view.loading ? (
							<Skeleton className="h-48 rounded-xl" />
						) : (
							<>
								<div className="mb-4 grid grid-cols-3 gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3">
									<MoneyStat label="Income" value={view.data.income} currency={currency} />
									<MoneyStat label="Spending" value={view.data.spending} currency={currency} />
									<div>
										<p className="text-xs text-slate-500 dark:text-slate-400">Entries</p>
										<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{view.data.entries.length}</p>
									</div>
								</div>
								{entries.length === 0 ? (
									<p className="py-8 text-center text-sm text-slate-500 dark:text-slate-400">{query ? "No entries match your search." : "No entries you can see in this month."}</p>
								) : (
									<ul className="divide-y divide-slate-100 dark:divide-slate-800" role="list">
										{entries.map((e, i) => {
											const voided = e.status === "Void";
											return (
												<Reveal as="li" key={e.id} index={i} className="flex items-start gap-3 py-3">
													<div className="min-w-0 flex-1">
														<div className="flex flex-wrap items-center gap-2">
															<p className={cn("truncate font-medium text-slate-900 dark:text-slate-100", voided && "text-slate-400")}>{e.payee || e.categoryName || e.type}</p>
															{voided && <Badge variant="outline">Void</Badge>}
														</div>
														<p className="truncate text-xs text-slate-500 dark:text-slate-400">
															{formatDate(e.txnDate)} · {[e.categoryName ?? e.type, e.accountName, e.memberName].filter(Boolean).join(" · ")}
														</p>
														{e.notes && <p className="mt-0.5 truncate text-xs text-slate-400">{e.notes}</p>}
													</div>
													<Amount value={e.amount} currency={currency} direction={e.direction} muted={voided} />
												</Reveal>
											);
										})}
									</ul>
								)}
							</>
						)}
					</Panel>
				</div>
			)}
		</>
	);
}
