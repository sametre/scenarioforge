import { LightningElement, wire } from 'lwc';
import getDashboard from '@salesforce/apex/ScenarioForgeService.getDashboard';
export default class ScenarioForgeDashboard extends LightningElement {
    dashboard;
    error;
    @wire(getDashboard) wired({ data, error }) {
        if (data) {
            this.dashboard = data;
            this.error = undefined;
        } else if (error) {
            this.error = error?.body?.message || error.message;
        }
    }
    get passRate() {
        return `${this.dashboard?.passRate || 0}%`;
    }
    get hasRuns() {
        return (this.dashboard?.recentRuns?.length || 0) > 0;
    }
    openRun(event) {
        this.dispatchEvent(new CustomEvent('openrun', { detail: event.currentTarget.dataset.id }));
    }
}
