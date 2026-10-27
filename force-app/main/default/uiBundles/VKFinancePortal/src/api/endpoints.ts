import { vkf } from "./vkfClient";
import type { CreatedMember, DeviceSession, LoginResult, Member, MemberInput, Profile } from "./types";

type Message = { message: string };

export const authApi = {
	login: (username: string, password: string) => vkf<LoginResult>("POST", "/auth/login", { username, password }),
	logout: () => vkf<void>("POST", "/auth/logout", {}),
	session: () => vkf<Profile>("GET", "/auth/session"),
	firstLogin: (newPassword: string) => vkf<LoginResult>("POST", "/auth/first-login", { newPassword }),
	changePassword: (currentPassword: string, newPassword: string) =>
		vkf<Message>("PUT", "/auth/password", { currentPassword, newPassword }),
	forgot: (identifier: string) => vkf<Message>("POST", "/auth/forgot", { identifier }),
	reset: (token: string, newPassword: string) => vkf<Message>("POST", "/auth/reset", { token, newPassword }),
};

export const profileApi = {
	me: () => vkf<Profile>("GET", "/profile/me"),
	sessions: () => vkf<DeviceSession[]>("GET", "/profile/sessions"),
	signOutOtherDevices: () => vkf<{ revoked: number }>("DELETE", "/profile/sessions"),
	signOutDevice: (sessionId: string) => vkf<void>("DELETE", `/profile/sessions/${encodeURIComponent(sessionId)}`),
};

export const familyApi = {
	members: () => vkf<Member[]>("GET", "/family/members"),
	addMember: (input: MemberInput) => vkf<CreatedMember>("POST", "/family/members", input),
	updateMember: (id: string, input: MemberInput) =>
		vkf<Member>("PATCH", `/family/members/${encodeURIComponent(id)}`, input),
	unlock: (id: string) => vkf<void>("POST", `/family/members/${encodeURIComponent(id)}/unlock`, {}),
	resetPassword: (id: string, currentPassword: string) =>
		vkf<{ temporaryPassword: string }>("POST", `/family/members/${encodeURIComponent(id)}/reset-password`, {
			currentPassword,
		}),
	signOutMember: (id: string) => vkf<{ revoked: number }>("DELETE", `/family/members/${encodeURIComponent(id)}/sessions`),
};
