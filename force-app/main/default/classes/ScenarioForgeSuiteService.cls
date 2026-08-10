public with sharing class ScenarioForgeSuiteService {
    public class SuiteSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String tags;
        @AuraEnabled
        public Datetime lastRunAt;
        @AuraEnabled
        public Integer memberCount;
    }
    public class SuiteMemberDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id scenarioId;
        @AuraEnabled
        public String scenarioName;
        @AuraEnabled
        public Decimal sequence;
        @AuraEnabled
        public Boolean enabled;
        @AuraEnabled
        public String lastRunStatus;
    }
    public class SuiteDetails {
        @AuraEnabled
        public SuiteSummary suite;
        @AuraEnabled
        public List<SuiteMemberDTO> members;
        @AuraEnabled
        public List<SuiteRunSummary> recentRuns;
    }
    public class SuiteRunSummary {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id suiteId;
        @AuraEnabled
        public String suiteName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Datetime startedAt;
        @AuraEnabled
        public Datetime completedAt;
        @AuraEnabled
        public Decimal durationMs;
        @AuraEnabled
        public Decimal totalScenarios;
        @AuraEnabled
        public Decimal passedScenarios;
        @AuraEnabled
        public Decimal failedScenarios;
        @AuraEnabled
        public String summary;
    }
    public class SuiteRunItemDTO {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Decimal sequence;
        @AuraEnabled
        public Id scenarioId;
        @AuraEnabled
        public String scenarioName;
        @AuraEnabled
        public Id scenarioRunId;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Decimal durationMs;
        @AuraEnabled
        public String message;
    }
    public class SuiteRunDetails {
        @AuraEnabled
        public SuiteRunSummary run;
        @AuraEnabled
        public List<SuiteRunItemDTO> items;
    }

    @AuraEnabled(cacheable=true)
    public static List<SuiteSummary> getSuites() {
        List<SuiteSummary> output = new List<SuiteSummary>();
        for (Scenario_Suite__c row : [
            SELECT
                Id,
                Name,
                Description__c,
                Status__c,
                Tags__c,
                Last_Run_At__c,
                (SELECT Id FROM Members__r WHERE Enabled__c = TRUE)
            FROM Scenario_Suite__c
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 100
        ]) {
            SuiteSummary dto = mapSuite(row);
            dto.memberCount = row.Members__r == null ? 0 : row.Members__r.size();
            output.add(dto);
        }
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static SuiteDetails getSuiteDetails(Id suiteId) {
        if (suiteId == null)
            throw new AuraHandledException('Suite Id is required.');
        Scenario_Suite__c suite = [
            SELECT Id, Name, Description__c, Status__c, Tags__c, Last_Run_At__c
            FROM Scenario_Suite__c
            WHERE Id = :suiteId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Scenario_Suite_Member__c> rows = [
            SELECT Id, Scenario__c, Scenario__r.Name, Scenario__r.Last_Run_Status__c, Sequence__c, Enabled__c
            FROM Scenario_Suite_Member__c
            WHERE Suite__c = :suiteId
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        SuiteDetails dto = new SuiteDetails();
        dto.suite = mapSuite(suite);
        dto.suite.memberCount = rows.size();
        dto.members = new List<SuiteMemberDTO>();
        for (Scenario_Suite_Member__c row : rows) {
            SuiteMemberDTO member = new SuiteMemberDTO();
            member.id = row.Id;
            member.scenarioId = row.Scenario__c;
            member.scenarioName = row.Scenario__r == null ? null : row.Scenario__r.Name;
            member.sequence = row.Sequence__c;
            member.enabled = row.Enabled__c;
            member.lastRunStatus = row.Scenario__r == null ? null : row.Scenario__r.Last_Run_Status__c;
            dto.members.add(member);
        }
        dto.recentRuns = getSuiteRuns(suiteId, 10);
        return dto;
    }

    @AuraEnabled(cacheable=true)
    public static List<SuiteRunSummary> getSuiteRuns(Id suiteId, Integer limitSize) {
        Integer safeLimit = limitSize == null ? 25 : limitSize;
        if (safeLimit < 1)
            safeLimit = 1;
        if (safeLimit > 100)
            safeLimit = 100;
        List<SuiteRunSummary> output = new List<SuiteRunSummary>();
        if (suiteId == null) {
            for (Suite_Run__c row : [
                SELECT
                    Id,
                    Name,
                    Suite__c,
                    Suite__r.Name,
                    Status__c,
                    Started_At__c,
                    Completed_At__c,
                    Duration_Ms__c,
                    Total_Scenarios__c,
                    Passed_Scenarios__c,
                    Failed_Scenarios__c,
                    Summary__c
                FROM Suite_Run__c
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :safeLimit
            ])
                output.add(mapRun(row));
        } else {
            for (Suite_Run__c row : [
                SELECT
                    Id,
                    Name,
                    Suite__c,
                    Suite__r.Name,
                    Status__c,
                    Started_At__c,
                    Completed_At__c,
                    Duration_Ms__c,
                    Total_Scenarios__c,
                    Passed_Scenarios__c,
                    Failed_Scenarios__c,
                    Summary__c
                FROM Suite_Run__c
                WHERE Suite__c = :suiteId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :safeLimit
            ])
                output.add(mapRun(row));
        }
        return output;
    }

    @AuraEnabled(cacheable=true)
    public static SuiteRunDetails getSuiteRunDetails(Id suiteRunId) {
        if (suiteRunId == null)
            throw new AuraHandledException('Suite Run Id is required.');
        Suite_Run__c run = [
            SELECT
                Id,
                Name,
                Suite__c,
                Suite__r.Name,
                Status__c,
                Started_At__c,
                Completed_At__c,
                Duration_Ms__c,
                Total_Scenarios__c,
                Passed_Scenarios__c,
                Failed_Scenarios__c,
                Summary__c
            FROM Suite_Run__c
            WHERE Id = :suiteRunId
            WITH USER_MODE
            LIMIT 1
        ];
        List<Suite_Run_Item__c> rows = [
            SELECT
                Id,
                Sequence__c,
                Scenario__c,
                Scenario__r.Name,
                Scenario_Run__c,
                Status__c,
                Duration_Ms__c,
                Message__c
            FROM Suite_Run_Item__c
            WHERE Suite_Run__c = :suiteRunId
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        SuiteRunDetails dto = new SuiteRunDetails();
        dto.run = mapRun(run);
        dto.items = new List<SuiteRunItemDTO>();
        for (Suite_Run_Item__c row : rows) {
            SuiteRunItemDTO item = new SuiteRunItemDTO();
            item.id = row.Id;
            item.sequence = row.Sequence__c;
            item.scenarioId = row.Scenario__c;
            item.scenarioName = row.Scenario__r == null ? null : row.Scenario__r.Name;
            item.scenarioRunId = row.Scenario_Run__c;
            item.status = row.Status__c;
            item.durationMs = row.Duration_Ms__c;
            item.message = row.Message__c;
            dto.items.add(item);
        }
        return dto;
    }

    @AuraEnabled
    public static Id saveSuite(Id suiteId, String name, String description, String status, String tags) {
        if (String.isBlank(name))
            throw new AuraHandledException('Suite name is required.');
        Scenario_Suite__c record = suiteId == null ? new Scenario_Suite__c() : new Scenario_Suite__c(Id = suiteId);
        record.Name = name.trim();
        record.Description__c = description;
        record.Status__c = String.isBlank(status) ? 'Draft' : status;
        record.Tags__c = tags;
        if (suiteId == null)
            Database.insert(record, AccessLevel.USER_MODE);
        else
            Database.update(record, AccessLevel.USER_MODE);
        return record.Id;
    }

    @AuraEnabled
    public static Id addScenario(Id suiteId, Id scenarioId, Decimal sequence) {
        if (suiteId == null || scenarioId == null)
            throw new AuraHandledException('Suite and Scenario are required.');
        Integer existing = [
            SELECT COUNT()
            FROM Scenario_Suite_Member__c
            WHERE Suite__c = :suiteId AND Scenario__c = :scenarioId
            WITH USER_MODE
        ];
        if (existing > 0)
            throw new AuraHandledException('This scenario is already part of the suite.');
        Decimal safeSequence = sequence;
        if (safeSequence == null) {
            List<AggregateResult> rows = [
                SELECT MAX(Sequence__c) maxSequence
                FROM Scenario_Suite_Member__c
                WHERE Suite__c = :suiteId
                WITH USER_MODE
            ];
            Decimal maxSequence = rows.isEmpty() || rows[0].get('maxSequence') == null
                ? 0
                : (Decimal) rows[0].get('maxSequence');
            safeSequence = maxSequence + 1;
        }
        Scenario_Suite_Member__c member = new Scenario_Suite_Member__c(
            Suite__c = suiteId,
            Scenario__c = scenarioId,
            Sequence__c = safeSequence,
            Enabled__c = true
        );
        Database.insert(member, AccessLevel.USER_MODE);
        return member.Id;
    }

    @AuraEnabled
    public static void removeScenario(Id memberId) {
        if (memberId == null)
            return;
        Database.delete(new Scenario_Suite_Member__c(Id = memberId), AccessLevel.USER_MODE);
    }

    @AuraEnabled
    public static Id startSuite(Id suiteId) {
        if (suiteId == null)
            throw new AuraHandledException('Suite Id is required.');
        Scenario_Suite__c suite = [
            SELECT Id, Name, Status__c
            FROM Scenario_Suite__c
            WHERE Id = :suiteId
            WITH USER_MODE
            LIMIT 1
        ];
        if (suite.Status__c == 'Archived')
            throw new AuraHandledException('Archived suites cannot be executed.');
        List<Scenario_Suite_Member__c> members = [
            SELECT Id
            FROM Scenario_Suite_Member__c
            WHERE Suite__c = :suiteId AND Enabled__c = TRUE
            WITH USER_MODE
            ORDER BY Sequence__c ASC, CreatedDate ASC
        ];
        if (members.isEmpty())
            throw new AuraHandledException('Add at least one enabled scenario before running this suite.');
        if (members.size() > 50)
            throw new AuraHandledException(
                'A suite can execute up to 50 scenarios per run. Split larger regression packs into multiple suites.'
            );

        Suite_Run__c run = new Suite_Run__c(
            Suite__c = suiteId,
            Status__c = 'RUNNING',
            Started_At__c = System.now(),
            Total_Scenarios__c = members.size(),
            Passed_Scenarios__c = 0,
            Failed_Scenarios__c = 0,
            Executed_By__c = UserInfo.getUserId(),
            Summary__c = 'Regression suite queued. Each scenario executes in its own Queueable transaction.'
        );
        Database.insert(run, AccessLevel.SYSTEM_MODE);
        List<Id> memberIds = new List<Id>();
        for (Scenario_Suite_Member__c member : members)
            memberIds.add(member.Id);
        System.enqueueJob(new ScenarioForgeSuiteQueueable(run.Id, memberIds, 0));
        return run.Id;
    }

    private static SuiteSummary mapSuite(Scenario_Suite__c row) {
        SuiteSummary dto = new SuiteSummary();
        dto.id = row.Id;
        dto.name = row.Name;
        dto.description = row.Description__c;
        dto.status = row.Status__c;
        dto.tags = row.Tags__c;
        dto.lastRunAt = row.Last_Run_At__c;
        dto.memberCount = 0;
        return dto;
    }

    private static SuiteRunSummary mapRun(Suite_Run__c row) {
        SuiteRunSummary dto = new SuiteRunSummary();
        dto.id = row.Id;
        dto.name = row.Name;
        dto.suiteId = row.Suite__c;
        dto.suiteName = row.Suite__r == null ? null : row.Suite__r.Name;
        dto.status = row.Status__c;
        dto.startedAt = row.Started_At__c;
        dto.completedAt = row.Completed_At__c;
        dto.durationMs = row.Duration_Ms__c;
        dto.totalScenarios = row.Total_Scenarios__c;
        dto.passedScenarios = row.Passed_Scenarios__c;
        dto.failedScenarios = row.Failed_Scenarios__c;
        dto.summary = row.Summary__c;
        return dto;
    }
}
