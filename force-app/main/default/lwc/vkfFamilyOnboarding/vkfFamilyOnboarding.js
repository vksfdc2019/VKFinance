import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import onboardFamily from '@salesforce/apex/VkfConsoleController.onboardFamily';
import resetPortalPassword from '@salesforce/apex/VkfConsoleController.resetPortalPassword';

const EMPTY_FORM = {
    familyName: '',
    currencyCode: 'INR',
    timeZone: 'Asia/Kolkata',
    maxMembers: 10,
    firstName: '',
    lastName: '',
    username: '',
    email: ''
};

export default class VkfFamilyOnboarding extends LightningElement {
    form = { ...EMPTY_FORM };
    result;
    resetUsername = '';
    resetResult;
    busy = false;

    handleChange(event) {
        const { name, value } = event.target;
        this.form = { ...this.form, [name]: value };
    }

    handleResetChange(event) {
        this.resetUsername = event.target.value;
    }

    async handleOnboard() {
        if (!this.validate('onboard')) {
            return;
        }
        this.busy = true;
        this.result = undefined;
        try {
            this.result = await onboardFamily({ ...this.form, maxMembers: Number(this.form.maxMembers) });
            this.form = { ...EMPTY_FORM };
            this.toast('Family created', `${this.result.familyName} (${this.result.familyCode}) is ready.`, 'success');
        } catch (error) {
            this.toast('Could not create the family', this.errorMessage(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleReset() {
        if (!this.validate('reset')) {
            return;
        }
        this.busy = true;
        this.resetResult = undefined;
        try {
            const password = await resetPortalPassword({ username: this.resetUsername });
            this.resetResult = { username: this.resetUsername.trim().toLowerCase(), password };
            this.toast('Temporary password issued', 'The member sets a new password at next sign-in.', 'success');
        } catch (error) {
            this.toast('Could not reset the password', this.errorMessage(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    validate(formName) {
        return [...this.template.querySelectorAll(`lightning-input[data-form="${formName}"]`)].reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
