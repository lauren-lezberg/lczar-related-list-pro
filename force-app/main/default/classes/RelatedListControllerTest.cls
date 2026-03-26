@isTest
private class RelatedListControllerTest {

    @testSetup
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
    // FREE MODE TESTS
    // ----------------------------

    @isTest
    static void testFreeMode_limitEnforced() {
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

    @isTest
    static void testFreeMode_ignoresPagination() {
        RelatedListController.isProOverride = false;

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> result = RelatedListController.getRelatedRecords(
            acc.Id,
            'Opportunity',
            'AccountId',
            'Name',
            10,
            3, // should be ignored
            null,
            null
        );

        List<SObject> records = (List<SObject>) result.get('records');

        System.assertEquals(10, records.size());
    }

    // ----------------------------
    // PRO MODE TESTS
    // ----------------------------

    @isTest
    static void testProMode_paginationWorks() {
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

    @isTest
    static void testProMode_sortingWorks() {
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

    // ----------------------------
    // LOOKUP FIELD TEST
    // ----------------------------

    @isTest
    static void testLookupField_includesName() {
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

    // ----------------------------
    // SAVE (BULK)
    // ----------------------------

    @isTest
    static void testSaveRecords_bulkUpdate() {
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

    @isTest
    static void testSaveRecords_emptyList() {
        // Should return without error
        Test.startTest();
        RelatedListController.saveRecords(new List<SObject>());
        Test.stopTest();
        System.assert(true, 'Empty list should not throw');
    }

    // ----------------------------
    // DELETE
    // ----------------------------

    @isTest
    static void testDeleteRecord_success() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        Id oppId = opp.Id;

        Test.startTest();
        RelatedListController.deleteRecord(oppId);
        Test.stopTest();

        List<Opportunity> remaining = [SELECT Id FROM Opportunity WHERE Id = :oppId];
        System.assertEquals(0, remaining.size(), 'Record should have been deleted');
    }

    @isTest
    static void testDeleteRecord_nullId() {
        try {
            RelatedListController.deleteRecord(null);
            System.assert(false, 'Should have thrown an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Exception message should not be null');
        }
    }

    // ----------------------------
    // SEARCH SAFETY
    // ----------------------------

    @isTest
    static void testSearchRecords_injectionSafe() {
        List<SObject> results = RelatedListController.searchRecords(
            'Account',
            '%\' OR Name LIKE \'%'
        );

        System.assertNotEquals(null, results, 'Results should not be null');
        System.assertEquals(0, results.size(), 'Injection attempt should return no results');
    }

    @isTest
    static void testSearchRecords_invalidObject() {
        try {
            RelatedListController.searchRecords('FakeObject__c', 'test');
            System.assert(false, 'Should have thrown an AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage() != null, 'Exception message should not be null');
        }
    }

    // ----------------------------
    // INVALID PARENT FIELD
    // ----------------------------

    @isTest
    static void testGetRelatedRecords_invalidParentField() {
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

    // ----------------------------
    // PAGE SIZE CAP
    // ----------------------------

    @isTest
    static void testProMode_pageSizeCapped() {
        RelatedListController.isProOverride = true;

        Account acc = [SELECT Id FROM Account LIMIT 1];

        Map<String, Object> result = RelatedListController.getRelatedRecords(
            acc.Id,
            'Opportunity',
            'AccountId',
            'Name',
            99999, // should be capped to MAX_PAGE_SIZE
            1,
            null,
            null
        );

        Integer rowLimit = (Integer) result.get('rowLimit');
        System.assert(rowLimit <= 200, 'Row limit should be capped at MAX_PAGE_SIZE');
    }

    // ----------------------------
    // INVALID OBJECT HANDLING
    // ----------------------------

    @isTest
    static void testGetRelatedRecords_invalidObject() {
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

    // ----------------------------
    // FIELD METADATA
    // ----------------------------

    @isTest
    static void testGetFieldMetadata_returnsExpectedFields() {
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

    // ----------------------------
    // RELATIONSHIP NAME
    // ----------------------------

    @isTest
    static void testGetRelationshipName_found() {
        String relName = RelatedListController.getRelationshipName(
            'Account',
            'Opportunity',
            'AccountId'
        );

        System.assertNotEquals(null, relName, 'Should find the Opportunities relationship');
        System.assertEquals('Opportunities', relName);
    }

    @isTest
    static void testGetRelationshipName_notFound() {
        String relName = RelatedListController.getRelationshipName(
            'Account',
            'Opportunity',
            'FakeFieldId'
        );

        System.assertEquals(null, relName, 'Should return null for unknown relationship');
    }
}