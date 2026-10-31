import { createElement } from "lwc";
import VkfOwnerLedger from "c/vkfOwnerLedger";
import LightningConfirm from "lightning/confirm";
import getTransactions from "@salesforce/apex/VkfOwnerController.getTransactions";
import voidTransaction from "@salesforce/apex/VkfOwnerController.voidTransaction";

jest.mock(
  "@salesforce/apex/VkfOwnerController.getTransactions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VkfOwnerController.voidTransaction",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PAGE = {
  items: [
    {
      id: "t1",
      txnDate: "2026-10-30",
      type: "Expense",
      direction: "Debit",
      amount: 450,
      payee: "Fuel Stop",
      categoryName: "Fuel",
      accountName: "HDFC",
      status: "Cleared",
      canEdit: true,
      paymentMode: "UPI"
    },
    {
      id: "t2",
      txnDate: "2026-10-30",
      type: "Income",
      direction: "Credit",
      amount: 50000,
      categoryName: "Salary",
      accountName: "HDFC",
      status: "Cleared",
      canEdit: true
    },
    {
      id: "t3",
      txnDate: "2026-10-29",
      type: "Expense",
      direction: "Debit",
      amount: 99,
      payee: "Old",
      accountName: "Cash",
      status: "Void",
      canEdit: true
    }
  ],
  totals: { income: 50000, expenses: 450, count: 3 },
  nextCursor: "c2"
};

// Apex mocks settle in microtasks; a few ticks cover load + re-render.
const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function mount() {
  const element = createElement("c-vkf-owner-ledger", { is: VkfOwnerLedger });
  element.familyId = "a01A";
  element.month = "2026-10";
  element.currencyCode = "INR";
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe("c-vkf-owner-ledger", () => {
  beforeEach(() => {
    getTransactions.mockResolvedValue(JSON.stringify(PAGE));
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("loads once for the month and groups entries by day", async () => {
    const element = await mount();

    expect(getTransactions).toHaveBeenCalledTimes(1);
    expect(JSON.parse(getTransactions.mock.calls[0][0].filtersJson)).toEqual({
      month: "2026-10",
      limit: 50
    });
    const days = element.shadowRoot.querySelectorAll("section.day");
    expect(days.length).toBe(2);
    expect(days[0].querySelector(".day-net").textContent).toBe("+₹49,550");
    expect(element.shadowRoot.querySelector(".more")).not.toBeNull();
  });

  it("does not offer void on an entry that is already void", async () => {
    const element = await mount();
    const buttons = [...element.shadowRoot.querySelectorAll(".void-btn")].map(
      (b) => b.dataset.id
    );
    expect(buttons).toEqual(["t1", "t2"]);
  });

  it("sends the type filter to Apex", async () => {
    const element = await mount();
    element.shadowRoot
      .querySelector('button[data-value="Income,Refund"]')
      .click();
    await flush();
    await flush();

    const last =
      getTransactions.mock.calls[getTransactions.mock.calls.length - 1][0];
    expect(JSON.parse(last.filtersJson).type).toBe("Income,Refund");
  });

  it("voids after confirmation and tells the shell", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    voidTransaction.mockResolvedValue();
    const element = await mount();
    const changed = jest.fn();
    element.addEventListener("changed", changed);

    element.shadowRoot.querySelector('.void-btn[data-id="t1"]').click();
    await flush();

    expect(voidTransaction).toHaveBeenCalledWith({
      familyId: "a01A",
      transactionId: "t1"
    });
    expect(changed).toHaveBeenCalled();
  });

  it("keeps the entry when the confirmation is cancelled", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(false);
    const element = await mount();

    element.shadowRoot.querySelector('.void-btn[data-id="t1"]').click();
    await flush();

    expect(voidTransaction).not.toHaveBeenCalled();
  });
});
