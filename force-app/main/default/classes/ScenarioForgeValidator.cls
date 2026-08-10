public with sharing class ScenarioForgeValidator {
    private static final Set<String> SUPPORTED_ACTIONS = new Set<String>{
        'CREATE_RECORD',
        'FIND_RECORD',
        'UPDATE_RECORD',
        'DELETE_RECORD',
        'ASSERT_FIELD',
        'ASSERT_RECORD_EXISTS',
        'ASSERT_RECORD_NOT_EXISTS',
        'ASSERT_RECORD_COUNT'
    };
    private static final Set<String> PROTECTED_OBJECTS = new Set<String>{
        'Scenario__c',
        'Scenario_Step__c',
        'Scenario_Run__c',
        'Scenario_Result__c',
        'Scenario_Suite__c',
        'Scenario_Suite_Member__c',
        'Suite_Run__c',
        'Suite_Run_Item__c'
    };

    public class ValidationIssue {
        @AuraEnabled
        public String severity;
        @AuraEnabled
        public String code;
        @AuraEnabled
        public Decimal sequence;
        @AuraEnabled
        public String message;

        public ValidationIssue(String severity, String code, Decimal sequence, String message) {
            this.severity = severity;
            this.code = code;
            this.sequence = sequence;
            this.message = message;
        }
    }

    public class ValidationReport {
        @AuraEnabled
        public Boolean valid;
        @AuraEnabled
        public Integer errorCount;
        @AuraEnabled
        public Integer warningCount;
        @AuraEnabled
        public Integer enabledSteps;
        @AuraEnabled
        public List<ValidationIssue> issues;
    }

    @AuraEnabled(cacheable=true)
    public static ValidationReport validateScenario(Id scenarioId) {
        if (scenarioId == null) {
            throw new AuraHandledException('A scenario Id is required.');
        }

        Scenario__c scenario = [
            SELECT Id, Name, Status__c
            FROM Scenario__c
            WHERE Id = :scenarioId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Scenario_Step__c> steps = [
            SELECT
                Id,
                Sequence__c,
                Action__c,
                Target_Object__c,
                Record_Alias__c,
                Configuration__c,
                Enabled__c,
                Stop_On_Failure__c
            FROM Scenario_Step__c
            WHERE Scenario__c = :scenarioId AND Enabled__c = TRUE
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];

        ValidationReport report = new ValidationReport();
        report.issues = new List<ValidationIssue>();
        report.enabledSteps = steps.size();

        if (scenario.Status__c == 'Archived') {
            add(report, 'ERROR', 'SCENARIO_ARCHIVED', null, 'Archived scenarios cannot be executed.');
        }
        if (steps.isEmpty()) {
            add(report, 'ERROR', 'NO_STEPS', null, 'Add at least one enabled step before running this scenario.');
        }

        Set<String> availableAliases = new Set<String>();
        Set<String> declaredAliases = new Set<String>();
        Set<Decimal> sequences = new Set<Decimal>();
        for (Scenario_Step__c step : steps) {
            if (sequences.contains(step.Sequence__c)) {
                add(
                    report,
                    'WARNING',
                    'DUPLICATE_SEQUENCE',
                    step.Sequence__c,
                    'Multiple enabled steps share sequence ' +
                        step.Sequence__c +
                        '. CreatedDate will determine their order.'
                );
            }
            sequences.add(step.Sequence__c);
            validateStep(step, availableAliases, declaredAliases, report);
            if (
                (step.Action__c == 'CREATE_RECORD' || step.Action__c == 'FIND_RECORD') &&
                String.isNotBlank(step.Record_Alias__c)
            ) {
                availableAliases.add(step.Record_Alias__c.trim());
                declaredAliases.add(step.Record_Alias__c.trim());
            }
        }

        report.errorCount = 0;
        report.warningCount = 0;
        for (ValidationIssue issue : report.issues) {
            if (issue.severity == 'ERROR')
                report.errorCount++;
            else if (issue.severity == 'WARNING')
                report.warningCount++;
        }
        report.valid = report.errorCount == 0;
        return report;
    }

    public static void assertRunnable(Id scenarioId) {
        ValidationReport report = validateScenario(scenarioId);
        if (report.valid)
            return;
        List<String> errors = new List<String>();
        for (ValidationIssue issue : report.issues) {
            if (issue.severity == 'ERROR')
                errors.add(issue.message);
            if (errors.size() == 3)
                break;
        }
        throw new AuraHandledException('Preflight blocked this run: ' + String.join(errors, ' '));
    }

    private static void validateStep(
        Scenario_Step__c step,
        Set<String> availableAliases,
        Set<String> declaredAliases,
        ValidationReport report
    ) {
        String action = normalize(step.Action__c);
        if (!SUPPORTED_ACTIONS.contains(action)) {
            add(report, 'ERROR', 'UNSUPPORTED_ACTION', step.Sequence__c, 'Unsupported action: ' + step.Action__c + '.');
            return;
        }

        String objectName = String.isBlank(step.Target_Object__c) ? null : step.Target_Object__c.trim();
        if (String.isBlank(objectName)) {
            add(report, 'ERROR', 'OBJECT_REQUIRED', step.Sequence__c, 'Target Object API Name is required.');
            return;
        }
        if (PROTECTED_OBJECTS.contains(objectName)) {
            add(
                report,
                'ERROR',
                'PROTECTED_OBJECT',
                step.Sequence__c,
                objectName + ' is ScenarioForge internal data and cannot be used as a target object.'
            );
            return;
        }

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        if (!globalDescribe.containsKey(objectName)) {
            add(report, 'ERROR', 'UNKNOWN_OBJECT', step.Sequence__c, 'Unknown Salesforce object: ' + objectName + '.');
            return;
        }
        Schema.DescribeSObjectResult objectDescribe = globalDescribe.get(objectName).getDescribe();

        if (action == 'CREATE_RECORD' && !objectDescribe.isCreateable()) {
            add(
                report,
                'ERROR',
                'OBJECT_CREATE_ACCESS',
                step.Sequence__c,
                'The running user cannot create ' + objectName + ' records.'
            );
        }
        if (action == 'UPDATE_RECORD' && !objectDescribe.isUpdateable()) {
            add(
                report,
                'ERROR',
                'OBJECT_UPDATE_ACCESS',
                step.Sequence__c,
                'The running user cannot update ' + objectName + ' records.'
            );
        }
        if (action == 'DELETE_RECORD' && !objectDescribe.isDeletable()) {
            add(
                report,
                'ERROR',
                'OBJECT_DELETE_ACCESS',
                step.Sequence__c,
                'The running user cannot delete ' + objectName + ' records.'
            );
        }
        if ((action == 'FIND_RECORD' || action.startsWith('ASSERT_')) && !objectDescribe.isAccessible()) {
            add(
                report,
                'ERROR',
                'OBJECT_READ_ACCESS',
                step.Sequence__c,
                'The running user cannot read ' + objectName + ' records.'
            );
        }

        Map<String, Object> config;
        try {
            config = parseConfig(step.Configuration__c);
        } catch (Exception e) {
            add(report, 'ERROR', 'INVALID_JSON', step.Sequence__c, 'Configuration must be a valid JSON object.');
            return;
        }

        try {
            if (action == 'CREATE_RECORD') {
                validateFields(objectDescribe, asMap(config.get('fields')), true, false, step.Sequence__c, report);
                validateNewAlias(step.Record_Alias__c, declaredAliases, step.Sequence__c, report);
            } else if (action == 'FIND_RECORD') {
                validateWhere(objectDescribe, asMap(config.get('where')), availableAliases, step.Sequence__c, report);
                validateNewAlias(step.Record_Alias__c, declaredAliases, step.Sequence__c, report);
                if (String.isBlank(step.Record_Alias__c))
                    add(report, 'ERROR', 'ALIAS_REQUIRED', step.Sequence__c, 'FIND_RECORD requires a Record Alias.');
            } else if (action == 'UPDATE_RECORD') {
                validateAlias(aliasFrom(step, config), availableAliases, step.Sequence__c, report);
                validateFields(objectDescribe, asMap(config.get('fields')), false, true, step.Sequence__c, report);
            } else if (action == 'DELETE_RECORD') {
                validateAlias(aliasFrom(step, config), availableAliases, step.Sequence__c, report);
            } else if (action == 'ASSERT_FIELD') {
                validateAlias(aliasFrom(step, config), availableAliases, step.Sequence__c, report);
                String fieldName = stringValue(config.get('field'));
                validateReadableField(objectDescribe, fieldName, step.Sequence__c, report);
                validateAssertionOperator(stringValue(config.get('operator')), step.Sequence__c, report);
            } else if (action == 'ASSERT_RECORD_EXISTS' || action == 'ASSERT_RECORD_NOT_EXISTS') {
                validateWhere(objectDescribe, asMap(config.get('where')), availableAliases, step.Sequence__c, report);
            } else if (action == 'ASSERT_RECORD_COUNT') {
                validateWhere(objectDescribe, asMap(config.get('where')), availableAliases, step.Sequence__c, report);
                validateAssertionOperator(stringValue(config.get('operator')), step.Sequence__c, report);
                if (config.get('expected') == null)
                    add(
                        report,
                        'ERROR',
                        'EXPECTED_REQUIRED',
                        step.Sequence__c,
                        'ASSERT_RECORD_COUNT requires an expected numeric value.'
                    );
            }
        } catch (ScenarioForgeValidationException e) {
            add(report, 'ERROR', 'INVALID_CONFIG_SHAPE', step.Sequence__c, e.getMessage());
        }
    }

    private static void validateNewAlias(
        String aliasName,
        Set<String> declaredAliases,
        Decimal sequence,
        ValidationReport report
    ) {
        if (String.isBlank(aliasName))
            return;
        String normalized = aliasName.trim();
        if (!Pattern.matches('^[A-Za-z][A-Za-z0-9_]*$', normalized)) {
            add(
                report,
                'ERROR',
                'INVALID_ALIAS',
                sequence,
                'Record Alias must start with a letter and contain only letters, numbers, and underscores.'
            );
        }
        if (declaredAliases.contains(normalized)) {
            add(
                report,
                'ERROR',
                'DUPLICATE_ALIAS',
                sequence,
                'Record Alias "' + normalized + '" has already been declared by an earlier step.'
            );
        }
    }

    private static void validateAlias(
        String aliasName,
        Set<String> availableAliases,
        Decimal sequence,
        ValidationReport report
    ) {
        if (String.isBlank(aliasName)) {
            add(
                report,
                'ERROR',
                'ALIAS_REQUIRED',
                sequence,
                'This action requires a recordAlias or Record Alias value.'
            );
        } else if (!availableAliases.contains(aliasName)) {
            add(
                report,
                'ERROR',
                'UNKNOWN_ALIAS',
                sequence,
                'Alias "' + aliasName + '" must be created or found by an earlier step.'
            );
        }
    }

    private static void validateFields(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> fields,
        Boolean creating,
        Boolean updating,
        Decimal sequence,
        ValidationReport report
    ) {
        if (fields.isEmpty()) {
            add(report, 'WARNING', 'EMPTY_FIELDS', sequence, 'No fields are configured for this data operation.');
            return;
        }
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        for (String fieldName : fields.keySet()) {
            if (fieldName == 'Id' || !fieldMap.containsKey(fieldName)) {
                add(report, 'ERROR', 'UNKNOWN_FIELD', sequence, 'Unknown or protected field: ' + fieldName + '.');
                continue;
            }
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if (creating && !fieldDescribe.isCreateable())
                add(
                    report,
                    'ERROR',
                    'FIELD_CREATE_ACCESS',
                    sequence,
                    'Field ' + fieldName + ' is not createable for the running user.'
                );
            if (updating && !fieldDescribe.isUpdateable())
                add(
                    report,
                    'ERROR',
                    'FIELD_UPDATE_ACCESS',
                    sequence,
                    'Field ' + fieldName + ' is not updateable for the running user.'
                );
        }
    }

    private static void validateReadableField(
        Schema.DescribeSObjectResult objectDescribe,
        String fieldName,
        Decimal sequence,
        ValidationReport report
    ) {
        if (String.isBlank(fieldName) || !objectDescribe.fields.getMap().containsKey(fieldName)) {
            add(report, 'ERROR', 'UNKNOWN_FIELD', sequence, 'ASSERT_FIELD requires a valid field API name.');
            return;
        }
        if (!objectDescribe.fields.getMap().get(fieldName).getDescribe().isAccessible()) {
            add(
                report,
                'ERROR',
                'FIELD_READ_ACCESS',
                sequence,
                'Field ' + fieldName + ' is not readable for the running user.'
            );
        }
    }

    private static void validateWhere(
        Schema.DescribeSObjectResult objectDescribe,
        Map<String, Object> whereValues,
        Set<String> availableAliases,
        Decimal sequence,
        ValidationReport report
    ) {
        if (whereValues.isEmpty())
            add(
                report,
                'WARNING',
                'UNFILTERED_QUERY',
                sequence,
                'This step has no where filters and can match any accessible record.'
            );
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        for (String fieldName : whereValues.keySet()) {
            if (!fieldMap.containsKey(fieldName)) {
                add(report, 'ERROR', 'UNKNOWN_FILTER_FIELD', sequence, 'Unknown filter field: ' + fieldName + '.');
                continue;
            }
            if (!fieldMap.get(fieldName).getDescribe().isAccessible())
                add(
                    report,
                    'ERROR',
                    'FILTER_FIELD_ACCESS',
                    sequence,
                    'Filter field ' + fieldName + ' is not readable for the running user.'
                );
            Object value = whereValues.get(fieldName);
            if (value instanceof String) {
                String alias = aliasToken((String) value);
                if (alias != null && !availableAliases.contains(alias))
                    add(
                        report,
                        'ERROR',
                        'UNKNOWN_ALIAS',
                        sequence,
                        'Filter references alias "' + alias + '" before it is available.'
                    );
            }
        }
    }

    private static void validateAssertionOperator(String operatorName, Decimal sequence, ValidationReport report) {
        if (String.isBlank(operatorName))
            return;
        Set<String> allowed = new Set<String>{
            'EQUALS',
            'NOT_EQUALS',
            'CONTAINS',
            'NOT_CONTAINS',
            'STARTS_WITH',
            'ENDS_WITH',
            'GREATER_THAN',
            'GREATER_OR_EQUAL',
            'LESS_THAN',
            'LESS_OR_EQUAL',
            'IS_NULL',
            'NOT_NULL'
        };
        if (!allowed.contains(normalize(operatorName)))
            add(
                report,
                'ERROR',
                'UNSUPPORTED_OPERATOR',
                sequence,
                'Unsupported assertion operator: ' + operatorName + '.'
            );
    }

    private static Map<String, Object> parseConfig(String source) {
        if (String.isBlank(source))
            return new Map<String, Object>();
        Object parsed = JSON.deserializeUntyped(source);
        if (!(parsed instanceof Map<String, Object>))
            throw new ScenarioForgeValidationException('Configuration must be an object.');
        return (Map<String, Object>) parsed;
    }

    private static Map<String, Object> asMap(Object value) {
        if (value == null)
            return new Map<String, Object>();
        if (!(value instanceof Map<String, Object>))
            throw new ScenarioForgeValidationException('Expected a JSON object.');
        return (Map<String, Object>) value;
    }

    private static String aliasFrom(Scenario_Step__c step, Map<String, Object> config) {
        String configured = stringValue(config.get('recordAlias'));
        return String.isNotBlank(configured) ? configured : step.Record_Alias__c;
    }

    private static String aliasToken(String value) {
        if (String.isBlank(value) || !value.startsWith('${') || !value.endsWith('}'))
            return null;
        String token = value.substring(2, value.length() - 1);
        if (new Set<String>{ 'TODAY', 'NOW', 'USER_ID' }.contains(token))
            return null;
        return token;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }

    private static void add(ValidationReport report, String severity, String code, Decimal sequence, String message) {
        report.issues.add(new ValidationIssue(severity, code, sequence, message));
    }

    public class ScenarioForgeValidationException extends Exception {
    }
}
