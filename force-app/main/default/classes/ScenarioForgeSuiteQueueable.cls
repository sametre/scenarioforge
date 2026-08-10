public with sharing class ScenarioForgeSuiteQueueable implements Queueable {
    private Id suiteRunId;
    private List<Id> memberIds;
    private Integer currentIndex;

    public ScenarioForgeSuiteQueueable(Id suiteRunId, List<Id> memberIds, Integer currentIndex) {
        this.suiteRunId = suiteRunId;
        this.memberIds = memberIds;
        this.currentIndex = currentIndex;
    }

    public void execute(QueueableContext context) {
        if (
            suiteRunId == null ||
            memberIds == null ||
            memberIds.isEmpty() ||
            currentIndex == null ||
            currentIndex >= memberIds.size()
        ) {
            finalizeRun('ERROR', 'Suite execution state was invalid.');
            return;
        }

        Scenario_Suite_Member__c member;
        try {
            member = [
                SELECT Id, Suite__c, Scenario__c, Scenario__r.Name, Sequence__c, Enabled__c
                FROM Scenario_Suite_Member__c
                WHERE Id = :memberIds[currentIndex]
                WITH USER_MODE
                LIMIT 1
            ];
        } catch (Exception e) {
            persistErrorItem(null, null, currentIndex + 1, 'Unable to load suite member: ' + e.getMessage());
            continueOrFinalize();
            return;
        }

        Long started = System.now().getTime();
        Id scenarioRunId;
        String status = 'ERROR';
        String message;
        try {
            if (!member.Enabled__c) {
                message = 'Suite member was disabled after the suite was queued.';
            } else {
                scenarioRunId = ScenarioForgeRunner.runScenario(member.Scenario__c);
                Scenario_Run__c scenarioRun = [
                    SELECT Status__c, Summary__c
                    FROM Scenario_Run__c
                    WHERE Id = :scenarioRunId
                    WITH USER_MODE
                    LIMIT 1
                ];
                status = scenarioRun.Status__c;
                message = scenarioRun.Summary__c;
            }
        } catch (Exception e) {
            status = 'ERROR';
            message = e.getMessage();
        }
        Long duration = System.now().getTime() - started;

        Suite_Run_Item__c item = new Suite_Run_Item__c(
            Suite_Run__c = suiteRunId,
            Scenario__c = member.Scenario__c,
            Scenario_Run__c = scenarioRunId,
            Sequence__c = member.Sequence__c,
            Status__c = status,
            Duration_Ms__c = duration,
            Message__c = truncate(message, 32000)
        );
        Database.insert(item, AccessLevel.SYSTEM_MODE);
        continueOrFinalize();
    }

    private void continueOrFinalize() {
        Integer nextIndex = currentIndex + 1;
        if (nextIndex < memberIds.size()) {
            System.enqueueJob(new ScenarioForgeSuiteQueueable(suiteRunId, memberIds, nextIndex));
        } else {
            finalizeRun(null, null);
        }
    }

    private void persistErrorItem(Id scenarioId, Id scenarioRunId, Decimal sequence, String message) {
        Suite_Run_Item__c item = new Suite_Run_Item__c(
            Suite_Run__c = suiteRunId,
            Scenario__c = scenarioId,
            Scenario_Run__c = scenarioRunId,
            Sequence__c = sequence,
            Status__c = 'ERROR',
            Duration_Ms__c = 0,
            Message__c = truncate(message, 32000)
        );
        Database.insert(item, AccessLevel.SYSTEM_MODE);
    }

    private void finalizeRun(String forcedStatus, String forcedSummary) {
        Suite_Run__c run = [
            SELECT Id, Suite__c, Started_At__c, Total_Scenarios__c
            FROM Suite_Run__c
            WHERE Id = :suiteRunId
            WITH USER_MODE
            LIMIT 1
        ];
        Integer passed = 0;
        Integer failed = 0;
        Integer errors = 0;
        for (AggregateResult row : [
            SELECT Status__c statusValue, COUNT(Id) countValue
            FROM Suite_Run_Item__c
            WHERE Suite_Run__c = :suiteRunId
            WITH USER_MODE
            GROUP BY Status__c
        ]) {
            Integer countValue = Integer.valueOf(String.valueOf(row.get('countValue')));
            String statusValue = (String) row.get('statusValue');
            if (statusValue == 'PASSED')
                passed += countValue;
            else if (statusValue == 'ERROR') {
                errors += countValue;
                failed += countValue;
            } else
                failed += countValue;
        }
        Datetime completed = System.now();
        String finalStatus = forcedStatus;
        if (String.isBlank(finalStatus))
            finalStatus = errors > 0 ? 'ERROR' : (failed > 0 ? 'FAILED' : 'PASSED');
        String summary = forcedSummary;
        if (String.isBlank(summary))
            summary =
                'Suite completed: ' +
                passed +
                ' passed, ' +
                failed +
                ' failed/error across ' +
                String.valueOf(run.Total_Scenarios__c) +
                ' scenarios.';

        run.Status__c = finalStatus;
        run.Completed_At__c = completed;
        run.Duration_Ms__c = run.Started_At__c == null ? null : completed.getTime() - run.Started_At__c.getTime();
        run.Passed_Scenarios__c = passed;
        run.Failed_Scenarios__c = failed;
        run.Summary__c = summary;
        Database.update(run, AccessLevel.SYSTEM_MODE);

        if (run.Suite__c != null) {
            Scenario_Suite__c suite = new Scenario_Suite__c(Id = run.Suite__c, Last_Run_At__c = completed);
            Database.update(suite, AccessLevel.SYSTEM_MODE);
        }
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength)
            return value;
        return value.substring(0, maxLength);
    }
}
