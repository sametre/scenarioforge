import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getSuiteRunDetails from '@salesforce/apex/ScenarioForgeSuiteService.getSuiteRunDetails';
export default class ScenarioForgeSuiteRunDetail extends LightningElement {
    @api suiteRunId;
    details;
    wiredValue;
    error;
    timer;
    @wire(getSuiteRunDetails, { suiteRunId: '$suiteRunId' }) wired(value) {
        this.wiredValue = value;
        if (value.data) {
            this.details = value.data;
            this.error = undefined;
            this.managePolling();
        } else if (value.error) this.error = value.error?.body?.message || value.error.message;
    }
    disconnectedCallback() {
        this.stopPolling();
    }
    get running() {
        return this.details?.run?.status === 'RUNNING';
    }
    get statusClass() {
        return `status ${String(this.details?.run?.status || '').toLowerCase()}`;
    }
    managePolling() {
        if (this.running && !this.timer) this.timer = setInterval(() => refreshApex(this.wiredValue), 2000);
        else if (!this.running) this.stopPolling();
    }
    stopPolling() {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = undefined;
        }
    }
    back() {
        this.dispatchEvent(new CustomEvent('back'));
    }
    refresh() {
        refreshApex(this.wiredValue);
    }
    openRun(event) {
        const id = event.currentTarget.dataset.id;
        if (id) this.dispatchEvent(new CustomEvent('openrun', { detail: id }));
    }
}
