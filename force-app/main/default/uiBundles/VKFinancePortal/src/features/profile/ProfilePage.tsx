import { useCallback, useEffect, useState, type FormEvent } from "react";
import { useLocation } from "react-router";
import {
	AlertTriangle,
	CheckCircle2,
	Clock,
	KeyRound,
	Lock,
	LogIn,
	LogOut,
	Monitor,
	ShieldAlert,
	ShieldCheck,
	ShieldOff,
	Smartphone,
	UserCog,
	XCircle,
	type LucideIcon,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, PasswordRules, TextField } from "@/components/forms";
import { PageHeader, Panel } from "@/components/finance/ui";
import { ProgressRing, Reveal } from "@/components/finance/motion";
import { authApi, profileApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { DeviceSession, Profile, SecurityEvent, SecurityOverview } from "@/api/types";
import { formatDateTime, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { TwoStepCard } from "./TwoStep";

const YEAR_MS = 365 * 24 * 60 * 60 * 1000;

interface Check {
	label: string;
	detail: string;
	ok: boolean;
	href?: string;
}

/** A few plain checks that add up to a score, each with what to do about it. */
function checksFor(profile: Profile, overview: SecurityOverview, devices: number): Check[] {
	const admin = profile.role === "Family Admin" || profile.role === "Co-Admin";
	const passwordAge = overview.passwordChangedAt ? Date.now() - new Date(overview.passwordChangedAt).getTime() : Infinity;
	const checks: Check[] = [
		{
			label: "Two-step verification",
			detail: overview.mfa.enabled
				? "A code from your phone is needed to sign in."
				: admin
					? "Strongly recommended for admins."
					: "Adds a second lock to your account.",
			ok: overview.mfa.enabled,
			href: "#two-step",
		},
		{
			label: "Recovery codes",
			detail: overview.mfa.enabled ? `${overview.mfa.recoveryCodesLeft} left.` : "Created when you turn on two-step.",
			ok: overview.mfa.enabled && overview.mfa.recoveryCodesLeft > 3,
			href: "#two-step",
		},
		{
			label: "Password set in the last year",
			detail: overview.passwordChangedAt ? `Last changed ${formatRelative(overview.passwordChangedAt)}.` : "Not recorded.",
			ok: passwordAge < YEAR_MS,
			href: "#password",
		},
		{
			label: "Email for password resets",
			detail: profile.email ? profile.email : "Ask your Family Admin to add one.",
			ok: !!profile.email,
		},
		{
			label: "Few devices signed in",
			detail: `${devices} device${devices === 1 ? "" : "s"} right now.`,
			ok: devices <= 2,
			href: "#devices",
		},
	];
	return checks;
}

function SecurityCheckup({ profile, overview, devices }: { profile: Profile; overview: SecurityOverview; devices: number }) {
	const checks = checksFor(profile, overview, devices);
	const passed = checks.filter((c) => c.ok).length;
	const score = Math.round((passed / checks.length) * 100);
	const status = score >= 80 ? "good" : score >= 50 ? "warning" : "critical";
	const color = {
		good: "var(--status-good)",
		warning: "var(--status-warning)",
		critical: "var(--status-critical)",
	}[status];
	const verdict = {
		good: "Well protected",
		warning: "Could be stronger",
		critical: "Needs attention",
	}[status];

	return (
		<Panel bodyClassName="grid items-center gap-6 sm:grid-cols-[auto_1fr]">
			<div className="flex flex-col items-center gap-2">
				<ProgressRing value={score} size={112} stroke={10} color={color} label={`Security checkup ${passed} of ${checks.length}`}>
					<span className="text-2xl font-semibold tabular-nums text-slate-900">
						{passed}/{checks.length}
					</span>
					<span className="text-[11px] text-slate-500">checks</span>
				</ProgressRing>
				<span className="flex items-center gap-1 text-sm font-medium text-slate-700">
					{status === "good" ? (
						<ShieldCheck className="size-4 text-emerald-600" aria-hidden="true" />
					) : (
						<AlertTriangle className="size-4 text-amber-600" aria-hidden="true" />
					)}
					{verdict}
				</span>
			</div>
			<ul className="grid gap-2 sm:grid-cols-2">
				{checks.map((c, i) => (
					<li key={c.label} className="vk-rise flex items-start gap-3 rounded-xl p-2.5 ring-1 ring-slate-900/5" style={{ animationDelay: `${i * 50}ms` }}>
						{c.ok ? (
							<CheckCircle2 className="mt-0.5 size-5 shrink-0 text-emerald-600" aria-label="Done" />
						) : (
							<AlertTriangle className="mt-0.5 size-5 shrink-0 text-amber-500" aria-label="To do" />
						)}
						<div className="min-w-0 text-sm">
							{c.href && !c.ok ? (
								<a href={c.href} className="font-medium text-slate-900 underline-offset-4 hover:text-teal-800 hover:underline">
									{c.label}
								</a>
							) : (
								<p className="font-medium text-slate-900">{c.label}</p>
							)}
							<p className="line-clamp-2 text-xs text-slate-500">{c.detail}</p>
						</div>
					</li>
				))}
			</ul>
		</Panel>
	);
}

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
		<Panel title="Change password" description="Your other devices are signed out when you change it." className="scroll-mt-6" bodyClassName="p-5">
			<form id="password" className="grid gap-4" onSubmit={submit} noValidate>
				<FormErrors errors={errors} />
				<TextField
					id="current-password"
					label="Current password"
					type="password"
					autoComplete="current-password"
					value={current}
					onChange={(e) => setCurrent(e.target.value)}
				/>
				<TextField id="new-password" label="New password" type="password" autoComplete="new-password" value={next} onChange={(e) => setNext(e.target.value)} />
				<TextField
					id="confirm-password-new"
					label="Confirm new password"
					type="password"
					autoComplete="new-password"
					value={confirm}
					onChange={(e) => setConfirm(e.target.value)}
				/>
				<PasswordRules admin={admin} />
				<div>
					<Button type="submit" disabled={busy || !current || !next || !confirm}>
						{busy && <Spinner />}
						Change password
					</Button>
				</div>
			</form>
		</Panel>
	);
}

function DevicesCard({ sessions, reload }: { sessions: DeviceSession[] | null; reload(): void }) {
	async function run(action: () => Promise<unknown>, message: string) {
		try {
			await action();
			toast.success(message);
			reload();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}
	const others = sessions?.filter((s) => !s.current).length ?? 0;

	return (
		<Panel
			title="Where you're signed in"
			description="Sessions end after 30 minutes without activity, or 12 hours at most."
			className="scroll-mt-6"
			action={
				others > 0 ? (
					<Button variant="outline" size="sm" onClick={() => void run(() => profileApi.signOutOtherDevices(), "All other devices are signed out.")}>
						<LogOut aria-hidden="true" />
						Sign out others
					</Button>
				) : undefined
			}
		>
			<div id="devices" className="grid gap-2">
				{!sessions ? (
					<Spinner />
				) : (
					sessions.map((s) => {
						const Icon = /iOS|Android/.test(s.device) ? Smartphone : Monitor;
						return (
							<div key={s.id} className="flex flex-wrap items-center justify-between gap-2 rounded-xl p-3 ring-1 ring-slate-900/5">
								<div className="flex items-center gap-3">
									<span
										className={cn(
											"relative flex size-9 items-center justify-center rounded-lg",
											s.current ? "bg-teal-50 text-teal-700" : "bg-slate-100 text-slate-600",
										)}
									>
										<Icon className="size-4" aria-hidden="true" />
										{s.current && <span className="vk-pulse absolute -top-0.5 -right-0.5 size-2.5 rounded-full bg-emerald-500 ring-2 ring-white" />}
									</span>
									<div>
										<p className="text-sm font-medium text-slate-900">
											{s.device}
											{s.current && <span className="ml-2 rounded-full bg-teal-50 px-2 py-0.5 text-xs font-medium text-teal-800">This device</span>}
										</p>
										<p className="text-xs text-slate-500">
											Signed in {formatDateTime(s.startedAt)} · active {formatRelative(s.lastActivity)}
										</p>
									</div>
								</div>
								{!s.current && (
									<Button variant="ghost" size="sm" onClick={() => void run(() => profileApi.signOutDevice(s.id), "That device is signed out.")}>
										Sign out
									</Button>
								)}
							</div>
						);
					})
				)}
			</div>
		</Panel>
	);
}

const EVENT_STYLE: Record<string, { label: string; icon: LucideIcon; tone: "good" | "info" | "warn" | "bad" }> = {
	LOGIN_SUCCESS: { label: "Signed in", icon: LogIn, tone: "good" },
	LOGIN_FAILED: { label: "Failed sign-in", icon: XCircle, tone: "bad" },
	LOGIN_LOCKED: {
		label: "Sign-in refused - account locked",
		icon: Lock,
		tone: "bad",
	},
	ACCOUNT_LOCKED: { label: "Account locked", icon: Lock, tone: "bad" },
	LOGIN_THROTTLED: { label: "Too many attempts", icon: Clock, tone: "warn" },
	PASSWORD_SET: { label: "Password set", icon: KeyRound, tone: "info" },
	PASSWORD_CHANGED: { label: "Password changed", icon: KeyRound, tone: "info" },
	PASSWORD_RESET: {
		label: "Password reset by email link",
		icon: KeyRound,
		tone: "info",
	},
	PASSWORD_CHANGE_FAILED: {
		label: "Password change refused",
		icon: ShieldAlert,
		tone: "warn",
	},
	STEP_UP_FAILED: {
		label: "Confirmation failed",
		icon: ShieldAlert,
		tone: "warn",
	},
	MFA_ENABLED: { label: "Two-step turned on", icon: ShieldCheck, tone: "good" },
	MFA_DISABLED: { label: "Two-step turned off", icon: ShieldOff, tone: "warn" },
	MFA_RECOVERY_CODE_USED: {
		label: "Recovery code used",
		icon: KeyRound,
		tone: "warn",
	},
	MFA_RECOVERY_CODES_RENEWED: {
		label: "New recovery codes",
		icon: KeyRound,
		tone: "info",
	},
	SIGN_OUT_EVERYWHERE: {
		label: "Signed out other devices",
		icon: LogOut,
		tone: "info",
	},
	SESSION_REVOKED: { label: "Signed out a device", icon: LogOut, tone: "info" },
	ADMIN_PASSWORD_RESET: {
		label: "Password reset by your Family Admin",
		icon: UserCog,
		tone: "warn",
	},
	ADMIN_MFA_RESET: {
		label: "Two-step reset by your Family Admin",
		icon: UserCog,
		tone: "warn",
	},
	MEMBER_UNLOCKED: {
		label: "Unlocked by your Family Admin",
		icon: UserCog,
		tone: "info",
	},
	MEMBER_SESSIONS_REVOKED: {
		label: "Signed out by your Family Admin",
		icon: UserCog,
		tone: "info",
	},
};

const TONE = {
	good: "bg-emerald-50 text-emerald-700",
	info: "bg-sky-50 text-sky-700",
	warn: "bg-amber-50 text-amber-700",
	bad: "bg-red-50 text-red-700",
};

const ACTIVITY_PREVIEW = 8;

function ActivityCard({ events }: { events: SecurityEvent[] }) {
	const [all, setAll] = useState(false);
	const shown = all ? events : events.slice(0, ACTIVITY_PREVIEW);
	return (
		<Panel
			title="Recent security activity"
			description="Sign-ins and changes to your account in the last 30 days. Something you don't recognise? Change your password."
			action={
				events.length > ACTIVITY_PREVIEW ? (
					<Button variant="ghost" size="sm" onClick={() => setAll((a) => !a)}>
						{all ? "Show less" : `Show all ${events.length}`}
					</Button>
				) : undefined
			}
		>
			{events.length === 0 ? (
				<p className="py-6 text-center text-sm text-slate-500">Nothing yet - new activity can take a few seconds to appear.</p>
			) : (
				<ol className="relative grid gap-1 before:absolute before:top-2 before:bottom-2 before:left-[17px] before:w-px before:bg-slate-200">
					{shown.map((e, i) => {
						const style = EVENT_STYLE[e.type] ?? {
							label: e.type.replace(/_/g, " ").toLowerCase(),
							icon: ShieldAlert,
							tone: "info" as const,
						};
						return (
							<li key={`${e.at}-${i}`} className="vk-rise relative flex items-start gap-3 py-1.5" style={{ animationDelay: `${Math.min(i, 10) * 35}ms` }}>
								<span className={cn("relative z-10 flex size-9 shrink-0 items-center justify-center rounded-full ring-4 ring-white", TONE[style.tone])}>
									<style.icon className="size-4" aria-hidden="true" />
								</span>
								<div className="min-w-0 flex-1 pt-1">
									<p className="text-sm font-medium text-slate-900">{style.label}</p>
									{e.details && <p className="truncate text-xs text-slate-500">{e.details}</p>}
								</div>
								<time className="shrink-0 pt-1.5 text-xs text-slate-500" dateTime={e.at} title={formatDateTime(e.at)}>
									{formatRelative(e.at)}
								</time>
							</li>
						);
					})}
				</ol>
			)}
		</Panel>
	);
}

export default function ProfilePage() {
	const { profile, refresh } = useAuth();
	const { hash } = useLocation();
	const [overview, setOverview] = useState<SecurityOverview | null>(null);
	const [sessions, setSessions] = useState<DeviceSession[] | null>(null);

	const load = useCallback(async () => {
		try {
			const [o, s] = await Promise.all([profileApi.security(), profileApi.sessions()]);
			setOverview(o);
			setSessions(s);
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}, []);

	useEffect(() => {
		void load();
	}, [load]);

	// Links like /profile#two-step land on the section once the page has loaded.
	const loaded = overview !== null;
	useEffect(() => {
		if (loaded && hash) document.getElementById(hash.slice(1))?.scrollIntoView({ behavior: "smooth", block: "start" });
	}, [loaded, hash]);

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
		<>
			<title>Security · VK Finance</title>
			<PageHeader title="Security" description="Keep your account - and your family's money - safe." />
			{!overview ? (
				<div className="flex justify-center py-16">
					<Spinner className="size-6" />
				</div>
			) : (
				<div className="grid gap-6 lg:grid-cols-3">
					<div className="grid content-start gap-6 lg:col-span-2">
						<Reveal index={0}>
							<SecurityCheckup profile={profile} overview={overview} devices={sessions?.length ?? 1} />
						</Reveal>
						<Reveal index={1}>
							<TwoStepCard
								status={overview.mfa}
								onChanged={() => {
									void load();
									void refresh();
								}}
							/>
						</Reveal>
						<Reveal index={2}>
							<DevicesCard sessions={sessions} reload={() => void load()} />
						</Reveal>
						<Reveal index={3}>
							<ActivityCard events={overview.activity} />
						</Reveal>
					</div>
					<div className="grid content-start gap-6">
						<Reveal index={1}>
							<Panel title="Your details" description="Ask your Family Admin to change your name, email or role.">
								<dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2 text-sm">
									{details.map(([label, value]) => (
										<div key={label} className="contents">
											<dt className="text-slate-500">{label}</dt>
											<dd className="truncate text-slate-900">{value || "—"}</dd>
										</div>
									))}
								</dl>
							</Panel>
						</Reveal>
						<Reveal index={2}>
							<ChangePasswordCard admin={admin} />
						</Reveal>
					</div>
				</div>
			)}
		</>
	);
}
