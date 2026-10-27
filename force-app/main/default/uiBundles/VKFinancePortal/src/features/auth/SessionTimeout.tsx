import { useCallback, useEffect, useRef, useState } from "react";
import { authApi } from "@/api/endpoints";
import { Button } from "@/components/ui/button";
import {
	Dialog,
	DialogContent,
	DialogDescription,
	DialogFooter,
	DialogHeader,
	DialogTitle,
} from "@/components/ui/dialog";
import { useAuth } from "./AuthContext";

const ACTIVITY_EVENTS = ["mousemove", "keydown", "click", "scroll", "touchstart"] as const;
const WARN_BEFORE_MS = 2 * 60_000;
const KEEP_ALIVE_EVERY_MS = 5 * 60_000;

/**
 * Signs the member out after the server's idle timeout, warning two minutes before.
 * While the member is active, pings the server every few minutes so its idle clock
 * matches what they see.
 */
export function SessionTimeout() {
	const { profile, logout } = useAuth();
	const idleMs = (profile?.idleTimeoutMinutes ?? 30) * 60_000;
	const lastActivity = useRef(Date.now());
	const lastPing = useRef(Date.now());
	const [warning, setWarning] = useState(false);

	useEffect(() => {
		const markActive = () => {
			lastActivity.current = Date.now();
			if (Date.now() - lastPing.current > KEEP_ALIVE_EVERY_MS) {
				lastPing.current = Date.now();
				authApi.session().catch(() => undefined);
			}
		};
		ACTIVITY_EVENTS.forEach((name) => window.addEventListener(name, markActive, { passive: true }));
		const timer = window.setInterval(() => {
			const idleFor = Date.now() - lastActivity.current;
			if (idleFor >= idleMs) {
				void logout("idle");
			} else {
				setWarning(idleFor >= idleMs - WARN_BEFORE_MS);
			}
		}, 10_000);
		return () => {
			ACTIVITY_EVENTS.forEach((name) => window.removeEventListener(name, markActive));
			window.clearInterval(timer);
		};
	}, [idleMs, logout]);

	const stay = useCallback(() => {
		lastActivity.current = Date.now();
		lastPing.current = Date.now();
		setWarning(false);
		authApi.session().catch(() => undefined);
	}, []);

	return (
		<Dialog open={warning} onOpenChange={(open) => !open && stay()}>
			<DialogContent showCloseButton={false}>
				<DialogHeader>
					<DialogTitle>Still there?</DialogTitle>
					<DialogDescription>
						For your family's security you'll be signed out in about two minutes because there's been no
						activity.
					</DialogDescription>
				</DialogHeader>
				<DialogFooter>
					<Button variant="outline" onClick={() => void logout("user")}>
						Sign out now
					</Button>
					<Button onClick={stay}>Stay signed in</Button>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
