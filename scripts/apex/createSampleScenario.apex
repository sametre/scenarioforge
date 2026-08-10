Scenario__c scenario = new Scenario__c(
    Name = 'Account automation smoke test',
    Description__c = 'Creates an Account, updates it, verifies the field value, and confirms that the record exists inside the isolated transaction.',
    Status__c = 'Active',
    Category__c = 'Sample',
    Tags__c = 'account,smoke-test'
);
insert scenario;

insert new List<Scenario_Step__c>{
    new Scenario_Step__c(
        Scenario__c = scenario.Id,
        Sequence__c = 1,
        Action__c = 'CREATE_RECORD',
        Target_Object__c = 'Account',
        Record_Alias__c = 'account',
        Configuration__c = '{"fields":{"Name":"ScenarioForge Test Account","Industry":"Technology"}}',
        Enabled__c = true,
        Stop_On_Failure__c = true
    ),
    new Scenario_Step__c(
        Scenario__c = scenario.Id,
        Sequence__c = 2,
        Action__c = 'UPDATE_RECORD',
        Target_Object__c = 'Account',
        Record_Alias__c = 'account',
        Configuration__c = '{"recordAlias":"account","fields":{"Phone":"555-0100"}}',
        Enabled__c = true,
        Stop_On_Failure__c = true
    ),
    new Scenario_Step__c(
        Scenario__c = scenario.Id,
        Sequence__c = 3,
        Action__c = 'ASSERT_FIELD',
        Target_Object__c = 'Account',
        Record_Alias__c = 'account',
        Configuration__c = '{"recordAlias":"account","field":"Phone","operator":"EQUALS","expected":"555-0100"}',
        Enabled__c = true,
        Stop_On_Failure__c = true
    ),
    new Scenario_Step__c(
        Scenario__c = scenario.Id,
        Sequence__c = 4,
        Action__c = 'ASSERT_RECORD_EXISTS',
        Target_Object__c = 'Account',
        Configuration__c = '{"where":{"Id":"${account}"}}',
        Enabled__c = true,
        Stop_On_Failure__c = true
    )
};
System.debug('ScenarioForge sample scenario created: ' + scenario.Id);
