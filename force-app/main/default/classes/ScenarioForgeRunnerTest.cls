@IsTest
private class ScenarioForgeRunnerTest {
    @TestSetup
    static void setupData() {
        Scenario__c scenario = new Scenario__c(Name = 'Account lifecycle regression', Status__c = 'Active');
        insert scenario;
        insert new List<Scenario_Step__c>{
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 1,
                Action__c = 'CREATE_RECORD',
                Target_Object__c = 'Account',
                Record_Alias__c = 'account',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"fields":{"Name":"ScenarioForge Isolated Account","Industry":"Technology"}}'
            ),
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 2,
                Action__c = 'UPDATE_RECORD',
                Target_Object__c = 'Account',
                Record_Alias__c = 'account',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"recordAlias":"account","fields":{"Phone":"555-0100"}}'
            ),
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 3,
                Action__c = 'ASSERT_FIELD',
                Target_Object__c = 'Account',
                Record_Alias__c = 'account',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"recordAlias":"account","field":"Phone","operator":"STARTS_WITH","expected":"555"}'
            ),
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 4,
                Action__c = 'ASSERT_RECORD_EXISTS',
                Target_Object__c = 'Account',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"where":{"Id":"${account}"}}'
            )
        };
    }

    @IsTest
    static void runScenarioPassesRollsBackAndPersistsTelemetry() {
        Scenario__c scenario = [SELECT Id FROM Scenario__c LIMIT 1];
        Test.startTest();
        Id runId = ScenarioForgeRunner.runScenario(scenario.Id);
        Test.stopTest();
        Scenario_Run__c run = [
            SELECT Status__c, Executed_Steps__c, Passed_Steps__c, Failed_Steps__c, Engine_Version__c, Isolation_Mode__c
            FROM Scenario_Run__c
            WHERE Id = :runId
        ];
        System.assertEquals('PASSED', run.Status__c);
        System.assertEquals(Decimal.valueOf('4'), run.Executed_Steps__c);
        System.assertEquals(Decimal.valueOf('4'), run.Passed_Steps__c);
        System.assertEquals(Decimal.valueOf('0'), run.Failed_Steps__c);
        System.assertEquals('3.0.0', run.Engine_Version__c);
        System.assertEquals('SAVEPOINT_ROLLBACK', run.Isolation_Mode__c);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'ScenarioForge Isolated Account']);
        System.assertEquals(4, [SELECT COUNT() FROM Scenario_Result__c WHERE Run__c = :runId]);
    }

    @IsTest
    static void findAndDeleteCanModelExistingDataWithoutPersistingMutation() {
        Account existing = new Account(Name = 'ScenarioForge Existing');
        insert existing;
        Scenario__c scenario = new Scenario__c(Name = 'Existing record regression', Status__c = 'Active');
        insert scenario;
        insert new List<Scenario_Step__c>{
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 1,
                Action__c = 'FIND_RECORD',
                Target_Object__c = 'Account',
                Record_Alias__c = 'existing',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"where":{"Name":"ScenarioForge Existing"}}'
            ),
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 2,
                Action__c = 'DELETE_RECORD',
                Target_Object__c = 'Account',
                Record_Alias__c = 'existing',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"recordAlias":"existing"}'
            ),
            new Scenario_Step__c(
                Scenario__c = scenario.Id,
                Sequence__c = 3,
                Action__c = 'ASSERT_RECORD_NOT_EXISTS',
                Target_Object__c = 'Account',
                Enabled__c = true,
                Stop_On_Failure__c = true,
                Configuration__c = '{"where":{"Name":"ScenarioForge Existing"}}'
            )
        };
        Test.startTest();
        Id runId = ScenarioForgeRunner.runScenario(scenario.Id);
        Test.stopTest();
        System.assertEquals('PASSED', [SELECT Status__c FROM Scenario_Run__c WHERE Id = :runId].Status__c);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE Id = :existing.Id]);
    }

    @IsTest
    static void failedAssertionProducesFailedRun() {
        Scenario__c scenario = [SELECT Id FROM Scenario__c LIMIT 1];
        insert new Scenario_Step__c(
            Scenario__c = scenario.Id,
            Sequence__c = 5,
            Action__c = 'ASSERT_RECORD_COUNT',
            Target_Object__c = 'Contact',
            Enabled__c = true,
            Stop_On_Failure__c = true,
            Configuration__c = '{"where":{},"operator":"GREATER_THAN","expected":99999}'
        );
        Test.startTest();
        Id runId = ScenarioForgeRunner.runScenario(scenario.Id);
        Test.stopTest();
        System.assertEquals('FAILED', [SELECT Status__c FROM Scenario_Run__c WHERE Id = :runId].Status__c);
    }
}
