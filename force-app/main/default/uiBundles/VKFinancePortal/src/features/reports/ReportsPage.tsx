import { Link } from "react-router";
import {
	BarChart3,
	CalendarRange,
	CreditCard,
	Gauge,
	Landmark,
	LineChart as LineIcon,
	PieChart,
	ReceiptText,
	ScrollText,
	ShieldCheck,
	Smartphone,
	Tags,
	Trash2,
	Users,
	type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { toast } from "@/components/ui/sonner";
import { Reveal } from "@/components/finance/motion";
import { PageHeader } from "@/components/finance/ui";
import { queryString, reportApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { ReportType } from "@/api/reportTypes";
import { useAsync } from "@/lib/useAsync";
import { useAuth } from "@/features/auth/AuthContext";

export interface ReportInfo {
	type: ReportType;
	title: string;
	text: string;
	icon: LucideIcon;
	tint: string;
	adminOnly?: boolean;
}

export const REPORT_GROUPS: { title: string; reports: ReportInfo[] }[] = [
	{
		title: "Spending",
		reports: [
			{ type: "summary", title: "Monthly summary", text: "Where this month's money came from and went.", icon: CalendarRange, tint: "bg-teal-50 text-teal-700" },
			{ type: "category", title: "Spending by category", text: "Drill from category to sub-category to entries.", icon: PieChart, tint: "bg-orange-50 text-orange-700" },
			{ type: "members", title: "Member spending", text: "Who spent what against their limit.", icon: Users, tint: "bg-violet-50 text-violet-700", adminOnly: true },
			{ type: "modes", title: "Payment modes", text: "UPI vs cash vs cards vs bank transfers.", icon: Smartphone, tint: "bg-sky-50 text-sky-700" },
		],
	},
	{
		title: "Planning",
		reports: [
			{ type: "trend", title: "Income vs spending", text: "Twelve months of saving, month by month.", icon: BarChart3, tint: "bg-emerald-50 text-emerald-700" },
			{ type: "budget", title: "Budget vs actual", text: "Which budgets are over, and by how much.", icon: Gauge, tint: "bg-amber-50 text-amber-700" },
			{ type: "forecast", title: "Cash-flow forecast", text: "Will there be enough in 30, 60 and 90 days?", icon: LineIcon, tint: "bg-indigo-50 text-indigo-700", adminOnly: true },
			{ type: "annual", title: "Annual summary", text: "Financial-year totals and tax-relevant items.", icon: ScrollText, tint: "bg-rose-50 text-rose-700", adminOnly: true },
		],
	},
	{
		title: "Accounts and commitments",
		reports: [
			{ type: "account", title: "Account statement", text: "Running balance for one account.", icon: Tags, tint: "bg-slate-100 text-slate-700" },
			{ type: "cards", title: "Credit cards", text: "Card spending, payments and limits used.", icon: CreditCard, tint: "bg-slate-100 text-slate-700" },
			{ type: "loans", title: "Loans and EMIs", text: "Outstanding, repaid and interest this year.", icon: Landmark, tint: "bg-stone-100 text-stone-700" },
			{ type: "bills", title: "Bills", text: "Paid on time or late, and yearly cost per biller.", icon: ReceiptText, tint: "bg-yellow-50 text-yellow-800", adminOnly: true },
		],
	},
	{
		title: "Security",
		reports: [
			{ type: "security", title: "Security and activity", text: "Sign-ins, sessions, locked accounts, recent changes.", icon: ShieldCheck, tint: "bg-red-50 text-red-700", adminOnly: true },
		],
	},
];

export const REPORT_INFO = Object.fromEntries(REPORT_GROUPS.flatMap((g) => g.reports).map((r) => [r.type, r])) as Record<ReportType, ReportInfo>;

export default function ReportsPage() {
	const { profile } = useAuth();
	const isAdmin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const { data: saved, reload } = useAsync(() => reportApi.saved(), []);
	let index = 0;

	async function remove(id: string, name: string) {
		try {
			await reportApi.remove(id);
			toast.success(`${name} deleted`);
			reload();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	return (
		<>
			<PageHeader title="Reports" description="Every view of your family's money - export any of them, print them, or save your favourite filters." />
			{saved && saved.length > 0 && (
				<section className="mb-8">
					<h2 className="mb-3 text-sm font-semibold text-slate-700">Saved reports</h2>
					<ul className="flex flex-wrap gap-2">
						{saved.map((s) => (
							<li key={s.id} className="vk-rise flex items-center gap-1 rounded-full bg-white py-1 pr-1 pl-3 text-sm shadow-sm ring-1 ring-slate-900/5">
								<Link to={`/reports/${s.reportType}${queryString(s.filters)}`} className="font-medium text-slate-800 hover:text-teal-700">
									{s.name}
								</Link>
								<span className="text-xs text-slate-400">· {REPORT_INFO[s.reportType]?.title ?? s.reportType}{s.shared ? (s.mine ? " · shared" : ` · from ${s.ownerName}`) : ""}</span>
								{(s.mine || profile?.role === "Family Admin") && (
									<Button variant="ghost" size="icon-xs" aria-label={`Delete ${s.name}`} onClick={() => void remove(s.id, s.name)}>
										<Trash2 />
									</Button>
								)}
							</li>
						))}
					</ul>
				</section>
			)}
			{REPORT_GROUPS.map((group) => {
				const visible = group.reports.filter((r) => isAdmin || !r.adminOnly);
				if (!visible.length) return null;
				return (
					<section key={group.title} className="mb-8">
						<h2 className="mb-3 text-sm font-semibold text-slate-700">{group.title}</h2>
						<div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
							{visible.map((r) => (
								<Reveal key={r.type} index={index++}>
									<Link
										to={`/reports/${r.type}`}
										className="vk-lift flex h-full flex-col rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-900/5 focus-visible:ring-2 focus-visible:ring-teal-600 focus-visible:outline-none"
									>
										<span className={`mb-3 flex size-10 items-center justify-center rounded-xl ${r.tint}`}>
											<r.icon className="size-5" aria-hidden="true" />
										</span>
										<span className="font-semibold text-slate-900">{r.title}</span>
										<span className="mt-1 text-sm text-slate-500">{r.text}</span>
									</Link>
								</Reveal>
							))}
						</div>
					</section>
				);
			})}
		</>
	);
}
