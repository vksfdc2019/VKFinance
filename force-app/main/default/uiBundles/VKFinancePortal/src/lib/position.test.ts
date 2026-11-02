import { describe, expect, it } from "vitest";
import type { MoneyPosition } from "@/api/positionTypes";
import type { BillInstance, Loan } from "@/api/commitmentTypes";
import { alerts, billHeadline, cardHeadline, dailyAllowance, daysLeft, dueEvents, loanHeadline } from "./position";

function position(overrides: Partial<MoneyPosition> = {}): MoneyPosition {
	return {
		month: "2026-11",
		periodStart: "2026-10-30",
		periodEnd: "2026-11-29",
		asOf: "2026-11-20",
		isCurrent: true,
		currencyCode: "INR",
		summary: { liquid: 100000, cardAvailable: 200000, owed: 0, duesRemaining: 10000, leftAfterDues: 90000, moneyIn: 0, moneyOut: 0 },
		...overrides,
	};
}

const bill = (b: Partial<BillInstance>): BillInstance => ({
	id: "b1", billId: "B1", billName: "Electricity", dueDate: "2026-11-22", amountDue: 1500, amountPaid: 0, status: "Due", autoPay: false, daysLeft: 2, canPay: true, ...b,
});

describe("money position readings", () => {
	it("splits what is left after dues over the days left, today included", () => {
		expect(daysLeft(position())).toBe(10);
		expect(dailyAllowance(position())).toBe(9000);
		expect(dailyAllowance(position({ summary: { ...position().summary, leftAfterDues: -500 } }))).toBe(0);
		expect(dailyAllowance(position({ isCurrent: false }))).toBeUndefined();
	});

	it("reads card use against the 30% CIBIL guideline", () => {
		const cards = (pct: number) => ({ totalLimit: 100000, used: pct * 1000, available: 100000 - pct * 1000, utilisationPct: pct, spent: 0, paid: 0, dueNow: 0, minimumDue: 0, overdueCount: 0, cards: [{ id: "c", name: "HDFC", used: 0, spent: 0, paid: 0, dueRemaining: 0 }] });
		expect(cardHeadline(position({ cards: cards(12) }), "INR")?.tone).toBe("good");
		expect(cardHeadline(position({ cards: cards(45) }), "INR")?.tone).toBe("warning");
		expect(cardHeadline(position({ cards: cards(85) }), "INR")?.tone).toBe("critical");
	});

	it("names the next bill, or says they are all paid", () => {
		const bills = (items: BillInstance[]) => ({ due: 3000, paid: 0, remaining: 3000, overdue: 0, count: items.length, paidCount: 0, overdueCount: 0, items });
		expect(billHeadline(position({ bills: bills([bill({ billName: "Broadband", dueDate: "2026-11-25" }), bill({})]) }), "INR")?.text).toContain("Next is Electricity in 2 days");
		expect(billHeadline(position({ bills: { ...bills([bill({ status: "Paid" })]), paidCount: 1 } }), "INR")?.text).toBe("All 1 bill paid this month.");
	});

	it("counts EMIs left on a single loan", () => {
		const loan = { id: "L", name: "Home loan", status: "Active", repaidPct: 39, installmentsLeft: 54 } as Loan;
		const loans = { borrowed: 1, outstanding: 1, repaid: 0, monthlyEmi: 0, emiDue: 0, emiPaid: 0, emiRemaining: 0, interestRemaining: 0, activeCount: 1, overdueCount: 0, loans: [{ loan, emiThisMonth: 0, paidThisMonth: 0, monthStatus: "None" as const }] };
		expect(loanHeadline(position({ loans }), "INR")?.text).toBe("Home loan is 39% repaid - 54 EMIs to go.");
	});

	it("raises overdue first, then soon-due bills and low balances; skips auto-pay", () => {
		const p = position({
			bills: { due: 0, paid: 0, remaining: 0, overdue: 0, count: 3, paidCount: 0, overdueCount: 1, items: [bill({ billName: "Water", status: "Overdue", daysLeft: -3 }), bill({}), bill({ billName: "OTT", autoPay: true })] },
			bank: { available: 3000, locked: 0, moneyIn: 0, moneyOut: 0, accounts: [{ id: "s", name: "SBI Savings", type: "Savings", liquid: true, balance: 3000, moneyIn: 0, moneyOut: 0 }] },
		});
		const list = alerts(p, "INR");
		expect(list.map((a) => a.tone)).toEqual(["critical", "warning", "warning"]);
		expect(list[0].text).toContain("Water");
		expect(list.some((a) => a.text.includes("OTT"))).toBe(false);
		expect(list[2].text).toContain("Balance is low in SBI Savings");
		expect(alerts({ ...p, isCurrent: false }, "INR")).toEqual([]);
	});

	it("puts bills, EMIs and card bills on the calendar, only inside the month", () => {
		const p = position({
			bills: { due: 0, paid: 0, remaining: 0, overdue: 0, count: 2, paidCount: 0, overdueCount: 0, items: [bill({ dueDate: "2026-11-05" }), bill({ dueDate: "2026-10-20", status: "Overdue" })] },
			cards: { totalLimit: 0, used: 0, available: 0, spent: 0, paid: 0, dueNow: 5000, minimumDue: 0, overdueCount: 0, cards: [{ id: "c", name: "HDFC", used: 5000, spent: 0, paid: 0, dueRemaining: 5000, dueDate: "2026-11-03" }] },
		});
		expect(dueEvents(p).map((e) => `${e.date} ${e.kind}`)).toEqual(["2026-11-03 card", "2026-11-05 bill"]);
	});
});
