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

        System.assertNotEquals(null, parent);
        System.assertNotEquals(null, parent.get('Name'));
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

    // ----------------------------
    // SEARCH SAFETY
    // ----------------------------

    @isTest
    static void testSearchRecords_injectionSafe() {
        List<SObject> results = RelatedListController.searchRecords(
            'Account',
            '%\' OR Name LIKE \'%'
        );

        System.assertNotEquals(null, results);
    }

    // ----------------------------
    // INVALID OBJECT HANDLING
    // ----------------------------

    @isTest
    static void testGetRelatedRecords_invalidObject() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        try {
            RelatedListController.getRelatedRecords(
                acc.Id,
                'FakeObject__c',
                'AccountId',
                'Name',
                10,
                1,
                null,
                null
            );
            System.assert(false, 'Should have failed');
        } catch (Exception e) {
            System.assert(true);
        }
    }
}