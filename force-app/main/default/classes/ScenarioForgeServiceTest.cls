@IsTest
private class ScenarioForgeServiceTest {
    @IsTest
    static void crudPreflightAndPortabilityWork() {
        Test.startTest();
        Id scenarioId = ScenarioForgeService.saveScenario(
            null,
            'Opportunity approval',
            'Regression test',
            'Active',
            'Sales',
            'flow,approval'
        );
        Id stepId = ScenarioForgeService.saveStep(
            null,
            scenarioId,
            1,
            'CREATE_RECORD',
            'Account',
            'account',
            '{"fields":{"Name":"Service Test"}}',
            true,
            true
        );
        ScenarioForgeValidator.ValidationReport report = ScenarioForgeService.validateScenario(scenarioId);
        String exported = ScenarioForgeService.exportScenario(scenarioId);
        Id importedId = ScenarioForgeService.importScenario(exported);
        List<ScenarioForgeService.ScenarioSummary> scenarios = ScenarioForgeService.getScenarios();
        ScenarioForgeService.ScenarioDetails imported = ScenarioForgeService.getScenarioDetails(importedId);
        ScenarioForgeService.DashboardDTO dashboard = ScenarioForgeService.getDashboard();
        ScenarioForgeService.deleteStep(stepId);
        Test.stopTest();
        System.assert(report.valid);
        System.assert(exported.contains('ScenarioForge'));
        System.assertEquals('Draft', imported.scenario.status);
        System.assertEquals(1, imported.steps.size());
        System.assert(scenarios.size() >= 2);
        System.assertEquals(1, dashboard.activeScenarios);
    }

    @IsTest
    static void duplicateCreatesDraftCopy() {
        Id scenarioId = ScenarioForgeService.saveScenario(null, 'Source', 'Source', 'Active', 'Core', 'smoke');
        ScenarioForgeService.saveStep(
            null,
            scenarioId,
            1,
            'CREATE_RECORD',
            'Account',
            'account',
            '{"fields":{"Name":"Copy Test"}}',
            true,
            true
        );
        Test.startTest();
        Id copyId = ScenarioForgeService.duplicateScenario(scenarioId);
        Test.stopTest();
        ScenarioForgeService.ScenarioDetails details = ScenarioForgeService.getScenarioDetails(copyId);
        System.assertEquals('Draft', details.scenario.status);
        System.assertEquals(1, details.steps.size());
    }
}
