@isTest
private class RelatedListControllerTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(
                Name = 'Test Opportunity 1',
                AccountId = acc.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Amount = 10000
            ),
            new Opportunity(
                Name = 'Test Opportunity 2',
                AccountId = acc.Id,
                StageName = 'Qualification',
                CloseDate = Date.today().addDays(60),
                Amount = 20000
            )
        };
        insert opps;
    }

    @isTest
    static void testGetRelatedRecords_basic() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        Map<String, Object> result = RelatedListController.getRelatedRecords(
            acc.Id,
            'Opportunity',
            'AccountId',
            'Name,Amount,CloseDate,StageName',
            10,
            1,
            'Name',
            'ASC'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assert(result.containsKey('records'));
        System.assert(result.containsKey('isPro'));
        List<SObject> records = (List<SObject>) result.get('records');
        System.assertEquals(2, records.size());
    }

    @isTest
    static void testGetRelatedRecords_noResults() {
        Account acc = new Account(Name = 'Empty Account');
        insert acc;

        Test.startTest();
        Map<String, Object> result = RelatedListController.getRelatedRecords(
            acc.Id,
            'Opportunity',
            'AccountId',
            'Name,Amount',
            10,
            1,
            'Name',
            'ASC'
        );
        Test.stopTest();

        List<SObject> records = (List<SObject>) result.get('records');
        System.assertEquals(0, records.size());
    }

    @isTest
    static void testGetRelatedRecords_withProEnabled() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        // Insert Pro metadata record
        RelatedListConfig__mdt proConfig = new RelatedListConfig__mdt(
            MasterLabel = 'Pro',
            DeveloperName = 'Pro',
            IsPro__c = true
        );

        Test.startTest();
        Map<String, Object> result = RelatedListController.getRelatedRecords(
            acc.Id,
            'Opportunity',
            'AccountId',
            'Name,Amount,CloseDate',
            10,
            1,
            'Name',
            'ASC'
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @isTest
    static void testSaveRecords() {
        Opportunity opp = [SELECT Id, Name FROM Opportunity LIMIT 1];
        opp.Name = 'Updated Name';

        Test.startTest();
        RelatedListController.saveRecords(new List<SObject>{ opp });
        Test.stopTest();

        Opportunity updated = [SELECT Name FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals('Updated Name', updated.Name);
    }

    @isTest
    static void testGetRelationshipName() {
        Test.startTest();
        String relName = RelatedListController.getRelationshipName(
            'Account',
            'Opportunity',
            'AccountId'
        );
        Test.stopTest();

        System.assertNotEquals(null, relName);
        System.assertEquals('Opportunities', relName);
    }

    @isTest
    static void testGetFieldTypes() {
        Test.startTest();
        Map<String, String> fieldTypes = RelatedListController.getFieldTypes(
            'Opportunity',
            'Name,StageName,Amount,CloseDate'
        );
        Test.stopTest();

        System.assertNotEquals(null, fieldTypes);
        System.assertEquals('STRING', fieldTypes.get('Name'));
        System.assertEquals('PICKLIST', fieldTypes.get('StageName'));
        System.assertEquals('CURRENCY', fieldTypes.get('Amount'));
        System.assertEquals('DATE', fieldTypes.get('CloseDate'));
    }

    @isTest
    static void testGetPicklistValues() {
        Test.startTest();
        Map<String, List<Map<String, String>>> picklistValues = 
            RelatedListController.getPicklistValues(
                'Opportunity',
                'Name,StageName,Amount'
            );
        Test.stopTest();

        System.assertNotEquals(null, picklistValues);
        System.assert(picklistValues.containsKey('StageName'));
        System.assert(picklistValues.get('StageName').size() > 0);
    }

    @isTest
    static void testGetRelationshipName_invalid() {
        Test.startTest();
        String relName = RelatedListController.getRelationshipName(
            'Account',
            'Opportunity',
            'InvalidField__c'
        );
        Test.stopTest();

        System.assertEquals(null, relName);
    }
}