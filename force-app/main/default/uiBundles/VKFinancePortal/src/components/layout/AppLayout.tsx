import { NavLink, Outlet } from "react-router";
import { LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { SessionTimeout } from "@/features/auth/SessionTimeout";
import { BrandMark } from "./BrandMark";

export default function AppLayout() {
	const { profile, can, logout } = useAuth();
	const links = [
		{ to: "/", label: "Home", show: true },
		{ to: "/family", label: "Family", show: can("MEMBERS:CREATE") },
		{ to: "/profile", label: "Profile & security", show: true },
	].filter((link) => link.show);

	return (
		<div className="min-h-svh bg-slate-50">
			<header className="border-b bg-white">
				<div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
					<BrandMark />
					<nav className="flex flex-1 flex-wrap gap-1" aria-label="Main">
						{links.map((link) => (
							<NavLink
								key={link.to}
								to={link.to}
								end={link.to === "/"}
								className={({ isActive }) =>
									cn(
										"rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
										isActive ? "bg-teal-50 text-teal-900" : "text-slate-600 hover:bg-slate-100",
									)
								}
							>
								{link.label}
							</NavLink>
						))}
					</nav>
					<div className="flex items-center gap-3">
						<span className="hidden text-sm text-slate-700 sm:inline">
							{profile?.firstName} {profile?.lastName}
						</span>
						<Badge variant="secondary">{profile?.role}</Badge>
						<Button variant="ghost" size="sm" onClick={() => void logout("user")}>
							<LogOut aria-hidden="true" />
							Sign out
						</Button>
					</div>
				</div>
			</header>
			<main className="mx-auto max-w-6xl px-4 py-8">
				<Outlet />
			</main>
			<SessionTimeout />
		</div>
	);
}
