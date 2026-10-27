import { useMemo, useState } from "react";
import { Check, ChevronsUpDown, Search } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { CategoryChip } from "@/components/finance/icons";
import type { Category } from "@/api/financeTypes";
import { cn } from "@/lib/utils";

/** Searchable, grouped picker for a family's ~100 categories. Shows active ones of one kind. */
export function CategoryPicker({
	id,
	categories,
	kind,
	value,
	onChange,
}: {
	id: string;
	categories: Category[];
	kind: "Income" | "Expense";
	value?: string;
	onChange: (categoryId: string) => void;
}) {
	const [open, setOpen] = useState(false);
	const [query, setQuery] = useState("");
	const byId = useMemo(() => new Map(categories.map((c) => [c.id, c])), [categories]);
	const groups = useMemo(() => {
		const q = query.trim().toLowerCase();
		const parents = categories.filter((c) => c.kind === kind && !c.parentId && c.active);
		return parents
			.map((parent) => {
				const children = categories.filter((c) => c.parentId === parent.id && c.active);
				const parentMatches = !q || parent.name.toLowerCase().includes(q);
				const items = [parent, ...children].filter((c) => parentMatches || c.name.toLowerCase().includes(q));
				return { parent, items };
			})
			.filter((g) => g.items.length > 0);
	}, [categories, kind, query]);
	const selected = value ? byId.get(value) : undefined;
	const selectedParent = selected?.parentId ? byId.get(selected.parentId) : undefined;

	function choose(categoryId: string) {
		onChange(categoryId);
		setOpen(false);
		setQuery("");
	}

	return (
		<Popover open={open} onOpenChange={setOpen}>
			<PopoverTrigger asChild>
				<button
					id={id}
					type="button"
					role="combobox"
					aria-expanded={open}
					className="flex h-10 w-full items-center gap-2.5 rounded-lg border border-input bg-white px-2.5 text-left text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50"
				>
					{selected ? (
						<>
							<CategoryChip icon={selected.icon} color={selected.color} size="sm" className="size-6 rounded-lg" />
							<span className="min-w-0 flex-1 truncate">
								{selected.name}
								{selectedParent && <span className="text-slate-400"> · {selectedParent.name}</span>}
							</span>
						</>
					) : (
						<span className="flex-1 text-muted-foreground">Choose a category</span>
					)}
					<ChevronsUpDown className="size-4 text-slate-400" aria-hidden="true" />
				</button>
			</PopoverTrigger>
			<PopoverContent className="w-(--radix-popover-trigger-width) min-w-72 p-0" align="start">
				<div className="flex items-center gap-2 border-b px-3">
					<Search className="size-4 text-slate-400" aria-hidden="true" />
					<input
						autoFocus
						value={query}
						onChange={(e) => setQuery(e.target.value)}
						placeholder="Search categories"
						aria-label="Search categories"
						className="h-10 flex-1 bg-transparent text-sm outline-none placeholder:text-slate-400"
						onKeyDown={(e) => {
							if (e.key === "Enter" && groups[0]?.items[0]) {
								e.preventDefault();
								choose((groups[0].items.find((c) => c.parentId) ?? groups[0].items[0]).id);
							}
						}}
					/>
				</div>
				<div className="max-h-72 overflow-y-auto p-1.5" role="listbox" aria-label="Categories">
					{groups.length === 0 && <p className="px-2 py-6 text-center text-sm text-slate-500">No matching categories.</p>}
					{groups.map(({ parent, items }) => (
						<div key={parent.id} className="mb-1">
							<p className="flex items-center gap-2 px-2 pt-2 pb-1 text-xs font-semibold uppercase tracking-wide text-slate-400">
								{parent.name}
							</p>
							{items.map((c) => (
								<button
									key={c.id}
									type="button"
									role="option"
									aria-selected={c.id === value}
									onClick={() => choose(c.id)}
									className={cn(
										"flex w-full items-center gap-2.5 rounded-lg px-2 py-1.5 text-left text-sm hover:bg-slate-100 focus-visible:bg-slate-100 focus-visible:outline-none",
										c.id === value && "bg-teal-50",
									)}
								>
									<CategoryChip icon={c.icon} color={c.color} size="sm" className="size-6 rounded-lg" />
									<span className="flex-1 truncate">{c.parentId ? c.name : `${c.name} (general)`}</span>
									{c.id === value && <Check className="size-4 text-teal-700" aria-hidden="true" />}
								</button>
							))}
						</div>
					))}
				</div>
			</PopoverContent>
		</Popover>
	);
}
