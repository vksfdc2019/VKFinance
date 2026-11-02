import { Suspense } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router";
import {
	Archive,
	ArrowLeftRight,
	BarChart3,
	ChartPie,
	ChevronsUpDown,
	Landmark,
	LayoutDashboard,
	LifeBuoy,
	LogOut,
	Palette,
	Plus,
	ReceiptText,
	Repeat,
	Scale,
	ShieldCheck,
	Sparkles,
	Tags,
	Target,
	UserRound,
	Users,
	Wallet,
	type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuLabel,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { SessionTimeout } from "@/features/auth/SessionTimeout";
import { LedgerProvider, useLedger } from "@/features/ledger/LedgerContext";
import { BrandMark } from "./BrandMark";
import { NotificationBell } from "./NotificationBell";
import { ModeToggle } from "./ModeToggle";

interface NavItem {
	to: string;
	label: string;
	icon: LucideIcon;
	show: boolean;
	/** In the account menu at the foot of the sidebar on wide screens, so the list fits a laptop screen. */
	inAccountMenu?: boolean;
}

function initials(first?: string, last?: string) {
	return `${first?.[0] ?? ""}${last?.[0] ?? ""}`.toUpperCase() || "?";
}

export default function AppLayout() {
	return (
		<LedgerProvider>
			<Shell />
		</LedgerProvider>
	);
}

function Shell() {
	const { profile, can, logout } = useAuth();
	const { openEntry, canAdd } = useLedger();
	const navigate = useNavigate();
	const location = useLocation();
	const links: NavItem[] = [
		{ to: "/", label: "Overview", icon: LayoutDashboard, show: can("DASHBOARD:READ") },
		{ to: "/position", label: "Money position", icon: Scale, show: can("DASHBOARD:READ") },
		{ to: "/analytics", label: "Analytics", icon: ChartPie, show: can("DASHBOARD:READ") },
		{ to: "/transactions", label: "Transactions", icon: ArrowLeftRight, show: can("TRANSACTIONS:READ") },
		{ to: "/accounts", label: "Accounts", icon: Wallet, show: can("ACCOUNTS:READ") },
		{ to: "/budgets", label: "Budgets", icon: Target, show: can("BUDGETS:READ") },
		{ to: "/bills", label: "Bills", icon: ReceiptText, show: can("BILLS:READ") },
		{ to: "/loans", label: "Loans & EMIs", icon: Landmark, show: can("LOANS:READ") },
		{ to: "/recurring", label: "Recurring", icon: Repeat, show: can("RECURRING:READ") },
		{ to: "/reports", label: "Reports", icon: BarChart3, show: can("REPORTS:READ") },
		{ to: "/archive", label: "Archive", icon: Archive, show: can("TRANSACTIONS:READ") },
		{ to: "/enhancements", label: "Discover", icon: Sparkles, show: can("ENHANCEMENTS:READ") },
		{ to: "/categories", label: "Categories", icon: Tags, show: can("CATEGORIES:CREATE") },
		{ to: "/family", label: "Family", icon: Users, show: can("MEMBERS:CREATE") },
		{ to: "/profile", label: "Security", icon: ShieldCheck, show: true, inAccountMenu: true },
		{ to: "/appearance", label: "Appearance", icon: Palette, show: true, inAccountMenu: true },
		{ to: "/help", label: "Help", icon: LifeBuoy, show: true, inAccountMenu: true },
	].filter((link) => link.show);
	const avatar = initials(profile?.firstName, profile?.lastName);

	return (
		<div className="vk-app-bg min-h-svh">
			<aside className="no-print sticky top-0 z-30 border-b border-slate-200/70 dark:border-slate-800/70 bg-white/85 dark:bg-slate-900/85 backdrop-blur-md lg:fixed lg:inset-y-0 lg:left-0 lg:flex lg:h-svh lg:w-64 lg:flex-col lg:overflow-hidden lg:border-r lg:border-b-0">
				<div className="flex shrink-0 items-center justify-between gap-3 px-4 py-3 lg:px-5 lg:pt-5 lg:pb-4 [@media(max-height:760px)]:lg:pt-3 [@media(max-height:760px)]:lg:pb-2.5">
					<BrandMark />
					<div className="flex items-center gap-1">
					<ModeToggle />
					<NotificationBell />
					<DropdownMenu>
						<DropdownMenuTrigger asChild>
							<button
								type="button"
								aria-label="Account menu"
								className="flex size-9 items-center justify-center rounded-full bg-gradient-to-br from-brand-600 to-brand-alt-700 text-xs font-semibold text-white lg:hidden"
							>
								{avatar}
							</button>
						</DropdownMenuTrigger>
						<DropdownMenuContent align="end" className="w-56">
							<DropdownMenuLabel>
								<p className="font-medium">
									{profile?.firstName} {profile?.lastName}
								</p>
								<p className="text-xs font-normal text-muted-foreground">
									{profile?.role} · {profile?.familyName}
								</p>
							</DropdownMenuLabel>
							<DropdownMenuSeparator />
							<DropdownMenuItem onSelect={() => navigate("/profile")}>
								<UserRound />
								Profile &amp; security
							</DropdownMenuItem>
							<DropdownMenuItem onSelect={() => navigate("/appearance")}>
								<Palette />
								Appearance
							</DropdownMenuItem>
							<DropdownMenuItem onSelect={() => navigate("/help")}>
								<LifeBuoy />
								Help
							</DropdownMenuItem>
							<DropdownMenuItem onSelect={() => void logout("user")}>
								<LogOut />
								Sign out
							</DropdownMenuItem>
						</DropdownMenuContent>
					</DropdownMenu>
					</div>
				</div>

				{canAdd && (
					<div className="hidden shrink-0 px-4 pb-3 lg:block [@media(max-height:760px)]:lg:pb-2">
						<Button className="h-10 w-full rounded-xl shadow-sm shadow-brand-900/20 [@media(max-height:760px)]:lg:h-9" onClick={() => openEntry()}>
							<Plus />
							Add transaction
							<kbd className="ml-auto rounded bg-white/15 px-1.5 text-[10px] font-medium">N</kbd>
						</Button>
					</div>
				)}

				<nav aria-label="Main" className="vk-thin-scroll flex gap-1 overflow-x-auto px-3 pb-2.5 lg:min-h-0 lg:flex-1 lg:flex-col lg:gap-0.5 lg:overflow-x-hidden lg:overflow-y-auto lg:overscroll-contain lg:px-4 lg:pb-3">
					{links.map(({ to, label, icon: Icon, inAccountMenu }) => (
						<NavLink
							key={to}
							to={to}
							end={to === "/"}
							className={({ isActive }) =>
								cn(
									"flex shrink-0 items-center gap-2.5 rounded-xl px-3 py-2 text-sm font-medium whitespace-nowrap transition-colors lg:py-1.5 [@media(max-height:760px)]:lg:py-1",
									inAccountMenu && "lg:hidden",
									isActive
										? "bg-brand-50 dark:bg-brand-950/40 text-brand-900 dark:text-brand-100 ring-1 ring-brand-600/15"
										: "text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 hover:text-slate-900 dark:hover:text-slate-100",
								)
							}
						>
							<Icon className="size-4" aria-hidden="true" />
							{label}
						</NavLink>
					))}
				</nav>

				<div className="hidden shrink-0 border-t border-slate-200/70 dark:border-slate-800/70 px-4 py-3 lg:block">
					<DropdownMenu>
						<DropdownMenuTrigger asChild>
							<button
								type="button"
								aria-label="Account menu"
								className="flex w-full items-center gap-3 rounded-xl p-1.5 text-left transition-colors hover:bg-slate-100 dark:hover:bg-slate-800"
							>
								<span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-brand-600 to-brand-alt-700 text-xs font-semibold text-white">
									{avatar}
								</span>
								<span className="min-w-0 flex-1">
									<span className="block truncate text-sm font-medium text-slate-900 dark:text-slate-100">
										{profile?.firstName} {profile?.lastName}
									</span>
									<span className="block truncate text-xs text-slate-500 dark:text-slate-400">
										{profile?.role} · {profile?.familyCode}
									</span>
								</span>
								<ChevronsUpDown className="size-4 shrink-0 text-slate-400" aria-hidden="true" />
							</button>
						</DropdownMenuTrigger>
						<DropdownMenuContent side="top" align="start" className="w-56">
							<DropdownMenuLabel>
								<p className="font-medium">{profile?.familyName}</p>
								<p className="text-xs font-normal text-muted-foreground">Family code {profile?.familyCode}</p>
							</DropdownMenuLabel>
							<DropdownMenuSeparator />
							<DropdownMenuItem onSelect={() => navigate("/profile")}>
								<ShieldCheck />
								Security
							</DropdownMenuItem>
							<DropdownMenuItem onSelect={() => navigate("/appearance")}>
								<Palette />
								Appearance
							</DropdownMenuItem>
							<DropdownMenuItem onSelect={() => navigate("/help")}>
								<LifeBuoy />
								Help
							</DropdownMenuItem>
							<DropdownMenuSeparator />
							<DropdownMenuItem onSelect={() => void logout("user")}>
								<LogOut />
								Sign out
							</DropdownMenuItem>
						</DropdownMenuContent>
					</DropdownMenu>
					<Button variant="ghost" size="sm" className="mt-1 w-full justify-start text-slate-600 dark:text-slate-400 hover:text-red-700 dark:hover:text-red-300" onClick={() => void logout("user")}>
						<LogOut aria-hidden="true" />
						Sign out
					</Button>
				</div>
			</aside>

			<main className="lg:pl-64 print:pl-0">
				<div className="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
					<Suspense fallback={<PageLoading />}>
						<div key={location.pathname} className="vk-rise">
							<Outlet />
						</div>
					</Suspense>
				</div>
			</main>

			{canAdd && (
				<Button
					size="icon-lg"
					aria-label="Add transaction"
					className="fixed right-5 bottom-5 z-30 size-14 rounded-2xl shadow-lg shadow-brand-900/25 lg:hidden [&_svg]:size-6"
					onClick={() => openEntry()}
				>
					<Plus />
				</Button>
			)}
			<SessionTimeout />
		</div>
	);
}

function PageLoading() {
	return (
		<div className="space-y-4" aria-busy="true" aria-label="Loading">
			<div className="h-9 w-56 animate-pulse rounded-xl bg-slate-200/70 dark:bg-slate-700/70" />
			<div className="h-64 animate-pulse rounded-2xl bg-slate-200/50 dark:bg-slate-700/50" />
		</div>
	);
}
