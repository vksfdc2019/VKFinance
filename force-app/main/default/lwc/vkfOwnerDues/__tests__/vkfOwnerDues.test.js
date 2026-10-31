import { createElement } from "lwc";
import VkfOwnerDues from "c/vkfOwnerDues";
import LightningConfirm from "lightning/confirm";
import getDues from "@salesforce/apex/VkfOwnerController.getDues";
import payDue from "@salesforce/apex/VkfOwnerController.payDue";

jest.mock(
  "@salesforce/apex/VkfOwnerController.getDues",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VkfOwnerController.payDue",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const DUES = [
  {
    kind: "bill",
    id: "bi1",
    parentId: "b1",
    title: "BESCOM",
    subtitle: "Electricity",
    amount: 1500,
    dueDate: "2026-10-28",
    daysLeft: -3
  },
  {
    kind: "emi",
    id: "e1",
    parentId: "l1",
    title: "Home loan EMI",
    subtitle: "Instalment 4",
    amount: 32000,
    dueDate: "2026-11-05",
    daysLeft: 5
  },
  {
    kind: "card",
    id: "s1",
    parentId: "a9",
    title: "HDFC card bill",
    subtitle: "Minimum ₹500",
    amount: 8000,
    dueDate: "2026-11-10",
    daysLeft: 10
  }
];

// Apex mocks settle in microtasks; a few ticks cover load + re-render.
const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

async function mount() {
  const element = createElement("c-vkf-owner-dues", { is: VkfOwnerDues });
  element.familyId = "a01A";
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe("c-vkf-owner-dues", () => {
  beforeEach(() => {
    getDues.mockResolvedValue(JSON.stringify(DUES));
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("totals the window, flags overdue items and only offers Pay for bills and EMIs", async () => {
    const element = await mount();

    expect(getDues).toHaveBeenCalledWith({ familyId: "a01A", days: 30 });
    expect(element.shadowRoot.querySelector(".summary-value").textContent).toBe(
      "₹41,500"
    );
    expect(element.shadowRoot.textContent).toContain("1 overdue");
    expect(element.shadowRoot.querySelectorAll(".pay-btn").length).toBe(2);
    expect(element.shadowRoot.querySelector(".due_overdue")).not.toBeNull();
  });

  it("pays an EMI against its loan after confirmation", async () => {
    LightningConfirm.open = jest.fn().mockResolvedValue(true);
    payDue.mockResolvedValue("{}");
    const element = await mount();

    element.shadowRoot.querySelector('.pay-btn[data-key="emi-e1"]').click();
    await flush();

    expect(payDue).toHaveBeenCalledWith({
      familyId: "a01A",
      kind: "emi",
      recordId: "e1",
      parentId: "l1",
      paymentJson: null
    });
  });

  it("reloads with the chosen window", async () => {
    const element = await mount();
    element.shadowRoot.querySelector('button[data-value="7"]').click();
    await flush();
    await flush();

    expect(getDues).toHaveBeenLastCalledWith({ familyId: "a01A", days: 7 });
  });
});
