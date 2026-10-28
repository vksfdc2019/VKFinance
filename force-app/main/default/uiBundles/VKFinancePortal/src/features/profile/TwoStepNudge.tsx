import { useState } from "react";
import { Link } from "react-router";
import { ShieldCheck, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/features/auth/AuthContext";

const DISMISSED = "vkf:two-step-nudge";

function wasDismissed(): boolean {
	try {
		return sessionStorage.getItem(DISMISSED) === "1";
	} catch {
		return false;
	}
}

/** Asks admins without two-step to turn it on. Dismissing hides it until the next sign-in. */
export function TwoStepNudge() {
	const { profile } = useAuth();
	const [hidden, setHidden] = useState(wasDismissed);
	const admin = profile?.role === "Family Admin" || profile?.role === "Co-Admin";
	if (!admin || profile?.mfaEnabled || hidden) return null;

	function dismiss() {
		setHidden(true);
		try {
			sessionStorage.setItem(DISMISSED, "1");
		} catch {
			// Storage can be blocked; the nudge just comes back on the next page view.
		}
	}

	return (
		<div
			className="vk-rise mb-6 flex flex-wrap items-center gap-4 rounded-2xl bg-gradient-to-r from-teal-700 to-emerald-700 p-4 text-white shadow-sm"
			role="region"
			aria-label="Security tip"
		>
			<span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-white/15">
				<ShieldCheck className="size-5" aria-hidden="true" />
			</span>
			<div className="min-w-0 flex-1">
				<p className="font-semibold">Protect your family's money with two-step verification</p>
				<p className="text-sm text-white/80">As an admin you can see and change everything. A code from your phone stops anyone who learns your password.</p>
			</div>
			<Button asChild variant="secondary" className="bg-white text-teal-800 hover:bg-white/90">
				<Link to="/profile#two-step">Set it up</Link>
			</Button>
			<button type="button" onClick={dismiss} aria-label="Not now" className="rounded-lg p-1.5 text-white/70 hover:bg-white/10 hover:text-white">
				<X className="size-4" aria-hidden="true" />
			</button>
		</div>
	);
}
