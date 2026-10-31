import { LightningElement, api } from "lwc";
import getOverview from "@salesforce/apex/VkfOwnerController.getOverview";
import {
  colorFor,
  errorMessage,
  initials,
  money,
  monthLabel,
  parse,
  percent,
  shortDate,
  signedMoney
} from "c/vkfOwnerLib";

const TOP_CATEGORIES = 6;
const LIST_SIZE = 5;

/** Family overview: net worth, month KPIs, category spend, trend, accounts, dues, recent entries. */
export default class VkfOwnerOverview extends LightningElement {
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
    // Several setters fire together on first render; only the latest request may write.
    const seq = ++this._requestSeq;
    await Promise.resolve();
    if (seq !== this._requestSeq) {
      return;
    }
    this.loading = !this.data;
    this.error = undefined;
    try {
      const result = parse(
        await getOverview({ familyId: this._familyId, month: this._month })
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

  fmt(value, compact) {
    return money(value, this.currencyCode, compact);
  }

  get worth() {
    const w = this.data?.netWorth || {};
    const assets = Number(w.assets) || 0;
    const liabilities = Number(w.liabilities) || 0;
    const share =
      assets + liabilities > 0 ? (assets / (assets + liabilities)) * 100 : 100;
    return {
      net: this.fmt(w.net),
      assets: this.fmt(assets),
      liabilities: this.fmt(liabilities),
      assetStyle: `width: ${share.toFixed(1)}%`
    };
  }

  get kpis() {
    const k = this.data?.kpis || {};
    const delta = (now, prev, goodWhenUp) => {
      if (!prev) {
        return {};
      }
      const change = ((now - prev) / prev) * 100;
      const up = change >= 0;
      const good = up === goodWhenUp;
      return {
        delta: `${up ? "▲" : "▼"} ${Math.abs(change).toFixed(0)}% vs last month`,
        deltaClass: `chip ${good ? "chip_good" : "chip_bad"}`
      };
    };
    const net = Number(k.net) || 0;
    return [
      {
        key: "income",
        label: "Income",
        value: this.fmt(k.income),
        valueClass: "kpi-value num positive",
        ...delta(k.income, k.prevIncome, true)
      },
      {
        key: "spent",
        label: "Spent",
        value: this.fmt(k.expenses),
        valueClass: "kpi-value num",
        ...delta(k.expenses, k.prevExpenses, false)
      },
      {
        key: "net",
        label: "Net this month",
        value: this.fmt(net),
        valueClass: `kpi-value num ${net < 0 ? "negative" : "positive"}`
      },
      {
        key: "rate",
        label: "Savings rate",
        value:
          k.savingsRate === undefined || k.savingsRate === null
            ? "—"
            : percent(k.savingsRate),
        valueClass: "kpi-value num"
      }
    ];
  }

  get budgetLine() {
    const b = this.data?.budget;
    if (!b || !b.planned) {
      return null;
    }
    return `${percent((b.spent / b.planned) * 100)} of budget${b.overCount ? ` · ${b.overCount} over` : ""}`;
  }

  get categories() {
    const rows = (this.data?.byCategory || []).slice(0, TOP_CATEGORIES);
    const max = Math.max(1, ...rows.map((c) => Number(c.amount) || 0));
    return rows.map((c, i) => {
      const color = c.color || colorFor(c.name);
      return {
        key: c.categoryId || `c${i}`,
        name: c.name,
        amount: this.fmt(c.amount),
        swatch: `background: ${color}`,
        bar: `width: ${(((Number(c.amount) || 0) / max) * 100).toFixed(1)}%; background: ${color}`
      };
    });
  }

  get trend() {
    const rows = (this.data?.trend || []).slice(-6);
    const max = Math.max(
      1,
      ...rows.flatMap((t) => [Number(t.income) || 0, Number(t.expenses) || 0])
    );
    const h = (v) =>
      `height: ${Math.max(3, ((Number(v) || 0) / max) * 100).toFixed(1)}%`;
    return rows.map((t) => ({
      key: t.month,
      label: monthLabel(t.month, true).split(" ")[0],
      title: `${monthLabel(t.month)} · in ${this.fmt(t.income)} · out ${this.fmt(t.expenses)}`,
      inStyle: h(t.income),
      outStyle: h(t.expenses)
    }));
  }

  get trendLabel() {
    return this.trend.map((t) => t.title).join("; ");
  }

  get accounts() {
    return (this.data?.accounts || []).map((a) => {
      const color = a.color || colorFor(a.name);
      return {
        id: a.id,
        name: a.name,
        type: a.last4 ? `${a.type} ·· ${a.last4}` : a.type,
        balance: this.fmt(a.balance),
        owner: a.isShared ? "Shared" : a.ownerName || "",
        style: `--account-color: ${color}`
      };
    });
  }

  get upcoming() {
    return (this.data?.upcoming || []).slice(0, LIST_SIZE).map((d, i) => ({
      key: d.id || `d${i}`,
      title: d.title,
      when:
        d.daysLeft < 0
          ? `Overdue · ${shortDate(d.dueDate)}`
          : d.daysLeft === 0
            ? "Due today"
            : `Due ${shortDate(d.dueDate)} · in ${d.daysLeft}d`,
      amount: this.fmt(d.amount),
      initials: initials(d.title),
      avatar: `background: ${d.color || colorFor(d.title)}`
    }));
  }

  get recent() {
    return (this.data?.recent || []).slice(0, LIST_SIZE).map((t) => {
      const title = t.payee || t.categoryName || t.type;
      const debit = t.direction === "Debit";
      return {
        id: t.id,
        title,
        sub: [shortDate(t.txnDate), t.accountName, t.memberName]
          .filter(Boolean)
          .join(" · "),
        amount: signedMoney(t.amount, debit, this.currencyCode),
        amountClass: `row-amount num ${debit ? "negative" : "positive"}`,
        initials: initials(title),
        avatar: `background: ${t.color || colorFor(title)}`
      };
    });
  }
}
