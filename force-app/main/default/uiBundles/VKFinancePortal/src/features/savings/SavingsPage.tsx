import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { AlertTriangle, BadgeIndianRupee, HeartPulse, Info, MoreVertical, Pencil, Plus, ReceiptText, Shield, ShieldCheck, Sprout, Trash2, TrendingUp } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { AnimatedMoney, Reveal } from "@/components/finance/motion";
import { EmptyState, PageHeader, Panel, SegmentedControl, StatusMeter } from "@/components/finance/ui";
import { savingsApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Policy, Scheme, TaxSummary } from "@/api/savingsTypes";
import { formatMoney, formatShortDate } from "@/lib/format";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";
import { PolicyDialog, SchemeActionDialog, SchemeDialog, type SchemeAction } from "./SavingsDialogs";
import { SchemeCard } from "./SchemeCard";

type Tab = "schemes" | "insurance";

/** PPF, SSY, NSC and other Indian savings schemes, insurance policies, and the year's tax savings. */
export default function SavingsPage() {
	const { profile, can } = useAuth();
	const { version, refresh } = useLedger();
	const navigate = useNavigate();
	const [params, setParams] = useSearchParams();
	const tab: Tab = params.get("tab") === "insurance" ? "insurance" : "schemes";
	const { data, errors } = useAsync(() => savingsApi.portfolio(), [version]);
	const currency = data?.currencyCode ?? profile?.currencyCode ?? "INR";
	const canAdd = can("ACCOUNTS:CREATE");
	const [schemeDialog, setSchemeDialog] = useState<{ scheme?: Scheme } | null>(null);
	const [action, setAction] = useState<{ scheme: Scheme; action: SchemeAction } | null>(null);
	const [policyDialog, setPolicyDialog] = useState<{ policy?: Policy } | null>(null);

	const done = () => {
		setSchemeDialog(null);
		setAction(null);
		setPolicyDialog(null);
		refresh();
	};

	async function remove(kind: "scheme" | "policy", id: string, name: string) {
		try {
			if (kind === "scheme") await savingsApi.deleteScheme(id);
			else await savingsApi.deletePolicy(id);
			toast.success(`${name} deleted`);
			refresh();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	const setTab = (t: Tab) => {
		const next = new URLSearchParams(params);
		if (t === "schemes") next.delete("tab");
		else next.set("tab", t);
		setParams(next, { replace: true });
	};

	return (
		<>
			<PageHeader
				title="Savings & insurance"
				description="PPF, SSY, NSC, KVP, SCSS, Post Office schemes, NPS, EPF, gold bonds - and LIC, term and health policies"
				actions={
					canAdd && (
						<>
							<Button variant="outline" className="rounded-xl bg-white dark:bg-slate-900" onClick={() => setPolicyDialog({})}>
								<ShieldCheck />
								Add policy
							</Button>
							<Button className="rounded-xl" onClick={() => setSchemeDialog({})}>
								<Plus />
								Add scheme
							</Button>
						</>
					)
				}
			/>
			<FormErrors errors={errors} />
			{!data ? (
				errors.length === 0 && <SavingsSkeleton />
			) : (
				<>
					<Reveal index={0}>
						<Hero data={data} currency={currency} />
					</Reveal>
					{data.taxes.length > 0 && (
						<Reveal index={1} className="mt-4">
							<TaxPanel taxes={data.taxes} currency={currency} />
						</Reveal>
					)}
					<div className="mt-6 mb-4 flex flex-wrap items-center justify-between gap-3">
						<SegmentedControl
							label="Show"
							value={tab}
							onChange={setTab}
							options={[
								{ value: "schemes", label: `Schemes · ${data.schemes.length}` },
								{ value: "insurance", label: `Insurance · ${data.policies.length}` },
							]}
							className="w-full bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10 sm:w-auto"
						/>
					</div>
					{tab === "schemes" ? (
						data.schemes.length === 0 ? (
							<Panel>
								<EmptyState icon={<Sprout />} title="No savings schemes yet" action={canAdd && <Button onClick={() => setSchemeDialog({})}><Plus />Add PPF, NSC, SSY…</Button>}>
									Track PPF, Sukanya Samriddhi, NSC, KVP, SCSS, Post Office deposits, NPS, EPF and gold bonds - with maturity values and 80C.
								</EmptyState>
							</Panel>
						) : (
							<div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
								{data.schemes.map((s, i) => (
									<Reveal key={s.id} index={i + 2}>
										<SchemeCard
											scheme={s}
											currency={currency}
											onAction={(a) => setAction({ scheme: s, action: a })}
											onEdit={() => setSchemeDialog({ scheme: s })}
											onHistory={() => navigate(`/transactions?account=${s.accountId}`)}
											onDelete={() => void remove("scheme", s.id, s.name)}
										/>
									</Reveal>
								))}
							</div>
						)
					) : data.policies.length === 0 ? (
						<Panel>
							<EmptyState icon={<Shield />} title="No insurance policies yet" action={canAdd && <Button onClick={() => setPolicyDialog({})}><Plus />Add LIC or other policy</Button>}>
								Add LIC, term, health, vehicle or home policies. Premiums become bills with reminders, and count towards 80C and 80D.
							</EmptyState>
						</Panel>
					) : (
						<div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
							{data.policies.map((p, i) => (
								<Reveal key={p.id} index={i + 2}>
									<PolicyCard policy={p} currency={currency} onEdit={() => setPolicyDialog({ policy: p })} onPay={() => navigate("/bills")} onDelete={() => void remove("policy", p.id, p.insurer)} />
								</Reveal>
							))}
						</div>
					)}
				</>
			)}
			{schemeDialog && <SchemeDialog scheme={schemeDialog.scheme} onClose={() => setSchemeDialog(null)} onSaved={done} />}
			{action && <SchemeActionDialog scheme={action.scheme} action={action.action} currency={currency} onClose={() => setAction(null)} onSaved={done} />}
			{policyDialog && <PolicyDialog policy={policyDialog.policy} onClose={() => setPolicyDialog(null)} onSaved={done} />}
		</>
	);
}

function Hero({ data, currency }: { data: import("@/api/savingsTypes").SavingsPortfolio; currency: string }) {
	const tiles = [
		{ label: "Value at maturity", value: formatMoney(data.schemesMaturityValue, currency), hint: "Estimated at today's rates", icon: TrendingUp },
		{ label: "Life cover", value: formatMoney(data.lifeCover, currency), hint: "Sum assured, active policies", icon: ShieldCheck },
		{ label: "Health cover", value: formatMoney(data.healthCover, currency), hint: "Family floater and others", icon: HeartPulse },
		{ label: "Premiums a year", value: formatMoney(data.yearlyPremiums, currency), hint: "All active policies", icon: ReceiptText },
	];
	return (
		<section className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-brand-alt-700 via-brand-800 to-slate-900 p-5 text-white shadow-xl shadow-emerald-900/20 sm:p-7">
			<div className="pointer-events-none absolute -top-24 -right-16 size-72 rounded-full bg-emerald-300/20 blur-3xl" />
			<div className="pointer-events-none absolute -bottom-28 left-1/4 size-72 rounded-full bg-sky-300/10 blur-3xl" />
			<div className="relative grid gap-6 lg:grid-cols-[1fr_2fr] lg:items-center">
				<div>
					<p className="flex items-center gap-2 text-sm text-emerald-100/80">
						<Sprout className="size-4" aria-hidden="true" />
						In savings schemes today
					</p>
					<p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums sm:text-4xl">
						<AnimatedMoney value={data.schemesValue} currency={currency} />
					</p>
					<p className="mt-1 text-xs text-emerald-100/70">{data.schemes.filter((s) => s.status === "Active").length} active schemes · {data.financialYear}</p>
				</div>
				<dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
					{tiles.map((t) => (
						<div key={t.label} className="rounded-xl bg-white/10 px-3 py-2.5 ring-1 ring-white/10">
							<dt className="flex items-center gap-1.5 text-[11px] text-emerald-100/75">
								<t.icon className="size-3.5" aria-hidden="true" />
								{t.label}
							</dt>
							<dd className="mt-0.5 text-base font-semibold tabular-nums">{t.value}</dd>
							<dd className="text-[10px] text-emerald-100/60">{t.hint}</dd>
						</div>
					))}
				</dl>
			</div>
		</section>
	);
}

/** 80C, 80CCD(1B) and 80D for each person this financial year. */
function TaxPanel({ taxes, currency }: { taxes: TaxSummary[]; currency: string }) {
	const [who, setWho] = useState(taxes[0].ownerId);
	const t = taxes.find((x) => x.ownerId === who) ?? taxes[0];
	const bars = [
		{ label: "Section 80C", used: t.section80C, limit: t.limit80C, note: "PPF, SSY, NSC, SCSS, 5-yr TD, EPF, tax-saver FD, life premiums" },
		{ label: "Section 80CCD(1B)", used: t.section80CCD1B, limit: t.limit80CCD1B, note: "Your own NPS, over and above 80C" },
		{ label: "Section 80D", used: t.section80D, limit: t.limit80D, note: "Health premiums (Rs 50,000 if a senior citizen)" },
	];
	return (
		<Panel
			title={
				<span className="flex items-center gap-2">
					<span className="flex size-7 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300 [&_svg]:size-4" aria-hidden="true">
						<BadgeIndianRupee />
					</span>
					Tax savings · {t.financialYear}
				</span>
			}
			description="Old tax regime. The new regime (the default) does not allow these deductions."
			action={
				taxes.length > 1 && (
					<SegmentedControl label="Whose tax" value={who} onChange={setWho} options={taxes.map((x) => ({ value: x.ownerId, label: x.ownerName?.split(" ")[0] ?? "Member" }))} />
				)
			}
		>
			<div className="grid gap-6 lg:grid-cols-3">
				{bars.map((b) => {
					const left = Math.max(0, b.limit - b.used);
					return (
						<div key={b.label}>
							<div className="flex items-baseline justify-between gap-2">
								<p className="text-sm font-semibold text-slate-900 dark:text-slate-100">{b.label}</p>
								<p className="text-sm tabular-nums text-slate-700 dark:text-slate-300">
									<span className="font-semibold text-slate-900 dark:text-slate-100">{formatMoney(Math.min(b.used, b.limit), currency)}</span> / {formatMoney(b.limit, currency)}
								</p>
							</div>
							<StatusMeter
								className="mt-2"
								value={b.used}
								max={b.limit}
								status={b.used >= b.limit ? "good" : "warning"}
								label={b.used >= b.limit ? "Limit used in full" : `${formatMoney(left, currency)} more can be claimed`}
							/>
							<p className="mt-1 text-[11px] text-slate-500 dark:text-slate-400">{b.note}</p>
						</div>
					);
				})}
			</div>
			{(t.items80C.length > 0 || t.items80D.length > 0) && (
				<ul className="mt-5 grid gap-x-6 gap-y-1.5 border-t border-slate-100 dark:border-slate-800 pt-4 text-sm sm:grid-cols-2">
					{[...t.items80C.map((i) => ({ ...i, section: "80C" })), ...t.items80D.map((i) => ({ ...i, section: "80D" }))].map((i, n) => (
						<li key={n} className="flex items-center justify-between gap-3">
							<span className="min-w-0 truncate text-slate-700 dark:text-slate-300">
								<span className="mr-2 rounded bg-slate-100 dark:bg-slate-800 px-1.5 py-0.5 text-[10px] font-semibold text-slate-600 dark:text-slate-300">{i.section}</span>
								{i.label}
							</span>
							<span className="font-medium tabular-nums text-slate-900 dark:text-slate-100">{formatMoney(i.amount, currency)}</span>
						</li>
					))}
				</ul>
			)}
		</Panel>
	);
}

const STATE_BADGE: Record<Policy["premiumState"], string> = {
	Upcoming: "bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300",
	Due: "bg-amber-50 dark:bg-amber-950/40 text-amber-800 dark:text-amber-200",
	"In grace": "bg-orange-50 dark:bg-orange-950/40 text-orange-800 dark:text-orange-200",
	Overdue: "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
	Finished: "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-800 dark:text-emerald-200",
	None: "bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-400",
};

function PolicyCard({ policy: p, currency, onEdit, onPay, onDelete }: { policy: Policy; currency: string; onEdit: () => void; onPay: () => void; onDelete: () => void }) {
	const health = p.policyType === "Health";
	const Icon = health ? HeartPulse : p.policyType === "Vehicle" || p.policyType === "Home" ? Shield : ShieldCheck;
	const stateText =
		p.premiumState === "Due"
			? `Premium due ${formatShortDate(p.nextDueDate)}`
			: p.premiumState === "In grace"
				? `In grace till ${formatShortDate(p.graceEnds)} - pay now`
				: p.premiumState === "Overdue"
					? `Grace over ${formatShortDate(p.graceEnds)} - may lapse`
					: p.premiumState === "Finished"
						? "All premiums paid"
						: p.premiumState === "Upcoming"
							? `Next premium ${formatShortDate(p.nextDueDate)}`
							: p.status;
	return (
		<article className="vk-lift flex h-full flex-col rounded-2xl bg-white dark:bg-slate-900 p-5 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
			<div className="flex items-start gap-3">
				<span className={cn("flex size-11 shrink-0 items-center justify-center rounded-xl [&_svg]:size-5", health ? "bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-300" : "bg-sky-50 dark:bg-sky-950/40 text-sky-700 dark:text-sky-300")} aria-hidden="true">
					<Icon />
				</span>
				<div className="min-w-0 flex-1">
					<p className="truncate text-base font-semibold text-slate-900 dark:text-slate-100">{p.insurer}</p>
					<p className="truncate text-xs text-slate-500 dark:text-slate-400">{[p.planName, p.policyType, p.policyNumberMasked].filter(Boolean).join(" · ")}</p>
				</div>
				{p.canManage && (
					<DropdownMenu>
						<DropdownMenuTrigger asChild>
							<Button variant="ghost" size="icon-sm" aria-label={`Actions for ${p.insurer} policy`}>
								<MoreVertical />
							</Button>
						</DropdownMenuTrigger>
						<DropdownMenuContent align="end" className="w-48">
							{p.openInstanceId && (
								<DropdownMenuItem onSelect={onPay}>
									<ReceiptText />
									Pay premium
								</DropdownMenuItem>
							)}
							<DropdownMenuItem onSelect={onEdit}>
								<Pencil />
								Edit policy
							</DropdownMenuItem>
							<DropdownMenuSeparator />
							<DropdownMenuItem variant="destructive" onSelect={onDelete}>
								<Trash2 />
								Delete policy
							</DropdownMenuItem>
						</DropdownMenuContent>
					</DropdownMenu>
				)}
			</div>

			<dl className="mt-4 grid grid-cols-2 gap-3 text-sm">
				<div>
					<dt className="text-xs text-slate-500 dark:text-slate-400">{health ? "Cover" : "Sum assured"}</dt>
					<dd className="text-lg font-semibold tabular-nums text-slate-900 dark:text-slate-100">{p.sumAssured ? formatMoney(p.sumAssured, currency) : "—"}</dd>
				</div>
				<div>
					<dt className="text-xs text-slate-500 dark:text-slate-400">Premium</dt>
					<dd className="text-lg font-semibold tabular-nums text-slate-900 dark:text-slate-100">
						{p.premium ? formatMoney(p.premium, currency) : "—"}
						<span className="ml-1 text-xs font-normal text-slate-500 dark:text-slate-400">{p.frequency === "Single" ? "single" : p.frequency.toLowerCase()}</span>
					</dd>
				</div>
				<div>
					<dt className="text-xs text-slate-500 dark:text-slate-400">{p.insuredName ? "Insured" : "Holder"}</dt>
					<dd className="truncate font-medium text-slate-800 dark:text-slate-200">{p.insuredName ?? p.ownerName ?? "—"}</dd>
				</div>
				<div>
					<dt className="text-xs text-slate-500 dark:text-slate-400">{p.maturityValue ? "Maturity" : "Ends"}</dt>
					<dd className="font-medium tabular-nums text-slate-800 dark:text-slate-200">
						{p.maturityValue ? `${formatMoney(p.maturityValue, currency)} · ` : ""}
						{p.maturityDate ? p.maturityDate.slice(0, 4) : "—"}
					</dd>
				</div>
			</dl>

			<div className="mt-auto pt-4">
				<div className="flex flex-wrap items-center gap-1.5">
					<Badge variant="outline" className={cn("border-0 font-medium", STATE_BADGE[p.premiumState])}>
						{stateText}
					</Badge>
					{p.taxSection && <Badge variant="outline" className="border-0 bg-emerald-50 dark:bg-emerald-950/40 font-medium text-emerald-800 dark:text-emerald-200">{p.taxSection}</Badge>}
					{p.nominee && <Badge variant="outline" className="border-0 bg-slate-100 dark:bg-slate-800 font-normal text-slate-600 dark:text-slate-400">Nominee: {p.nominee}</Badge>}
				</div>
				{p.premiumState !== "None" && p.premiumState !== "Finished" && (
					<p className="mt-2 flex items-center gap-1.5 text-[11px] text-slate-500 dark:text-slate-400">
						<Info className="size-3" aria-hidden="true" />
						{p.graceDays}-day grace period for {p.frequency.toLowerCase()} premiums (IRDAI)
						{p.premiumsEnd ? ` · premiums end ${formatShortDate(p.premiumsEnd)} ${p.premiumsEnd.slice(0, 4)}` : ""}
					</p>
				)}
				{p.taxWarnings.map((w) => (
					<p key={w} className="mt-2 flex items-start gap-1.5 rounded-lg bg-amber-50 dark:bg-amber-950/30 px-2.5 py-1.5 text-[11px] text-amber-900 dark:text-amber-100">
						<AlertTriangle className="mt-0.5 size-3 shrink-0" aria-hidden="true" />
						{w}
					</p>
				))}
				{p.yearlyPremium > 0 && p.sumAssured && p.sumAssured > 0 && !health && (
					<p className="mt-2 text-[11px] text-slate-500 dark:text-slate-400">
						{formatMoney(p.yearlyPremium, currency)} a year · cover is {Math.round(p.sumAssured / p.yearlyPremium)}× the yearly premium
					</p>
				)}
			</div>
		</article>
	);
}

function SavingsSkeleton() {
	return (
		<div aria-busy="true" aria-label="Loading">
			<Skeleton className="h-44 rounded-3xl" />
			<Skeleton className="mt-4 h-40 rounded-2xl" />
			<div className="mt-6 grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
				{[0, 1, 2].map((i) => (
					<Skeleton key={i} className="h-64 rounded-2xl" />
				))}
			</div>
		</div>
	);
}
