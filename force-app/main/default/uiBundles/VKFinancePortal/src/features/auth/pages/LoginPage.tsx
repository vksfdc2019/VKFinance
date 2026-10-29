import { useState, type FormEvent } from "react";
import { Link, useNavigate, useSearchParams } from "react-router";
import { KeyRound, ShieldCheck, Smartphone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { StatusAlert } from "@/components/alerts/status-alert";
import { AuthCard } from "@/components/layout/AuthCard";
import { FormErrors, TextField } from "@/components/forms";
import { OtpInput } from "@/components/security/OtpInput";
import { ApiError, errorMessages } from "@/api/vkfClient";
import { useAuth } from "../AuthContext";
import { safeNext } from "../RouteGuards";

const REASON_TEXT = {
	expired: "Your session ended. Please sign in again.",
	idle: "You were signed out after a period of inactivity.",
	user: "You've signed out.",
} as const;

export default function LoginPage() {
	const { login, completeMfa, signOutReason } = useAuth();
	const navigate = useNavigate();
	const [params] = useSearchParams();
	const [username, setUsername] = useState("");
	const [password, setPassword] = useState("");
	const [challenge, setChallenge] = useState<string | null>(null);
	const [code, setCode] = useState("");
	const [useRecovery, setUseRecovery] = useState(false);
	const [failures, setFailures] = useState(0);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	function finish(mustChangePassword: boolean) {
		navigate(mustChangePassword ? "/first-login" : safeNext(params.get("next")), { replace: true });
	}

	async function submitPassword(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			const result = await login(username, password);
			if (result.mfaRequired && result.challenge) {
				setChallenge(result.challenge);
				setCode("");
				setUseRecovery(false);
			} else {
				finish(result.mustChangePassword);
			}
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setPassword("");
			setBusy(false);
		}
	}

	async function submitCode(value = code) {
		if (!challenge || busy) return;
		setErrors([]);
		setBusy(true);
		try {
			const result = await completeMfa(challenge, value);
			finish(result.mustChangePassword);
		} catch (error) {
			setErrors(errorMessages(error));
			setCode("");
			setFailures((n) => n + 1);
			// The challenge is spent (expired, too many tries or locked): start again from the password.
			if (error instanceof ApiError && error.code !== "INVALID_CODE") setChallenge(null);
		} finally {
			setBusy(false);
		}
	}

	if (challenge) {
		return (
			<AuthCard title="Two-step verification" description="Your account is protected with an authenticator app.">
				<form
					className="vk-rise grid gap-5"
					onSubmit={(e) => {
						e.preventDefault();
						void submitCode();
					}}
					noValidate
				>
					<div className="flex items-center gap-3 rounded-xl bg-brand-50 dark:bg-brand-950/40 p-3 text-sm text-brand-900 dark:text-brand-100">
						<span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-white dark:bg-slate-900 text-brand-700 dark:text-brand-300 shadow-sm">
							{useRecovery ? <KeyRound className="size-5" aria-hidden="true" /> : <Smartphone className="size-5" aria-hidden="true" />}
						</span>
						{useRecovery
							? "Enter one of the recovery codes you saved when you set up two-step verification. Each code works once."
							: "Open your authenticator app and enter the 6-digit code for VK Finance."}
					</div>
					<FormErrors errors={errors} />
					{useRecovery ? (
						<TextField
							id="recovery-code"
							label="Recovery code"
							autoComplete="off"
							autoCapitalize="none"
							spellCheck={false}
							placeholder="xxxxx-xxxxx"
							className="font-mono tracking-wider"
							value={code}
							onChange={(e) => setCode(e.target.value)}
							autoFocus
						/>
					) : (
						<OtpInput value={code} onChange={setCode} onComplete={(v) => void submitCode(v)} disabled={busy} invalid={failures} autoFocus />
					)}
					<Button type="submit" disabled={busy || (useRecovery ? code.trim().length < 10 : code.length !== 6)}>
						{busy ? <Spinner /> : <ShieldCheck aria-hidden="true" />}
						Verify and sign in
					</Button>
					<div className="flex flex-wrap items-center justify-between gap-2 text-sm">
						<button
							type="button"
							className="text-brand-800 dark:text-brand-200 underline-offset-4 hover:underline"
							onClick={() => {
								setUseRecovery((r) => !r);
								setCode("");
								setErrors([]);
							}}
						>
							{useRecovery ? "Use my authenticator app" : "Use a recovery code"}
						</button>
						<button
							type="button"
							className="text-slate-500 dark:text-slate-400 underline-offset-4 hover:underline"
							onClick={() => {
								setChallenge(null);
								setErrors([]);
							}}
						>
							Back to sign in
						</button>
					</div>
					<p className="text-xs text-slate-500 dark:text-slate-400">Lost your phone and your recovery codes? Ask your Family Admin to reset your two-step verification.</p>
				</form>
			</AuthCard>
		);
	}

	return (
		<AuthCard title="Sign in" description="Use the username your Family Admin gave you.">
			<form className="grid gap-4" onSubmit={submitPassword} noValidate>
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
				<Link to="/forgot-password" className="text-center text-sm text-brand-800 dark:text-brand-200 underline-offset-4 hover:underline">
					Forgot your password?
				</Link>
			</form>
		</AuthCard>
	);
}
