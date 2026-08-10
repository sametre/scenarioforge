public with sharing class ScenarioForgeService {
    public class ScenarioSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String category;
        @AuraEnabled
        public String tags;
        @AuraEnabled
        public Datetime lastRunAt;
        @AuraEnabled
        public String lastRunStatus;
        @AuraEnabled
        public Integer stepCount;
    }
    public class StepDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal sequence;
        @AuraEnabled
        public String action;
        @AuraEnabled
        public String targetObject;
        @AuraEnabled
        public String recordAlias;
        @AuraEnabled
        public String configuration;
        @AuraEnabled
        public Boolean enabled;
        @AuraEnabled
        public Boolean stopOnFailure;
    }
    public class ScenarioDetails {
        @AuraEnabled
        public ScenarioSummary scenario;
        @AuraEnabled
        public List<StepDTO> steps;
    }
    public class RunSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id scenarioId;
        @AuraEnabled
        public String scenarioName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Datetime completedAt;
        @AuraEnabled
        public Decimal durationMs;
        @AuraEnabled
        public Decimal totalSteps;
        @AuraEnabled
        public Decimal executedSteps;
        @AuraEnabled
        public Decimal passedSteps;
        @AuraEnabled
        public Decimal failedSteps;
        @AuraEnabled
        public Decimal cpuMs;
        @AuraEnabled
        public Decimal soqlQueries;
        @AuraEnabled
        public Decimal dmlStatements;
        @AuraEnabled
        public String engineVersion;
        @AuraEnabled
        public String isolationMode;
        @AuraEnabled
        public String summary;
    }
    public class ResultDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Decimal sequence;
        @AuraEnabled
        public String action;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public String expected;
        @AuraEnabled
        public String actual;
        @AuraEnabled
        public Decimal durationMs;
    }
    public class RunDetails {
        @AuraEnabled
        public RunSummary run;
        @AuraEnabled
        public List<ResultDTO> results;
    }
    public class DashboardDTO {
        @AuraEnabled
        public Integer activeScenarios;
        @AuraEnabled
        public Integer activeSuites;
        @AuraEnabled
        public Integer totalRuns;
        @AuraEnabled
        public Integer passedRuns;
        @AuraEnabled
        public Integer failedRuns;
        @AuraEnabled
        public Decimal passRate;
        @AuraEnabled
        public List<RunSummary> recentRuns;
    }
    public class ObjectOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean custom;
        @AuraEnabled
        public Boolean createable;
        @AuraEnabled
        public Boolean updateable;
        @AuraEnabled
        public Boolean deletable;
        @AuraEnabled
        public Boolean queryable;
    }
    public class FieldOption {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public Boolean createable;
        @AuraEnabled
        public Boolean updateable;
        @AuraEnabled
        public Boolean accessible;
        @AuraEnabled
        public Boolean requiredOnCreate;
    }

    @AuraEnabled(cacheable=true)
    public static List<ScenarioSummary> getScenarios() {
        List<ScenarioSummary> output = new List<ScenarioSummary>();
        for (Scenario__c row : [
            SELECT
                Id,
                Name,
                Description__c,
                Status__c,
                Category__c,
                Tags__c,
                Last_Run_At__c,
                Last_Run_Status__c,
                (SELECT Id FROM Steps__r WHERE Enabled__c = TRUE)
            FROM Scenario__c
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            ScenarioSummary dto = mapScenario(row);
            dto.stepCount = row.Steps__r == null ? 0 : row.Steps__r.size();
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static ScenarioDetails getScenarioDetails(Id scenarioId) {
        requireId(scenarioId, 'Scenario');
        Scenario__c row = [
            SELECT Id, Name, Description__c, Status__c, Category__c, Tags__c, Last_Run_At__c, Last_Run_Status__c
            FROM Scenario__c
            WHERE Id = :scenarioId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Scenario_Step__c> steps = [
            SELECT
                Id,
                Name,
                Sequence__c,
                Action__c,
                Target_Object__c,
                Record_Alias__c,
                Configuration__c,
                Enabled__c,
                Stop_On_Failure__c
            FROM Scenario_Step__c
            WHERE Scenario__c = :scenarioId
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        ScenarioDetails details = new ScenarioDetails();
        details.scenario = mapScenario(row);
        details.scenario.stepCount = steps.size();
        details.steps = new List<StepDTO>();
        for (Scenario_Step__c step : steps)
            details.steps.add(mapStep(step));
        return details;
    }

    @AuraEnabled(cacheable=true)
    public static List<RunSummary> getRecentRuns(Integer limitSize) {
        Integer safeLimit = limitSize == null ? 50 : limitSize;
        if (safeLimit < 1)
            safeLimit = 1;
        if (safeLimit > 200)
            safeLimit = 200;
        List<RunSummary> output = new List<RunSummary>();
        for (Scenario_Run__c row : [
            SELECT
                Id,
                Name,
                Scenario__c,
                Scenario__r.Name,
                Status__c,
                Started_At__c,
                Completed_At__c,
                Duration_Ms__c,
                Total_Steps__c,
                Executed_Steps__c,
                Passed_Steps__c,
                Failed_Steps__c,
                Cpu_Ms__c,
                Soql_Queries__c,
                Dml_Statements__c,
                Engine_Version__c,
                Isolation_Mode__c,
                Summary__c
            FROM Scenario_Run__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :safeLimit
        ])
            output.add(mapRun(row));
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static RunDetails getRunDetails(Id runId) {
        requireId(runId, 'Run');
        Scenario_Run__c row = [
            SELECT
                Id,
                Name,
                Scenario__c,
                Scenario__r.Name,
                Status__c,
                Started_At__c,
                Completed_At__c,
                Duration_Ms__c,
                Total_Steps__c,
                Executed_Steps__c,
                Passed_Steps__c,
                Failed_Steps__c,
                Cpu_Ms__c,
                Soql_Queries__c,
                Dml_Statements__c,
                Engine_Version__c,
                Isolation_Mode__c,
                Summary__c
            FROM Scenario_Run__c
            WHERE Id = :runId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Scenario_Result__c> results = [
            SELECT Id, Sequence__c, Action__c, Status__c, Message__c, Expected__c, Actual__c, Duration_Ms__c
            FROM Scenario_Result__c
            WHERE Run__c = :runId
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        RunDetails details = new RunDetails();
        details.run = mapRun(row);
        details.results = new List<ResultDTO>();
        for (Scenario_Result__c resultRow : results) {
            ResultDTO dto = new ResultDTO();
            dto.id = resultRow.Id;
            dto.sequence = resultRow.Sequence__c;
            dto.action = resultRow.Action__c;
            dto.status = resultRow.Status__c;
            dto.message = resultRow.Message__c;
            dto.expected = resultRow.Expected__c;
            dto.actual = resultRow.Actual__c;
            dto.durationMs = resultRow.Duration_Ms__c;
            details.results.add(dto);
        }
        return details;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardDTO getDashboard() {
        DashboardDTO dto = new DashboardDTO();
        dto.activeScenarios = [SELECT COUNT() FROM Scenario__c WHERE Status__c = 'Active' WITH USER_MODE];
        dto.activeSuites = [SELECT COUNT() FROM Scenario_Suite__c WHERE Status__c = 'Active' WITH USER_MODE];
        List<AggregateResult> aggregates = [
            SELECT Status__c statusValue, COUNT(Id) countValue
            FROM Scenario_Run__c
            WITH USER_MODE
            GROUP BY Status__c
        ];
        dto.totalRuns = 0;
        dto.passedRuns = 0;
        dto.failedRuns = 0;
        for (AggregateResult ar : aggregates) {
            Integer countValue = Integer.valueOf(String.valueOf(ar.get('countValue')));
            String statusValue = (String) ar.get('statusValue');
            dto.totalRuns += countValue;
            if (statusValue == 'PASSED')
                dto.passedRuns += countValue;
            else
                dto.failedRuns += countValue;
        }
        dto.passRate = dto.totalRuns == 0
            ? 0
            : (Decimal.valueOf(String.valueOf(dto.passedRuns)) /
                  Decimal.valueOf(String.valueOf(dto.totalRuns)) *
                  100)
                  .setScale(1);
        dto.recentRuns = getRecentRuns(8);
        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static ScenarioForgeValidator.ValidationReport validateScenario(Id scenarioId) {
        return ScenarioForgeValidator.validateScenario(scenarioId);
    }

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getObjectCatalog() {
        List<ObjectOption> output = new List<ObjectOption>();
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String apiName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult d = globalDescribe.get(apiName).getDescribe();
            if (!d.isAccessible() || d.isDeprecatedAndHidden())
                continue;
            if (apiName.startsWith('Scenario_') || apiName.startsWith('Suite_Run'))
                continue;
            ObjectOption dto = new ObjectOption();
            dto.apiName = apiName;
            dto.label = d.getLabel();
            dto.custom = d.isCustom();
            dto.createable = d.isCreateable();
            dto.updateable = d.isUpdateable();
            dto.deletable = d.isDeletable();
            dto.queryable = d.isQueryable();
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFieldCatalog(String objectApiName) {
        if (String.isBlank(objectApiName) || !Schema.getGlobalDescribe().containsKey(objectApiName))
            throw new AuraHandledException('Unknown object API name.');
        Schema.DescribeSObjectResult d = Schema.getGlobalDescribe().get(objectApiName).getDescribe();
        if (!d.isAccessible())
            throw new AuraHandledException('The running user cannot access this object.');
        List<FieldOption> output = new List<FieldOption>();
        for (String apiName : d.fields.getMap().keySet()) {
            Schema.DescribeFieldResult fd = d.fields.getMap().get(apiName).getDescribe();
            if (!fd.isAccessible())
                continue;
            FieldOption dto = new FieldOption();
            dto.apiName = apiName;
            dto.label = fd.getLabel();
            dto.type = String.valueOf(fd.getType());
            dto.createable = fd.isCreateable();
            dto.updateable = fd.isUpdateable();
            dto.accessible = fd.isAccessible();
            dto.requiredOnCreate = !fd.isNillable() && !fd.isDefaultedOnCreate() && fd.isCreateable();
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled
    public static Id saveScenario(
        Id scenarioId,
        String name,
        String description,
        String status,
        String category,
        String tags
    ) {
        if (String.isBlank(name))
            throw new AuraHandledException('Scenario name is required.');
        Scenario__c record = scenarioId == null ? new Scenario__c() : new Scenario__c(Id = scenarioId);
        record.Name = name.trim();
        record.Description__c = description;
        record.Status__c = String.isBlank(status) ? 'Draft' : status;
        record.Category__c = category;
        record.Tags__c = tags;
        if (scenarioId == null)
            Database.insert(record, AccessLevel.USER_MODE);
        else
            Database.update(record, AccessLevel.USER_MODE);
        return record.Id;
    }

    @AuraEnabled
    public static Id saveStep(
        Id stepId,
        Id scenarioId,
        Decimal sequence,
        String action,
        String targetObject,
        String recordAlias,
        String configuration,
        Boolean enabled,
        Boolean stopOnFailure
    ) {
        requireId(scenarioId, 'Scenario');
        if (sequence == null)
            throw new AuraHandledException('Sequence is required.');
        if (String.isBlank(action))
            throw new AuraHandledException('Action is required.');
        if (String.isBlank(targetObject))
            throw new AuraHandledException('Target object API name is required.');
        validateJson(configuration);
        Scenario_Step__c record = stepId == null ? new Scenario_Step__c() : new Scenario_Step__c(Id = stepId);
        record.Scenario__c = scenarioId;
        record.Sequence__c = sequence;
        record.Action__c = action.trim().toUpperCase();
        record.Target_Object__c = targetObject.trim();
        record.Record_Alias__c = String.isBlank(recordAlias) ? null : recordAlias.trim();
        record.Configuration__c = String.isBlank(configuration) ? '{}' : configuration;
        record.Enabled__c = enabled == null ? true : enabled;
        record.Stop_On_Failure__c = stopOnFailure == null ? true : stopOnFailure;
        if (stepId == null)
            Database.insert(record, AccessLevel.USER_MODE);
        else
            Database.update(record, AccessLevel.USER_MODE);
        return record.Id;
    }

    @AuraEnabled
    public static void deleteStep(Id stepId) {
        if (stepId == null)
            return;
        Database.delete(new Scenario_Step__c(Id = stepId), AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static Id duplicateScenario(Id scenarioId) {
        ScenarioDetails source = getScenarioDetails(scenarioId);
        Id newId = saveScenario(
            null,
            source.scenario.name + ' Copy',
            source.scenario.description,
            'Draft',
            source.scenario.category,
            source.scenario.tags
        );
        List<Scenario_Step__c> inserts = new List<Scenario_Step__c>();
        for (StepDTO step : source.steps) {
            inserts.add(
                new Scenario_Step__c(
                    Scenario__c = newId,
                    Sequence__c = step.sequence,
                    Action__c = step.action,
                    Target_Object__c = step.targetObject,
                    Record_Alias__c = step.recordAlias,
                    Configuration__c = step.configuration,
                    Enabled__c = step.enabled,
                    Stop_On_Failure__c = step.stopOnFailure
                )
            );
        }
        if (!inserts.isEmpty())
            Database.insert(inserts, AccessLevel.USER_MODE);
        return newId;
    }

    @AuraEnabled(cacheable=true)
    public static String exportScenario(Id scenarioId) {
        ScenarioDetails source = getScenarioDetails(scenarioId);
        Map<String, Object> scenarioMap = new Map<String, Object>{
            'name' => source.scenario.name,
            'description' => source.scenario.description,
            'status' => source.scenario.status,
            'category' => source.scenario.category,
            'tags' => source.scenario.tags
        };
        List<Object> steps = new List<Object>();
        for (StepDTO step : source.steps) {
            steps.add(
                new Map<String, Object>{
                    'sequence' => step.sequence,
                    'action' => step.action,
                    'targetObject' => step.targetObject,
                    'recordAlias' => step.recordAlias,
                    'configuration' => JSON.deserializeUntyped(
                        String.isBlank(step.configuration) ? '{}' : step.configuration
                    ),
                    'enabled' => step.enabled,
                    'stopOnFailure' => step.stopOnFailure
                }
            );
        }
        return JSON.serializePretty(
            new Map<String, Object>{
                'schemaVersion' => '3.0',
                'product' => 'ScenarioForge',
                'scenario' => scenarioMap,
                'steps' => steps
            }
        );
    }

    @AuraEnabled
    public static Id importScenario(String source) {
        if (String.isBlank(source))
            throw new AuraHandledException('Paste a ScenarioForge export document.');
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(source);
        } catch (Exception e) {
            throw new AuraHandledException('Import document is not valid JSON.');
        }
        if (!(parsed instanceof Map<String, Object>))
            throw new AuraHandledException('Import document must be a JSON object.');
        Map<String, Object> root = (Map<String, Object>) parsed;
        if (String.valueOf(root.get('product')) != 'ScenarioForge')
            throw new AuraHandledException('This document is not a ScenarioForge export.');
        Map<String, Object> scenarioMap = castMap(root.get('scenario'));
        String name = stringValue(scenarioMap.get('name'));
        if (String.isBlank(name))
            throw new AuraHandledException('Imported scenario is missing a name.');
        Id scenarioId = saveScenario(
            null,
            name,
            stringValue(scenarioMap.get('description')),
            'Draft',
            stringValue(scenarioMap.get('category')),
            stringValue(scenarioMap.get('tags'))
        );
        List<Scenario_Step__c> inserts = new List<Scenario_Step__c>();
        Object rawSteps = root.get('steps');
        if (rawSteps instanceof List<Object>) {
            for (Object rawStep : (List<Object>) rawSteps) {
                Map<String, Object> stepMap = castMap(rawStep);
                inserts.add(
                    new Scenario_Step__c(
                        Scenario__c = scenarioId,
                        Sequence__c = decimalValue(
                            stepMap.get('sequence'),
                            Decimal.valueOf(String.valueOf(inserts.size() + 1))
                        ),
                        Action__c = stringValue(stepMap.get('action')),
                        Target_Object__c = stringValue(stepMap.get('targetObject')),
                        Record_Alias__c = stringValue(stepMap.get('recordAlias')),
                        Configuration__c = JSON.serialize(
                            stepMap.get('configuration') == null
                                ? new Map<String, Object>()
                                : stepMap.get('configuration')
                        ),
                        Enabled__c = booleanValue(stepMap.get('enabled'), true),
                        Stop_On_Failure__c = booleanValue(stepMap.get('stopOnFailure'), true)
                    )
                );
            }
        }
        if (!inserts.isEmpty())
            Database.insert(inserts, AccessLevel.USER_MODE);
        return scenarioId;
    }

    @AuraEnabled
    public static Id runScenario(Id scenarioId) {
        return ScenarioForgeRunner.runScenario(scenarioId);
    }

    private static void validateJson(String source) {
        if (String.isBlank(source))
            return;
        try {
            Object parsed = JSON.deserializeUntyped(source);
            if (!(parsed instanceof Map<String, Object>))
                throw new AuraHandledException('Configuration must contain a JSON object.');
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Configuration must contain valid JSON.');
        }
    }

    private static ScenarioSummary mapScenario(Scenario__c row) {
        ScenarioSummary dto = new ScenarioSummary();
        dto.id = row.Id;
        dto.name = row.Name;
        dto.description = row.Description__c;
        dto.status = row.Status__c;
        dto.category = row.Category__c;
        dto.tags = row.Tags__c;
        dto.lastRunAt = row.Last_Run_At__c;
        dto.lastRunStatus = row.Last_Run_Status__c;
        dto.stepCount = 0;
        return dto;
    }

    private static StepDTO mapStep(Scenario_Step__c row) {
        StepDTO dto = new StepDTO();
        dto.id = row.Id;
        dto.name = row.Name;
        dto.sequence = row.Sequence__c;
        dto.action = row.Action__c;
        dto.targetObject = row.Target_Object__c;
        dto.recordAlias = row.Record_Alias__c;
        dto.configuration = row.Configuration__c;
        dto.enabled = row.Enabled__c;
        dto.stopOnFailure = row.Stop_On_Failure__c;
        return dto;
    }

    private static RunSummary mapRun(Scenario_Run__c row) {
        RunSummary dto = new RunSummary();
        dto.id = row.Id;
        dto.name = row.Name;
        dto.scenarioId = row.Scenario__c;
        dto.scenarioName = row.Scenario__r == null ? null : row.Scenario__r.Name;
        dto.status = row.Status__c;
        dto.startedAt = row.Started_At__c;
        dto.completedAt = row.Completed_At__c;
        dto.durationMs = row.Duration_Ms__c;
        dto.totalSteps = row.Total_Steps__c;
        dto.executedSteps = row.Executed_Steps__c;
        dto.passedSteps = row.Passed_Steps__c;
        dto.failedSteps = row.Failed_Steps__c;
        dto.cpuMs = row.Cpu_Ms__c;
        dto.soqlQueries = row.Soql_Queries__c;
        dto.dmlStatements = row.Dml_Statements__c;
        dto.engineVersion = row.Engine_Version__c;
        dto.isolationMode = row.Isolation_Mode__c;
        dto.summary = row.Summary__c;
        return dto;
    }

    private static Map<String, Object> castMap(Object value) {
        if (!(value instanceof Map<String, Object>))
            throw new AuraHandledException('Import document has an invalid structure.');
        return (Map<String, Object>) value;
    }
    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }
    private static Decimal decimalValue(Object value, Decimal fallback) {
        return value == null ? fallback : Decimal.valueOf(String.valueOf(value));
    }
    private static Boolean booleanValue(Object value, Boolean fallback) {
        return value == null ? fallback : Boolean.valueOf(String.valueOf(value));
    }
    private static void requireId(Id value, String label) {
        if (value == null)
            throw new AuraHandledException(label + ' Id is required.');
    }
}
