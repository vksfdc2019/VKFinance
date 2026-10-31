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

describe("commitments", async () => {
	const { emiFor, monthsToRepay } = await import("@/features/commitments/LoansPage");
	const { dueText } = await import("@/features/commitments/shared");

	it("computes the same EMI as the server", () => {
		expect(emiFor(1000000, 9, 60)).toBe(20758.36);
		expect(emiFor(100000, 12, 12)).toBe(8884.88);
		expect(emiFor(1200, 0, 12)).toBe(100);
		expect(emiFor(0, 9, 12)).toBe(0);
	});

	it("works out how many EMIs are left at a new rate", () => {
		expect(monthsToRepay(1000000, 9, emiFor(1000000, 9, 60))).toBe(60);
		expect(monthsToRepay(1000000, 10, emiFor(1000000, 9, 60))).toBeGreaterThan(60);
		expect(monthsToRepay(1200, 0, 100)).toBe(12);
		expect(monthsToRepay(100000, 12, 1000)).toBe(Infinity);
		expect(monthsToRepay(0, 9, 1000)).toBe(0);
	});

	it("describes due dates in plain words", () => {
		expect(dueText(-1)).toBe("1 day late");
		expect(dueText(-3)).toBe("3 days late");
		expect(dueText(0)).toBe("Due today");
		expect(dueText(1)).toBe("Tomorrow");
		expect(dueText(9)).toBe("In 9 days");
	});
});

describe("reports", async () => {
	const { presetRange, formatCell, toCsv } = await import("@/features/reports/ReportView");
	const { normalise } = await import("@/pages/DashboardLayout");

	it("turns period presets into dates, with an April-March financial year", () => {
		const today = new Date(2026, 9, 27);
		expect(presetRange("this-month", today)).toEqual({ from: "2026-10-01", to: "2026-10-31" });
		expect(presetRange("last-month", today)).toEqual({ from: "2026-09-01", to: "2026-09-30" });
		expect(presetRange("fy", today)).toEqual({ from: "2026-04-01", to: "2027-03-31" });
		expect(presetRange("fy", new Date(2027, 1, 10))).toEqual({ from: "2026-04-01", to: "2027-03-31" });
		expect(presetRange("last-12", today)).toEqual({ from: "2025-11-01", to: "2026-10-31" });
		expect(presetRange("custom", today)).toBeNull();
	});

	it("formats cells by type and escapes CSV", () => {
		expect(formatCell(1234.5, "money", "INR")).toBe("₹1,234.50");
		expect(formatCell(12.34, "percent", "INR")).toBe("12.3%");
		expect(formatCell(null, "money", "INR")).toBe("—");
		expect(formatCell("2026-10", "month", "INR")).toBe("October 2026");
		const csv = toCsv([{ title: "T", columns: [{ key: "a", label: "Name", format: "text" }], rows: [{ a: 'He said "hi"' }] }]);
		expect(csv).toBe('"T"\r\n"Name"\r\n"He said ""hi"""\r\n');
	});

	it("keeps a saved layout's order and adds new widgets at the end", () => {
		const layout = normalise([{ key: "recent" }, { key: "bogus" }, { key: "upcoming", hidden: true }]);
		expect(layout.map((w) => w.key)).toEqual(["recent", "upcoming", "cashflow", "categories", "budget", "accounts"]);
		expect(layout[1].hidden).toBe(true);
	});
});

describe("family month", async () => {
	const { monthKey, monthPeriod, monthRange, setMonthStartDay, shiftMonth } = await import("@/lib/format");
	const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

	it("starts on payday when the family says so", () => {
		setMonthStartDay(30);
		expect(monthKey(new Date(2026, 9, 30))).toBe("2026-11");
		expect(monthKey(new Date(2026, 9, 29))).toBe("2026-10");
		expect(monthKey(new Date(2026, 10, 1))).toBe("2026-11");
		const nov = monthPeriod("2026-11");
		expect([iso(nov.start), iso(nov.end)]).toEqual(["2026-10-30", "2026-11-29"]);
		const feb = monthPeriod("2027-02");
		expect([iso(feb.start), iso(feb.end)]).toEqual(["2027-01-30", "2027-02-27"]);
		expect(monthRange("2026-11")).toBe("30 Oct – 29 Nov");
		expect(shiftMonth("2026-11", 1)).toBe("2026-12");
		setMonthStartDay(10);
		expect(monthKey(new Date(2026, 10, 9))).toBe("2026-10");
		expect(shiftMonth("2026-11", -1)).toBe("2026-10");
		setMonthStartDay(1);
		expect(monthKey(new Date(2026, 10, 30))).toBe("2026-11");
		expect(monthRange("2026-11")).toBe("");
	});
});
