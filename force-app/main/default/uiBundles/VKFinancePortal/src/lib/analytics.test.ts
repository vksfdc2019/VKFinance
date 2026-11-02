import { describe, expect, it } from "vitest";
import type { Account } from "@/api/financeTypes";
import type { MonthFlow } from "@/api/analyticsTypes";
import { assetMix, cardUse, emiBurden, monthProgress, moneySplit, savingsRateStatus } from "./analytics";

const flow = (f: Partial<MonthFlow>): MonthFlow => ({ month: "2026-11", periodStart: "2026-10-30", periodEnd: "2026-11-29", income: 100000, spending: 30000, bills: 5000, emis: 35000, saved: 30000, ...f });
const account = (a: Partial<Account>): Account => ({ id: "a", name: "A", type: "Savings", balance: 0, isLiability: false, ...a }) as Account;

describe("analytics numbers", () => {
	it("splits income in the validated order and hides a negative saving", () => {
		expect(moneySplit(flow({})).map((s) => s.key)).toEqual(["emis", "spending", "bills", "saved"]);
		expect(moneySplit(flow({ saved: -2000 }))[3].value).toBe(0);
	});

	it("groups what you own and leaves out what you owe", () => {
		const mix = assetMix([
			account({ type: "Savings", balance: 50000 }),
			account({ type: "Current", balance: 10000 }),
			account({ type: "Fixed Deposit", balance: 200000 }),
			account({ type: "Credit Card", balance: 9000, isLiability: true }),
		]);
		expect(mix.map((s) => [s.key, s.value])).toEqual([
			["bank", 60000],
			["deposits", 200000],
		]);
	});

	it("counts a shared card limit once", () => {
		const shared = { id: "g", name: "HDFC", creditLimit: 200000, outstanding: 60000, available: 140000, utilisationPct: 30, overLimit: 0, activeCardCount: 2, version: 1 };
		const use = cardUse([
			account({ type: "Credit Card", isLiability: true, balance: 40000, sharedCredit: shared }),
			account({ type: "Credit Card", isLiability: true, balance: 20000, sharedCredit: shared }),
			account({ type: "Credit Card", isLiability: true, balance: 10000, creditLimit: 100000 }),
		]);
		expect(use.pct).toBeCloseTo(23.3);
		expect(use.status).toBe("good");
		expect(cardUse([]).pct).toBeUndefined();
	});

	it("reads EMI burden and savings rate against Indian norms", () => {
		expect(emiBurden(flow({})).status).toBe("good");
		expect(emiBurden(flow({ emis: 45000 })).status).toBe("warning");
		expect(emiBurden(flow({ emis: 55000 })).status).toBe("critical");
		expect(savingsRateStatus(25)).toBe("good");
		expect(savingsRateStatus(12)).toBe("warning");
		expect(savingsRateStatus(5)).toBe("critical");
	});

	it("measures progress through a payday month", () => {
		const p = { periodStart: "2026-10-30", periodEnd: "2026-11-29" };
		expect(monthProgress(p, "2026-10-29")).toBe(0);
		expect(monthProgress(p, "2026-11-29")).toBe(1);
		expect(monthProgress(p, "2026-11-14")).toBeCloseTo(16 / 31);
	});
});
