@IsTest
private class ScenarioForgeSuiteServiceTest {
    @IsTest
    static void oneScenarioSuiteCompletesAsync() {
        Scenario__c scenario = new Scenario__c(Name = 'Suite scenario', Status__c = 'Active');
        insert scenario;
        insert new Scenario_Step__c(
            Scenario__c = scenario.Id,
            Sequence__c = 1,
            Action__c = 'CREATE_RECORD',
            Target_Object__c = 'Account',
            Record_Alias__c = 'account',
            Enabled__c = true,
            Stop_On_Failure__c = true,
            Configuration__c = '{"fields":{"Name":"Suite Rollback"}}'
        );
        Id suiteId = ScenarioForgeSuiteService.saveSuite(null, 'Release Gate', 'Critical paths', 'Active', 'release');
        ScenarioForgeSuiteService.addScenario(suiteId, scenario.Id, 1);
        Test.startTest();
        Id suiteRunId = ScenarioForgeSuiteService.startSuite(suiteId);
        Test.stopTest();
        Suite_Run__c run = [
            SELECT Status__c, Passed_Scenarios__c, Failed_Scenarios__c
            FROM Suite_Run__c
            WHERE Id = :suiteRunId
        ];
        System.assertEquals('PASSED', run.Status__c);
        System.assertEquals(Decimal.valueOf('1'), run.Passed_Scenarios__c);
        System.assertEquals(0, [SELECT COUNT() FROM Account WHERE Name = 'Suite Rollback']);
        System.assertEquals(1, [SELECT COUNT() FROM Suite_Run_Item__c WHERE Suite_Run__c = :suiteRunId]);
    }
}
