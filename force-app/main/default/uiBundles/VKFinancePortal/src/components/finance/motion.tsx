import { useEffect, useRef, useState, type CSSProperties, type ReactNode } from "react";
import { cn } from "@/lib/utils";
import { formatMoney } from "@/lib/format";

export function prefersReducedMotion(): boolean {
	return typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
}

/** Eases a number from its previous value to the new one (ease-out cubic). */
export function useCountUp(value: number, duration = 700): number {
	const [shown, setShown] = useState(value);
	const from = useRef(value);

	useEffect(() => {
		const start = from.current;
		if (prefersReducedMotion() || start === value) {
			from.current = value;
			setShown(value);
			return;
		}
		let frame = 0;
		const began = performance.now();
		const tick = (now: number) => {
			const t = Math.min(1, (now - began) / duration);
			const eased = 1 - Math.pow(1 - t, 3);
			setShown(start + (value - start) * eased);
			if (t < 1) frame = requestAnimationFrame(tick);
			else from.current = value;
		};
		frame = requestAnimationFrame(tick);
		return () => {
			cancelAnimationFrame(frame);
			from.current = value;
		};
	}, [value, duration]);
	return shown;
}

export function AnimatedMoney({ value, currency, className }: { value: number; currency?: string; className?: string }) {
	const shown = useCountUp(value);
	// Paise flicker while counting looks noisy; snap to the exact value at the end.
	return <span className={className}>{formatMoney(shown === value ? value : Math.round(shown), currency)}</span>;
}

/** Fades and lifts its children in; `index` staggers siblings. */
export function Reveal({
	children,
	index = 0,
	className,
	as: Tag = "div",
}: {
	children: ReactNode;
	index?: number;
	className?: string;
	as?: "div" | "section" | "li";
}) {
	const style: CSSProperties = { animationDelay: `${Math.min(index, 12) * 60}ms` };
	return (
		<Tag className={cn("vk-rise", className)} style={style}>
			{children}
		</Tag>
	);
}

/** A circular progress ring that draws itself to the value. */
export function ProgressRing({
	value,
	size = 72,
	stroke = 7,
	color = "var(--series-magnitude)",
	track = "rgb(226 232 240)",
	children,
	label,
}: {
	value: number;
	size?: number;
	stroke?: number;
	color?: string;
	track?: string;
	children?: ReactNode;
	label: string;
}) {
	const r = (size - stroke) / 2;
	const circumference = 2 * Math.PI * r;
	const pct = Math.max(0, Math.min(100, value));
	const [drawn, setDrawn] = useState(prefersReducedMotion() ? pct : 0);
	useEffect(() => {
		const id = requestAnimationFrame(() => setDrawn(pct));
		return () => cancelAnimationFrame(id);
	}, [pct]);
	return (
		<div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }} role="img" aria-label={label}>
			<svg width={size} height={size} className="-rotate-90">
				<circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track} strokeWidth={stroke} />
				<circle
					cx={size / 2}
					cy={size / 2}
					r={r}
					fill="none"
					stroke={color}
					strokeWidth={stroke}
					strokeLinecap="round"
					strokeDasharray={circumference}
					strokeDashoffset={circumference * (1 - drawn / 100)}
					style={{ transition: "stroke-dashoffset 0.9s cubic-bezier(0.2, 0.8, 0.2, 1)" }}
				/>
			</svg>
			<div className="absolute inset-0 flex flex-col items-center justify-center text-center">{children}</div>
		</div>
	);
}

/** A tick that pops and draws itself - shown after a payment succeeds. */
export function SuccessCheck({ title, detail }: { title: string; detail?: ReactNode }) {
	return (
		<div className="flex flex-col items-center justify-center py-8 text-center" role="status">
			<div className="vk-pop flex size-20 items-center justify-center rounded-full bg-emerald-50 dark:bg-emerald-950/40 ring-8 ring-emerald-50/60 dark:ring-emerald-900/60">
				<svg viewBox="0 0 36 36" className="size-12" aria-hidden="true">
					<circle cx="18" cy="18" r="16" fill="#059669" />
					<path className="vk-draw" d="M11 18.5l4.5 4.5L25 13.5" fill="none" stroke="white" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
				</svg>
			</div>
			<p className="vk-rise mt-4 text-lg font-semibold text-slate-900 dark:text-slate-100" style={{ animationDelay: "150ms" }}>
				{title}
			</p>
			{detail && (
				<p className="vk-rise mt-1 text-sm text-slate-500 dark:text-slate-400" style={{ animationDelay: "250ms" }}>
					{detail}
				</p>
			)}
		</div>
	);
}
