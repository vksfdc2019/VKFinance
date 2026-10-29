import { useState, type FormEvent } from "react";
import { Link, useSearchParams } from "react-router";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { StatusAlert } from "@/components/alerts/status-alert";
import { AuthCard } from "@/components/layout/AuthCard";
import { FormErrors, PasswordRules, TextField } from "@/components/forms";
import { authApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";

export default function ResetPasswordPage() {
	const [params] = useSearchParams();
	const token = params.get("t") ?? "";
	const [password, setPassword] = useState("");
	const [confirm, setConfirm] = useState("");
	const [done, setDone] = useState<string | null>(null);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	async function submit(event: FormEvent) {
		event.preventDefault();
		if (password !== confirm) {
			setErrors(["The two passwords don't match."]);
			return;
		}
		setErrors([]);
		setBusy(true);
		try {
			setDone((await authApi.reset(token, password)).message);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	if (!token) {
		return (
			<AuthCard title="Reset link missing">
				<StatusAlert variant="error">This page needs the link from your reset email.</StatusAlert>
				<Link to="/forgot-password" className="mt-4 block text-center text-sm text-brand-800 dark:text-brand-200 hover:underline">
					Request a new link
				</Link>
			</AuthCard>
		);
	}

	return (
		<AuthCard title="Choose a new password">
			{done ? (
				<div className="grid gap-4">
					<StatusAlert variant="success">{done}</StatusAlert>
					<Button asChild>
						<Link to="/login">Go to sign in</Link>
					</Button>
				</div>
			) : (
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<TextField
						id="new-password"
						label="New password"
						type="password"
						autoComplete="new-password"
						value={password}
						onChange={(e) => setPassword(e.target.value)}
						required
					/>
					<TextField
						id="confirm-password"
						label="Confirm new password"
						type="password"
						autoComplete="new-password"
						value={confirm}
						onChange={(e) => setConfirm(e.target.value)}
						required
					/>
					<PasswordRules />
					<Button type="submit" disabled={busy || !password || !confirm}>
						{busy && <Spinner />}
						Save new password
					</Button>
					<p className="text-center text-xs text-muted-foreground">
						Saving signs you out on every device. Family Admins need at least 12 characters.
					</p>
				</form>
			)}
		</AuthCard>
	);
}
