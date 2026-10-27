import type { ComponentProps, ReactNode } from "react";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusAlert } from "@/components/alerts/status-alert";

interface TextFieldProps extends ComponentProps<typeof Input> {
	id: string;
	label: string;
	hint?: ReactNode;
}

export function TextField({ id, label, hint, ...inputProps }: TextFieldProps) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={id}>{label}</Label>
			<Input id={id} {...inputProps} />
			{hint && <p className="text-xs text-muted-foreground">{hint}</p>}
		</div>
	);
}

export function FormErrors({ errors }: { errors: string[] }) {
	if (errors.length === 0) return null;
	return (
		<StatusAlert variant="error">
			{errors.length === 1 ? (
				errors[0]
			) : (
				<ul className="list-disc pl-4">
					{errors.map((error) => (
						<li key={error}>{error}</li>
					))}
				</ul>
			)}
		</StatusAlert>
	);
}

/** The server enforces these; the list just tells people what to aim for. */
export function PasswordRules({ admin }: { admin?: boolean }) {
	return (
		<ul className="list-disc space-y-0.5 pl-4 text-xs text-muted-foreground">
			<li>At least {admin ? 12 : 10} characters</li>
			<li>Mix at least three of: upper-case, lower-case, digits, symbols</li>
			<li>Not your name or username, and not a common password</li>
			<li>Not one of your last 5 passwords</li>
		</ul>
	);
}
