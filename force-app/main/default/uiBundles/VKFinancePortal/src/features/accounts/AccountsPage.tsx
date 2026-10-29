import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { ArrowLeftRight, CreditCard, FileText, ListOrdered, MoreVertical, Pencil, Plus, Power, Receipt, Scale, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { EmptyState, PageHeader } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account, AccountType } from "@/api/financeTypes";
import { formatMoney } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { AccountCard } from "./AccountCard";
import { AccountDialog, ReconcileDialog } from "./AccountDialogs";
import { StatementsDialog } from "./StatementsDialog";

const GROUPS: { title: string; types: AccountType[] }[] = [
	{ title: "Bank & cash", types: ["Savings", "Current", "Cash", "UPI Wallet"] },
	{ title: "Credit cards", types: ["Credit Card"] },
	{ title: "Savings & investments", types: ["Fixed Deposit", "Investment"] },
	{ title: "Loans", types: ["Loan"] },
];

export default function AccountsPage() {
	const { can } = useAuth();
	const { version, refresh, openEntry, canAdd, currency } = useLedger();
	const navigate = useNavigate();
	const [params, setParams] = useSearchParams();
	const [showClosed, setShowClosed] = useState(false);
	const [editing, setEditing] = useState<Account | "new" | null>(params.get("new") === "1" ? "new" : null);
	const [reconciling, setReconciling] = useState<Account | null>(null);
	const [statementsFor, setStatementsFor] = useState<Account | null>(null);
	const { data: accounts, errors, loading } = useAsync(() => financeApi.accounts(showClosed), [showClosed, version]);
	const canCreate = can("ACCOUNTS:CREATE");

	useEffect(() => {
		if (params.get("new")) setParams({}, { replace: true });
	}, [params, setParams]);

	async function setStatus(account: Account, status: "Active" | "Closed") {
		try {
			await financeApi.updateAccount(account.id, { status });
			toast.success(status === "Closed" ? `${account.name} closed` : `${account.name} reopened`);
			refresh();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	const active = (accounts ?? []).filter((a) => a.status === "Active");
	const assets = active.filter((a) => !a.isLiability).reduce((s, a) => s + a.balance, 0);
	const owed = active.filter((a) => a.isLiability).reduce((s, a) => s + a.balance, 0);

	function menu(a: Account) {
		const usable = a.canUse && a.status === "Active";
		return (
			<DropdownMenu>
				<DropdownMenuTrigger asChild>
					<Button variant="ghost" size="icon-sm" aria-label={`Actions for ${a.name}`} className="text-white hover:bg-white/15 hover:text-white">
						<MoreVertical />
					</Button>
				</DropdownMenuTrigger>
				<DropdownMenuContent align="end" className="w-52">
					{usable && canAdd && (
						<>
							<DropdownMenuItem onSelect={() => openEntry({ mode: "expense", accountId: a.id })}>
								<Receipt />
								Add expense here
							</DropdownMenuItem>
							{a.type === "Credit Card" ? (
								<DropdownMenuItem onSelect={() => openEntry({ mode: "transfer", toAccountId: a.id })}>
									<CreditCard />
									Pay this card
								</DropdownMenuItem>
							) : (
								<DropdownMenuItem onSelect={() => openEntry({ mode: "transfer", accountId: a.id })}>
									<ArrowLeftRight />
									Transfer from here
								</DropdownMenuItem>
							)}
						</>
					)}
					<DropdownMenuItem onSelect={() => navigate(`/transactions?account=${a.id}`)}>
						<ListOrdered />
						View transactions
					</DropdownMenuItem>
					{a.type === "Credit Card" && a.statementDay && (
						<DropdownMenuItem onSelect={() => setStatementsFor(a)}>
							<FileText />
							Statements
						</DropdownMenuItem>
					)}
					{a.canManage && (
						<>
							<DropdownMenuSeparator />
							<DropdownMenuItem onSelect={() => setEditing(a)}>
								<Pencil />
								Edit details
							</DropdownMenuItem>
							{a.status === "Active" && (
								<DropdownMenuItem onSelect={() => setReconciling(a)}>
									<Scale />
									Match to statement
								</DropdownMenuItem>
							)}
							<DropdownMenuItem onSelect={() => void setStatus(a, a.status === "Active" ? "Closed" : "Active")}>
								<Power />
								{a.status === "Active" ? "Close account" : "Reopen account"}
							</DropdownMenuItem>
						</>
					)}
				</DropdownMenuContent>
			</DropdownMenu>
		);
	}

	return (
		<>
			<PageHeader
				title="Accounts"
				description="Bank accounts, cash, wallets and cards - balances update with every entry."
				actions={
					<>
						{canAdd && (
							<Button variant="outline" onClick={() => openEntry({ mode: "transfer" })}>
								<ArrowLeftRight />
								Transfer
							</Button>
						)}
						{canCreate && (
							<Button onClick={() => setEditing("new")}>
								<Plus />
								Add account
							</Button>
						)}
					</>
				}
			/>

			<div className="mb-6 grid gap-3 sm:grid-cols-3">
				<Summary label="Net worth" value={formatMoney(assets - owed, currency)} strong />
				<Summary label="You have" value={formatMoney(assets, currency)} />
				<Summary label="You owe" value={formatMoney(owed, currency)} />
			</div>

			<FormErrors errors={errors} />
			{!accounts && loading ? (
				<div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
					{[0, 1, 2].map((i) => (
						<Skeleton key={i} className="h-48 rounded-2xl" />
					))}
				</div>
			) : accounts && accounts.length === 0 ? (
				<div className="rounded-2xl bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
					<EmptyState
						icon={<Wallet />}
						title="No accounts yet"
						action={
							canCreate && (
								<Button onClick={() => setEditing("new")}>
									<Plus />
									Add your first account
								</Button>
							)
						}
					>
						Add the bank accounts, cash and cards your family uses. Their balances then follow every entry.
					</EmptyState>
				</div>
			) : (
				GROUPS.map((group) => {
					const rows = (accounts ?? []).filter((a) => group.types.includes(a.type));
					if (!rows.length) return null;
					const total = rows.filter((a) => a.status === "Active").reduce((s, a) => s + a.balance, 0);
					return (
						<section key={group.title} className="mb-8">
							<div className="mb-3 flex items-baseline justify-between">
								<h2 className="text-sm font-semibold text-slate-700 dark:text-slate-300">{group.title}</h2>
								<span className="text-sm tabular-nums text-slate-500 dark:text-slate-400">{formatMoney(total, currency)}</span>
							</div>
							<div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
								{rows.map((a) => (
									<AccountCard key={a.id} account={a} currency={currency} menu={menu(a)} />
								))}
							</div>
						</section>
					);
				})
			)}

			<label className="inline-flex items-center gap-2 text-sm text-slate-600 dark:text-slate-400">
				<Checkbox checked={showClosed} onCheckedChange={(v) => setShowClosed(v === true)} />
				Show closed accounts
			</label>

			{editing && (
				<AccountDialog
					account={editing === "new" ? undefined : editing}
					currency={currency}
					onClose={() => setEditing(null)}
					onSaved={() => {
						setEditing(null);
						refresh();
					}}
				/>
			)}
			{statementsFor && <StatementsDialog account={statementsFor} currency={currency} onClose={() => setStatementsFor(null)} />}
			{reconciling && (
				<ReconcileDialog
					account={reconciling}
					currency={currency}
					onClose={() => setReconciling(null)}
					onSaved={() => {
						setReconciling(null);
						refresh();
					}}
				/>
			)}
		</>
	);
}

function Summary({ label, value, strong }: { label: string; value: string; strong?: boolean }) {
	return (
		<div className={strong ? "rounded-2xl bg-slate-900 dark:bg-slate-700 px-5 py-4 text-white" : "rounded-2xl bg-white dark:bg-slate-900 px-5 py-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10"}>
			<p className={strong ? "text-xs text-slate-300" : "text-xs text-slate-500 dark:text-slate-400"}>{label}</p>
			<p className="mt-1 text-xl font-semibold tabular-nums">{value}</p>
		</div>
	);
}
