import { Navigate, Outlet, useLocation } from "react-router";
import { Spinner } from "@/components/ui/spinner";
import { useAuth } from "./AuthContext";

export function FullPageSpinner() {
	return (
		<div className="flex min-h-svh items-center justify-center text-muted-foreground">
			<Spinner className="size-6" />
		</div>
	);
}

/** Only accepts relative in-app paths, so a crafted ?next= can't redirect off-site. */
export function safeNext(value: string | null): string {
	if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) return "/";
	return value;
}

export function RequireAuth() {
	const { status } = useAuth();
	const location = useLocation();
	if (status === "loading") return <FullPageSpinner />;
	if (status === "anonymous") {
		const next = encodeURIComponent(location.pathname + location.search);
		return <Navigate to={`/login?next=${next}`} replace />;
	}
	if (status === "restricted") return <Navigate to="/first-login" replace />;
	return <Outlet />;
}

export function RequirePermission({ permission }: { permission: string }) {
	const { can } = useAuth();
	return can(permission) ? <Outlet /> : <Navigate to="/" replace />;
}

/** Sign-in pages: send already signed-in members straight in. */
export function PublicOnly() {
	const { status } = useAuth();
	if (status === "loading") return <FullPageSpinner />;
	if (status === "authenticated") return <Navigate to="/" replace />;
	if (status === "restricted") return <Navigate to="/first-login" replace />;
	return <Outlet />;
}
