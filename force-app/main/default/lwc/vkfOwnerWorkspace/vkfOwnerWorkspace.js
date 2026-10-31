import { LightningElement } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getFamilies from "@salesforce/apex/VkfOwnerController.getFamilies";
import VkfOwnerEntryModal from "c/vkfOwnerEntryModal";
import {
  currentMonth,
  errorMessage,
  monthLabel,
  parse,
  recall,
  remember,
  shiftMonth
} from "c/vkfOwnerLib";

const TABS = [
  { value: "overview", label: "Overview", monthly: true },
  { value: "ledger", label: "Ledger", monthly: true },
  { value: "dues", label: "Dues", monthly: false },
  { value: "budget", label: "Budget", monthly: true },
  { value: "members", label: "Family", monthly: false }
];

/**
 * Shell of the Owner Workspace: family picker, month, section tabs and the add-entry button.
 * Sections load their own data from familyId/month; bumping refreshToken reloads them.
 */
export default class VkfOwnerWorkspace extends LightningElement {
  families = [];
  familyId;
  month = currentMonth();
  activeTab = recall("tab") || "overview";
  refreshToken = 0;
  loadingFamilies = true;
  error;

  connectedCallback() {
    if (!TABS.some((t) => t.value === this.activeTab)) {
      this.activeTab = "overview";
    }
    this.loadFamilies();
  }

  async loadFamilies() {
    this.loadingFamilies = true;
    this.error = undefined;
    try {
      this.families = parse(await getFamilies(), []);
      const remembered = recall("family");
      const keep = this.families.find(
        (f) => f.id === (this.familyId || remembered)
      );
      this.familyId = (keep || this.families[0])?.id;
    } catch (e) {
      this.error = errorMessage(e);
    } finally {
      this.loadingFamilies = false;
    }
  }

  get family() {
    return this.families.find((f) => f.id === this.familyId) || {};
  }

  get hasFamilies() {
    return !this.loadingFamilies && this.families.length > 0;
  }

  get showEmpty() {
    return !this.loadingFamilies && !this.error && this.families.length === 0;
  }

  get familyOptions() {
    return this.families.map((f) => ({
      label: f.status === "Active" ? f.name : `${f.name} (${f.status})`,
      value: f.id
    }));
  }

  get currencyCode() {
    return this.family.currencyCode || "INR";
  }

  get canWrite() {
    return this.family.status === "Active";
  }

  get statusClass() {
    return this.family.status === "Active"
      ? "meta-pill meta-pill_good"
      : "meta-pill meta-pill_warn";
  }

  get memberLabel() {
    const n = this.family.memberCount || 0;
    return `${n} ${n === 1 ? "member" : "members"}`;
  }

  get tabs() {
    return TABS.map((t) => ({
      ...t,
      cls: t.value === this.activeTab ? "segment segment_active" : "segment",
      current: t.value === this.activeTab ? "page" : null
    }));
  }

  get showMonth() {
    return TABS.find((t) => t.value === this.activeTab)?.monthly;
  }

  get monthText() {
    return monthLabel(this.month);
  }

  get isCurrentMonth() {
    return this.month >= currentMonth();
  }

  get isOverview() {
    return this.activeTab === "overview";
  }

  get isLedger() {
    return this.activeTab === "ledger";
  }

  get isDues() {
    return this.activeTab === "dues";
  }

  get isBudget() {
    return this.activeTab === "budget";
  }

  handleFamilyChange(event) {
    this.familyId = event.detail.value;
    remember("family", this.familyId);
  }

  handleTab(event) {
    this.activeTab = event.currentTarget.dataset.tab;
    remember("tab", this.activeTab);
  }

  handlePrevMonth() {
    this.month = shiftMonth(this.month, -1);
  }

  handleNextMonth() {
    if (!this.isCurrentMonth) {
      this.month = shiftMonth(this.month, 1);
    }
  }

  handleRefresh() {
    this.loadFamilies();
    this.refreshToken += 1;
  }

  handleChanged() {
    this.refreshToken += 1;
  }

  async handleAdd() {
    const result = await VkfOwnerEntryModal.open({
      size: "small",
      label: `New entry · ${this.family.name}`,
      familyId: this.familyId,
      familyName: this.family.name,
      currencyCode: this.currencyCode
    });
    if (result?.saved) {
      this.refreshToken += 1;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Saved",
          message: result.message,
          variant: "success"
        })
      );
    }
  }
}
