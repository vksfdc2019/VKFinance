/**
 * Jest stub for lightning/modal (sfdx-lwc-jest ships none). Tests mock open() on the
 * component's own class; close() emits 'close' so a test can read the result.
 */
import { LightningElement, api } from "lwc";

export default class LightningModal extends LightningElement {
  @api label;
  @api size;
  @api description;
  @api disableClose;

  static open() {
    return Promise.resolve();
  }

  close(result) {
    this.dispatchEvent(new CustomEvent("close", { detail: result }));
  }
}
