public with sharing class ScenarioForgeRunner {
    public static final String ENGINE_VERSION = '3.0.0';
    public static final String ISOLATION_MODE = 'SAVEPOINT_ROLLBACK';

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

    public class StepExecution {
        public Id stepId;
        public Decimal sequence;
        public String action;
        public String status;
        public String message;
        public String expected;
        public String actual;
        public Long durationMs;
    }

    private class ExecutionContext {
        Map<String, Id> aliases = new Map<String, Id>();
        Map<String, String> aliasObjects = new Map<String, String>();
    }

    public static Id runScenario(Id scenarioId) {
        ScenarioForgeValidator.assertRunnable(scenarioId);

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
                Name,
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

        Datetime startedAt = System.now();
        Long startedWall = startedAt.getTime();
        Integer startedCpu = Limits.getCpuTime();
        Integer startedQueries = Limits.getQueries();
        Integer startedDml = Limits.getDmlStatements();

        List<StepExecution> executions = new List<StepExecution>();
        ExecutionContext context = new ExecutionContext();
        Savepoint checkpoint = Database.setSavepoint();
        String fatalError;
        String stopReason;

        try {
            for (Scenario_Step__c step : steps) {
                StepExecution execution = executeStep(step, context);
                executions.add(execution);
                if (execution.status != 'PASSED' && step.Stop_On_Failure__c) {
                    stopReason =
                        'Execution stopped at step ' +
                        String.valueOf(step.Sequence__c) +
                        ' because Stop on Failure is enabled.';
                    break;
                }
            }
        } catch (Exception e) {
            fatalError = safeMessage(e);
        } finally {
            Database.rollback(checkpoint);
        }

        Integer passed = 0;
        Integer failed = 0;
        for (StepExecution execution : executions) {
            if (execution.status == 'PASSED')
                passed++;
            else
                failed++;
        }
        if (fatalError != null)
            failed++;

        Datetime completedAt = System.now();
        Long durationMs = completedAt.getTime() - startedWall;
        Integer cpuMs = Limits.getCpuTime() - startedCpu;
        Integer queryCount = Limits.getQueries() - startedQueries;
        Integer dmlCount = Limits.getDmlStatements() - startedDml;
        String runStatus = fatalError != null ? 'ERROR' : (failed > 0 ? 'FAILED' : 'PASSED');

        String summary;
        if (fatalError != null) {
            summary = 'Engine error: ' + fatalError;
        } else if (String.isNotBlank(stopReason)) {
            summary = stopReason + ' Business-data mutations were rolled back.';
        } else {
            summary = 'Scenario completed in isolated rollback mode. Business-data mutations were rolled back; execution evidence was persisted.';
        }

        Scenario_Run__c run = new Scenario_Run__c(
            Scenario__c = scenarioId,
            Status__c = runStatus,
            Started_At__c = startedAt,
            Completed_At__c = completedAt,
            Duration_Ms__c = durationMs,
            Total_Steps__c = steps.size(),
            Executed_Steps__c = executions.size() + (fatalError == null ? 0 : 1),
            Passed_Steps__c = passed,
            Failed_Steps__c = failed,
            Executed_By__c = UserInfo.getUserId(),
            Cpu_Ms__c = cpuMs,
            Soql_Queries__c = queryCount,
            Dml_Statements__c = dmlCount,
            Engine_Version__c = ENGINE_VERSION,
            Isolation_Mode__c = ISOLATION_MODE,
            Summary__c = summary
        );
        Database.insert(run, AccessLevel.SYSTEM_MODE);

        List<Scenario_Result__c> resultRecords = new List<Scenario_Result__c>();
        for (StepExecution execution : executions) {
            resultRecords.add(
                new Scenario_Result__c(
                    Run__c = run.Id,
                    Step__c = execution.stepId,
                    Sequence__c = execution.sequence,
                    Action__c = execution.action,
                    Status__c = execution.status,
                    Message__c = truncate(execution.message, 32000),
                    Expected__c = truncate(execution.expected, 32000),
                    Actual__c = truncate(execution.actual, 32000),
                    Duration_Ms__c = execution.durationMs
                )
            );
        }
        if (fatalError != null) {
            resultRecords.add(
                new Scenario_Result__c(
                    Run__c = run.Id,
                    Sequence__c = executions.size() + 1,
                    Action__c = 'ENGINE',
                    Status__c = 'ERROR',
                    Message__c = truncate(fatalError, 32000),
                    Duration_Ms__c = 0
                )
            );
        }
        if (!resultRecords.isEmpty())
            Database.insert(resultRecords, AccessLevel.SYSTEM_MODE);

        scenario.Last_Run_At__c = completedAt;
        scenario.Last_Run_Status__c = runStatus;
        Database.update(scenario, AccessLevel.SYSTEM_MODE);
        return run.Id;
    }

    private static StepExecution executeStep(Scenario_Step__c step, ExecutionContext context) {
        Long startedWall = System.now().getTime();
        StepExecution result = new StepExecution();
        result.stepId = step.Id;
        result.sequence = step.Sequence__c;
        result.action = normalize(step.Action__c);
        result.status = 'PASSED';

        try {
            Map<String, Object> config = parseConfig(step.Configuration__c);
            if (result.action == 'CREATE_RECORD')
                executeCreate(step, config, context, result);
            else if (result.action == 'FIND_RECORD')
                executeFind(step, config, context, result);
            else if (result.action == 'UPDATE_RECORD')
                executeUpdate(step, config, context, result);
            else if (result.action == 'DELETE_RECORD')
                executeDelete(step, config, context, result);
            else if (result.action == 'ASSERT_FIELD')
                executeAssertField(step, config, context, result);
            else if (result.action == 'ASSERT_RECORD_EXISTS')
                executeAssertRecordExists(step, config, context, result, true);
            else if (result.action == 'ASSERT_RECORD_NOT_EXISTS')
                executeAssertRecordExists(step, config, context, result, false);
            else if (result.action == 'ASSERT_RECORD_COUNT')
                executeAssertRecordCount(step, config, context, result);
            else
                fail(result, 'Unsupported action: ' + step.Action__c, null, step.Action__c);
        } catch (Exception e) {
            result.status = 'ERROR';
            result.message = safeMessage(e);
        }
        result.durationMs = System.now().getTime() - startedWall;
        return result;
    }

    private static void executeCreate(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String objectName = requireTargetObject(step.Target_Object__c);
        Schema.SObjectType objectType = requireObject(objectName);
        SObject record = objectType.newSObject();
        applyFields(record, objectName, asMap(config.get('fields')), context);
        Database.SaveResult sr = Database.insert(record, false, AccessLevel.USER_MODE);
        if (!sr.isSuccess())
            throw new ScenarioForgeException(joinErrors(sr.getErrors()));
        registerAlias(step.Record_Alias__c, objectName, sr.getId(), context);
        result.message = 'Created ' + objectName + ' in the isolated scenario transaction.';
        result.actual = String.valueOf(sr.getId());
    }

    private static void executeFind(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String objectName = requireTargetObject(step.Target_Object__c);
        String aliasName = step.Record_Alias__c;
        if (String.isBlank(aliasName))
            throw new ScenarioForgeException('FIND_RECORD requires a Record Alias.');
        Id recordId = findFirstMatching(objectName, asMap(config.get('where')), context);
        if (recordId == null) {
            fail(
                result,
                'No accessible ' + objectName + ' record matched the FIND_RECORD filters.',
                '1 matching record',
                '0 matching records'
            );
            return;
        }
        registerAlias(aliasName, objectName, recordId, context);
        result.message = 'Found ' + objectName + ' and registered alias @' + aliasName + '.';
        result.actual = String.valueOf(recordId);
    }

    private static void executeUpdate(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String aliasName = firstNonBlank(stringValue(config.get('recordAlias')), step.Record_Alias__c);
        Id recordId = requireAlias(aliasName, context);
        String objectName = requireTargetObject(
            firstNonBlank(step.Target_Object__c, context.aliasObjects.get(aliasName))
        );
        SObject record = requireObject(objectName).newSObject();
        record.put('Id', recordId);
        applyFields(record, objectName, asMap(config.get('fields')), context);
        Database.SaveResult sr = Database.update(record, false, AccessLevel.USER_MODE);
        if (!sr.isSuccess())
            throw new ScenarioForgeException(joinErrors(sr.getErrors()));
        result.message = 'Updated ' + objectName + ' alias @' + aliasName + '.';
        result.actual = String.valueOf(recordId);
    }

    private static void executeDelete(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String aliasName = firstNonBlank(stringValue(config.get('recordAlias')), step.Record_Alias__c);
        Id recordId = requireAlias(aliasName, context);
        String objectName = requireTargetObject(
            firstNonBlank(step.Target_Object__c, context.aliasObjects.get(aliasName))
        );
        SObject record = requireObject(objectName).newSObject();
        record.put('Id', recordId);
        Database.DeleteResult dr = Database.delete(record, false, AccessLevel.USER_MODE);
        if (!dr.isSuccess())
            throw new ScenarioForgeException(joinErrors(dr.getErrors()));
        result.message = 'Deleted ' + objectName + ' alias @' + aliasName + ' inside the isolated transaction.';
        result.actual = String.valueOf(recordId);
    }

    private static void executeAssertField(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String aliasName = firstNonBlank(stringValue(config.get('recordAlias')), step.Record_Alias__c);
        Id recordId = requireAlias(aliasName, context);
        String objectName = requireTargetObject(
            firstNonBlank(step.Target_Object__c, context.aliasObjects.get(aliasName))
        );
        Schema.DescribeSObjectResult describe = requireObject(objectName).getDescribe();
        String fieldName = stringValue(config.get('field'));
        if (String.isBlank(fieldName) || !describe.fields.getMap().containsKey(fieldName))
            throw new ScenarioForgeException('Unknown field ' + fieldName + ' on ' + objectName + '.');

        String query = 'SELECT Id, ' + fieldName + ' FROM ' + objectName + ' WHERE Id = :recordId LIMIT 1';
        List<SObject> records = Database.queryWithBinds(
            query,
            new Map<String, Object>{ 'recordId' => recordId },
            AccessLevel.USER_MODE
        );
        if (records.isEmpty()) {
            fail(result, 'Record not found for field assertion.', stringify(config.get('expected')), null);
            return;
        }
        Object actual = records[0].get(fieldName);
        Object expected = resolveValue(config.get('expected'), context);
        String operatorName = normalizeOperator(stringValue(config.get('operator')), 'EQUALS');
        Boolean passed = compare(actual, expected, operatorName);
        result.expected = stringify(expected);
        result.actual = stringify(actual);
        if (!passed)
            fail(
                result,
                'Field assertion failed for ' + objectName + '.' + fieldName + ' (' + operatorName + ').',
                result.expected,
                result.actual
            );
        else
            result.message = 'Field assertion passed for ' + objectName + '.' + fieldName + ' (' + operatorName + ').';
    }

    private static void executeAssertRecordExists(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result,
        Boolean shouldExist
    ) {
        String objectName = requireTargetObject(step.Target_Object__c);
        Integer countValue = countMatching(objectName, asMap(config.get('where')), context);
        result.expected = shouldExist ? '>= 1' : '0';
        result.actual = String.valueOf(countValue);
        Boolean passed = shouldExist ? countValue >= 1 : countValue == 0;
        if (!passed) {
            String label = shouldExist ? 'at least one' : 'zero';
            fail(result, 'Expected ' + label + ' matching ' + objectName + ' record.', result.expected, result.actual);
        } else {
            result.message =
                (shouldExist ? 'Record existence' : 'Record absence') +
                ' assertion passed for ' +
                objectName +
                '.';
        }
    }

    private static void executeAssertRecordCount(
        Scenario_Step__c step,
        Map<String, Object> config,
        ExecutionContext context,
        StepExecution result
    ) {
        String objectName = requireTargetObject(step.Target_Object__c);
        Integer actualCount = countMatching(objectName, asMap(config.get('where')), context);
        Decimal expected = decimalValue(config.get('expected'));
        String operatorName = normalizeOperator(stringValue(config.get('operator')), 'EQUALS');
        Boolean passed = compare(Decimal.valueOf(actualCount), expected, operatorName);
        result.expected = operatorName + ' ' + String.valueOf(expected);
        result.actual = String.valueOf(actualCount);
        if (!passed)
            fail(result, 'Record count assertion failed for ' + objectName + '.', result.expected, result.actual);
        else
            result.message = 'Record count assertion passed for ' + objectName + '.';
    }

    private static Integer countMatching(String objectName, Map<String, Object> whereValues, ExecutionContext context) {
        QueryParts parts = buildWhere(objectName, whereValues, context);
        String query = 'SELECT COUNT() FROM ' + objectName + parts.whereClause;
        return Database.countQueryWithBinds(query, parts.binds, AccessLevel.USER_MODE);
    }

    private static Id findFirstMatching(String objectName, Map<String, Object> whereValues, ExecutionContext context) {
        QueryParts parts = buildWhere(objectName, whereValues, context);
        String query = 'SELECT Id FROM ' + objectName + parts.whereClause + ' LIMIT 2';
        List<SObject> rows = Database.queryWithBinds(query, parts.binds, AccessLevel.USER_MODE);
        if (rows.isEmpty())
            return null;
        if (rows.size() > 1) {
            throw new ScenarioForgeException(
                'FIND_RECORD matched more than one record. Add a unique filter so the alias is deterministic.'
            );
        }
        return (Id) rows[0].get('Id');
    }

    private class QueryParts {
        String whereClause = '';
        Map<String, Object> binds = new Map<String, Object>();
    }

    private static QueryParts buildWhere(String objectName, Map<String, Object> whereValues, ExecutionContext context) {
        Schema.DescribeSObjectResult describe = requireObject(objectName).getDescribe();
        List<String> predicates = new List<String>();
        QueryParts parts = new QueryParts();
        Integer indexValue = 0;
        for (String fieldName : whereValues.keySet()) {
            if (!describe.fields.getMap().containsKey(fieldName))
                throw new ScenarioForgeException('Unknown filter field ' + fieldName + ' on ' + objectName + '.');
            String bindName = 'v' + indexValue++;
            predicates.add(fieldName + ' = :' + bindName);
            Object resolved = resolveValue(whereValues.get(fieldName), context);
            parts.binds.put(bindName, coerceValue(describe.fields.getMap().get(fieldName).getDescribe(), resolved));
        }
        if (!predicates.isEmpty())
            parts.whereClause = ' WHERE ' + String.join(predicates, ' AND ');
        return parts;
    }

    private static void applyFields(
        SObject record,
        String objectName,
        Map<String, Object> fields,
        ExecutionContext context
    ) {
        Schema.DescribeSObjectResult describe = requireObject(objectName).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        for (String fieldName : fields.keySet()) {
            if (fieldName == 'Id' || !fieldMap.containsKey(fieldName))
                throw new ScenarioForgeException('Unknown or protected field ' + fieldName + ' on ' + objectName + '.');
            Object value = resolveValue(fields.get(fieldName), context);
            record.put(fieldName, coerceValue(fieldMap.get(fieldName).getDescribe(), value));
        }
    }

    private static void registerAlias(String aliasName, String objectName, Id recordId, ExecutionContext context) {
        if (String.isBlank(aliasName))
            return;
        String normalizedAlias = aliasName.trim();
        if (context.aliases.containsKey(normalizedAlias))
            throw new ScenarioForgeException('Duplicate record alias: ' + normalizedAlias + '.');
        context.aliases.put(normalizedAlias, recordId);
        context.aliasObjects.put(normalizedAlias, objectName);
    }

    private static Object resolveValue(Object value, ExecutionContext context) {
        if (!(value instanceof String))
            return value;
        String text = (String) value;
        if (!text.startsWith('${') || !text.endsWith('}'))
            return value;
        String token = text.substring(2, text.length() - 1);
        if (token == 'TODAY')
            return Date.today();
        if (token == 'NOW')
            return System.now();
        if (token == 'USER_ID')
            return UserInfo.getUserId();
        return requireAlias(token, context);
    }

    private static Object coerceValue(Schema.DescribeFieldResult fieldDescribe, Object value) {
        if (value == null)
            return null;
        Schema.DisplayType typeValue = fieldDescribe.getType();
        String text = String.valueOf(value);
        if (typeValue == Schema.DisplayType.Boolean)
            return Boolean.valueOf(text);
        if (typeValue == Schema.DisplayType.Date)
            return value instanceof Date ? value : Date.valueOf(text);
        if (typeValue == Schema.DisplayType.DateTime) {
            if (value instanceof Datetime)
                return value;
            String normalized = text.replace('T', ' ');
            Boolean gmt = normalized.endsWith('Z');
            if (gmt)
                normalized = normalized.substring(0, normalized.length() - 1);
            Integer dotIndex = normalized.indexOf('.');
            if (dotIndex > -1)
                normalized = normalized.substring(0, dotIndex);
            return gmt ? Datetime.valueOfGmt(normalized) : Datetime.valueOf(normalized);
        }
        if (typeValue == Schema.DisplayType.Integer)
            return Integer.valueOf(text);
        if (
            typeValue == Schema.DisplayType.Double ||
            typeValue == Schema.DisplayType.Currency ||
            typeValue == Schema.DisplayType.Percent
        )
            return Decimal.valueOf(text);
        if (typeValue == Schema.DisplayType.Id || typeValue == Schema.DisplayType.Reference)
            return (Id) text;
        return text;
    }

    private static Boolean compare(Object actual, Object expected, String operatorName) {
        if (operatorName == 'IS_NULL')
            return actual == null;
        if (operatorName == 'NOT_NULL')
            return actual != null;
        if (operatorName == 'CONTAINS')
            return actual != null && expected != null && String.valueOf(actual).contains(String.valueOf(expected));
        if (operatorName == 'NOT_CONTAINS')
            return actual == null || expected == null || !String.valueOf(actual).contains(String.valueOf(expected));
        if (operatorName == 'STARTS_WITH')
            return actual != null && expected != null && String.valueOf(actual).startsWith(String.valueOf(expected));
        if (operatorName == 'ENDS_WITH')
            return actual != null && expected != null && String.valueOf(actual).endsWith(String.valueOf(expected));
        if (operatorName == 'EQUALS')
            return stringify(actual) == stringify(expected);
        if (operatorName == 'NOT_EQUALS')
            return stringify(actual) != stringify(expected);
        if (
            operatorName == 'GREATER_THAN' ||
            operatorName == 'GREATER_OR_EQUAL' ||
            operatorName == 'LESS_THAN' ||
            operatorName == 'LESS_OR_EQUAL'
        ) {
            if (actual == null || expected == null)
                return false;
            Decimal a = Decimal.valueOf(String.valueOf(actual));
            Decimal e = Decimal.valueOf(String.valueOf(expected));
            if (operatorName == 'GREATER_THAN')
                return a > e;
            if (operatorName == 'GREATER_OR_EQUAL')
                return a >= e;
            if (operatorName == 'LESS_THAN')
                return a < e;
            return a <= e;
        }
        throw new ScenarioForgeException('Unsupported assertion operator: ' + operatorName);
    }

    private static Map<String, Object> parseConfig(String source) {
        if (String.isBlank(source))
            return new Map<String, Object>();
        Object parsed = JSON.deserializeUntyped(source);
        if (!(parsed instanceof Map<String, Object>))
            throw new ScenarioForgeException('Configuration JSON must be an object.');
        return (Map<String, Object>) parsed;
    }

    private static Map<String, Object> asMap(Object value) {
        if (value == null)
            return new Map<String, Object>();
        if (!(value instanceof Map<String, Object>))
            throw new ScenarioForgeException('Expected a JSON object.');
        return (Map<String, Object>) value;
    }

    private static Schema.SObjectType requireObject(String objectName) {
        if (String.isBlank(objectName) || !Schema.getGlobalDescribe().containsKey(objectName))
            throw new ScenarioForgeException('Unknown Salesforce object: ' + objectName + '.');
        return Schema.getGlobalDescribe().get(objectName);
    }

    private static String requireTargetObject(String objectName) {
        if (String.isBlank(objectName))
            throw new ScenarioForgeException('Target Object API Name is required.');
        String normalized = objectName.trim();
        if (PROTECTED_OBJECTS.contains(normalized))
            throw new ScenarioForgeException(normalized + ' is protected ScenarioForge internal data.');
        requireObject(normalized);
        return normalized;
    }

    private static Id requireAlias(String aliasName, ExecutionContext context) {
        if (String.isBlank(aliasName) || !context.aliases.containsKey(aliasName))
            throw new ScenarioForgeException('Unknown record alias: ' + aliasName + '.');
        return context.aliases.get(aliasName);
    }

    private static void fail(StepExecution result, String message, String expected, String actual) {
        result.status = 'FAILED';
        result.message = message;
        result.expected = expected;
        result.actual = actual;
    }

    private static String firstNonBlank(String a, String b) {
        return String.isNotBlank(a) ? a : b;
    }
    private static String normalize(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }
    private static String normalizeOperator(String value, String fallback) {
        return String.isBlank(value) ? fallback : value.trim().toUpperCase();
    }
    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Decimal decimalValue(Object value) {
        if (value == null)
            throw new ScenarioForgeException('Expected numeric value is required.');
        return Decimal.valueOf(String.valueOf(value));
    }

    private static String stringify(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String joinErrors(Database.Error[] errors) {
        List<String> messages = new List<String>();
        for (Database.Error errorValue : errors)
            messages.add(errorValue.getStatusCode() + ': ' + errorValue.getMessage());
        return String.join(messages, ' | ');
    }

    private static String safeMessage(Exception e) {
        String message = e.getMessage();
        return String.isBlank(message) ? e.getTypeName() : message;
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength)
            return value;
        return value.substring(0, maxLength);
    }

    public class ScenarioForgeException extends Exception {
    }
}
