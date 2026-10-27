import { useState, type FormEvent } from "react";
import { Link } from "react-router";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { StatusAlert } from "@/components/alerts/status-alert";
import { AuthCard } from "@/components/layout/AuthCard";
import { FormErrors, TextField } from "@/components/forms";
import { authApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";

export default function ForgotPasswordPage() {
	const [identifier, setIdentifier] = useState("");
	const [message, setMessage] = useState<string | null>(null);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	async function submit(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			setMessage((await authApi.forgot(identifier)).message);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	return (
		<AuthCard
			title="Reset your password"
			description="Enter your username or email. If your account has an email address we'll send a reset link."
		>
			<form className="grid gap-4" onSubmit={submit} noValidate>
				<FormErrors errors={errors} />
				{message ? (
					<StatusAlert variant="success">{message}</StatusAlert>
				) : (
					<>
						<TextField
							id="identifier"
							label="Username or email"
							autoCapitalize="none"
							value={identifier}
							onChange={(e) => setIdentifier(e.target.value)}
							required
						/>
						<Button type="submit" disabled={busy || !identifier.trim()}>
							{busy && <Spinner />}
							Send reset link
						</Button>
					</>
				)}
				<p className="text-center text-sm text-muted-foreground">
					No email on your account? Ask your Family Admin to reset your password.
				</p>
				<Link to="/login" className="text-center text-sm text-teal-800 underline-offset-4 hover:underline">
					Back to sign in
				</Link>
			</form>
		</AuthCard>
	);
}
