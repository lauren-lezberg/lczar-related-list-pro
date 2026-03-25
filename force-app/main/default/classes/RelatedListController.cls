public with sharing class RelatedListController {

    @TestVisible static Boolean isProOverride;

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
        Boolean isPro = isProOverride != null 
            ? isProOverride 
            : RelatedListConfig__mdt.getInstance('Pro') != null;

        // Free tier row limit
        Integer rowLimit = isPro ? (pageSize != null ? pageSize : 50) : 10;
        Integer offset = isPro && pageNumber != null ? (pageNumber - 1) * rowLimit : 0;

        // Get SObjectType and check object-level read access
        Schema.SObjectType childType = Schema.getGlobalDescribe().get(objectApiName);
        if (childType == null || !childType.getDescribe().isAccessible()) {
            return null;
        }

        // Build list of fields that the user can read
        Map<String, Schema.SObjectField> fieldMap = childType.getDescribe().fields.getMap();
        List<String> queryFields = new List<String>{ 'Id' };

        for (String field : fieldsString.split(',')) {
            String trimmed = field.trim();
            Schema.SObjectField sField = fieldMap.get(trimmed);

            if (sField != null && sField.getDescribe().isAccessible()) {
                queryFields.add(trimmed);

                // For lookup fields, include the Name if accessible
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

        // Build dynamic query
        String query = 'SELECT ' + fieldList +
            ' FROM ' + objectApiName +
            ' WHERE ' + parentFieldApiName + ' = :recordId';

        if (isPro && sortField != null && sortDirection != null) {
            if (fieldMap.containsKey(sortField) && 
                fieldMap.get(sortField).getDescribe().isAccessible() &&
                (sortDirection == 'ASC' || sortDirection == 'DESC')) {
                query += ' ORDER BY ' + sortField + ' ' + sortDirection;
            }
        }

        query += ' LIMIT ' + rowLimit;

        if (isPro && offset > 0) {
            query += ' OFFSET ' + offset;
        }

        // Execute query
        List<SObject> records = Database.query(query);

        // Total count only in Pro mode
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
        if (records == null || records.isEmpty()) return;
    
        // Verify user has edit access to the object
        String objectName = records[0].getSObjectType().getDescribe().getName();
        if (!Schema.getGlobalDescribe().get(objectName).getDescribe().isUpdateable()) {
            throw new AuraHandledException('You do not have permission to edit these records.');
        }
        
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
        Map<String, Object> fields = new Map<String, Object>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) return result;

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null) continue;

            Schema.DescribeFieldResult fieldDescribe = sObjectField.getDescribe();
            if (!fieldDescribe.isAccessible()) continue;

            Map<String, Object> fieldInfo = new Map<String, Object>{
                'type' => String.valueOf(fieldDescribe.getType()),
                'accessible' => true,
                'editable' => fieldDescribe.isUpdateable(),
                'label' => fieldDescribe.getLabel()
            };

            // Picklist values
            if (fieldDescribe.getType() == Schema.DisplayType.PICKLIST ||
                fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST) {
                List<Map<String, String>> picklistValues = new List<Map<String, String>>();
                for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                    if (entry.isActive()) {
                        picklistValues.add(new Map<String, String>{
                            'label' => entry.getLabel(),
                            'value' => entry.getValue()
                        });
                    }
                }
                fieldInfo.put('picklistValues', picklistValues);
            }

            // Lookup target
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> refs = fieldDescribe.getReferenceTo();
                if (!refs.isEmpty()) {
                    fieldInfo.put('lookupTarget', refs[0].getDescribe().getName());
                }
            }

            fields.put(trimmedField, fieldInfo);
        }

        result.put('fields', fields);

        Boolean isObjectCreatable = objectType.getDescribe().isCreateable();
        result.put('isObjectCreatable', isObjectCreatable);

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<SObject> searchRecords(String objectApiName, String searchTerm) {
        String query = 'SELECT Id, Name FROM ' + objectApiName + 
            ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\' LIMIT 10';
        return Database.query(query);
    }
}