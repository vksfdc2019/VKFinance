import type { ReactNode } from "react";
import { Link, useSearchParams } from "react-router";
import { CreditCard, Landmark, Lock, ReceiptText, Scale, Wallet } from "lucide-react";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { FormErrors } from "@/components/forms";
import { AccountChip, CategoryChip } from "@/components/finance/icons";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { EmptyState, MonthSwitcher, PageHeader, Panel, StatusMeter, utilisationStatus } from "@/components/finance/ui";
import { DueBadge } from "@/features/commitments/shared";
import { financeApi } from "@/api/endpoints";
import type { BankPosition, BillPosition, CardPosition, LoanPosition, MoneyPosition, PositionLoan } from "@/api/positionTypes";
import { formatDate, formatMoney, formatPercent, formatShortDate, monthKey, monthLabel } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { SplitBar, type Segment } from "./SplitBar";
import { AlertStrip, DueCalendar, Headline as Note, RingRow } from "./Insights";
import { bankHeadline, billHeadline, cardHeadline, dailyAllowance, daysLeft, loanHeadline, type Tone } from "@/lib/position";

/** Available against spent, side by side for bank accounts, credit cards, bills and loans. */
export default function PositionPage() {
	const { profile } = useAuth();
	const { version } = useLedger();
	const [params, setParams] = useSearchParams();
	const month = params.get("month") ?? monthKey();
	const { data, errors } = useAsync(() => financeApi.position(month), [month, version]);
	const currency = data?.currencyCode ?? profile?.currencyCode ?? "INR";

	function setMonth(m: string) {
		const next = new URLSearchParams(params);
		if (m === monthKey()) next.delete("month");
		else next.set("month", m);
		setParams(next, { replace: true });
	}

	return (
		<>
			<PageHeader
				title="Money position"
				description={
					data
						? `Balances as of ${formatDate(data.asOf)} · ${monthLabel(data.month)} runs ${formatShortDate(data.periodStart)} – ${formatShortDate(data.periodEnd)}`
						: "What you have, what you spent and what is still due"
				}
				actions={<MonthSwitcher value={month} onChange={setMonth} />}
			/>
			<FormErrors errors={errors} />
			{!data ? (
				errors.length === 0 && <PositionSkeleton />
			) : (
				<>
					<AlertStrip data={data} currency={currency} />
					<Reveal index={0}>
						<Headline data={data} currency={currency} />
					</Reveal>
					<RingRow data={data} currency={currency} />
					<Reveal index={1} className="mt-4">
						<DueCalendar key={data.month} data={data} currency={currency} />
					</Reveal>
					<div className="mt-4 grid gap-4 xl:grid-cols-2">
						{data.bank && (
							<Reveal index={1}>
								<BankPanel bank={data.bank} currency={currency} note={bankHeadline(data, currency)} />
							</Reveal>
						)}
						{data.cards && (
							<Reveal index={2}>
								<CardsPanel cards={data.cards} currency={currency} note={cardHeadline(data, currency)} />
							</Reveal>
						)}
						{data.bills && (
							<Reveal index={3}>
								<BillsPanel bills={data.bills} currency={currency} month={data.month} note={billHeadline(data, currency)} />
							</Reveal>
						)}
						{data.loans && (
							<Reveal index={4}>
								<LoansPanel loans={data.loans} currency={currency} note={loanHeadline(data, currency)} />
							</Reveal>
						)}
					</div>
				</>
			)}
		</>
	);
}

function Headline({ data, currency }: { data: MoneyPosition; currency: string }) {
	const s = data.summary;
	const left = s.leftAfterDues;
	const committed = Math.min(Math.max(s.liquid, 0), s.duesRemaining);
	const daily = dailyAllowance(data);
	return (
		<section className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-brand-800 via-brand-900 to-slate-900 p-5 text-white shadow-lg shadow-brand-900/20 sm:p-6">
			<div className="pointer-events-none absolute -top-16 -right-10 size-56 rounded-full bg-brand-400/20 blur-2xl" />
			<div className="pointer-events-none absolute -bottom-24 left-1/3 size-56 rounded-full bg-sky-400/10 blur-2xl" />
			<div className="relative grid gap-6 lg:grid-cols-[1.1fr_2fr] lg:items-center">
				<div>
					<p className="flex items-center gap-2 text-sm text-brand-100/80">
						<Wallet className="size-4" aria-hidden="true" />
						Available to spend
					</p>
					<p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl">
						<AnimatedMoney value={s.liquid} currency={currency} />
					</p>
					<p className="mt-1 text-xs text-brand-100/70">Savings, current, cash and UPI wallets</p>
					{data.isCurrent && s.liquid > 0 && (
						<div className="mt-4">
							<div className="flex h-2.5 overflow-hidden rounded-full bg-white/15" role="img" aria-label={`${formatMoney(committed, currency)} of it is needed for this month's dues`}>
								<div className="h-full bg-amber-300" style={{ width: `${(committed / s.liquid) * 100}%` }} />
								<div className="h-full flex-1 bg-emerald-300/90" />
							</div>
							<p className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-brand-100/80">
								<span className="inline-flex items-center gap-1.5">
									<span className="size-2 rounded-full bg-amber-300" aria-hidden="true" />
									Kept for dues {formatMoney(committed, currency)}
								</span>
								<span className="inline-flex items-center gap-1.5">
									<span className="size-2 rounded-full bg-emerald-300" aria-hidden="true" />
									Free {formatMoney(Math.max(0, left ?? 0), currency)}
								</span>
							</p>
						</div>
					)}
				</div>
				<dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
					{daily !== undefined && (
						<div className="col-span-2 flex items-center justify-between gap-3 rounded-xl bg-emerald-400/15 px-4 py-3 ring-1 ring-emerald-300/30 dark:ring-emerald-700/30 sm:col-span-4">
							<div>
								<dt className="text-[11px] text-emerald-100/80">You can spend about</dt>
								<dd className="text-xl font-semibold tabular-nums text-emerald-100">
									{formatMoney(daily, currency)} <span className="text-sm font-medium text-emerald-100/80">a day</span>
								</dd>
							</div>
							<dd className="text-right text-[11px] text-emerald-100/80">
								for the next {daysLeft(data)} {daysLeft(data) === 1 ? "day" : "days"}
								<br />
								till {formatShortDate(data.periodEnd)}, after dues
							</dd>
						</div>
					)}
					{data.isCurrent ? (
						<>
							<HeroTile label="Still due this month" value={formatMoney(s.duesRemaining, currency)} hint="Bills, EMIs and card dues" />
							<HeroTile
								label="Left after dues"
								value={formatMoney(left ?? 0, currency)}
								hint={left !== undefined && left < 0 ? "Short - move money in" : "Safe to spend"}
								tone={left !== undefined && left < 0 ? "bad" : "good"}
							/>
						</>
					) : (
						<>
							<HeroTile label="Money in" value={formatMoney(s.moneyIn, currency)} hint={monthLabel(data.month)} />
							<HeroTile label="Money out" value={formatMoney(s.moneyOut, currency)} hint={monthLabel(data.month)} />
						</>
					)}
					<HeroTile label="Card limit free" value={formatMoney(s.cardAvailable, currency)} hint="Across all cards" />
					<HeroTile label="You owe" value={formatMoney(s.owed, currency)} hint="Cards and loans" />
				</dl>
			</div>
		</section>
	);
}

function HeroTile({ label, value, hint, tone }: { label: string; value: string; hint?: string; tone?: "good" | "bad" }) {
	return (
		<div className="rounded-xl bg-white/10 px-3 py-2.5 ring-1 ring-white/10">
			<dt className="text-[11px] text-brand-100/70">{label}</dt>
			<dd className={cn("mt-0.5 text-base font-semibold tabular-nums", tone === "bad" && "text-red-200", tone === "good" && "text-emerald-200")}>{value}</dd>
			{hint && <dd className="text-[10px] text-brand-100/60">{hint}</dd>}
		</div>
	);
}

/** The two figures a section is about, then a bar that compares them. */
function SectionTop({ primary, secondary, segments, label }: { primary: Figure; secondary: Figure; segments: Segment[]; label: string }) {
	return (
		<div>
			<div className="flex flex-wrap items-end justify-between gap-3">
				<FigureView figure={primary} large />
				<FigureView figure={secondary} align="right" />
			</div>
			<SplitBar className="mt-3" segments={segments} label={label} />
		</div>
	);
}

interface Figure {
	label: string;
	value: string;
	tone?: "good" | "warn" | "bad";
}

function FigureView({ figure, large, align }: { figure: Figure; large?: boolean; align?: "right" }) {
	return (
		<div className={cn(align === "right" && "text-right")}>
			<p className="text-xs text-slate-500 dark:text-slate-400">{figure.label}</p>
			<p
				className={cn(
					"font-semibold tracking-tight tabular-nums",
					large ? "text-2xl" : "text-lg",
					figure.tone === "bad" ? "text-red-700 dark:text-red-300" : figure.tone === "warn" ? "text-amber-700 dark:text-amber-300" : "text-slate-900 dark:text-slate-100",
				)}
			>
				{figure.value}
			</p>
		</div>
	);
}

function Stats({ items }: { items: { label: string; value: ReactNode }[] }) {
	return (
		<dl className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
			{items.map((item) => (
				<div key={item.label} className="rounded-xl bg-slate-50 dark:bg-slate-800/50 px-3 py-2">
					<dt className="text-[11px] text-slate-500 dark:text-slate-400">{item.label}</dt>
					<dd className="mt-0.5 text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{item.value}</dd>
				</div>
			))}
		</dl>
	);
}

function ViewAll({ to, label }: { to: string; label: string }) {
	return (
		<Link to={to} className="text-xs font-medium text-brand-700 dark:text-brand-300 hover:underline">
			{label}
		</Link>
	);
}

function Rows({ children }: { children: ReactNode }) {
	return <ul className="mt-4 divide-y divide-slate-100 dark:divide-slate-800 border-t border-slate-100 dark:border-slate-800">{children}</ul>;
}

function masked(last4?: string) {
	return last4 ? `•• ${last4}` : undefined;
}

function BankPanel({ bank, currency, note }: { bank: BankPosition; currency: string; note?: SectionNote }) {
	const spendable = bank.accounts.filter((a) => a.liquid);
	const locked = bank.accounts.filter((a) => !a.liquid);
	const net = bank.moneyIn - bank.moneyOut;
	return (
		<Panel className="h-full" title={<SectionTitle icon={<Landmark />} text="Bank & cash" />} description="Savings, current, cash, UPI wallets and deposits" action={<ViewAll to="/accounts" label="Accounts" />}>
			{bank.accounts.length === 0 ? (
				<EmptyState icon={<Landmark />} title="No accounts yet" action={<ViewAll to="/accounts" label="Add an account" />} className="py-6" />
			) : (
				<>
					{note && <Note text={note.text} tone={note.tone} />}
					<SectionTop
						primary={{ label: "Available now", value: formatMoney(bank.available, currency) }}
						secondary={{ label: "Locked in deposits", value: formatMoney(bank.locked, currency) }}
						label="Money in against money out this month"
						segments={[
							{ label: "Money in", value: bank.moneyIn, className: "bg-emerald-500" },
							{ label: "Money out", value: bank.moneyOut, className: "bg-orange-400" },
						]}
					/>
					<Stats
						items={[
							{ label: "Money in", value: <span className="text-emerald-700 dark:text-emerald-300">+{formatMoney(bank.moneyIn, currency)}</span> },
							{ label: "Money out", value: <span>−{formatMoney(bank.moneyOut, currency)}</span> },
							{ label: "Net this month", value: <span className={net < 0 ? "text-red-700 dark:text-red-300" : undefined}>{formatMoney(net, currency, { signed: true })}</span> },
							{ label: "Lowest balance", value: bank.lowestBalance === undefined ? "–" : formatMoney(bank.lowestBalance, currency) },
						]}
					/>
					<Rows>
						{[...spendable, ...locked].map((a) => (
							<li key={a.id}>
								<Link to={`/transactions?account=${a.id}`} className="-mx-2 flex items-center gap-3 rounded-xl px-2 py-2.5 hover:bg-slate-50 dark:hover:bg-slate-800/60">
									<AccountChip account={a} />
									<div className="min-w-0 flex-1">
										<p className="flex items-center gap-1.5 truncate text-sm font-medium text-slate-900 dark:text-slate-100">
											{a.name}
											{!a.liquid && <Lock className="size-3 shrink-0 text-slate-400" aria-label="Locked" />}
										</p>
										<p className="truncate text-xs text-slate-500 dark:text-slate-400">
											{a.liquid
												? [a.institution ?? a.type, masked(a.last4), a.ownerName].filter(Boolean).join(" · ")
												: a.maturityDate
													? `${a.type} · matures ${formatShortDate(a.maturityDate)}${a.maturityAmount ? ` for ${formatMoney(a.maturityAmount, currency)}` : ""}`
													: [a.type, a.institution].filter(Boolean).join(" · ")}
										</p>
									</div>
									<div className="text-right">
										<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(a.balance, currency)}</p>
										{(a.moneyIn > 0 || a.moneyOut > 0) && (
											<p className="text-[11px] tabular-nums text-slate-500 dark:text-slate-400">
												<span className="text-emerald-700 dark:text-emerald-300">+{formatMoney(a.moneyIn, currency)}</span> · −{formatMoney(a.moneyOut, currency)}
											</p>
										)}
									</div>
								</Link>
							</li>
						))}
					</Rows>
				</>
			)}
		</Panel>
	);
}

function CardsPanel({ cards, currency, note }: { cards: CardPosition; currency: string; note?: SectionNote }) {
	const pct = cards.utilisationPct ?? 0;
	return (
		<Panel className="h-full" title={<SectionTitle icon={<CreditCard />} text="Credit cards" />} description="Limit, what you used and what is due" action={<ViewAll to="/accounts" label="Cards" />}>
			{cards.cards.length === 0 ? (
				<EmptyState icon={<CreditCard />} title="No credit cards" className="py-6" />
			) : (
				<>
					{note && <Note text={note.text} tone={note.tone} />}
					<SectionTop
						primary={{ label: "Limit available", value: formatMoney(cards.available, currency) }}
						secondary={{ label: `Used of ${formatMoney(cards.totalLimit, currency)}`, value: formatMoney(cards.used, currency), tone: pct > 70 ? "bad" : pct > 30 ? "warn" : undefined }}
						label="Credit used against limit available"
						segments={[
							{ label: "Used", value: cards.used, className: "bg-orange-400" },
							{ label: "Available", value: Math.max(0, cards.available), className: "bg-emerald-500" },
						]}
					/>
					{cards.totalLimit > 0 && (
						<StatusMeter
							className="mt-3"
							value={pct}
							max={100}
							status={utilisationStatus(pct)}
							label={`${formatPercent(pct)} of your limit in use${pct <= 30 ? " - healthy for your credit score" : " - under 30% is better for your CIBIL score"}`}
						/>
					)}
					<Stats
						items={[
							{ label: "Spent this month", value: formatMoney(cards.spent, currency) },
							{ label: "Paid this month", value: formatMoney(cards.paid, currency) },
							{ label: "Bill due now", value: <span className={cards.overdueCount > 0 ? "text-red-700 dark:text-red-300" : undefined}>{formatMoney(cards.dueNow, currency)}</span> },
							{ label: "Next due date", value: cards.nextDueDate ? formatShortDate(cards.nextDueDate) : "Nothing due" },
						]}
					/>
					{cards.minimumDue > 0 && (
						<p className="mt-2 text-xs text-slate-500 dark:text-slate-400">
							Minimum due {formatMoney(cards.minimumDue, currency)}. Paying only the minimum attracts interest on the full balance - pay the total due to stay interest-free.
						</p>
					)}
					<Rows>
						{cards.cards.map((c) => {
							const p = c.utilisationPct ?? 0;
							return (
								<li key={c.id} className="py-3">
									<div className="flex items-center gap-3">
										<AccountChip account={{ color: c.color, type: "Credit Card" }} />
										<div className="min-w-0 flex-1">
											<p className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">{c.name}</p>
											<p className="truncate text-xs text-slate-500 dark:text-slate-400">
												{[c.network, masked(c.last4), c.sharedLimitName ? `shares ${c.sharedLimitName}` : c.institution].filter(Boolean).join(" · ")}
											</p>
										</div>
										<div className="text-right">
											<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(c.used, currency)}</p>
											<p className="text-[11px] text-slate-500 dark:text-slate-400">
												{c.available !== undefined ? `${formatMoney(c.available, currency)} free` : "used"}
											</p>
										</div>
									</div>
									{c.creditLimit !== undefined && (
										<div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800" role="img" aria-label={`${formatPercent(p)} of the limit used`}>
											<div className="h-full rounded-full" style={{ width: `${Math.min(100, Math.max(0, p))}%`, backgroundColor: `var(--status-${utilisationStatus(p)})` }} />
										</div>
									)}
									<div className="mt-1.5 flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-500 dark:text-slate-400">
										<span>Spent {formatMoney(c.spent, currency)} this month</span>
										{c.dueRemaining > 0 ? (
											<span className={cn("font-medium", c.statementStatus === "Overdue" ? "text-red-700 dark:text-red-300" : "text-amber-800 dark:text-amber-200")}>
												{formatMoney(c.dueRemaining, currency)} due {c.dueDate ? formatShortDate(c.dueDate) : ""}
												{c.lateFeeAfter && c.statementStatus !== "Overdue" ? ` · no late fee till ${formatShortDate(c.lateFeeAfter)}` : ""}
											</span>
										) : (
											<span>{c.nextStatementDate ? `Next statement ${formatShortDate(c.nextStatementDate)}` : "No bill due"}</span>
										)}
									</div>
								</li>
							);
						})}
					</Rows>
				</>
			)}
		</Panel>
	);
}

function BillsPanel({ bills, currency, month, note }: { bills: BillPosition; currency: string; month: string; note?: SectionNote }) {
	return (
		<Panel className="h-full" title={<SectionTitle icon={<ReceiptText />} text="Bills" />} description={`Due in ${monthLabel(month)}, and anything overdue`} action={<ViewAll to="/bills" label="Bills" />}>
			{bills.items.length === 0 ? (
				<EmptyState icon={<ReceiptText />} title="No bills this month" className="py-6">
					Card bills show with their card, and EMIs under loans.
				</EmptyState>
			) : (
				<>
					{note && <Note text={note.text} tone={note.tone} />}
					<SectionTop
						primary={{ label: "Still to pay", value: formatMoney(bills.remaining, currency), tone: bills.overdue > 0 ? "bad" : undefined }}
						secondary={{ label: `Paid of ${formatMoney(bills.due, currency)}`, value: formatMoney(bills.paid, currency) }}
						label="Bills paid against still to pay"
						segments={[
							{ label: "Paid", value: bills.paid, className: "bg-emerald-500" },
							{ label: "Overdue", value: bills.overdue, className: "bg-red-500" },
							{ label: "Upcoming", value: Math.max(0, bills.remaining - bills.overdue), className: "bg-amber-400" },
						]}
					/>
					<Stats
						items={[
							{ label: "Bills this month", value: bills.count },
							{ label: "Paid", value: `${bills.paidCount} of ${bills.count}` },
							{ label: "Overdue", value: <span className={bills.overdueCount > 0 ? "text-red-700 dark:text-red-300" : undefined}>{bills.overdueCount}</span> },
							{ label: "Overdue amount", value: formatMoney(bills.overdue, currency) },
						]}
					/>
					<Rows>
						{bills.items.map((b) => (
							<li key={b.id} className="flex items-center gap-3 py-2.5">
								<CategoryChip icon={b.icon} color={b.color} size="sm" />
								<div className="min-w-0 flex-1">
									<p className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">{b.billName}</p>
									<p className="truncate text-xs text-slate-500 dark:text-slate-400">
										Due {formatShortDate(b.dueDate)}
										{b.autoPay ? " · auto-pay" : ""}
										{b.responsibleName ? ` · ${b.responsibleName}` : ""}
									</p>
								</div>
								<div className="flex flex-col items-end gap-1">
									<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(b.amountDue ?? 0, currency)}</p>
									<DueBadge status={b.status} daysLeft={b.daysLeft} />
								</div>
							</li>
						))}
					</Rows>
				</>
			)}
		</Panel>
	);
}

const LOAN_BADGE: Record<PositionLoan["monthStatus"], string> = {
	Paid: "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-800 dark:text-emerald-200",
	Due: "bg-amber-50 dark:bg-amber-950/40 text-amber-800 dark:text-amber-200",
	Overdue: "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
	None: "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400",
};

function LoansPanel({ loans, currency, note }: { loans: LoanPosition; currency: string; note?: SectionNote }) {
	return (
		<Panel className="h-full" title={<SectionTitle icon={<Scale />} text="Loans & EMIs" />} description="What you borrowed, repaid and still owe" action={<ViewAll to="/loans" label="Loans" />}>
			{loans.loans.length === 0 ? (
				<EmptyState icon={<Scale />} title="No loans" className="py-6" />
			) : (
				<>
					{note && <Note text={note.text} tone={note.tone} />}
					<SectionTop
						primary={{ label: "Outstanding", value: formatMoney(loans.outstanding, currency) }}
						secondary={{ label: `Repaid of ${formatMoney(loans.borrowed, currency)}`, value: `${formatMoney(loans.repaid, currency)}${loans.repaidPct !== undefined ? ` · ${formatPercent(loans.repaidPct)}` : ""}` }}
						label="Principal repaid against outstanding"
						segments={[
							{ label: "Repaid", value: loans.repaid, className: "bg-emerald-500" },
							{ label: "Outstanding", value: loans.outstanding, className: "bg-sky-500" },
						]}
					/>
					<Stats
						items={[
							{ label: "Monthly EMI", value: formatMoney(loans.monthlyEmi, currency) },
							{ label: "EMIs paid this month", value: formatMoney(loans.emiPaid, currency) },
							{ label: "EMIs still due", value: <span className={loans.overdueCount > 0 ? "text-red-700 dark:text-red-300" : undefined}>{formatMoney(loans.emiRemaining, currency)}</span> },
							{ label: "Interest to come", value: formatMoney(loans.interestRemaining, currency) },
						]}
					/>
					<Rows>
						{loans.loans.map(({ loan, emiThisMonth, dueThisMonth, monthStatus }) => (
							<li key={loan.id} className="py-3">
								<div className="flex items-center gap-3">
									<span className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-sky-50 dark:bg-sky-950/40 text-sky-700 dark:text-sky-300 [&_svg]:size-4" aria-hidden="true">
										<Landmark />
									</span>
									<div className="min-w-0 flex-1">
										<p className="truncate text-sm font-medium text-slate-900 dark:text-slate-100">{loan.name}</p>
										<p className="truncate text-xs text-slate-500 dark:text-slate-400">
											{[loan.lender, `${loan.annualRate}% ${loan.rateType?.toLowerCase() ?? ""}`.trim(), loan.loanAccountNumberMasked].filter(Boolean).join(" · ")}
										</p>
									</div>
									<div className="text-right">
										<p className="text-sm font-semibold tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(loan.outstanding, currency)}</p>
										<p className="text-[11px] text-slate-500 dark:text-slate-400">{loan.status === "Closed" ? "closed" : `${loan.installmentsLeft} EMIs left`}</p>
									</div>
								</div>
								<div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800" role="img" aria-label={`${formatPercent(loan.repaidPct)} repaid`}>
									<div className="h-full rounded-full bg-emerald-500" style={{ width: `${Math.min(100, Math.max(0, loan.repaidPct))}%` }} />
								</div>
								<div className="mt-1.5 flex flex-wrap items-center justify-between gap-2 text-[11px] text-slate-500 dark:text-slate-400">
									<span>
										EMI {formatMoney(emiThisMonth || loan.emi, currency)}
										{dueThisMonth ? ` · ${formatShortDate(dueThisMonth)}` : ""}
									</span>
									<Badge variant="outline" className={cn("border-0 font-medium", LOAN_BADGE[monthStatus])}>
										{monthStatus === "None" ? "No EMI this month" : monthStatus === "Due" ? "EMI due" : `EMI ${monthStatus.toLowerCase()}`}
									</Badge>
								</div>
							</li>
						))}
					</Rows>
				</>
			)}
		</Panel>
	);
}

type SectionNote = { text: string; tone: Tone };

function SectionTitle({ icon, text }: { icon: ReactNode; text: string }) {
	return (
		<span className="flex items-center gap-2">
			<span className="flex size-7 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300 [&_svg]:size-4" aria-hidden="true">
				{icon}
			</span>
			{text}
		</span>
	);
}

function PositionSkeleton() {
	return (
		<div aria-busy="true" aria-label="Loading">
			<Skeleton className="h-44 rounded-2xl" />
			<div className="mt-4 grid gap-4 xl:grid-cols-2">
				{[0, 1, 2, 3].map((i) => (
					<Skeleton key={i} className="h-80 rounded-2xl" />
				))}
			</div>
		</div>
	);
}

