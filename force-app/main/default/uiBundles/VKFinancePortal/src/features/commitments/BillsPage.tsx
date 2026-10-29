import { useEffect, useState, type FormEvent } from "react";
import { CalendarCheck2, MoreHorizontal, Pencil, Plus, ReceiptText, SkipForward, Zap } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { CategoryChip } from "@/components/finance/icons";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { EmptyState, PageHeader, Panel } from "@/components/finance/ui";
import { commitmentApi, familyApi, financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Account, Category } from "@/api/financeTypes";
import type { Member } from "@/api/types";
import { BILL_FREQUENCIES, type Bill, type BillInstance } from "@/api/commitmentTypes";
import { currencySymbol, formatDate, formatMoney, formatShortDate, todayIso } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { CategoryPicker } from "@/features/ledger/CategoryPicker";
import { useLedger } from "@/features/ledger/LedgerContext";
import { DueBadge, PayBillDialog } from "./shared";

export default function BillsPage() {
	const { version, refresh, currency } = useLedger();
	const { data, errors, loading } = useAsync(() => commitmentApi.bills(), [version]);
	const [paying, setPaying] = useState<BillInstance | null>(null);
	const [editing, setEditing] = useState<Bill | "new" | null>(null);

	async function skip(i: BillInstance) {
		try {
			await commitmentApi.skipBill(i.id);
			toast.success(`${i.billName} skipped this time`);
			refresh();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	const overdue = data?.open.filter((i) => i.status === "Overdue") ?? [];
	const thisWeek = data?.open.filter((i) => i.status !== "Overdue" && i.daysLeft <= 7) ?? [];
	const later = data?.open.filter((i) => i.status !== "Overdue" && i.daysLeft > 7) ?? [];
	const paidYear = data?.bills.reduce((s, b) => s + b.paidLast12Months, 0) ?? 0;

	return (
		<>
			<PageHeader
				title="Bills"
				description="Every recurring bill in one place - reminders before they're due, and auto-pay if you want it."
				actions={
					data?.canEdit && (
						<Button onClick={() => setEditing("new")}>
							<Plus />
							Add bill
						</Button>
					)
				}
			/>
			<FormErrors errors={errors} />
			{!data && loading ? (
				<div className="grid gap-4 md:grid-cols-3">
					{[0, 1, 2].map((i) => (
						<Skeleton key={i} className="h-28 rounded-2xl" />
					))}
				</div>
			) : data && data.bills.length === 0 ? (
				<Panel>
					<EmptyState
						icon={<ReceiptText />}
						title="No bills yet"
						action={
							data.canEdit && (
								<Button onClick={() => setEditing("new")}>
									<Plus />
									Add your first bill
								</Button>
							)
						}
					>
						Electricity, internet, school fees, insurance - add them once and VK Finance reminds you before each one is due.
					</EmptyState>
				</Panel>
			) : (
				data && (
					<>
						<div className="mb-6 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
							<Reveal index={0}>
								<Stat label="Overdue" tone={data.overdue > 0 ? "bad" : "ok"} value={<AnimatedMoney value={data.overdue} currency={currency} />} />
							</Reveal>
							<Reveal index={1}>
								<Stat label="Due in the next 30 days" value={<AnimatedMoney value={data.dueNext30} currency={currency} />} />
							</Reveal>
							<Reveal index={2}>
								<Stat label="Paid in the last 12 months" value={<AnimatedMoney value={paidYear} currency={currency} />} />
							</Reveal>
							<Reveal index={3}>
								<Stat label="On auto-pay" value={`${data.bills.filter((b) => b.autoPay && b.active).length} of ${data.bills.filter((b) => b.active).length}`} />
							</Reveal>
						</div>

						<div className="grid gap-6 xl:grid-cols-[1fr_22rem]">
							<div className="space-y-6">
								{[
									{ title: "Overdue", rows: overdue },
									{ title: "Due this week", rows: thisWeek },
									{ title: "Coming up", rows: later },
								]
									.filter((g) => g.rows.length)
									.map((group, gi) => (
										<section key={group.title}>
											<h2 className={cn("mb-2 text-sm font-semibold", group.title === "Overdue" ? "text-red-700 dark:text-red-300" : "text-slate-700 dark:text-slate-300")}>{group.title}</h2>
											<ul className="space-y-2">
												{group.rows.map((i, index) => (
													<Reveal as="li" key={i.id} index={gi * 3 + index}>
														<div
															className={cn(
																"vk-lift flex flex-wrap items-center gap-3 rounded-2xl bg-white dark:bg-slate-900 p-4 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10",
																i.status === "Overdue" && "ring-red-200 dark:ring-red-800",
															)}
														>
															<CategoryChip icon={i.icon} color={i.color} size="lg" />
															<div className="min-w-0 flex-1">
																<p className="truncate font-semibold text-slate-900 dark:text-slate-100">{i.billName}</p>
																<p className="truncate text-xs text-slate-500 dark:text-slate-400">
																	{formatDate(i.dueDate)}
																	{i.responsibleName ? ` · ${i.responsibleName}` : ""}
																	{i.autoPay ? " · auto-pay" : ""}
																</p>
															</div>
															<div className="text-right">
																<p className="font-semibold tabular-nums text-slate-900 dark:text-slate-100">
																	{formatMoney((i.amountDue ?? 0) - (i.amountPaid ?? 0), currency)}
																</p>
																<DueBadge status={i.status} daysLeft={i.daysLeft} />
															</div>
															<div className="flex items-center gap-1">
																{i.canPay && (
																	<Button size="sm" onClick={() => setPaying(i)}>
																		Pay
																	</Button>
																)}
																{data.canEdit && (
																	<DropdownMenu>
																		<DropdownMenuTrigger asChild>
																			<Button variant="ghost" size="icon-sm" aria-label={`More for ${i.billName}`}>
																				<MoreHorizontal />
																			</Button>
																		</DropdownMenuTrigger>
																		<DropdownMenuContent align="end">
																			<DropdownMenuItem onSelect={() => void skip(i)} disabled={(i.amountPaid ?? 0) > 0}>
																				<SkipForward />
																				Skip this time
																			</DropdownMenuItem>
																			<DropdownMenuItem onSelect={() => setEditing(data.bills.find((b) => b.id === i.billId) ?? null)}>
																				<Pencil />
																				Edit bill
																			</DropdownMenuItem>
																		</DropdownMenuContent>
																	</DropdownMenu>
																)}
															</div>
														</div>
													</Reveal>
												))}
											</ul>
										</section>
									))}
								{data.open.length === 0 && (
									<Panel>
										<EmptyState icon={<CalendarCheck2 />} title="All caught up">
											Nothing is due in the next three months.
										</EmptyState>
									</Panel>
								)}
							</div>

							<div className="space-y-4">
								<Panel title="Your billers" description={`${data.bills.length} saved`} bodyClassName="px-3 pb-3">
									<ul className="space-y-0.5">
										{data.bills.map((b) => (
											<li key={b.id}>
												<button
													type="button"
													disabled={!data.canEdit}
													onClick={() => setEditing(b)}
													className={cn("flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left enabled:hover:bg-slate-50 dark:enabled:hover:bg-slate-800/60", !b.active && "opacity-50")}
												>
													<CategoryChip icon={b.icon} color={b.color} size="sm" />
													<span className="min-w-0 flex-1">
														<span className="block truncate text-sm font-medium text-slate-900 dark:text-slate-100">{b.name}</span>
														<span className="block truncate text-xs text-slate-500 dark:text-slate-400">
															{b.frequency}
															{b.active && b.nextDueDate ? ` · next ${formatShortDate(b.nextDueDate)}` : b.active ? "" : " · paused"}
														</span>
													</span>
													{b.autoPay && (
														<Badge variant="secondary" className="gap-1">
															<Zap className="size-3" aria-hidden="true" />
															Auto
														</Badge>
													)}
													<span className="text-sm tabular-nums text-slate-700 dark:text-slate-300">{b.expectedAmount ? formatMoney(b.expectedAmount, currency) : "—"}</span>
												</button>
											</li>
										))}
									</ul>
								</Panel>
								{data.recentlyPaid.length > 0 && (
									<Panel title="Recently paid" bodyClassName="px-4 pb-4">
										<ul className="space-y-2 text-sm">
											{data.recentlyPaid.slice(0, 6).map((i) => (
												<li key={i.id} className="flex items-center justify-between gap-2">
													<span className="truncate text-slate-700 dark:text-slate-300">{i.billName}</span>
													<span className="shrink-0 text-xs text-slate-500 dark:text-slate-400">
														{formatMoney(i.amountPaid ?? 0, currency)} · {formatShortDate(i.dueDate)}
													</span>
												</li>
											))}
										</ul>
									</Panel>
								)}
							</div>
						</div>
					</>
				)
			)}

			{paying && (
				<PayBillDialog
					instance={paying}
					currency={currency}
					onClose={() => setPaying(null)}
					onPaid={() => {
						setPaying(null);
						refresh();
					}}
				/>
			)}
			{editing && (
				<BillDialog
					bill={editing === "new" ? undefined : editing}
					currency={currency}
					onClose={() => setEditing(null)}
					onSaved={() => {
						setEditing(null);
						refresh();
					}}
				/>
			)}
		</>
	);
}

function Stat({ label, value, tone }: { label: string; value: React.ReactNode; tone?: "bad" | "ok" }) {
	return (
		<div className={cn("rounded-2xl px-5 py-4 shadow-sm ring-1", tone === "bad" ? "bg-red-50 dark:bg-red-950/40 ring-red-200 dark:ring-red-800" : "bg-white dark:bg-slate-900 ring-slate-900/5 dark:ring-white/10")}>
			<p className={cn("text-xs", tone === "bad" ? "text-red-700 dark:text-red-300" : "text-slate-500 dark:text-slate-400")}>{label}</p>
			<p className={cn("mt-1 text-xl font-semibold tabular-nums", tone === "bad" ? "text-red-800 dark:text-red-200" : "text-slate-900 dark:text-slate-100")}>{value}</p>
		</div>
	);
}

function BillDialog({ bill, currency, onClose, onSaved }: { bill?: Bill; currency: string; onClose: () => void; onSaved: () => void }) {
	const { profile } = useAuth();
	const { loadCategories } = useLedger();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [name, setName] = useState(bill?.name ?? "");
	const [categoryId, setCategoryId] = useState(bill?.categoryId ?? "");
	const [frequency, setFrequency] = useState<string>(bill?.frequency ?? "Monthly");
	const [nextDue, setNextDue] = useState(bill?.nextDueDate ?? todayIso());
	const [amount, setAmount] = useState(bill?.expectedAmount ? String(bill.expectedAmount) : "");
	const [accountId, setAccountId] = useState(bill?.payFromAccountId ?? "none");
	const [creditCardId, setCreditCardId] = useState(bill?.creditCardAccountId ?? "none");
	const [autoPay, setAutoPay] = useState(bill?.autoPay ?? false);
	const [reminder, setReminder] = useState(String(bill?.reminderDays ?? 3));
	const [responsible, setResponsible] = useState(bill?.responsibleId ?? profile?.userId ?? "");
	const [consumerNo, setConsumerNo] = useState(bill?.consumerNo ?? "");
	const [active, setActive] = useState(bill?.active ?? true);
	const [refs, setRefs] = useState<{ categories: Category[]; accounts: Account[]; members: Member[] }>();
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	useEffect(() => {
		Promise.all([loadCategories(), financeApi.accounts(), isAdmin ? familyApi.members() : Promise.resolve([])])
			.then(([categories, accounts, members]) => setRefs({ categories, accounts: accounts.filter((a) => a.canUse && a.type !== "Loan"), members }))
			.catch((error: unknown) => setErrors(errorMessages(error)));
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	async function submit(e: FormEvent) {
		e.preventDefault();
		setSaving(true);
		try {
			const input = {
				name: name.trim(),
				categoryId,
				frequency,
				nextDueDate: nextDue,
				expectedAmount: amount ? Number(amount.replace(/,/g, "")) : null,
				payFromAccountId: accountId === "none" ? null : accountId,
				creditCardAccountId: creditCardId === "none" ? null : creditCardId,
				autoPay,
				reminderDays: Number(reminder) || 0,
				consumerNo: consumerNo.trim() || null,
				...(isAdmin ? { responsibleId: responsible || null } : {}),
				...(bill ? { active } : {}),
			};
			if (bill) await commitmentApi.updateBill(bill.id, input);
			else await commitmentApi.createBill(input);
			toast.success(bill ? "Bill updated" : `${input.name} added - we'll remind you before it's due`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-lg">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>{bill ? `Edit ${bill.name}` : "Add a bill"}</DialogTitle>
						<DialogDescription>Reminders go to the person responsible a few days before each due date.</DialogDescription>
					</DialogHeader>
					<div className="grid gap-3 sm:grid-cols-2">
						<TextField id="bill-name" label="Biller" placeholder="e.g. BESCOM, Airtel Fiber" value={name} maxLength={80} onChange={(e) => setName(e.target.value)} />
						<TextField id="bill-consumer" label="Consumer / account no" value={consumerNo} maxLength={40} onChange={(e) => setConsumerNo(e.target.value)} />
					</div>
					<div className="grid gap-1.5">
						<Label htmlFor="bill-credit-card">Credit card this bill repays</Label>
						<Select value={creditCardId} onValueChange={setCreditCardId}>
							<SelectTrigger id="bill-credit-card" className="w-full"><SelectValue /></SelectTrigger>
							<SelectContent>
								<SelectItem value="none">Regular bill</SelectItem>
								{refs?.accounts.filter((a) => a.type === "Credit Card").map((a) => (
									<SelectItem key={a.id} value={a.id}>{a.name}</SelectItem>
								))}
							</SelectContent>
						</Select>
						<p className="text-xs text-slate-500 dark:text-slate-400">Choose a card to show this bill on its account. Payments reduce the card balance.</p>
					</div>
					<div className="grid gap-1.5">
						<Label htmlFor="bill-category">Category</Label>
						{refs ? (
							<CategoryPicker id="bill-category" categories={refs.categories} kind="Expense" value={categoryId} onChange={setCategoryId} />
						) : (
							<div className="h-10 animate-pulse rounded-lg bg-slate-100 dark:bg-slate-800" />
						)}
					</div>
					<div className="grid gap-3 sm:grid-cols-3">
						<div className="grid gap-1.5">
							<Label htmlFor="bill-frequency">Comes</Label>
							<Select value={frequency} onValueChange={setFrequency}>
								<SelectTrigger id="bill-frequency" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									{BILL_FREQUENCIES.map((f) => (
										<SelectItem key={f} value={f}>
											{f}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<TextField id="bill-due" label="Next due" type="date" value={nextDue} onChange={(e) => setNextDue(e.target.value)} />
						<div className="grid gap-1.5">
							<Label htmlFor="bill-amount">Usual amount</Label>
							<div className="relative">
								<span className="pointer-events-none absolute top-1/2 left-3 -translate-y-1/2 text-sm text-slate-400">{currencySymbol(currency)}</span>
								<Input id="bill-amount" inputMode="decimal" className="pl-7" value={amount} onChange={(e) => setAmount(e.target.value)} />
							</div>
						</div>
					</div>
					<div className="grid gap-3 sm:grid-cols-2">
						<div className="grid gap-1.5">
							<Label htmlFor="bill-account">Usually paid from</Label>
							<Select value={accountId} onValueChange={setAccountId}>
								<SelectTrigger id="bill-account" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									<SelectItem value="none">Decide when paying</SelectItem>
									{refs?.accounts.filter((a) => creditCardId === "none" || !a.isLiability).map((a) => (
										<SelectItem key={a.id} value={a.id}>
											{a.name}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
						<TextField
							id="bill-reminder"
							label="Remind me (days before)"
							inputMode="numeric"
							value={reminder}
							onChange={(e) => setReminder(e.target.value.replace(/\D/g, "").slice(0, 2))}
						/>
					</div>
					{isAdmin && refs && refs.members.length > 1 && (
						<div className="grid gap-1.5">
							<Label htmlFor="bill-owner">Responsible</Label>
							<Select value={responsible} onValueChange={setResponsible}>
								<SelectTrigger id="bill-owner" className="w-full">
									<SelectValue />
								</SelectTrigger>
								<SelectContent>
									{refs.members.map((m) => (
										<SelectItem key={m.id} value={m.id}>
											{m.firstName} {m.lastName}
										</SelectItem>
									))}
								</SelectContent>
							</Select>
						</div>
					)}
					<label className="flex items-start gap-2.5 rounded-xl bg-brand-50/60 dark:bg-brand-950/40 p-3 text-sm ring-1 ring-brand-700/10">
						<Checkbox checked={autoPay} onCheckedChange={(v) => setAutoPay(v === true)} className="mt-0.5" />
						<span>
							<span className="font-medium text-slate-900 dark:text-slate-100">Auto-pay on the due date</span>
							<span className="block text-xs text-slate-600 dark:text-slate-400">Records the usual amount from the chosen account automatically each morning it&apos;s due.</span>
						</span>
					</label>
					{bill && (
						<label className="flex items-center gap-2.5 text-sm">
							<Checkbox checked={active} onCheckedChange={(v) => setActive(v === true)} />
							Active (untick to pause this bill)
						</label>
					)}
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving || !refs}>
							{saving && <Spinner />}
							{bill ? "Save" : "Add bill"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
