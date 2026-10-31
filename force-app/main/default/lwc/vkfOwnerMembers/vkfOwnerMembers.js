import { LightningElement, api } from "lwc";
import getMembers from "@salesforce/apex/VkfOwnerController.getMembers";
import { colorFor, errorMessage, initials, parse } from "c/vkfOwnerLib";

const ROLE_ORDER = ["Family Admin", "Co-Admin", "Member", "Child", "Viewer"];

/** Read-only member directory with sign-in health at a glance. */
export default class VkfOwnerMembers extends LightningElement {
  rows = [];
  loading = true;
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
      const result = parse(await getMembers({ familyId: this._familyId }), []);
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

  get members() {
    return [...this.rows]
      .sort((a, b) => ROLE_ORDER.indexOf(a.role) - ROLE_ORDER.indexOf(b.role))
      .map((m) => {
        const name =
          `${m.firstName || ""} ${m.lastName || ""}`.trim() || m.username;
        const facts = [
          {
            label: m.status,
            cls: `chip ${m.status === "Active" ? "chip_good" : "chip_warn"}`
          }
        ];
        if (m.locked) {
          facts.push({ label: "Locked", cls: "chip chip_bad" });
        }
        facts.push(
          m.mfaEnabled
            ? { label: "Two-step on", cls: "chip chip_good" }
            : { label: "Two-step off", cls: "chip" }
        );
        if (m.mustChangePassword) {
          facts.push({ label: "Must set password", cls: "chip chip_warn" });
        }
        if (m.activeSessions) {
          facts.push({
            label: `${m.activeSessions} active session${m.activeSessions === 1 ? "" : "s"}`,
            cls: "chip"
          });
        }
        return {
          id: m.id,
          name,
          subtitle: m.relationship || "",
          role: m.role,
          roleClass:
            m.role === "Family Admin" || m.role === "Co-Admin"
              ? "role role_admin"
              : "role",
          username: m.username,
          email: m.email,
          mobile: m.mobile,
          lastLogin: m.lastLogin
            ? new Date(m.lastLogin).toLocaleString("en-IN", {
                dateStyle: "medium",
                timeStyle: "short"
              })
            : "Never",
          facts,
          initials: initials(name),
          avatar: `background: linear-gradient(135deg, ${colorFor(name)}, #0f172a 180%)`,
          cardClass:
            m.status === "Active"
              ? "card member"
              : "card member member_inactive"
        };
      });
  }
}
