public without sharing class RelatedListController {

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getRelatedRecords(
        Id recordId,
        String objectApiName,
        String parentFieldApiName,
        String fieldsString,
        Integer pageSize,
        Integer pageNumber,
        String sortField,
        String sortDirection
    ) {
        Boolean isPro = RelatedListConfig__mdt.getInstance('Pro') != null;

        // Free tier row limit
        Integer rowLimit = isPro ? (pageSize != null ? pageSize : 50) : 10;
        Integer offset = isPro && pageNumber != null ? (pageNumber - 1) * rowLimit : 0;

        // Build field list including lookup name fields
        List<String> fields = fieldsString.split(',');
        List<String> queryFields = new List<String>{ 'Id' };

        Schema.SObjectType childType = Schema.getGlobalDescribe().get(objectApiName);
        Map<String, Schema.SObjectField> fieldMap = childType != null ?
            childType.getDescribe().fields.getMap() :
            new Map<String, Schema.SObjectField>();

        for (String field : fields) {
            String trimmed = field.trim();
            queryFields.add(trimmed);

            // For lookup fields, also query the Name field via relationship
            Schema.SObjectField sField = fieldMap.get(trimmed);
            if (sField != null) {
                Schema.DescribeFieldResult fieldDescribe = sField.getDescribe();
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                    String relationshipName = fieldDescribe.getRelationshipName();
                    if (relationshipName != null) {
                        queryFields.add(relationshipName + '.Name');
                    }
                }
            }
        }

        String fieldList = String.join(queryFields, ', ');

        // Build query
        String query = 'SELECT ' + fieldList +
            ' FROM ' + objectApiName +
            ' WHERE ' + parentFieldApiName + ' = :recordId';

        if (isPro && sortField != null && sortDirection != null) {
            query += ' ORDER BY ' + sortField + ' ' + sortDirection;
        }

        query += ' LIMIT ' + rowLimit;

        if (isPro && offset > 0) {
            query += ' OFFSET ' + offset;
        }

        List<SObject> records = Database.query(query);

        // Get total count for pagination
        Integer totalCount = 0;
        if (isPro) {
            String countQuery = 'SELECT COUNT() FROM ' + objectApiName +
                ' WHERE ' + parentFieldApiName + ' = :recordId';
            totalCount = Database.countQuery(countQuery);
        }

        return new Map<String, Object>{
            'records' => records,
            'isPro' => isPro,
            'totalCount' => totalCount,
            'rowLimit' => rowLimit
        };
    }

    @AuraEnabled
    public static void saveRecords(List<SObject> records) {
        update records;
    }

    @AuraEnabled(cacheable=true)
    public static String getRelationshipName(String parentObjectApiName, String childObjectApiName, String parentFieldApiName) {
        Schema.DescribeSObjectResult parentDescribe = Schema.getGlobalDescribe()
            .get(parentObjectApiName)
            .getDescribe();
        
        for (Schema.ChildRelationship rel : parentDescribe.getChildRelationships()) {
            if (rel.getChildSObject().getDescribe().getName() == childObjectApiName
                && String.valueOf(rel.getField()) == parentFieldApiName) {
                return rel.getRelationshipName();
            }
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getPicklistValues(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) return result;
        
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        
        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null) continue;
            
            Schema.DescribeFieldResult fieldDescribe = sObjectField.getDescribe();
            Schema.DisplayType fieldType = fieldDescribe.getType();
            
            if (fieldType == Schema.DisplayType.PICKLIST || 
                fieldType == Schema.DisplayType.MULTIPICKLIST) {
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                    if (entry.isActive()) {
                        values.add(new Map<String, String>{
                            'label' => entry.getLabel(),
                            'value' => entry.getValue()
                        });
                    }
                }
                result.put(trimmedField, values);
            }
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFieldTypes(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, String> result = new Map<String, String>();
        
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) return result;
        
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        
        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null) continue;
            
            Schema.DisplayType fieldType = sObjectField.getDescribe().getType();
            result.put(trimmedField, String.valueOf(fieldType));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFieldMetadata(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, String> fieldTypes = new Map<String, String>();
        Map<String, String> lookupTargets = new Map<String, String>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) return result;

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null) continue;

            Schema.DescribeFieldResult fieldDescribe = sObjectField.getDescribe();
            Schema.DisplayType fieldType = fieldDescribe.getType();
            fieldTypes.put(trimmedField, String.valueOf(fieldType));

            if (fieldType == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> refs = fieldDescribe.getReferenceTo();
                if (!refs.isEmpty()) {
                    lookupTargets.put(trimmedField, refs[0].getDescribe().getName());
                }
            }
        }

        result.put('fieldTypes', fieldTypes);
        result.put('lookupTargets', lookupTargets);
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<SObject> searchRecords(String objectApiName, String searchTerm) {
        String query = 'SELECT Id, Name FROM ' + objectApiName + 
            ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\' LIMIT 10';
        return Database.query(query);
    }
}