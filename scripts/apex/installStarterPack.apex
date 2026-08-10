ScenarioForgeOnboardingService.StarterPackResult result = ScenarioForgeOnboardingService.installStarterPack();
System.debug(LoggingLevel.INFO, 'ScenarioForge starter pack: ' + result.message);
System.debug(LoggingLevel.INFO, 'Scenarios available: ' + result.scenarioCount);
System.debug(LoggingLevel.INFO, 'Starter suite Id: ' + result.suiteId);
