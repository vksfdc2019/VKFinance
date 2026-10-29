import { useState, type ReactNode } from "react";
import { Link, useSearchParams } from "react-router";
import { ArrowDownLeft, ArrowRight, ArrowUpRight, Landmark, PiggyBank, Plus, SlidersHorizontal, Target, Wallet } from "lucide-react";
import { CustomiseDialog, useDashboardLayout, Widget } from "./DashboardLayout";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { FormErrors } from "@/components/forms";
import { CashFlowChart } from "@/components/charts/CashFlowChart";
import { CategoryBars, NeedsWantsBar } from "@/components/charts/CategoryBars";
import { AccountChip, CategoryChip } from "@/components/finance/icons";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { DueBadge, PayBillDialog } from "@/features/commitments/shared";
import type { DueItem } from "@/api/commitmentTypes";
import { DeltaPill, EmptyState, MonthSwitcher, PageHeader, Panel, StatusMeter, budgetStatus, utilisationStatus } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import type { Dashboard } from "@/api/financeTypes";
import { formatMoney, formatPercent, monthKey, monthLabel, percentChange } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { TwoStepNudge } from "@/features/profile/TwoStepNudge";
import { TxnRow } from "@/features/ledger/TxnRow";

function greeting() {
	const hour = new Date().getHours();
	return hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening";
}

/** How far through the month we are: 1 for past months, 0 for future ones. */
function monthProgress(month: string) {
	const now = new Date();
	const current = monthKey(now);
	if (month < current) return 1;
	if (month > current) return 0;
	return now.getDate() / new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
}

export default function HomePage() {
	const { profile, can } = useAuth();
	const { version, openEntry, canAdd, refresh } = useLedger();
	const [paying, setPaying] = useState<DueItem | null>(null);
	const [customising, setCustomising] = useState(false);
	const { layout, saveLayout } = useDashboardLayout();
	const [params, setParams] = useSearchParams();
	const month = params.get("month") ?? monthKey();
	const memberId = params.get("member") ?? undefined;
	const { data, errors } = useAsync(() => financeApi.dashboard(month, memberId), [month, memberId, version]);
	const currency = data?.currencyCode ?? profile?.currencyCode ?? "INR";

	function setParam(key: string, value?: string) {
		const next = new URLSearchParams(params);
		if (value) next.set(key, value);
		else next.delete(key);
		setParams(next, { replace: true });
	}

	const header = (
		<>
			<PageHeader
			title={`${greeting()}, ${profile?.firstName ?? ""}`}
			description={`${profile?.familyName} · ${profile?.familyCode}`}
			actions={
				<>
					{data && data.members.length > 1 && (
						<Select value={memberId ?? "all"} onValueChange={(v) => setParam("member", v === "all" ? undefined : v)}>
							<SelectTrigger className="h-9 w-44 rounded-xl bg-white dark:bg-slate-900" aria-label="Whose money">
								<SelectValue />
							</SelectTrigger>
							<SelectContent>
								<SelectItem value="all">Whole family</SelectItem>
								{data.members.map((m) => (
									<SelectItem key={m.id} value={m.id}>
										{m.name}
									</SelectItem>
								))}
							</SelectContent>
						</Select>
					)}
					<MonthSwitcher value={month} onChange={(m) => setParam("month", m === monthKey() ? undefined : m)} />
					<Button variant="outline" size="icon" className="rounded-xl bg-white dark:bg-slate-900" aria-label="Customise dashboard" onClick={() => setCustomising(true)}>
						<SlidersHorizontal />
					</Button>
					{customising && <CustomiseDialog layout={layout} onClose={() => setCustomising(false)} onSave={saveLayout} />}
				</>
			}
			/>
			<TwoStepNudge />
		</>
	);

	if (!data) {
		return (
			<>
				{header}
				<FormErrors errors={errors} />
				{errors.length === 0 && <OverviewSkeleton />}
			</>
		);
	}

	const isNewFamily = data.accounts.length === 0 && data.recent.length === 0 && !memberId;
	if (isNewFamily) {
		return (
			<>
				{header}
				<GettingStarted canAddAccounts={can("ACCOUNTS:CREATE")} canAdd={canAdd} onAdd={() => openEntry()} />
			</>
		);
	}

	const { kpis } = data;
	const progress = monthProgress(month);
	const txnLink = (extra: string) => `/transactions?month=${month}${memberId ? `&member=${memberId}` : ""}${extra}`;

	return (
		<>
			{header}
			<FormErrors errors={errors} />

			<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
				<Reveal index={0} className="md:col-span-2 xl:col-span-1">
					<NetWorthCard data={data} currency={currency} />
				</Reveal>
				<KpiCard
					index={1}
					label="Income"
					icon={<ArrowDownLeft />}
					tint="bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300"
					value={<AnimatedMoney value={kpis.income} currency={currency} />}
					footer={<DeltaPill change={percentChange(kpis.income, kpis.prevIncome)} goodWhenUp />}
				/>
				<KpiCard
					index={2}
					label="Spending"
					icon={<ArrowUpRight />}
					tint="bg-orange-50 dark:bg-orange-950/40 text-orange-700 dark:text-orange-300"
					value={<AnimatedMoney value={kpis.expenses} currency={currency} />}
					footer={<DeltaPill change={percentChange(kpis.expenses, kpis.prevExpenses)} goodWhenUp={false} />}
				/>
				<KpiCard
					index={3}
					label="Saved"
					icon={<PiggyBank />}
					tint="bg-sky-50 dark:bg-sky-950/40 text-sky-700 dark:text-sky-300"
					value={<AnimatedMoney value={kpis.net} currency={currency} />}
					footer={
						<span className="text-xs text-slate-500 dark:text-slate-400">
							{kpis.savingsRate !== undefined ? `${formatPercent(kpis.savingsRate)} of income` : "No income recorded yet"}
						</span>
					}
				/>
			</div>

			<div className="mt-4 grid gap-4 xl:grid-cols-3">
			{data.upcoming.length > 0 && (
				<Widget id="upcoming" layout={layout} className="xl:col-span-3">
					<Panel
						title="Coming up"
						description="Bills, EMIs and card bills in the next 30 days"
						action={
							<span className="text-xs font-medium tabular-nums text-slate-600 dark:text-slate-400">
								{formatMoney(data.upcoming.reduce((s, d) => s + d.amount, 0), currency)} in total
							</span>
						}
						bodyClassName="px-3 pb-4 pt-3"
					>
						<ul className="flex snap-x gap-3 overflow-x-auto px-2 pb-1">
							{data.upcoming.map((d, i) => (
								<li key={d.id} className="vk-rise w-60 shrink-0 snap-start" style={{ animationDelay: `${200 + i * 50}ms` }}>
									<div className="vk-lift flex h-full flex-col rounded-2xl bg-slate-50 dark:bg-slate-800/40 p-3.5 ring-1 ring-slate-900/5 dark:ring-white/10">
										<div className="flex items-center gap-2.5">
											<CategoryChip icon={d.icon} color={d.color} size="sm" />
											<div className="min-w-0 flex-1">
												<p className="truncate text-sm font-semibold text-slate-900 dark:text-slate-100">{d.title}</p>
												<p className="truncate text-[11px] text-slate-500 dark:text-slate-400">{d.subtitle}</p>
											</div>
										</div>
										<div className="mt-3 flex items-end justify-between gap-2">
											<div>
												<p className="text-lg font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(d.amount, currency)}</p>
												<DueBadge status={d.status} daysLeft={d.daysLeft} />
											</div>
											{d.kind === "bill" && can("BILLS:PAY") ? (
												<Button size="xs" onClick={() => setPaying(d)}>
													Pay
												</Button>
											) : (
												<Button asChild size="xs" variant="outline">
													<Link to={d.link}>Open</Link>
												</Button>
											)}
										</div>
									</div>
								</li>
							))}
						</ul>
					</Panel>
				</Widget>
			)}
			{paying && (
				<PayBillDialog
					instance={{ id: paying.id, billName: paying.title, dueDate: paying.dueDate, amountDue: paying.amount, amountPaid: 0 }}
					currency={currency}
					onClose={() => setPaying(null)}
					onPaid={() => {
						setPaying(null);
						refresh();
					}}
				/>
			)}

				<Widget id="cashflow" layout={layout} className="xl:col-span-2">
				<Panel title="Cash flow" description="Income and spending over the last six months" className="h-full">
					<CashFlowChart data={data.trend} currency={currency} highlight={month} />
				</Panel>
				</Widget>
				<Widget id="categories" layout={layout}>
				<Panel
					className="h-full"
					title="Where it went"
					description={`Spending by category · ${monthLabel(month)}`}
					action={
						data.byCategory.length > 0 && (
							<Link to={txnLink("&type=Expense")} className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline">
								Details
							</Link>
						)
					}
				>
					{data.byCategory.length ? (
						<CategoryBars items={data.byCategory} currency={currency} linkTo={(id) => txnLink(`&category=${id}`)} />
					) : (
						<p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">No spending recorded in {monthLabel(month)}.</p>
					)}
				</Panel>
				</Widget>

				<Widget id="budget" layout={layout}>
				<Panel
					className="h-full"
					title="Budget"
					description={monthLabel(month)}
					action={
						can("BUDGETS:READ") && (
							<Link to={`/budgets?month=${month}`} className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline">
								{data.budget ? "Open" : can("BUDGETS:EDIT") ? "Plan" : "View"}
							</Link>
						)
					}
				>
					{data.budget ? (
						<div>
							<p className="text-2xl font-semibold tabular-nums text-slate-900 dark:text-slate-100">
								{formatMoney(data.budget.spent, currency)}
								<span className="text-sm font-normal text-slate-500 dark:text-slate-400"> of {formatMoney(data.budget.planned, currency)}</span>
							</p>
							<StatusMeter
								className="mt-3"
								value={data.budget.spent}
								max={data.budget.planned}
								status={budgetStatus(data.budget.spent, data.budget.planned, progress)}
								label={
									data.budget.overCount > 0
										? `${data.budget.overCount} ${data.budget.overCount === 1 ? "category is" : "categories are"} over plan`
										: data.budget.spent > data.budget.planned
											? "Over budget"
											: `${formatMoney(data.budget.planned - data.budget.spent, currency)} left to spend`
								}
							/>
						</div>
					) : (
						<div className="flex items-center gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3">
							<Target className="size-5 shrink-0 text-brand-700 dark:text-brand-300" aria-hidden="true" />
							<p className="text-sm text-slate-600 dark:text-slate-400">
								{data.wholeFamily && !memberId ? "No budget for this month yet." : "The family budget shows in the whole-family view."}
							</p>
						</div>
					)}
					<div className="mt-6">
						<p className="mb-2 text-sm font-medium text-slate-800 dark:text-slate-200">Needs vs wants</p>
						<NeedsWantsBar needs={kpis.essential} wants={kpis.discretionary} currency={currency} />
					</div>
				</Panel>
				</Widget>

				<Widget id="accounts" layout={layout}>
				<Panel
					className="h-full"
					title="Accounts"
					description={`${data.accounts.length} active`}
					action={
						<Link to="/accounts" className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline">
							Manage
						</Link>
					}
					bodyClassName="px-3 pb-3"
				>
					<ul className="space-y-0.5">
						{data.accounts.slice(0, 6).map((a) => (
							<li key={a.id}>
								<Link to={`/transactions?account=${a.id}`} className="flex items-center gap-3 rounded-xl px-2 py-2 hover:bg-slate-50 dark:hover:bg-slate-800/60">
									<AccountChip account={a} />
									<div className="min-w-0 flex-1">
										<p className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">{a.name}</p>
										{a.card?.utilisationPct !== undefined ? (
											<div className="mt-1 h-1 w-full max-w-32 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
												<div
													className="h-full rounded-full"
													style={{
														width: `${Math.min(100, Math.max(0, a.card.utilisationPct))}%`,
														backgroundColor: `var(--status-${utilisationStatus(a.card.utilisationPct)})`,
													}}
												/>
											</div>
										) : (
											<p className="truncate text-xs text-slate-500 dark:text-slate-400">{a.ownerName ? `${a.type} · ${a.ownerName}` : a.type}</p>
										)}
									</div>
									<div className="text-right">
										<p className={cn("text-sm font-semibold tabular-nums", a.isLiability ? "text-slate-700 dark:text-slate-300" : "text-slate-900 dark:text-slate-100")}>
											{formatMoney(a.balance, currency)}
										</p>
										{a.isLiability && <p className="text-[11px] text-slate-400">owed</p>}
									</div>
								</Link>
							</li>
						))}
					</ul>
				</Panel>
				</Widget>

				<Widget id="recent" layout={layout}>
				<Panel
					className="h-full"
					title="Recent activity"
					action={
						<Link to={txnLink("")} className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline">
							See all
						</Link>
					}
					bodyClassName="px-2 pb-3"
				>
					{data.recent.length ? (
						<div className="space-y-0.5">
							{data.recent.slice(0, 7).map((t) => (
								<TxnRow key={t.id} txn={t} currency={currency} compact onOpen={(txn) => openEntry({ txn })} />
							))}
						</div>
					) : (
						<p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">Nothing recorded yet.</p>
					)}
				</Panel>
				</Widget>
			</div>
		</>
	);
}

function NetWorthCard({ data, currency, className }: { data: Dashboard; currency: string; className?: string }) {
	return (
		<div
			className={cn(
				"relative overflow-hidden rounded-2xl bg-gradient-to-br from-brand-800 via-brand-900 to-slate-900 p-5 text-white shadow-lg shadow-brand-900/20",
				className,
			)}
		>
			<div className="pointer-events-none absolute -top-16 -right-10 size-48 rounded-full bg-brand-400/20 blur-2xl" />
			<div className="pointer-events-none absolute -bottom-20 -left-10 size-48 rounded-full bg-sky-400/10 blur-2xl" />
			<div className="relative">
				<p className="flex items-center gap-2 text-sm text-brand-100/80">
					<Landmark className="size-4" aria-hidden="true" />
					{data.wholeFamily && !data.memberId ? "Family net worth" : "Net worth"}
				</p>
				<p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums">
					<AnimatedMoney value={data.netWorth.net} currency={currency} />
				</p>
				<dl className="mt-4 grid grid-cols-2 gap-3 text-xs">
					<div className="rounded-xl bg-white/10 px-3 py-2">
						<dt className="text-brand-100/70">You have</dt>
						<dd className="mt-0.5 text-sm font-semibold tabular-nums">{formatMoney(data.netWorth.assets, currency)}</dd>
					</div>
					<div className="rounded-xl bg-white/10 px-3 py-2">
						<dt className="text-brand-100/70">You owe</dt>
						<dd className="mt-0.5 text-sm font-semibold tabular-nums">{formatMoney(data.netWorth.liabilities, currency)}</dd>
					</div>
				</dl>
			</div>
		</div>
	);
}

function KpiCard({
	label,
	value,
	icon,
	tint,
	footer,
	index,
}: {
	label: string;
	value: ReactNode;
	icon: ReactNode;
	tint: string;
	footer: ReactNode;
	index: number;
}) {
	return (
		<div className="vk-rise vk-lift rounded-2xl bg-white dark:bg-slate-900 p-5 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10" style={{ animationDelay: `${index * 60}ms` }}>
			<div className="flex items-center justify-between">
				<p className="text-sm font-medium text-slate-500 dark:text-slate-400">{label}</p>
				<span className={cn("flex size-8 items-center justify-center rounded-xl [&_svg]:size-4", tint)} aria-hidden="true">
					{icon}
				</span>
			</div>
			<p className="mt-3 text-2xl font-semibold tracking-tight tabular-nums text-slate-900 dark:text-slate-100">{value}</p>
			<div className="mt-2">{footer}</div>
		</div>
	);
}

function GettingStarted({ canAddAccounts, canAdd, onAdd }: { canAddAccounts: boolean; canAdd: boolean; onAdd: () => void }) {
	const steps = [
		{
			title: "Add your accounts",
			text: "Bank accounts, cash, UPI wallets and credit cards - with today's balances.",
			action: canAddAccounts && (
				<Button asChild size="sm">
					<Link to="/accounts?new=1">
						<Plus />
						Add an account
					</Link>
				</Button>
			),
		},
		{
			title: "Record what you spend",
			text: "Press N anywhere to add an expense in seconds. Categories are ready for you.",
			action: canAdd && (
				<Button size="sm" variant="outline" onClick={onAdd}>
					Add a transaction
				</Button>
			),
		},
		{
			title: "Plan the month",
			text: "Set a budget per category and watch it fill up as the month goes.",
			action: (
				<Button asChild size="sm" variant="outline">
					<Link to="/budgets">
						Open budgets
						<ArrowRight />
					</Link>
				</Button>
			),
		},
	];
	return (
		<Panel>
			<EmptyState icon={<Wallet />} title="Let's set up your family's money">
				Three quick steps and your dashboard comes alive.
			</EmptyState>
			<ol className="mx-auto grid max-w-4xl gap-4 pb-6 md:grid-cols-3">
				{steps.map((step, i) => (
					<li key={step.title} className="rounded-2xl bg-slate-50 dark:bg-slate-800/40 p-5 ring-1 ring-slate-900/5 dark:ring-white/10">
						<span className="flex size-7 items-center justify-center rounded-full bg-brand-700 text-xs font-semibold text-white">{i + 1}</span>
						<h3 className="mt-3 font-semibold text-slate-900 dark:text-slate-100">{step.title}</h3>
						<p className="mt-1 text-sm text-slate-500 dark:text-slate-400">{step.text}</p>
						{step.action && <div className="mt-4">{step.action}</div>}
					</li>
				))}
			</ol>
		</Panel>
	);
}

function OverviewSkeleton() {
	return (
		<div className="space-y-4" aria-busy="true" aria-label="Loading overview">
			<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
				{[0, 1, 2, 3].map((i) => (
					<Skeleton key={i} className="h-36 rounded-2xl" />
				))}
			</div>
			<div className="grid gap-4 xl:grid-cols-3">
				<Skeleton className="h-80 rounded-2xl xl:col-span-2" />
				<Skeleton className="h-80 rounded-2xl" />
			</div>
		</div>
	);
}
