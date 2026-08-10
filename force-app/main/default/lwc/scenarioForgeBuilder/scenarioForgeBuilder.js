import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getScenarioDetails from '@salesforce/apex/ScenarioForgeService.getScenarioDetails';
import saveStep from '@salesforce/apex/ScenarioForgeService.saveStep';
import deleteStep from '@salesforce/apex/ScenarioForgeService.deleteStep';
import runScenario from '@salesforce/apex/ScenarioForgeService.runScenario';
import validateScenario from '@salesforce/apex/ScenarioForgeService.validateScenario';
import exportScenario from '@salesforce/apex/ScenarioForgeService.exportScenario';
import getObjectCatalog from '@salesforce/apex/ScenarioForgeService.getObjectCatalog';
import getFieldCatalog from '@salesforce/apex/ScenarioForgeService.getFieldCatalog';

const ACTIONS = [
    { label: 'Create Record', value: 'CREATE_RECORD' },
    { label: 'Find Existing Record', value: 'FIND_RECORD' },
    { label: 'Update Record', value: 'UPDATE_RECORD' },
    { label: 'Delete Record', value: 'DELETE_RECORD' },
    { label: 'Assert Field Value', value: 'ASSERT_FIELD' },
    { label: 'Assert Record Exists', value: 'ASSERT_RECORD_EXISTS' },
    { label: 'Assert Record Does Not Exist', value: 'ASSERT_RECORD_NOT_EXISTS' },
    { label: 'Assert Record Count', value: 'ASSERT_RECORD_COUNT' },
];

const OPERATORS = [
    { label: 'Equals', value: 'EQUALS' },
    { label: 'Not equals', value: 'NOT_EQUALS' },
    { label: 'Contains', value: 'CONTAINS' },
    { label: 'Does not contain', value: 'NOT_CONTAINS' },
    { label: 'Starts with', value: 'STARTS_WITH' },
    { label: 'Ends with', value: 'ENDS_WITH' },
    { label: 'Greater than', value: 'GREATER_THAN' },
    { label: 'Greater or equal', value: 'GREATER_OR_EQUAL' },
    { label: 'Less than', value: 'LESS_THAN' },
    { label: 'Less or equal', value: 'LESS_OR_EQUAL' },
    { label: 'Is null', value: 'IS_NULL' },
    { label: 'Is not null', value: 'NOT_NULL' },
];

export default class ScenarioForgeBuilder extends LightningElement {
    @api scenarioId;
    details;
    wiredValue;
    showModal = false;
    showExport = false;
    exportText = '';
    busy = false;
    editingId;
    preflight;
    advancedJson = false;
    objectCatalog = [];
    objectOptions = [];
    fieldCatalog = [];
    fieldOptions = [];
    rowCounter = 0;
    pairs = [];
    form = { alias: '', field: '', operator: 'EQUALS', expected: '' };
    draft = this.freshDraft(1);
    actionOptions = ACTIONS;
    operatorOptions = OPERATORS;

    connectedCallback() {
        this.loadObjects();
    }

    @wire(getScenarioDetails, { scenarioId: '$scenarioId' })
    wiredDetails(value) {
        this.wiredValue = value;
        if (value.data) this.details = value.data;
    }

    get hasSteps() {
        return (this.details?.steps?.length || 0) > 0;
    }
    get preflightClass() {
        return `preflight ${this.preflight?.valid ? 'valid' : 'invalid'}`;
    }
    get hasIssues() {
        return (this.preflight?.issues?.length || 0) > 0;
    }
    get modeLabel() {
        return this.advancedJson ? 'Use Guided Builder' : 'Advanced JSON';
    }
    get isCreate() {
        return this.draft.action === 'CREATE_RECORD';
    }
    get isFind() {
        return this.draft.action === 'FIND_RECORD';
    }
    get isUpdate() {
        return this.draft.action === 'UPDATE_RECORD';
    }
    get isDelete() {
        return this.draft.action === 'DELETE_RECORD';
    }
    get isAssertField() {
        return this.draft.action === 'ASSERT_FIELD';
    }
    get isExists() {
        return this.draft.action === 'ASSERT_RECORD_EXISTS' || this.draft.action === 'ASSERT_RECORD_NOT_EXISTS';
    }
    get isCount() {
        return this.draft.action === 'ASSERT_RECORD_COUNT';
    }
    get isCreateOrFind() {
        return this.isCreate || this.isFind;
    }
    get usesPairs() {
        return this.isCreate || this.isFind || this.isUpdate || this.isExists || this.isCount;
    }
    get usesExistingAlias() {
        return this.isUpdate || this.isDelete || this.isAssertField;
    }
    get pairTitle() {
        return this.isCreate || this.isUpdate ? 'Fields to write' : 'Match filters';
    }
    get pairHelp() {
        return this.isCreate || this.isUpdate
            ? 'Choose fields and values. Salesforce field types are coerced at runtime.'
            : 'All filters are combined with AND. Use a unique filter for Find Record.';
    }
    get pairKeyLabel() {
        return this.isCreate || this.isUpdate ? 'Field' : 'Filter field';
    }
    get expectedDisabled() {
        return this.form.operator === 'IS_NULL' || this.form.operator === 'NOT_NULL';
    }

    freshDraft(sequence) {
        return {
            sequence,
            action: 'CREATE_RECORD',
            targetObject: 'Account',
            recordAlias: `record${sequence}`,
            configuration: '{\n  "fields": {\n    "Name": "ScenarioForge Test"\n  }\n}',
            enabled: true,
            stopOnFailure: true,
        };
    }

    async loadObjects() {
        try {
            const rows = await getObjectCatalog();
            this.objectCatalog = [...rows].sort((a, b) => a.label.localeCompare(b.label));
            this.refreshObjectOptions();
        } catch (error) {
            this.toast('Object catalog unavailable', this.message(error), 'warning');
        }
    }

    refreshObjectOptions() {
        let rows = this.objectCatalog;
        if (this.draft.action === 'CREATE_RECORD') rows = rows.filter((row) => row.createable);
        else if (this.draft.action === 'UPDATE_RECORD') rows = rows.filter((row) => row.updateable);
        else if (this.draft.action === 'DELETE_RECORD') rows = rows.filter((row) => row.deletable);
        else rows = rows.filter((row) => row.queryable);
        this.objectOptions = rows.map((row) => ({ label: `${row.label} (${row.apiName})`, value: row.apiName }));
    }

    refreshFieldOptions() {
        let rows = this.fieldCatalog;
        if (this.draft.action === 'CREATE_RECORD') rows = rows.filter((row) => row.createable);
        else if (this.draft.action === 'UPDATE_RECORD') rows = rows.filter((row) => row.updateable);
        else rows = rows.filter((row) => row.accessible);
        this.fieldOptions = rows.map((row) => ({ label: `${row.label} (${row.apiName})`, value: row.apiName }));
    }

    async loadFields(objectApiName) {
        this.fieldOptions = [];
        if (!objectApiName) return;
        try {
            const rows = await getFieldCatalog({ objectApiName });
            this.fieldCatalog = [...rows].sort((a, b) => a.label.localeCompare(b.label));
            this.refreshFieldOptions();
        } catch (error) {
            this.toast('Field catalog unavailable', this.message(error), 'warning');
        }
    }

    back() {
        this.dispatchEvent(new CustomEvent('back'));
    }

    async addStep() {
        const next = (this.details?.steps?.length || 0) + 1;
        this.editingId = undefined;
        this.draft = this.freshDraft(next);
        this.advancedJson = false;
        this.form = { alias: '', field: '', operator: 'EQUALS', expected: '' };
        this.pairs = [this.newPair('Name', 'ScenarioForge Test')];
        await this.loadFields(this.draft.targetObject);
        this.showModal = true;
    }

    async edit(event) {
        const step = this.details.steps.find((item) => item.id === event.currentTarget.dataset.id);
        this.editingId = step.id;
        this.draft = {
            sequence: step.sequence,
            action: step.action,
            targetObject: step.targetObject,
            recordAlias: step.recordAlias,
            configuration: step.configuration,
            enabled: step.enabled,
            stopOnFailure: step.stopOnFailure,
        };
        await this.loadFields(step.targetObject);
        this.advancedJson = false;
        try {
            this.hydrateGuided(JSON.parse(step.configuration || '{}'));
        } catch (error) {
            this.advancedJson = true;
        }
        this.showModal = true;
    }

    close() {
        this.showModal = false;
    }
    closeExport() {
        this.showExport = false;
    }
    toggleMode() {
        if (!this.advancedJson) {
            try {
                this.draft = { ...this.draft, configuration: JSON.stringify(this.compileGuided(), null, 2) };
            } catch (error) {
                this.toast('Complete the guided fields first', error.message, 'warning');
                return;
            }
        } else {
            try {
                this.hydrateGuided(JSON.parse(this.draft.configuration || '{}'));
            } catch (error) {
                this.toast(
                    'JSON cannot be converted',
                    'Fix the JSON before switching back to Guided Builder.',
                    'error',
                );
                return;
            }
        }
        this.advancedJson = !this.advancedJson;
    }

    async change(event) {
        const name = event.target.name;
        const value =
            event.target.type === 'checkbox' ? event.target.checked : (event.detail?.value ?? event.target.value);
        this.draft = { ...this.draft, [name]: value };
        if (name === 'action') {
            this.resetGuidedForAction(value);
            this.refreshObjectOptions();
            this.refreshFieldOptions();
        }
        if (name === 'targetObject') await this.loadFields(value);
    }

    changeForm(event) {
        const value = event.detail?.value ?? event.target.value;
        this.form = { ...this.form, [event.target.name]: value };
    }

    addPair() {
        this.pairs = [...this.pairs, this.newPair('', '')];
    }
    removePair(event) {
        const id = Number(event.currentTarget.dataset.row);
        this.pairs = this.pairs.filter((row) => row.id !== id);
        if (this.pairs.length === 0) this.pairs = [this.newPair('', '')];
    }
    pairFieldChanged(event) {
        const id = Number(event.currentTarget.dataset.row);
        this.pairs = this.pairs.map((row) => (row.id === id ? { ...row, field: event.detail.value } : row));
    }
    pairValueChanged(event) {
        const id = Number(event.currentTarget.dataset.row);
        this.pairs = this.pairs.map((row) => (row.id === id ? { ...row, value: event.target.value } : row));
    }

    newPair(field, value) {
        return { id: ++this.rowCounter, field: field || '', value: value == null ? '' : String(value) };
    }

    resetGuidedForAction(action) {
        this.form = { alias: '', field: '', operator: 'EQUALS', expected: '' };
        if (action === 'CREATE_RECORD') {
            this.draft = { ...this.draft, recordAlias: this.draft.recordAlias || `record${this.draft.sequence}` };
            this.pairs = [this.newPair('Name', 'ScenarioForge Test')];
        } else {
            this.pairs = [this.newPair('', '')];
        }
    }

    hydrateGuided(config) {
        this.form = {
            alias: config.recordAlias || '',
            field: config.field || '',
            operator: config.operator || 'EQUALS',
            expected: config.expected == null ? '' : String(config.expected),
        };
        const source = config.fields || config.where || {};
        this.pairs = Object.entries(source).map(([field, value]) => this.newPair(field, value));
        if (this.pairs.length === 0) this.pairs = [this.newPair('', '')];
    }

    pairsObject() {
        const output = {};
        for (const row of this.pairs) {
            if (!row.field) continue;
            output[row.field] = row.value;
        }
        return output;
    }

    compileGuided() {
        const action = this.draft.action;
        const pairs = this.pairsObject();
        if (this.usesPairs && Object.keys(pairs).length === 0) throw new Error('Add at least one field or filter.');
        if (action === 'CREATE_RECORD') return { fields: pairs };
        if (action === 'FIND_RECORD') return { where: pairs };
        if (action === 'UPDATE_RECORD') {
            if (!this.form.alias) throw new Error('Enter the record alias created by an earlier step.');
            return { recordAlias: this.form.alias, fields: pairs };
        }
        if (action === 'DELETE_RECORD') {
            if (!this.form.alias) throw new Error('Enter the record alias created by an earlier step.');
            return { recordAlias: this.form.alias };
        }
        if (action === 'ASSERT_FIELD') {
            if (!this.form.alias || !this.form.field) throw new Error('Choose the record alias and field to assert.');
            const config = {
                recordAlias: this.form.alias,
                field: this.form.field,
                operator: this.form.operator || 'EQUALS',
            };
            if (!this.expectedDisabled) config.expected = this.form.expected;
            return config;
        }
        if (action === 'ASSERT_RECORD_EXISTS' || action === 'ASSERT_RECORD_NOT_EXISTS') return { where: pairs };
        if (action === 'ASSERT_RECORD_COUNT') {
            if (this.form.expected === '') throw new Error('Enter the expected record count.');
            return { where: pairs, operator: this.form.operator || 'EQUALS', expected: this.form.expected };
        }
        return {};
    }

    async save() {
        this.busy = true;
        try {
            let configuration = this.draft.configuration;
            if (this.advancedJson) JSON.parse(configuration || '{}');
            else configuration = JSON.stringify(this.compileGuided(), null, 2);
            const recordAlias = this.isCreateOrFind
                ? this.draft.recordAlias
                : this.usesExistingAlias
                  ? this.form.alias
                  : this.draft.recordAlias;
            await saveStep({
                stepId: this.editingId,
                scenarioId: this.scenarioId,
                ...this.draft,
                recordAlias,
                configuration,
            });
            this.showModal = false;
            this.preflight = undefined;
            await refreshApex(this.wiredValue);
            this.toast('Step saved', 'Scenario definition updated.', 'success');
        } catch (error) {
            this.toast('Unable to save step', error?.message || this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async remove(event) {
        this.busy = true;
        try {
            await deleteStep({ stepId: event.currentTarget.dataset.id });
            this.preflight = undefined;
            await refreshApex(this.wiredValue);
        } catch (error) {
            this.toast('Unable to delete step', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async validate() {
        this.busy = true;
        try {
            this.preflight = await validateScenario({ scenarioId: this.scenarioId });
            this.toast(
                this.preflight.valid ? 'Preflight passed' : 'Preflight found issues',
                this.preflight.valid
                    ? 'Scenario is ready to execute.'
                    : `${this.preflight.errorCount} errors and ${this.preflight.warningCount} warnings.`,
                this.preflight.valid ? 'success' : 'warning',
            );
        } catch (error) {
            this.toast('Preflight failed', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async run() {
        this.busy = true;
        try {
            const runId = await runScenario({ scenarioId: this.scenarioId });
            this.dispatchEvent(new CustomEvent('openrun', { detail: runId }));
        } catch (error) {
            this.toast('Execution blocked', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async exportDefinition() {
        this.busy = true;
        try {
            this.exportText = await exportScenario({ scenarioId: this.scenarioId });
            this.showExport = true;
        } catch (error) {
            this.toast('Export failed', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async copyExport() {
        try {
            await navigator.clipboard.writeText(this.exportText);
            this.toast('Copied', 'Scenario JSON copied to clipboard.', 'success');
        } catch (error) {
            this.toast('Copy unavailable', 'Select the JSON and copy it manually.', 'info');
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
    message(error) {
        return error?.body?.message || error?.message || 'Unexpected error';
    }
}
