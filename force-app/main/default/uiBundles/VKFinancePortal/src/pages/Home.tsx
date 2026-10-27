import { Link } from "react-router";
import { ShieldCheck, Users, Wallet } from "lucide-react";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/features/auth/AuthContext";

const COMING_NEXT = [
	"Bank, cash, UPI wallet and credit-card accounts",
	"Income, expenses, transfers and card payments",
	"Bills, loans and EMI schedules with reminders",
	"Monthly budgets, dashboards and reports",
];

export default function HomePage() {
	const { profile, can } = useAuth();
	if (!profile) return null;
	const isAdmin = can("MEMBERS:CREATE");

	return (
		<div className="grid gap-6">
			<title>Home · VK Finance</title>
			<div>
				<h1 className="text-2xl font-semibold text-slate-900">Hello, {profile.firstName}</h1>
				<p className="text-slate-600">
					{profile.familyName} · {profile.familyCode}
				</p>
			</div>
			<div className="grid gap-4 md:grid-cols-3">
				<Card>
					<CardHeader>
						<CardTitle className="flex items-center gap-2 text-base">
							<Users className="size-4 text-teal-800" aria-hidden="true" />
							Your family
						</CardTitle>
						<CardDescription>You're signed in as {profile.role}.</CardDescription>
					</CardHeader>
					<CardContent>
						{isAdmin ? (
							<Button asChild variant="outline" size="sm">
								<Link to="/family">Manage family members</Link>
							</Button>
						) : (
							<p className="text-sm text-slate-600">Your Family Admin manages who can sign in.</p>
						)}
					</CardContent>
				</Card>
				<Card>
					<CardHeader>
						<CardTitle className="flex items-center gap-2 text-base">
							<ShieldCheck className="size-4 text-teal-800" aria-hidden="true" />
							Security
						</CardTitle>
						<CardDescription>Change your password and see where you're signed in.</CardDescription>
					</CardHeader>
					<CardContent>
						<Button asChild variant="outline" size="sm">
							<Link to="/profile">Profile & security</Link>
						</Button>
					</CardContent>
				</Card>
				<Card>
					<CardHeader>
						<CardTitle className="flex items-center gap-2 text-base">
							<Wallet className="size-4 text-teal-800" aria-hidden="true" />
							Coming next
						</CardTitle>
						<CardDescription>The money features arrive in the next phase.</CardDescription>
					</CardHeader>
					<CardContent>
						<ul className="list-disc space-y-1 pl-4 text-sm text-slate-600">
							{COMING_NEXT.map((item) => (
								<li key={item}>{item}</li>
							))}
						</ul>
					</CardContent>
				</Card>
			</div>
		</div>
	);
}
