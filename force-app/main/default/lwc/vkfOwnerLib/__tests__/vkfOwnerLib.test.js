import {
  colorFor,
  errorMessage,
  initials,
  money,
  monthLabel,
  parse,
  parseDate,
  recall,
  remember,
  shiftMonth,
  signedMoney
} from "c/vkfOwnerLib";

describe("c-vkf-owner-lib", () => {
  it("formats rupees with Indian grouping and treats bad input as zero", () => {
    expect(money(123456, "INR")).toBe("₹1,23,456");
    expect(money("oops", "INR")).toBe("₹0");
    expect(signedMoney(500, true, "INR")).toBe("−₹500");
    expect(signedMoney(-500, false, "INR")).toBe("+₹500");
  });

  it("moves across year boundaries when shifting months", () => {
    expect(shiftMonth("2026-01", -1)).toBe("2025-12");
    expect(shiftMonth("2025-12", 1)).toBe("2026-01");
    expect(monthLabel("2026-10")).toContain("2026");
  });

  it("parses ISO dates as local dates so the day never shifts", () => {
    const d = parseDate("2026-10-31");
    expect([d.getFullYear(), d.getMonth(), d.getDate()]).toEqual([2026, 9, 31]);
    expect(parseDate(null)).toBeNull();
  });

  it("reads Apex error bodies in both shapes", () => {
    expect(errorMessage({ body: { message: "Choose a family first." } })).toBe(
      "Choose a family first."
    );
    expect(errorMessage({ body: [{ message: "A" }, { message: "B" }] })).toBe(
      "A B"
    );
    expect(errorMessage(undefined)).toBe("Something went wrong.");
  });

  it("returns the fallback for empty or invalid JSON", () => {
    expect(parse('{"a":1}')).toEqual({ a: 1 });
    expect(parse("", [])).toEqual([]);
    expect(parse("{bad", "x")).toBe("x");
  });

  it("builds initials and a stable colour", () => {
    expect(initials("Anil kumar Sharma")).toBe("AK");
    expect(initials("")).toBe("?");
    expect(colorFor("Savings")).toBe(colorFor("Savings"));
  });

  it("survives blocked storage", () => {
    const spy = jest
      .spyOn(Storage.prototype, "getItem")
      .mockImplementation(() => {
        throw new Error("blocked");
      });
    jest.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("blocked");
    });
    expect(() => remember("tab", "dues")).not.toThrow();
    expect(recall("tab")).toBeNull();
    spy.mockRestore();
  });
});
