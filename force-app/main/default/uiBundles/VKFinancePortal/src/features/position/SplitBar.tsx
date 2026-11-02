import { cn } from "@/lib/utils";

export interface Segment {
	label: string;
	value: number;
	/** Background class for the segment and its legend dot. */
	className: string;
}

/** One bar split into parts, with a legend - e.g. used against available. Colour is never the only cue. */
export function SplitBar({ segments, label, className }: { segments: Segment[]; label: string; className?: string }) {
	const shown = segments.filter((s) => s.value > 0);
	const total = shown.reduce((sum, s) => sum + s.value, 0);
	const pct = (v: number) => (total > 0 ? (v / total) * 100 : 0);
	return (
		<div className={className}>
			<div
				className="flex h-2.5 gap-0.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800"
				role="img"
				aria-label={`${label}: ${shown.map((s) => `${s.label} ${Math.round(pct(s.value))}%`).join(", ") || "nothing yet"}`}
			>
				{shown.map((s) => (
					<div key={s.label} className={cn("h-full transition-[width] duration-500 first:rounded-l-full last:rounded-r-full", s.className)} style={{ width: `${pct(s.value)}%` }} />
				))}
			</div>
			<ul className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-[11px] text-slate-500 dark:text-slate-400">
				{segments.map((s) => (
					<li key={s.label} className="inline-flex items-center gap-1.5">
						<span className={cn("size-2 rounded-full", s.className)} aria-hidden="true" />
						{s.label} {total > 0 ? `${Math.round(pct(Math.max(0, s.value)))}%` : ""}
					</li>
				))}
			</ul>
		</div>
	);
}
