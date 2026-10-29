import { useEffect, useRef, type ClipboardEvent, type KeyboardEvent } from "react";
import { cn } from "@/lib/utils";

const LENGTH = 6;

/**
 * Six boxes for an authenticator code. Typing moves forward, Backspace moves back, and a
 * pasted code fills every box. Phones offer the code from SMS/apps via one-time-code.
 */
export function OtpInput({
	value,
	onChange,
	onComplete,
	disabled,
	invalid,
	autoFocus,
	label = "Six-digit code",
}: {
	value: string;
	onChange(value: string): void;
	onComplete?(value: string): void;
	disabled?: boolean;
	/** Changes on every failed attempt to replay the shake. */
	invalid?: number;
	autoFocus?: boolean;
	label?: string;
}) {
	const refs = useRef<(HTMLInputElement | null)[]>([]);
	const digits = Array.from({ length: LENGTH }, (_, i) => value[i] ?? "");

	useEffect(() => {
		if (autoFocus) refs.current[0]?.focus();
	}, [autoFocus]);

	useEffect(() => {
		if (invalid) refs.current[0]?.focus();
	}, [invalid]);

	function update(next: string) {
		const clean = next.replace(/\D/g, "").slice(0, LENGTH);
		onChange(clean);
		if (clean.length === LENGTH) onComplete?.(clean);
		return clean;
	}

	function type(index: number, raw: string) {
		const digit = raw.replace(/\D/g, "").slice(-1);
		if (!digit) return;
		const chars = digits.slice();
		chars[index] = digit;
		const clean = update(chars.join(""));
		refs.current[Math.min(clean.length, LENGTH - 1)]?.focus();
	}

	function key(index: number, event: KeyboardEvent<HTMLInputElement>) {
		if (event.key === "Backspace") {
			event.preventDefault();
			const chars = digits.slice();
			const target = chars[index] ? index : Math.max(0, index - 1);
			chars[target] = "";
			update(chars.join(""));
			refs.current[target]?.focus();
		} else if (event.key === "ArrowLeft") {
			refs.current[Math.max(0, index - 1)]?.focus();
		} else if (event.key === "ArrowRight") {
			refs.current[Math.min(LENGTH - 1, index + 1)]?.focus();
		}
	}

	function paste(event: ClipboardEvent<HTMLInputElement>) {
		event.preventDefault();
		const clean = update(event.clipboardData.getData("text"));
		refs.current[Math.min(clean.length, LENGTH - 1)]?.focus();
	}

	return (
		<div key={invalid} role="group" aria-label={label} className={cn("flex justify-center gap-2", invalid ? "vk-shake" : undefined)}>
			{digits.map((digit, i) => (
				<input
					key={i}
					ref={(el) => {
						refs.current[i] = el;
					}}
					value={digit}
					onChange={(e) => type(i, e.target.value)}
					onKeyDown={(e) => key(i, e)}
					onPaste={paste}
					onFocus={(e) => e.target.select()}
					disabled={disabled}
					inputMode="numeric"
					autoComplete={i === 0 ? "one-time-code" : "off"}
					aria-label={`Digit ${i + 1}`}
					maxLength={1}
					className={cn(
						"size-12 rounded-xl border bg-white dark:bg-slate-900 text-center text-xl font-semibold tabular-nums text-slate-900 dark:text-slate-100 shadow-sm transition-all outline-none",
						"focus:border-brand-600 focus:ring-4 focus:ring-brand-600/15 disabled:opacity-50 sm:size-13",
						digit ? "border-brand-300 dark:border-brand-700 bg-brand-50/40 dark:bg-brand-950/40" : invalid && !value ? "border-red-300 dark:border-red-700" : "border-slate-200 dark:border-slate-800",
					)}
				/>
			))}
		</div>
	);
}
