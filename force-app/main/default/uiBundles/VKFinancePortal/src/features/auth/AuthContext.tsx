import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { authApi } from "@/api/endpoints";
import { SESSION_EXPIRED_EVENT, sessionStore } from "@/api/vkfClient";
import type { LoginResult, Profile } from "@/api/types";

export type AuthStatus = "loading" | "anonymous" | "restricted" | "authenticated";
export type SignOutReason = "user" | "expired" | "idle";

interface AuthContextValue {
	status: AuthStatus;
	profile: Profile | null;
	/** Why the last session ended; shown once on the sign-in page. */
	signOutReason: SignOutReason | null;
	login(username: string, password: string): Promise<LoginResult>;
	completeFirstLogin(newPassword: string): Promise<void>;
	logout(reason?: SignOutReason): Promise<void>;
	refresh(): Promise<void>;
	can(permission: string): boolean;
}

const AuthContext = createContext<AuthContextValue | null>(null);

function statusFor(profile: Profile): AuthStatus {
	return profile.sessionScope === "FULL" ? "authenticated" : "restricted";
}

export function AuthProvider({ children }: { children: ReactNode }) {
	const [status, setStatus] = useState<AuthStatus>(sessionStore.get() ? "loading" : "anonymous");
	const [profile, setProfile] = useState<Profile | null>(null);
	const [signOutReason, setSignOutReason] = useState<SignOutReason | null>(null);

	const clear = useCallback((reason: SignOutReason | null) => {
		sessionStore.clear();
		setProfile(null);
		setStatus("anonymous");
		setSignOutReason(reason);
	}, []);

	const accept = useCallback((result: LoginResult) => {
		sessionStore.set(result.token);
		setProfile(result.profile);
		setStatus(statusFor(result.profile));
		setSignOutReason(null);
	}, []);

	const refresh = useCallback(async () => {
		const current = await authApi.session();
		setProfile(current);
		setStatus(statusFor(current));
	}, []);

	useEffect(() => {
		if (sessionStore.get()) {
			refresh().catch(() => clear("expired"));
		}
		const onExpired = () => clear("expired");
		window.addEventListener(SESSION_EXPIRED_EVENT, onExpired);
		return () => window.removeEventListener(SESSION_EXPIRED_EVENT, onExpired);
	}, [refresh, clear]);

	const login = useCallback(
		async (username: string, password: string) => {
			const result = await authApi.login(username, password);
			accept(result);
			return result;
		},
		[accept],
	);

	const completeFirstLogin = useCallback(
		async (newPassword: string) => {
			accept(await authApi.firstLogin(newPassword));
		},
		[accept],
	);

	const logout = useCallback(
		async (reason: SignOutReason = "user") => {
			try {
				await authApi.logout();
			} catch {
				// The session may already be gone; sign out locally either way.
			}
			clear(reason);
		},
		[clear],
	);

	const can = useCallback((permission: string) => profile?.permissions.includes(permission) ?? false, [profile]);

	const value = useMemo(
		() => ({ status, profile, signOutReason, login, completeFirstLogin, logout, refresh, can }),
		[status, profile, signOutReason, login, completeFirstLogin, logout, refresh, can],
	);
	return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
	const ctx = useContext(AuthContext);
	if (!ctx) throw new Error("useAuth must be used inside AuthProvider");
	return ctx;
}
