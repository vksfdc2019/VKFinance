import { useMemo, useState } from "react";
import { Link } from "react-router";
import {
	BarChart3,
	ChevronDown,
	KeyRound,
	LifeBuoy,
	LockKeyhole,
	ReceiptText,
	Search,
	ShieldCheck,
	Target,
	Users,
	Wallet,
	ArrowLeftRight,
	type LucideIcon,
} from "lucide-react";
import { Input } from "@/components/ui/input";
import { PageHeader } from "@/components/finance/ui";
import { Reveal } from "@/components/finance/motion";
import { useAuth } from "@/features/auth/AuthContext";
import { cn } from "@/lib/utils";

interface Topic {
	id: string;
	title: string;
	icon: LucideIcon;
	tint: string;
	adminOnly?: boolean;
	items: { q: string; a: string }[];
}

/** The family user guide, in the app. docs/User_Guide.md is the printable version of the same help. */
const TOPICS: Topic[] = [
	{
		id: "start",
		title: "Signing in",
		icon: KeyRound,
		tint: "bg-teal-50 text-teal-700",
		items: [
			{
				q: "How do I sign in the first time?",
				a: "Your Family Admin gives you a username and a temporary password. Sign in with them and choose your own password straight away. The temporary password works for 24 hours.",
			},
			{
				q: "Why was I signed out?",
				a: "For safety you're signed out after 30 minutes without activity, and after 12 hours at most. You'll see a warning a minute before. Changing your password also signs out your other devices.",
			},
			{
				q: "I forgot my password.",
				a: "Use 'Forgot your password?' on the sign-in page. If your account has an email address you'll get a link that works for 30 minutes. Otherwise ask your Family Admin to reset it - they'll give you a new temporary password.",
			},
			{
				q: "My account is locked.",
				a: "After 5 wrong attempts the account locks for 30 minutes (longer if it keeps happening). Wait, or ask your Family Admin to unlock it from the Family page.",
			},
		],
	},
	{
		id: "two-step",
		title: "Two-step verification",
		icon: ShieldCheck,
		tint: "bg-emerald-50 text-emerald-700",
		items: [
			{
				q: "What is it, and should I turn it on?",
				a: "After your password, you also type a 6-digit code from an app on your phone. Someone who learns your password still can't get in. It's strongly recommended for Family Admins and Co-Admins.",
			},
			{
				q: "How do I set it up?",
				a: "Go to Security, choose 'Set up', confirm your password, scan the QR code with Google Authenticator, Microsoft Authenticator or a similar app, then type the code it shows. Save the 10 recovery codes somewhere safe, away from your phone.",
			},
			{
				q: "I don't have my phone.",
				a: "On the code screen choose 'Use a recovery code' and type one of your saved codes. Each code works once. Make a fresh set from Security when you're running low.",
			},
			{
				q: "I lost my phone and my recovery codes.",
				a: "Ask your Family Admin to choose 'Reset two-step' for you on the Family page. You can then sign in with your password and set it up again.",
			},
			{
				q: "The code is always wrong.",
				a: "Codes change every 30 seconds - type the newest one. If it still fails, make sure your phone sets its date and time automatically.",
			},
		],
	},
	{
		id: "money",
		title: "Recording money",
		icon: ArrowLeftRight,
		tint: "bg-sky-50 text-sky-700",
		items: [
			{
				q: "How do I add a transaction?",
				a: "Press 'Add transaction' (or the N key on a keyboard). Choose expense, income or transfer, the amount, the account and a category. Balances and budgets update instantly.",
			},
			{
				q: "How do I move money between my own accounts?",
				a: "Add a transfer. It records both sides at once, so neither account's balance is counted as spending or income. Paying a credit card bill is a transfer from your bank to the card.",
			},
			{
				q: "I made a mistake.",
				a: "Open the transaction to edit it, or void it. Voiding keeps a record but takes it out of balances and reports. Children can change their own entries for 24 hours.",
			},
			{
				q: "Who sees my transactions?",
				a: "Family Admins and Co-Admins see the whole family. Members see their own accounts and shared ones. Viewers can look but not change anything. Another family never sees anything of yours.",
			},
		],
	},
	{
		id: "accounts",
		title: "Accounts and cards",
		icon: Wallet,
		tint: "bg-indigo-50 text-indigo-700",
		items: [
			{
				q: "What should I add as an account?",
				a: "Anything that holds or owes money: bank accounts, cash, UPI wallets, credit cards, loans, fixed deposits and investments. Add the balance on the day you start as the opening balance.",
			},
			{
				q: "Do you need my card number?",
				a: "No - only the last 4 digits, so you can tell cards apart. Never type a full card number, CVV, PIN or bank password anywhere in VK Finance.",
			},
			{
				q: "My balance doesn't match the bank.",
				a: "Check for missing or duplicate entries in Transactions for that account. Every night VK Finance also re-adds each account from its history and fixes any difference.",
			},
		],
	},
	{
		id: "plans",
		title: "Budgets, bills and loans",
		icon: Target,
		tint: "bg-amber-50 text-amber-700",
		items: [
			{
				q: "How do budgets work?",
				a: "Set an amount per category for the month. The bars turn amber near the limit and red when you go over, and the bell tells admins at 80% and 100%.",
			},
			{
				q: "How do bill reminders work?",
				a: "Add each bill once with its due day. VK Finance creates the bill every month, reminds you before it's due, and can pay it automatically from an account you choose.",
			},
			{
				q: "How are EMIs tracked?",
				a: "Add the loan with its amount, rate and tenure. VK Finance works out the EMI schedule, reminds you before each EMI and keeps the outstanding balance up to date as you pay.",
			},
			{
				q: "What are recurring entries?",
				a: "Salary, rent, SIPs and other regular amounts. Choose to post them automatically or to get a suggestion you confirm.",
			},
		],
	},
	{
		id: "reports",
		title: "Reports",
		icon: BarChart3,
		tint: "bg-violet-50 text-violet-700",
		items: [
			{
				q: "Which reports are there?",
				a: "Thirteen, from the monthly summary and spending by category to the cash-flow forecast, credit cards, loans, bills and the annual summary. Some are for admins only.",
			},
			{
				q: "Can I export or print?",
				a: "Yes. Every report has Export CSV (opens in Excel or Google Sheets) and Print - choose 'Save as PDF' in the print window for a PDF.",
			},
			{
				q: "Can I keep a report with my filters?",
				a: "Choose Save on the report. Saved reports appear at the top of Reports; tick 'share' to let the rest of the family use it too.",
			},
		],
	},
	{
		id: "family",
		title: "Managing the family",
		icon: Users,
		tint: "bg-rose-50 text-rose-700",
		adminOnly: true,
		items: [
			{
				q: "How do I add someone?",
				a: "On Family choose 'Add member', pick their role and give them the username and temporary password shown once on screen.",
			},
			{
				q: "What can each role do?",
				a: "Family Admin: everything, including managing admins. Co-Admin: everything except managing Family Admins. Member: their own and shared money. Child: their own accounts, with edits allowed for 24 hours. Viewer: read only.",
			},
			{
				q: "Why does it ask for my password again?",
				a: "Changing roles, resetting someone's password or two-step, and removing members are sensitive. You confirm with your password - and a code if you have two-step on - so nobody can do it from your unlocked device.",
			},
			{
				q: "Someone left the family.",
				a: "Choose 'Remove from family'. Their sign-in and secrets are deleted; the transactions they recorded stay in your history.",
			},
		],
	},
	{
		id: "privacy",
		title: "Privacy and safety",
		icon: LockKeyhole,
		tint: "bg-slate-100 text-slate-700",
		items: [
			{
				q: "How is my password stored?",
				a: "Never as text. It's salted and hashed thousands of times, so not even the people running VK Finance can read it.",
			},
			{
				q: "How do I know nobody else is using my account?",
				a: "Security shows every device signed in and your recent sign-ins and changes. Sign out anything you don't recognise and change your password.",
			},
			{
				q: "What should I do if something looks wrong?",
				a: "Change your password, sign out other devices, turn on two-step verification and tell your Family Admin. Admins are told automatically when an account gets locked.",
			},
		],
	},
];

const SHORTCUTS = [
	["N", "Add a transaction"],
	["Esc", "Close a dialog"],
	["Tab / Shift+Tab", "Move between fields"],
];

export default function HelpPage() {
	const { profile } = useAuth();
	const admin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	const [query, setQuery] = useState("");
	const [open, setOpen] = useState<string | null>(null);

	const topics = useMemo(() => {
		const q = query.trim().toLowerCase();
		return TOPICS.filter((t) => admin || !t.adminOnly)
			.map((t) => ({
				...t,
				items: q ? t.items.filter((i) => `${t.title} ${i.q} ${i.a}`.toLowerCase().includes(q)) : t.items,
			}))
			.filter((t) => t.items.length > 0);
	}, [query, admin]);

	return (
		<>
			<title>Help · VK Finance</title>
			<PageHeader title="Help" description="Short answers to the questions families ask most." />
			<div className="relative mb-6 max-w-xl">
				<Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-slate-400" aria-hidden="true" />
				<Input
					value={query}
					onChange={(e) => setQuery(e.target.value)}
					placeholder="Search help, e.g. recovery code"
					className="h-11 rounded-xl bg-white pl-9"
					aria-label="Search help"
				/>
			</div>
			<nav aria-label="Topics" className="mb-6 flex flex-wrap gap-2">
				{topics.map((t) => (
					<a
						key={t.id}
						href={`#${t.id}`}
						className="rounded-full bg-white px-3 py-1.5 text-sm text-slate-700 shadow-sm ring-1 ring-slate-900/5 hover:text-teal-800"
					>
						{t.title}
					</a>
				))}
			</nav>
			{topics.length === 0 && (
				<p className="py-10 text-center text-sm text-slate-500">No help matches “{query}”. Try another word, or ask your Family Admin.</p>
			)}
			<div className="grid gap-6 lg:grid-cols-2">
				{topics.map((t, ti) => (
					<Reveal key={t.id} index={ti}>
						<section id={t.id} className="scroll-mt-6 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-900/5">
							<h2 className="mb-3 flex items-center gap-3 text-base font-semibold text-slate-900">
								<span className={cn("flex size-9 items-center justify-center rounded-xl", t.tint)}>
									<t.icon className="size-5" aria-hidden="true" />
								</span>
								{t.title}
							</h2>
							<ul className="divide-y divide-slate-100">
								{t.items.map((item) => {
									const key = `${t.id}:${item.q}`;
									const expanded = open === key || query.trim().length > 0;
									return (
										<li key={key}>
											<button
												type="button"
												className="flex w-full items-center justify-between gap-3 py-3 text-left text-sm font-medium text-slate-800 hover:text-teal-800"
												aria-expanded={expanded}
												onClick={() => setOpen(open === key ? null : key)}
											>
												{item.q}
												<ChevronDown className={cn("size-4 shrink-0 text-slate-400 transition-transform", expanded && "rotate-180")} aria-hidden="true" />
											</button>
											{expanded && <p className="vk-rise pb-3 text-sm leading-relaxed text-slate-600">{item.a}</p>}
										</li>
									);
								})}
							</ul>
						</section>
					</Reveal>
				))}
			</div>
			<div className="mt-6 grid gap-6 lg:grid-cols-2">
				<section className="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-slate-900/5">
					<h2 className="mb-3 flex items-center gap-2 text-base font-semibold text-slate-900">
						<ReceiptText className="size-5 text-slate-400" aria-hidden="true" />
						Keyboard shortcuts
					</h2>
					<dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
						{SHORTCUTS.map(([keys, action]) => (
							<div key={keys} className="contents">
								<dt>
									<kbd className="rounded-md bg-slate-100 px-2 py-0.5 font-mono text-xs text-slate-700 ring-1 ring-slate-900/10">{keys}</kbd>
								</dt>
								<dd className="text-slate-600">{action}</dd>
							</div>
						))}
					</dl>
				</section>
				<section className="flex items-start gap-4 rounded-2xl bg-gradient-to-br from-teal-50 to-white p-5 shadow-sm ring-1 ring-slate-900/5">
					<LifeBuoy className="mt-0.5 size-6 shrink-0 text-teal-700" aria-hidden="true" />
					<div className="text-sm text-slate-700">
						<h2 className="mb-1 text-base font-semibold text-slate-900">Still stuck?</h2>
						Ask your Family Admin - they can unlock accounts, reset passwords and two-step, and change roles. To keep your own account safe, visit{" "}
						<Link to="/profile" className="font-medium text-teal-800 underline-offset-4 hover:underline">
							Security
						</Link>
						.
					</div>
				</section>
			</div>
		</>
	);
}
