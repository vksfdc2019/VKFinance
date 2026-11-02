import { describe, expect, it } from "vitest";
import { addMonths, effectiveYield, fdValue, maturityDate, payoutPerPeriod, quoteDeposit, rdInstalmentsDue, rdMaturity, tenureLabel } from "./deposits";

// The same figures DepositServiceTest asserts on the server, so the preview and the saved deposit agree.
describe("deposit maths", () => {
	const d = "2026-01-01";

	it("compounds FDs quarterly and keeps short ones simple", () => {
		expect(fdValue(100000, 7, "Quarterly", d, "2027-01-01", "2027-01-01")).toBe(107185.9);
		expect(fdValue(100000, 7, "Quarterly", d, "2031-01-01", "2031-01-01")).toBe(141477.82);
		expect(fdValue(100000, 6, "Quarterly", d, "2026-04-01", "2026-04-01")).toBe(101479.45);
	});

	it("matures RDs the way banks quote them", () => {
		expect(rdMaturity(10000, 7, 12, d)).toBe(124621.32);
		expect(rdInstalmentsDue(d, 12, "2026-03-01")).toBe(3);
		expect(rdInstalmentsDue(d, 12, "2025-12-31")).toBe(0);
	});

	it("discounts monthly payouts", () => {
		expect(payoutPerPeriod(100000, 7, "Monthly")).toBe(579.94);
		expect(payoutPerPeriod(100000, 7, "Quarterly")).toBe(1750);
	});

	it("does month arithmetic like Apex", () => {
		expect(addMonths("2026-01-31", 1)).toBe("2026-02-28");
		expect(addMonths("2026-11-15", 3)).toBe("2027-02-15");
		expect(maturityDate("2026-01-01", 13, 5)).toBe("2027-02-06");
		expect(effectiveYield(100000, 107185.9, d, "2027-01-01")).toBe(7.19);
	});

	it("quotes complete terms only", () => {
		const base = { kind: "FD" as const, principal: 100000, instalment: 0, rate: 7, compounding: "Quarterly" as const, payout: "On maturity" as const, startDate: d, months: 12, days: 0 };
		expect(quoteDeposit(base)?.maturityAmount).toBe(107185.9);
		expect(quoteDeposit({ ...base, payout: "Quarterly" })).toMatchObject({ maturityAmount: 100000, interest: 7000, payoutPerPeriod: 1750 });
		expect(quoteDeposit({ ...base, kind: "RD", instalment: 10000 })).toMatchObject({ maturityAmount: 124621.32, invested: 120000 });
		expect(quoteDeposit({ ...base, rate: 0 })).toBeNull();
		expect(quoteDeposit({ ...base, months: 0 })).toBeNull();
		// Half-typed or impossible dates give no quote instead of an unreadable maturity date.
		expect(quoteDeposit({ ...base, startDate: "2026-1" })).toBeNull();
		expect(quoteDeposit({ ...base, startDate: "20262-11-20" })).toBeNull();
		expect(quoteDeposit({ ...base, months: 99999 })).toBeNull();
		expect(tenureLabel(15, 10)).toBe("1 year 3 months 10 days");
	});
});
