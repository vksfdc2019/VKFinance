import { ArrowDownLeft, ArrowUpRight, Bell, CheckCircle2, Plus, ShoppingBag, TriangleAlert, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import { contrastRatio } from "@/theme/color";
import { themeColors, type ResolvedTheme } from "@/theme/themes";

/**
 * A small working copy of the app in the theme being chosen. It uses the same brand-* and dark:
 * classes as the real pages, so what you see here is what every page will look like.
 */
export function ThemePreview({ theme, currency = "INR" }: { theme: ResolvedTheme; currency?: string }) {
	const { primary, adjusted } = themeColors(theme);
	const ratio = contrastRatio(primary, "#ffffff");
	const money = (n: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency, maximumFractionDigits: 0 }).format(n);

	return (
		<div className="space-y-3" aria-label="Preview of your theme">
			<div className="overflow-hidden rounded-2xl bg-slate-50 dark:bg-slate-950 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
				{/* App bar */}
				<div className="flex items-center justify-between border-b border-slate-200/70 dark:border-slate-800/70 bg-white/85 dark:bg-slate-900/85 px-3 py-2">
					<div className="flex items-center gap-2">
						<span className="flex size-6 items-center justify-center rounded-lg bg-gradient-to-br from-brand-600 to-brand-alt-700 text-[10px] font-bold text-white">VK</span>
						<span className="text-xs font-semibold text-slate-900 dark:text-slate-100">VK Finance</span>
					</div>
					<div className="flex items-center gap-1.5 text-slate-500 dark:text-slate-400">
						<Bell className="size-3.5" aria-hidden="true" />
						<span className="size-5 rounded-full bg-gradient-to-br from-brand-600 to-brand-alt-700" />
					</div>
				</div>

				<div className="space-y-3 p-3">
					{/* Hero balance */}
					<div className="relative overflow-hidden rounded-xl bg-gradient-to-br from-brand-700 via-brand-800 to-brand-alt-900 p-4 text-white">
						<div className="pointer-events-none absolute -top-8 -right-8 size-24 rounded-full bg-white/10" />
						<p className="flex items-center gap-1.5 text-[11px] text-brand-100">
							<Wallet className="size-3.5" aria-hidden="true" />
							Net worth
						</p>
						<p className="mt-1 text-xl font-semibold tabular-nums">{money(842600)}</p>
						<p className="mt-2 inline-flex items-center gap-1 rounded-full bg-white/15 px-2 py-0.5 text-[10px]">
							<ArrowUpRight className="size-3" aria-hidden="true" />
							4.2% this month
						</p>
					</div>

					{/* Buttons */}
					<div className="flex flex-wrap gap-2">
						<Button size="sm" className="rounded-lg">
							<Plus />
							Add entry
						</Button>
						<Button size="sm" variant="outline" className="rounded-lg">
							Reports
						</Button>
						<span className="inline-flex items-center rounded-lg bg-brand-50 dark:bg-brand-950/40 px-2.5 text-xs font-medium text-brand-800 dark:text-brand-200 ring-1 ring-brand-600/15">
							Selected
						</span>
					</div>

					{/* Budget card */}
					<div className="rounded-xl bg-white dark:bg-slate-900 p-3 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
						<div className="flex items-center justify-between text-xs">
							<span className="font-medium text-slate-900 dark:text-slate-100">Groceries</span>
							<span className="text-slate-500 dark:text-slate-400 tabular-nums">{money(6200)} of {money(9000)}</span>
						</div>
						<div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
							<div className="h-full w-[69%] rounded-full bg-brand-600" />
						</div>
						<div className="mt-3 flex flex-wrap gap-1.5 text-[10px] font-medium">
							<span className="inline-flex items-center gap-1 rounded-full bg-emerald-50 dark:bg-emerald-950/40 px-2 py-0.5 text-emerald-700 dark:text-emerald-300">
								<CheckCircle2 className="size-3" aria-hidden="true" />
								On track
							</span>
							<span className="inline-flex items-center gap-1 rounded-full bg-amber-50 dark:bg-amber-950/40 px-2 py-0.5 text-amber-800 dark:text-amber-200">
								<TriangleAlert className="size-3" aria-hidden="true" />
								Bill due in 3 days
							</span>
						</div>
					</div>

					{/* Transactions */}
					<ul className="divide-y divide-slate-100 dark:divide-slate-800 rounded-xl bg-white dark:bg-slate-900 shadow-sm ring-1 ring-slate-900/5 dark:ring-white/10">
						{[
							{ icon: ShoppingBag, name: "Big Bazaar", meta: "Groceries · HDFC", amount: -2450 },
							{ icon: ArrowDownLeft, name: "Salary", meta: "Income · HDFC", amount: 120000 },
						].map((t) => (
							<li key={t.name} className="flex items-center gap-2.5 px-3 py-2">
								<span className="flex size-7 items-center justify-center rounded-lg bg-brand-50 dark:bg-brand-950/40 text-brand-700 dark:text-brand-300">
									<t.icon className="size-3.5" aria-hidden="true" />
								</span>
								<div className="min-w-0 flex-1">
									<p className="truncate text-xs font-medium text-slate-900 dark:text-slate-100">{t.name}</p>
									<p className="truncate text-[10px] text-slate-500 dark:text-slate-400">{t.meta}</p>
								</div>
								<span className={t.amount > 0 ? "text-xs font-semibold text-emerald-700 dark:text-emerald-300 tabular-nums" : "text-xs font-semibold text-slate-900 dark:text-slate-100 tabular-nums"}>
									{t.amount > 0 ? "+" : "−"}
									{money(Math.abs(t.amount))}
								</span>
							</li>
						))}
					</ul>
				</div>
			</div>

			<p className="flex items-start gap-2 rounded-xl bg-white dark:bg-slate-900 px-3 py-2 text-xs text-slate-600 dark:text-slate-400 ring-1 ring-slate-900/5 dark:ring-white/10">
				<CheckCircle2 className="mt-0.5 size-3.5 shrink-0 text-emerald-600 dark:text-emerald-400" aria-hidden="true" />
				<span>
					Button text contrast <strong className="font-semibold text-slate-900 dark:text-slate-100">{ratio.toFixed(1)}:1</strong> - meets WCAG AA
					{adjusted && " (your colour was darkened slightly for buttons so text stays readable)"}.
				</span>
			</p>
		</div>
	);
}
