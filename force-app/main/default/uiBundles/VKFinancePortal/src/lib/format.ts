import { addMonths, format, formatDistanceToNow, isToday, isYesterday, parseISO } from "date-fns";

export function formatDateTime(value?: string | null): string {
	return value ? format(new Date(value), "d MMM yyyy, h:mm a") : "—";
}

export function formatRelative(value?: string | null): string {
	return value ? `${formatDistanceToNow(new Date(value))} ago` : "Never";
}

const numberFormats = new Map<string, Intl.NumberFormat>();

function numberFormat(currency: string, options: Intl.NumberFormatOptions): Intl.NumberFormat {
	const key = currency + JSON.stringify(options);
	let nf = numberFormats.get(key);
	if (!nf) {
		// en-IN groups as 1,23,456 and abbreviates as 1.2L / 3.4Cr, which is what Indian families expect.
		nf = new Intl.NumberFormat("en-IN", { style: "currency", currency, ...options });
		numberFormats.set(key, nf);
	}
	return nf;
}

/** ₹1,23,456 - paise only when there are any. */
export function formatMoney(amount: number | null | undefined, currency = "INR", options: { signed?: boolean } = {}): string {
	const value = amount ?? 0;
	const whole = Math.abs(value % 1) < 0.005;
	const text = numberFormat(currency, {
		minimumFractionDigits: whole ? 0 : 2,
		maximumFractionDigits: whole ? 0 : 2,
	}).format(Math.abs(value));
	if (value < 0) return `−${text}`;
	return options.signed && value > 0 ? `+${text}` : text;
}

/** ₹1.2L, ₹45K - for chart axes and tight spaces. */
export function formatCompact(amount: number | null | undefined, currency = "INR"): string {
	const value = amount ?? 0;
	const text = numberFormat(currency, { notation: "compact", maximumFractionDigits: 1 }).format(Math.abs(value));
	return value < 0 ? `−${text}` : text;
}

export function currencySymbol(currency = "INR"): string {
	return numberFormat(currency, { maximumFractionDigits: 0 }).formatToParts(0).find((p) => p.type === "currency")?.value ?? currency;
}

export function formatPercent(value: number | null | undefined, digits = 0): string {
	return value === null || value === undefined || !Number.isFinite(value) ? "—" : `${value.toFixed(digits)}%`;
}

/** "2026-10" for the month containing the date. */
export function monthKey(date: Date = new Date()): string {
	return format(date, "yyyy-MM");
}

export function monthFromKey(key: string): Date {
	return parseISO(`${key}-01`);
}

export function shiftMonth(key: string, delta: number): string {
	return monthKey(addMonths(monthFromKey(key), delta));
}

export function monthLabel(key: string, style: "long" | "short" = "long"): string {
	return format(monthFromKey(key), style === "long" ? "MMMM yyyy" : "MMM");
}

/** Today as yyyy-MM-dd in the browser's time zone. */
export function todayIso(): string {
	return format(new Date(), "yyyy-MM-dd");
}

export function formatDate(iso?: string | null): string {
	return iso ? format(parseISO(iso), "d MMM yyyy") : "—";
}

export function formatShortDate(iso?: string | null): string {
	return iso ? format(parseISO(iso), "d MMM") : "—";
}

/** "Today", "Yesterday" or "Mon, 26 Oct" for grouping a list by day. */
export function dayHeading(iso: string): string {
	const date = parseISO(iso);
	if (isToday(date)) return "Today";
	if (isYesterday(date)) return "Yesterday";
	return format(date, date.getFullYear() === new Date().getFullYear() ? "EEE, d MMM" : "EEE, d MMM yyyy");
}

/** Percentage change from previous to current; undefined when there is no base to compare with. */
export function percentChange(current: number, previous: number): number | undefined {
	if (!previous) return undefined;
	return ((current - previous) / Math.abs(previous)) * 100;
}
