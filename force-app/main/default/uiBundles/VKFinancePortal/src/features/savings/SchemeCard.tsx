import { BadgeIndianRupee, MoreVertical, Pencil, Plus, Power, Trash2, TrendingUp, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import type { Scheme } from "@/api/savingsTypes";
import { formatDate, formatMoney, formatShortDate } from "@/lib/format";
import { SCHEME_BY_CODE, SCHEME_TINT } from "@/lib/schemes";
import { cn } from "@/lib/utils";
import type { SchemeAction } from "./SavingsDialogs";

/** A scheme on its own coloured card: balance, maturity, rate and this year's deposits. */
export function SchemeCard({
	scheme: s,
	currency,
	onAction,
	onEdit,
	onHistory,
	onDelete,
}: {
	scheme: Scheme;
	currency: string;
	onAction: (a: SchemeAction) => void;
	onEdit: () => void;
	onHistory: () => void;
	onDelete: () => void;
}) {
	const info = SCHEME_BY_CODE[s.scheme];
	const active = s.status === "Active";
	const gain = s.maturityValue !== undefined ? s.maturityValue - s.balance : undefined;
	return (
		<article className={cn("vk-lift relative overflow-hidden rounded-2xl bg-gradient-to-br p-5 text-white shadow-lg", SCHEME_TINT[s.scheme], !active && "opacity-80 saturate-50")}>
			<div className="pointer-events-none absolute -top-12 -right-12 size-40 rounded-full bg-white/10 blur-2xl" />
			<div className="relative">
				<div className="flex items-start justify-between gap-3">
					<div className="min-w-0">
						<p className="flex items-center gap-2">
							<span className="rounded-md bg-white/20 px-1.5 py-0.5 text-[11px] font-bold tracking-wide">{info?.short ?? s.scheme}</span>
							{s.taxSection && <span className="rounded-full bg-black/20 px-2 py-0.5 text-[10px] font-medium">{s.taxSection}</span>}
							{!active && <span className="rounded-full bg-black/30 px-2 py-0.5 text-[10px] font-medium">{s.status}</span>}
						</p>
						<h3 className="mt-2 truncate text-base font-semibold">{s.name}</h3>
						<p className="truncate text-xs text-white/75">
							{[s.institution, s.accountNumberMasked, s.beneficiary ? `for ${s.beneficiary}` : s.ownerName].filter(Boolean).join(" · ") || s.schemeLabel}
						</p>
					</div>
					{s.canManage && (
						<DropdownMenu>
							<DropdownMenuTrigger asChild>
								<Button variant="ghost" size="icon-sm" className="text-white hover:bg-white/15 hover:text-white" aria-label={`Actions for ${s.name}`}>
									<MoreVertical />
								</Button>
							</DropdownMenuTrigger>
							<DropdownMenuContent align="end" className="w-52">
								{active && s.depositsOpen && (
									<DropdownMenuItem onSelect={() => onAction("contribute")}>
										<Plus />
										Add a deposit
									</DropdownMenuItem>
								)}
								{active && (
									<DropdownMenuItem onSelect={() => onAction("interest")}>
										<BadgeIndianRupee />
										Record interest
									</DropdownMenuItem>
								)}
								{active && (
									<DropdownMenuItem onSelect={() => onAction("value")}>
										<TrendingUp />
										Update value
									</DropdownMenuItem>
								)}
								<DropdownMenuItem onSelect={onHistory}>
									<Wallet />
									Entries
								</DropdownMenuItem>
								<DropdownMenuItem onSelect={onEdit}>
									<Pencil />
									Edit details
								</DropdownMenuItem>
								{active && (
									<DropdownMenuItem onSelect={() => onAction("close")}>
										<Power />
										Close or matured
									</DropdownMenuItem>
								)}
								{s.canDelete && (
									<>
										<DropdownMenuSeparator />
										<DropdownMenuItem variant="destructive" onSelect={onDelete}>
											<Trash2 />
											Delete (added by mistake)
										</DropdownMenuItem>
									</>
								)}
							</DropdownMenuContent>
						</DropdownMenu>
					)}
				</div>

				<p className="mt-4 text-2xl font-semibold tracking-tight tabular-nums">{formatMoney(s.balance, currency)}</p>
				<p className="text-[11px] text-white/70">{s.kind === "market" && s.valueAsOf ? `Value as of ${formatShortDate(s.valueAsOf)}` : "Balance today"}</p>

				{s.progressPct !== undefined && active && (
					<div className="mt-3 h-1.5 overflow-hidden rounded-full bg-white/20" role="progressbar" aria-label="Term elapsed" aria-valuenow={Math.round(s.progressPct)} aria-valuemin={0} aria-valuemax={100}>
						<div className="h-full rounded-full bg-white" style={{ width: `${s.progressPct}%` }} />
					</div>
				)}

				<dl className="mt-3 grid grid-cols-2 gap-3 text-sm">
					<div>
						<dt className="text-xs text-white/70">{s.payoutAmount ? `Interest ${s.payout?.toLowerCase()}` : "At maturity"}</dt>
						<dd className="font-semibold tabular-nums">{s.payoutAmount ? formatMoney(s.payoutAmount, currency) : s.maturityValue !== undefined ? formatMoney(s.maturityValue, currency) : "Market-linked"}</dd>
					</div>
					<div>
						<dt className="text-xs text-white/70">Matures on</dt>
						<dd className="font-semibold">{s.maturityDate ? formatShortDate(s.maturityDate) + " " + s.maturityDate.slice(0, 4) : "—"}</dd>
					</div>
					<div>
						<dt className="text-xs text-white/70">Rate</dt>
						<dd className="font-semibold tabular-nums">{s.rate !== undefined ? `${s.rate}% a year` : "—"}</dd>
					</div>
					<div>
						<dt className="text-xs text-white/70">{s.roomThisYear !== undefined ? "Room this FY" : "Deposited this FY"}</dt>
						<dd className="font-semibold tabular-nums">{formatMoney(s.roomThisYear ?? s.contributedThisYear, currency)}</dd>
					</div>
				</dl>

				<div className="mt-3 flex flex-wrap gap-1.5 text-[11px]">
					{gain !== undefined && gain > 0 && active && <span className="rounded-full bg-black/20 px-2 py-0.5">+{formatMoney(gain, currency)} by maturity</span>}
					{s.daysToMaturity !== undefined && active && s.daysToMaturity >= 0 && s.daysToMaturity <= 90 && <span className="rounded-full bg-amber-300/30 px-2 py-0.5">Matures in {s.daysToMaturity} days</span>}
					{s.daysToMaturity !== undefined && active && s.daysToMaturity < 0 && <span className="rounded-full bg-amber-300/30 px-2 py-0.5">Matured {formatDate(s.maturityDate)} - close it</span>}
					{s.taxNote && <span className="rounded-full bg-black/15 px-2 py-0.5">{s.taxNote}</span>}
				</div>
			</div>
		</article>
	);
}
