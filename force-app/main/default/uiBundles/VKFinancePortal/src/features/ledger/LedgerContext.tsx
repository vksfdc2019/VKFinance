import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { financeApi } from "@/api/endpoints";
import type { Category, Txn } from "@/api/financeTypes";
import { useAuth } from "@/features/auth/AuthContext";
import { TransactionDialog, type EntryMode } from "./TransactionDialog";

export interface EntryOptions {
	mode?: EntryMode;
	accountId?: string;
	toAccountId?: string;
	txn?: Txn;
}

interface LedgerContextValue {
	/** Bumps after any change to the ledger; pages include it in their load deps. */
	version: number;
	refresh: () => void;
	openEntry: (options?: EntryOptions) => void;
	canAdd: boolean;
	categories: Category[] | undefined;
	loadCategories: (force?: boolean) => Promise<Category[]>;
	currency: string;
}

const LedgerContext = createContext<LedgerContextValue | null>(null);

export function LedgerProvider({ children }: { children: ReactNode }) {
	const { profile, can } = useAuth();
	const [version, setVersion] = useState(0);
	const [entry, setEntry] = useState<EntryOptions | null>(null);
	const [categories, setCategories] = useState<Category[]>();
	const canAdd = can("TRANSACTIONS:CREATE");

	const refresh = useCallback(() => setVersion((v) => v + 1), []);
	const openEntry = useCallback((options: EntryOptions = {}) => setEntry(options), []);
	const loadCategories = useCallback(
		async (force = false) => {
			if (categories && !force) return categories;
			const loaded = await financeApi.categories();
			setCategories(loaded);
			return loaded;
		},
		[categories],
	);

	// "N" adds a transaction from anywhere, unless the person is typing.
	useEffect(() => {
		if (!canAdd) return;
		function onKey(e: KeyboardEvent) {
			const target = e.target as HTMLElement | null;
			const typing = target?.closest("input, textarea, select, [contenteditable='true'], [role='dialog']");
			if (!typing && !e.metaKey && !e.ctrlKey && !e.altKey && e.key.toLowerCase() === "n") {
				e.preventDefault();
				setEntry({});
			}
		}
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [canAdd]);

	const value = useMemo<LedgerContextValue>(
		() => ({
			version,
			refresh,
			openEntry,
			canAdd,
			categories,
			loadCategories,
			currency: profile?.currencyCode ?? "INR",
		}),
		[version, refresh, openEntry, canAdd, categories, loadCategories, profile?.currencyCode],
	);

	return (
		<LedgerContext.Provider value={value}>
			{children}
			{entry && (
				<TransactionDialog
					options={entry}
					onClose={() => setEntry(null)}
					onSaved={() => {
						setEntry(null);
						refresh();
					}}
				/>
			)}
		</LedgerContext.Provider>
	);
}

export function useLedger(): LedgerContextValue {
	const ctx = useContext(LedgerContext);
	if (!ctx) throw new Error("useLedger must be used inside LedgerProvider");
	return ctx;
}
