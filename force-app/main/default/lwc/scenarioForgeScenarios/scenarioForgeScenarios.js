import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScenarios from '@salesforce/apex/ScenarioForgeService.getScenarios';
import saveScenario from '@salesforce/apex/ScenarioForgeService.saveScenario';
import runScenario from '@salesforce/apex/ScenarioForgeService.runScenario';
import duplicateScenario from '@salesforce/apex/ScenarioForgeService.duplicateScenario';
import importScenario from '@salesforce/apex/ScenarioForgeService.importScenario';

export default class ScenarioForgeScenarios extends LightningElement {
    scenarios = [];
    wiredValue;
    showModal = false;
    showImport = false;
    showTemplates = false;
    busy = false;
    error;
    importText = '';
    draft = { name: '', description: '', status: 'Draft', category: '', tags: '' };
    statusOptions = [
        { label: 'Draft', value: 'Draft' },
        { label: 'Active', value: 'Active' },
        { label: 'Archived', value: 'Archived' },
    ];
    templates = [
        {
            key: 'smoke',
            name: 'Account Smoke Test',
            description: 'Create a record, assert a field, then roll everything back.',
            icon: 'utility:check',
        },
        {
            key: 'lifecycle',
            name: 'Record Lifecycle',
            description: 'Create, update, validate, delete, and verify record absence.',
            icon: 'utility:loop',
        },
        {
            key: 'relationship',
            name: 'Parent / Child Relationship',
            description: 'Create an Account and related Contact, then verify the relationship.',
            icon: 'utility:merge_field',
        },
    ];
    templateSources = {
        smoke: JSON.stringify({
            schemaVersion: '3.0',
            product: 'ScenarioForge',
            scenario: {
                name: 'Account Smoke Test',
                description: 'Create an Account and verify its Name field.',
                category: 'Smoke',
                tags: 'template, smoke',
            },
            steps: [
                {
                    sequence: 1,
                    action: 'CREATE_RECORD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: { fields: { Name: 'ScenarioForge Smoke Account' } },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 2,
                    action: 'ASSERT_FIELD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: {
                        recordAlias: 'account',
                        field: 'Name',
                        operator: 'EQUALS',
                        expected: 'ScenarioForge Smoke Account',
                    },
                    enabled: true,
                    stopOnFailure: true,
                },
            ],
        }),
        lifecycle: JSON.stringify({
            schemaVersion: '3.0',
            product: 'ScenarioForge',
            scenario: {
                name: 'Account Lifecycle Regression',
                description: 'Create, update, validate, delete, and verify an Account lifecycle.',
                category: 'Regression',
                tags: 'template, lifecycle',
            },
            steps: [
                {
                    sequence: 1,
                    action: 'CREATE_RECORD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: { fields: { Name: 'ScenarioForge Lifecycle Account' } },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 2,
                    action: 'UPDATE_RECORD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: { recordAlias: 'account', fields: { Industry: 'Technology' } },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 3,
                    action: 'ASSERT_FIELD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: {
                        recordAlias: 'account',
                        field: 'Industry',
                        operator: 'EQUALS',
                        expected: 'Technology',
                    },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 4,
                    action: 'DELETE_RECORD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: { recordAlias: 'account' },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 5,
                    action: 'ASSERT_RECORD_NOT_EXISTS',
                    targetObject: 'Account',
                    configuration: { where: { Id: '${account}' } },
                    enabled: true,
                    stopOnFailure: true,
                },
            ],
        }),
        relationship: JSON.stringify({
            schemaVersion: '3.0',
            product: 'ScenarioForge',
            scenario: {
                name: 'Account Contact Relationship',
                description: 'Create a parent Account and child Contact and verify the lookup.',
                category: 'Relationship',
                tags: 'template, relationship',
            },
            steps: [
                {
                    sequence: 1,
                    action: 'CREATE_RECORD',
                    targetObject: 'Account',
                    recordAlias: 'account',
                    configuration: { fields: { Name: 'ScenarioForge Parent Account' } },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 2,
                    action: 'CREATE_RECORD',
                    targetObject: 'Contact',
                    recordAlias: 'contact',
                    configuration: { fields: { LastName: 'ScenarioForge Contact', AccountId: '${account}' } },
                    enabled: true,
                    stopOnFailure: true,
                },
                {
                    sequence: 3,
                    action: 'ASSERT_RECORD_COUNT',
                    targetObject: 'Contact',
                    configuration: { where: { AccountId: '${account}' }, operator: 'EQUALS', expected: 1 },
                    enabled: true,
                    stopOnFailure: true,
                },
            ],
        }),
    };

    @wire(getScenarios) wiredScenarios(value) {
        this.wiredValue = value;
        if (value.data) {
            this.scenarios = value.data;
            this.error = undefined;
        } else if (value.error) {
            this.error = this.message(value.error);
        }
    }
    get empty() {
        return this.scenarios.length === 0;
    }
    newScenario() {
        this.draft = { name: '', description: '', status: 'Draft', category: '', tags: '' };
        this.showModal = true;
    }
    closeModal() {
        this.showModal = false;
    }
    openImport() {
        this.importText = '';
        this.showImport = true;
    }
    closeImport() {
        this.showImport = false;
    }
    openTemplates() {
        this.showTemplates = true;
    }
    closeTemplates() {
        this.showTemplates = false;
    }
    change(event) {
        this.draft = { ...this.draft, [event.target.name]: event.detail?.value ?? event.target.value };
    }
    changeImport(event) {
        this.importText = event.target.value;
    }
    open(event) {
        this.dispatchEvent(new CustomEvent('openscenario', { detail: event.currentTarget.dataset.id }));
    }
    async save() {
        this.busy = true;
        try {
            const id = await saveScenario({ scenarioId: null, ...this.draft });
            this.showModal = false;
            await refreshApex(this.wiredValue);
            this.dispatchEvent(new CustomEvent('openscenario', { detail: id }));
        } catch (e) {
            this.toast('Unable to create scenario', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async run(event) {
        event.stopPropagation();
        this.busy = true;
        try {
            const runId = await runScenario({ scenarioId: event.currentTarget.dataset.id });
            this.dispatchEvent(new CustomEvent('openrun', { detail: runId }));
        } catch (e) {
            this.toast('Execution blocked', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async duplicate(event) {
        event.stopPropagation();
        this.busy = true;
        try {
            const id = await duplicateScenario({ scenarioId: event.currentTarget.dataset.id });
            await refreshApex(this.wiredValue);
            this.toast('Scenario duplicated', 'A Draft copy was created.', 'success');
            this.dispatchEvent(new CustomEvent('openscenario', { detail: id }));
        } catch (e) {
            this.toast('Duplicate failed', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async createFromTemplate(event) {
        this.busy = true;
        try {
            const source = this.templateSources[event.currentTarget.dataset.key];
            const id = await importScenario({ source });
            this.showTemplates = false;
            await refreshApex(this.wiredValue);
            this.toast(
                'Template created',
                'The template was added as Draft. Run Preflight before activating it.',
                'success',
            );
            this.dispatchEvent(new CustomEvent('openscenario', { detail: id }));
        } catch (e) {
            this.toast('Template failed', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    async importDefinition() {
        this.busy = true;
        try {
            const id = await importScenario({ source: this.importText });
            this.showImport = false;
            await refreshApex(this.wiredValue);
            this.toast('Scenario imported', 'Imported definitions are always created as Draft.', 'success');
            this.dispatchEvent(new CustomEvent('openscenario', { detail: id }));
        } catch (e) {
            this.toast('Import failed', this.message(e), 'error');
        } finally {
            this.busy = false;
        }
    }
    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    message(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
