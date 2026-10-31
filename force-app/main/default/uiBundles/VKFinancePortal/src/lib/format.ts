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

let monthStartDay = 1;

/**
 * The family's month starts on this day (from the profile; 1 = calendar months). Same rule as
 * BudgetMonth.cls: after the 15th, a month is named for the one it mostly covers, so with 30
 * "November" runs 30 Oct to 29 Nov. Short months start on their last day.
 */
export function setMonthStartDay(day?: number | null): void {
	monthStartDay = day && day >= 1 && day <= 31 ? Math.floor(day) : 1;
}

export function getMonthStartDay(): number {
	return monthStartDay;
}

function periodStartFor(year: number, monthIndex: number, day: number): Date {
	if (day <= 1) return new Date(year, monthIndex, 1);
	const month = day > 15 ? new Date(year, monthIndex - 1, 1) : new Date(year, monthIndex, 1);
	const last = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
	return new Date(month.getFullYear(), month.getMonth(), Math.min(day, last));
}

/** First and last day of the family month named by "2026-11". */
export function monthPeriod(key: string): { start: Date; end: Date } {
	const anchor = monthFromKey(key);
	const start = periodStartFor(anchor.getFullYear(), anchor.getMonth(), monthStartDay);
	const next = periodStartFor(anchor.getFullYear(), anchor.getMonth() + 1, monthStartDay);
	return { start, end: new Date(next.getFullYear(), next.getMonth(), next.getDate() - 1) };
}

/** "30 Oct – 29 Nov" when months start on payday; empty for calendar months. */
export function monthRange(key: string): string {
	if (monthStartDay <= 1) return "";
	const { start, end } = monthPeriod(key);
	return `${format(start, "d MMM")} – ${format(end, "d MMM")}`;
}

/** "2026-10" for the calendar month containing the date. */
export function calendarMonthKey(date: Date = new Date()): string {
	return format(date, "yyyy-MM");
}

/** "2026-11" for the family month containing the date - with a 30th start, 30 October is already November. */
export function monthKey(date: Date = new Date()): string {
	const day = new Date(date.getFullYear(), date.getMonth(), date.getDate());
	let anchor = new Date(day.getFullYear(), day.getMonth(), 1);
	if (day >= periodStartFor(anchor.getFullYear(), anchor.getMonth() + 1, monthStartDay)) anchor = addMonths(anchor, 1);
	else if (day < periodStartFor(anchor.getFullYear(), anchor.getMonth(), monthStartDay)) anchor = addMonths(anchor, -1);
	return format(anchor, "yyyy-MM");
}

export function monthFromKey(key: string): Date {
	return parseISO(`${key}-01`);
}

export function shiftMonth(key: string, delta: number): string {
	return calendarMonthKey(addMonths(monthFromKey(key), delta));
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
