import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import LightningConfirm from "lightning/confirm";
import getTransactions from "@salesforce/apex/VkfOwnerController.getTransactions";
import voidTransaction from "@salesforce/apex/VkfOwnerController.voidTransaction";
import {
  LEDGER_FILTERS,
  colorFor,
  errorMessage,
  initials,
  longDate,
  money,
  parse,
  signedMoney
} from "c/vkfOwnerLib";

const PAGE_SIZE = 50;
const SEARCH_DELAY_MS = 350;

/** Month ledger: search, type filter, day groups, void and cursor paging. */
export default class VkfOwnerLedger extends LightningElement {
  @api currencyCode = "INR";
  items = [];
  rawTotals = {};
  nextCursor;
  query = "";
  type = "";
  loading = true;
  loadingMore = false;
  busy = false;
  error;
  _familyId;
  _month;
  _refreshToken;
  _requestSeq = 0;
  _searchTimer;

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

  disconnectedCallback() {
    clearTimeout(this._searchTimer);
  }

  filtersFor(cursor) {
    const f = { month: this._month, limit: PAGE_SIZE };
    if (this.query) {
      f.q = this.query;
    }
    if (this.type) {
      f.type = this.type;
    }
    if (cursor) {
      f.cursor = cursor;
    }
    return JSON.stringify(f);
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
    this.loading = this.items.length === 0;
    this.error = undefined;
    try {
      const page = parse(
        await getTransactions({
          familyId: this._familyId,
          filtersJson: this.filtersFor()
        }),
        {}
      );
      if (seq === this._requestSeq) {
        this.items = page.items || [];
        this.rawTotals = page.totals || {};
        this.nextCursor = page.nextCursor;
      }
    } catch (e) {
      if (seq === this._requestSeq) {
        this.error = errorMessage(e);
        this.items = [];
      }
    } finally {
      if (seq === this._requestSeq) {
        this.loading = false;
      }
    }
  }

  async handleMore() {
    if (!this.nextCursor) {
      return;
    }
    this.loadingMore = true;
    const seq = this._requestSeq;
    try {
      const page = parse(
        await getTransactions({
          familyId: this._familyId,
          filtersJson: this.filtersFor(this.nextCursor)
        }),
        {}
      );
      if (seq === this._requestSeq) {
        this.items = [...this.items, ...(page.items || [])];
        this.nextCursor = page.nextCursor;
      }
    } catch (e) {
      this.toast("Could not load more", errorMessage(e), "error");
    } finally {
      this.loadingMore = false;
    }
  }

  handleSearch(event) {
    const value = (event.target.value || "").trim();
    clearTimeout(this._searchTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._searchTimer = setTimeout(() => {
      if (value !== this.query) {
        this.query = value;
        this.load();
      }
    }, SEARCH_DELAY_MS);
  }

  handleFilter(event) {
    this.type = event.currentTarget.dataset.value;
    this.load();
  }

  async handleVoid(event) {
    const { id, title, amount } = event.currentTarget.dataset;
    const ok = await LightningConfirm.open({
      label: "Void this entry?",
      message: `${title} · ${amount}. Balances are restored, and a voided payment re-opens its bill or EMI.`,
      theme: "warning"
    });
    if (!ok) {
      return;
    }
    this.busy = true;
    try {
      await voidTransaction({ familyId: this._familyId, transactionId: id });
      this.toast("Entry voided", `${title} was voided.`, "success");
      this.dispatchEvent(new CustomEvent("changed"));
    } catch (e) {
      this.toast("Could not void", errorMessage(e), "error");
    } finally {
      this.busy = false;
    }
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  get filters() {
    return LEDGER_FILTERS.map((f) => ({
      ...f,
      selected: f.value === this.type ? "true" : "false",
      cls: f.value === this.type ? "segment segment_active" : "segment"
    }));
  }

  get totals() {
    return {
      income: money(this.rawTotals.income, this.currencyCode),
      expenses: money(this.rawTotals.expenses, this.currencyCode),
      count: this.rawTotals.count || 0
    };
  }

  get moreLabel() {
    return this.loadingMore ? "Loading…" : "Load more";
  }

  get groups() {
    const byDay = new Map();
    for (const t of this.items) {
      const key = t.txnDate || "none";
      if (!byDay.has(key)) {
        byDay.set(key, { key, label: longDate(t.txnDate), items: [], net: 0 });
      }
      const g = byDay.get(key);
      const debit = t.direction === "Debit";
      const isVoid = t.status === "Void";
      const isTransfer = Boolean(t.transferGroupId);
      if (!isVoid && !isTransfer) {
        g.net += debit ? -Number(t.amount || 0) : Number(t.amount || 0);
      }
      const title = t.payee || t.categoryName || t.type;
      const badges = [];
      if (isVoid) {
        badges.push("Void");
      }
      if (isTransfer && t.counterAccountName) {
        badges.push(`${debit ? "To" : "From"} ${t.counterAccountName}`);
      }
      if (t.source && t.source !== "Manual") {
        badges.push(t.source);
      }
      if (t.paymentMode) {
        badges.push(t.paymentMode);
      }
      g.items.push({
        id: t.id,
        title,
        sub: [
          t.parentCategoryName
            ? `${t.parentCategoryName} › ${t.categoryName}`
            : t.categoryName,
          t.accountName,
          t.memberName
        ]
          .filter(Boolean)
          .join(" · "),
        badges,
        amount: signedMoney(t.amount, debit, this.currencyCode),
        amountClass: `row-amount num ${isVoid ? "struck" : debit ? "negative" : "positive"}`,
        rowClass: isVoid ? "row row_void" : "row",
        canVoid: !isVoid && t.canEdit !== false,
        initials: initials(title),
        avatar: `background: ${t.color || colorFor(title)}`
      });
    }
    return [...byDay.values()].map((g) => ({
      ...g,
      net: `${g.net < 0 ? "−" : "+"}${money(Math.abs(g.net), this.currencyCode)}`,
      netClass: `num day-net ${g.net < 0 ? "negative" : "positive"}`
    }));
  }
}
