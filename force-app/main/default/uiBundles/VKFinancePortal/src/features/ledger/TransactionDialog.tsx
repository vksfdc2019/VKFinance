import { useEffect, useMemo, useState, type FormEvent } from "react";
import { ArrowDown, Info, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { SegmentedControl } from "@/components/finance/ui";
import { AccountChip } from "@/components/finance/icons";
import { familyApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Member } from "@/api/types";
import { PAYMENT_MODES, type Account, type AccountRef, type Category, type EntryInput, type PaymentMode } from "@/api/financeTypes";
import { currencySymbol, formatMoney, todayIso } from "@/lib/format";
import { useAuth } from "@/features/auth/AuthContext";
import { CategoryPicker } from "./CategoryPicker";
import { useLedger, type EntryOptions } from "./LedgerContext";

export type EntryMode = "expense" | "income" | "transfer";

const MODE_FOR_ACCOUNT: Partial<Record<Account["type"], string>> = {
	Cash: "Cash",
	"Credit Card": "Credit Card",
	"UPI Wallet": "UPI",
};

interface References {
	accounts: Account[];
	targets: AccountRef[];
	categories: Category[];
	members: Member[];
}

export function TransactionDialog({
	options,
	onClose,
	onSaved,
}: {
	options: EntryOptions;
	onClose: () => void;
	onSaved: () => void;
}) {
	const { profile, can } = useAuth();
	const { loadCategories, currency, refresh } = useLedger();
	const txn = options.txn;
	const editing = Boolean(txn);
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const lockedShape = Boolean(txn?.transferGroupId) || txn?.type === "Adjustment";

	const [mode, setMode] = useState<EntryMode>(
		txn ? (txn.transferGroupId ? "transfer" : txn.type === "Income" ? "income" : "expense") : (options.mode ?? "expense"),
	);
	const [refund, setRefund] = useState(txn?.type === "Refund");
	const [amount, setAmount] = useState(txn ? String(txn.amount) : "");
	const [date, setDate] = useState(txn?.txnDate ?? todayIso());
	const [accountId, setAccountId] = useState(txn?.accountId ?? options.accountId ?? "");
	const [toAccountId, setToAccountId] = useState(options.toAccountId ?? "");
	const [categoryId, setCategoryId] = useState(txn?.categoryId ?? "");
	const [payee, setPayee] = useState(txn && !txn.transferGroupId ? (txn.payee ?? "") : "");
	const [paymentMode, setPaymentMode] = useState<string>(txn?.paymentMode ?? "");
	const [modeTouched, setModeTouched] = useState(Boolean(txn?.paymentMode));
	const [notes, setNotes] = useState(txn?.notes ?? "");
	const [memberId, setMemberId] = useState(txn?.memberId ?? profile?.userId ?? "");
	const [refs, setRefs] = useState<References>();
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const [confirmVoid, setConfirmVoid] = useState(false);

	useEffect(() => {
		let cancelled = false;
		Promise.all([
			financeApi.accounts(),
			editing ? Promise.resolve([]) : financeApi.transferTargets(),
			loadCategories(),
			isAdmin ? familyApi.members() : Promise.resolve([]),
		])
			.then(([accounts, targets, categories, members]) => {
				if (!cancelled) setRefs({ accounts, targets, categories, members: members.filter((m) => m.status !== "Disabled") });
			})
			.catch((error: unknown) => !cancelled && setErrors(errorMessages(error)));
		return () => {
			cancelled = true;
		};
		// Reference data is loaded once per dialog.
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	const usable = useMemo(
		() =>
			(refs?.accounts ?? []).filter(
				(a) => a.canUse && a.status === "Active" && a.type !== "Loan" && (mode === "expense" || !a.isLiability),
			),
		[refs, mode],
	);
	const targets = (refs?.targets ?? []).filter((t) => t.id !== accountId);
	const selectedTarget = targets.find((t) => t.id === toAccountId);

	// Pick sensible defaults once accounts arrive, and keep the account valid when the mode changes.
	useEffect(() => {
		if (!refs || editing) return;
		if (!usable.some((a) => a.id === accountId)) setAccountId(usable[0]?.id ?? "");
	}, [refs, usable, accountId, editing]);

	useEffect(() => {
		if (modeTouched) return;
		const account = refs?.accounts.find((a) => a.id === accountId);
		if (account) setPaymentMode(MODE_FOR_ACCOUNT[account.type] ?? (mode === "transfer" ? "NEFT/IMPS" : "UPI"));
	}, [accountId, refs, modeTouched, mode]);

	function switchMode(next: EntryMode) {
		setMode(next);
		setErrors([]);
		const kind = next === "income" ? "Income" : "Expense";
		const current = refs?.categories.find((c) => c.id === categoryId);
		if (current && current.kind !== kind) setCategoryId("");
	}

	function validate(): number | null {
		const value = Number(amount.replace(/[, ]/g, ""));
		const problems: string[] = [];
		if (!Number.isFinite(value) || value <= 0) problems.push("Enter an amount more than zero.");
		if (!date) problems.push("Choose a date.");
		if (!lockedShape) {
			if (!accountId) problems.push(mode === "transfer" ? "Choose the account the money leaves." : "Choose an account.");
			if (mode === "transfer" && !toAccountId) problems.push("Choose where the money goes.");
			if (mode !== "transfer" && !categoryId) problems.push("Choose a category.");
		}
		setErrors(problems);
		return problems.length ? null : Math.round(value * 100) / 100;
	}

	async function save(addAnother: boolean) {
		const value = validate();
		if (value === null) return;
		setSaving(true);
		try {
			if (txn && lockedShape) {
				await financeApi.updateTransaction(txn.id, { amount: value, date, notes: notes || null });
			} else if (mode === "transfer") {
				await financeApi.transfer({
					fromAccountId: accountId,
					toAccountId,
					amount: value,
					date,
					notes: notes || undefined,
					paymentMode: (paymentMode || undefined) as PaymentMode | undefined,
					memberId: isAdmin ? memberId : undefined,
				});
			} else {
				const input: EntryInput = {
					type: mode === "income" ? "Income" : refund ? "Refund" : "Expense",
					amount: value,
					date,
					accountId,
					categoryId,
					payee: payee || null,
					notes: notes || null,
					paymentMode: (paymentMode || null) as EntryInput["paymentMode"],
					memberId: isAdmin ? memberId : undefined,
				};
				if (txn) await financeApi.updateTransaction(txn.id, input);
				else await financeApi.createEntry(input);
			}
			toast.success(
				txn ? "Transaction updated" : mode === "transfer" ? "Transfer recorded" : `${formatMoney(value, currency)} recorded`,
			);
			if (addAnother) {
				refresh();
				setAmount("");
				setPayee("");
				setNotes("");
				setCategoryId("");
				setErrors([]);
				document.getElementById("txn-amount")?.focus();
			} else {
				onSaved();
			}
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	async function voidIt() {
		if (!txn) return;
		setSaving(true);
		try {
			await financeApi.voidTransaction(txn.id);
			toast.success(txn.transferGroupId ? "Both sides of the transfer were voided" : "Transaction voided");
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	function onSubmit(e: FormEvent) {
		e.preventDefault();
		void save(false);
	}

	const title = txn ? "Edit transaction" : "Add transaction";
	const canVoid = Boolean(txn?.canEdit && txn.status !== "Void" && can("TRANSACTIONS:DELETE"));
	const readOnly = Boolean(txn && (!txn.canEdit || txn.isPayment));
	const symbol = currencySymbol(currency);

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="gap-0 overflow-hidden p-0 sm:max-w-lg">
				<form onSubmit={onSubmit} noValidate>
					<DialogHeader className="space-y-3 border-b bg-gradient-to-b from-slate-50 to-white px-6 pt-6 pb-4">
						<DialogTitle className="text-lg">{title}</DialogTitle>
						<DialogDescription className="sr-only">Record money in, money out, or a move between accounts.</DialogDescription>
						{!txn ? (
							<SegmentedControl
								label="Transaction type"
								value={mode}
								onChange={switchMode}
								className="w-full"
								options={[
									{ value: "expense", label: "Expense" },
									{ value: "income", label: "Income" },
									{ value: "transfer", label: "Transfer" },
								]}
							/>
						) : (
							<p className="text-sm text-slate-500">
								{txn.type}
								{txn.accountName ? ` · ${txn.accountName}` : ""}
								{txn.counterAccountName ? ` ↔ ${txn.counterAccountName}` : ""}
							</p>
						)}
					</DialogHeader>

					<fieldset disabled={readOnly || saving} className="max-h-[65vh] space-y-4 overflow-y-auto px-6 py-5">
						<div>
							<Label htmlFor="txn-amount" className="sr-only">
								Amount
							</Label>
							<div className="flex items-center gap-2 rounded-2xl bg-slate-50 px-4 py-3 ring-1 ring-slate-900/5 focus-within:ring-2 focus-within:ring-teal-600">
								<span className="text-2xl font-medium text-slate-400">{symbol}</span>
								<input
									id="txn-amount"
									autoFocus={!txn}
									inputMode="decimal"
									autoComplete="off"
									placeholder="0"
									value={amount}
									onChange={(e) => setAmount(e.target.value.replace(/[^0-9.,]/g, ""))}
									className="w-full bg-transparent text-3xl font-semibold tabular-nums text-slate-900 outline-none placeholder:text-slate-300"
									aria-label="Amount"
								/>
							</div>
						</div>

						{mode === "transfer" && !lockedShape ? (
							<div className="space-y-2">
								<AccountSelect
									id="txn-from"
									label="From"
									accounts={usable}
									value={accountId}
									onChange={setAccountId}
								/>
								<div className="flex justify-center">
									<span className="flex size-7 items-center justify-center rounded-full bg-slate-100 text-slate-500">
										<ArrowDown className="size-4" aria-hidden="true" />
									</span>
								</div>
								<AccountSelect id="txn-to" label="To" accounts={targets} value={toAccountId} onChange={setToAccountId} showOwner />
								{selectedTarget?.type === "Credit Card" && (
									<p className="flex gap-2 rounded-xl bg-sky-50 p-3 text-xs text-sky-900">
										<Info className="size-4 shrink-0" aria-hidden="true" />
										This pays the card bill. It isn&apos;t counted as spending - the card purchases already were.
									</p>
								)}
							</div>
						) : (
							!lockedShape && (
								<>
									<AccountSelect id="txn-account" label="Account" accounts={usable} value={accountId} onChange={setAccountId} />
									<div className="grid gap-1.5">
										<Label htmlFor="txn-category">Category</Label>
										{refs ? (
											<CategoryPicker
												id="txn-category"
												categories={refs.categories}
												kind={mode === "income" ? "Income" : "Expense"}
												value={categoryId}
												onChange={setCategoryId}
											/>
										) : (
											<div className="h-10 animate-pulse rounded-lg bg-slate-100" />
										)}
									</div>
								</>
							)
						)}

						<div className="grid grid-cols-2 gap-3">
							<div className="grid gap-1.5">
								<Label htmlFor="txn-date">Date</Label>
								<Input id="txn-date" type="date" value={date} max="2100-12-31" onChange={(e) => setDate(e.target.value)} />
							</div>
							{!lockedShape && (
								<div className="grid gap-1.5">
									<Label htmlFor="txn-mode">Paid by</Label>
									<Select
										value={paymentMode}
										onValueChange={(v) => {
											setPaymentMode(v);
											setModeTouched(true);
										}}
									>
										<SelectTrigger id="txn-mode" className="w-full">
											<SelectValue placeholder="Payment mode" />
										</SelectTrigger>
										<SelectContent>
											{PAYMENT_MODES.map((m) => (
												<SelectItem key={m} value={m}>
													{m}
												</SelectItem>
											))}
										</SelectContent>
									</Select>
								</div>
							)}
						</div>

						{mode !== "transfer" && !lockedShape && (
							<div className="grid gap-1.5">
								<Label htmlFor="txn-payee">{mode === "income" ? "Received from" : "Paid to"}</Label>
								<Input
									id="txn-payee"
									value={payee}
									maxLength={120}
									placeholder={mode === "income" ? "e.g. Employer" : "e.g. DMart, Apollo Pharmacy"}
									onChange={(e) => setPayee(e.target.value)}
								/>
							</div>
						)}

						<div className="grid gap-1.5">
							<Label htmlFor="txn-notes">Notes</Label>
							<Input id="txn-notes" value={notes} maxLength={255} placeholder="Optional" onChange={(e) => setNotes(e.target.value)} />
						</div>

						{isAdmin && !lockedShape && refs && refs.members.length > 1 && (
							<div className="grid gap-1.5">
								<Label htmlFor="txn-member">For</Label>
								<Select value={memberId} onValueChange={setMemberId}>
									<SelectTrigger id="txn-member" className="w-full">
										<SelectValue />
									</SelectTrigger>
									<SelectContent>
										{refs.members.map((m) => (
											<SelectItem key={m.id} value={m.id}>
												{m.firstName} {m.lastName}
												{m.isSelf ? " (you)" : ""}
											</SelectItem>
										))}
									</SelectContent>
								</Select>
							</div>
						)}

						{mode === "expense" && !lockedShape && (
							<label className="flex items-center gap-2.5 text-sm text-slate-700">
								<Checkbox checked={refund} onCheckedChange={(v) => setRefund(v === true)} />
								This is a refund or cashback (reduces spending in the category)
							</label>
						)}

						{readOnly && (
							<p className="rounded-xl bg-amber-50 p-3 text-xs text-amber-900">
								{txn?.status === "Void"
									? "This transaction is void."
									: txn?.isPayment
										? "This is a bill or EMI payment. Void it here if it was a mistake, then pay again from Bills or Loans."
										: "You can view this transaction but not change it."}
							</p>
						)}
						<FormErrors errors={errors} />
					</fieldset>

					<DialogFooter className="flex-row items-center gap-2 border-t bg-slate-50/60 px-6 py-4 sm:justify-between">
						<div>
							{canVoid &&
								(confirmVoid ? (
									<Button type="button" variant="destructive" disabled={saving} onClick={() => void voidIt()}>
										Confirm void
									</Button>
								) : (
									<Button type="button" variant="ghost" className="text-red-700" onClick={() => setConfirmVoid(true)}>
										<Trash2 />
										Void
									</Button>
								))}
						</div>
						<div className="flex gap-2">
							<Button type="button" variant="outline" onClick={onClose}>
								{readOnly ? "Close" : "Cancel"}
							</Button>
							{!txn && mode !== "transfer" && (
								<Button type="button" variant="outline" className="hidden sm:inline-flex" disabled={saving} onClick={() => void save(true)}>
									Save &amp; add another
								</Button>
							)}
							{!readOnly && (
								<Button type="submit" disabled={saving || !refs}>
									{saving && <Spinner />}
									{txn ? "Save changes" : "Save"}
								</Button>
							)}
						</div>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

function AccountSelect({
	id,
	label,
	accounts,
	value,
	onChange,
	showOwner,
}: {
	id: string;
	label: string;
	accounts: (Account | AccountRef)[];
	value: string;
	onChange: (id: string) => void;
	showOwner?: boolean;
}) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={id}>{label}</Label>
			<Select value={value} onValueChange={onChange}>
				<SelectTrigger id={id} className="h-11 w-full">
					<SelectValue placeholder={accounts.length ? "Choose an account" : "No accounts yet"} />
				</SelectTrigger>
				<SelectContent>
					{accounts.map((a) => (
						<SelectItem key={a.id} value={a.id}>
							<span className="flex items-center gap-2">
								<AccountChip account={a} className="size-6 rounded-md [&_svg]:size-3" />
								<span>{a.name}</span>
								<span className="text-xs text-slate-400">
									{showOwner && a.ownerName ? a.ownerName : a.type}
								</span>
							</span>
						</SelectItem>
					))}
				</SelectContent>
			</Select>
		</div>
	);
}
