import type { ReactNode } from "react";
import { CalendarClock, Layers3, Lock, Users } from "lucide-react";
import { ACCOUNT_GRADIENTS, ACCOUNT_ICONS, accountColor } from "@/components/finance/icons";
import { utilisationStatus } from "@/components/finance/ui";
import type { Account, CardCycle } from "@/api/financeTypes";
import type { Deposit } from "@/api/depositTypes";
import { formatDate, formatMoney, formatShortDate } from "@/lib/format";
import { cn } from "@/lib/utils";

/** The bill in words: what is left to pay and by when, or when the next statement closes. */
function billNote(card: Partial<CardCycle>, currency: string): string {
	const bill = card.bill ?? card.statement;
	const next = card.nextStatementDate ? ` · Next statement ${formatShortDate(card.nextStatementDate)}` : "";
	if (!bill || bill.amount === undefined) return "No bill recorded";
	if (bill.status === "Paid") return `${bill.amount > 0 ? "Bill paid" : "Nothing to pay"}${next}`;
	const left = formatMoney(Math.max(0, bill.amount - bill.amountPaid), currency);
	if (bill.status === "Overdue") return `Was due ${formatShortDate(bill.dueDate)} · ${left} to pay`;
	if (bill.status === "Partially Paid") return `${left} left · Due ${formatShortDate(bill.dueDate)}`;
	return `Due ${formatShortDate(bill.dueDate)}${"minimumDue" in bill ? ` · Minimum ${formatMoney(bill.minimumDue, currency)}` : ""}`;
}

/** A bank-card style tile. Text stays white on every gradient; status uses an icon and words. */
export function AccountCard({
	account,
	currency,
	menu,
	className,
}: {
	account: Pick<Account, "name" | "type" | "balance" | "isLiability" | "status"> &
		Partial<Omit<Account, "card" | "deposit">> & { card?: Partial<CardCycle>; deposit?: Partial<Deposit> };
	currency: string;
	menu?: ReactNode;
	className?: string;
}) {
	const Icon = ACCOUNT_ICONS[account.type];
	const card = account.card;
	const pct = account.sharedCreditRestricted ? undefined : account.sharedCredit?.utilisationPct ?? card?.utilisationPct;
	const bill = card?.bill ?? card?.statement;
	const available = account.creditLimitGroupId ? account.sharedCredit?.available : card?.available ?? (account.creditLimit !== undefined ? account.creditLimit - account.balance : undefined);
	const displayedLimit = account.sharedCredit?.creditLimit ?? account.creditLimit;
	const closed = account.status === "Closed";
	const deposit = account.deposit;
	const isDeposit = account.type === "Fixed Deposit" || account.type === "Recurring Deposit";

	return (
		<article
			className={cn(
				"relative flex min-h-48 flex-col overflow-hidden rounded-2xl bg-gradient-to-br p-5 text-white shadow-lg shadow-slate-900/10 transition-transform",
				ACCOUNT_GRADIENTS[accountColor({ color: account.color, type: account.type })],
				closed && "opacity-60 grayscale",
				className,
			)}
		>
			<div className="pointer-events-none absolute -top-12 -right-12 size-40 rounded-full bg-white/10" />
			<div className="pointer-events-none absolute -right-4 -bottom-16 size-40 rounded-full bg-white/5" />

			<div className="relative flex items-start justify-between gap-3">
				<div className="min-w-0">
					<p className="flex items-center gap-1.5 text-xs font-medium tracking-wide text-white/75 uppercase">
						<Icon className="size-3.5" aria-hidden="true" />
						{account.institution || account.type}
						{account.type === "Credit Card" && account.cardNetwork && <span className="text-white/60">· {account.cardNetwork}</span>}
					</p>
					<h3 className="mt-1 truncate text-lg font-semibold">{account.name || "New account"}</h3>
					{account.creditLimitGroupId && <p className="mt-2 flex items-center gap-1.5 text-[11px] text-white/85"><Layers3 className="size-3.5 shrink-0" />{account.sharedCredit?.name ?? "Shared credit limit"}</p>}
				</div>
				{menu}
			</div>

			<div className="relative mt-auto pt-4">
				<p className="text-xs text-white/70">
					{account.type === "Credit Card" ? "Total outstanding" : account.isLiability ? "Outstanding" : isDeposit ? (account.type === "Recurring Deposit" ? "Paid in so far" : "Invested") : "Balance"}
				</p>
				<p className="text-2xl font-semibold tracking-tight tabular-nums">{formatMoney(account.balance, currency)}</p>

				{account.type === "Credit Card" ? (
					<div className="mt-3">
						<div className="h-1.5 overflow-hidden rounded-full bg-white/25" aria-hidden="true">
							<div
								className="h-full rounded-full bg-white"
								style={{ width: `${Math.min(100, Math.max(0, pct ?? 0))}%` }}
							/>
						</div>
						{pct !== undefined && (
							<p className="mt-1.5 text-[11px] text-white/80">
								{pct.toFixed(0)}% {account.creditLimitGroupId ? "of shared limit used" : "used"}
								{utilisationStatus(pct) !== "good" && " · keep under 30%"}
							</p>
						)}
						<dl className="mt-3 grid grid-cols-2 gap-3">
							<div>
								<dt className="text-xs text-white/70">Available amount</dt>
								<dd className="font-semibold tabular-nums">{account.sharedCreditRestricted ? "Restricted" : available === undefined ? "—" : formatMoney(available, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Bill amount</dt>
								<dd className="font-semibold tabular-nums">{bill?.amount === undefined ? "—" : formatMoney(bill.amount, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Total credit limit</dt>
								<dd className="font-semibold tabular-nums">{account.sharedCreditRestricted ? "Restricted" : displayedLimit === undefined ? "—" : formatMoney(displayedLimit, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Bill due date</dt>
								<dd className="font-semibold">{bill?.dueDate ? formatShortDate(bill.dueDate) : "—"}</dd>
							</div>
						</dl>
						{account.sharedCredit && <p className="mt-2 text-[11px] text-white/80">One limit across {account.sharedCredit.activeCardCount} active cards · counted once</p>}
						{account.sharedCreditRestricted && <p className="mt-2 text-[11px] text-white/80">Shared totals are private because some linked cards are outside your access.</p>}
						{(account.sharedCredit?.overLimit ?? 0) > 0 && <p className="mt-2 rounded-lg bg-black/20 px-2.5 py-1.5 text-xs font-semibold">Shared limit exceeded by {formatMoney(account.sharedCredit!.overLimit, currency)}</p>}
						{card && (
							<p className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-black/15 px-2.5 py-1 text-[11px]">
								<CalendarClock className="size-3.5" aria-hidden="true" />
								{billNote(card, currency)}
							</p>
						)}
						<CardTerms account={account} currency={currency} />
					</div>
				) : isDeposit ? (
					<DepositDetails deposit={deposit} currency={currency} closed={closed} />
				) : (
					<div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-white/80">
						{account.last4 && <span className="font-mono tracking-widest">•••• {account.last4}</span>}
						{account.isShared && (
							<span className="inline-flex items-center gap-1 rounded-full bg-black/15 px-2 py-0.5">
								<Users className="size-3" aria-hidden="true" />
								Shared
							</span>
						)}
						{account.ownerName && <span className="rounded-full bg-black/15 px-2 py-0.5">{account.ownerName}</span>}
						{closed && <span className="rounded-full bg-black/25 px-2 py-0.5">Closed</span>}
					</div>
				)}
			</div>
		</article>
	);
}

/** Maturity value, rate and dates on an FD or RD tile. */
function DepositDetails({ deposit: d, currency, closed }: { deposit?: Partial<Deposit>; currency: string; closed: boolean }) {
	if (!d) {
		return <p className="mt-3 inline-flex rounded-full bg-black/15 px-2.5 py-1 text-[11px]">Add the deposit details to track maturity</p>;
	}
	const days = d.daysToMaturity;
	const active = d.status === "Active" && !closed;
	const open = d.status === "Active" || !d.status;
	return (
		<div className="mt-3">
			{d.progressPct !== undefined && active && (
				<div className="h-1.5 overflow-hidden rounded-full bg-white/25" role="progressbar" aria-label="Term elapsed" aria-valuenow={Math.round(d.progressPct)} aria-valuemin={0} aria-valuemax={100}>
					<div className="h-full rounded-full bg-white" style={{ width: `${Math.min(100, Math.max(0, d.progressPct))}%` }} />
				</div>
			)}
			<dl className="mt-3 grid grid-cols-2 gap-3">
				<div>
					<dt className="text-xs text-white/70">{open ? "At maturity" : "Received"}</dt>
					<dd className="font-semibold tabular-nums">{formatMoney(open ? d.maturityAmount : d.amountReceived, currency)}</dd>
				</div>
				<div>
					<dt className="text-xs text-white/70">Matures on</dt>
					<dd className="font-semibold">{d.maturityDate ? formatShortDate(d.maturityDate) : "—"}</dd>
				</div>
				<div>
					<dt className="text-xs text-white/70">Rate of interest</dt>
					<dd className="font-semibold tabular-nums">
						{d.rate ? `${d.rate}%` : "—"}
						{d.seniorCitizen && <span className="font-normal text-white/80"> · senior</span>}
					</dd>
				</div>
				<div>
					<dt className="text-xs text-white/70">{d.kind === "RD" ? "Monthly instalment" : d.payoutPerPeriod ? `Paid ${d.payout?.toLowerCase()}` : "Interest earned"}</dt>
					<dd className="font-semibold tabular-nums">
						{d.kind === "RD"
							? `${formatMoney(d.instalment, currency)}${d.instalmentsDue !== undefined ? ` · ${d.instalmentsDue}/${d.tenureMonths}` : ""}`
							: formatMoney(d.payoutPerPeriod ?? d.interestAtMaturity, currency)}
					</dd>
				</div>
			</dl>
			<div className="mt-3 flex flex-wrap items-center gap-2 text-[11px] text-white/85">
				{d.depositNumberMasked && <span className="font-mono tracking-wider">{d.depositNumberMasked}</span>}
				{d.taxSaver && (
					<span className="inline-flex items-center gap-1 rounded-full bg-black/15 px-2 py-0.5">
						<Lock className="size-3" aria-hidden="true" />
						Tax saver
					</span>
				)}
				{active && days !== undefined && days <= 30 && (
					<span className="inline-flex items-center gap-1 rounded-full bg-black/25 px-2 py-0.5 font-semibold">
						<CalendarClock className="size-3" aria-hidden="true" />
						{days < 0 ? `Matured ${formatDate(d.maturityDate)} - record it` : days === 0 ? "Matures today" : `Matures in ${days} ${days === 1 ? "day" : "days"}`}
					</span>
				)}
				{d.status === "Matured" && <span className="rounded-full bg-black/25 px-2 py-0.5">Matured {formatShortDate(d.closedOn)}</span>}
				{d.status === "Closed Early" && <span className="rounded-full bg-black/25 px-2 py-0.5">Closed early {formatShortDate(d.closedOn)}</span>}
			</div>
		</div>
	);
}

/** Expiry and the annual fee waiver, when the card's terms are known. */
function CardTerms({ account, currency }: { account: Partial<Pick<Account, "cardExpiry" | "annualFee">> & { card?: Partial<CardCycle> }; currency: string }) {
	const expiry = account.cardExpiry;
	const daysToExpiry = expiry ? Math.round((new Date(expiry).getTime() - new Date().setHours(0, 0, 0, 0)) / 86_400_000) : undefined;
	const remaining = account.card?.feeWaiverRemaining;
	if (!expiry && remaining === undefined) return null;
	return (
		<div className="mt-2 flex flex-wrap gap-2 text-[11px] text-white/85">
			{expiry && (
				<span className={cn("rounded-full px-2 py-0.5", daysToExpiry !== undefined && daysToExpiry <= 60 ? "bg-black/30 font-semibold" : "bg-black/15")}>
					{daysToExpiry !== undefined && daysToExpiry < 0 ? "Expired" : "Valid thru"} {expiry.slice(5, 7)}/{expiry.slice(2, 4)}
				</span>
			)}
			{remaining !== undefined && account.annualFee ? (
				<span className="rounded-full bg-black/15 px-2 py-0.5">
					{remaining > 0 ? `Spend ${formatMoney(remaining, currency)} more to waive the ${formatMoney(account.annualFee, currency)} fee` : "Annual fee waiver reached"}
				</span>
			) : null}
		</div>
	);
}
