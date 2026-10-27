export type Role = "Family Admin" | "Co-Admin" | "Member" | "Child" | "Viewer";
export type MemberStatus = "Invited" | "Active" | "Disabled" | "Removed";

export const ROLES: Role[] = ["Family Admin", "Co-Admin", "Member", "Child", "Viewer"];
export const RELATIONSHIPS = [
	"Self",
	"Spouse",
	"Son",
	"Daughter",
	"Father",
	"Mother",
	"Brother",
	"Sister",
	"Grandparent",
	"Other",
] as const;

export interface Profile {
	userId: string;
	firstName: string;
	lastName: string;
	username: string;
	email?: string;
	mobile?: string;
	relationship?: string;
	role: Role;
	status: MemberStatus;
	familyId: string;
	familyName: string;
	familyCode: string;
	currencyCode?: string;
	mustChangePassword: boolean;
	sessionScope: "FULL" | "CHANGE_PASSWORD";
	idleTimeoutMinutes: number;
	permissions: string[];
}

export interface LoginResult {
	token: string;
	mustChangePassword: boolean;
	profile: Profile;
}

export interface Member {
	id: string;
	firstName: string;
	lastName: string;
	username: string;
	email?: string;
	mobile?: string;
	relationship?: string;
	role: Role;
	status: MemberStatus;
	viewerScope?: "Own" | "Family";
	locked: boolean;
	lockedUntil?: string;
	lastLogin?: string;
	mustChangePassword: boolean;
	activeSessions: number;
	isSelf: boolean;
}

export interface CreatedMember {
	member: Member;
	temporaryPassword: string;
}

export interface DeviceSession {
	id: string;
	startedAt: string;
	lastActivity: string;
	expiresAt: string;
	device: string;
	current: boolean;
}

export interface MemberInput {
	firstName?: string;
	lastName?: string;
	username?: string;
	email?: string;
	mobile?: string;
	relationship?: string;
	role?: Role;
	viewerScope?: "Own" | "Family";
	status?: MemberStatus;
	currentPassword?: string;
}
