import { api } from "lwc";
import LightningModal from "lightning/modal";
import getEntryOptions from "@salesforce/apex/VkfOwnerController.getEntryOptions";
import saveEntry from "@salesforce/apex/VkfOwnerController.saveEntry";
import { errorMessage, isoToday, money, parse } from "c/vkfOwnerLib";

const TYPES = [
  { value: "Expense", label: "Expense" },
  { value: "Income", label: "Income" },
  { value: "Transfer", label: "Transfer" }
];
const QUICK_COUNT = 6;

/**
 * Add an expense, income or transfer for the chosen family. Validation that matters
 * (account fits type, category kind, balances) stays in the Apex services; this form
 * only catches the obvious before the round trip.
 */
export default class VkfOwnerEntryModal extends LightningModal {
  @api familyId;
  @api familyName;
  @api currencyCode = "INR";

  options = { accounts: [], categories: [], members: [], paymentModes: [] };
  form = { type: "Expense", amount: "", date: isoToday(), paymentMode: "UPI" };
  loading = true;
  saving = false;
  loadError;
  saveError;
  today = isoToday();

  async connectedCallback() {
    try {
      this.options = parse(
        await getEntryOptions({ familyId: this.familyId }),
        this.options
      );
      this.applyDefaults();
    } catch (e) {
      this.loadError = errorMessage(e);
    } finally {
      this.loading = false;
    }
  }

  applyDefaults() {
    const first = this.entryAccounts[0]?.value;
    const second = this.transferAccounts.find((a) => a.value !== first)?.value;
    const admin = this.options.members.find((m) => m.role === "Family Admin");
    this.form = {
      ...this.form,
      accountId: this.form.accountId || first,
      fromAccountId: this.form.fromAccountId || first,
      toAccountId: this.form.toAccountId || second,
      memberId: this.form.memberId || admin?.id,
      paymentMode: this.options.paymentModes.includes(this.form.paymentMode)
        ? this.form.paymentMode
        : this.options.paymentModes[0]
    };
  }

  // ---------- view model ----------

  get types() {
    return TYPES.map((t) => ({
      ...t,
      selected: t.value === this.form.type ? "true" : "false",
      cls:
        t.value === this.form.type
          ? `segment segment_active segment_${t.value.toLowerCase()}`
          : "segment"
    }));
  }

  get isTransfer() {
    return this.form.type === "Transfer";
  }

  get showDetails() {
    return !this.isTransfer;
  }

  get payeeLabel() {
    return this.form.type === "Income" ? "From (payer)" : "Payee";
  }

  get currencySymbol() {
    return money(0, this.currencyCode).replace(/[\d.,\s]/g, "") || "₹";
  }

  get amountClass() {
    return `amount amount_${this.form.type.toLowerCase()}`;
  }

  get usableAccounts() {
    return (this.options.accounts || []).filter(
      (a) => a.status !== "Closed" && a.canUse !== false
    );
  }

  accountOption(a) {
    return {
      label: `${a.name} · ${money(a.balance, this.currencyCode)}`,
      value: a.id
    };
  }

  get entryAccounts() {
    return this.usableAccounts
      .filter((a) => a.type !== "Loan")
      .map((a) => this.accountOption(a));
  }

  get transferAccounts() {
    return this.usableAccounts.map((a) => this.accountOption(a));
  }

  get kindCategories() {
    const all = this.options.categories || [];
    const names = new Map(all.map((c) => [c.id, c.name]));
    return all
      .filter((c) => c.kind === this.form.type && c.active !== false)
      .map((c) => ({
        ...c,
        fullName:
          c.parentId && names.has(c.parentId)
            ? `${names.get(c.parentId)} › ${c.name}`
            : c.name
      }))
      .sort((a, b) => a.fullName.localeCompare(b.fullName));
  }

  get categoryOptions() {
    return this.kindCategories.map((c) => ({ label: c.fullName, value: c.id }));
  }

  /** Leaf categories in their configured order make the best one-tap shortcuts. */
  get quickCategories() {
    const all = this.kindCategories;
    const parents = new Set(all.map((c) => c.parentId).filter(Boolean));
    return all
      .filter((c) => !parents.has(c.id))
      .sort((a, b) => (a.sortOrder ?? 999) - (b.sortOrder ?? 999))
      .slice(0, QUICK_COUNT)
      .map((c) => ({
        value: c.id,
        label: c.name,
        cls:
          c.id === this.form.categoryId
            ? "quick-chip quick-chip_active"
            : "quick-chip"
      }));
  }

  get memberOptions() {
    return (this.options.members || []).map((m) => ({
      label: `${m.name} · ${m.role}`,
      value: m.id
    }));
  }

  get paymentModes() {
    return (this.options.paymentModes || []).map((m) => ({
      label: m,
      value: m
    }));
  }

  get saveDisabled() {
    return this.saving || this.loading || Boolean(this.loadError);
  }

  get saveLabel() {
    if (this.saving) {
      return "Saving…";
    }
    const amount = Number(this.form.amount);
    return amount > 0 ? `Save ${money(amount, this.currencyCode)}` : "Save";
  }

  // ---------- events ----------

  handleType(event) {
    const type = event.currentTarget.dataset.value;
    if (type !== this.form.type) {
      this.form = { ...this.form, type, categoryId: undefined };
      this.saveError = undefined;
    }
  }

  handleChange(event) {
    this.form = {
      ...this.form,
      [event.target.name]: event.detail?.value ?? event.target.value
    };
  }

  handleNativeInput(event) {
    this.form = {
      ...this.form,
      [event.target.dataset.field]: event.target.value
    };
  }

  handleQuickCategory(event) {
    this.form = { ...this.form, categoryId: event.currentTarget.dataset.value };
  }

  handleCancel() {
    this.close({ saved: false });
  }

  validate() {
    const inputs = [
      ...this.template.querySelectorAll("lightning-input, lightning-combobox")
    ];
    // Every field reports (so all errors show at once); only an explicit false fails.
    const fieldsOk = inputs.reduce(
      (ok, el) => el.reportValidity() !== false && ok,
      true
    );
    const amount = Number(this.form.amount);
    if (!(amount > 0)) {
      return "Enter an amount above zero.";
    }
    if (!fieldsOk) {
      return "Fill in the highlighted fields.";
    }
    if (this.isTransfer && this.form.fromAccountId === this.form.toAccountId) {
      return "Choose two different accounts.";
    }
    return null;
  }

  body() {
    const f = this.form;
    const amount = Number(f.amount);
    if (this.isTransfer) {
      return {
        type: "Transfer",
        amount,
        date: f.date,
        fromAccountId: f.fromAccountId,
        toAccountId: f.toAccountId,
        notes: f.notes || undefined
      };
    }
    return {
      type: f.type,
      amount,
      date: f.date,
      accountId: f.accountId,
      categoryId: f.categoryId,
      paymentMode: f.paymentMode || undefined,
      payee: f.payee || undefined,
      memberId: f.memberId || undefined,
      notes: f.notes || undefined
    };
  }

  async handleSave() {
    this.saveError = this.validate();
    if (this.saveError) {
      return;
    }
    this.saving = true;
    this.disableClose = true;
    try {
      await saveEntry({
        familyId: this.familyId,
        entryJson: JSON.stringify(this.body())
      });
      this.disableClose = false;
      this.close({
        saved: true,
        message: `${this.form.type} of ${money(this.form.amount, this.currencyCode)} recorded.`
      });
    } catch (e) {
      this.saveError = errorMessage(e);
    } finally {
      this.saving = false;
      this.disableClose = false;
    }
  }
}
