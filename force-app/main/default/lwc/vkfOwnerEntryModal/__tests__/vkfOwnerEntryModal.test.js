import { createElement } from "lwc";
import VkfOwnerEntryModal from "c/vkfOwnerEntryModal";
import getEntryOptions from "@salesforce/apex/VkfOwnerController.getEntryOptions";
import saveEntry from "@salesforce/apex/VkfOwnerController.saveEntry";

jest.mock(
  "@salesforce/apex/VkfOwnerController.getEntryOptions",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VkfOwnerController.saveEntry",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const OPTIONS = {
  accounts: [
    {
      id: "acc1",
      name: "HDFC Savings",
      type: "Savings",
      balance: 10000,
      status: "Active",
      canUse: true
    },
    {
      id: "acc2",
      name: "Wallet",
      type: "Cash",
      balance: 500,
      status: "Active",
      canUse: true
    },
    {
      id: "acc3",
      name: "Home loan",
      type: "Loan",
      balance: -100000,
      status: "Active",
      canUse: true
    }
  ],
  categories: [
    { id: "p1", name: "Food", kind: "Expense" },
    {
      id: "c1",
      name: "Groceries",
      kind: "Expense",
      parentId: "p1",
      sortOrder: 1
    },
    { id: "i1", name: "Salary", kind: "Income" }
  ],
  members: [{ id: "m1", name: "Anil Sharma", role: "Family Admin" }],
  paymentModes: ["Cash", "UPI"]
};

// Apex mocks settle in microtasks; a few ticks cover load + re-render.
const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function mount() {
  const element = createElement("c-vkf-owner-entry-modal", {
    is: VkfOwnerEntryModal
  });
  element.familyId = "a01A";
  element.familyName = "Sharma Family";
  element.currencyCode = "INR";
  document.body.appendChild(element);
  // Options load in connectedCallback, then the form re-renders.
  await flush();
  await flush();
  return element;
}

function setAmount(element, value) {
  const input = element.shadowRoot.querySelector(".amount-input");
  input.value = value;
  input.dispatchEvent(new CustomEvent("input"));
}

function primary(element) {
  return element.shadowRoot.querySelector(".btn_primary");
}

describe("c-vkf-owner-entry-modal", () => {
  beforeEach(() => {
    getEntryOptions.mockResolvedValue(JSON.stringify(OPTIONS));
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("offers non-loan accounts and categories of the chosen kind with parent names", async () => {
    const element = await mount();
    // name is an @api property on base components, not a reflected attribute.
    const byName = (name) =>
      [...element.shadowRoot.querySelectorAll("lightning-combobox")].find(
        (c) => c.name === name
      );
    const account = byName("accountId");
    const category = byName("categoryId");

    expect(account.options.map((o) => o.value)).toEqual(["acc1", "acc2"]);
    expect(account.value).toBe("acc1");
    expect(category.options.map((o) => o.label)).toEqual([
      "Food",
      "Food › Groceries"
    ]);
    expect(element.shadowRoot.querySelectorAll(".quick-chip").length).toBe(1);
  });

  it("refuses to save without an amount", async () => {
    const element = await mount();
    primary(element).click();
    await flush();

    expect(saveEntry).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector(".alert").textContent).toBe(
      "Enter an amount above zero."
    );
  });

  it("saves an expense with the defaults and closes with a message", async () => {
    saveEntry.mockResolvedValue("{}");
    const element = await mount();
    const closed = jest.fn();
    element.addEventListener("close", closed);

    setAmount(element, "450");
    element.shadowRoot.querySelector(".quick-chip").click();
    await flush();
    primary(element).click();
    await flush();

    const body = JSON.parse(saveEntry.mock.calls[0][0].entryJson);
    expect(body).toEqual(
      expect.objectContaining({
        type: "Expense",
        amount: 450,
        accountId: "acc1",
        categoryId: "c1",
        paymentMode: "UPI",
        memberId: "m1"
      })
    );
    expect(closed.mock.calls[0][0].detail).toEqual({
      saved: true,
      message: "Expense of ₹450 recorded."
    });
  });

  it("sends a transfer between two accounts", async () => {
    saveEntry.mockResolvedValue("{}");
    const element = await mount();

    element.shadowRoot.querySelector('button[data-value="Transfer"]').click();
    await flush();
    setAmount(element, "200");
    await flush();
    primary(element).click();
    await flush();

    const body = JSON.parse(saveEntry.mock.calls[0][0].entryJson);
    expect(body).toEqual(
      expect.objectContaining({
        type: "Transfer",
        amount: 200,
        fromAccountId: "acc1",
        toAccountId: "acc2"
      })
    );
  });

  it("keeps the form open and shows the service message when saving fails", async () => {
    saveEntry.mockRejectedValue({
      body: { message: "Pay bills from a bank, cash, wallet or card account." }
    });
    const element = await mount();
    setAmount(element, "10");
    element.shadowRoot.querySelector(".quick-chip").click();
    await flush();
    primary(element).click();
    await flush();

    expect(element.shadowRoot.querySelector(".alert").textContent).toContain(
      "Pay bills from"
    );
  });
});
