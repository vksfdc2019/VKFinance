import { useState, type FormEvent } from "react";
import { Eye, EyeOff, Pencil, Plus, Tags } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { Spinner } from "@/components/ui/spinner";
import { toast } from "@/components/ui/sonner";
import { FormErrors, TextField } from "@/components/forms";
import { CATEGORY_COLORS, CATEGORY_ICONS, CategoryChip } from "@/components/finance/icons";
import { EmptyState, PageHeader, Panel, SegmentedControl } from "@/components/finance/ui";
import { financeApi } from "@/api/endpoints";
import { errorMessages } from "@/api/vkfClient";
import type { Category, CategoryInput } from "@/api/financeTypes";
import { useAsync } from "@/lib/useAsync";
import { cn } from "@/lib/utils";
import { useAuth } from "@/features/auth/AuthContext";
import { useLedger } from "@/features/ledger/LedgerContext";

type Editing = { category?: Category; parent?: Category; kind: "Income" | "Expense" };

export default function CategoriesPage() {
	const { can } = useAuth();
	const { version, refresh, loadCategories } = useLedger();
	const [kind, setKind] = useState<"Expense" | "Income">("Expense");
	const [editing, setEditing] = useState<Editing | null>(null);
	const { data: categories, errors, loading } = useAsync(() => loadCategories(true), [version]);
	const canEdit = can("CATEGORIES:EDIT");

	const parents = (categories ?? []).filter((c) => c.kind === kind && !c.parentId);
	const childrenOf = (id: string) => (categories ?? []).filter((c) => c.parentId === id);

	async function toggle(category: Category) {
		try {
			await financeApi.updateCategory(category.id, { active: !category.active });
			toast.success(category.active ? `${category.name} hidden` : `${category.name} shown`);
			refresh();
		} catch (error) {
			toast.error(errorMessages(error)[0]);
		}
	}

	return (
		<>
			<PageHeader
				title="Categories"
				description="How your family's money is grouped. Hidden categories keep their history but leave the pickers."
				actions={
					canEdit && (
						<Button onClick={() => setEditing({ kind })}>
							<Plus />
							New category
						</Button>
					)
				}
			/>
			<SegmentedControl
				label="Kind"
				value={kind}
				onChange={setKind}
				className="mb-4"
				options={[
					{ value: "Expense", label: "Spending" },
					{ value: "Income", label: "Income" },
				]}
			/>
			<FormErrors errors={errors} />
			{!categories && loading ? (
				<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
					{[0, 1, 2, 3, 4, 5].map((i) => (
						<Skeleton key={i} className="h-36 rounded-2xl" />
					))}
				</div>
			) : parents.length === 0 ? (
				<Panel>
					<EmptyState icon={<Tags />} title="No categories yet" />
				</Panel>
			) : (
				<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
					{parents.map((parent) => (
						<Panel key={parent.id} className={cn(!parent.active && "opacity-60")} bodyClassName="p-4">
							<div className="flex items-start gap-3">
								<CategoryChip icon={parent.icon} color={parent.color} size="lg" />
								<div className="min-w-0 flex-1">
									<h2 className="truncate font-semibold text-slate-900">{parent.name}</h2>
									<p className="text-xs text-slate-500">
										{childrenOf(parent.id).length} sub-categories{!parent.active && " · hidden"}
									</p>
								</div>
								{canEdit && (
									<div className="flex gap-0.5">
										<Button variant="ghost" size="icon-sm" aria-label={`Edit ${parent.name}`} onClick={() => setEditing({ category: parent, kind })}>
											<Pencil />
										</Button>
										<Button variant="ghost" size="icon-sm" aria-label={parent.active ? `Hide ${parent.name}` : `Show ${parent.name}`} onClick={() => void toggle(parent)}>
											{parent.active ? <EyeOff /> : <Eye />}
										</Button>
									</div>
								)}
							</div>
							<ul className="mt-3 flex flex-wrap gap-1.5">
								{childrenOf(parent.id).map((child) => (
									<li key={child.id}>
										<button
											type="button"
											disabled={!canEdit}
											onClick={() => setEditing({ category: child, parent, kind })}
											className={cn(
												"inline-flex items-center gap-1 rounded-full bg-slate-100 px-2.5 py-1 text-xs text-slate-700 enabled:hover:bg-slate-200",
												!child.active && "text-slate-400 line-through",
											)}
										>
											{child.name}
											{child.essential && <span className="sr-only">(need)</span>}
										</button>
									</li>
								))}
								{canEdit && (
									<li>
										<button
											type="button"
											onClick={() => setEditing({ parent, kind })}
											className="inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium text-teal-700 ring-1 ring-teal-700/20 hover:bg-teal-50"
										>
											<Plus className="size-3" aria-hidden="true" />
											Add
										</button>
									</li>
								)}
							</ul>
							{parent.taxRelevant && (
								<Badge variant="outline" className="mt-3">
									Tax relevant
								</Badge>
							)}
						</Panel>
					))}
				</div>
			)}
			{editing && (
				<CategoryDialog
					editing={editing}
					onClose={() => setEditing(null)}
					onSaved={() => {
						setEditing(null);
						refresh();
					}}
				/>
			)}
		</>
	);
}

function CategoryDialog({ editing, onClose, onSaved }: { editing: Editing; onClose: () => void; onSaved: () => void }) {
	const { category, parent, kind } = editing;
	const isChild = Boolean(parent);
	const [name, setName] = useState(category?.name ?? "");
	const [icon, setIcon] = useState(category?.icon ?? (isChild ? undefined : "tag"));
	const [color, setColor] = useState(category?.color ?? (isChild ? undefined : CATEGORY_COLORS[0]));
	const [essential, setEssential] = useState(category?.essential ?? false);
	const [taxRelevant, setTaxRelevant] = useState(category?.taxRelevant ?? false);
	const [active, setActive] = useState(category?.active ?? true);
	const [errors, setErrors] = useState<string[]>([]);
	const [saving, setSaving] = useState(false);

	async function submit(e: FormEvent) {
		e.preventDefault();
		const input: CategoryInput = { name: name.trim(), essential, taxRelevant };
		if (!isChild) {
			input.icon = icon;
			input.color = color;
		}
		setSaving(true);
		try {
			if (category) {
				await financeApi.updateCategory(category.id, { ...input, active });
			} else {
				await financeApi.createCategory({ ...input, kind, parentId: parent?.id });
			}
			toast.success(category ? "Category updated" : `${input.name} added`);
			onSaved();
		} catch (error) {
			setErrors(errorMessages(error));
		} finally {
			setSaving(false);
		}
	}

	return (
		<Dialog open onOpenChange={(open) => !open && onClose()}>
			<DialogContent className="sm:max-w-md">
				<form onSubmit={submit} noValidate className="space-y-4">
					<DialogHeader>
						<DialogTitle>
							{category ? `Edit ${category.name}` : isChild ? `New sub-category in ${parent?.name}` : `New ${kind === "Income" ? "income" : "spending"} category`}
						</DialogTitle>
						<DialogDescription>Renaming keeps every past transaction in this category.</DialogDescription>
					</DialogHeader>
					<div className="flex items-center gap-3">
						<CategoryChip icon={icon ?? parent?.icon} color={color ?? parent?.color} size="lg" />
						<div className="flex-1">
							<TextField id="cat-name" label="Name" value={name} maxLength={40} autoFocus onChange={(e) => setName(e.target.value)} />
						</div>
					</div>
					{!isChild && (
						<>
							<fieldset>
								<legend className="mb-2 text-sm font-medium">Icon</legend>
								<div className="grid max-h-36 grid-cols-9 gap-1 overflow-y-auto rounded-xl bg-slate-50 p-2">
									{Object.entries(CATEGORY_ICONS).map(([key, Icon]) => (
										<button
											key={key}
											type="button"
											aria-label={key}
											aria-pressed={icon === key}
											onClick={() => setIcon(key)}
											className={cn(
												"flex size-8 items-center justify-center rounded-lg text-slate-600 hover:bg-white",
												icon === key && "bg-white text-teal-700 ring-2 ring-teal-600",
											)}
										>
											<Icon className="size-4" />
										</button>
									))}
								</div>
							</fieldset>
							<fieldset>
								<legend className="mb-2 text-sm font-medium">Colour</legend>
								<div className="flex flex-wrap gap-2">
									{CATEGORY_COLORS.map((c) => (
										<button
											key={c}
											type="button"
											aria-label={c}
											aria-pressed={color === c}
											onClick={() => setColor(c)}
											className={cn("size-7 rounded-full ring-offset-2", color === c && "ring-2 ring-slate-900")}
											style={{ backgroundColor: c }}
										/>
									))}
								</div>
							</fieldset>
						</>
					)}
					<div className="space-y-2.5">
						{kind === "Expense" && (
							<label className="flex items-start gap-2.5 text-sm">
								<Checkbox checked={essential} onCheckedChange={(v) => setEssential(v === true)} className="mt-0.5" />
								<span>
									A need, not a want
									<span className="block text-xs text-slate-500">Used for the needs vs wants split.</span>
								</span>
							</label>
						)}
						<label className="flex items-center gap-2.5 text-sm">
							<Checkbox checked={taxRelevant} onCheckedChange={(v) => setTaxRelevant(v === true)} />
							Relevant for income tax
						</label>
						{category && (
							<label className="flex items-center gap-2.5 text-sm">
								<Checkbox checked={active} onCheckedChange={(v) => setActive(v === true)} />
								Show in pickers
							</label>
						)}
					</div>
					<FormErrors errors={errors} />
					<DialogFooter>
						<Button type="button" variant="outline" onClick={onClose}>
							Cancel
						</Button>
						<Button type="submit" disabled={saving}>
							{saving && <Spinner />}
							{category ? "Save" : "Add category"}
						</Button>
					</DialogFooter>
				</form>
			</DialogContent>
		</Dialog>
	);
}
