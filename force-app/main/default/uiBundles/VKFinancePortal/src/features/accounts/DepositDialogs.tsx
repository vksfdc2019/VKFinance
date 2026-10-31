import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from "react";
import { BadgeIndianRupee, CalendarCheck2, Landmark, Percent, ShieldAlert, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { Panel } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account } from "@/api/financeTypes";
import { COMPOUNDING, ON_MATURITY, PAYOUTS, type Compounding, type Deposit, type DepositInput, type DepositKind, type OnMaturity, type Payout } from "@/api/depositTypes";
import { addMonths, daysBetween, maturityDate, quoteDeposit, tenureLabel, wholeMonths, type DepositTerms } from "@/lib/deposits";
import { formatDate, formatMoney, todayIso } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";

export const DEPOSIT_TYPES = ["Fixed Deposit", "Recurring Deposit"] as const;
export const isDepositType = (type: string) => (DEPOSIT_TYPES as readonly string[]).includes(type);
export const depositKind = (type: string): DepositKind => (type === "Recurring Deposit" ? "RD" : "FD");

function num(value: string): number {
	const n = Number(value.replace(/[, ]/g, ""));
	return Number.isFinite(n) ? n : 0;
}

/** Bank, cash and wallet accounts that money can come from or go to. */
function useMoneyAccounts(excludeId?: string) {
	const [accounts, setAccounts] = useState<Account[]>([]);
	useEffect(() => {
		financeApi
			.accounts()
			.then((all) => setAccounts(all.filter((a) => a.canUse && !a.isLiability && !isDepositType(a.type) && a.id !== excludeId)))
			.catch(() => setAccounts([]));
	}, [excludeId]);
	return accounts;
}

function AccountSelect({ id, label, value, onChange, accounts, optional }: { id: string; label: string; value: string; onChange: (v: string) => void; accounts: Account[]; optional?: boolean }) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={id}>{label}</Label>
			<Select value={value || "none"} onValueChange={(v) => onChange(v === "none" ? "" : v)}>
				<SelectTrigger id={id} className="w-full">
					<SelectValue placeholder="Choose an account" />
				</SelectTrigger>
				<SelectContent>
					{optional && <SelectItem value="none">Not linked</SelectItem>}
					{accounts.map((a) => (
						<SelectItem key={a.id} value={a.id}>
							{a.name}
							{a.institution ? ` · ${a.institution}` : ""}
						</SelectItem>
					))}
				</SelectContent>
			</Select>
		</div>
	);
}

function Choice<T extends string>({ id, label, value, options, onChange }: { id: string; label: string; value: T; options: readonly T[]; onChange: (v: T) => void }) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={id}>{label}</Label>
			<Select value={value} onValueChange={(v) => onChange(v as T)}>
				<SelectTrigger id={id} className="w-full">
					<SelectValue />
				</SelectTrigger>
				<SelectContent>
					{options.map((o) => (
						<SelectItem key={o} value={o}>
							{o}
						</SelectItem>
					))}
				</SelectContent>
			</Select>
		</div>
	);
}

function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
	return (
		<label className="flex items-start gap-2.5 text-sm text-slate-700 dark:text-slate-300">
			<Checkbox checked={checked} onCheckedChange={(v) => onChange(v === true)} className="mt-0.5" />
			<span>
				{label}
				{hint && <span className="block text-xs text-slate-500 dark:text-slate-400">{hint}</span>}
			</span>
		</label>
	);
}

// ------------------------------------------------------------------ the form inside the account dialog

export interface DepositForm {
	depositNumber: string;
	principal: string;
	instalment: string;
	rate: string;
	seniorCitizen: boolean;
	compounding: Compounding;
	payout: Payout;
	startDate: string;
	months: string;
	days: string;
	bankMaturity: string;
	onMaturity: OnMaturity;
	payoutAccountId: string;
	fundingAccountId: string;
	autoPost: boolean;
	nominee: string;
	taxSaver: boolean;
	penaltyRate: string;
	form15Submitted: boolean;
}

export function depositFormFrom(d?: Deposit): DepositForm {
	return {
		depositNumber: d?.depositNumber ?? "",
		principal: d?.principal ? String(d.principal) : "",
		instalment: d?.instalment ? String(d.instalment) : "",
		rate: d?.rate ? String(d.rate) : "",
		seniorCitizen: d?.seniorCitizen ?? false,
		compounding: d?.compounding ?? "Quarterly",
		payout: d?.payout ?? "On maturity",
		startDate: d?.startDate ?? todayIso(),
		months: d ? String(d.tenureMonths) : "12",
		days: d ? String(d.tenureDays) : "0",
		bankMaturity: d?.maturityQuoted ? String(d.maturityAmount) : "",
		onMaturity: d?.onMaturity ?? "Credit to account",
		payoutAccountId: d?.payoutAccountId ?? "",
		fundingAccountId: d?.fundingAccountId ?? "",
		autoPost: true,
		nominee: d?.nominee ?? "",
		taxSaver: d?.taxSaver ?? false,
		penaltyRate: d ? String(d.penaltyRate) : "1",
		form15Submitted: d?.form15Submitted ?? false,
	};
}

export function depositTerms(form: DepositForm, kind: DepositKind): DepositTerms {
	return {
		kind,
		principal: num(form.principal),
		instalment: num(form.instalment),
		rate: num(form.rate),
		compounding: form.compounding,
		payout: kind === "RD" ? "On maturity" : form.payout,
		startDate: form.startDate,
		months: num(form.months),
		days: kind === "RD" ? 0 : num(form.days),
	};
}

export function depositInput(form: DepositForm, kind: DepositKind, existing?: Deposit): DepositInput {
	const rd = kind === "RD";
	const number = form.depositNumber.trim();
	return {
		// An unchanged masked number must not overwrite the real one.
		...(number && number === existing?.depositNumberMasked ? {} : { depositNumber: number || null }),
		principal: rd ? null : num(form.principal),
		instalment: rd ? num(form.instalment) : null,
		rate: num(form.rate),
		seniorCitizen: form.seniorCitizen,
		compounding: rd ? "Quarterly" : form.compounding,
		payout: rd ? "On maturity" : form.payout,
		startDate: form.startDate,
		tenureMonths: num(form.months),
		tenureDays: rd ? 0 : num(form.days),
		maturityAmount: form.bankMaturity.trim() ? num(form.bankMaturity) : null,
		onMaturity: rd ? "Credit to account" : form.onMaturity,
		payoutAccountId: form.payoutAccountId || null,
		fundingAccountId: rd ? form.fundingAccountId || null : null,
		autoPost: form.autoPost,
		nominee: form.nominee.trim() || null,
		taxSaver: rd ? false : form.taxSaver,
		penaltyRate: num(form.penaltyRate),
		form15Submitted: form.form15Submitted,
	};
}

function Section({ title, children }: { title: string; children: ReactNode }) {
	return (
		<fieldset className="grid gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 sm:grid-cols-2">
			<legend className="sr-only">{title}</legend>
			<p className="text-xs font-semibold tracking-wide text-slate-500 uppercase sm:col-span-2 dark:text-slate-400">{title}</p>
			{children}
		</fieldset>
	);
}

export function DepositFields({
	kind,
	form,
	onChange,
	currency,
	accountId,
}: {
	kind: DepositKind;
	form: DepositForm;
	onChange: (form: DepositForm) => void;
	currency: string;
	accountId?: string;
}) {
	const accounts = useMoneyAccounts(accountId);
	const set = <K extends keyof DepositForm>(key: K) => (value: DepositForm[K]) => onChange({ ...form, [key]: value });
	const rd = kind === "RD";
	const quote = useMemo(() => quoteDeposit(depositTerms(form, kind)), [form, kind]);
	const maturity = form.startDate ? maturityDate(form.startDate, num(form.months), rd ? 0 : num(form.days)) : "";
	const payoutFd = !rd && form.payout !== "On maturity";

	function setMaturity(iso: string) {
		if (!iso || !form.startDate || iso <= form.startDate) return;
		const months = wholeMonths(form.startDate, iso);
		onChange({ ...form, months: String(months), days: String(daysBetween(addMonths(form.startDate, months), iso)) });
	}

	return (
		<div className="space-y-3">
			<Section title={rd ? "Recurring deposit" : "Fixed deposit"}>
				<TextField
					id="dep-number"
					label={rd ? "RD account number" : "FD account / receipt number"}
					value={form.depositNumber}
					maxLength={30}
					autoComplete="off"
					onChange={(e) => set("depositNumber")(e.target.value)}
					hint="Only you and family admins see the full number."
				/>
				{rd ? (
					<TextField id="dep-instalment" label="Monthly instalment" inputMode="decimal" value={form.instalment} onChange={(e) => set("instalment")(e.target.value)} />
				) : (
					<TextField id="dep-principal" label="Amount invested" inputMode="decimal" value={form.principal} onChange={(e) => set("principal")(e.target.value)} />
				)}
				<TextField id="dep-rate" label="Rate of interest (% a year)" inputMode="decimal" value={form.rate} onChange={(e) => set("rate")(e.target.value.replace(/[^0-9.]/g, ""))} />
				<TextField id="dep-start" label="Invested on" type="date" value={form.startDate} onChange={(e) => set("startDate")(e.target.value)} />
				<div className="grid grid-cols-2 gap-2">
					<TextField id="dep-months" label="Duration: months" inputMode="numeric" value={form.months} onChange={(e) => set("months")(e.target.value.replace(/\D/g, ""))} />
					{!rd && <TextField id="dep-days" label="days" inputMode="numeric" value={form.days} onChange={(e) => set("days")(e.target.value.replace(/\D/g, ""))} />}
				</div>
				<TextField
					id="dep-maturity-date"
					label="Maturity date"
					type="date"
					value={maturity}
					onChange={(e) => setMaturity(e.target.value)}
					hint={tenureLabel(num(form.months), rd ? 0 : num(form.days))}
				/>
				{!rd && <Choice id="dep-compounding" label="Interest compounds" value={form.compounding} options={COMPOUNDING} onChange={set("compounding")} />}
				{!rd && <Choice id="dep-payout" label="Interest paid" value={form.payout} options={PAYOUTS} onChange={set("payout")} />}
				<TextField
					id="dep-bank-maturity"
					label="Maturity amount as per bank (optional)"
					inputMode="decimal"
					value={form.bankMaturity}
					onChange={(e) => set("bankMaturity")(e.target.value)}
					hint={quote ? `Calculated: ${formatMoney(quote.maturityAmount, currency)}` : "Leave blank to calculate it."}
				/>
				<div className="self-end pb-2">
					<Toggle checked={form.seniorCitizen} onChange={set("seniorCitizen")} label="Senior citizen rate" hint="Also raises the TDS threshold to ₹1,00,000." />
				</div>
			</Section>

			<Section title="Money in and out">
				{rd && (
					<>
						<AccountSelect id="dep-funding" label="Instalments paid from" value={form.fundingAccountId} onChange={set("fundingAccountId")} accounts={accounts} optional />
						<div className="self-end pb-2">
							<Toggle checked={form.autoPost} onChange={set("autoPost")} label="Record instalments automatically" hint="Like a standing instruction with your bank." />
						</div>
					</>
				)}
				<AccountSelect
					id="dep-payout-account"
					label={payoutFd ? "Interest and maturity paid into" : "Maturity amount paid into"}
					value={form.payoutAccountId}
					onChange={set("payoutAccountId")}
					accounts={accounts}
					optional
				/>
				{!rd && <Choice id="dep-on-maturity" label="On maturity" value={form.onMaturity} options={ON_MATURITY} onChange={set("onMaturity")} />}
				{payoutFd && (
					<div className="sm:col-span-2">
						<Toggle checked={form.autoPost} onChange={set("autoPost")} label="Record each interest payout automatically" hint="Half-yearly payouts are recorded at maturity." />
					</div>
				)}
			</Section>

			<Section title="Nominee, tax and safety">
				<TextField id="dep-nominee" label="Nominee" value={form.nominee} maxLength={80} onChange={(e) => set("nominee")(e.target.value)} />
				<TextField
					id="dep-penalty"
					label="Premature withdrawal penalty (%)"
					inputMode="decimal"
					value={form.penaltyRate}
					onChange={(e) => set("penaltyRate")(e.target.value.replace(/[^0-9.]/g, ""))}
					hint="Most banks cut 0.5-1% off the rate."
				/>
				{!rd && (
					<Toggle checked={form.taxSaver} onChange={set("taxSaver")} label="Tax-saver FD (section 80C)" hint="Up to ₹1,50,000, 5-year lock-in, no early withdrawal." />
				)}
				<Toggle checked={form.form15Submitted} onChange={set("form15Submitted")} label="Form 15G / 15H submitted" hint="The bank won't deduct TDS this year." />
			</Section>
		</div>
	);
}

/** The figures under the account preview while the deposit is being typed. */
export function DepositQuoteCard({ kind, form, currency }: { kind: DepositKind; form: DepositForm; currency: string }) {
	const quote = quoteDeposit(depositTerms(form, kind));
	if (!quote) return null;
	const bank = form.bankMaturity.trim() ? num(form.bankMaturity) : 0;
	const shown = bank || quote.maturityAmount;
	const differs = bank > 0 && Math.abs(bank - quote.maturityAmount) > Math.max(1, quote.maturityAmount * 0.002);
	return (
		<div className="mt-3 space-y-1.5 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 text-xs">
			<Row label="Maturity amount" value={formatMoney(shown, currency)} strong />
			<Row label="Matures on" value={formatDate(quote.maturityDate)} />
			<Row label={kind === "RD" ? "You pay in" : "Invested"} value={formatMoney(quote.invested, currency)} />
			<Row label="Interest earned" value={formatMoney(bank ? bank - quote.invested : quote.interest, currency)} />
			{quote.payoutPerPeriod !== undefined && <Row label={`Paid ${form.payout.toLowerCase()}`} value={formatMoney(quote.payoutPerPeriod, currency)} />}
			{quote.effectiveYield !== undefined && <Row label="Effective yield" value={`${quote.effectiveYield}% a year`} />}
			{differs && <p className="pt-1 text-amber-700 dark:text-amber-300">Differs from the calculated {formatMoney(quote.maturityAmount, currency)} - we&apos;ll use the bank&apos;s figure.</p>}
		</div>
	);
}

function Row({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
	return (
		<div className="flex justify-between gap-3">
			<span className="text-slate-500 dark:text-slate-400">{label}</span>
			<span className={cn("tabular-nums", strong && "font-semibold text-slate-900 dark:text-slate-100")}>{value}</span>
		</div>
	);
}

// ------------------------------------------------------------------ maturity, early closure and renewal

export function CloseDepositDialog({ account, currency, onClose, onDone }: { account: Account; currency: string; onClose: () => void; onDone: () => void }) {
	const d = account.deposit!;
	const matured = d.daysToMaturity <= 0;
	const accounts = useMoneyAccounts(account.id);
	const [date, setDate] = useState(matured ? d.maturityDate : todayIso());
	const [amount, setAmount] = useState(String(matured ? d.maturityAmount : (d.prematureValue ?? d.currentValue)));
	const [toAccountId, setToAccountId] = useState(d.payoutAccountId ?? "");
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const early = date < d.maturityDate;
	const received = num(amount);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			await financeApi.closeDeposit(account.id, { date, amountReceived: received, toAccountId });
			toast.success(`${account.name} ${early ? "closed" : "matured"} · ${formatMoney(received, currency)} moved`);
			onDone();
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="sm:max-w-md">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{matured ? `Record ${account.name} maturing` : `Close ${account.name} early`}</DialogTitle>
						<DialogDescription>
							{matured
								? `Matured on ${formatDate(d.maturityDate)}. The interest is recorded as income, then the money moves to the account you choose.`
								: `Matures ${formatDate(d.maturityDate)}. Closing now earns ${d.rate - d.penaltyRate}% instead of ${d.rate}% (a ${d.penaltyRate}% penalty) for the time it ran.`}
						</DialogDescription>
					</DialogHeader>
					<div className="grid grid-cols-2 gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 text-sm">
						<div>
							<p className="text-xs text-slate-500 dark:text-slate-400">{d.kind === "RD" ? "Paid in" : "Invested"}</p>
							<p className="font-semibold tabular-nums">{formatMoney(account.balance, currency)}</p>
						</div>
						<div>
							<p className="text-xs text-slate-500 dark:text-slate-400">Interest</p>
							<p className="font-semibold tabular-nums">{formatMoney(received - account.balance, currency, { signed: true })}</p>
						</div>
					</div>
					<TextField id="close-date" label={early ? "Closed on" : "Credited on"} type="date" value={date} onChange={(e) => setDate(e.target.value)} />
					<TextField id="close-amount" label="Amount the bank paid" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} hint="Check it against your bank statement." />
					<AccountSelect id="close-to" label="Paid into" value={toAccountId} onChange={setToAccountId} accounts={accounts} />
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving || !toAccountId || !(received > 0)}>
							{saving && <Spinner />}
							{early ? "Close deposit" : "Record maturity"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

export function RenewDepositDialog({ account, currency, onClose, onDone }: { account: Account; currency: string; onClose: () => void; onDone: () => void }) {
	const d = account.deposit!;
	const accounts = useMoneyAccounts(account.id);
	const [received, setReceived] = useState(String(d.maturityAmount));
	const [withInterest, setWithInterest] = useState(d.onMaturity !== "Renew principal");
	const [toAccountId, setToAccountId] = useState(d.payoutAccountId ?? "");
	const [rate, setRate] = useState(String(d.rate));
	const [months, setMonths] = useState(String(d.tenureMonths));
	const [days, setDays] = useState(String(d.tenureDays));
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const principal = withInterest ? num(received) : (d.principal ?? 0);
	const quote = quoteDeposit({ kind: "FD", principal, instalment: 0, rate: num(rate), compounding: d.compounding, payout: d.payout, startDate: d.maturityDate, months: num(months), days: num(days) });

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			const renewed = await financeApi.renewDeposit(account.id, {
				date: d.maturityDate,
				amountReceived: num(received),
				includeInterest: withInterest,
				toAccountId: withInterest ? undefined : toAccountId,
				rate: num(rate),
				tenureMonths: num(months),
				tenureDays: num(days),
			});
			toast.success(`${account.name} renewed to ${formatDate(renewed.maturityDate)} · ${formatMoney(renewed.maturityAmount, currency)} at maturity`);
			onDone();
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="sm:max-w-md">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>Renew {account.name}</DialogTitle>
						<DialogDescription>A new term from {formatDate(d.maturityDate)}, at the rate the bank offers on that day.</DialogDescription>
					</DialogHeader>
					<TextField id="renew-received" label="Maturity amount" inputMode="decimal" value={received} onChange={(e) => setReceived(e.target.value)} />
					<Toggle checked={withInterest} onChange={setWithInterest} label="Reinvest the interest too" hint={withInterest ? "Principal and interest roll over." : "Only the principal rolls over; the interest is paid out."} />
					{!withInterest && <AccountSelect id="renew-to" label="Interest paid into" value={toAccountId} onChange={setToAccountId} accounts={accounts} />}
					<div className="grid grid-cols-3 gap-2">
						<TextField id="renew-rate" label="New rate %" inputMode="decimal" value={rate} onChange={(e) => setRate(e.target.value.replace(/[^0-9.]/g, ""))} />
						<TextField id="renew-months" label="Months" inputMode="numeric" value={months} onChange={(e) => setMonths(e.target.value.replace(/\D/g, ""))} />
						<TextField id="renew-days" label="Days" inputMode="numeric" value={days} onChange={(e) => setDays(e.target.value.replace(/\D/g, ""))} />
					</div>
					{quote && (
						<p className="rounded-xl bg-slate-50 dark:bg-slate-800/40 px-3 py-2.5 text-sm">
							{formatMoney(principal, currency)} grows to <span className="font-semibold tabular-nums">{formatMoney(quote.maturityAmount, currency)}</span> on {formatDate(quote.maturityDate)}
						</p>
					)}
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving || (!withInterest && !toAccountId)}>
							{saving && <Spinner />}
							Renew
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

// ------------------------------------------------------------------ the portfolio panel

function Stat({ icon, label, value }: { icon: ReactNode; label: string; value: string }) {
	return (
		<div className="rounded-xl bg-slate-50 dark:bg-slate-800/40 px-4 py-3">
			<p className="flex items-center gap-1.5 text-xs text-slate-500 dark:text-slate-400">
				{icon}
				{label}
			</p>
			<p className="mt-1 text-lg font-semibold tabular-nums text-slate-900 dark:text-slate-100">{value}</p>
		</div>
	);
}

/** Totals across every FD and RD, with the TDS and deposit-insurance checks Indian depositors need. */
export function DepositsPanel({ currency, version }: { currency: string; version: number }) {
	const { data } = useAsync(() => financeApi.deposits(), [version]);
	if (!data || data.deposits.every((d) => d.status !== "Active")) return null;
	const active = data.deposits.filter((d) => d.status === "Active");
	const soon = active.filter((d) => d.daysToMaturity <= 30).sort((a, b) => a.daysToMaturity - b.daysToMaturity);
	const tdsWatch = data.tds.filter((t) => t.estimatedTds > 0 || (!t.form15Submitted && t.interest >= t.threshold * 0.8));
	const uncovered = data.cover.filter((c) => c.uncovered > 0);

	return (
		<Panel title="Deposits" description={`${active.length} active · interest figures for ${data.financialYear}`} className="mb-6">
			<div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
				<Stat icon={<Landmark className="size-3.5" aria-hidden="true" />} label="Invested" value={formatMoney(data.invested, currency)} />
				<Stat icon={<BadgeIndianRupee className="size-3.5" aria-hidden="true" />} label="Worth today" value={formatMoney(data.currentValue, currency)} />
				<Stat icon={<CalendarCheck2 className="size-3.5" aria-hidden="true" />} label="At maturity" value={formatMoney(data.maturityValue, currency)} />
				<Stat icon={<Percent className="size-3.5" aria-hidden="true" />} label={`Interest in ${data.financialYear}`} value={formatMoney(data.interestThisFy, currency)} />
			</div>

			{soon.length > 0 && (
				<div className="mt-4">
					<h3 className="mb-2 text-xs font-semibold tracking-wide text-slate-500 uppercase dark:text-slate-400">Maturing soon</h3>
					<ul className="divide-y divide-slate-100 rounded-xl ring-1 ring-slate-900/5 dark:divide-slate-800 dark:ring-white/10">
						{soon.map((d) => (
							<li key={d.id} className="flex flex-wrap items-center justify-between gap-2 px-3 py-2 text-sm">
								<span className="min-w-0 truncate">
									<span className="font-medium text-slate-900 dark:text-slate-100">{d.accountName}</span>
									<span className="text-slate-500 dark:text-slate-400"> · {d.onMaturity.toLowerCase()}</span>
								</span>
								<span className="tabular-nums">
									{formatMoney(d.maturityAmount, currency)}{" "}
									<span className={cn("text-xs", d.daysToMaturity <= 0 ? "font-semibold text-amber-700 dark:text-amber-300" : "text-slate-500 dark:text-slate-400")}>
										{d.daysToMaturity < 0 ? `matured ${formatDate(d.maturityDate)}` : d.daysToMaturity === 0 ? "matures today" : `in ${d.daysToMaturity} days`}
									</span>
								</span>
							</li>
						))}
					</ul>
				</div>
			)}

			{(tdsWatch.length > 0 || uncovered.length > 0) && (
				<div className="mt-4 grid gap-3 lg:grid-cols-2">
					{tdsWatch.map((t) => (
						<p key={`tds-${t.ownerName}-${t.institution}`} className="flex gap-2 rounded-xl bg-amber-50 px-3 py-2.5 text-xs text-amber-900 dark:bg-amber-950/40 dark:text-amber-100">
							<ShieldAlert className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
							<span>
								<span className="font-semibold">TDS · {t.ownerName} at {t.institution ?? "one bank"}:</span> {formatMoney(t.interest, currency)} interest this year against the{" "}
								{formatMoney(t.threshold, currency)} limit.{" "}
								{t.estimatedTds > 0
									? `About ${formatMoney(t.estimatedTds, currency)} (${data.tdsRate}%) will be deducted - claim it back when you file, or submit Form 15G/15H if your income is below the taxable limit.`
									: "Close to the limit - TDS starts once it is crossed."}
							</span>
						</p>
					))}
					{uncovered.map((c) => (
						<p key={`cover-${c.ownerName}-${c.institution}`} className="flex gap-2 rounded-xl bg-sky-50 px-3 py-2.5 text-xs text-sky-900 dark:bg-sky-950/40 dark:text-sky-100">
							<ShieldCheck className="mt-0.5 size-4 shrink-0" aria-hidden="true" />
							<span>
								<span className="font-semibold">Deposit insurance · {c.ownerName} at {c.institution ?? "one bank"}:</span> {formatMoney(c.amount, currency)} held; DICGC insures{" "}
								{formatMoney(data.dicgcCover, currency)} per depositor per bank, so {formatMoney(c.uncovered, currency)} is uninsured. Consider spreading it across banks.
							</span>
						</p>
					))}
				</div>
			)}
		</Panel>
	);
}
