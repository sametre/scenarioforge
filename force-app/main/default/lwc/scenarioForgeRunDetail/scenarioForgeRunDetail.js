import { LightningElement, api, wire } from 'lwc';
import getRunDetails from '@salesforce/apex/ScenarioForgeService.getRunDetails';
export default class ScenarioForgeRunDetail extends LightningElement {
    @api runId;
    details;
    error;
    @wire(getRunDetails, { runId: '$runId' }) wired({ data, error }) {
        if (data) {
            this.details = data;
            this.error = undefined;
        } else if (error) this.error = error?.body?.message || error.message;
    }
    get statusClass() {
        return `status ${String(this.details?.run?.status || '').toLowerCase()}`;
    }
    back() {
        this.dispatchEvent(new CustomEvent('back'));
    }
}
