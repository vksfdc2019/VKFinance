import { useEffect, useState, type FormEvent } from "react";
import { Pause, Play, Plus, Repeat, SkipForward } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { CategoryChip } from "@/components/finance/icons";
import { Reveal } from "@/components/finance/motion";
import { EmptyState, PageHeader, Panel, SegmentedControl } from "@/components/finance/ui";
import { commitmentApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account, AccountRef, Category } from "@/api/financeTypes";
import { RULE_FREQUENCIES, type RecurringRule } from "@/api/commitmentTypes";
import { currencySymbol, formatDate, formatMoney, todayIso } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { CategoryPicker } from "@/features/ledger/CategoryPicker";
import { useLedger } from "@/features/ledger/LedgerContext";
import { dueText } from "./shared";

function daysUntil(iso?: string) {
	return iso ? Math.round((new Date(`${iso}T00:00:00`).getTime() - new Date(new Date().toDateString()).getTime()) / 86400000) : undefined;
}

export default function RecurringPage() {
	const { version, refresh, currency } = useLedger();
	const { data: rules, errors, loading } = useAsync(() => commitmentApi.rules(), [version]);
	const [editing, setEditing] = useState<RecurringRule | "new" | null>(null);
	const [busy, setBusy] = useState<string | null>(null);

	async function run(rule: RecurringRule, action: "post" | "skip" | "toggle") {
		setBusy(rule.id + action);
		try {
			if (action === "toggle") await commitmentApi.updateRule(rule.id, { active: !rule.active });
			else await commitmentApi.postRule(rule.id, action === "skip");
			toast.success(action === "post" ? `${rule.name} recorded` : action === "skip" ? `${rule.name} skipped this time` : rule.active ? "Paused" : "Resumed");
			refresh();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		} finally {
			setBusy(null);
		}
	}

	const monthlyOut = (rules ?? [])
		.filter((r) => r.active && r.type === "Expense")
		.reduce((s, r) => s + (r.frequency === "Weekly" ? (r.amount * 52) / 12 : r.frequency === "Quarterly" ? r.amount / 3 : r.frequency === "Yearly" ? r.amount / 12 : r.amount), 0);

	return (
		<>
			<PageHeader
				title="Recurring"
				description="Salary, rent, SIPs and subscriptions that repeat. Auto-post records them for you; Suggest asks first."
				actions={
					<Button onClick={() => setEditing("new")}>
						<Plus />
						Add recurring
					</Button>
				}
			/>
			<FormErrors errors={errors} />
			{!rules && loading ? (
				<Skeleton className="h-64 rounded-2xl" />
			) : rules && rules.length === 0 ? (
				<Panel>
					<EmptyState
						icon={<Repeat />}
						title="Nothing repeating yet"
						action={
							<Button onClick={() => setEditing("new")}>
								<Plus />
								Add your salary or rent
							</Button>
						}
					>
						Set it once and every month&apos;s entry is ready - or posted automatically.
					</EmptyState>
				</Panel>
			) : (
				rules && (
					<>
						<p className="mb-4 text-sm text-slate-600">
							About <span className="font-semibold tabular-nums text-slate-900">{formatMoney(Math.round(monthlyOut), currency)}</span> goes out on repeat each month.
						</p>
						<ul className="grid gap-3 lg:grid-cols-2">
							{rules.map((r, i) => {
								const days = daysUntil(r.nextRunDate);
								const due = days !== undefined && days <= 0 && r.active;
								return (
									<Reveal as="li" key={r.id} index={i}>
										<div className={cn("vk-lift rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-900/5", !r.active && "opacity-60", due && "ring-amber-300")}>
											<div className="flex items-start gap-3">
												<CategoryChip icon={r.icon} color={r.color} size="lg" />
												<div className="min-w-0 flex-1">
													<div className="flex flex-wrap items-center gap-2">
														<p className="truncate font-semibold text-slate-900">{r.name}</p>
														<Badge variant={r.mode === "Auto-post" ? "secondary" : "outline"}>{r.mode}</Badge>
														{!r.active && <Badge variant="outline">Paused</Badge>}
													</div>
													<p className="truncate text-xs text-slate-500">
														{r.type === "Transfer" ? `${r.accountName} → ${r.toAccountName}` : `${r.categoryName ?? r.type} · ${r.accountName}`} · {r.frequency}
														{r.memberName ? ` · ${r.memberName}` : ""}
													</p>
												</div>
												<p className={cn("font-semibold tabular-nums", r.type === "Income" ? "text-emerald-700" : "text-slate-900")}>
													{r.type === "Income" ? "+" : ""}
													{formatMoney(r.amount, currency)}
												</p>
											</div>
											<div className="mt-3 flex flex-wrap items-center justify-between gap-2">
												<p className={cn("text-xs", due ? "font-medium text-amber-800" : "text-slate-500")}>
													{r.active && r.nextRunDate ? `${days !== undefined ? dueText(days) : ""} · ${formatDate(r.nextRunDate)}` : "Finished or paused"}
												</p>
												{r.canEdit && (
													<div className="flex gap-1">
														{r.active && r.nextRunDate && (
															<>
																<Button size="xs" onClick={() => void run(r, "post")} disabled={busy !== null}>
																	{busy === r.id + "post" ? <Spinner /> : <Play />}
																	Record now
																</Button>
																<Button size="xs" variant="ghost" onClick={() => void run(r, "skip")} disabled={busy !== null}>
																	<SkipForward />
																	Skip
																</Button>
															</>
														)}
														<Button size="xs" variant="ghost" onClick={() => void run(r, "toggle")} disabled={busy !== null} aria-label={r.active ? `Pause ${r.name}` : `Resume ${r.name}`}>
															{r.active ? <Pause /> : <Play />}
														</Button>
														<Button size="xs" variant="ghost" onClick={() => setEditing(r)}>
															Edit
														</Button>
													</div>
												)}
											</div>
										</div>
									</Reveal>
								);
							})}
						</ul>
					</>
				)
			)}
			{editing && (
				<RuleDialog
					rule={editing === "new" ? undefined : editing}
					currency={currency}
					onClose={() => setEditing(null)}
					onSaved={() => {
						setEditing(null);
						refresh();
					}}
				/>
			)}
		</>
	);
}

function RuleDialog({ rule, currency, onClose, onSaved }: { rule?: RecurringRule; currency: string; onClose: () => void; onSaved: () => void }) {
	const { loadCategories } = useLedger();
	const [type, setType] = useState<RecurringRule["type"]>(rule?.type ?? "Expense");
	const [name, setName] = useState(rule?.name ?? "");
	const [amount, setAmount] = useState(rule ? String(rule.amount) : "");
	const [accountId, setAccountId] = useState(rule?.accountId ?? "");
	const [toAccountId, setToAccountId] = useState(rule?.toAccountId ?? "");
	const [categoryId, setCategoryId] = useState(rule?.categoryId ?? "");
	const [payee, setPayee] = useState(rule?.payee ?? "");
	const [frequency, setFrequency] = useState<string>(rule?.frequency ?? "Monthly");
	const [nextRun, setNextRun] = useState(rule?.nextRunDate ?? todayIso());
	const [mode, setMode] = useState<string>(rule?.mode ?? "Suggest");
	const [refs, setRefs] = useState<{ accounts: Account[]; targets: AccountRef[]; categories: Category[] }>();
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	useEffect(() => {
		Promise.all([financeApi.accounts(), financeApi.transferTargets(), loadCategories()])
			.then(([accounts, targets, categories]) => setRefs({ accounts: accounts.filter((a) => a.canUse && a.type !== "Loan"), targets, categories }))
			.catch((error: unknown) => setErrors(errorMessages(error)));
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			const input = {
				name: name.trim(),
				type,
				amount: Number(amount.replace(/,/g, "")),
				accountId,
				...(type === "Transfer" ? { toAccountId } : { categoryId, payee: payee.trim() || undefined }),
				frequency,
				nextRunDate: nextRun,
				mode,
			};
			if (rule) await commitmentApi.updateRule(rule.id, input);
			else await commitmentApi.createRule(input);
			toast.success(rule ? "Saved" : `${input.name} will repeat ${frequency.toLowerCase()}`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	const sources = (refs?.accounts ?? []).filter((a) => type === "Expense" || !a.isLiability);
	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-lg">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{rule ? `Edit ${rule.name}` : "Add something that repeats"}</DialogTitle>
						<DialogDescription>We check every morning and record (or ask you to confirm) anything that&apos;s due.</DialogDescription>
					</DialogHeader>
					<SegmentedControl
						label="Type"
						value={type}
						onChange={setType}
						className="w-full"
						options={[
							{ value: "Expense", label: "Expense", disabled: Boolean(rule) && rule?.type === "Transfer" },
							{ value: "Income", label: "Income", disabled: Boolean(rule) && rule?.type === "Transfer" },
							{ value: "Transfer", label: "Transfer", disabled: Boolean(rule) && rule?.type !== "Transfer" },
						]}
					/>
					<div className="grid gap-3 sm:grid-cols-2">
						<TextField id="rule-name" label="Name" placeholder="e.g. Rent, Salary, SIP" value={name} maxLength={80} onChange={(e) => setName(e.target.value)} />
						<div className="grid gap-1.5">
							<Label htmlFor="rule-amount">Amount</Label>
							<div className="relative">
								<span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-sm text-slate-400">{currencySymbol(currency)}</span>
								<Input id="rule-amount" inputMode="decimal" className="pl-7" value={amount} onChange={(e) => setAmount(e.target.value)} />
							</div>
						</div>
					</div>
					<div className="grid gap-3 sm:grid-cols-2">
						<div className="grid gap-1.5">
							<Label htmlFor="rule-account">{type === "Income" ? "Into" : "From"}</Label>
							<Select value={accountId} onValueChange={setAccountId}>
								<SelectTrigger id="rule-account" className="w-full">
									<SelectValue placeholder="Choose an account" />
								</SelectTrigger>
								<SelectContent>
									{sources.map((a) => (
										<SelectItem key={a.id} value={a.id}>
											{a.name}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						{type === "Transfer" ? (
							<div className="grid gap-1.5">
								<Label htmlFor="rule-to">To</Label>
								<Select value={toAccountId} onValueChange={setToAccountId}>
									<SelectTrigger id="rule-to" className="w-full">
										<SelectValue placeholder="Choose an account" />
									</SelectTrigger>
									<SelectContent>
										{(refs?.targets ?? [])
											.filter((t) => t.id !== accountId)
											.map((t) => (
												<SelectItem key={t.id} value={t.id}>
													{t.name}
													{t.ownerName ? ` · ${t.ownerName}` : ""}
												</SelectItem>
											))}
									</SelectContent>
								</Select>
							</div>
						) : (
							<TextField id="rule-payee" label={type === "Income" ? "From" : "Paid to"} value={payee} maxLength={120} onChange={(e) => setPayee(e.target.value)} />
						)}
					</div>
					{type !== "Transfer" && (
						<div className="grid gap-1.5">
							<Label htmlFor="rule-category">Category</Label>
							{refs ? (
								<CategoryPicker id="rule-category" categories={refs.categories} kind={type === "Income" ? "Income" : "Expense"} value={categoryId} onChange={setCategoryId} />
							) : (
								<div className="h-10 animate-pulse rounded-lg bg-slate-100" />
							)}
						</div>
					)}
					<div className="grid gap-3 sm:grid-cols-3">
						<div className="grid gap-1.5">
							<Label htmlFor="rule-frequency">Repeats</Label>
							<Select value={frequency} onValueChange={setFrequency}>
								<SelectTrigger id="rule-frequency" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									{RULE_FREQUENCIES.map((f) => (
										<SelectItem key={f} value={f}>
											{f}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<TextField id="rule-next" label="Next date" type="date" value={nextRun} onChange={(e) => setNextRun(e.target.value)} />
						<div className="grid gap-1.5">
							<Label htmlFor="rule-mode">When due</Label>
							<Select value={mode} onValueChange={setMode}>
								<SelectTrigger id="rule-mode" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value="Suggest">Ask me first</SelectItem>
									<SelectItem value="Auto-post">Record automatically</SelectItem>
								</SelectContent>
							</Select>
						</div>
					</div>
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving || !refs}>
							{saving && <Spinner />}
							{rule ? "Save" : "Add"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
