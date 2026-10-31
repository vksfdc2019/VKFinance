import type { Appearance } from "@/theme/themes";

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
	/** Day the family month starts (1 = calendar months). */
	monthStartDay?: number;
	mustChangePassword: boolean;
	mfaEnabled: boolean;
	sessionScope: "FULL" | "CHANGE_PASSWORD";
	idleTimeoutMinutes: number;
	permissions: string[];
	/** Saved themes; missing from older servers. */
	appearance?: Appearance;
}

/** A sign-in either finishes (token + profile) or asks for an authenticator code first. */
export interface LoginResult {
	token?: string;
	mustChangePassword: boolean;
	profile?: Profile;
	mfaRequired?: boolean;
	challenge?: string;
}

export interface CompletedLogin extends LoginResult {
	token: string;
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
	mfaEnabled?: boolean;
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
	/** Authenticator or recovery code, when the admin has two-step on. */
	code?: string;
}

export interface MfaStatus {
	enabled: boolean;
	enrolledAt?: string;
	recoveryCodesLeft: number;
}

export interface MfaSetup {
	secret: string;
	otpauthUri: string;
}

export interface SecurityEvent {
	at: string;
	type: string;
	details?: string;
	byAdmin: boolean;
}

export interface SecurityOverview {
	mfa: MfaStatus;
	passwordChangedAt?: string;
	lastLogin?: string;
	activeSessions: number;
	activity: SecurityEvent[];
}

/** Family-wide settings; only the Family Admin can change them. */
export interface FamilySettings {
	/** 1-31; 1 = calendar months. With 30, "November" runs 30 Oct to 29 Nov. */
	monthStartDay: number;
	current: { key: string; startDate: string; endDate: string };
	canEdit: boolean;
}
