import { useCallback, useEffect, useState, type FormEvent } from "react";
import { Monitor } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { toast } from "@/components/ui/sonner";
import { FormErrors, PasswordRules, TextField } from "@/components/forms";
import { authApi, profileApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { DeviceSession } from "@/api/types";
import { formatDateTime, formatRelative } from "@/lib/format";
import { useAuth } from "@/features/auth/AuthContext";

function ChangePasswordCard({ admin }: { admin: boolean }) {
	const [current, setCurrent] = useState("");
	const [next, setNext] = useState("");
	const [confirm, setConfirm] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	async function submit(event: FormEvent) {
		event.preventDefault();
		if (next !== confirm) {
			setErrors(["The two new passwords don't match."]);
			return;
		}
		setErrors([]);
		setBusy(true);
		try {
			const { message } = await authApi.changePassword(current, next);
			toast.success(message);
			setCurrent("");
			setNext("");
			setConfirm("");
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle className="text-base">Change password</CardTitle>
				<CardDescription>Your other devices are signed out when you change it.</CardDescription>
			</CardHeader>
			<CardContent>
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<TextField id="current-password" label="Current password" type="password" autoComplete="current-password" value={current} onChange={(e) => setCurrent(e.target.value)} />
					<TextField id="new-password" label="New password" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
					<TextField id="confirm-password" label="Confirm new password" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} />
					<PasswordRules admin={admin} />
					<div>
						<Button type="submit" disabled={busy || !current || !next || !confirm}>
							{busy && <Spinner />}
							Change password
						</Button>
					</div>
				</form>
			</CardContent>
		</Card>
	);
}

function DevicesCard() {
	const [sessions, setSessions] = useState<DeviceSession[] | null>(null);

	const load = useCallback(async () => {
		try {
			setSessions(await profileApi.sessions());
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}, []);

	useEffect(() => {
		void load();
	}, [load]);

	async function run(action: () => Promise<unknown>, message: string) {
		try {
			await action();
			toast.success(message);
			await load();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	const others = sessions?.filter((session) => !session.current).length ?? 0;

	return (
		<Card>
			<CardHeader>
				<CardTitle className="text-base">Where you're signed in</CardTitle>
				<CardDescription>Sessions end after 30 minutes without activity, or 12 hours at most.</CardDescription>
			</CardHeader>
			<CardContent className="grid gap-3">
				{!sessions ? (
					<Spinner />
				) : (
					sessions.map((session) => (
						<div key={session.id} className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3">
							<div className="flex items-center gap-3">
								<Monitor className="size-4 text-slate-500" aria-hidden="true" />
								<div>
									<div className="text-sm font-medium">
										{session.device}
										{session.current && (
											<Badge variant="secondary" className="ml-2">
												This device
											</Badge>
										)}
									</div>
									<div className="text-xs text-slate-500">
										Signed in {formatDateTime(session.startedAt)} · active {formatRelative(session.lastActivity)}
									</div>
								</div>
							</div>
							{!session.current && (
								<Button variant="outline" size="sm" onClick={() => void run(() => profileApi.signOutDevice(session.id), "That device is signed out.")}>
									Sign out
								</Button>
							)}
						</div>
					))
				)}
				{others > 0 && (
					<div>
						<Button variant="outline" onClick={() => void run(() => profileApi.signOutOtherDevices(), "All other devices are signed out.")}>
							Sign out all other devices
						</Button>
					</div>
				)}
			</CardContent>
		</Card>
	);
}

export default function ProfilePage() {
	const { profile } = useAuth();
	if (!profile) return null;
	const admin = profile.role === "Family Admin" || profile.role === "Co-Admin";
	const details: [string, string | undefined][] = [
		["Name", `${profile.firstName} ${profile.lastName}`],
		["Username", profile.username],
		["Email", profile.email],
		["Mobile", profile.mobile],
		["Relationship", profile.relationship],
		["Role", profile.role],
		["Family", `${profile.familyName} (${profile.familyCode})`],
	];

	return (
		<div className="grid gap-6">
			<title>Profile · VK Finance</title>
			<h1 className="text-2xl font-semibold text-slate-900">Profile & security</h1>
			<div className="grid gap-6 lg:grid-cols-2">
				<Card>
					<CardHeader>
						<CardTitle className="text-base">Your details</CardTitle>
						<CardDescription>Ask your Family Admin to change your name, email or role.</CardDescription>
					</CardHeader>
					<CardContent>
						<dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
							{details.map(([label, value]) => (
								<div key={label} className="contents">
									<dt className="text-slate-500">{label}</dt>
									<dd className="text-slate-900">{value || "—"}</dd>
								</div>
							))}
						</dl>
					</CardContent>
				</Card>
				<ChangePasswordCard admin={admin} />
			</div>
			<DevicesCard />
		</div>
	);
}
