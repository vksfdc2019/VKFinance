import { useCallback, useEffect, useState, type ReactNode } from "react";
import { ArrowDown, ArrowUp, Eye, EyeOff, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { toast } from "@/components/ui/sonner";
import { reportApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { LayoutWidget } from "@/api/reportTypes";
import { cn } from "@/lib/utils";

export const WIDGET_LABELS: Record<string, string> = {
	upcoming: "Coming up",
	cashflow: "Cash flow",
	categories: "Where it went",
	budget: "Budget and needs vs wants",
	accounts: "Accounts",
	recent: "Recent activity",
};
const DEFAULT_ORDER = Object.keys(WIDGET_LABELS);

/** Saved order first, then any widgets added since the layout was saved. */
export function normalise(saved: LayoutWidget[]): LayoutWidget[] {
	const known = saved.filter((w) => WIDGET_LABELS[w.key]);
	const missing = DEFAULT_ORDER.filter((k) => !known.some((w) => w.key === k)).map((key) => ({ key, hidden: false }));
	return [...known, ...missing];
}

/** Each person's overview layout, stored on their portal user so it follows them across devices. */
export function useDashboardLayout() {
	const [layout, setLayout] = useState<LayoutWidget[]>(() => normalise([]));
	useEffect(() => {
		reportApi
			.layout()
			.then((r) => setLayout(normalise(r.widgets)))
			.catch(() => undefined);
	}, []);
	const saveLayout = useCallback(async (next: LayoutWidget[]) => {
		const saved = await reportApi.saveLayout(next);
		setLayout(normalise(saved.widgets));
	}, []);
	return { layout, saveLayout };
}

/** Places a panel by the person's chosen order (CSS order), or hides it. */
export function Widget({ id, layout, className, children }: { id: string; layout: LayoutWidget[]; className?: string; children: ReactNode }) {
	const index = layout.findIndex((w) => w.key === id);
	if (index >= 0 && layout[index].hidden) return null;
	return (
		<div className={cn("vk-rise", className)} style={{ order: index, animationDelay: `${180 + Math.max(0, index) * 60}ms` }}>
			{children}
		</div>
	);
}

export function CustomiseDialog({
	layout,
	onClose,
	onSave,
}: {
	layout: LayoutWidget[];
	onClose: () => void;
	onSave: (layout: LayoutWidget[]) => Promise<void>;
}) {
	const [draft, setDraft] = useState(layout);
	const [busy, setBusy] = useState(false);

	function move(i: number, delta: number) {
		setDraft((d) => {
			const next = [...d];
			const [item] = next.splice(i, 1);
			next.splice(i + delta, 0, item);
			return next;
		});
	}

	async function save(next: LayoutWidget[]) {
		setBusy(true);
		try {
			await onSave(next);
			toast.success("Dashboard updated");
			onClose();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
			setBusy(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-md">
				<DialogHeader>
					<DialogTitle>Customise your overview</DialogTitle>
					<DialogDescription>Show, hide and reorder the panels below your headline numbers. Saved to your login, so it follows you.</DialogDescription>
				</DialogHeader>
				<ul className="space-y-1.5">
					{draft.map((w, i) => (
						<li key={w.key} className={cn("flex items-center gap-2 rounded-xl px-3 py-2 ring-1 ring-slate-900/5 dark:ring-white/10 transition-colors", w.hidden ? "bg-slate-50 dark:bg-slate-800/40 text-slate-400" : "bg-white dark:bg-slate-900")}>
							<span className="flex-1 text-sm font-medium">{WIDGET_LABELS[w.key]}</span>
							<Button variant="ghost" size="icon-sm" aria-label={`Move ${WIDGET_LABELS[w.key]} up`} disabled={i === 0} onClick={() => move(i, -1)}>
								<ArrowUp />
							</Button>
							<Button variant="ghost" size="icon-sm" aria-label={`Move ${WIDGET_LABELS[w.key]} down`} disabled={i === draft.length - 1} onClick={() => move(i, 1)}>
								<ArrowDown />
							</Button>
							<Button
								variant="ghost"
								size="icon-sm"
								aria-label={w.hidden ? `Show ${WIDGET_LABELS[w.key]}` : `Hide ${WIDGET_LABELS[w.key]}`}
								onClick={() => setDraft((d) => d.map((x, j) => (j === i ? { ...x, hidden: !x.hidden } : x)))}
							>
								{w.hidden ? <EyeOff /> : <Eye />}
							</Button>
						</li>
					))}
				</ul>
				<DialogFooter className="sm:justify-between">
					<Button variant="ghost" onClick={() => void save(normalise([]))} disabled={busy}>
						<RotateCcw />
						Reset
					</Button>
					<div className="flex gap-2">
						<Button variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button onClick={() => void save(draft)} disabled={busy}>
							Save
						</Button>
					</div>
				</DialogFooter>
			</DialogContent>
		</Dialog>
	);
}
