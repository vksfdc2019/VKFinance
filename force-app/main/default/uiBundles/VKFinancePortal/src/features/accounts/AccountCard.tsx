import type { ReactNode } from "react";
import { CalendarClock, Users } from "lucide-react";
import { ACCOUNT_GRADIENTS, ACCOUNT_ICONS, accountColor } from "@/components/finance/icons";
import { utilisationStatus } from "@/components/finance/ui";
import type { Account, CardCycle } from "@/api/financeTypes";
import { formatMoney, formatShortDate } from "@/lib/format";
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
		Partial<Omit<Account, "card">> & { card?: Partial<CardCycle> };
	currency: string;
	menu?: ReactNode;
	className?: string;
}) {
	const Icon = ACCOUNT_ICONS[account.type];
	const card = account.card;
	const pct = card?.utilisationPct;
	const bill = card?.bill ?? card?.statement;
	const available = card?.available ?? (account.creditLimit !== undefined ? account.creditLimit - account.balance : undefined);
	const closed = account.status === "Closed";

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
					</p>
					<h3 className="mt-1 truncate text-lg font-semibold">{account.name || "New account"}</h3>
				</div>
				{menu}
			</div>

			<div className="relative mt-auto pt-4">
				<p className="text-xs text-white/70">
					{account.type === "Credit Card" ? "Total outstanding" : account.isLiability ? "Outstanding" : "Balance"}
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
								{pct.toFixed(0)}% used
								{utilisationStatus(pct) !== "good" && " · keep under 30%"}
							</p>
						)}
						<dl className="mt-3 grid grid-cols-2 gap-3">
							<div>
								<dt className="text-xs text-white/70">Available amount</dt>
								<dd className="font-semibold tabular-nums">{available === undefined ? "—" : formatMoney(available, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Bill amount</dt>
								<dd className="font-semibold tabular-nums">{bill?.amount === undefined ? "—" : formatMoney(bill.amount, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Total credit limit</dt>
								<dd className="font-semibold tabular-nums">{account.creditLimit === undefined ? "—" : formatMoney(account.creditLimit, currency)}</dd>
							</div>
							<div>
								<dt className="text-xs text-white/70">Bill due date</dt>
								<dd className="font-semibold">{bill?.dueDate ? formatShortDate(bill.dueDate) : "—"}</dd>
							</div>
						</dl>
						{card && (
							<p className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-black/15 px-2.5 py-1 text-[11px]">
								<CalendarClock className="size-3.5" aria-hidden="true" />
								{billNote(card, currency)}
							</p>
						)}
					</div>
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
