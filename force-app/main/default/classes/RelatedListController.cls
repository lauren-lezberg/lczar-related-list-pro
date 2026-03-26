public with sharing class RelatedListController {

    @TestVisible static Boolean isProOverride;

    // Maximum rows returnable in Pro mode regardless of configured page size
    private static final Integer MAX_PAGE_SIZE = 200;

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

        // Cap page size to prevent runaway queries
        Integer safePageSize = (pageSize != null && pageSize > 0)
            ? Math.min(pageSize, MAX_PAGE_SIZE)
            : 50;

        // Free tier row limit
        Integer rowLimit = isPro ? safePageSize : 10;
        Integer offset = isPro && pageNumber != null ? (pageNumber - 1) * rowLimit : 0;

        // Get SObjectType and check object-level read access
        Schema.SObjectType childType = Schema.getGlobalDescribe().get(objectApiName);
        if (childType == null || !childType.getDescribe().isAccessible()) {
            return null;
        }

        // Validate parentFieldApiName exists on the object before using in query
        Map<String, Schema.SObjectField> fieldMap = childType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(parentFieldApiName)) {
            throw new AuraHandledException('Invalid parent field: ' + parentFieldApiName);
        }

        // Build list of fields that the user can read
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

        // Build dynamic query — objectApiName and parentFieldApiName are
        // both validated against Schema above so safe to interpolate
        String query = 'SELECT ' + fieldList +
            ' FROM ' + objectApiName +
            ' WHERE ' + parentFieldApiName + ' = :recordId';

        if (sortField != null && sortDirection != null &&
            fieldMap.containsKey(sortField) && 
            fieldMap.get(sortField).getDescribe().isAccessible() &&
            (sortDirection == 'ASC' || sortDirection == 'DESC')) {
            query += ' ORDER BY ' + sortField + ' ' + sortDirection + ' NULLS LAST';
        } else if (fieldMap.containsKey('Name') && fieldMap.get('Name').getDescribe().isAccessible()) {
            // Safe default — keeps free and pro showing the same records
            query += ' ORDER BY Name ASC NULLS LAST';
        } else {
            // Objects without Name (e.g. Task) fall back to CreatedDate
            query += ' ORDER BY CreatedDate ASC NULLS LAST';
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

        Schema.SObjectType objectType = records[0].getSObjectType();
        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();

        // Check object-level update access
        if (!objectDescribe.isUpdateable()) {
            throw new AuraHandledException('You do not have permission to edit these records.');
        }

        // Check field-level security for every field being updated
        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();
        for (SObject record : records) {
            Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
            for (String fieldName : populatedFields.keySet()) {
                if (fieldName == 'Id') continue;
                Schema.SObjectField sField = fieldMap.get(fieldName);
                if (sField == null || !sField.getDescribe().isUpdateable()) {
                    throw new AuraHandledException(
                        'You do not have permission to edit the field: ' + fieldName
                    );
                }
            }
        }

        update records;
    }

    @AuraEnabled
    public static void deleteRecord(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID is required.');
        }

        Schema.SObjectType objectType = recordId.getSObjectType();
        if (objectType == null) {
            throw new AuraHandledException('Could not determine object type for this record.');
        }

        if (!objectType.getDescribe().isDeletable()) {
            throw new AuraHandledException('You do not have permission to delete this record.');
        }

        SObject record = objectType.newSObject(recordId);
        delete record;
    }

    @AuraEnabled(cacheable=true)
    public static String getRelationshipName(String parentObjectApiName, String childObjectApiName, String parentFieldApiName) {
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectApiName);
        if (parentType == null) return null;

        for (Schema.ChildRelationship rel : parentType.getDescribe().getChildRelationships()) {
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
        if (objectType == null || !objectType.getDescribe().isAccessible()) return result;
        
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        
        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null || !sObjectField.getDescribe().isAccessible()) continue;
            
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
        if (objectType == null || !objectType.getDescribe().isAccessible()) return result;
        
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        
        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null || !sObjectField.getDescribe().isAccessible()) continue;
            
            Schema.DisplayType fieldType = sObjectField.getDescribe().getType();
            result.put(trimmedField, String.valueOf(fieldType));
        }
        return result;
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getFieldMetadata(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, Object> result = new Map<String, Object>();
        Map<String, Object> fields = new Map<String, Object>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            result.put('isValid', false);
            return result;
        }

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
        result.put('isValid', true);
        Boolean isObjectCreatable = objectType.getDescribe().isCreateable();
        Boolean isObjectDeletable = objectType.getDescribe().isDeletable();
        result.put('isObjectCreatable', isObjectCreatable);
        result.put('isObjectDeletable', isObjectDeletable);

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<SObject> searchRecords(String objectApiName, String searchTerm) {
        // Validate objectApiName against schema before using in query
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            throw new AuraHandledException('Invalid or inaccessible object: ' + objectApiName);
        }

        // Verify the object has a Name field before querying it
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Name') || !fieldMap.get('Name').getDescribe().isAccessible()) {
            throw new AuraHandledException('Object does not have an accessible Name field.');
        }

        String query = 'SELECT Id, Name FROM ' + objectApiName +
            ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\' LIMIT 10';
        return Database.query(query);
    }
}