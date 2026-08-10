@IsTest
private class ScenarioForgeOnboardingServiceTest {
    @IsTest
    static void installsStarterPackOnlyOnce() {
        Test.startTest();
        ScenarioForgeOnboardingService.StarterPackResult first = ScenarioForgeOnboardingService.installStarterPack();
        ScenarioForgeOnboardingService.StarterPackResult second = ScenarioForgeOnboardingService.installStarterPack();
        ScenarioForgeOnboardingService.SetupState state = ScenarioForgeOnboardingService.getSetupState();
        Test.stopTest();

        System.assertEquals(true, first.created);
        System.assert(first.scenarioCount >= 2);
        System.assertNotEquals(null, first.firstScenarioId);
        System.assertNotEquals(null, first.suiteId);
        System.assertEquals(false, second.created);
        System.assertEquals(true, state.starterInstalled);
        System.assert(state.scenarioCount >= 2);
        System.assert(state.suiteCount >= 1);
    }
}
