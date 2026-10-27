import { useEffect, useState, type FormEvent } from "react";
import { AlertTriangle, CalendarClock, CheckCircle2, Clock, OctagonAlert } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Spinner } from "@/components/ui/spinner";
import { FormErrors } from "@/components/forms";
import { SuccessCheck } from "@/components/finance/motion";
import { financeApi, commitmentApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account } from "@/api/financeTypes";
import type { BillInstance, DueStatus, Loan } from "@/api/commitmentTypes";
import { currencySymbol, formatDate, formatMoney, todayIso } from "@/lib/format";
import { cn } from "@/lib/utils";

export function dueText(daysLeft: number): string {
	if (daysLeft < 0) return `${-daysLeft} day${daysLeft === -1 ? "" : "s"} late`;
	if (daysLeft === 0) return "Due today";
	if (daysLeft === 1) return "Tomorrow";
	return `In ${daysLeft} days`;
}

/** Status with an icon and words - colour is never the only signal. */
export function DueBadge({ status, daysLeft }: { status: DueStatus; daysLeft?: number }) {
	const late = status === "Overdue";
	const soon = status === "Due" || status === "Partially Paid" || status === "Unpaid";
	const done = status === "Paid" || status === "Skipped";
	const Icon = late ? OctagonAlert : soon ? AlertTriangle : done ? CheckCircle2 : Clock;
	return (
		<Badge
			variant="outline"
			className={cn(
				"gap-1 border-0 font-medium",
				late && "bg-red-50 text-red-700",
				soon && "bg-amber-50 text-amber-800",
				done && "bg-emerald-50 text-emerald-800",
				!late && !soon && !done && "bg-slate-100 text-slate-600",
			)}
		>
			<Icon className="size-3" aria-hidden="true" />
			{status === "Partially Paid" ? "Part paid" : late || daysLeft === undefined || done ? status : dueText(daysLeft)}
		</Badge>
	);
}

function usePayingAccounts(includeCards: boolean) {
	const [accounts, setAccounts] = useState<Account[]>();
	useEffect(() => {
		financeApi
			.accounts()
			.then((all) => setAccounts(all.filter((a) => a.canUse && a.type !== "Loan" && (includeCards || !a.isLiability))))
			.catch(() => setAccounts([]));
	}, [includeCards]);
	return accounts;
}

function AccountPicker({ id, accounts, value, onChange }: { id: string; accounts?: Account[]; value: string; onChange: (v: string) => void }) {
	return (
		<Select value={value} onValueChange={onChange}>
			<SelectTrigger id={id} className="w-full">
				<SelectValue placeholder={accounts ? "Choose an account" : "Loading…"} />
			</SelectTrigger>
			<SelectContent>
				{accounts?.map((a) => (
					<SelectItem key={a.id} value={a.id}>
						{a.name} <span className="text-xs text-slate-400">{a.type}</span>
					</SelectItem>
				))}
			</SelectContent>
		</Select>
	);
}

export function PayBillDialog({
	instance,
	currency,
	onClose,
	onPaid,
}: {
	instance: Pick<BillInstance, "id" | "billName" | "dueDate" | "amountDue" | "amountPaid" | "payFromAccountId">;
	currency: string;
	onClose: () => void;
	onPaid: () => void;
}) {
	const remaining = (instance.amountDue ?? 0) - (instance.amountPaid ?? 0);
	const accounts = usePayingAccounts(true);
	const [amount, setAmount] = useState(remaining > 0 ? String(remaining) : "");
	const [accountId, setAccountId] = useState(instance.payFromAccountId ?? "");
	const [date, setDate] = useState(todayIso());
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const [done, setDone] = useState(false);

	useEffect(() => {
		if (!accountId && accounts?.length) setAccountId(accounts[0].id);
	}, [accounts, accountId]);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			await commitmentApi.payBill(instance.id, { amount: Number(amount.replace(/,/g, "")), accountId, date });
			setDone(true);
			setTimeout(onPaid, 1100);
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="sm:max-w-md">
				{done ? (
					<SuccessCheck title={`${instance.billName} paid`} detail={`${formatMoney(Number(amount), currency)} recorded as a bill payment`} />
				) : (
					<form onSubmit={submit} noValidate className="space-y-4">
						<DialogHeader>
							<DialogTitle>Pay {instance.billName}</DialogTitle>
							<DialogDescription>Due {formatDate(instance.dueDate)}. The payment is recorded as spending in this bill&apos;s category.</DialogDescription>
						</DialogHeader>
						<div className="flex items-center gap-2 rounded-2xl bg-slate-50 px-4 py-3 ring-1 ring-slate-900/5 focus-within:ring-2 focus-within:ring-teal-600">
							<span className="text-2xl text-slate-400">{currencySymbol(currency)}</span>
							<input
								aria-label="Amount paid"
								inputMode="decimal"
								autoFocus
								value={amount}
								onChange={(e) => setAmount(e.target.value.replace(/[^0-9.,]/g, ""))}
								className="w-full bg-transparent text-3xl font-semibold tabular-nums outline-none"
							/>
						</div>
						<div className="grid grid-cols-2 gap-3">
							<div className="grid gap-1.5">
								<Label htmlFor="pay-account">From</Label>
								<AccountPicker id="pay-account" accounts={accounts} value={accountId} onChange={setAccountId} />
							</div>
							<div className="grid gap-1.5">
								<Label htmlFor="pay-date">Paid on</Label>
								<Input id="pay-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
							</div>
						</div>
						<FormErrors errors={errors} />
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={saving || !accountId}>
								{saving && <Spinner />}
								Pay {amount ? formatMoney(Number(amount.replace(/,/g, "")) || 0, currency) : ""}
							</Button>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}

export function PayEmiDialog({ loan, currency, onClose, onPaid }: { loan: Loan; currency: string; onClose: () => void; onPaid: () => void }) {
	const accounts = usePayingAccounts(false);
	const [accountId, setAccountId] = useState(loan.debitAccountId ?? "");
	const [date, setDate] = useState(todayIso());
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);
	const [done, setDone] = useState(false);
	const next = loan.next;

	useEffect(() => {
		if (!accountId && accounts?.length) setAccountId(accounts[0].id);
	}, [accounts, accountId]);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			await commitmentApi.payEmi(loan.id, { accountId, date });
			setDone(true);
			setTimeout(onPaid, 1100);
		} catch (error) {
			setErrors(errorMessages(error));
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && !saving && onClose()}>
			<DialogContent className="sm:max-w-md">
				{done ? (
					<SuccessCheck title={`EMI ${next?.no ?? ""} paid`} detail={`${loan.name} · ${formatMoney(next?.emi ?? loan.emi, currency)}`} />
				) : (
					<form onSubmit={submit} noValidate className="space-y-4">
						<DialogHeader>
							<DialogTitle>Pay EMI {next?.no} · {loan.name}</DialogTitle>
							<DialogDescription className="flex items-center gap-1.5">
								<CalendarClock className="size-4" aria-hidden="true" />
								Due {formatDate(next?.dueDate)}
							</DialogDescription>
						</DialogHeader>
						{next && (
							<dl className="grid grid-cols-3 gap-2 rounded-2xl bg-slate-50 p-4 text-center ring-1 ring-slate-900/5">
								<div>
									<dt className="text-xs text-slate-500">EMI</dt>
									<dd className="text-lg font-semibold tabular-nums">{formatMoney(next.emi, currency)}</dd>
								</div>
								<div>
									<dt className="text-xs text-slate-500">Principal</dt>
									<dd className="text-lg font-semibold tabular-nums text-emerald-700">{formatMoney(next.principal, currency)}</dd>
								</div>
								<div>
									<dt className="text-xs text-slate-500">Interest</dt>
									<dd className="text-lg font-semibold tabular-nums text-orange-700">{formatMoney(next.interest, currency)}</dd>
								</div>
							</dl>
						)}
						<div className="grid grid-cols-2 gap-3">
							<div className="grid gap-1.5">
								<Label htmlFor="emi-account">From</Label>
								<AccountPicker id="emi-account" accounts={accounts} value={accountId} onChange={setAccountId} />
							</div>
							<div className="grid gap-1.5">
								<Label htmlFor="emi-date">Paid on</Label>
								<Input id="emi-date" type="date" value={date} onChange={(e) => setDate(e.target.value)} />
							</div>
						</div>
						<p className="text-xs text-slate-500">Interest is recorded as spending; the principal reduces what you owe.</p>
						<FormErrors errors={errors} />
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={saving || !accountId || !next}>
								{saving && <Spinner />}
								Pay {next ? formatMoney(next.emi, currency) : ""}
							</Button>
						</DialogFooter>
					</form>
				)}
			</DialogContent>
		</Dialog>
	);
}
