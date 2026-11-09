import { describe, expect, it } from "vitest";
import { PO_TD_RATES, SCHEMES, SCHEME_BY_CODE, financialYear, termLabel } from "./schemes";

describe("Indian savings schemes", () => {
	it("knows each scheme once, with its rules", () => {
		expect(new Set(SCHEMES.map((s) => s.code)).size).toBe(SCHEMES.length);
		expect(SCHEME_BY_CODE.PPF).toMatchObject({ kind: "yearly", max: 150000, tax: "80C · EEE" });
		expect(SCHEME_BY_CODE.KVP.months).toBe(115);
		expect(SCHEME_BY_CODE.NPS.ownMaturity).toBe(true);
		expect(PO_TD_RATES[60]).toBe(7.5);
	});

	it("labels terms and financial years", () => {
		expect(termLabel(115)).toBe("9 years 7 months");
		expect(termLabel(60)).toBe("5 years");
		expect(financialYear("2026-11-09")).toBe("FY 2026-27");
		expect(financialYear("2027-03-31")).toBe("FY 2026-27");
		expect(financialYear("2027-04-01")).toBe("FY 2027-28");
	});
});
