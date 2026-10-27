import {
	ArrowLeftRight,
	Baby,
	Banknote,
	BookOpen,
	Briefcase,
	Building2,
	Bus,
	Car,
	CircleEllipsis,
	Coffee,
	CreditCard,
	Dumbbell,
	Film,
	Fuel,
	Gamepad2,
	Gift,
	GraduationCap,
	HandCoins,
	HandHeart,
	HeartPulse,
	House,
	Landmark,
	Laptop,
	Music,
	PartyPopper,
	PawPrint,
	PiggyBank,
	Pill,
	Plane,
	Receipt,
	Rocket,
	Scale,
	ShieldCheck,
	Shirt,
	ShoppingBag,
	Smartphone,
	Sparkles,
	Stethoscope,
	Tag,
	TrendingUp,
	Tv,
	UtensilsCrossed,
	Wallet,
	Wifi,
	Zap,
	type LucideIcon,
} from "lucide-react";
import type { AccountColor, AccountType } from "@/api/financeTypes";
import { cn } from "@/lib/utils";

/** Icon names stored on categories (kebab-case lucide names) -> components. Only these are bundled. */
export const CATEGORY_ICONS: Record<string, LucideIcon> = {
	wallet: Wallet,
	"utensils-crossed": UtensilsCrossed,
	"party-popper": PartyPopper,
	"heart-pulse": HeartPulse,
	pill: Pill,
	house: House,
	zap: Zap,
	car: Car,
	"graduation-cap": GraduationCap,
	"shopping-bag": ShoppingBag,
	sparkles: Sparkles,
	baby: Baby,
	"hand-heart": HandHeart,
	"shield-check": ShieldCheck,
	tv: Tv,
	plane: Plane,
	gift: Gift,
	landmark: Landmark,
	receipt: Receipt,
	"paw-print": PawPrint,
	"circle-ellipsis": CircleEllipsis,
	"arrow-left-right": ArrowLeftRight,
	"credit-card": CreditCard,
	scale: Scale,
	tag: Tag,
	rocket: Rocket,
	coffee: Coffee,
	"book-open": BookOpen,
	briefcase: Briefcase,
	dumbbell: Dumbbell,
	music: Music,
	film: Film,
	bus: Bus,
	fuel: Fuel,
	smartphone: Smartphone,
	wifi: Wifi,
	stethoscope: Stethoscope,
	shirt: Shirt,
	laptop: Laptop,
	"gamepad-2": Gamepad2,
	"piggy-bank": PiggyBank,
	"trending-up": TrendingUp,
	banknote: Banknote,
};

export const CATEGORY_COLORS = [
	"#0f766e",
	"#059669",
	"#2563eb",
	"#4f46e5",
	"#7c3aed",
	"#c026d3",
	"#db2777",
	"#e11d48",
	"#ea580c",
	"#d97706",
	"#65a30d",
	"#0891b2",
	"#475569",
];

const FALLBACK_COLOR = "#64748b";

/** A rounded tile with the category's icon on a tint of its colour. Identity, not data encoding. */
export function CategoryChip({
	icon,
	color,
	size = "md",
	className,
}: {
	icon?: string;
	color?: string;
	size?: "sm" | "md" | "lg";
	className?: string;
}) {
	const Icon = (icon && CATEGORY_ICONS[icon]) || Tag;
	const tint = color ?? FALLBACK_COLOR;
	return (
		<span
			aria-hidden="true"
			className={cn(
				"inline-flex shrink-0 items-center justify-center rounded-xl",
				size === "sm" && "size-7 [&_svg]:size-3.5",
				size === "md" && "size-9 [&_svg]:size-4",
				size === "lg" && "size-11 [&_svg]:size-5",
				className,
			)}
			style={{ backgroundColor: `${tint}1a`, color: tint }}
		>
			<Icon strokeWidth={2.2} />
		</span>
	);
}

export const ACCOUNT_ICONS: Record<AccountType, LucideIcon> = {
	Savings: Landmark,
	Current: Building2,
	Cash: Banknote,
	"UPI Wallet": Smartphone,
	"Credit Card": CreditCard,
	"Fixed Deposit": PiggyBank,
	Investment: TrendingUp,
	Loan: HandCoins,
};

export const DEFAULT_ACCOUNT_COLOR: Record<AccountType, AccountColor> = {
	Savings: "teal",
	Current: "sky",
	Cash: "emerald",
	"UPI Wallet": "violet",
	"Credit Card": "slate",
	"Fixed Deposit": "amber",
	Investment: "indigo",
	Loan: "rose",
};

/** Full class strings so Tailwind keeps them. */
export const ACCOUNT_GRADIENTS: Record<AccountColor, string> = {
	teal: "from-teal-600 via-teal-700 to-emerald-800",
	emerald: "from-emerald-500 via-emerald-600 to-green-800",
	sky: "from-sky-500 via-sky-600 to-blue-800",
	indigo: "from-indigo-500 via-indigo-600 to-indigo-900",
	violet: "from-violet-500 via-violet-600 to-purple-900",
	rose: "from-rose-500 via-rose-600 to-pink-800",
	amber: "from-amber-500 via-orange-500 to-orange-700",
	orange: "from-orange-500 via-orange-600 to-red-700",
	slate: "from-slate-600 via-slate-700 to-slate-900",
	zinc: "from-zinc-500 via-zinc-600 to-zinc-800",
};

export const ACCOUNT_SWATCHES: Record<AccountColor, string> = {
	teal: "bg-teal-600",
	emerald: "bg-emerald-500",
	sky: "bg-sky-500",
	indigo: "bg-indigo-500",
	violet: "bg-violet-500",
	rose: "bg-rose-500",
	amber: "bg-amber-500",
	orange: "bg-orange-500",
	slate: "bg-slate-700",
	zinc: "bg-zinc-500",
};

export function accountColor(account: { color?: AccountColor; type: AccountType }): AccountColor {
	return account.color ?? DEFAULT_ACCOUNT_COLOR[account.type] ?? "teal";
}

export function AccountChip({ account, className }: { account: { color?: AccountColor; type: AccountType }; className?: string }) {
	const Icon = ACCOUNT_ICONS[account.type] ?? Wallet;
	return (
		<span
			aria-hidden="true"
			className={cn(
				"inline-flex size-9 shrink-0 items-center justify-center rounded-xl bg-gradient-to-br text-white shadow-sm [&_svg]:size-4",
				ACCOUNT_GRADIENTS[accountColor(account)],
				className,
			)}
		>
			<Icon strokeWidth={2.2} />
		</span>
	);
}
