import type { ReactNode } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { BarChart3, CalendarDays, Gauge as GaugeIcon, PieChart, Sparkles, Store, Target, TrendingUp, Wallet } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { FormErrors } from "@/components/forms";
import { CashFlowChart } from "@/components/charts/CashFlowChart";
import { DonutChart } from "@/components/charts/DonutChart";
import { Funnel } from "@/components/charts/Funnel";
import { Gauge } from "@/components/charts/Gauge";
import { LineChart } from "@/components/charts/LineChart";
import { StackedBars } from "@/components/charts/StackedBars";
import { SpendHeatmap } from "@/components/charts/SpendHeatmap";
import { BulletBars, RankBars } from "@/components/charts/BulletBars";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { DeltaPill, EmptyState, MonthSwitcher, PageHeader, Panel, SegmentedControl } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import type { Analytics } from "@/api/analyticsTypes";
import type { BudgetView, Dashboard } from "@/api/financeTypes";
import { formatMoney, formatPercent, formatShortDate, monthKey, monthLabel, percentChange, todayIso } from "@/lib/format";
import { assetMix, cardUse, emiBurden, monthProgress, moneySplit, savingsRateStatus } from "@/lib/analytics";
import { useAsync } from "@/lib/useAsync";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";

const RANGES = [
	{ value: "6", label: "6M" },
	{ value: "12", label: "1Y" },
	{ value: "24", label: "2Y" },
] as const;
type Range = (typeof RANGES)[number]["value"];

interface Bundle {
	analytics: Analytics;
	dashboard: Dashboard;
	budget?: BudgetView;
}

/** Charts of where the money went: splits, trends, health gauges, budgets and daily spending. */
export default function AnalyticsPage() {
	const { profile, can } = useAuth();
	const { version } = useLedger();
	const navigate = useNavigate();
	const [params, setParams] = useSearchParams();
	const month = params.get("month") ?? monthKey();
	const memberId = params.get("member") ?? undefined;
	const range = (RANGES.find((r) => r.value === params.get("range"))?.value ?? "12") as Range;
	const withBudget = can("BUDGETS:READ") && !memberId;
	const { data, errors } = useAsync<Bundle>(
		async () => {
			const [analytics, dashboard, budget] = await Promise.all([
				financeApi.analytics(month, Number(range), memberId),
				financeApi.dashboard(month, memberId),
				withBudget ? financeApi.budget(month).catch(() => undefined) : Promise.resolve(undefined),
			]);
			return { analytics, dashboard, budget };
		},
		[month, memberId, range, version, withBudget],
	);
	const currency = data?.analytics.currencyCode ?? profile?.currencyCode ?? "INR";

	function setParam(key: string, value?: string) {
		const next = new URLSearchParams(params);
		if (value) next.set(key, value);
		else next.delete(key);
		setParams(next, { replace: true });
	}

	const header = (
		<PageHeader
			title="Analytics"
			description={data ? `${monthLabel(data.analytics.month)} · ${formatShortDate(data.analytics.periodStart)} – ${formatShortDate(data.analytics.periodEnd)}` : "Where your money goes, month by month"}
			actions={
				<>
					{data && data.analytics.members.length > 1 && (
						<Select value={memberId ?? "all"} onValueChange={(v) => setParam("member", v === "all" ? undefined : v)}>
							<SelectTrigger className="h-9 w-44 rounded-xl bg-white dark:bg-slate-900" aria-label="Whose money">
								<SelectValue />
							</SelectTrigger>
							<SelectContent>
								<SelectItem value="all">Whole family</SelectItem>
								{data.analytics.members.map((m) => (
									<SelectItem key={m.id} value={m.id}>
										{m.name}
									</SelectItem>
								))}
							</SelectContent>
						</Select>
					)}
					<SegmentedControl label="Trend range" value={range} options={RANGES.map((r) => ({ value: r.value, label: r.label }))} onChange={(v) => setParam("range", v === "12" ? undefined : v)} className="bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10" />
					<MonthSwitcher value={month} onChange={(m) => setParam("month", m === monthKey() ? undefined : m)} />
				</>
			}
		/>
	);

	if (!data) {
		return (
			<>
				{header}
				<FormErrors errors={errors} />
				{errors.length === 0 && <AnalyticsSkeleton />}
			</>
		);
	}

	const { analytics: a, dashboard: d, budget } = data;
	const m = a.current;
	const prev = a.series.length > 1 ? a.series[a.series.length - 2] : undefined;
	const out = m.spending + m.bills + m.emis;
	const empty = a.series.every((f) => f.income === 0 && f.spending === 0 && f.bills === 0 && f.emis === 0);
	const txnLink = (extra: string) => `/transactions?month=${a.month}${memberId ? `&member=${memberId}` : ""}${extra}`;

	if (empty) {
		return (
			<>
				{header}
				<Panel>
					<EmptyState icon={<BarChart3 />} title="No transactions to chart yet">
						Add income and spending, and this page fills with charts of where your money goes.
					</EmptyState>
				</Panel>
			</>
		);
	}

	const split = moneySplit(m);
	const assets = assetMix(d.accounts);
	const cards = cardUse(d.accounts);
	const burden = emiBurden(m);
	const cumulative = a.series.map((f, i) => ({ label: monthLabel(f.month, "short"), value: a.series.slice(0, i + 1).reduce((s, x) => s + x.saved, 0) }));
	const savedTotal = cumulative.length ? cumulative[cumulative.length - 1].value : 0;
	const budgetRows = (budget?.exists ? budget.lines : [])
		.filter((l) => l.planned > 0 || l.spent > 0)
		.sort((x, y) => y.spent / Math.max(1, y.planned) - x.spent / Math.max(1, x.planned))
		.slice(0, 8)
		.map((l) => ({ key: l.categoryId, name: l.name, icon: l.icon, color: l.color, planned: l.planned, spent: l.spent }));

	return (
		<>
			{header}
			<FormErrors errors={errors} />

			<Reveal index={0}>
				<section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-brand-800 via-brand-900 to-slate-900 p-5 text-white shadow-xl shadow-brand-900/20 sm:p-7">
					<div className="pointer-events-none absolute -top-24 -right-16 size-72 rounded-full bg-brand-400/25 blur-3xl" />
					<div className="pointer-events-none absolute -bottom-28 left-1/4 size-72 rounded-full bg-sky-400/15 blur-3xl" />
					<div className="relative grid gap-6 lg:grid-cols-[1fr_auto] lg:items-center">
						<div>
							<p className="flex items-center gap-2 text-sm text-brand-100/80">
								<Sparkles className="size-4" aria-hidden="true" />
								{monthLabel(a.month)} at a glance
							</p>
							<dl className="mt-4 grid grid-cols-2 gap-x-6 gap-y-5 sm:grid-cols-4">
								<HeroFigure label="Income" value={<AnimatedMoney value={m.income} currency={currency} />} change={prev && percentChange(m.income, prev.income)} goodWhenUp />
								<HeroFigure label="Money out" value={<AnimatedMoney value={out} currency={currency} />} change={prev && percentChange(out, prev.spending + prev.bills + prev.emis)} goodWhenUp={false} />
								<HeroFigure label="Saved" value={<AnimatedMoney value={m.saved} currency={currency} />} change={prev && percentChange(m.saved, prev.saved)} goodWhenUp />
								<HeroFigure label="Savings rate" value={m.savingsRate === undefined ? "–" : formatPercent(m.savingsRate)} hint={m.income > 0 ? "of income" : "No income yet"} />
							</dl>
						</div>
						<div className="flex h-24 items-end gap-1.5 lg:w-72" role="img" aria-label={`Saved each month: ${a.series.map((f) => `${monthLabel(f.month, "short")} ${formatMoney(f.saved, currency)}`).join(", ")}`}>
							{a.series.slice(-12).map((f) => {
								const top = Math.max(1, ...a.series.slice(-12).map((x) => Math.abs(x.saved)));
								return (
									<div key={f.month} className="flex flex-1 flex-col items-center justify-end gap-1" title={`${monthLabel(f.month)}: ${formatMoney(f.saved, currency)}`}>
										<div
											className={f.saved < 0 ? "w-full rounded-t bg-red-300/80" : f.month === a.month ? "w-full rounded-t bg-emerald-300" : "w-full rounded-t bg-white/30"}
											style={{ height: `${Math.max(4, (Math.abs(f.saved) / top) * 80)}px` }}
										/>
									</div>
								);
							})}
						</div>
					</div>
				</section>
			</Reveal>

			<div className="mt-4 grid gap-4 lg:grid-cols-2">
				<Card index={1} icon={<PieChart />} title="Where your income went" description="EMIs, everyday spending, bills and what was left">
					{m.income > 0 || out > 0 ? (
						<DonutChart slices={split} currency={currency} label="Where income went" centreLabel="Income" centreValue={formatMoney(m.income, currency)} />
					) : (
						<NoData />
					)}
				</Card>
				<Card index={2} icon={<PieChart />} title="Spending by category" description="Tap a category to see its transactions">
					<DonutChart
						slices={d.byCategory.map((c) => ({ key: c.categoryId, label: c.name, value: c.amount, color: c.color ?? "#64748b", onSelect: () => navigate(txnLink(`&category=${c.categoryId}`)) }))}
						currency={currency}
						label="Spending by category"
						centreLabel="Spent"
					/>
				</Card>
			</div>

			<div className="mt-4 grid gap-4 xl:grid-cols-2">
				<Card index={4} icon={<TrendingUp />} title="From income to savings" description={`How ${monthLabel(a.month)}'s income narrowed, step by step`}>
					{m.income > 0 ? (
						<Funnel
							label="Income to savings"
							currency={currency}
							steps={[
								{ label: "Income", value: m.income },
								{ label: "After EMIs", value: m.income - m.emis, minus: { label: "EMIs", value: m.emis, color: "var(--viz-emi)" } },
								{ label: "After spending", value: m.income - m.emis - m.spending, minus: { label: "Spending", value: m.spending, color: "var(--viz-spend)" } },
								{ label: "Saved", value: m.saved, minus: { label: "Bills", value: m.bills, color: "var(--viz-bill)" } },
							]}
						/>
					) : (
						<NoData text="No income recorded this month." />
					)}
				</Card>
				<Card index={3} icon={<Wallet />} title="What you own" description={`Net worth ${formatMoney(d.netWorth.net, currency)} after ${formatMoney(d.netWorth.liabilities, currency)} owed`}>
					{assets.length ? <DonutChart pie slices={assets} currency={currency} label="What you own" /> : <NoData text="Add an account to see this." />}
				</Card>
			</div>

			<div className="mt-4">
				<Card index={5} icon={<GaugeIcon />} title="Financial health" description="Three ratios Indian banks and planners watch">
					<div className="grid gap-8 sm:grid-cols-3">
						<Gauge
							title="Savings rate"
							value={m.savingsRate}
							target={20}
							status={savingsRateStatus(m.savingsRate)}
							verdict={m.savingsRate === undefined ? "No income yet" : m.savingsRate >= 20 ? "Healthy" : m.savingsRate >= 10 ? "Could be better" : "Too low"}
							hint="Aim to save at least 20% of what comes in."
						/>
						<Gauge
							title="EMI burden (FOIR)"
							value={burden.pct}
							target={40}
							status={burden.status}
							verdict={burden.pct === undefined ? "No income yet" : burden.pct <= 40 ? "Comfortable" : burden.pct <= 50 ? "Stretched" : "Too high"}
							hint="EMIs as a share of income. Lenders prefer under 40-50%."
						/>
						<Gauge
							title="Card limit used"
							value={cards.pct}
							target={30}
							status={cards.status}
							verdict={cards.pct === undefined ? "No credit cards" : cards.pct <= 30 ? "Good for CIBIL" : cards.pct <= 70 ? "Bring it down" : "Hurting your score"}
							hint="Under 30% of your limit helps your CIBIL score."
						/>
					</div>
				</Card>
			</div>

			<div className="mt-4 grid gap-4 xl:grid-cols-2">
				<Card index={6} icon={<BarChart3 />} title="Income vs money out" description={`Each family month, last ${a.series.length} months`}>
					<CashFlowChart data={a.series.map((f) => ({ month: f.month, income: f.income, expenses: f.spending + f.bills + f.emis }))} currency={currency} highlight={a.month} />
				</Card>
				<Card index={7} icon={<BarChart3 />} title="What money went on" description="EMIs, everyday spending and bills each month">
					<StackedBars
						label="Money out by month"
						currency={currency}
						highlight={a.month}
						months={a.series.map((f) => f.month)}
						values={a.series.map((f) => ({ emis: f.emis, spending: f.spending, bills: f.bills }))}
						series={[
							{ key: "emis", label: "EMIs", color: "var(--viz-emi)" },
							{ key: "spending", label: "Spending", color: "var(--viz-spend)" },
							{ key: "bills", label: "Bills", color: "var(--viz-bill)" },
						]}
					/>
				</Card>
			</div>

			<div className="mt-4 grid gap-4 xl:grid-cols-2">
				<Card index={8} icon={<TrendingUp />} title="Savings built up" description={`What you saved, added up over ${a.series.length} months: ${formatMoney(savedTotal, currency)}`}>
					<LineChart points={cumulative} currency={currency} label="Savings built up over time" />
				</Card>
				{withBudget ? (
					<Card index={9} icon={<Target />} title="Budget vs actual" description={budgetRows.length ? "Biggest risks first · the tick marks how far through the month we are" : "No budget for this month"}>
						{budgetRows.length ? <BulletBars rows={budgetRows} currency={currency} progress={monthProgress(a, todayIso())} /> : <NoData text="Set a budget on the Budgets page to compare." />}
					</Card>
				) : (
					<PayeesCard a={a} currency={currency} index={9} />
				)}
			</div>

			<div className="mt-4 grid gap-4 xl:grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)]">
				<Card index={10} icon={<CalendarDays />} title="Spending by day" description="Darker days are bigger spending days · bills and EMIs left out">
					<SpendHeatmap days={a.days} currency={currency} today={todayIso()} />
				</Card>
				{withBudget && <PayeesCard a={a} currency={currency} index={11} />}
			</div>
		</>
	);
}

function PayeesCard({ a, currency, index }: { a: Analytics; currency: string; index: number }) {
	return (
		<Card index={index} icon={<Store />} title="Top payees" description="Where the most money went this month">
			{a.payees.length ? <RankBars rows={a.payees.map((p) => ({ name: p.name, amount: p.amount, note: `${p.count}×` }))} currency={currency} /> : <NoData text="Add a payee to entries to see this." />}
		</Card>
	);
}

function HeroFigure({ label, value, change, goodWhenUp, hint }: { label: string; value: ReactNode; change?: number; goodWhenUp?: boolean; hint?: string }) {
	return (
		<div>
			<dt className="text-xs text-brand-100/70">{label}</dt>
			<dd className="mt-1 text-xl font-semibold tracking-tight tabular-nums sm:text-2xl">{value}</dd>
			<dd className="mt-1">{change !== undefined ? <DeltaPill change={change} goodWhenUp={goodWhenUp ?? true} /> : <span className="text-[11px] text-brand-100/60">{hint}</span>}</dd>
		</div>
	);
}

function Card({ index, icon, title, description, children, className }: { index: number; icon: ReactNode; title: string; description?: string; children: ReactNode; className?: string }) {
	return (
		<Reveal index={index} className={className}>
			<Panel
				className="vk-lift h-full"
				title={
					<span className="flex items-center gap-2">
						<span className="flex size-7 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300 [&_svg]:size-4" aria-hidden="true">
							{icon}
						</span>
						{title}
					</span>
				}
				description={description}
			>
				{children}
			</Panel>
		</Reveal>
	);
}

function NoData({ text = "Nothing to chart for this period." }: { text?: string }) {
	return <p className="py-10 text-center text-sm text-slate-500 dark:text-slate-400">{text}</p>;
}

function AnalyticsSkeleton() {
	return (
		<div aria-busy="true" aria-label="Loading">
			<Skeleton className="h-48 rounded-3xl" />
			<div className="mt-4 grid gap-4 lg:grid-cols-3">
				{[0, 1, 2].map((i) => (
					<Skeleton key={i} className="h-72 rounded-2xl" />
				))}
			</div>
			<div className="mt-4 grid gap-4 xl:grid-cols-2">
				<Skeleton className="h-80 rounded-2xl" />
				<Skeleton className="h-80 rounded-2xl" />
			</div>
		</div>
	);
}
