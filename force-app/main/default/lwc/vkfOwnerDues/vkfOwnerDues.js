import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getDues from "@salesforce/apex/VkfOwnerController.getDues";
import payDue from "@salesforce/apex/VkfOwnerController.payDue";
import {
  colorFor,
  errorMessage,
  initials,
  longDate,
  money,
  parse
} from "c/vkfOwnerLib";

const WINDOWS = [7, 30, 90];
const PAYABLE = new Set(["bill", "emi"]);
const SOON_DAYS = 3;

/** Bills, EMIs and card bills coming up; bills and EMIs can be paid in one tap. */
export default class VkfOwnerDues extends LightningElement {
  @api currencyCode = "INR";
  days = 30;
  rows = [];
  loading = true;
  busy = false;
  error;
  _familyId;
  _refreshToken;
  _requestSeq = 0;

  @api
  get familyId() {
    return this._familyId;
  }
  set familyId(value) {
    this._familyId = value;
    this.load();
  }

  @api
  get refreshToken() {
    return this._refreshToken;
  }
  set refreshToken(value) {
    const changed =
      this._refreshToken !== undefined && value !== this._refreshToken;
    this._refreshToken = value;
    if (changed) {
      this.load();
    }
  }

  async load() {
    if (!this._familyId) {
      return;
    }
    const seq = ++this._requestSeq;
    await Promise.resolve();
    if (seq !== this._requestSeq) {
      return;
    }
    this.loading = this.rows.length === 0;
    this.error = undefined;
    try {
      const result = parse(
        await getDues({ familyId: this._familyId, days: this.days }),
        []
      );
      if (seq === this._requestSeq) {
        this.rows = result;
      }
    } catch (e) {
      if (seq === this._requestSeq) {
        this.error = errorMessage(e);
        this.rows = [];
      }
    } finally {
      if (seq === this._requestSeq) {
        this.loading = false;
      }
    }
  }

  handleWindow(event) {
    this.days = Number(event.currentTarget.dataset.value);
    this.load();
  }

  async handlePay(event) {
    const item = this.items.find(
      (d) => d.key === event.currentTarget.dataset.key
    );
    if (!item) {
      return;
    }
    const ok = await LightningConfirm.open({
      label: `Pay ${item.title}?`,
      message: `${item.amount} will be recorded from the usual account for this ${item.kind === "emi" ? "loan" : "bill"}.`,
      theme: "info"
    });
    if (!ok) {
      return;
    }
    this.busy = true;
    try {
      await payDue({
        familyId: this._familyId,
        kind: item.kind,
        recordId: item.id,
        parentId: item.parentId,
        paymentJson: null
      });
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Paid",
          message: `${item.title} · ${item.amount}`,
          variant: "success"
        })
      );
      this.dispatchEvent(new CustomEvent("changed"));
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Payment not recorded",
          message: errorMessage(e),
          variant: "error"
        })
      );
    } finally {
      this.busy = false;
    }
  }

  get windows() {
    return WINDOWS.map((value) => ({
      value,
      label: `${value} days`,
      selected: value === this.days ? "true" : "false",
      cls: value === this.days ? "segment segment_active" : "segment"
    }));
  }

  get items() {
    return this.rows.map((d, i) => {
      const overdue = d.daysLeft < 0;
      const soon = !overdue && d.daysLeft <= SOON_DAYS;
      let badge;
      if (overdue) {
        badge = `${Math.abs(d.daysLeft)}d overdue`;
      } else if (d.daysLeft === 0) {
        badge = "Due today";
      } else {
        badge = `In ${d.daysLeft}d`;
      }
      return {
        key: `${d.kind}-${d.id || i}`,
        kind: d.kind,
        id: d.id,
        parentId: d.parentId,
        title: d.title,
        subtitle: d.subtitle,
        amount: money(d.amount, this.currencyCode),
        date: longDate(d.dueDate),
        badge,
        badgeClass: `chip ${overdue ? "chip_bad" : soon ? "chip_warn" : ""}`,
        cardClass: `card due ${overdue ? "due_overdue" : ""}`,
        payable: PAYABLE.has(d.kind),
        initials: initials(d.title),
        avatar: `background: ${d.color || colorFor(d.title)}`
      };
    });
  }

  get summary() {
    const total = this.rows.reduce(
      (sum, d) => sum + (Number(d.amount) || 0),
      0
    );
    const overdue = this.rows.filter((d) => d.daysLeft < 0).length;
    return {
      total: money(total, this.currencyCode),
      count: `${this.rows.length} ${this.rows.length === 1 ? "item" : "items"}`,
      overdue: overdue ? `${overdue} overdue` : null
    };
  }
}
