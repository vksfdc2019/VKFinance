import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import { ArrowLeft } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { familyApi, financeApi, savingsApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Member } from "@/api/types";
import type { Account } from "@/api/financeTypes";
import { POLICY_STATUSES, POLICY_TYPES, PREMIUM_MODES, type Policy, type PolicyInput, type PolicyStatus, type PolicyType, type PremiumMode, type Scheme, type SchemeCode, type SchemeInput } from "@/api/savingsTypes";
import { formatMoney, todayIso } from "@/lib/format";
import { PO_TD_RATES, SCHEMES, SCHEME_BY_CODE, SCHEME_TINT, termLabel } from "@/lib/schemes";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";

const SPENDABLE = new Set(["Savings", "Current", "Cash", "UPI Wallet"]);

function num(value: string): number | null {
	const cleaned = value.replace(/[, ]/g, "");
	return cleaned === "" ? null : Number(cleaned);
}

function str(value?: number | null): string {
	return value === undefined || value === null ? "" : String(value);
}

function useBankAccounts(): Account[] {
	const [accounts, setAccounts] = useState<Account[]>([]);
	useEffect(() => {
		financeApi
			.accounts()
			.then((all) => setAccounts(all.filter((a) => SPENDABLE.has(a.type) && a.canUse !== false)))
			.catch(() => setAccounts([]));
	}, []);
	return accounts;
}

function useMembers(): { isAdmin: boolean; members: Member[] } {
	const { profile } = useAuth();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [members, setMembers] = useState<Member[]>([]);
	useEffect(() => {
		if (isAdmin) familyApi.members().then(setMembers).catch(() => setMembers([]));
	}, [isAdmin]);
	return { isAdmin, members };
}

function Field({ label, htmlFor, hint, children }: { label: string; htmlFor: string; hint?: ReactNode; children: ReactNode }) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={htmlFor}>{label}</Label>
			{children}
			{hint && <p className="text-xs text-muted-foreground">{hint}</p>}
		</div>
	);
}

function Choice<T extends string>({ id, value, options, onChange, placeholder }: { id: string; value: T | ""; options: readonly { value: T; label: string }[]; onChange: (v: T) => void; placeholder?: string }) {
	return (
		<Select value={value} onValueChange={(v) => onChange(v as T)}>
			<SelectTrigger id={id} className="w-full">
				<SelectValue placeholder={placeholder} />
			</SelectTrigger>
			<SelectContent>
				{options.map((o) => (
					<SelectItem key={o.value} value={o.value}>
						{o.label}
					</SelectItem>
				))}
			</SelectContent>
		</Select>
	);
}

function OwnerField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
	const { isAdmin, members } = useMembers();
	if (!isAdmin || members.length < 2) return null;
	return (
		<Field label="Whose is it" htmlFor="owner" hint="Tax limits like 80C apply to each person separately.">
			<Choice id="owner" value={value} options={members.map((m) => ({ value: m.id, label: `${m.firstName} ${m.lastName}`.trim() }))} onChange={onChange} />
		</Field>
	);
}

// ------------------------------------------------------------------ schemes

/** Add a scheme (pick one, then its details) or edit one. The form asks only what that scheme needs. */
export function SchemeDialog({ scheme, onClose, onSaved }: { scheme?: Scheme; onClose: () => void; onSaved: () => void }) {
	const { profile } = useAuth();
	const [code, setCode] = useState<SchemeCode | null>(scheme?.scheme ?? null);
	const info = code ? SCHEME_BY_CODE[code] : null;
	const [form, setForm] = useState(() => ({
		name: scheme?.name ?? "",
		institution: scheme?.institution ?? "",
		ownerId: scheme?.ownerId ?? profile?.userId ?? "",
		accountNumber: scheme?.accountNumber ?? "",
		beneficiary: scheme?.beneficiary ?? "",
		nominee: scheme?.nominee ?? "",
		startDate: scheme?.startDate ?? todayIso(),
		tenureMonths: str(scheme?.tenureMonths),
		maturityDate: scheme?.maturityDate ?? "",
		rate: str(scheme?.rate),
		principal: str(scheme?.principal),
		plannedContribution: str(scheme?.plannedContribution),
		balance: "",
		notes: scheme?.notes ?? "",
	}));
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const set = (key: keyof typeof form) => (value: string) => setForm((f) => ({ ...f, [key]: value }));

	function pick(next: SchemeCode) {
		const s = SCHEME_BY_CODE[next];
		setCode(next);
		setForm((f) => ({ ...f, rate: str(s.rate), tenureMonths: str(s.months), name: f.name || (next === "OTHER" ? "" : s.short) }));
	}

	async function submit(e: FormEvent) {
		e.preventDefault();
		if (!info || !code) return;
		const input: SchemeInput = {
			name: form.name.trim() || undefined,
			institution: form.institution.trim(),
			accountNumber: form.accountNumber.trim(),
			nominee: form.nominee.trim(),
			notes: form.notes.trim(),
			startDate: form.startDate,
			rate: num(form.rate),
		};
		if (info.beneficiaryLabel) input.beneficiary = form.beneficiary.trim();
		if (info.kind === "lump") input.principal = num(form.principal);
		if (info.kind !== "lump") input.plannedContribution = num(form.plannedContribution);
		if (code === "PO_TD" || code === "OTHER" || code === "SGB") input.tenureMonths = num(form.tenureMonths);
		if (info.ownMaturity && form.maturityDate) input.maturityDate = form.maturityDate;
		if (!scheme) {
			input.scheme = code;
			input.ownerId = form.ownerId || undefined;
			input.balance = info.kind === "lump" && !form.balance ? num(form.principal) : num(form.balance || "0");
		}
		setSaving(true);
		setErrors([]);
		try {
			if (scheme) await savingsApi.updateScheme(scheme.id, input);
			else await savingsApi.createScheme(input);
			toast.success(scheme ? `${info.short} updated` : `${info.short} added`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[90svh] overflow-y-auto sm:max-w-2xl">
				{!info ? (
					<>
						<DialogHeader>
							<DialogTitle>Add a savings scheme</DialogTitle>
							<DialogDescription>Government small savings, retirement and gold schemes. Pick one to see what it needs.</DialogDescription>
						</DialogHeader>
						<ul className="grid gap-2 sm:grid-cols-2">
							{SCHEMES.map((s) => (
								<li key={s.code}>
									<button
										type="button"
										onClick={() => pick(s.code)}
										className="group flex w-full items-start gap-3 rounded-xl p-3 text-left ring-1 ring-slate-900/10 dark:ring-white/10 transition hover:bg-slate-50 dark:hover:bg-slate-800/60 hover:ring-brand-500/40"
									>
										<span className={cn("flex h-10 min-w-12 items-center justify-center rounded-lg bg-gradient-to-br px-1.5 text-[11px] font-bold tracking-wide text-white shadow-sm", SCHEME_TINT[s.code])}>{s.short}</span>
										<span className="min-w-0">
											<span className="block text-sm font-semibold text-slate-900 dark:text-slate-100">{s.label}</span>
											<span className="block text-xs text-slate-500 dark:text-slate-400">{s.blurb}</span>
											{s.tax && <span className="mt-1 inline-block rounded-full bg-emerald-50 dark:bg-emerald-950/40 px-2 py-0.5 text-[10px] font-medium text-emerald-800 dark:text-emerald-200">{s.tax}</span>}
										</span>
									</button>
								</li>
							))}
						</ul>
					</>
				) : (
					<form onSubmit={submit} noValidate className="space-y-4">
						<DialogHeader>
							<DialogTitle className="flex items-center gap-2">
								{!scheme && (
									<Button type="button" variant="ghost" size="icon-sm" aria-label="Choose another scheme" onClick={() => setCode(null)}>
										<ArrowLeft />
									</Button>
								)}
								{scheme ? `Edit ${scheme.name}` : info.label}
							</DialogTitle>
							<DialogDescription>
								{info.blurb}. {info.taxNote}
							</DialogDescription>
						</DialogHeader>
						<div className="grid gap-4 sm:grid-cols-2">
							<TextField id="s-name" label="Name" placeholder={info.short} value={form.name} maxLength={80} onChange={(e) => set("name")(e.target.value)} />
							<TextField id="s-inst" label="Held at" placeholder="e.g. SBI, India Post" value={form.institution} maxLength={80} onChange={(e) => set("institution")(e.target.value)} />
							<TextField id="s-no" label="Account / certificate number" value={form.accountNumber} maxLength={40} autoComplete="off" onChange={(e) => set("accountNumber")(e.target.value)} />
							{info.beneficiaryLabel ? (
								<TextField id="s-ben" label={info.beneficiaryLabel} value={form.beneficiary} maxLength={80} onChange={(e) => set("beneficiary")(e.target.value)} />
							) : (
								<TextField id="s-nom" label="Nominee" value={form.nominee} maxLength={80} onChange={(e) => set("nominee")(e.target.value)} />
							)}
							<TextField id="s-start" label="Opened on" type="date" max={todayIso()} value={form.startDate} onChange={(e) => set("startDate")(e.target.value)} />
							{code === "PO_TD" ? (
								<Field label="Term" htmlFor="s-term">
									<Choice
										id="s-term"
										value={form.tenureMonths as "12" | "24" | "36" | "60" | ""}
										options={[12, 24, 36, 60].map((m) => ({ value: String(m) as "12", label: `${m / 12} ${m === 12 ? "year" : "years"} · ${PO_TD_RATES[m]}%` }))}
										onChange={(v) => setForm((f) => ({ ...f, tenureMonths: v, rate: str(PO_TD_RATES[Number(v)]) }))}
									/>
								</Field>
							) : info.ownMaturity ? (
								<TextField id="s-mat" label={code === "NPS" ? "Matures on (you turn 60)" : "Matures on (optional)"} type="date" value={form.maturityDate} onChange={(e) => set("maturityDate")(e.target.value)} />
							) : (
								<div className="grid gap-1.5">
									<Label>Term</Label>
									<p className="flex h-9 items-center rounded-md bg-slate-50 dark:bg-slate-800/50 px-3 text-sm text-slate-700 dark:text-slate-300">
										{code === "PPF" ? "15 full financial years (extendable by 5)" : code === "SSY" ? "Deposits 15 years · matures at 21 years" : termLabel(info.months)}
									</p>
								</div>
							)}
							<TextField id="s-rate" label="Interest rate % a year" inputMode="decimal" value={form.rate} hint={info.rate ? `Last notified: ${info.rate}%. Use the rate on your passbook.` : undefined} onChange={(e) => set("rate")(e.target.value)} />
							{info.kind === "lump" ? (
								<TextField id="s-principal" label="Amount invested" inputMode="decimal" value={form.principal} hint={info.max ? `Rs ${info.min?.toLocaleString("en-IN")} to Rs ${info.max.toLocaleString("en-IN")}` : info.min ? `From Rs ${info.min.toLocaleString("en-IN")}` : undefined} onChange={(e) => set("principal")(e.target.value)} />
							) : (
								<TextField id="s-contrib" label={info.contributionLabel ?? "Planned yearly deposit"} inputMode="decimal" value={form.plannedContribution} hint={info.max ? `Up to Rs ${info.max.toLocaleString("en-IN")} a financial year` : "Used to estimate the maturity value"} onChange={(e) => set("plannedContribution")(e.target.value)} />
							)}
							{!scheme && (
								<TextField
									id="s-balance"
									label={info.kind === "lump" ? "Value today (optional)" : "Balance today"}
									inputMode="decimal"
									value={form.balance}
									placeholder={info.kind === "lump" ? "Same as invested" : "0"}
									hint={info.kind === "market" ? "Current value from your statement" : "From the passbook - later deposits are recorded here"}
									onChange={(e) => set("balance")(e.target.value)}
								/>
							)}
							{!scheme && <OwnerField value={form.ownerId} onChange={set("ownerId")} />}
						</div>
						<TextField id="s-notes" label="Notes" value={form.notes} maxLength={255} onChange={(e) => set("notes")(e.target.value)} />
						<FormErrors errors={errors} />
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={saving}>
								{saving && <Spinner />}
								{scheme ? "Save" : `Add ${info.short}`}
							</Button>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}

export type SchemeAction = "contribute" | "interest" | "value" | "close";

const ACTION_TEXT: Record<SchemeAction, { title: string; button: string; description: string }> = {
	contribute: { title: "Add a deposit", button: "Record deposit", description: "Recorded as a transfer from your bank, so both balances stay right." },
	interest: { title: "Record interest", button: "Record interest", description: "Interest credited to the scheme, or paid out to your bank (SCSS, MIS, TD)." },
	value: { title: "Update value", button: "Update value", description: "Today's value from your statement; the change is recorded as one adjustment." },
	close: { title: "Close or mark matured", button: "Close scheme", description: "The balance moves to the account it was paid into, and the scheme stops." },
};

export function SchemeActionDialog({ scheme, action, currency, onClose, onSaved }: { scheme: Scheme; action: SchemeAction; currency: string; onClose: () => void; onSaved: () => void }) {
	const accounts = useBankAccounts();
	const [amount, setAmount] = useState(action === "value" ? String(scheme.balance) : action === "contribute" && scheme.plannedContribution && scheme.kind === "monthly" ? String(scheme.plannedContribution) : "");
	const [accountId, setAccountId] = useState("");
	const [date, setDate] = useState(todayIso());
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const text = ACTION_TEXT[action];
	const needsAccount = action === "contribute" || (action === "close" && scheme.balance > 0);

	async function submit(e: FormEvent) {
		e.preventDefault();
		const value = num(amount);
		if (action !== "close" && (value === null || Number.isNaN(value) || value < 0)) {
			setErrors(["Enter an amount."]);
			return;
		}
		if (needsAccount && !accountId) {
			setErrors([action === "contribute" ? "Choose the account the money came from." : "Choose the account the money went to."]);
			return;
		}
		setSaving(true);
		setErrors([]);
		try {
			if (action === "contribute") await savingsApi.contribute(scheme.id, { fromAccountId: accountId, amount: value!, date });
			else if (action === "interest") await savingsApi.creditInterest(scheme.id, { amount: value!, date, toAccountId: accountId || undefined });
			else if (action === "value") await savingsApi.updateValue(scheme.id, { value: value!, date });
			else await savingsApi.closeScheme(scheme.id, { toAccountId: accountId || undefined, date });
			toast.success(action === "close" ? `${scheme.name} closed` : "Saved");
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-md">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>
							{text.title} · {scheme.name}
						</DialogTitle>
						<DialogDescription>{text.description}</DialogDescription>
					</DialogHeader>
					{action === "contribute" && scheme.roomThisYear !== undefined && (
						<p className="rounded-xl bg-emerald-50 dark:bg-emerald-950/30 px-3 py-2 text-xs text-emerald-900 dark:text-emerald-100">
							Room left this financial year: <span className="font-semibold">{formatMoney(scheme.roomThisYear, currency)}</span> of Rs 1,50,000.
						</p>
					)}
					{action === "close" ? (
						<p className="rounded-xl bg-slate-50 dark:bg-slate-800/40 px-3 py-2 text-sm">
							Balance to move: <span className="font-semibold tabular-nums">{formatMoney(scheme.balance, currency)}</span>
						</p>
					) : (
						<TextField id="act-amount" label={action === "value" ? "Value today" : "Amount"} inputMode="decimal" autoFocus value={amount} onChange={(e) => setAmount(e.target.value)} />
					)}
					{(needsAccount || action === "interest") && (
						<Field label={action === "contribute" ? "Paid from" : action === "interest" ? "Paid into (leave empty if credited to the scheme)" : "Paid into"} htmlFor="act-account">
							<Choice id="act-account" value={accountId} placeholder="Choose an account" options={accounts.map((a) => ({ value: a.id, label: `${a.name} · ${formatMoney(a.balance, currency)}` }))} onChange={setAccountId} />
						</Field>
					)}
					<TextField id="act-date" label="Date" type="date" max={todayIso()} value={date} onChange={(e) => setDate(e.target.value)} />
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving} variant={action === "close" ? "destructive" : "default"}>
							{saving && <Spinner />}
							{text.button}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

// ------------------------------------------------------------------ insurance

const LIFE: PolicyType[] = ["Term", "Endowment", "Money-back", "Whole life", "ULIP", "Pension"];

export function PolicyDialog({ policy, onClose, onSaved }: { policy?: Policy; onClose: () => void; onSaved: () => void }) {
	const { profile } = useAuth();
	const accounts = useBankAccounts();
	const [form, setForm] = useState(() => ({
		insurer: policy?.insurer ?? "LIC of India",
		planName: policy?.planName ?? "",
		policyType: (policy?.policyType ?? "Endowment") as PolicyType,
		policyNumber: policy?.policyNumber ?? "",
		ownerId: policy?.ownerId ?? profile?.userId ?? "",
		insuredName: policy?.insuredName ?? "",
		sumAssured: str(policy?.sumAssured),
		premium: str(policy?.premium),
		frequency: (policy?.frequency ?? "Yearly") as PremiumMode,
		startDate: policy?.startDate ?? "",
		nextDueDate: policy?.nextDueDate ?? "",
		policyTermYears: str(policy?.policyTermYears),
		premiumTermYears: str(policy?.premiumTermYears),
		maturityValue: str(policy?.maturityValue),
		nominee: policy?.nominee ?? "",
		taxSection: policy?.taxSection ?? "",
		payFromAccountId: policy?.payFromAccountId ?? "",
		status: (policy?.status ?? "Active") as PolicyStatus,
		notes: policy?.notes ?? "",
	}));
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const set = (key: keyof typeof form) => (value: string) => setForm((f) => ({ ...f, [key]: value }));
	const life = LIFE.includes(form.policyType);
	const savingsPlan = life && form.policyType !== "Term";
	const premium = num(form.premium) ?? 0;
	const sumAssured = num(form.sumAssured) ?? 0;
	const perYear = { Yearly: 1, "Half-yearly": 2, Quarterly: 4, Monthly: 12, Single: 0 }[form.frequency];
	const overTen = life && sumAssured > 0 && premium * perYear > sumAssured * 0.1;

	async function submit(e: FormEvent) {
		e.preventDefault();
		const input: PolicyInput = {
			insurer: form.insurer.trim(),
			planName: form.planName.trim(),
			policyType: form.policyType,
			policyNumber: form.policyNumber.trim(),
			insuredName: form.insuredName.trim(),
			sumAssured: num(form.sumAssured),
			premium: num(form.premium),
			frequency: form.frequency,
			policyTermYears: num(form.policyTermYears),
			premiumTermYears: num(form.premiumTermYears),
			maturityValue: savingsPlan ? num(form.maturityValue) : null,
			nominee: form.nominee.trim(),
			taxSection: form.taxSection || "None",
			payFromAccountId: form.payFromAccountId,
			notes: form.notes.trim(),
		};
		if (form.startDate) input.startDate = form.startDate;
		if (form.nextDueDate) input.nextDueDate = form.nextDueDate;
		if (policy) input.status = form.status;
		else input.ownerId = form.ownerId || undefined;
		setSaving(true);
		setErrors([]);
		try {
			if (policy) await savingsApi.updatePolicy(policy.id, input);
			else await savingsApi.createPolicy(input);
			toast.success(policy ? "Policy updated" : form.nextDueDate && form.frequency !== "Single" ? "Policy added · premium reminders are on" : "Policy added");
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[90svh] overflow-y-auto sm:max-w-2xl">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{policy ? `Edit ${policy.insurer} policy` : "Add an insurance policy"}</DialogTitle>
						<DialogDescription>LIC and other life plans, health, vehicle or home cover. With a next due date, the premium becomes a bill with reminders.</DialogDescription>
					</DialogHeader>
					<div className="grid gap-4 sm:grid-cols-2">
						<TextField id="p-insurer" label="Insurer" value={form.insurer} maxLength={80} onChange={(e) => set("insurer")(e.target.value)} />
						<Field label="Type" htmlFor="p-type">
							<Choice
								id="p-type"
								value={form.policyType}
								options={POLICY_TYPES.map((t) => ({ value: t, label: t }))}
								onChange={(t) => setForm((f) => ({ ...f, policyType: t, taxSection: policy ? f.taxSection : LIFE.includes(t) ? "80C" : t === "Health" ? "80D" : "" }))}
							/>
						</Field>
						<TextField id="p-plan" label="Plan" placeholder={form.policyType === "Endowment" ? "e.g. Jeevan Anand" : undefined} value={form.planName} maxLength={80} onChange={(e) => set("planName")(e.target.value)} />
						<TextField id="p-no" label="Policy number" value={form.policyNumber} maxLength={40} autoComplete="off" onChange={(e) => set("policyNumber")(e.target.value)} />
						<TextField id="p-insured" label={life ? "Life assured" : "Insured"} value={form.insuredName} maxLength={80} onChange={(e) => set("insuredName")(e.target.value)} />
						<TextField id="p-nominee" label="Nominee" value={form.nominee} maxLength={80} onChange={(e) => set("nominee")(e.target.value)} />
						<TextField id="p-sa" label={life ? "Sum assured" : "Cover amount"} inputMode="decimal" value={form.sumAssured} onChange={(e) => set("sumAssured")(e.target.value)} />
						<div className="grid grid-cols-2 gap-2">
							<TextField id="p-premium" label="Premium" inputMode="decimal" value={form.premium} onChange={(e) => set("premium")(e.target.value)} />
							<Field label="Mode" htmlFor="p-mode">
								<Choice id="p-mode" value={form.frequency} options={PREMIUM_MODES.map((m) => ({ value: m, label: m }))} onChange={set("frequency") as (v: PremiumMode) => void} />
							</Field>
						</div>
						<TextField id="p-start" label="Policy start (DOC)" type="date" value={form.startDate} onChange={(e) => set("startDate")(e.target.value)} />
						{form.frequency !== "Single" && <TextField id="p-due" label="Next premium due" type="date" value={form.nextDueDate} hint={policy?.billId ? "The premium bill keeps its own schedule" : "Creates the premium bill"} disabled={!!policy?.billId} onChange={(e) => set("nextDueDate")(e.target.value)} />}
						<TextField id="p-term" label="Policy term (years)" inputMode="numeric" value={form.policyTermYears} onChange={(e) => set("policyTermYears")(e.target.value)} />
						<TextField id="p-ppt" label="Premium paying term (years)" inputMode="numeric" value={form.premiumTermYears} onChange={(e) => set("premiumTermYears")(e.target.value)} />
						{savingsPlan && <TextField id="p-mv" label="Expected maturity value" inputMode="decimal" value={form.maturityValue} hint="From your policy bond or bonus statement" onChange={(e) => set("maturityValue")(e.target.value)} />}
						<Field label="Tax section" htmlFor="p-tax">
							<Choice
								id="p-tax"
								value={form.taxSection as "80C" | "80D" | ""}
								options={[
									{ value: "80C" as const, label: "80C (life premium)" },
									{ value: "80D" as const, label: "80D (health premium)" },
								]}
								placeholder="None"
								onChange={set("taxSection")}
							/>
						</Field>
						<Field label="Pay premium from" htmlFor="p-from">
							<Choice id="p-from" value={form.payFromAccountId} placeholder="Choose an account" options={accounts.map((a) => ({ value: a.id, label: a.name }))} onChange={set("payFromAccountId")} />
						</Field>
						{policy ? (
							<Field label="Status" htmlFor="p-status" hint="Paid-up, lapsed or matured policies stop the premium bill.">
								<Choice id="p-status" value={form.status} options={POLICY_STATUSES.map((s) => ({ value: s, label: s }))} onChange={set("status") as (v: PolicyStatus) => void} />
							</Field>
						) : (
							<OwnerField value={form.ownerId} onChange={set("ownerId")} />
						)}
					</div>
					{overTen && (
						<p className="rounded-xl bg-amber-50 dark:bg-amber-950/30 px-3 py-2 text-xs text-amber-900 dark:text-amber-100">
							The yearly premium is more than 10% of the sum assured. For policies from April 2012, only 10% of the sum assured counts for 80C and the maturity amount becomes taxable.
						</p>
					)}
					<TextField id="p-notes" label="Notes" value={form.notes} maxLength={255} onChange={(e) => set("notes")(e.target.value)} />
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving}>
							{saving && <Spinner />}
							{policy ? "Save" : "Add policy"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
