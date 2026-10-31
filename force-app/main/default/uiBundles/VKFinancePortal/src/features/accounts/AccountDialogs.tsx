import { useEffect, useState, type FormEvent } from "react";
import { Check } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { ACCOUNT_ICONS, ACCOUNT_SWATCHES, DEFAULT_ACCOUNT_COLOR } from "@/components/finance/icons";
import { familyApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Member } from "@/api/types";
import { ACCOUNT_COLORS, ACCOUNT_TYPES, type Account, type AccountColor, type AccountInput, type AccountType } from "@/api/financeTypes";
import { currencySymbol, formatMoney, todayIso } from "@/lib/format";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { AccountCard } from "./AccountCard";
import { DepositFields, DepositQuoteCard, depositFormFrom, depositInput, depositKind, depositTerms, isDepositType } from "./DepositDialogs";
import { quoteDeposit, rdInstalmentsDue } from "@/lib/deposits";

const TYPE_HINTS: Record<AccountType, string> = {
	Savings: "Bank savings",
	Current: "Bank current",
	Cash: "Cash in hand",
	"UPI Wallet": "Paytm, PhonePe…",
	"Credit Card": "Card you pay later",
	"Fixed Deposit": "Bank FD, tax saver",
	"Recurring Deposit": "Monthly RD",
	Investment: "MF, stocks, PPF",
	Loan: "Home, car, personal",
};

function num(value: string): number | null {
	const cleaned = value.replace(/[, ]/g, "");
	return cleaned === "" ? null : Number(cleaned);
}

export function AccountDialog({
	account,
	currency,
	onClose,
	onSaved,
}: {
	account?: Account;
	currency: string;
	onClose: () => void;
	onSaved: (account: Account) => void;
}) {
	const { profile } = useAuth();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [type, setType] = useState<AccountType>(account?.type ?? "Savings");
	const [name, setName] = useState(account?.name ?? "");
	const [institution, setInstitution] = useState(account?.institution ?? "");
	const [last4, setLast4] = useState(account?.last4 ?? "");
	const [opening, setOpening] = useState(account?.openingBalance !== undefined ? String(account.openingBalance) : "");
	const [openingDate, setOpeningDate] = useState(account?.openingDate ?? todayIso());
	const [creditLimit, setCreditLimit] = useState((account?.independentCreditLimit ?? account?.creditLimit) ? String(account?.independentCreditLimit ?? account?.creditLimit) : "");
	const [statementDay, setStatementDay] = useState(account?.statementDay ? String(account.statementDay) : "");
	const [dueDays, setDueDays] = useState(account?.paymentDueDays ? String(account.paymentDueDays) : "20");
	const [minDue, setMinDue] = useState(account?.minDuePct !== undefined ? String(account.minDuePct) : "5");
	const [color, setColor] = useState<AccountColor | undefined>(account?.color);
	const [shared, setShared] = useState(account?.isShared ?? false);
	const [ownerId, setOwnerId] = useState<string>(account ? (account.ownerId ?? "family") : (profile?.userId ?? "family"));
	const [members, setMembers] = useState<Member[]>([]);
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const [depositForm, setDepositForm] = useState(() => depositFormFrom(account?.deposit));
	// Set once a new deposit account exists, so a retry after a terms error doesn't add it twice.
	const [created, setCreated] = useState<Account>();
	const isCard = type === "Credit Card";
	const isDeposit = isDepositType(type);
	const kind = depositKind(type);
	const liability = isCard || type === "Loan";

	useEffect(() => {
		if (isAdmin) familyApi.members().then(setMembers).catch(() => setMembers([]));
	}, [isAdmin]);

	async function submit(e: FormEvent) {
		e.preventDefault();
		const input: AccountInput = {
			name: name.trim(),
			institution: institution.trim() || null,
			color: color ?? DEFAULT_ACCOUNT_COLOR[type],
			isShared: shared,
		};
		// A deposit's balance comes from its terms; the server sets it while the account has no entries.
		if (!isDeposit) {
			input.last4 = last4.trim() || null;
			input.openingBalance = num(opening) ?? 0;
			input.openingDate = openingDate;
		}
		if (!account) input.type = type;
		else if (type !== account.type) input.type = type;
		if (isCard) {
			if (!account?.creditLimitGroupId) input.creditLimit = num(creditLimit);
			input.statementDay = num(statementDay);
			input.paymentDueDays = num(dueDays);
			input.minDuePct = num(minDue);
		}
		if (isAdmin) input.ownerId = ownerId === "family" ? null : ownerId;
		setSaving(true);
		try {
			const existing = account ?? created;
			const saved = existing ? await financeApi.updateAccount(existing.id, input) : await financeApi.createAccount(input);
			if (isDeposit) {
				if (!account) setCreated(saved);
				await financeApi.saveDeposit(saved.id, depositInput(depositForm, kind, account?.deposit));
			}
			toast.success(account ? "Account updated" : `${saved.name} added`);
			onSaved(saved);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	const quote = isDeposit ? quoteDeposit(depositTerms(depositForm, kind)) : null;
	const terms = depositTerms(depositForm, kind);
	const depositBalance = kind === "RD" ? terms.instalment * (terms.startDate ? rdInstalmentsDue(terms.startDate, terms.months, todayIso()) : 0) : terms.principal;
	const previewBalance = isDeposit
		? account && account.balance !== 0 ? account.balance : depositBalance
		: account ? account.balance + ((num(opening) ?? 0) - (account.openingBalance ?? 0)) : (num(opening) ?? 0);
	const previewLimit = isCard ? (account?.creditLimitGroupId ? account.creditLimit ?? null : num(creditLimit)) : null;
	const previewGroup = account?.sharedCredit ? { ...account.sharedCredit } : undefined;
	if (previewGroup && account) {
		previewGroup.outstanding += Math.max(0, previewBalance) - Math.max(0, account.balance);
		previewGroup.available = Math.max(0, previewGroup.creditLimit - previewGroup.outstanding);
		previewGroup.overLimit = Math.max(0, previewGroup.outstanding - previewGroup.creditLimit);
		previewGroup.utilisationPct = previewGroup.outstanding / previewGroup.creditLimit * 100;
	}
	const preview = {
		name,
		type,
		institution,
		last4,
		color: color ?? DEFAULT_ACCOUNT_COLOR[type],
		balance: previewBalance,
		isLiability: liability,
		isShared: shared,
		status: "Active" as const,
		creditLimit: previewLimit ?? undefined,
		creditLimitGroupId: account?.creditLimitGroupId,
		sharedCredit: previewGroup,
		sharedCreditRestricted: account?.sharedCreditRestricted,
		deposit: quote
			? {
					kind,
					rate: terms.rate,
					maturityDate: quote.maturityDate,
					maturityAmount: depositForm.bankMaturity.trim() ? num(depositForm.bankMaturity) ?? quote.maturityAmount : quote.maturityAmount,
					depositNumberMasked: depositForm.depositNumber.trim() ? `•••• ${depositForm.depositNumber.trim().slice(-4)}` : undefined,
					instalment: terms.instalment,
					tenureMonths: terms.months,
					status: "Active" as const,
					taxSaver: kind === "FD" && depositForm.taxSaver,
				}
			: undefined,
		card:
			previewLimit && previewLimit > 0
				? { ...account?.card, available: previewGroup?.available ?? previewLimit - previewBalance, utilisationPct: previewGroup?.utilisationPct ?? (previewBalance / previewLimit) * 100 }
				: undefined,
	};

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-2xl">
				<form onSubmit={submit} noValidate className="space-y-5">
					<DialogHeader>
						<DialogTitle>{account ? `Edit ${account.name}` : "Add an account"}</DialogTitle>
						<DialogDescription>
							{isDeposit
								? "Enter the terms from your deposit receipt - we work out the maturity amount and remind you before it matures."
								: "Never enter full account or card numbers - the last 4 digits are enough to recognise it."}
						</DialogDescription>
					</DialogHeader>

					<div className="grid gap-5 md:grid-cols-[1fr_15rem]">
						<div className="space-y-4">
							{(!account || account.type !== "Credit Card") && (
								<fieldset>
									<legend className="mb-2 text-sm font-medium">Type</legend>
									<div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
										{ACCOUNT_TYPES.filter((t) => !account || t !== "Credit Card").map((t) => {
											const Icon = ACCOUNT_ICONS[t];
											return (
												<button
													key={t}
													type="button"
													aria-pressed={type === t}
													onClick={() => setType(t)}
													className={cn(
														"flex flex-col items-start gap-1 rounded-xl p-2.5 text-left ring-1 transition-colors",
														type === t ? "bg-brand-50 dark:bg-brand-950/40 ring-2 ring-brand-600" : "ring-slate-200 dark:ring-slate-800 hover:bg-slate-50 dark:hover:bg-slate-800/60",
													)}
												>
													<Icon className="size-4 text-brand-700 dark:text-brand-300" aria-hidden="true" />
													<span className="text-xs font-semibold text-slate-900 dark:text-slate-100">{t}</span>
													<span className="text-[10px] leading-tight text-slate-500 dark:text-slate-400">{TYPE_HINTS[t]}</span>
												</button>
											);
										})}
									</div>
								</fieldset>
							)}

							<div className="grid gap-3 sm:grid-cols-2">
								<TextField id="acct-name" label="Name" value={name} maxLength={80} placeholder="e.g. HDFC Salary" onChange={(e) => setName(e.target.value)} />
								<TextField id="acct-bank" label={isCard ? "Card issuer" : "Bank or provider"} value={institution} maxLength={80} onChange={(e) => setInstitution(e.target.value)} />
								{!isDeposit && (
								<TextField
									id="acct-last4"
									label="Last 4 digits"
									value={last4}
									inputMode="numeric"
									maxLength={4}
									placeholder="1234"
									onChange={(e) => setLast4(e.target.value.replace(/\D/g, ""))}
								/>
								)}
								{!isDeposit && (
								<div className="grid gap-1.5">
									<Label htmlFor="acct-opening">{isCard ? "Total outstanding on opening date" : liability ? "Amount owed on opening date" : "Balance on opening date"}</Label>
									<div className="relative">
										<span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-sm text-slate-400">{currencySymbol(currency)}</span>
										<Input id="acct-opening" inputMode="decimal" className="pl-7" value={opening} placeholder="0" onChange={(e) => setOpening(e.target.value)} />
									</div>
								</div>
								)}
								{!isDeposit && <TextField id="acct-opening-date" label="Opening date" type="date" value={openingDate} onChange={(e) => setOpeningDate(e.target.value)} />}
							</div>

							{isDeposit && <DepositFields kind={kind} form={depositForm} onChange={setDepositForm} currency={currency} accountId={account?.id ?? created?.id} />}

							{isCard && (
								<div className="grid gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 sm:grid-cols-2">
									{account?.creditLimitGroupId ? (
										<div className="rounded-lg border border-brand-200 bg-brand-50 p-3 text-xs text-brand-900 dark:border-brand-800 dark:bg-brand-950/40 dark:text-brand-100">
											<p className="font-semibold">{account.sharedCredit?.name ?? "Shared credit limit"}</p>
											<p className="mt-1">Manage this facility from Shared credit limits on the Accounts page.</p>
										</div>
									) : <TextField id="acct-limit" label="Credit limit" inputMode="decimal" value={creditLimit} onChange={(e) => setCreditLimit(e.target.value)} />}
									<TextField
										id="acct-statement"
										label="Statement day"
										inputMode="numeric"
										placeholder="1-31"
										value={statementDay}
										hint="The day each month your bill is generated."
										onChange={(e) => setStatementDay(e.target.value.replace(/\D/g, ""))}
									/>
									<TextField id="acct-due" label="Days to pay after statement" inputMode="numeric" value={dueDays} onChange={(e) => setDueDays(e.target.value.replace(/\D/g, ""))} />
									<TextField id="acct-min" label="Minimum due %" inputMode="decimal" value={minDue} onChange={(e) => setMinDue(e.target.value)} />
								</div>
							)}

							<fieldset>
								<legend className="mb-2 text-sm font-medium">Colour</legend>
								<div className="flex flex-wrap gap-2">
									{ACCOUNT_COLORS.map((c) => (
										<button
											key={c}
											type="button"
											aria-label={c}
											aria-pressed={(color ?? DEFAULT_ACCOUNT_COLOR[type]) === c}
											onClick={() => setColor(c)}
											className={cn(
												"flex size-7 items-center justify-center rounded-full ring-offset-2 transition",
												ACCOUNT_SWATCHES[c],
												(color ?? DEFAULT_ACCOUNT_COLOR[type]) === c && "ring-2 ring-slate-900",
											)}
										>
											{(color ?? DEFAULT_ACCOUNT_COLOR[type]) === c && <Check className="size-3.5 text-white" aria-hidden="true" />}
										</button>
									))}
								</div>
							</fieldset>

							<div className="grid gap-3 sm:grid-cols-2">
								{isAdmin && (
									<div className="grid gap-1.5">
										<Label htmlFor="acct-owner">Belongs to</Label>
										<Select value={ownerId} onValueChange={setOwnerId}>
											<SelectTrigger id="acct-owner" className="w-full">
												<SelectValue />
											</SelectTrigger>
											<SelectContent>
												<SelectItem value="family">The family (no single owner)</SelectItem>
												{members.map((m) => (
													<SelectItem key={m.id} value={m.id}>
														{m.firstName} {m.lastName}
													</SelectItem>
												))}
											</SelectContent>
										</Select>
									</div>
								)}
								<label className="flex items-start gap-2.5 self-end pb-2 text-sm text-slate-700 dark:text-slate-300">
									<Checkbox checked={shared} onCheckedChange={(v) => setShared(v === true)} className="mt-0.5" />
									<span>
										Shared with the family
										<span className="block text-xs text-slate-500 dark:text-slate-400">Members can see it and record spending on it.</span>
									</span>
								</label>
							</div>
						</div>

						<div className="hidden md:block">
							<p className="mb-2 text-xs font-medium text-slate-500 dark:text-slate-400">Preview</p>
							<AccountCard account={preview} currency={currency} />
							{isDeposit && <DepositQuoteCard kind={kind} form={depositForm} currency={currency} />}
						</div>
					</div>

					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving}>
							{saving && <Spinner />}
							{account ? "Save changes" : "Add account"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

export function ReconcileDialog({
	account,
	currency,
	onClose,
	onSaved,
}: {
	account: Account;
	currency: string;
	onClose: () => void;
	onSaved: () => void;
}) {
	const [actual, setActual] = useState(String(account.balance));
	const [note, setNote] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const value = num(actual);
	const diff = value === null || Number.isNaN(value) ? 0 : value - account.balance;

	async function submit(e: FormEvent) {
		e.preventDefault();
		if (value === null || Number.isNaN(value)) {
			setErrors(["Enter the balance your bank or card shows."]);
			return;
		}
		setSaving(true);
		try {
			await financeApi.reconcile(account.id, value, note || undefined);
			toast.success(diff === 0 ? "Already in balance" : "Balance adjusted");
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
						<DialogTitle>Match {account.name} to your statement</DialogTitle>
						<DialogDescription>
							We&apos;ll add one adjustment entry for the difference, so the history still explains the balance.
						</DialogDescription>
					</DialogHeader>
					<div className="grid grid-cols-2 gap-3 rounded-xl bg-slate-50 dark:bg-slate-800/40 p-3 text-sm">
						<div>
							<p className="text-xs text-slate-500 dark:text-slate-400">VK Finance shows</p>
							<p className="font-semibold tabular-nums">{formatMoney(account.balance, currency)}</p>
						</div>
						<div>
							<p className="text-xs text-slate-500 dark:text-slate-400">Difference</p>
							<p className="font-semibold tabular-nums">{formatMoney(diff, currency, { signed: true })}</p>
						</div>
					</div>
					<TextField
						id="rec-actual"
						label={account.isLiability ? "Amount owed per statement" : "Balance per bank"}
						inputMode="decimal"
						autoFocus
						value={actual}
						onChange={(e) => setActual(e.target.value)}
					/>
					<TextField id="rec-note" label="Note" value={note} maxLength={255} placeholder="e.g. Interest credited" onChange={(e) => setNote(e.target.value)} />
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving}>
							{saving && <Spinner />}
							{diff === 0 ? "Confirm" : "Adjust balance"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
