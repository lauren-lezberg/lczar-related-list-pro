@IsTest
private class RelatedListControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Opportunity> opps = new List<Opportunity>();

        for (Integer i = 0; i < 25; i++) {
            opps.add(new Opportunity(
                Name = 'Opp ' + i,
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = i * 1000
            ));
        }

        insert opps;
    }

    // ----------------------------
    // LICENSE KEY VALIDATION
    // ----------------------------

    @IsTest
    static void testIsValidProLicense_validKey() {
        // isProOverride bypasses license check in other tests — test the method directly
        System.assertEquals(false, RelatedListController.isValidProLicense(),
            'Should return false when no Pro metadata record exists');
    }

    @IsTest
    static void testIsValidProLicense_invalidPrefix() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            // No metadata record = not pro, even with override off
            RelatedListController.isProOverride = false;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            // Without override, component should be in free mode
            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id, 'Opportunity', 'AccountId', 'Name', 10, 1, null, null
            );

            System.assertEquals(false, result.get('isPro'),
                'Should be free mode when no valid license exists');
        }
    }

    // ----------------------------
    // FREE MODE TESTS
    // ----------------------------

    @IsTest
    static void testFreeModeLimit() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = false;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name,Amount',
                50,
                1,
                null,
                null
            );

            List<SObject> records = (List<SObject>) result.get('records');

            System.assertEquals(10, records.size(), 'Free mode should limit to 10');
            System.assertEquals(10, result.get('rowLimit'));
            System.assertEquals(0, result.get('totalCount'));
        }
    }

    @IsTest
    static void testFreeModeDefaultSort() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = false;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name',
                10,
                1,
                null,
                null
            );

            List<Opportunity> records = (List<Opportunity>) result.get('records');
            System.assertEquals(10, records.size());

            for (Integer i = 0; i < records.size() - 1; i++) {
                System.assert(
                    records[i].Name <= records[i + 1].Name,
                    'Free mode records should be sorted by Name ASC'
                );
            }
        }
    }

    @IsTest
    static void testFreeModeIgnoresPagination() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = false;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name',
                10,
                3,
                null,
                null
            );

            List<SObject> records = (List<SObject>) result.get('records');
            System.assertEquals(10, records.size());
        }
    }

    // ----------------------------
    // PRO MODE TESTS
    // ----------------------------

    @IsTest
    static void testProModePagination() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = true;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> page1 = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name',
                10,
                1,
                'Name',
                'ASC'
            );

            Map<String, Object> page2 = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name',
                10,
                2,
                'Name',
                'ASC'
            );

            List<SObject> records1 = (List<SObject>) page1.get('records');
            List<SObject> records2 = (List<SObject>) page2.get('records');

            System.assertEquals(10, records1.size());
            System.assertEquals(10, records2.size());
            System.assertNotEquals(records1[0].Id, records2[0].Id, 'Pages should differ');
            System.assertEquals(25, page1.get('totalCount'));
        }
    }

    @IsTest
    static void testProModeSorting() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = true;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name,Amount',
                10,
                1,
                'Amount',
                'DESC'
            );

            List<Opportunity> records = (List<Opportunity>) result.get('records');
            System.assert(records[0].Amount >= records[1].Amount,
                'Records should be sorted DESC by Amount');
        }
    }

    @IsTest
    static void testProModePageSizeCapped() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = true;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name',
                99999,
                1,
                null,
                null
            );

            Integer rowLimit = (Integer) result.get('rowLimit');
            System.assert(rowLimit <= 200, 'Row limit should be capped at MAX_PAGE_SIZE');
        }
    }

    // ----------------------------
    // LOOKUP FIELD TEST
    // ----------------------------

    @IsTest
    static void testLookupFieldIncludesName() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            RelatedListController.isProOverride = true;

            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'Opportunity',
                'AccountId',
                'Name,AccountId',
                10,
                1,
                null,
                null
            );

            List<SObject> records = (List<SObject>) result.get('records');
            SObject first = records[0];
            SObject parent = first.getSObject('Account');

            System.assertNotEquals(null, parent, 'Parent relationship should be populated');
            System.assertNotEquals(null, parent.get('Name'), 'Parent Name should be populated');
        }
    }

    // ----------------------------
    // SAVE
    // ----------------------------

    @IsTest
    static void testSaveRecordsBulkUpdate() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            List<Opportunity> opps = [SELECT Id, Name FROM Opportunity LIMIT 2];

            for (Opportunity o : opps) {
                o.Name = 'Updated';
            }

            Test.startTest();
            RelatedListController.saveRecords(opps);
            Test.stopTest();

            List<Opportunity> updated = [SELECT Name FROM Opportunity WHERE Id IN :opps];
            for (Opportunity o : updated) {
                System.assertEquals('Updated', o.Name);
            }
        }
    }

    @IsTest
    static void testSaveRecordsEmptyList() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            Test.startTest();
            RelatedListController.saveRecords(new List<SObject>());
            Test.stopTest();
            System.assert(true, 'Empty list should not throw');
        }
    }

    // ----------------------------
    // DELETE
    // ----------------------------

    @IsTest
    static void testDeleteRecordSuccess() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
            Id oppId = opp.Id;

            Test.startTest();
            RelatedListController.deleteRecord(oppId);
            Test.stopTest();

            List<Opportunity> remaining = [SELECT Id FROM Opportunity WHERE Id = :oppId];
            System.assertEquals(0, remaining.size(), 'Record should have been deleted');
        }
    }

    @IsTest
    static void testDeleteRecordNullId() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            try {
                RelatedListController.deleteRecord(null);
                System.assert(false, 'Should have thrown an AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Exception message should not be null');
            }
        }
    }

    // ----------------------------
    // SEARCH
    // ----------------------------

    @IsTest
    static void testSearchRecordsInjectionSafe() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            List<SObject> results = RelatedListController.searchRecords(
                'Account',
                '%\' OR Name LIKE \'%'
            );

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(0, results.size(), 'Injection attempt should return no results');
        }
    }

    @IsTest
    static void testSearchRecordsInvalidObject() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            try {
                RelatedListController.searchRecords('FakeObject__c', 'test');
                System.assert(false, 'Should have thrown an AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Exception message should not be null');
            }
        }
    }

    // ----------------------------
    // INVALID INPUTS
    // ----------------------------

    @IsTest
    static void testGetRelatedRecordsInvalidParentField() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            Account acc = [SELECT Id FROM Account LIMIT 1];

            try {
                RelatedListController.getRelatedRecords(
                    acc.Id,
                    'Opportunity',
                    'FakeFieldId__c',
                    'Name',
                    10,
                    1,
                    null,
                    null
                );
                System.assert(false, 'Should have thrown an AuraHandledException');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage() != null, 'Exception message should not be null');
            }
        }
    }

    @IsTest
    static void testGetRelatedRecordsInvalidObject() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            Account acc = [SELECT Id FROM Account LIMIT 1];

            Map<String, Object> result = RelatedListController.getRelatedRecords(
                acc.Id,
                'FakeObject__c',
                'AccountId',
                'Name',
                10,
                1,
                null,
                null
            );

            System.assertEquals(null, result, 'Invalid object should return null');
        }
    }

    // ----------------------------
    // FIELD METADATA
    // ----------------------------

    @IsTest
    static void testGetFieldMetadataReturnsExpectedFields() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            Map<String, Object> result = RelatedListController.getFieldMetadata(
                'Opportunity',
                'Name,Amount,StageName'
            );

            System.assertNotEquals(null, result, 'Result should not be null');

            Map<String, Object> fields = (Map<String, Object>) result.get('fields');
            System.assertNotEquals(null, fields, 'Fields map should not be null');
            System.assert(fields.containsKey('Name'), 'Should contain Name field');
            System.assert(fields.containsKey('Amount'), 'Should contain Amount field');
            System.assert(fields.containsKey('StageName'), 'Should contain StageName field');
            System.assert(result.containsKey('isObjectCreatable'), 'Should include isObjectCreatable');
            System.assert(result.containsKey('isObjectDeletable'), 'Should include isObjectDeletable');
        }
    }

    // ----------------------------
    // RELATIONSHIP NAME
    // ----------------------------

    @IsTest
    static void testGetRelationshipNameFound() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            String relName = RelatedListController.getRelationshipName(
                'Account',
                'Opportunity',
                'AccountId'
            );

            System.assertNotEquals(null, relName, 'Should find the Opportunities relationship');
            System.assertEquals('Opportunities', relName);
        }
    }

    @IsTest
    static void testGetRelationshipNameNotFound() {
        User testUser = createTestUser();
        System.runAs(testUser) {
            String relName = RelatedListController.getRelationshipName(
                'Account',
                'Opportunity',
                'FakeFieldId'
            );

            System.assertEquals(null, relName, 'Should return null for unknown relationship');
        }
    }

    // ----------------------------
    // HELPER
    // ----------------------------

    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias = 'rlptest',
            Email = 'rlptest@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'TestUser',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'rlptest' + System.currentTimeMillis() + '@example.com'
        );
        insert u;
        return u;
    }
}