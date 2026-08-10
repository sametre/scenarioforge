@IsTest
private class ScenarioForgeValidatorTest {
    @IsTest
    static void detectsAliasOrderingAndUnknownField() {
        Scenario__c scenario = new Scenario__c(Name = 'Invalid definition', Status__c = 'Draft');
        insert scenario;
        insert new Scenario_Step__c(
            Scenario__c = scenario.Id,
            Sequence__c = 1,
            Action__c = 'ASSERT_FIELD',
            Target_Object__c = 'Account',
            Record_Alias__c = 'future',
            Enabled__c = true,
            Stop_On_Failure__c = true,
            Configuration__c = '{"recordAlias":"future","field":"Definitely_Not_A_Field__c","expected":"x"}'
        );
        Test.startTest();
        ScenarioForgeValidator.ValidationReport report = ScenarioForgeValidator.validateScenario(scenario.Id);
        Test.stopTest();
        System.assertEquals(false, report.valid);
        System.assert(report.errorCount >= 2);
    }
}
