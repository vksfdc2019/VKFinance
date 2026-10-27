import { Link } from "react-router";
import { CategoryChip } from "@/components/finance/icons";
import { formatMoney } from "@/lib/format";

interface Item {
	categoryId?: string;
	name: string;
	icon?: string;
	color?: string;
	amount: number;
}

/**
 * Spending by category as a ranked list of bars - one hue (magnitude, not identity),
 * every value labelled directly. Anything past the top `limit` folds into "Other".
 */
export function CategoryBars({
	items,
	currency,
	limit = 6,
	linkTo,
}: {
	items: Item[];
	currency: string;
	limit?: number;
	linkTo?: (categoryId: string) => string;
}) {
	const total = items.reduce((sum, i) => sum + i.amount, 0);
	const shown = items.slice(0, limit);
	const rest = items.slice(limit);
	const rows: Item[] = rest.length
		? [...shown, { name: `Other (${rest.length})`, icon: "circle-ellipsis", color: "#94a3b8", amount: rest.reduce((s, i) => s + i.amount, 0) }]
		: shown;
	const largest = Math.max(1, ...rows.map((r) => r.amount));

	return (
		<ul className="space-y-3.5">
			{rows.map((row) => {
				const share = total > 0 ? (row.amount / total) * 100 : 0;
				const content = (
					<>
						<CategoryChip icon={row.icon} color={row.color} size="sm" />
						<div className="min-w-0 flex-1">
							<div className="flex items-baseline justify-between gap-2">
								<span className="truncate text-sm font-medium text-slate-800">{row.name}</span>
								<span className="shrink-0 text-sm font-semibold tabular-nums text-slate-900">{formatMoney(row.amount, currency)}</span>
							</div>
							<div className="mt-1.5 flex items-center gap-2">
								<div className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-100">
									<div
										className="h-full rounded-full transition-[width] duration-500"
										style={{ width: `${(row.amount / largest) * 100}%`, backgroundColor: "var(--series-magnitude)" }}
									/>
								</div>
								<span className="w-9 shrink-0 text-right text-xs tabular-nums text-slate-500">{share.toFixed(0)}%</span>
							</div>
						</div>
					</>
				);
				return (
					<li key={row.categoryId ?? row.name}>
						{row.categoryId && linkTo ? (
							<Link to={linkTo(row.categoryId)} className="-m-1.5 flex items-center gap-3 rounded-xl p-1.5 hover:bg-slate-50">
								{content}
							</Link>
						) : (
							<div className="flex items-center gap-3">{content}</div>
						)}
					</li>
				);
			})}
		</ul>
	);
}

/** Needs vs wants as one bar: the needs share in one hue against a neutral track, both labelled. */
export function NeedsWantsBar({ needs, wants, currency }: { needs: number; wants: number; currency: string }) {
	const total = needs + wants;
	const needsPct = total > 0 ? (needs / total) * 100 : 0;
	return (
		<div>
			<div className="flex h-2.5 gap-0.5 overflow-hidden rounded-full" aria-hidden="true">
				<div className="h-full rounded-l-full" style={{ width: `${needsPct}%`, backgroundColor: "var(--series-magnitude)" }} />
				<div className="h-full flex-1 rounded-r-full bg-slate-200" />
			</div>
			<dl className="mt-2.5 grid grid-cols-2 gap-2 text-xs">
				<div>
					<dt className="text-slate-500">Needs · {needsPct.toFixed(0)}%</dt>
					<dd className="font-semibold tabular-nums text-slate-900">{formatMoney(needs, currency)}</dd>
				</div>
				<div className="text-right">
					<dt className="text-slate-500">Wants · {total > 0 ? (100 - needsPct).toFixed(0) : 0}%</dt>
					<dd className="font-semibold tabular-nums text-slate-900">{formatMoney(wants, currency)}</dd>
				</div>
			</dl>
		</div>
	);
}
