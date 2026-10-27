import { describe, expect, it } from "vitest";
import { formatCompact, formatMoney, monthLabel, percentChange, shiftMonth } from "./format";
import { niceMax } from "@/components/charts/CashFlowChart";
import { budgetStatus, utilisationStatus } from "@/components/finance/ui";
import { queryString } from "@/api/endpoints";
import { txnTitle } from "@/features/ledger/TxnRow";
import type { Txn } from "@/api/financeTypes";

describe("money formatting", () => {
	it("groups rupees the Indian way and shows paise only when present", () => {
		expect(formatMoney(123456)).toBe("₹1,23,456");
		expect(formatMoney(250.5)).toBe("₹250.50");
		expect(formatMoney(-1000)).toBe("−₹1,000");
		expect(formatMoney(500, "INR", { signed: true })).toBe("+₹500");
	});

	it("abbreviates large amounts in lakh and crore", () => {
		expect(formatCompact(150000)).toBe("₹1.5L");
		expect(formatCompact(25000000)).toBe("₹2.5Cr");
	});
});

describe("months", () => {
	it("moves across year boundaries", () => {
		expect(shiftMonth("2026-01", -1)).toBe("2025-12");
		expect(shiftMonth("2026-12", 1)).toBe("2027-01");
		expect(monthLabel("2026-10")).toBe("October 2026");
		expect(monthLabel("2026-10", "short")).toBe("Oct");
	});

	it("has no percentage change without a base", () => {
		expect(percentChange(100, 0)).toBeUndefined();
		expect(percentChange(150, 100)).toBe(50);
	});
});

describe("chart axis", () => {
	it("rounds the maximum up to a friendly step", () => {
		expect(niceMax(0)).toBe(4);
		expect(niceMax(87000)).toBe(100000);
		expect(niceMax(81000)).toBe(100000);
		expect(niceMax(19000)).toBe(20000);
		expect(niceMax(9)).toBe(10);
	});
});

describe("status rules", () => {
	it("warns when spending runs ahead of the calendar and flags overspend", () => {
		expect(budgetStatus(2000, 10000, 0.5)).toBe("good");
		expect(budgetStatus(7000, 10000, 0.3)).toBe("warning");
		expect(budgetStatus(8500, 10000, 0.9)).toBe("warning");
		expect(budgetStatus(10001, 10000, 1)).toBe("critical");
		expect(budgetStatus(0, 0, 1)).toBe("good");
	});

	it("uses the 30% card utilisation guideline", () => {
		expect(utilisationStatus(12)).toBe("good");
		expect(utilisationStatus(45)).toBe("warning");
		expect(utilisationStatus(85)).toBe("critical");
	});
});

describe("query strings", () => {
	it("skips empty values and encodes the rest", () => {
		expect(queryString({ month: "2026-10", q: "50% off", includeVoid: false, accountId: undefined })).toBe("?month=2026-10&q=50%25+off");
		expect(queryString({})).toBe("");
	});
});

describe("transaction titles", () => {
	const base = { id: "1", name: "TXN-1", amount: 10, txnDate: "2026-10-27", accountId: "a", status: "Cleared", canEdit: true } as const;
	it("describes transfers by direction and entries by payee", () => {
		expect(txnTitle({ ...base, type: "Transfer Out", direction: "Debit", payee: "Riya Wallet" } as Txn)).toBe("To Riya Wallet");
		expect(txnTitle({ ...base, type: "Transfer In", direction: "Credit", payee: "HDFC" } as Txn)).toBe("From HDFC");
		expect(txnTitle({ ...base, type: "Card Payment", direction: "Debit", payee: "Visa" } as Txn)).toBe("Card bill · Visa");
		expect(txnTitle({ ...base, type: "Expense", direction: "Debit", categoryName: "Groceries" } as Txn)).toBe("Groceries");
		expect(txnTitle({ ...base, type: "Expense", direction: "Debit", payee: "DMart", categoryName: "Groceries" } as Txn)).toBe("DMart");
	});
});
