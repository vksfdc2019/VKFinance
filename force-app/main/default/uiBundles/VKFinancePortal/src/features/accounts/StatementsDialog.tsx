import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { FormErrors } from "@/components/forms";
import { Reveal } from "@/components/finance/motion";
import { StatusMeter } from "@/components/finance/ui";
import { commitmentApi } from "@/api/endpoints";
import type { Account } from "@/api/financeTypes";
import { formatDate, formatMoney, formatShortDate } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { DueBadge } from "@/features/commitments/shared";

/** A card's monthly statements: what was billed, what's been paid, and whether it's settled. */
export function StatementsDialog({ account, currency, onClose }: { account: Account; currency: string; onClose: () => void }) {
	const { data, errors, loading } = useAsync(() => commitmentApi.statements(account.id), [account.id]);
	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>{account.name} statements</DialogTitle>
					<DialogDescription>
						Closes on day {account.statementDay} each month; pay within {account.paymentDueDays ?? 20} days to avoid interest.
					</DialogDescription>
				</DialogHeader>
				<FormErrors errors={errors} />
				{!data && loading ? (
					<Skeleton className="h-40 rounded-xl" />
				) : data && data.length === 0 ? (
					<p className="py-8 text-center text-sm text-slate-500">No statement has closed yet.</p>
				) : (
					<ul className="max-h-[60vh] space-y-2 overflow-y-auto">
						{data?.map((s, i) => {
							const left = Math.max(0, s.amount - s.amountPaid);
							const days = Math.round((new Date(`${s.dueDate}T00:00:00`).getTime() - new Date(new Date().toDateString()).getTime()) / 86400000);
							return (
								<Reveal as="li" key={s.id} index={i}>
									<div className="rounded-2xl bg-slate-50 p-4 ring-1 ring-slate-900/5">
										<div className="flex items-start justify-between gap-3">
											<div>
												<p className="text-sm font-semibold text-slate-900">
													{formatShortDate(s.cycleStart)} – {formatShortDate(s.cycleEnd)}
												</p>
												<p className="text-xs text-slate-500">
													Due {formatDate(s.dueDate)} · minimum {formatMoney(s.minimumDue, currency)}
												</p>
											</div>
											<div className="text-right">
												<p className="font-semibold tabular-nums">{formatMoney(s.amount, currency)}</p>
												<DueBadge status={s.status} daysLeft={s.status === "Paid" ? undefined : days} />
											</div>
										</div>
										{s.amount > 0 && (
											<StatusMeter
												className="mt-3"
												value={s.amountPaid}
												max={s.amount}
												status={s.status === "Paid" ? "good" : s.status === "Overdue" ? "critical" : "warning"}
												label={s.status === "Paid" ? "Paid in full" : `${formatMoney(s.amountPaid, currency)} paid · ${formatMoney(left, currency)} to go`}
											/>
										)}
									</div>
								</Reveal>
							);
						})}
					</ul>
				)}
			</DialogContent>
		</Dialog>
	);
}
