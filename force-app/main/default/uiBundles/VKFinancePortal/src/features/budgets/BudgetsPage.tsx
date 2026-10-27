import { useEffect, useMemo, useState } from "react";
import { useSearchParams } from "react-router";
import { CalendarRange, Copy, Pencil, Plus, Target } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { CategoryChip } from "@/components/finance/icons";
import { EmptyState, MonthSwitcher, PageHeader, Panel, StatusMeter, budgetStatus } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { BudgetLine, BudgetView, Category } from "@/api/financeTypes";
import { currencySymbol, formatMoney, monthKey, monthLabel, shiftMonth } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { useLedger } from "@/features/ledger/LedgerContext";

export default function BudgetsPage() {
	const { version, currency, loadCategories } = useLedger();
	const [params, setParams] = useSearchParams();
	const month = params.get("month") ?? monthKey();
	const { data: budget, errors, loading, setData } = useAsync(() => financeApi.budget(month), [month, version]);
	const [editing, setEditing] = useState(false);
	const [busy, setBusy] = useState(false);
	const [actionErrors, setActionErrors] = useState<string[]>([]);

	useEffect(() => setEditing(false), [month]);

	async function copyLastMonth() {
		setBusy(true);
		try {
			setData(await financeApi.copyBudget(month));
			toast.success(`Copied the ${monthLabel(shiftMonth(month, -1))} plan`);
			setActionErrors([]);
		} catch (error) {
			setActionErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	const progress = useMemo(() => {
		if (!budget) return 0;
		return budget.daysInMonth ? budget.daysElapsed / budget.daysInMonth : 0;
	}, [budget]);

	return (
		<>
			<PageHeader
				title="Budgets"
				description="A plan for each month, and how the family is tracking against it."
				actions={
					<>
						<MonthSwitcher value={month} onChange={(m) => setParams(m === monthKey() ? {} : { month: m }, { replace: true })} />
						{budget?.canEdit && !editing && (
							<>
								<Button variant="outline" onClick={() => void copyLastMonth()} disabled={busy}>
									{busy ? <Spinner /> : <Copy />}
									Copy last month
								</Button>
								<Button onClick={() => setEditing(true)}>
									<Pencil />
									{budget.exists ? "Edit plan" : "Create plan"}
								</Button>
							</>
						)}
					</>
				}
			/>
			<FormErrors errors={[...errors, ...actionErrors]} />

			{!budget && loading ? (
				<div className="space-y-4">
					<Skeleton className="h-36 rounded-2xl" />
					<Skeleton className="h-80 rounded-2xl" />
				</div>
			) : budget && editing ? (
				<BudgetEditor
					budget={budget}
					currency={currency}
					loadCategories={loadCategories}
					onCancel={() => setEditing(false)}
					onSaved={(saved) => {
						setData(saved);
						setEditing(false);
					}}
				/>
			) : budget && !budget.exists ? (
				<Panel>
					<EmptyState
						icon={<Target />}
						title={`No plan for ${monthLabel(month)} yet`}
						action={
							budget.canEdit && (
								<div className="flex flex-wrap justify-center gap-2">
									<Button onClick={() => setEditing(true)}>
										<Plus />
										Create a plan
									</Button>
									<Button variant="outline" onClick={() => void copyLastMonth()} disabled={busy}>
										<Copy />
										Copy last month
									</Button>
								</div>
							)
						}
					>
						{budget.canEdit
							? "Set how much the family wants to spend in each category. Spending fills the bars as it happens."
							: "Your Family Admin hasn't set a budget for this month."}
					</EmptyState>
					{budget.unbudgeted.length > 0 && <Unbudgeted lines={budget.unbudgeted} currency={currency} />}
				</Panel>
			) : (
				budget && <BudgetSummary budget={budget} currency={currency} progress={progress} month={month} />
			)}
		</>
	);
}

function BudgetSummary({ budget, currency, progress, month }: { budget: BudgetView; currency: string; progress: number; month: string }) {
	const left = budget.totalPlanned - budget.totalSpent;
	const plannedSpent = budget.lines.reduce((s, l) => s + l.spent, 0);
	const daysLeft = budget.daysInMonth - budget.daysElapsed;
	const isCurrent = month === monthKey();
	const perDay = isCurrent && daysLeft > 0 && left > 0 ? left / daysLeft : undefined;

	return (
		<div className="space-y-4">
			<div className="grid gap-4 lg:grid-cols-3">
				<div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-slate-900 via-slate-800 to-teal-900 p-6 text-white shadow-lg lg:col-span-2">
					<div className="pointer-events-none absolute -top-20 -right-20 size-56 rounded-full bg-teal-400/15 blur-2xl" />
					<p className="text-sm text-slate-300">Spent so far</p>
					<p className="mt-1 text-3xl font-semibold tabular-nums">
						{formatMoney(budget.totalSpent, currency)}
						<span className="text-base font-normal text-slate-400"> of {formatMoney(budget.totalPlanned, currency)}</span>
					</p>
					<div className="mt-4 rounded-xl bg-white/95 p-3 text-slate-900">
						<StatusMeter
							value={plannedSpent}
							max={budget.totalPlanned}
							status={budgetStatus(plannedSpent, budget.totalPlanned, progress)}
							label={left >= 0 ? `${formatMoney(left, currency)} left in the plan` : `${formatMoney(-left, currency)} over the plan`}
						/>
					</div>
				</div>
				<Panel>
					<div className="flex h-full flex-col justify-center gap-3">
						<div className="flex items-center gap-3">
							<span className="flex size-10 items-center justify-center rounded-xl bg-teal-50 text-teal-700">
								<CalendarRange className="size-5" aria-hidden="true" />
							</span>
							<div>
								<p className="text-xs text-slate-500">{isCurrent ? `${daysLeft} days to go` : monthLabel(month)}</p>
								<p className="text-lg font-semibold tabular-nums text-slate-900">
									{perDay !== undefined ? `${formatMoney(Math.floor(perDay), currency)} / day` : `${Math.round(progress * 100)}% of the month`}
								</p>
							</div>
						</div>
						<p className="text-xs text-slate-500">
							{perDay !== undefined
								? "What the family can spend each day and still finish inside the plan."
								: "Daily allowance shows for the current month."}
						</p>
					</div>
				</Panel>
			</div>

			<Panel title="By category" description={`${budget.lines.length} planned categories`}>
				<ul className="divide-y divide-slate-100">
					{budget.lines.map((line) => {
						const remaining = line.planned - line.spent;
						const status = budgetStatus(line.spent, line.planned, progress);
						return (
							<li key={line.categoryId} className="grid gap-3 py-3.5 sm:grid-cols-[minmax(0,14rem)_1fr_auto] sm:items-center">
								<div className="flex items-center gap-3">
									<CategoryChip icon={line.icon} color={line.color} />
									<div className="min-w-0">
										<p className="truncate text-sm font-medium text-slate-900">{line.name}</p>
										<p className="text-xs text-slate-500">{line.planned > 0 ? `${Math.round((line.spent / line.planned) * 100)}% used` : "Not planned"}</p>
									</div>
								</div>
								<StatusMeter
									value={line.spent}
									max={line.planned}
									status={status}
									label={
										remaining < 0
											? `${formatMoney(-remaining, currency)} over`
											: status === "warning"
												? `${formatMoney(remaining, currency)} left - slow down`
												: `${formatMoney(remaining, currency)} left`
									}
								/>
								<p className="text-right text-sm tabular-nums">
									<span className="font-semibold text-slate-900">{formatMoney(line.spent, currency)}</span>
									<span className="text-slate-400"> / {formatMoney(line.planned, currency)}</span>
								</p>
							</li>
						);
					})}
				</ul>
				{budget.unbudgeted.length > 0 && <Unbudgeted lines={budget.unbudgeted} currency={currency} />}
			</Panel>
		</div>
	);
}

function Unbudgeted({ lines, currency }: { lines: BudgetLine[]; currency: string }) {
	return (
		<div className="mt-5 rounded-xl bg-amber-50/60 p-4 ring-1 ring-amber-900/10">
			<p className="text-sm font-medium text-amber-950">Spending outside the plan</p>
			<ul className="mt-2 flex flex-wrap gap-2">
				{lines.map((l) => (
					<li key={l.categoryId} className="inline-flex items-center gap-2 rounded-full bg-white py-1 pr-3 pl-1 text-xs ring-1 ring-slate-900/5">
						<CategoryChip icon={l.icon} color={l.color} size="sm" className="size-6 rounded-full" />
						{l.name}
						<span className="font-semibold tabular-nums">{formatMoney(l.spent, currency)}</span>
					</li>
				))}
			</ul>
		</div>
	);
}

function BudgetEditor({
	budget,
	currency,
	loadCategories,
	onCancel,
	onSaved,
}: {
	budget: BudgetView;
	currency: string;
	loadCategories: () => Promise<Category[]>;
	onCancel: () => void;
	onSaved: (budget: BudgetView) => void;
}) {
	const [categories, setCategories] = useState<Category[]>();
	const [amounts, setAmounts] = useState<Record<string, string>>(() =>
		Object.fromEntries(budget.lines.map((l) => [l.categoryId, String(l.planned)])),
	);
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const spent = useMemo(
		() => new Map([...budget.lines, ...budget.unbudgeted].map((l) => [l.categoryId, l.spent])),
		[budget],
	);

	useEffect(() => {
		loadCategories()
			.then((all) => setCategories(all.filter((c) => c.kind === "Expense" && !c.parentId && c.active)))
			.catch((error: unknown) => setErrors(errorMessages(error)));
	}, [loadCategories]);

	const total = Object.values(amounts).reduce((s, v) => s + (Number(v.replace(/,/g, "")) || 0), 0);

	async function save() {
		const lines = (categories ?? []).map((c) => ({ categoryId: c.id, planned: Number((amounts[c.id] ?? "").replace(/,/g, "")) || 0 }));
		if (lines.some((l) => l.planned < 0)) {
			setErrors(["Planned amounts can't be negative."]);
			return;
		}
		setSaving(true);
		try {
			onSaved(await financeApi.saveBudget(budget.month, lines));
			toast.success(`Plan for ${monthLabel(budget.month)} saved`);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Panel
			title={`Plan for ${monthLabel(budget.month)}`}
			description="Leave a category empty to keep it out of the plan."
			action={<p className="text-sm font-semibold tabular-nums text-slate-900">Total {formatMoney(total, currency)}</p>}
		>
			{!categories ? (
				<Skeleton className="h-64 rounded-xl" />
			) : (
				<div className="grid gap-x-6 gap-y-2 md:grid-cols-2">
					{categories.map((c) => (
						<label key={c.id} className="flex items-center gap-3 rounded-xl px-2 py-1.5 hover:bg-slate-50">
							<CategoryChip icon={c.icon} color={c.color} size="sm" />
							<span className="min-w-0 flex-1">
								<span className="block truncate text-sm font-medium text-slate-800">{c.name}</span>
								{spent.get(c.id) ? (
									<span className="text-xs text-slate-500">Spent {formatMoney(spent.get(c.id), currency)} so far</span>
								) : null}
							</span>
							<span className="relative w-32">
								<span className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-xs text-slate-400">{currencySymbol(currency)}</span>
								<Input
									inputMode="decimal"
									aria-label={`Planned for ${c.name}`}
									className="h-9 pl-6 text-right tabular-nums"
									placeholder="0"
									value={amounts[c.id] ?? ""}
									onChange={(e) => setAmounts((prev) => ({ ...prev, [c.id]: e.target.value.replace(/[^0-9.,]/g, "") }))}
								/>
							</span>
						</label>
					))}
				</div>
			)}
			<FormErrors errors={errors} />
			<div className="mt-5 flex justify-end gap-2">
				<Button variant="outline" onClick={onCancel}>
					Cancel
				</Button>
				<Button onClick={() => void save()} disabled={saving || !categories}>
					{saving && <Spinner />}
					Save plan
				</Button>
			</div>
		</Panel>
	);
}
