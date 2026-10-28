import { useEffect, useState, type FormEvent } from "react";
import { Copy } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Spinner } from "@/components/ui/spinner";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/components/ui/dialog";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { OtpInput } from "@/components/security/OtpInput";
import { useAuth } from "@/features/auth/AuthContext";
import { errorMessages } from "@/api/vkfClient";
import { familyApi } from "@/api/endpoints";
import { RELATIONSHIPS, ROLES, type CreatedMember, type Member, type MemberInput, type Role } from "@/api/types";

interface SelectFieldProps {
	id: string;
	label: string;
	value: string;
	options: readonly string[];
	onChange(value: string): void;
	disabled?: boolean;
}

function SelectField({ id, label, value, options, onChange, disabled }: SelectFieldProps) {
	return (
		<div className="grid gap-1.5">
			<Label htmlFor={id}>{label}</Label>
			<Select value={value} onValueChange={onChange} disabled={disabled}>
				<SelectTrigger id={id} className="w-full">
					<SelectValue placeholder={`Choose ${label.toLowerCase()}`} />
				</SelectTrigger>
				<SelectContent>
					{options.map((option) => (
						<SelectItem key={option} value={option}>
							{option}
						</SelectItem>
					))}
				</SelectContent>
			</Select>
		</div>
	);
}

function roleOptions(actorIsFamilyAdmin: boolean): Role[] {
	return actorIsFamilyAdmin ? ROLES : ROLES.filter((role) => role !== "Family Admin");
}

const EMPTY: MemberInput = {
	firstName: "",
	lastName: "",
	username: "",
	email: "",
	mobile: "",
	relationship: "Son",
	role: "Member",
	viewerScope: "Own",
};

export function AddMemberDialog({
	open,
	onOpenChange,
	actorIsFamilyAdmin,
	onCreated,
}: {
	open: boolean;
	onOpenChange(open: boolean): void;
	actorIsFamilyAdmin: boolean;
	onCreated(result: CreatedMember): void;
}) {
	const [form, setForm] = useState<MemberInput>(EMPTY);
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	useEffect(() => {
		if (open) {
			setForm(EMPTY);
			setErrors([]);
		}
	}, [open]);

	const set = (key: keyof MemberInput) => (value: string) => setForm((current) => ({ ...current, [key]: value }));

	async function submit(event: FormEvent) {
		event.preventDefault();
		setErrors([]);
		setBusy(true);
		try {
			const result = await familyApi.addMember({
				...form,
				viewerScope: form.role === "Viewer" ? form.viewerScope : undefined,
			});
			onCreated(result);
			onOpenChange(false);
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	return (
		<Dialog open={open} onOpenChange={onOpenChange}>
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Add a family member</DialogTitle>
					<DialogDescription>
						They'll get a temporary password and choose their own at first sign-in.
					</DialogDescription>
				</DialogHeader>
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<div className="grid gap-4 sm:grid-cols-2">
						<TextField id="add-first" label="First name" value={form.firstName} onChange={(e) => set("firstName")(e.target.value)} required />
						<TextField id="add-last" label="Last name" value={form.lastName} onChange={(e) => set("lastName")(e.target.value)} required />
						<TextField
							id="add-username"
							label="Username"
							autoCapitalize="none"
							value={form.username}
							onChange={(e) => set("username")(e.target.value)}
							hint="4–40 characters: letters, digits, . _ -"
							required
						/>
						<TextField id="add-email" label="Email (optional)" type="email" value={form.email} onChange={(e) => set("email")(e.target.value)} hint="Needed for self-service password reset." />
						<TextField id="add-mobile" label="Mobile (optional)" type="tel" value={form.mobile} onChange={(e) => set("mobile")(e.target.value)} />
						<SelectField id="add-relationship" label="Relationship" value={form.relationship ?? ""} options={RELATIONSHIPS} onChange={set("relationship")} />
						<SelectField id="add-role" label="Role" value={form.role ?? "Member"} options={roleOptions(actorIsFamilyAdmin)} onChange={set("role")} />
						{form.role === "Viewer" && (
							<SelectField id="add-scope" label="Viewer can see" value={form.viewerScope ?? "Own"} options={["Own", "Family"]} onChange={set("viewerScope")} />
						)}
					</div>
					<DialogFooter>
						<Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
							Cancel
						</Button>
						<Button type="submit" disabled={busy}>
							{busy && <Spinner />}
							Add member
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

export function EditMemberDialog({
	member,
	actorIsFamilyAdmin,
	onClose,
	onSaved,
}: {
	member: Member | null;
	actorIsFamilyAdmin: boolean;
	onClose(): void;
	onSaved(): void;
}) {
	const { profile } = useAuth();
	const needsCode = !!profile?.mfaEnabled;
	const [form, setForm] = useState<MemberInput>({});
	const [password, setPassword] = useState("");
	const [code, setCode] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	useEffect(() => {
		if (member) {
			setForm({
				firstName: member.firstName,
				lastName: member.lastName,
				email: member.email ?? "",
				mobile: member.mobile ?? "",
				relationship: member.relationship ?? "Other",
				role: member.role,
				viewerScope: member.viewerScope ?? "Own",
			});
			setPassword("");
			setCode("");
			setErrors([]);
		}
	}, [member]);

	if (!member) return null;
	const roleChanged = form.role !== member.role;
	const set = (key: keyof MemberInput) => (value: string) => setForm((current) => ({ ...current, [key]: value }));

	async function submit(event: FormEvent) {
		event.preventDefault();
		if (!member) return;
		setErrors([]);
		setBusy(true);
		try {
			const changes: MemberInput = {
				firstName: form.firstName,
				lastName: form.lastName,
				email: form.email,
				mobile: form.mobile,
				relationship: form.relationship,
				viewerScope: form.viewerScope,
			};
			if (roleChanged) {
				changes.role = form.role;
				changes.currentPassword = password;
				if (needsCode) changes.code = code;
			}
			await familyApi.updateMember(member.id, changes);
			toast.success(`${form.firstName}'s details are saved.`);
			onSaved();
			onClose();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setBusy(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-lg">
				<DialogHeader>
					<DialogTitle>Edit {member.firstName}</DialogTitle>
					<DialogDescription>Username {member.username} can't be changed.</DialogDescription>
				</DialogHeader>
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<div className="grid gap-4 sm:grid-cols-2">
						<TextField id="edit-first" label="First name" value={form.firstName ?? ""} onChange={(e) => set("firstName")(e.target.value)} />
						<TextField id="edit-last" label="Last name" value={form.lastName ?? ""} onChange={(e) => set("lastName")(e.target.value)} />
						<TextField id="edit-email" label="Email" type="email" value={form.email ?? ""} onChange={(e) => set("email")(e.target.value)} />
						<TextField id="edit-mobile" label="Mobile" type="tel" value={form.mobile ?? ""} onChange={(e) => set("mobile")(e.target.value)} />
						<SelectField id="edit-relationship" label="Relationship" value={form.relationship ?? ""} options={RELATIONSHIPS} onChange={set("relationship")} />
						<SelectField
							id="edit-role"
							label="Role"
							value={form.role ?? member.role}
							options={roleOptions(actorIsFamilyAdmin)}
							onChange={set("role")}
							disabled={member.isSelf}
						/>
						{form.role === "Viewer" && (
							<SelectField id="edit-scope" label="Viewer can see" value={form.viewerScope ?? "Own"} options={["Own", "Family"]} onChange={set("viewerScope")} />
						)}
					</div>
					{roleChanged && (
						<TextField
							id="edit-confirm-password"
							label="Your password"
							type="password"
							autoComplete="current-password"
							value={password}
							onChange={(e) => setPassword(e.target.value)}
							hint="Changing a role signs the member out and needs your password."
						/>
					)}
					{roleChanged && needsCode && (
						<div className="grid gap-2">
							<span className="text-sm font-medium">Code from your authenticator app</span>
							<OtpInput value={code} onChange={setCode} disabled={busy} />
						</div>
					)}
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={busy || (roleChanged && (!password || (needsCode && code.length !== 6)))}>
							{busy && <Spinner />}
							Save
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

export interface PasswordConfirmation {
	title: string;
	description: string;
	confirmLabel: string;
	destructive?: boolean;
	run(password: string, code?: string): Promise<void>;
}

/** Re-asks the admin's own password - and a code when two-step is on - before a sensitive change (the server checks both). */
export function PasswordConfirmDialog({ action, onClose }: { action: PasswordConfirmation | null; onClose(): void }) {
	const { profile } = useAuth();
	const needsCode = !!profile?.mfaEnabled;
	const [password, setPassword] = useState("");
	const [code, setCode] = useState("");
	const [errors, setErrors] = useState<string[]>([]);
	const [busy, setBusy] = useState(false);

	useEffect(() => {
		setPassword("");
		setCode("");
		setErrors([]);
	}, [action]);

	if (!action) return null;

	async function submit(event: FormEvent) {
		event.preventDefault();
		if (!action) return;
		setErrors([]);
		setBusy(true);
		try {
			await action.run(password, needsCode ? code : undefined);
			onClose();
		} catch (error) {
			setErrors(errorMessages(error));
			setCode("");
		} finally {
			setBusy(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>{action.title}</DialogTitle>
					<DialogDescription>{action.description}</DialogDescription>
				</DialogHeader>
				<form className="grid gap-4" onSubmit={submit} noValidate>
					<FormErrors errors={errors} />
					<TextField
						id="confirm-own-password"
						label="Your password"
						type="password"
						autoComplete="current-password"
						value={password}
						onChange={(e) => setPassword(e.target.value)}
						autoFocus
					/>
					{needsCode && (
						<div className="grid gap-2">
							<span className="text-sm font-medium">Code from your authenticator app</span>
							<OtpInput value={code} onChange={setCode} disabled={busy} />
						</div>
					)}
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button
							type="submit"
							variant={action.destructive ? "destructive" : "default"}
							disabled={busy || !password || (needsCode && code.length !== 6)}
						>
							{busy && <Spinner />}
							{action.confirmLabel}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}

export function TemporaryPasswordDialog({
	credentials,
	onClose,
}: {
	credentials: { name: string; username: string; password: string } | null;
	onClose(): void;
}) {
	if (!credentials) return null;

	async function copy() {
		if (!credentials) return;
		try {
			await navigator.clipboard.writeText(`Username: ${credentials.username}\nTemporary password: ${credentials.password}`);
			toast.success("Copied to clipboard.");
		} catch {
			toast.error("Couldn't copy - select the text instead.");
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent>
				<DialogHeader>
					<DialogTitle>Temporary password for {credentials.name}</DialogTitle>
					<DialogDescription>
						This is shown only once. Share it privately - it works for 24 hours and must be changed at first
						sign-in.
					</DialogDescription>
				</DialogHeader>
				<dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 rounded-lg bg-slate-100 p-4 text-sm">
					<dt className="text-slate-600">Username</dt>
					<dd className="font-mono">{credentials.username}</dd>
					<dt className="text-slate-600">Password</dt>
					<dd className="font-mono" data-testid="temporary-password">
						{credentials.password}
					</dd>
				</dl>
				<DialogFooter>
					<Button variant="outline" onClick={() => void copy()}>
						<Copy aria-hidden="true" />
						Copy
					</Button>
					<Button onClick={onClose}>Done</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
