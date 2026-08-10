List<Scenario__c> scenarios = [
    SELECT Id, Name
    FROM Scenario__c
    WHERE Name = 'Account automation smoke test'
    LIMIT 1
];

System.assert(!scenarios.isEmpty(), 'Run scripts/apex/createSampleScenario.apex first.');

Scenario_Suite__c suite = new Scenario_Suite__c(
    Name = 'ScenarioForge Release Gate',
    Description__c = 'Sample regression suite for release-critical Salesforce automation paths.',
    Status__c = 'Active',
    Tags__c = 'sample,release-gate'
);
insert suite;

insert new Scenario_Suite_Member__c(
    Suite__c = suite.Id,
    Scenario__c = scenarios[0].Id,
    Sequence__c = 1,
    Enabled__c = true
);

System.debug('ScenarioForge sample suite created: ' + suite.Id);
