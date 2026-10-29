import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router";
import { AlertTriangle, Bell, CheckCheck, CheckCircle2, Info, OctagonAlert, ShieldCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { commitmentApi } from "@/api/endpoints";
import type { AppNotification } from "@/api/commitmentTypes";
import { formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";
import { useLedger } from "@/features/ledger/LedgerContext";

const POLL_MS = 60_000;
const ICONS = { info: Info, success: CheckCircle2, warning: AlertTriangle, critical: OctagonAlert } as const;
const TINTS = {
	info: "bg-sky-50 dark:bg-sky-950/40 text-sky-700 dark:text-sky-300",
	success: "bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300",
	warning: "bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300",
	critical: "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300",
} as const;

/** The bell: polls quietly, wiggles when something new arrives, and opens a list of alerts. */
export function NotificationBell({ className }: { className?: string }) {
	const navigate = useNavigate();
	const { version } = useLedger();
	const [items, setItems] = useState<AppNotification[]>([]);
	const [unread, setUnread] = useState(0);
	const [open, setOpen] = useState(false);
	const [wiggle, setWiggle] = useState(false);
	const lastUnread = useRef(0);

	const load = useCallback(async () => {
		try {
			const feed = await commitmentApi.notifications();
			setItems(feed.items);
			setUnread(feed.unread);
			if (feed.unread > lastUnread.current) {
				setWiggle(true);
				setTimeout(() => setWiggle(false), 900);
			}
			lastUnread.current = feed.unread;
		} catch {
			// The bell stays quiet if the feed can't load; the rest of the page still works.
		}
	}, []);

	useEffect(() => {
		void load();
		const timer = setInterval(() => document.visibilityState === "visible" && void load(), POLL_MS);
		return () => clearInterval(timer);
	}, [load, version]);

	async function markAll() {
		await commitmentApi.markRead([]).catch(() => undefined);
		setItems((list) => list.map((n) => ({ ...n, read: true })));
		setUnread(0);
		lastUnread.current = 0;
	}

	async function openItem(n: AppNotification) {
		if (!n.read) {
			void commitmentApi.markRead([n.id]).catch(() => undefined);
			setItems((list) => list.map((x) => (x.id === n.id ? { ...x, read: true } : x)));
			setUnread((u) => Math.max(0, u - 1));
			lastUnread.current = Math.max(0, lastUnread.current - 1);
		}
		setOpen(false);
		if (n.link) navigate(n.link);
	}

	return (
		<Popover open={open} onOpenChange={setOpen}>
			<PopoverTrigger asChild>
				<Button
					variant="ghost"
					size="icon"
					className={cn("relative rounded-full", className)}
					aria-label={unread ? `Notifications, ${unread} unread` : "Notifications"}
				>
					<Bell className={cn("size-5", wiggle && "vk-wiggle")} />
					{unread > 0 && (
						<span className="vk-pop vk-pulse absolute -top-0.5 -right-0.5 flex min-w-4.5 items-center justify-center rounded-full bg-red-600 px-1 text-[10px] font-semibold text-white">
							{unread > 9 ? "9+" : unread}
						</span>
					)}
				</Button>
			</PopoverTrigger>
			<PopoverContent align="end" className="w-[22rem] max-w-[calc(100vw-1.5rem)] p-0">
				<div className="flex items-center justify-between border-b px-4 py-3">
					<p className="font-semibold text-slate-900 dark:text-slate-100">Notifications</p>
					{unread > 0 && (
						<Button variant="ghost" size="xs" onClick={() => void markAll()}>
							<CheckCheck />
							Mark all read
						</Button>
					)}
				</div>
				<ul className="max-h-[26rem] overflow-y-auto p-1.5">
					{items.length === 0 && <li className="px-3 py-10 text-center text-sm text-slate-500 dark:text-slate-400">You&apos;re all caught up.</li>}
					{items.map((n, i) => {
						const Icon = n.type === "security" ? ShieldCheck : (ICONS[n.severity] ?? Info);
						return (
							<li key={n.id} className="vk-rise" style={{ animationDelay: `${Math.min(i, 8) * 35}ms` }}>
								<button
									type="button"
									onClick={() => void openItem(n)}
									className={cn("flex w-full gap-3 rounded-xl px-2.5 py-2.5 text-left hover:bg-slate-50 dark:hover:bg-slate-800/60", !n.read && "bg-brand-50/50 dark:bg-brand-950/40")}
								>
									<span className={cn("flex size-8 shrink-0 items-center justify-center rounded-lg", TINTS[n.severity] ?? TINTS.info)}>
										<Icon className="size-4" aria-hidden="true" />
									</span>
									<span className="min-w-0 flex-1">
										<span className={cn("block text-sm text-slate-900 dark:text-slate-100", !n.read && "font-semibold")}>{n.title}</span>
										{n.message && <span className="block text-xs text-slate-500 dark:text-slate-400">{n.message}</span>}
										<span className="mt-0.5 block text-[11px] text-slate-400">{formatRelative(n.createdAt)}</span>
									</span>
									{!n.read && <span className="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-label="Unread" />}
								</button>
							</li>
						);
					})}
				</ul>
			</PopoverContent>
		</Popover>
	);
}
