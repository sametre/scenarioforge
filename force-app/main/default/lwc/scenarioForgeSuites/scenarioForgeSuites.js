import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSuites from '@salesforce/apex/ScenarioForgeSuiteService.getSuites';
import getSuiteDetails from '@salesforce/apex/ScenarioForgeSuiteService.getSuiteDetails';
import saveSuite from '@salesforce/apex/ScenarioForgeSuiteService.saveSuite';
import addScenario from '@salesforce/apex/ScenarioForgeSuiteService.addScenario';
import removeScenario from '@salesforce/apex/ScenarioForgeSuiteService.removeScenario';
import startSuite from '@salesforce/apex/ScenarioForgeSuiteService.startSuite';
import getScenarios from '@salesforce/apex/ScenarioForgeService.getScenarios';

export default class ScenarioForgeSuites extends LightningElement {
    suites = [];
    scenarios = [];
    selectedSuiteId;
    details;
    wiredSuites;
    wiredDetails;
    busy = false;
    error;
    showSuiteModal = false;
    showMemberModal = false;
    suiteDraft = { name: '', description: '', status: 'Draft', tags: '' };
    selectedScenarioId;
    statusOptions = [
        { label: 'Draft', value: 'Draft' },
        { label: 'Active', value: 'Active' },
        { label: 'Archived', value: 'Archived' },
    ];

    @wire(getSuites) wiredSuiteList(value) {
        this.wiredSuites = value;
        if (value.data) {
            this.suites = value.data;
            this.error = undefined;
        } else if (value.error) this.error = this.message(value.error);
    }
    @wire(getScenarios) wiredScenarioList({ data }) {
        if (data) this.scenarios = data;
    }
    @wire(getSuiteDetails, { suiteId: '$selectedSuiteId' }) wiredSuiteDetail(value) {
        this.wiredDetails = value;
        if (value.data) this.details = value.data;
    }

    get hasSelection() {
        return !!this.selectedSuiteId;
    }
    get empty() {
        return this.suites.length === 0;
    }
    get hasMembers() {
        return (this.details?.members?.length || 0) > 0;
    }
    get hasSuiteRuns() {
        return (this.details?.recentRuns?.length || 0) > 0;
    }
    get scenarioOptions() {
        return this.scenarios
            .filter((s) => s.status !== 'Archived')
            .map((s) => ({ label: `${s.name} · ${s.stepCount} steps`, value: s.id }));
    }

    newSuite() {
        this.suiteDraft = { name: '', description: '', status: 'Draft', tags: '' };
        this.showSuiteModal = true;
    }
    closeSuiteModal() {
        this.showSuiteModal = false;
    }
    changeSuite(event) {
        this.suiteDraft = { ...this.suiteDraft, [event.target.name]: event.detail?.value ?? event.target.value };
    }
    async saveNewSuite() {
        this.busy = true;
        try {
            const id = await saveSuite({ suiteId: null, ...this.suiteDraft });
            this.showSuiteModal = false;
            await refreshApex(this.wiredSuites);
            this.selectedSuiteId = id;
            this.toast('Suite created', 'Add scenarios to build a regression pack.', 'success');
        } catch (e) {
            this.toast('Unable to create suite', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    openSuite(event) {
        this.selectedSuiteId = event.currentTarget.dataset.id;
    }
    back() {
        this.selectedSuiteId = undefined;
        this.details = undefined;
    }
    addMember() {
        this.selectedScenarioId = this.scenarioOptions[0]?.value;
        this.showMemberModal = true;
    }
    closeMemberModal() {
        this.showMemberModal = false;
    }
    changeScenario(event) {
        this.selectedScenarioId = event.detail.value;
    }
    async saveMember() {
        if (!this.selectedScenarioId) return;
        this.busy = true;
        try {
            await addScenario({ suiteId: this.selectedSuiteId, scenarioId: this.selectedScenarioId, sequence: null });
            this.showMemberModal = false;
            await refreshApex(this.wiredDetails);
            await refreshApex(this.wiredSuites);
            this.toast('Scenario added', 'Regression suite updated.', 'success');
        } catch (e) {
            this.toast('Unable to add scenario', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async removeMember(event) {
        this.busy = true;
        try {
            await removeScenario({ memberId: event.currentTarget.dataset.id });
            await refreshApex(this.wiredDetails);
            await refreshApex(this.wiredSuites);
        } catch (e) {
            this.toast('Unable to remove scenario', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async run() {
        this.busy = true;
        try {
            const id = await startSuite({ suiteId: this.selectedSuiteId });
            this.toast('Suite queued', 'Scenarios will execute in separate Queueable transactions.', 'success');
            this.dispatchEvent(new CustomEvent('opensuiterun', { detail: id }));
        } catch (e) {
            this.toast('Unable to start suite', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    openSuiteRun(event) {
        this.dispatchEvent(new CustomEvent('opensuiterun', { detail: event.currentTarget.dataset.id }));
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    message(e) {
        return e?.body?.message || e?.message || 'Unexpected error';
    }
}
