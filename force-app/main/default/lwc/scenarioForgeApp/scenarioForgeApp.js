import { LightningElement, wire } from 'lwc';
import SCENARIO_FORGE_ASSETS from '@salesforce/resourceUrl/scenarioForgeAssets';
import getSetupState from '@salesforce/apex/ScenarioForgeOnboardingService.getSetupState';

export default class ScenarioForgeApp extends LightningElement {
    view = 'dashboard';
    selectedScenarioId;
    selectedRunId;
    selectedSuiteRunId;
    logoUrl = `${SCENARIO_FORGE_ASSETS}/logo.svg`;
    initialized = false;
    setupState;

    @wire(getSetupState)
    wiredSetup({ data }) {
        if (!data) return;
        this.setupState = data;
        if (!this.initialized) {
            this.view = data.scenarioCount === 0 ? 'setup' : 'dashboard';
            this.initialized = true;
        }
    }

    get isSetup() {
        return this.view === 'setup';
    }
    get isDashboard() {
        return this.view === 'dashboard';
    }
    get isScenarios() {
        return this.view === 'scenarios';
    }
    get isBuilder() {
        return this.view === 'builder';
    }
    get isSuites() {
        return this.view === 'suites';
    }
    get isRuns() {
        return this.view === 'runs';
    }
    get isRunDetail() {
        return this.view === 'runDetail';
    }
    get isSuiteRunDetail() {
        return this.view === 'suiteRunDetail';
    }

    get setupClass() {
        return this.navClass('setup');
    }
    get dashboardClass() {
        return this.navClass('dashboard');
    }
    get scenariosClass() {
        return this.navClass('scenarios');
    }
    get suitesClass() {
        return this.navClass('suites');
    }
    get runsClass() {
        return this.navClass('runs');
    }
    navClass(name) {
        return `nav-item ${this.view === name ? 'active' : ''}`;
    }

    navigate(event) {
        this.view = event.currentTarget.dataset.view;
        this.selectedScenarioId = undefined;
        this.selectedRunId = undefined;
        this.selectedSuiteRunId = undefined;
    }
    openScenario(event) {
        this.selectedScenarioId = event.detail;
        this.view = 'builder';
    }
    openStarter(event) {
        this.selectedScenarioId = event.detail;
        this.view = 'builder';
    }
    setupComplete() {
        this.view = 'dashboard';
    }
    openRun(event) {
        this.selectedRunId = event.detail;
        this.view = 'runDetail';
    }
    openSuiteRun(event) {
        this.selectedSuiteRunId = event.detail;
        this.view = 'suiteRunDetail';
    }
    backToScenarios() {
        this.view = 'scenarios';
    }
    backToRuns() {
        this.view = 'runs';
    }
    backToSuites() {
        this.view = 'suites';
    }
}
