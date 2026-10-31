import { createElement } from "lwc";
import VkfOwnerWorkspace from "c/vkfOwnerWorkspace";
import getFamilies from "@salesforce/apex/VkfOwnerController.getFamilies";
import getOverview from "@salesforce/apex/VkfOwnerController.getOverview";
import VkfOwnerEntryModal from "c/vkfOwnerEntryModal";
import sendTestAlert from "@salesforce/apex/VkfOwnerController.sendTestAlert";

const TOAST_EVENT = "lightning__showtoast";

jest.mock(
  "@salesforce/apex/VkfOwnerController.sendTestAlert",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VkfOwnerController.getFamilies",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/VkfOwnerController.getOverview",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
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

const FAMILIES = [
  {
    id: "a01A",
    name: "Sharma Family",
    familyCode: "FAM-1",
    status: "Active",
    currencyCode: "INR",
    memberCount: 4,
    adminName: "Anil Sharma"
  },
  {
    id: "a01B",
    name: "Rao Family",
    familyCode: "FAM-2",
    status: "Suspended",
    currencyCode: "INR",
    memberCount: 1
  }
];

// Apex mocks settle in microtasks; a few ticks cover load + re-render.
const flush = async () => {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
};

function mount() {
  const element = createElement("c-vkf-owner-workspace", {
    is: VkfOwnerWorkspace
  });
  document.body.appendChild(element);
  return element;
}

describe("c-vkf-owner-workspace", () => {
  beforeEach(() => {
    window.localStorage.clear();
    getOverview.mockResolvedValue(
      JSON.stringify({
        kpis: {},
        netWorth: {},
        byCategory: [],
        trend: [],
        accounts: [],
        recent: [],
        upcoming: []
      })
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("opens the first family with its details and the overview", async () => {
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    const element = mount();
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector(".family-name").textContent).toBe(
      "Sharma Family"
    );
    expect(element.shadowRoot.textContent).toContain("4 members");
    expect(
      element.shadowRoot.querySelector("c-vkf-owner-overview")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector(".fab")).not.toBeNull();
    expect(getOverview).toHaveBeenCalledWith(
      expect.objectContaining({ familyId: "a01A" })
    );
  });

  it("reopens the remembered family and hides Add entry when it is suspended", async () => {
    window.localStorage.setItem("vkfOwner.family", "a01B");
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    const element = mount();
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector(".family-name").textContent).toBe(
      "Rao Family"
    );
    expect(element.shadowRoot.querySelector(".fab")).toBeNull();
  });

  it("switches sections from the tab bar and remembers the choice", async () => {
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    const element = mount();
    await flush();

    element.shadowRoot.querySelector('button[data-tab="members"]').click();
    await flush();

    expect(
      element.shadowRoot.querySelector("c-vkf-owner-members")
    ).not.toBeNull();
    expect(element.shadowRoot.querySelector(".month")).toBeNull();
    expect(window.localStorage.getItem("vkfOwner.tab")).toBe("members");
  });

  it("shows the empty state when there are no families", async () => {
    getFamilies.mockResolvedValue("[]");
    const element = mount();
    await flush();

    expect(element.shadowRoot.textContent).toContain("No families yet.");
  });

  it("shows the server message when families cannot load", async () => {
    getFamilies.mockRejectedValue({
      body: {
        message: "You need the VKF Platform Admin permission set to do this."
      }
    });
    const element = mount();
    await flush();

    expect(element.shadowRoot.querySelector(".banner").textContent).toContain(
      "VKF Platform Admin"
    );
  });

  it("opens the entry form for the selected family", async () => {
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    const open = jest
      .spyOn(VkfOwnerEntryModal, "open")
      .mockResolvedValue({ saved: false });
    const element = mount();
    await flush();

    element.shadowRoot.querySelector(".fab").click();
    await flush();

    expect(open).toHaveBeenCalledWith(
      expect.objectContaining({
        familyId: "a01A",
        familyName: "Sharma Family",
        currencyCode: "INR"
      })
    );
  });

  it("reports each channel after a test alert", async () => {
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    sendTestAlert.mockResolvedValue(
      JSON.stringify([
        { channel: "Telegram", status: "skipped" },
        { channel: "Email", status: "sent" },
        { channel: "Push", status: "sent" }
      ])
    );
    const element = mount();
    const toast = jest.fn();
    element.addEventListener(TOAST_EVENT, toast);
    await flush();

    element.shadowRoot
      .querySelector('button[aria-label="Send a test alert"]')
      .click();
    await flush();

    expect(sendTestAlert).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].detail).toEqual(
      expect.objectContaining({
        title: "Test alert sent",
        message: "Telegram off · Email sent · Push sent",
        variant: "success"
      })
    );
  });

  it("keeps a failed channel's reason on screen", async () => {
    getFamilies.mockResolvedValue(JSON.stringify(FAMILIES));
    sendTestAlert.mockResolvedValue(
      JSON.stringify([
        {
          channel: "Telegram",
          status: "failed",
          detail: "Add your Telegram chat ID in VKF Owner Alerts."
        },
        { channel: "Email", status: "sent" },
        { channel: "Push", status: "sent" }
      ])
    );
    const element = mount();
    const toast = jest.fn();
    element.addEventListener(TOAST_EVENT, toast);
    await flush();

    element.shadowRoot
      .querySelector('button[aria-label="Send a test alert"]')
      .click();
    await flush();

    const detail = toast.mock.calls[0][0].detail;
    expect(detail.variant).toBe("warning");
    expect(detail.mode).toBe("sticky");
    expect(detail.message).toContain("Telegram: Add your Telegram chat ID");
  });
});
