import { useState, type FormEvent, type ReactNode } from "react";
import { Check, Copy, Download, KeyRound, ShieldCheck, ShieldOff, Smartphone } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { OtpInput } from "@/components/security/OtpInput";
import { QrCode } from "@/components/security/QrCode";
import { profileApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { MfaSetup, MfaStatus } from "@/api/types";
import { formatDate } from "@/lib/format";
import { cn } from "@/lib/utils";

/** The two-step card on the Security page: set up, renew recovery codes, or turn off. */
export function TwoStepCard({ status, onChanged }: { status: MfaStatus; onChanged(): void }) {
	const [setup, setSetup] = useState(false);
	const [confirm, setConfirm] = useState<"disable" | "renew" | null>(null);
	const [codes, setCodes] = useState<string[] | null>(null);
	const low = status.enabled && status.recoveryCodesLeft <= 3;

	return (
		<section id="two-step" className="overflow-hidden rounded-2xl bg-white shadow-sm ring-1 ring-slate-900/5">
			<div
				className={cn(
					"flex flex-wrap items-center gap-4 p-5",
					status.enabled ? "bg-gradient-to-r from-emerald-50 to-white" : "bg-gradient-to-r from-amber-50 to-white",
				)}
			>
				<span
					className={cn(
						"flex size-12 shrink-0 items-center justify-center rounded-2xl shadow-sm ring-1",
						status.enabled ? "bg-emerald-600 text-white ring-emerald-700/20" : "bg-white text-amber-600 ring-amber-200",
					)}
				>
					{status.enabled ? <ShieldCheck className="size-6" aria-hidden="true" /> : <ShieldOff className="size-6" aria-hidden="true" />}
				</span>
				<div className="min-w-0 flex-1">
					<h2 className="text-base font-semibold text-slate-900">Two-step verification</h2>
					<p className="text-sm text-slate-600">
						{status.enabled
							? `On since ${formatDate(status.enrolledAt)}. Signing in needs your password and a code from your phone.`
							: "Off. Anyone who learns your password can sign in. Add a code from your phone as a second lock."}
					</p>
				</div>
				{!status.enabled && (
					<Button onClick={() => setSetup(true)}>
						<ShieldCheck aria-hidden="true" />
						Set up
					</Button>
				)}
			</div>
			{status.enabled && (
				<div className="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 p-5">
					<div className="flex items-center gap-3 text-sm">
						<KeyRound className={cn("size-5", low ? "text-amber-600" : "text-slate-400")} aria-hidden="true" />
						<div>
							<p className="font-medium text-slate-900">{status.recoveryCodesLeft} of 10 recovery codes left</p>
							<p className={cn("text-xs", low ? "text-amber-700" : "text-slate-500")}>
								{low ? "Running low - make a fresh set." : "Use one if you can't reach your phone. Each works once."}
							</p>
						</div>
					</div>
					<div className="flex flex-wrap gap-2">
						<Button variant="outline" onClick={() => setConfirm("renew")}>
							New recovery codes
						</Button>
						<Button variant="ghost" className="text-red-700 hover:bg-red-50 hover:text-red-800" onClick={() => setConfirm("disable")}>
							Turn off
						</Button>
					</div>
				</div>
			)}

			{setup && (
				<SetupDialog
					onClose={() => setSetup(false)}
					onDone={() => {
						setSetup(false);
						onChanged();
					}}
				/>
			)}
			{confirm && (
				<ConfirmWithCodeDialog
					title={confirm === "disable" ? "Turn off two-step verification?" : "Make new recovery codes?"}
					description={confirm === "disable" ? "Your account will be protected by your password only." : "Your old recovery codes stop working straight away."}
					confirmLabel={confirm === "disable" ? "Turn off" : "Make new codes"}
					destructive={confirm === "disable"}
					onClose={() => setConfirm(null)}
					run={async (password, code) => {
						if (confirm === "disable") {
							await profileApi.disableMfa(password, code);
							toast.success("Two-step verification is off.");
						} else {
							setCodes((await profileApi.renewRecoveryCodes(password, code)).recoveryCodes);
						}
						setConfirm(null);
						onChanged();
					}}
				/>
			)}
			{codes && (
				<Dialog open onOpenChange={(open) => !open && setCodes(null)}>
					<DialogContent className="sm:max-w-lg">
						<DialogHeader>
							<DialogTitle>Your new recovery codes</DialogTitle>
							<DialogDescription>Save these now - they won't be shown again.</DialogDescription>
						</DialogHeader>
						<RecoveryCodes codes={codes} onDone={() => setCodes(null)} />
					</DialogContent>
				</Dialog>
			)}
		</section>
	);
}

type Step = "password" | "scan" | "codes";
const STEPS: { key: Step; label: string }[] = [
	{ key: "password", label: "Confirm" },
	{ key: "scan", label: "Connect app" },
	{ key: "codes", label: "Save codes" },
];

/** Three steps: confirm the password, scan the QR code and enter a code, save recovery codes. */
function SetupDialog({ onClose, onDone }: { onClose(): void; onDone(): void }) {
	const [step, setStep] = useState<Step>("password");
	const [password, setPassword] = useState("");
	const [setup, setSetup] = useState<MfaSetup | null>(null);
	const [code, setCode] = useState("");
	const [failures, setFailures] = useState(0);
	const [codes, setCodes] = useState<string[]>([]);
	const [manual, setManual] = useState(false);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);
	const index = STEPS.findIndex((s) => s.key === step);

	async function start(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			setSetup(await profileApi.startMfa(password));
			setStep("scan");
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setPassword("");
			setBusy(false);
		}
	}

	async function verify(value = code) {
		if (busy) return;
		setErrors([]);
		setBusy(true);
		try {
			setCodes((await profileApi.confirmMfa(value)).recoveryCodes);
			setStep("codes");
		} catch (error) {
			setErrors(errorMessages(error));
			setCode("");
			setFailures((n) => n + 1);
		} finally {
			setBusy(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && (step === "codes" ? onDone() : onClose())}>
			<DialogContent className="sm:max-w-xl">
				<DialogHeader>
					<DialogTitle>Set up two-step verification</DialogTitle>
					<DialogDescription>Takes about a minute. You'll need your phone.</DialogDescription>
				</DialogHeader>
				<ol className="mb-1 grid grid-cols-3 gap-2" aria-label="Progress">
					{STEPS.map((s, i) => (
						<li key={s.key} className="grid gap-1.5" aria-current={i === index ? "step" : undefined}>
							<span className={cn("h-1.5 rounded-full transition-colors duration-500", i <= index ? "bg-teal-600" : "bg-slate-200")} />
							<span className={cn("text-xs", i === index ? "font-medium text-slate-900" : "text-slate-500")}>
								{i < index ? <Check className="mr-1 inline size-3 text-teal-700" aria-hidden="true" /> : null}
								{s.label}
							</span>
						</li>
					))}
				</ol>
				<FormErrors errors={errors} />

				{step === "password" && (
					<form key="password" className="vk-rise grid gap-4" onSubmit={start} noValidate>
						<TextField
							id="mfa-password"
							label="Your password"
							type="password"
							autoComplete="current-password"
							value={password}
							onChange={(e) => setPassword(e.target.value)}
							hint="So no one using an unlocked device can do this for you."
							autoFocus
						/>
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={busy || !password}>
								{busy && <Spinner />}
								Continue
							</Button>
						</DialogFooter>
					</form>
				)}

				{step === "scan" && setup && (
					<form
						key="scan"
						className="vk-rise grid gap-5"
						onSubmit={(e) => {
							e.preventDefault();
							void verify();
						}}
						noValidate
					>
						<div className="grid items-center gap-5 sm:grid-cols-[auto_1fr]">
							<div className="mx-auto rounded-2xl bg-white p-2 shadow-sm ring-1 ring-slate-900/10">
								<QrCode text={setup.otpauthUri} size={176} label="QR code to add VK Finance to your authenticator app" />
							</div>
							<ol className="grid gap-3 text-sm text-slate-700">
								<Instruction n={1}>
									Install an authenticator app - <span className="font-medium">Google Authenticator</span>,{" "}
									<span className="font-medium">Microsoft Authenticator</span> or similar.
								</Instruction>
								<Instruction n={2}>In the app, add an account and scan this QR code.</Instruction>
								<Instruction n={3}>Type the 6-digit code the app shows for VK Finance.</Instruction>
							</ol>
						</div>
						<div className="text-sm">
							{manual ? (
								<SecretKey secret={setup.secret} />
							) : (
								<button type="button" className="text-teal-800 underline-offset-4 hover:underline" onClick={() => setManual(true)}>
									Can't scan? Enter a key instead
								</button>
							)}
						</div>
						<OtpInput value={code} onChange={setCode} onComplete={(v) => void verify(v)} disabled={busy} invalid={failures} autoFocus />
						<DialogFooter>
							<Button type="button" variant="outline" onClick={onClose}>
								Cancel
							</Button>
							<Button type="submit" disabled={busy || code.length !== 6}>
								{busy ? <Spinner /> : <Smartphone aria-hidden="true" />}
								Verify code
							</Button>
						</DialogFooter>
					</form>
				)}

				{step === "codes" && (
					<div key="codes" className="vk-rise grid gap-4">
						<div className="flex items-center gap-3 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-900">
							<span className="vk-pop flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-600 text-white">
								<Check className="size-5" aria-hidden="true" />
							</span>
							Two-step verification is on. Other devices have been signed out.
						</div>
						<p className="text-sm text-slate-600">
							Save these recovery codes somewhere safe, away from your phone. If you lose your phone, each code lets you sign in once.
						</p>
						<RecoveryCodes codes={codes} onDone={onDone} />
					</div>
				)}
			</DialogContent>
		</Dialog>
	);
}

function Instruction({ n, children }: { n: number; children: ReactNode }) {
	return (
		<li className="flex gap-3">
			<span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-teal-50 text-xs font-semibold text-teal-800">{n}</span>
			<span>{children}</span>
		</li>
	);
}

function SecretKey({ secret }: { secret: string }) {
	const grouped = secret.match(/.{1,4}/g)?.join(" ") ?? secret;
	return (
		<div className="vk-rise flex flex-wrap items-center gap-2 rounded-xl bg-slate-50 p-3">
			<span className="text-slate-600">Key:</span>
			<code className="font-mono text-sm tracking-wider text-slate-900 select-all">{grouped}</code>
			<CopyButton text={secret} label="Copy key" />
			<p className="w-full text-xs text-slate-500">Choose "time-based" if the app asks.</p>
		</div>
	);
}

/** The recovery-code list with copy, download and an "I've saved them" check before closing. */
export function RecoveryCodes({ codes, onDone }: { codes: string[]; onDone(): void }) {
	const [saved, setSaved] = useState(false);
	const text = `VK Finance recovery codes\nEach code works once.\n\n${codes.join("\n")}\n`;

	function download() {
		const url = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
		const link = document.createElement("a");
		link.href = url;
		link.download = "vk-finance-recovery-codes.txt";
		link.click();
		URL.revokeObjectURL(url);
	}

	return (
		<div className="grid gap-4">
			<ul className="grid grid-cols-2 gap-2 rounded-xl bg-slate-50 p-4" data-testid="recovery-codes">
				{codes.map((c, i) => (
					<li
						key={c}
						className="vk-rise rounded-lg bg-white px-3 py-2 text-center font-mono text-sm tracking-wider text-slate-900 ring-1 ring-slate-900/5"
						style={{ animationDelay: `${i * 30}ms` }}
					>
						{c}
					</li>
				))}
			</ul>
			<div className="flex flex-wrap gap-2">
				<CopyButton text={text} label="Copy all" />
				<Button type="button" variant="outline" size="sm" onClick={download}>
					<Download aria-hidden="true" />
					Download
				</Button>
			</div>
			<label className="flex items-center gap-2 text-sm text-slate-700">
				<Checkbox checked={saved} onCheckedChange={(v) => setSaved(v === true)} />
				I've saved my recovery codes
			</label>
			<DialogFooter>
				<Button onClick={onDone} disabled={!saved}>
					Done
				</Button>
			</DialogFooter>
		</div>
	);
}

function CopyButton({ text, label }: { text: string; label: string }) {
	const [copied, setCopied] = useState(false);
	return (
		<Button
			type="button"
			variant="outline"
			size="sm"
			onClick={async () => {
				try {
					await navigator.clipboard.writeText(text);
					setCopied(true);
					setTimeout(() => setCopied(false), 1800);
				} catch {
					toast.error("Couldn't copy - select the text and copy it instead.");
				}
			}}
		>
			{copied ? <Check aria-hidden="true" /> : <Copy aria-hidden="true" />}
			{copied ? "Copied" : label}
		</Button>
	);
}

/**
 * Re-asks the password, plus a code when two-step is on. Used for turning two-step off,
 * new recovery codes, and the admin actions on the Family page.
 */
export function ConfirmWithCodeDialog({
	title,
	description,
	confirmLabel,
	destructive,
	needsCode = true,
	onClose,
	run,
}: {
	title: string;
	description: ReactNode;
	confirmLabel: string;
	destructive?: boolean;
	needsCode?: boolean;
	onClose(): void;
	run(password: string, code: string): Promise<void>;
}) {
	const [password, setPassword] = useState("");
	const [code, setCode] = useState("");
	const [recovery, setRecovery] = useState(false);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);
	const ready = !!password && (!needsCode || (recovery ? code.trim().length >= 10 : code.length === 6));

	async function submit(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			await run(password, code);
		} catch (error) {
			setErrors(errorMessages(error));
			setCode("");
			setBusy(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{title}</DialogTitle>
					<DialogDescription>{description}</DialogDescription>
				</DialogHeader>
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<TextField
						id="confirm-password"
						label="Your password"
						type="password"
						autoComplete="current-password"
						value={password}
						onChange={(e) => setPassword(e.target.value)}
						autoFocus
					/>
					{needsCode && (
						<div className="grid gap-2">
							<div className="flex items-center justify-between">
								<span className="text-sm font-medium">{recovery ? "Recovery code" : "Code from your authenticator app"}</span>
								<button
									type="button"
									className="text-xs text-teal-800 underline-offset-4 hover:underline"
									onClick={() => {
										setRecovery((r) => !r);
										setCode("");
									}}
								>
									{recovery ? "Use app code" : "Use a recovery code"}
								</button>
							</div>
							{recovery ? (
								<TextField
									id="confirm-recovery"
									label="Recovery code"
									className="font-mono"
									autoComplete="off"
									value={code}
									onChange={(e) => setCode(e.target.value)}
								/>
							) : (
								<OtpInput value={code} onChange={setCode} disabled={busy} />
							)}
						</div>
					)}
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" variant={destructive ? "destructive" : "default"} disabled={busy || !ready}>
							{busy && <Spinner />}
							{confirmLabel}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
