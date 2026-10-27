import { useState, type FormEvent } from "react";
import { Navigate, useNavigate } from "react-router";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { AuthCard } from "@/components/layout/AuthCard";
import { FormErrors, PasswordRules, TextField } from "@/components/forms";
import { errorMessages } from "@/api/vkfClient";
import { useAuth } from "../AuthContext";
import { FullPageSpinner } from "../RouteGuards";

/** Shown after signing in with a temporary password; the session can do nothing else. */
export default function FirstLoginPage() {
	const { status, profile, completeFirstLogin, logout } = useAuth();
	const navigate = useNavigate();
	const [password, setPassword] = useState("");
	const [confirm, setConfirm] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	if (status === "loading") return <FullPageSpinner />;
	if (status === "anonymous") return <Navigate to="/login" replace />;
	if (status === "authenticated") return <Navigate to="/" replace />;

	const admin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";

	async function submit(event: FormEvent) {
		event.preventDefault();
		if (password !== confirm) {
			setErrors(["The two passwords don't match."]);
			return;
		}
		setErrors([]);
		setBusy(true);
		try {
			await completeFirstLogin(password);
			navigate("/", { replace: true });
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	return (
		<AuthCard
			title={`Welcome, ${profile?.firstName ?? ""}`}
			description={`Choose your own password to finish setting up your ${profile?.familyName ?? "family"} account.`}
		>
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
				<PasswordRules admin={admin} />
				<Button type="submit" disabled={busy || !password || !confirm}>
					{busy && <Spinner />}
					Set password and continue
				</Button>
				<Button type="button" variant="ghost" onClick={() => void logout("user")}>
					Cancel and sign out
				</Button>
			</form>
		</AuthCard>
	);
}
