import { LightningElement, api } from "lwc";
import getBudget from "@salesforce/apex/VkfOwnerController.getBudget";
import { colorFor, errorMessage, money, parse, percent } from "c/vkfOwnerLib";

/** Month budget: overall ring with pace against the calendar, then each category. */
export default class VkfOwnerBudget extends LightningElement {
  @api currencyCode = "INR";
  data;
  loading = true;
  error;
  _familyId;
  _month;
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
  get month() {
    return this._month;
  }
  set month(value) {
    this._month = value;
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
    this.loading = !this.data;
    this.error = undefined;
    try {
      const result = parse(
        await getBudget({ familyId: this._familyId, month: this._month })
      );
      if (seq === this._requestSeq) {
        this.data = result;
      }
    } catch (e) {
      if (seq === this._requestSeq) {
        this.error = errorMessage(e);
        this.data = undefined;
      }
    } finally {
      if (seq === this._requestSeq) {
        this.loading = false;
      }
    }
  }

  fmt(value) {
    return money(value, this.currencyCode);
  }

  get hasBudget() {
    return Boolean(this.data?.exists && (this.data.lines || []).length);
  }

  get summary() {
    const d = this.data || {};
    const planned = Number(d.totalPlanned) || 0;
    const spent = Number(d.totalSpent) || 0;
    const used = planned > 0 ? (spent / planned) * 100 : 0;
    const elapsed = d.daysInMonth
      ? ((d.daysElapsed || 0) / d.daysInMonth) * 100
      : 0;
    const ahead = used - elapsed;
    let color = "var(--vkf-accent)";
    if (used > 100) {
      color = "var(--vkf-expense)";
    } else if (ahead > 10) {
      color = "var(--vkf-warn)";
    }
    let paceText = "On pace";
    let paceClass = "chip chip_good";
    if (used > 100) {
      paceText = "Over budget";
      paceClass = "chip chip_bad";
    } else if (ahead > 10) {
      paceText = "Spending ahead of the month";
      paceClass = "chip chip_warn";
    }
    return {
      planned: this.fmt(planned),
      spent: this.fmt(spent),
      pct: percent(used),
      ariaLabel: `${percent(used)} of the budget used`,
      ringStyle: `--ring-color: ${color}; --ring-pct: ${Math.min(100, used).toFixed(1)}`,
      paceText,
      paceClass,
      dayText: d.daysInMonth ? `Day ${d.daysElapsed} of ${d.daysInMonth}` : ""
    };
  }

  get lines() {
    return (this.data?.lines || []).map((l, i) => {
      const planned = Number(l.planned) || 0;
      const spent = Number(l.spent) || 0;
      const pct = planned > 0 ? (spent / planned) * 100 : spent > 0 ? 100 : 0;
      const over = spent > planned;
      const color = over ? "var(--vkf-expense)" : l.color || colorFor(l.name);
      return {
        key: l.categoryId || `l${i}`,
        name: l.name,
        essential: l.essential,
        spent: this.fmt(spent),
        planned: this.fmt(planned),
        amountClass: `num line-amt ${over ? "negative" : ""}`,
        swatch: `background: ${l.color || colorFor(l.name)}`,
        bar: `width: ${Math.min(100, pct).toFixed(1)}%; background: ${color}`,
        leftText: over
          ? `${this.fmt(spent - planned)} over`
          : `${this.fmt(planned - spent)} left`,
        leftClass: over ? "negative" : "muted"
      };
    });
  }

  get unbudgeted() {
    return (this.data?.unbudgeted || [])
      .filter((u) => Number(u.spent) > 0)
      .map((u, i) => ({
        key: u.categoryId || `u${i}`,
        name: u.name,
        spent: this.fmt(u.spent),
        swatch: `background: ${u.color || colorFor(u.name)}`
      }));
  }
}
