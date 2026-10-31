import { useEffect, useMemo, useState, type FormEvent } from "react";
import { Banknote, CalendarRange, Landmark, Pencil, Percent, Plus, Table2, Trash2, Zap } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { AnimatedMoney, ProgressRing, Reveal, SuccessCheck } from "@/components/finance/motion";
import { EmptyState, PageHeader, Panel } from "@/components/finance/ui";
import { commitmentApi, familyApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account } from "@/api/financeTypes";
import type { Member } from "@/api/types";
import { LOAN_TYPES, RATE_TYPES, type Loan, type LoanSchedule, type LoanUpdate, type RateChange } from "@/api/commitmentTypes";
import { currencySymbol, formatDate, formatMoney, todayIso } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { DueBadge, PayEmiDialog } from "./shared";

/** Same formula as the server, for the live preview while typing. */
export function emiFor(principal: number, annualRate: number, months: number): number {
	if (!(principal > 0) || !(months > 0)) return 0;
	if (!annualRate) return Math.round((principal / months) * 100) / 100;
	const r = annualRate / 1200;
	const f = Math.pow(1 + r, months);
	return Math.round(((principal * r * f) / (f - 1)) * 100) / 100;
}

/** EMIs needed to repay `outstanding` at a fixed EMI; Infinity when the EMI doesn't cover the interest. */
export function monthsToRepay(outstanding: number, annualRate: number, emi: number): number {
	if (!(outstanding > 0)) return 0;
	if (!(emi > 0)) return Infinity;
	if (!annualRate) return Math.ceil(outstanding / emi);
	const r = annualRate / 1200;
	if (emi <= outstanding * r) return Infinity;
	return Math.ceil(-Math.log(1 - (outstanding * r) / emi) / Math.log(1 + r) - 1e-9);
}

export default function LoansPage() {
	const { can } = useAuth();
	const { version, refresh, currency } = useLedger();
	const { data: loans, errors, loading } = useAsync(() => commitmentApi.loans(), [version]);
	const [adding, setAdding] = useState(false);
	const [paying, setPaying] = useState<Loan | null>(null);
	const [prepaying, setPrepaying] = useState<Loan | null>(null);
	const [scheduleFor, setScheduleFor] = useState<Loan | null>(null);
	const [rating, setRating] = useState<Loan | null>(null);
	const [editing, setEditing] = useState<Loan | null>(null);
	const active = (loans ?? []).filter((l) => l.status === "Active");

	return (
		<>
			<PageHeader
				title="Loans & EMIs"
				description="What you owe, what each EMI pays off, and when you'll be debt-free."
				actions={
					can("LOANS:CREATE") && (
						<Button onClick={() => setAdding(true)}>
							<Plus />
							Add loan
						</Button>
					)
				}
			/>
			<FormErrors errors={errors} />
			{!loans && loading ? (
				<div className="grid gap-4 md:grid-cols-2">
					{[0, 1].map((i) => (
						<Skeleton key={i} className="h-64 rounded-2xl" />
					))}
				</div>
			) : loans && loans.length === 0 ? (
				<Panel>
					<EmptyState
						icon={<Landmark />}
						title="No loans - nice"
						action={
							can("LOANS:CREATE") && (
								<Button onClick={() => setAdding(true)}>
									<Plus />
									Track a loan
								</Button>
							)
						}
					>
						Home, car, education or personal loans - add one to see every EMI split into principal and interest, and your payoff date.
					</EmptyState>
				</Panel>
			) : (
				loans && (
					<>
						<div className="mb-6 grid gap-3 sm:grid-cols-3">
							<Reveal index={0} className="rounded-2xl bg-slate-900 dark:bg-slate-700 px-5 py-4 text-white">
								<p className="text-xs text-slate-300">Total outstanding</p>
								<AnimatedMoney value={active.reduce((s, l) => s + l.outstanding, 0)} currency={currency} className="mt-1 block text-2xl font-semibold tabular-nums" />
							</Reveal>
							<Reveal index={1} className="rounded-2xl bg-white dark:bg-slate-900 px-5 py-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
								<p className="text-xs text-slate-500 dark:text-slate-400">EMIs every month</p>
								<AnimatedMoney value={active.reduce((s, l) => s + l.emi, 0)} currency={currency} className="mt-1 block text-2xl font-semibold tabular-nums" />
							</Reveal>
							<Reveal index={2} className="rounded-2xl bg-white dark:bg-slate-900 px-5 py-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
								<p className="text-xs text-slate-500 dark:text-slate-400">Interest still to pay</p>
								<AnimatedMoney value={active.reduce((s, l) => s + l.interestRemaining, 0)} currency={currency} className="mt-1 block text-2xl font-semibold tabular-nums" />
							</Reveal>
						</div>
						<div className="grid gap-4 lg:grid-cols-2">
							{loans.map((l, i) => (
								<Reveal key={l.id} index={i + 3}>
									<article className="vk-lift rounded-2xl bg-white dark:bg-slate-900 p-5 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
										<div className="flex items-start gap-4">
											<ProgressRing value={l.repaidPct} size={84} label={`${l.repaidPct}% repaid`} color="var(--status-good)">
												<span className="text-base font-semibold tabular-nums text-slate-900 dark:text-slate-100">{Math.round(l.repaidPct)}%</span>
												<span className="text-[10px] text-slate-500 dark:text-slate-400">repaid</span>
											</ProgressRing>
											<div className="min-w-0 flex-1">
												<div className="flex flex-wrap items-center gap-2">
													<h2 className="truncate text-lg font-semibold text-slate-900 dark:text-slate-100">{l.name}</h2>
													{l.autoDebit && (
														<Badge variant="secondary" className="gap-1">
															<Zap className="size-3" aria-hidden="true" />
															Auto-debit
														</Badge>
													)}
													<Badge variant="outline">{l.rateType}</Badge>
													{l.status === "Closed" && <Badge variant="outline">Closed</Badge>}
												</div>
												<p className="text-xs text-slate-500 dark:text-slate-400">
													{l.loanType} loan{l.lender ? ` · ${l.lender}` : ""} · {l.annualRate}% · {l.borrowerName}
												</p>
												<dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
													<div>
														<dt className="text-xs text-slate-500 dark:text-slate-400">Outstanding</dt>
														<dd className="font-semibold tabular-nums">{formatMoney(l.outstanding, currency)}</dd>
													</div>
													<div>
														<dt className="text-xs text-slate-500 dark:text-slate-400">EMI</dt>
														<dd className="font-semibold tabular-nums">{formatMoney(l.emi, currency)}</dd>
													</div>
													<div>
														<dt className="text-xs text-slate-500 dark:text-slate-400">EMIs left</dt>
														<dd className="font-semibold tabular-nums">{l.installmentsLeft}</dd>
													</div>
													<div>
														<dt className="text-xs text-slate-500 dark:text-slate-400">Debt-free by</dt>
														<dd className="font-semibold">{l.payoffDate ? formatDate(l.payoffDate) : "—"}</dd>
													</div>
												</dl>
											</div>
										</div>
										{l.next && l.status === "Active" && (
											<div className="mt-4 flex flex-wrap items-center justify-between gap-2 rounded-xl bg-slate-50 dark:bg-slate-800/40 px-3 py-2.5">
												<div className="text-sm">
													<span className="font-medium text-slate-900 dark:text-slate-100">EMI {l.next.no}</span>
													<span className="text-slate-500 dark:text-slate-400"> · {formatDate(l.next.dueDate)} · </span>
													<span className="tabular-nums text-emerald-700 dark:text-emerald-300">{formatMoney(l.next.principal, currency)} principal</span>
													<span className="text-slate-400"> + </span>
													<span className="tabular-nums text-orange-700 dark:text-orange-300">{formatMoney(l.next.interest, currency)} interest</span>
												</div>
												<DueBadge status={l.next.status} daysLeft={Math.round((new Date(l.next.dueDate).getTime() - Date.now()) / 86400000)} />
											</div>
										)}
										<div className="mt-4 flex flex-wrap gap-2">
											{l.canPay && l.next && (
												<Button size="sm" onClick={() => setPaying(l)}>
													<Banknote />
													Pay EMI
												</Button>
											)}
											{l.canPay && (
												<Button size="sm" variant="outline" onClick={() => setPrepaying(l)}>
													Prepay
												</Button>
											)}
											{l.canEdit && (
												<Button size="sm" variant="ghost" onClick={() => setEditing(l)}>
													<Pencil />
													Edit
												</Button>
											)}
											{can("LOANS:EDIT") && l.status === "Active" && (
												<Button size="sm" variant="outline" onClick={() => setRating(l)}>
													<Percent />
													Rate changed
												</Button>
											)}
											<Button size="sm" variant="ghost" onClick={() => setScheduleFor(l)}>
												<Table2 />
												Schedule
											</Button>
										</div>
									</article>
								</Reveal>
							))}
						</div>
					</>
				)
			)}

			{adding && (
				<LoanDialog
					currency={currency}
					onClose={() => setAdding(false)}
					onSaved={() => {
						setAdding(false);
						refresh();
					}}
				/>
			)}
			{paying && (
				<PayEmiDialog
					loan={paying}
					currency={currency}
					onClose={() => setPaying(null)}
					onPaid={() => {
						setPaying(null);
						refresh();
					}}
				/>
			)}
			{prepaying && (
				<PrepayDialog
					loan={prepaying}
					currency={currency}
					onClose={() => setPrepaying(null)}
					onDone={() => {
						setPrepaying(null);
						refresh();
					}}
				/>
			)}
			{scheduleFor && <ScheduleDialog loan={scheduleFor} currency={currency} onClose={() => setScheduleFor(null)} />}
			{editing && (
				<LoanDialog
					loan={editing}
					currency={currency}
					onClose={() => setEditing(null)}
					onSaved={() => {
						setEditing(null);
						refresh();
					}}
				/>
			)}
			{rating && (
				<RateDialog
					loan={rating}
					currency={currency}
					onClose={() => setRating(null)}
					onDone={() => {
						setRating(null);
						refresh();
					}}
				/>
			)}
		</>
	);
}

function ScheduleDialog({ loan, currency, onClose }: { loan: Loan; currency: string; onClose: () => void }) {
	const { data, errors } = useAsync<LoanSchedule>(() => commitmentApi.schedule(loan.id), [loan.id]);
	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-3xl">
				<DialogHeader>
					<DialogTitle>{loan.name} · repayment schedule</DialogTitle>
					<DialogDescription>
						{data ? `${formatMoney(data.totalInterestRemaining, currency)} interest left over ${loan.installmentsLeft} EMIs.` : "Loading…"}
					</DialogDescription>
				</DialogHeader>
				<FormErrors errors={errors} />
				<div className="mb-2 flex items-center gap-4 text-xs text-slate-600 dark:text-slate-400" aria-label="Legend">
					<span className="inline-flex items-center gap-1.5">
						<span className="size-2.5 rounded-sm" style={{ backgroundColor: "var(--series-magnitude)" }} />
						Principal
					</span>
					<span className="inline-flex items-center gap-1.5">
						<span className="size-2.5 rounded-sm" style={{ backgroundColor: "var(--series-spend)" }} />
						Interest
					</span>
				</div>
				<div className="max-h-[60vh] overflow-y-auto rounded-xl ring-1 ring-slate-900/5 dark:ring-white/10">
					<table className="w-full text-sm">
						<thead className="sticky top-0 bg-slate-50 dark:bg-slate-800/40 text-left text-xs text-slate-500 dark:text-slate-400">
							<tr>
								<th className="px-3 py-2 font-medium">#</th>
								<th className="px-3 py-2 font-medium">Due</th>
								<th className="px-3 py-2 text-right font-medium">EMI</th>
								<th className="hidden w-40 px-3 py-2 font-medium sm:table-cell">Split</th>
								<th className="px-3 py-2 text-right font-medium">Principal</th>
								<th className="px-3 py-2 text-right font-medium">Interest</th>
								<th className="px-3 py-2 text-right font-medium">Balance</th>
							</tr>
						</thead>
						<tbody className="tabular-nums">
							{(data?.rows ?? []).map((r) => (
								<tr key={r.no} className={r.status === "Paid" ? "bg-emerald-50/40 dark:bg-emerald-950/40 text-slate-500 dark:text-slate-400" : "border-t border-slate-100 dark:border-slate-800"}>
									<td className="px-3 py-1.5">{r.no}</td>
									<td className="px-3 py-1.5 whitespace-nowrap">{formatDate(r.dueDate)}</td>
									<td className="px-3 py-1.5 text-right">{formatMoney(r.emi, currency)}</td>
									<td className="hidden px-3 py-1.5 sm:table-cell">
										<div className="flex h-2 gap-0.5 overflow-hidden rounded-full" aria-hidden="true">
											<div style={{ width: `${(r.principal / r.emi) * 100}%`, backgroundColor: "var(--series-magnitude)" }} className="rounded-l-full" />
											<div style={{ backgroundColor: "var(--series-spend)" }} className="flex-1 rounded-r-full" />
										</div>
									</td>
									<td className="px-3 py-1.5 text-right">{formatMoney(r.principal, currency)}</td>
									<td className="px-3 py-1.5 text-right">{formatMoney(r.interest, currency)}</td>
									<td className="px-3 py-1.5 text-right">{r.status === "Paid" ? "Paid" : formatMoney(r.closing, currency)}</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			</DialogContent>
		</Dialog>
	);
}

function RateDialog({ loan, currency, onClose, onDone }: { loan: Loan; currency: string; onClose: () => void; onDone: () => void }) {
	const { data: history } = useAsync<RateChange[]>(() => commitmentApi.rateChanges(loan.id), [loan.id]);
	const [rate, setRate] = useState("");
	const [adjust, setAdjust] = useState<"EMI" | "Tenure">("Tenure");
	const [bankEmi, setBankEmi] = useState("");
	const [effectiveDate, setEffectiveDate] = useState(todayIso());
	const [note, setNote] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	const newRate = rate === "" ? NaN : Number(rate);
	const quoted = Number(bankEmi.replace(/,/g, "")) || 0;
	const preview = useMemo(() => {
		if (Number.isNaN(newRate)) return null;
		const emi = quoted || (adjust === "EMI" ? emiFor(loan.outstanding, newRate, Math.max(1, loan.installmentsLeft)) : loan.emi);
		return { emi, left: monthsToRepay(loan.outstanding, newRate, emi) };
	}, [newRate, quoted, adjust, loan]);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			const updated = await commitmentApi.changeRate(loan.id, {
				annualRate: newRate,
				adjust,
				emiAmount: quoted || undefined,
				effectiveDate,
				note: note.trim() || undefined,
			});
			toast.success(`${loan.name} is now at ${updated.annualRate}% · EMI ${formatMoney(updated.emi, currency)} · ${updated.installmentsLeft} EMIs left`);
			onDone();
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-lg">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{loan.name} · rate change</DialogTitle>
						<DialogDescription>
							Now {loan.annualRate}% ({loan.rateType.toLowerCase()}) · EMI {formatMoney(loan.emi, currency)} · {loan.installmentsLeft} EMIs left on{" "}
							{formatMoney(loan.outstanding, currency)}. The new rate applies from the next unpaid EMI.
						</DialogDescription>
					</DialogHeader>
					<div className="grid gap-3 sm:grid-cols-2">
						<TextField id="rate-new" label="New rate (% a year)" inputMode="decimal" autoFocus value={rate} onChange={(e) => setRate(e.target.value.replace(/[^0-9.]/g, ""))} />
						<TextField id="rate-date" label="Effective from" type="date" value={effectiveDate} onChange={(e) => setEffectiveDate(e.target.value)} />
						<div className="grid gap-1.5 sm:col-span-2">
							<Label htmlFor="rate-adjust">The bank changed</Label>
							<Select value={adjust} onValueChange={(v) => setAdjust(v as "EMI" | "Tenure")}>
								<SelectTrigger id="rate-adjust" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value="Tenure">The number of EMIs (EMI stays the same)</SelectItem>
									<SelectItem value="EMI">The EMI amount (end date stays the same)</SelectItem>
								</SelectContent>
							</Select>
						</div>
						<TextField
							id="rate-emi"
							label="New EMI as per bank (optional)"
							inputMode="decimal"
							value={bankEmi}
							onChange={(e) => setBankEmi(e.target.value.replace(/[^0-9.,]/g, ""))}
							hint="Leave blank to calculate it."
						/>
						<TextField id="rate-note" label="Note (optional)" placeholder="e.g. Repo rate cut" maxLength={255} value={note} onChange={(e) => setNote(e.target.value)} />
					</div>
					{preview && (
						<div className="rounded-xl bg-slate-50 dark:bg-slate-800/40 px-4 py-3 text-sm">
							{Number.isFinite(preview.left) ? (
								<>
									EMI <span className="font-semibold tabular-nums">{formatMoney(preview.emi, currency)}</span> · {preview.left} EMIs left
									{preview.left !== loan.installmentsLeft && (
										<span className="text-slate-500 dark:text-slate-400">
											{" "}
											({preview.left > loan.installmentsLeft ? "+" : ""}
											{preview.left - loan.installmentsLeft})
										</span>
									)}
								</>
							) : (
								<span className="text-orange-700 dark:text-orange-300">At {newRate}% this EMI doesn&apos;t cover the interest - choose &ldquo;The EMI amount&rdquo;.</span>
							)}
						</div>
					)}
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving || Number.isNaN(newRate)}>
							{saving && <Spinner />}
							Apply new rate
						</Button>
					</DialogFooter>
				</form>
				{history && history.length > 0 && (
					<section aria-labelledby="rate-history" className="border-t border-slate-100 dark:border-slate-800 pt-4">
						<h3 id="rate-history" className="mb-2 text-sm font-medium text-slate-900 dark:text-slate-100">
							Rate history
						</h3>
						<ol className="space-y-2 text-sm">
							{history.map((h) => (
								<li key={h.id} className="flex flex-wrap items-baseline justify-between gap-x-3">
									<span>
										<span className="text-slate-500 dark:text-slate-400">{formatDate(h.effectiveDate)} · </span>
										<span className="tabular-nums">
											{h.oldRate}% → {h.newRate}%
										</span>
										{h.note && <span className="text-slate-500 dark:text-slate-400"> · {h.note}</span>}
									</span>
									<span className="text-xs tabular-nums text-slate-500 dark:text-slate-400">
										{h.adjusted === "EMI"
											? `EMI ${formatMoney(h.oldEmi, currency)} → ${formatMoney(h.newEmi, currency)}`
											: `${h.oldEmisLeft ?? "?"} → ${h.newEmisLeft ?? "?"} EMIs left`}
									</span>
								</li>
							))}
						</ol>
					</section>
				)}
			</DialogContent>
		</Dialog>
	);
}

function PrepayDialog({ loan, currency, onClose, onDone }: { loan: Loan; currency: string; onClose: () => void; onDone: () => void }) {
	const [amount, setAmount] = useState("");
	const [accounts, setAccounts] = useState<Account[]>();
	const [accountId, setAccountId] = useState(loan.debitAccountId ?? "");
	const [result, setResult] = useState<Loan | null>(null);
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	useEffect(() => {
		financeApi.accounts().then((all) => setAccounts(all.filter((a) => a.canUse && !a.isLiability))).catch(() => setAccounts([]));
	}, []);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			setResult(await commitmentApi.prepay(loan.id, { amount: Number(amount.replace(/,/g, "")), accountId, date: todayIso() }));
			setTimeout(onDone, 1800);
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="sm:max-w-md">
				{result ? (
					<SuccessCheck
						title="Prepayment recorded"
						detail={
							<>
								{loan.installmentsLeft - result.installmentsLeft} fewer EMIs · debt-free by {result.payoffDate ? formatDate(result.payoffDate) : "—"}
							</>
						}
					/>
				) : (
					<form onSubmit={submit} noValidate className="space-y-4">
						<DialogHeader>
							<DialogTitle>Prepay {loan.name}</DialogTitle>
							<DialogDescription>
								Pays down principal only. Your EMI stays the same, so the loan finishes sooner. Outstanding: {formatMoney(loan.outstanding, currency)}.
									{loan.rateType === "Floating" && " Under RBI rules, banks can't charge a prepayment or foreclosure fee on floating-rate loans to individuals."}
							</DialogDescription>
						</DialogHeader>
						<div className="flex items-center gap-2 rounded-2xl bg-slate-50 dark:bg-slate-800/40 px-4 py-3 ring-1 ring-slate-900/5 dark:ring-white/10 focus-within:ring-2 focus-within:ring-brand-600">
							<span className="text-2xl text-slate-400">{currencySymbol(currency)}</span>
							<input
								aria-label="Prepayment amount"
								inputMode="decimal"
								autoFocus
								value={amount}
								placeholder="0"
								onChange={(e) => setAmount(e.target.value.replace(/[^0-9.,]/g, ""))}
								className="w-full bg-transparent text-3xl font-semibold tabular-nums outline-none placeholder:text-slate-300"
							/>
						</div>
						<div className="grid gap-1.5">
							<Label htmlFor="prepay-account">From</Label>
							<Select value={accountId} onValueChange={setAccountId}>
								<SelectTrigger id="prepay-account" className="w-full">
									<SelectValue placeholder="Choose an account" />
								</SelectTrigger>
								<SelectContent>
									{accounts?.map((a) => (
										<SelectItem key={a.id} value={a.id}>
											{a.name} · {formatMoney(a.balance, currency)}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<FormErrors errors={errors} />
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={saving || !amount || !accountId}>
								{saving && <Spinner />}
								Prepay
							</Button>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}

function loanForm(loan: Loan | undefined, userId: string) {
	return {
		name: loan?.name ?? "",
		lender: loan?.lender ?? "",
		loanAccountNumber: loan?.loanAccountNumber ?? "",
		loanType: loan?.loanType ?? "Home",
		principal: loan ? String(loan.principal) : "",
		annualRate: loan ? String(loan.annualRate) : "",
		rateType: loan?.rateType ?? "Fixed",
		tenureMonths: loan ? String(loan.tenureMonths) : "",
		firstEmiDate: loan?.firstEmiDate ?? todayIso(),
		installmentsPaid: loan ? String(loan.installmentsPaid) : "0",
		bankEmi: loan ? String(loan.emi) : "",
		bankOutstanding: loan ? String(loan.outstanding) : "",
		debitAccountId: loan?.debitAccountId ?? "",
		autoDebit: loan?.autoDebit ?? false,
		borrowerId: loan?.borrowerId ?? userId,
	};
}

/** Adds a loan, or edits one: details just change, while corrected terms re-price the loan on the server. */
function LoanDialog({ loan, currency, onClose, onSaved }: { loan?: Loan; currency: string; onClose: () => void; onSaved: () => void }) {
	const { profile } = useAuth();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [initial] = useState(() => loanForm(loan, profile?.userId ?? ""));
	const [form, setForm] = useState(initial);
	const [confirmDelete, setConfirmDelete] = useState(false);
	const [accounts, setAccounts] = useState<Account[]>([]);
	const [members, setMembers] = useState<Member[]>([]);
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const set = (key: keyof typeof form) => (value: string | boolean) => setForm((f) => ({ ...f, [key]: value }));

	useEffect(() => {
		financeApi.accounts().then((all) => setAccounts(all.filter((a) => a.canUse && !a.isLiability))).catch(() => undefined);
		if (isAdmin) familyApi.members().then(setMembers).catch(() => undefined);
	}, [isAdmin]);

	const principal = Number(form.principal.replace(/,/g, "")) || 0;
	const rate = Number(form.annualRate) || 0;
	const months = Number(form.tenureMonths) || 0;
	const bankEmi = Number(form.bankEmi.replace(/,/g, "")) || 0;
	const bankOutstanding = Number(form.bankOutstanding.replace(/,/g, "")) || 0;
	const preview = useMemo(() => {
		const calculated = emiFor(principal, rate, months);
		const emi = bankEmi || calculated;
		const total = emi * months;
		return { emi, calculated, interest: Math.max(0, total - principal), total };
	}, [principal, rate, months, bankEmi]);
	// More than 1% apart usually means the bank's loan amount, tenure or an earlier rate differs from what was typed.
	const emiMismatch = bankEmi > 0 && preview.calculated > 0 && Math.abs(bankEmi - preview.calculated) / preview.calculated > 0.01;

	const termsChanged =
		!!loan &&
		(["principal", "annualRate", "tenureMonths", "firstEmiDate", "installmentsPaid", "bankEmi", "bankOutstanding"] as const).some((k) => form[k].trim() !== initial[k]);

	function changes(): LoanUpdate {
		const u: LoanUpdate = {};
		const text = (k: "name" | "lender" | "loanAccountNumber") => form[k].trim();
		if (text("name") !== initial.name) u.name = text("name");
		if (text("lender") !== initial.lender) u.lender = text("lender") || null;
		if (text("loanAccountNumber") !== initial.loanAccountNumber && text("loanAccountNumber") !== loan?.loanAccountNumberMasked) {
			u.loanAccountNumber = text("loanAccountNumber") || null;
		}
		if (form.loanType !== initial.loanType) u.loanType = form.loanType;
		if (form.rateType !== initial.rateType) u.rateType = form.rateType;
		if (form.debitAccountId !== initial.debitAccountId) u.debitAccountId = form.debitAccountId || null;
		if (form.autoDebit !== initial.autoDebit) u.autoDebit = form.autoDebit;
		if (isAdmin && form.borrowerId !== initial.borrowerId) u.borrowerId = form.borrowerId;
		if (form.principal.trim() !== initial.principal) u.principal = principal;
		if (form.annualRate.trim() !== initial.annualRate) u.annualRate = rate;
		if (form.tenureMonths.trim() !== initial.tenureMonths) u.tenureMonths = months;
		if (form.firstEmiDate !== initial.firstEmiDate) u.firstEmiDate = form.firstEmiDate;
		if (form.installmentsPaid.trim() !== initial.installmentsPaid) u.installmentsPaid = Number(form.installmentsPaid) || 0;
		// Clearing a bank figure sends null, so the server works it out again.
		if (form.bankEmi.trim() !== initial.bankEmi) u.emiAmount = bankEmi || null;
		if (form.bankOutstanding.trim() !== initial.bankOutstanding) u.outstandingAmount = bankOutstanding || null;
		return u;
	}

	async function remove() {
		if (!loan) return;
		setSaving(true);
		try {
			await commitmentApi.deleteLoan(loan.id);
			toast.success(`${loan.name} deleted`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			if (loan) {
				const update = changes();
				if (Object.keys(update).length === 0) {
					onClose();
					return;
				}
				const saved = await commitmentApi.updateLoan(loan.id, update);
				toast.success(termsChanged ? `${saved.name} updated · EMI ${formatMoney(saved.emi, currency)} · ${formatMoney(saved.outstanding, currency)} outstanding` : `${saved.name} updated`);
				onSaved();
				return;
			}
			await commitmentApi.createLoan({
				name: form.name.trim(),
				lender: form.lender.trim() || undefined,
				loanType: form.loanType,
				principal,
				annualRate: rate,
				rateType: form.rateType,
				tenureMonths: months,
				firstEmiDate: form.firstEmiDate,
				loanAccountNumber: form.loanAccountNumber.trim() || undefined,
				installmentsPaid: Number(form.installmentsPaid) || 0,
				emiAmount: bankEmi || undefined,
				outstandingAmount: bankOutstanding || undefined,
				debitAccountId: form.debitAccountId || undefined,
				autoDebit: form.autoDebit,
				borrowerId: isAdmin ? form.borrowerId : undefined,
			});
			toast.success(`${form.name} added with ${formatMoney(preview.emi, currency)} EMIs`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	const interestShare = preview.total > 0 ? (preview.interest / preview.total) * 100 : 0;
	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-2xl">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{loan ? `Edit ${loan.name}` : "Add a loan"}</DialogTitle>
						<DialogDescription>
							{loan
								? "Fix any detail, or correct the terms to match your bank's loan statement. For a new rate from the bank, use Rate changed instead."
								: "Already paying it? Enter how many EMIs are done and we'll start from where you are."}
						</DialogDescription>
					</DialogHeader>
					<div className="grid gap-5 md:grid-cols-[1fr_14rem]">
						<div className="grid gap-3 sm:grid-cols-2">
							<TextField id="loan-name" label="Name" placeholder="e.g. Home loan" value={form.name} maxLength={80} onChange={(e) => set("name")(e.target.value)} />
							<TextField id="loan-lender" label="Lender" placeholder="e.g. SBI" value={form.lender} maxLength={80} onChange={(e) => set("lender")(e.target.value)} />
							<TextField
								id="loan-number"
								label="Loan account number (optional)"
								value={form.loanAccountNumber}
								maxLength={30}
								autoComplete="off"
								onChange={(e) => set("loanAccountNumber")(e.target.value)}
								hint="Members see only the last 4 digits."
							/>
							<div className="grid gap-1.5">
								<Label htmlFor="loan-type">Type</Label>
								<Select value={form.loanType} onValueChange={set("loanType")}>
									<SelectTrigger id="loan-type" className="w-full">
										<SelectValue />
									</SelectTrigger>
									<SelectContent>
										{LOAN_TYPES.map((t) => (
											<SelectItem key={t} value={t}>
												{t}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
							<TextField id="loan-principal" label="Loan amount" inputMode="decimal" value={form.principal} onChange={(e) => set("principal")(e.target.value)} />
							<TextField id="loan-rate" label="Interest rate (% a year)" inputMode="decimal" value={form.annualRate} onChange={(e) => set("annualRate")(e.target.value)} />
							<div className="grid gap-1.5">
								<Label htmlFor="loan-rate-type">Interest</Label>
								<Select value={form.rateType} onValueChange={set("rateType")}>
									<SelectTrigger id="loan-rate-type" className="w-full">
										<SelectValue />
									</SelectTrigger>
									<SelectContent>
										{RATE_TYPES.map((t) => (
											<SelectItem key={t} value={t}>
												{t}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
							<TextField id="loan-tenure" label="Tenure (months)" inputMode="numeric" value={form.tenureMonths} onChange={(e) => set("tenureMonths")(e.target.value.replace(/\D/g, ""))} />
							<TextField id="loan-first" label="First EMI date" type="date" value={form.firstEmiDate} onChange={(e) => set("firstEmiDate")(e.target.value)} />
							<TextField id="loan-paid" label={loan ? "EMIs paid so far (as per bank)" : "EMIs already paid"} inputMode="numeric" value={form.installmentsPaid} onChange={(e) => set("installmentsPaid")(e.target.value.replace(/\D/g, ""))} />
							<TextField
								id="loan-bank-emi"
								label="EMI as per bank (optional)"
								inputMode="decimal"
								value={form.bankEmi}
								onChange={(e) => set("bankEmi")(e.target.value.replace(/[^0-9.,]/g, ""))}
								hint="Leave blank to calculate it."
							/>
							<TextField
								id="loan-bank-outstanding"
								label="Outstanding as per bank (optional)"
								inputMode="decimal"
								value={form.bankOutstanding}
								onChange={(e) => set("bankOutstanding")(e.target.value.replace(/[^0-9.,]/g, ""))}
								hint="From your loan statement."
							/>
							<div className="grid gap-1.5 sm:col-span-2">
								<Label htmlFor="loan-debit">EMI paid from</Label>
								<Select value={form.debitAccountId} onValueChange={set("debitAccountId")}>
									<SelectTrigger id="loan-debit" className="w-full">
										<SelectValue placeholder="Choose an account" />
									</SelectTrigger>
									<SelectContent>
										{accounts.map((a) => (
											<SelectItem key={a.id} value={a.id}>
												{a.name}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
							{isAdmin && members.length > 1 && (
								<div className="grid gap-1.5 sm:col-span-2">
									<Label htmlFor="loan-borrower">Borrower</Label>
									<Select value={form.borrowerId} onValueChange={set("borrowerId")}>
										<SelectTrigger id="loan-borrower" className="w-full">
											<SelectValue />
										</SelectTrigger>
										<SelectContent>
											{members.map((m) => (
												<SelectItem key={m.id} value={m.id}>
													{m.firstName} {m.lastName}
												</SelectItem>
											))}
										</SelectContent>
									</Select>
								</div>
							)}
							<label className="flex items-start gap-2.5 text-sm sm:col-span-2">
								<Checkbox checked={form.autoDebit} onCheckedChange={(v) => set("autoDebit")(v === true)} className="mt-0.5" />
								<span>
									Auto-debit
									<span className="block text-xs text-slate-500 dark:text-slate-400">Records each EMI automatically on its due date.</span>
								</span>
							</label>
						</div>
						<div className="rounded-2xl bg-gradient-to-br from-slate-900 to-brand-900 p-5 text-white">
							<p className="flex items-center gap-1.5 text-xs text-brand-100/80">
								<CalendarRange className="size-3.5" aria-hidden="true" />
								Your EMI
							</p>
							<p className="mt-1 text-3xl font-semibold tabular-nums">
								<AnimatedMoney value={preview.emi} currency={currency} />
							</p>
							{emiMismatch && (
								<p className="mt-2 text-xs text-orange-200">
									Calculated EMI is {formatMoney(preview.calculated, currency)}. The bank&apos;s loan amount, tenure or an earlier rate may differ - we&apos;ll use the
									bank&apos;s EMI.
								</p>
							)}
							<div className="mt-4 flex h-2 gap-0.5 overflow-hidden rounded-full bg-white/15" aria-hidden="true">
								<div className="rounded-l-full bg-sky-300 transition-[width] duration-500" style={{ width: `${100 - interestShare}%` }} />
								<div className="flex-1 rounded-r-full bg-orange-300" />
							</div>
							<dl className="mt-3 space-y-1.5 text-xs">
								<div className="flex justify-between">
									<dt className="text-brand-100/80">Principal</dt>
									<dd className="tabular-nums">{formatMoney(principal, currency)}</dd>
								</div>
								<div className="flex justify-between">
									<dt className="text-brand-100/80">Total interest</dt>
									<dd className="tabular-nums">{formatMoney(Math.round(preview.interest), currency)}</dd>
								</div>
								<div className="flex justify-between border-t border-white/15 pt-1.5 font-medium">
									<dt>Total you&apos;ll pay</dt>
									<dd className="tabular-nums">{formatMoney(Math.round(preview.total), currency)}</dd>
								</div>
							</dl>
						</div>
					</div>
					{termsChanged && (
						<p className="rounded-xl bg-amber-50 px-3 py-2.5 text-xs text-amber-900 dark:bg-amber-950/40 dark:text-amber-100">
							Saving re-prices the loan: the outstanding and every future EMI are worked out again. EMIs already recorded here keep their numbers
							{loan && (loan.installmentsPaidHere ?? 0) > 0 ? ", and the outstanding changes only if you enter the bank's figure." : "."}
						</p>
					)}
					<FormErrors errors={errors} />
					<DialogFooter className="sm:justify-between">
						{loan?.canDelete ? (
							confirmDelete ? (
								<div className="flex flex-wrap items-center gap-2 text-sm">
									<span className="text-slate-600 dark:text-slate-400">Delete this loan and its schedule?</span>
									<Button type="button" variant="destructive" size="sm" disabled={saving} onClick={() => void remove()}>
										Delete
									</Button>
									<Button type="button" variant="ghost" size="sm" onClick={() => setConfirmDelete(false)}>
										Keep
									</Button>
								</div>
							) : (
								<Button type="button" variant="ghost" className="text-red-700 dark:text-red-300" onClick={() => setConfirmDelete(true)}>
									<Trash2 />
									Delete loan
								</Button>
							)
						) : (
							<span />
						)}
						<div className="flex gap-2">
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={saving}>
								{saving && <Spinner />}
								{loan ? "Save changes" : "Add loan"}
							</Button>
						</div>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

