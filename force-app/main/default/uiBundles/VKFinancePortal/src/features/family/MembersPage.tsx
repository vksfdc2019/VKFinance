import { useCallback, useEffect, useState } from "react";
import { MoreHorizontal, ShieldCheck, UserPlus } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Spinner } from "@/components/ui/spinner";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuSeparator,
	DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { toast } from "@/components/ui/sonner";
import { FormErrors } from "@/components/forms";
import { familyApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Member } from "@/api/types";
import { formatRelative } from "@/lib/format";
import { useAuth } from "@/features/auth/AuthContext";
import {
	AddMemberDialog,
	EditMemberDialog,
	PasswordConfirmDialog,
	TemporaryPasswordDialog,
	type PasswordConfirmation,
} from "./MemberDialogs";

function StatusBadge({ member }: { member: Member }) {
	if (member.locked) return <Badge variant="destructive">Locked</Badge>;
	if (member.status === "Active") return <Badge variant="secondary">Active</Badge>;
	if (member.status === "Invited") return <Badge variant="outline">Invited</Badge>;
	return <Badge variant="outline">{member.status}</Badge>;
}

export default function MembersPage() {
	const { profile } = useAuth();
	const actorIsFamilyAdmin = profile?.role === "Family Admin";
	const [members, setMembers] = useState<Member[] | null>(null);
	const [errors, setErrors] = useState<string[]>([]);
	const [adding, setAdding] = useState(false);
	const [editing, setEditing] = useState<Member | null>(null);
	const [confirmation, setConfirmation] = useState<PasswordConfirmation | null>(null);
	const [credentials, setCredentials] = useState<{ name: string; username: string; password: string } | null>(null);

	const load = useCallback(async () => {
		try {
			setMembers(await familyApi.members());
			setErrors([]);
		} catch (error) {
			setErrors(errorMessages(error));
		}
	}, []);

	useEffect(() => {
		void load();
	}, [load]);

	async function quickAction(run: () => Promise<unknown>, success: string) {
		try {
			await run();
			toast.success(success);
			await load();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	function canManage(member: Member) {
		return actorIsFamilyAdmin || member.role !== "Family Admin";
	}

	function confirmStatus(member: Member, status: "Active" | "Disabled" | "Removed") {
		const copy = {
			Disabled: {
				title: `Disable ${member.firstName}?`,
				description: "They're signed out everywhere and can't sign in until you enable them again. Their data stays.",
				label: "Disable",
			},
			Active: { title: `Enable ${member.firstName}?`, description: "They can sign in again with their current password.", label: "Enable" },
			Removed: {
				title: `Remove ${member.firstName} from the family?`,
				description: "Their sign-in is deleted for good. Records they created stay in the family's history.",
				label: "Remove member",
			},
		}[status];
		setConfirmation({
			title: copy.title,
			description: copy.description,
			confirmLabel: copy.label,
			destructive: status !== "Active",
			run: async (password, code) => {
				await familyApi.updateMember(member.id, { status, currentPassword: password, code });
				toast.success(`${member.firstName} is now ${status.toLowerCase()}.`);
				await load();
			},
		});
	}

	function confirmReset(member: Member) {
		setConfirmation({
			title: `Reset ${member.firstName}'s password?`,
			description: "We'll create a temporary password and sign them out on every device.",
			confirmLabel: "Reset password",
			run: async (password, code) => {
				const { temporaryPassword } = await familyApi.resetPassword(member.id, password, code);
				setCredentials({ name: member.firstName, username: member.username, password: temporaryPassword });
				await load();
			},
		});
	}

	function confirmResetMfa(member: Member) {
		setConfirmation({
			title: `Reset ${member.firstName}'s two-step verification?`,
			description:
				"For when they've lost their phone and their recovery codes. Two-step turns off and they're signed out everywhere; they can sign in with their password and set it up again.",
			confirmLabel: "Reset two-step",
			destructive: true,
			run: async (password, code) => {
				await familyApi.resetMfa(member.id, password, code);
				toast.success(`${member.firstName}'s two-step verification is reset.`);
				await load();
			},
		});
	}

	return (
		<div className="grid gap-6">
			<title>Family · VK Finance</title>
			<div className="flex flex-wrap items-end justify-between gap-4">
				<div>
					<h1 className="text-2xl font-semibold text-slate-900 dark:text-slate-100">Family members</h1>
					<p className="text-slate-600 dark:text-slate-400">
						{profile?.familyName} · {profile?.familyCode}
					</p>
				</div>
				<Button onClick={() => setAdding(true)}>
					<UserPlus aria-hidden="true" />
					Add member
				</Button>
			</div>
			<FormErrors errors={errors} />
			<Card>
				<CardHeader>
					<CardTitle className="text-base">Who can sign in</CardTitle>
					<CardDescription>Only your family's members appear here.</CardDescription>
				</CardHeader>
				<CardContent>
					{!members ? (
						<div className="flex justify-center py-8">
							<Spinner className="size-6" />
						</div>
					) : (
						<Table>
							<TableHeader>
								<TableRow>
									<TableHead>Name</TableHead>
									<TableHead>Username</TableHead>
									<TableHead>Role</TableHead>
									<TableHead>Status</TableHead>
									<TableHead className="hidden md:table-cell">Last sign-in</TableHead>
									<TableHead className="hidden md:table-cell">Devices</TableHead>
									<TableHead className="w-10">
										<span className="sr-only">Actions</span>
									</TableHead>
								</TableRow>
							</TableHeader>
							<TableBody>
								{members.map((member) => (
									<TableRow key={member.id}>
										<TableCell className="font-medium">
											{member.firstName} {member.lastName}
											{member.mfaEnabled && <ShieldCheck className="ml-1.5 inline size-4 text-emerald-600 dark:text-emerald-400" aria-label="Two-step on" />}
											{member.isSelf && <span className="ml-2 text-xs text-slate-500 dark:text-slate-400">(you)</span>}
											{member.relationship && <div className="text-xs text-slate-500 dark:text-slate-400">{member.relationship}</div>}
										</TableCell>
										<TableCell className="font-mono text-sm">{member.username}</TableCell>
										<TableCell>{member.role}</TableCell>
										<TableCell>
											<StatusBadge member={member} />
										</TableCell>
										<TableCell className="hidden md:table-cell">{formatRelative(member.lastLogin)}</TableCell>
										<TableCell className="hidden md:table-cell">{member.activeSessions}</TableCell>
										<TableCell>
											{canManage(member) && (
												<DropdownMenu modal={false}>
													<DropdownMenuTrigger asChild>
														<Button variant="ghost" size="icon" aria-label={`Actions for ${member.firstName}`}>
															<MoreHorizontal aria-hidden="true" />
														</Button>
													</DropdownMenuTrigger>
													<DropdownMenuContent align="end">
														<DropdownMenuItem onSelect={() => setEditing(member)}>Edit details</DropdownMenuItem>
														{member.locked && (
															<DropdownMenuItem
																onSelect={() => void quickAction(() => familyApi.unlock(member.id), `${member.firstName} is unlocked.`)}
															>
																Unlock
															</DropdownMenuItem>
														)}
														{!member.isSelf && member.status !== "Disabled" && (
															<DropdownMenuItem onSelect={() => confirmReset(member)}>Reset password</DropdownMenuItem>
														)}
														{!member.isSelf && member.mfaEnabled && (
															<DropdownMenuItem onSelect={() => confirmResetMfa(member)}>Reset two-step</DropdownMenuItem>
														)}
														{member.activeSessions > 0 && !member.isSelf && (
															<DropdownMenuItem
																onSelect={() =>
																	void quickAction(
																		() => familyApi.signOutMember(member.id),
																		`${member.firstName} is signed out everywhere.`,
																	)
																}
															>
																Sign out everywhere
															</DropdownMenuItem>
														)}
														{!member.isSelf && (
															<>
																<DropdownMenuSeparator />
																{member.status === "Disabled" ? (
																	<DropdownMenuItem onSelect={() => confirmStatus(member, "Active")}>Enable</DropdownMenuItem>
																) : (
																	member.status === "Active" && (
																		<DropdownMenuItem onSelect={() => confirmStatus(member, "Disabled")}>Disable</DropdownMenuItem>
																	)
																)}
																<DropdownMenuItem variant="destructive" onSelect={() => confirmStatus(member, "Removed")}>
																	Remove from family
																</DropdownMenuItem>
															</>
														)}
													</DropdownMenuContent>
												</DropdownMenu>
											)}
										</TableCell>
									</TableRow>
								))}
							</TableBody>
						</Table>
					)}
				</CardContent>
			</Card>

			<AddMemberDialog
				open={adding}
				onOpenChange={setAdding}
				actorIsFamilyAdmin={actorIsFamilyAdmin}
				onCreated={(result) => {
					setCredentials({ name: result.member.firstName, username: result.member.username, password: result.temporaryPassword });
					void load();
				}}
			/>
			<EditMemberDialog member={editing} actorIsFamilyAdmin={actorIsFamilyAdmin} onClose={() => setEditing(null)} onSaved={() => void load()} />
			<PasswordConfirmDialog action={confirmation} onClose={() => setConfirmation(null)} />
			<TemporaryPasswordDialog credentials={credentials} onClose={() => setCredentials(null)} />
		</div>
	);
}
