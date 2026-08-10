import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSetupState from '@salesforce/apex/ScenarioForgeOnboardingService.getSetupState';
import installStarterPack from '@salesforce/apex/ScenarioForgeOnboardingService.installStarterPack';

export default class ScenarioForgeOnboarding extends LightningElement {
    state;
    wiredState;
    busy = false;
    error;

    @wire(getSetupState)
    wiredSetup(value) {
        this.wiredState = value;
        if (value.data) {
            this.state = value.data;
            this.error = undefined;
        } else if (value.error) {
            this.error = this.message(value.error);
        }
    }

    get starterStatus() {
        return this.state?.starterInstalled ? 'Installed' : 'Not installed';
    }

    get starterClass() {
        return this.state?.starterInstalled ? 'status good' : 'status pending';
    }

    get authorClass() {
        return this.state?.canAuthor ? 'check good' : 'check warning';
    }

    get accountClass() {
        return this.state?.accountReady ? 'check good' : 'check warning';
    }

    get contactClass() {
        return this.state?.contactReady ? 'check good' : 'check neutral';
    }

    get installDisabled() {
        return this.busy || !this.state?.canAuthor || !this.state?.accountReady || this.state?.starterInstalled;
    }

    async install() {
        this.busy = true;
        try {
            const result = await installStarterPack();
            await refreshApex(this.wiredState);
            this.toast(
                result.created ? 'Starter pack installed' : 'Starter pack already installed',
                result.message,
                result.created ? 'success' : 'info',
            );
            if (result.firstScenarioId) {
                this.dispatchEvent(new CustomEvent('openstarter', { detail: result.firstScenarioId }));
            }
        } catch (error) {
            this.toast('Setup could not finish', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    continueToWorkspace() {
        this.dispatchEvent(new CustomEvent('setupcomplete'));
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    message(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
