public with sharing class ScenarioForgeOnboardingService {
    public static final String STARTER_TAG = 'scenarioforge-starter';
    public static final String PRODUCT_VERSION = '3.0.0';

    public class SetupState {
        @AuraEnabled
        public String productVersion;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public String orgId;
        @AuraEnabled
        public Integer scenarioCount;
        @AuraEnabled
        public Integer suiteCount;
        @AuraEnabled
        public Integer runCount;
        @AuraEnabled
        public Boolean starterInstalled;
        @AuraEnabled
        public Boolean canAuthor;
        @AuraEnabled
        public Boolean accountReady;
        @AuraEnabled
        public Boolean contactReady;
        @AuraEnabled
        public Boolean readyToUse;
        @AuraEnabled
        public String readinessMessage;
    }

    public class StarterPackResult {
        @AuraEnabled
        public Boolean created;
        @AuraEnabled
        public Integer scenarioCount;
        @AuraEnabled
        public Id suiteId;
        @AuraEnabled
        public Id firstScenarioId;
        @AuraEnabled
        public String message;
    }

    @AuraEnabled(cacheable=true)
    public static SetupState getSetupState() {
        SetupState state = new SetupState();
        String starterPattern = '%' + STARTER_TAG + '%';
        state.productVersion = PRODUCT_VERSION;
        state.userName = UserInfo.getName();
        state.orgId = UserInfo.getOrganizationId();
        state.scenarioCount = [SELECT COUNT() FROM Scenario__c WITH USER_MODE];
        state.suiteCount = [SELECT COUNT() FROM Scenario_Suite__c WITH USER_MODE];
        state.runCount = [SELECT COUNT() FROM Scenario_Run__c WITH USER_MODE];
        state.starterInstalled =
            [SELECT COUNT() FROM Scenario__c WHERE Tags__c LIKE :starterPattern WITH USER_MODE] > 0;
        state.canAuthor =
            Scenario__c.SObjectType.getDescribe().isCreateable() &&
            Scenario_Step__c.SObjectType.getDescribe().isCreateable() &&
            Scenario_Suite__c.SObjectType.getDescribe().isCreateable();
        state.accountReady =
            Account.SObjectType.getDescribe().isAccessible() &&
            Account.SObjectType.getDescribe().isCreateable() &&
            Account.Name.getDescribe().isCreateable();
        state.contactReady =
            Contact.SObjectType.getDescribe().isAccessible() &&
            Contact.SObjectType.getDescribe().isCreateable() &&
            Contact.LastName.getDescribe().isCreateable() &&
            Contact.AccountId.getDescribe().isCreateable();
        state.readyToUse = state.scenarioCount > 0;
        if (!state.canAuthor && state.scenarioCount == 0) {
            state.readinessMessage = 'ScenarioForge is installed with execution-only access. Ask an Author or Admin to create or install scenarios.';
        } else if (!state.accountReady) {
            state.readinessMessage = 'ScenarioForge is installed. Grant the current user create access to Account before using the starter pack.';
        } else if (!state.starterInstalled && state.scenarioCount == 0) {
            state.readinessMessage = 'Installation is complete. Install the starter pack to run your first regression scenario.';
        } else {
            state.readinessMessage = 'ScenarioForge is ready. Create a scenario, run Preflight, then execute it in isolated rollback mode.';
        }
        return state;
    }

    @AuraEnabled
    public static StarterPackResult installStarterPack() {
        StarterPackResult output = new StarterPackResult();
        String starterPattern = '%' + STARTER_TAG + '%';
        List<Scenario__c> existing = [
            SELECT Id
            FROM Scenario__c
            WHERE Tags__c LIKE :starterPattern
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            output.created = false;
            output.scenarioCount = [SELECT COUNT() FROM Scenario__c WHERE Tags__c LIKE :starterPattern WITH USER_MODE];
            output.firstScenarioId = existing[0].Id;
            List<Scenario_Suite__c> starterSuites = [
                SELECT Id
                FROM Scenario_Suite__c
                WHERE Tags__c LIKE :starterPattern
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 1
            ];
            output.suiteId = starterSuites.isEmpty() ? null : starterSuites[0].Id;
            output.message = 'The ScenarioForge starter pack is already installed.';
            return output;
        }

        if (!Account.SObjectType.getDescribe().isCreateable() || !Account.Name.getDescribe().isCreateable()) {
            throw new AuraHandledException(
                'The current user needs Create access to Account to install the starter pack. You can still create scenarios for objects you can access.'
            );
        }

        List<Scenario__c> scenarios = new List<Scenario__c>{
            new Scenario__c(
                Name = 'Account Creation Smoke Test',
                Description__c = 'Creates an Account, verifies the Name field, and rolls the business record back after the assertions are captured.',
                Status__c = 'Active',
                Category__c = 'Starter / Smoke',
                Tags__c = STARTER_TAG + ', smoke, account'
            ),
            new Scenario__c(
                Name = 'Account Lifecycle Regression',
                Description__c = 'Creates an Account, updates Industry, validates the change, deletes the record, and verifies that it no longer exists.',
                Status__c = 'Active',
                Category__c = 'Starter / Regression',
                Tags__c = STARTER_TAG + ', regression, account'
            )
        };
        Database.insert(scenarios, AccessLevel.USER_MODE);

        List<Scenario_Step__c> steps = new List<Scenario_Step__c>{
            step(
                scenarios[0].Id,
                1,
                'CREATE_RECORD',
                'Account',
                'account',
                '{"fields":{"Name":"ScenarioForge Smoke Account"}}'
            ),
            step(
                scenarios[0].Id,
                2,
                'ASSERT_FIELD',
                'Account',
                'account',
                '{"recordAlias":"account","field":"Name","operator":"EQUALS","expected":"ScenarioForge Smoke Account"}'
            ),
            step(
                scenarios[1].Id,
                1,
                'CREATE_RECORD',
                'Account',
                'account',
                '{"fields":{"Name":"ScenarioForge Lifecycle Account"}}'
            ),
            step(
                scenarios[1].Id,
                2,
                'UPDATE_RECORD',
                'Account',
                'account',
                '{"recordAlias":"account","fields":{"Industry":"Technology"}}'
            ),
            step(
                scenarios[1].Id,
                3,
                'ASSERT_FIELD',
                'Account',
                'account',
                '{"recordAlias":"account","field":"Industry","operator":"EQUALS","expected":"Technology"}'
            ),
            step(scenarios[1].Id, 4, 'DELETE_RECORD', 'Account', 'account', '{"recordAlias":"account"}'),
            step(scenarios[1].Id, 5, 'ASSERT_RECORD_NOT_EXISTS', 'Account', null, '{"where":{"Id":"${account}"}}')
        };

        if (
            Contact.SObjectType.getDescribe().isCreateable() &&
            Contact.LastName.getDescribe().isCreateable() &&
            Contact.AccountId.getDescribe().isCreateable()
        ) {
            Scenario__c contactScenario = new Scenario__c(
                Name = 'Account & Contact Relationship',
                Description__c = 'Builds a parent Account and related Contact, then validates the relationship without leaving test data behind.',
                Status__c = 'Active',
                Category__c = 'Starter / Relationship',
                Tags__c = STARTER_TAG + ', relationship, account, contact'
            );
            Database.insert(contactScenario, AccessLevel.USER_MODE);
            scenarios.add(contactScenario);
            steps.add(
                step(
                    contactScenario.Id,
                    1,
                    'CREATE_RECORD',
                    'Account',
                    'account',
                    '{"fields":{"Name":"ScenarioForge Relationship Account"}}'
                )
            );
            steps.add(
                step(
                    contactScenario.Id,
                    2,
                    'CREATE_RECORD',
                    'Contact',
                    'contact',
                    '{"fields":{"LastName":"ScenarioForge Contact","AccountId":"${account}"}}'
                )
            );
            steps.add(
                step(
                    contactScenario.Id,
                    3,
                    'ASSERT_RECORD_COUNT',
                    'Contact',
                    null,
                    '{"where":{"AccountId":"${account}"},"operator":"EQUALS","expected":1}'
                )
            );
        }
        Database.insert(steps, AccessLevel.USER_MODE);

        Scenario_Suite__c suite = new Scenario_Suite__c(
            Name = 'ScenarioForge Starter Regression',
            Description__c = 'A ready-to-run regression suite installed by the ScenarioForge onboarding wizard.',
            Status__c = 'Active',
            Tags__c = STARTER_TAG + ', release-gate'
        );
        Database.insert(suite, AccessLevel.USER_MODE);

        List<Scenario_Suite_Member__c> members = new List<Scenario_Suite_Member__c>();
        Integer sequence = 1;
        for (Scenario__c scenario : scenarios) {
            members.add(
                new Scenario_Suite_Member__c(
                    Suite__c = suite.Id,
                    Scenario__c = scenario.Id,
                    Sequence__c = sequence,
                    Enabled__c = true
                )
            );
            sequence++;
        }
        Database.insert(members, AccessLevel.USER_MODE);

        output.created = true;
        output.scenarioCount = scenarios.size();
        output.suiteId = suite.Id;
        output.firstScenarioId = scenarios[0].Id;
        output.message = 'Starter pack installed. Run the first scenario or execute the full starter regression suite.';
        return output;
    }

    private static Scenario_Step__c step(
        Id scenarioId,
        Decimal sequence,
        String action,
        String targetObject,
        String aliasName,
        String configuration
    ) {
        return new Scenario_Step__c(
            Scenario__c = scenarioId,
            Sequence__c = sequence,
            Action__c = action,
            Target_Object__c = targetObject,
            Record_Alias__c = aliasName,
            Configuration__c = configuration,
            Enabled__c = true,
            Stop_On_Failure__c = true
        );
    }
}
