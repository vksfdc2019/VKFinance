import { Badge } from "@/components/ui/badge";
import { Amount } from "@/components/finance/ui";
import { CategoryChip } from "@/components/finance/icons";
import type { Txn } from "@/api/financeTypes";
import { cn } from "@/lib/utils";

/** The main line for a ledger row: who it was with, or what kind of move it was. */
export function txnTitle(t: Txn): string {
	switch (t.type) {
		case "Transfer Out":
			return `To ${t.payee ?? t.counterAccountName ?? "another account"}`;
		case "Transfer In":
			return `From ${t.payee ?? t.counterAccountName ?? "another account"}`;
		case "Card Payment":
			return t.direction === "Debit" ? `Card bill · ${t.payee ?? "card"}` : `Payment from ${t.payee ?? "bank"}`;
		case "Adjustment":
			return "Balance adjustment";
		default:
			return t.payee || t.categoryName || t.type;
	}
}

export function TxnRow({
	txn,
	currency,
	showMember,
	onOpen,
	compact,
}: {
	txn: Txn;
	currency: string;
	showMember?: boolean;
	onOpen?: (txn: Txn) => void;
	compact?: boolean;
}) {
	const isVoid = txn.status === "Void";
	const detail = [
		txn.type === "Refund" ? "Refund" : txn.categoryName,
		txn.accountName,
		showMember ? txn.memberName : undefined,
	]
		.filter(Boolean)
		.join(" · ");

	return (
		<button
			type="button"
			onClick={() => onOpen?.(txn)}
			disabled={!onOpen}
			className={cn(
				"flex w-full items-center gap-3 rounded-xl text-left transition-colors enabled:hover:bg-slate-50 dark:enabled:hover:bg-slate-800/60 focus-visible:bg-slate-50 dark:focus-visible:bg-slate-800/40 focus-visible:outline-none",
				compact ? "px-1.5 py-2" : "px-3 py-2.5",
			)}
		>
			<CategoryChip icon={txn.icon} color={txn.color} />
			<div className="min-w-0 flex-1">
				<p className={cn("truncate text-sm font-medium text-slate-900 dark:text-slate-100", isVoid && "text-slate-400 line-through")}>{txnTitle(txn)}</p>
				<p className="truncate text-xs text-slate-500 dark:text-slate-400">{detail}</p>
			</div>
			<div className="flex shrink-0 flex-col items-end gap-0.5">
				<Amount value={txn.amount} currency={currency} direction={txn.direction} muted={isVoid} className="text-sm" />
				{isVoid ? (
					<Badge variant="outline" className="h-4 px-1 text-[10px]">
						Void
					</Badge>
				) : (
					txn.notes && !compact && <span className="max-w-40 truncate text-[11px] text-slate-400">{txn.notes}</span>
				)}
			</div>
		</button>
	);
}
