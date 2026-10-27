import { useState, type FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { StatusAlert } from "@/components/alerts/status-alert";
import { AuthCard } from "@/components/layout/AuthCard";
import { FormErrors, TextField } from "@/components/forms";
import { errorMessages } from "@/api/vkfClient";
import { useAuth } from "../AuthContext";
import { safeNext } from "../RouteGuards";

const REASON_TEXT = {
	expired: "Your session ended. Please sign in again.",
	idle: "You were signed out after a period of inactivity.",
	user: "You've signed out.",
} as const;

export default function LoginPage() {
	const { login, signOutReason } = useAuth();
	const navigate = useNavigate();
	const [params] = useSearchParams();
	const [username, setUsername] = useState("");
	const [password, setPassword] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	async function submit(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			const result = await login(username, password);
			navigate(result.mustChangePassword ? "/first-login" : safeNext(params.get("next")), { replace: true });
		} catch (error) {
			setErrors(errorMessages(error));
			setPassword("");
		} finally {
			setBusy(false);
		}
	}

	return (
		<AuthCard title="Sign in" description="Use the username your Family Admin gave you.">
			<form className="grid gap-4" onSubmit={submit} noValidate>
				{signOutReason && <StatusAlert variant="info">{REASON_TEXT[signOutReason]}</StatusAlert>}
				<FormErrors errors={errors} />
				<TextField
					id="username"
					label="Username"
					autoComplete="username"
					autoCapitalize="none"
					value={username}
					onChange={(e) => setUsername(e.target.value)}
					required
				/>
				<TextField
					id="password"
					label="Password"
					type="password"
					autoComplete="current-password"
					value={password}
					onChange={(e) => setPassword(e.target.value)}
					required
				/>
				<Button type="submit" disabled={busy || !username || !password}>
					{busy && <Spinner />}
					Sign in
				</Button>
				<Link to="/forgot-password" className="text-center text-sm text-teal-800 underline-offset-4 hover:underline">
					Forgot your password?
				</Link>
			</form>
		</AuthCard>
	);
}
