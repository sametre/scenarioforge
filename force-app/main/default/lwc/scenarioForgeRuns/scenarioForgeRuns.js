import { LightningElement, wire } from 'lwc';
import getRecentRuns from '@salesforce/apex/ScenarioForgeService.getRecentRuns';
export default class ScenarioForgeRuns extends LightningElement {
    runs = [];
    error;
    @wire(getRecentRuns, { limitSize: 100 }) wired({ data, error }) {
        if (data) {
            this.runs = data;
            this.error = undefined;
        } else if (error) this.error = error?.body?.message;
    }
    get empty() {
        return this.runs.length === 0;
    }
    open(event) {
        this.dispatchEvent(new CustomEvent('openrun', { detail: event.currentTarget.dataset.id }));
    }
}
