/**
 * @description Controller for the Related List Pro LWC component.
 * Provides dynamic SOQL querying, field metadata, picklist values,
 * inline save/delete, and lookup search with full CRUD/FLS enforcement.
 */
public with sharing class RelatedListController {

    @TestVisible static Boolean isProOverride;

    // Maximum rows returnable in Pro mode regardless of configured page size
    private static final Integer MAX_PAGE_SIZE = 200;

    /**
     * @description Validates that a Pro license record exists and contains
     * a license key starting with the expected prefix. This prevents casual
     * circumvention by simply creating the metadata record without a valid key.
     * @return true if Pro is legitimately licensed
     */
    @TestVisible
    private static Boolean isValidProLicense() {
        RelatedListConfig__mdt config = RelatedListConfig__mdt.getInstance('Pro');
        if (config == null) {
            return false;
        }
        String key = (String) config.get('LicenseKey__c');
        return String.isNotBlank(key) && key.startsWith('RLP-');
    }

    /**
     * @description Fetches related records for a given parent record.
     * objectApiName and parentFieldApiName are both validated against
     * Schema.getGlobalDescribe() before use in dynamic SOQL — PMD
     * ApexSOQLInjection findings on these variables are false positives.
     * CRUD/FLS is enforced via isAccessible() checks on the object and
     * every field before inclusion in the query.
     * @param recordId The parent record Id
     * @param objectApiName API name of the child object
     * @param parentFieldApiName Lookup field on child pointing to parent
     * @param fieldsString Comma-separated field API names to query
     * @param pageSize Number of rows per page (Pro only)
     * @param pageNumber Current page number (Pro only)
     * @param sortField Field to sort by (Pro only)
     * @param sortDirection ASC or DESC (Pro only)
     * @return Map containing records, isPro, totalCount, rowLimit
     */
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
            : isValidProLicense();

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
        // both validated against Schema above so safe to interpolate.
        // PMD ApexSOQLInjection findings on lines below are false positives.
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

        // Execute query — CRUD/FLS enforced above via isAccessible()
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

    /**
     * @description Saves a list of SObject records after verifying
     * object-level and field-level update access for each field.
     * PMD ApexCRUDViolation on the update DML is a false positive —
     * isUpdateable() is checked on the object and every populated field above.
     * @param records List of SObjects to update
     */
    @AuraEnabled
    public static void saveRecords(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

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
                if (fieldName == 'Id') {
                    continue;
                }
                Schema.SObjectField sField = fieldMap.get(fieldName);
                if (sField == null || !sField.getDescribe().isUpdateable()) {
                    throw new AuraHandledException(
                        'You do not have permission to edit the field: ' + fieldName
                    );
                }
            }
        }

        // CRUD enforced above — PMD ApexCRUDViolation is a false positive
        update records;
    }

    /**
     * @description Deletes a single record after verifying object-level
     * delete access. PMD ApexCRUDViolation on the delete DML is a false
     * positive — isDeletable() is checked above.
     * @param recordId Id of the record to delete
     */
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

        // CRUD enforced above — PMD ApexCRUDViolation is a false positive
        SObject record = objectType.newSObject(recordId);
        delete record;
    }

    /**
     * @description Returns the relationship API name between a parent and child object.
     * @param parentObjectApiName API name of the parent object
     * @param childObjectApiName API name of the child object
     * @param parentFieldApiName Lookup field on the child
     * @return Relationship name, or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static String getRelationshipName(
        String parentObjectApiName,
        String childObjectApiName,
        String parentFieldApiName
    ) {
        Schema.SObjectType parentType = Schema.getGlobalDescribe().get(parentObjectApiName);
        if (parentType == null) {
            return null;
        }

        for (Schema.ChildRelationship rel : parentType.getDescribe().getChildRelationships()) {
            if (rel.getChildSObject().getDescribe().getName() == childObjectApiName
                && String.valueOf(rel.getField()) == parentFieldApiName) {
                return rel.getRelationshipName();
            }
        }
        return null;
    }

    /**
     * @description Returns active picklist values for specified fields on an object.
     * @param objectApiName API name of the object
     * @param fieldsString Comma-separated field API names
     * @return Map of field name to list of label/value pairs
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getPicklistValues(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return result;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null || !sObjectField.getDescribe().isAccessible()) {
                continue;
            }

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

    /**
     * @description Returns field types for specified fields on an object.
     * @param objectApiName API name of the object
     * @param fieldsString Comma-separated field API names
     * @return Map of field name to display type string
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getFieldTypes(
        String objectApiName,
        String fieldsString
    ) {
        Map<String, String> result = new Map<String, String>();

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null || !objectType.getDescribe().isAccessible()) {
            return result;
        }

        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for (String field : fieldsString.split(',')) {
            String trimmedField = field.trim();
            Schema.SObjectField sObjectField = fieldMap.get(trimmedField);
            if (sObjectField == null || !sObjectField.getDescribe().isAccessible()) {
                continue;
            }

            Schema.DisplayType fieldType = sObjectField.getDescribe().getType();
            result.put(trimmedField, String.valueOf(fieldType));
        }
        return result;
    }

    /**
     * @description Returns rich field metadata including type, editability,
     * label, picklist values, and lookup targets. Also returns object-level
     * createable and deletable flags.
     * @param objectApiName API name of the object
     * @param fieldsString Comma-separated field API names
     * @return Map containing fields metadata and object permissions
     */
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
            if (sObjectField == null) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = sObjectField.getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }

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
        result.put('isObjectCreatable', objectType.getDescribe().isCreateable());
        result.put('isObjectDeletable', objectType.getDescribe().isDeletable());

        return result;
    }

    /**
     * @description Searches for records by Name on a given object.
     * objectApiName is validated against Schema before use in dynamic SOQL —
     * PMD ApexSOQLInjection finding is a false positive.
     * @param objectApiName API name of the object to search
     * @param searchTerm Search string (escaped before use)
     * @return List of matching records with Id and Name
     */
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

        // objectApiName validated above — PMD ApexSOQLInjection is a false positive
        String query = 'SELECT Id, Name FROM ' + objectApiName +
            ' WHERE Name LIKE \'%' + String.escapeSingleQuotes(searchTerm) + '%\' LIMIT 10';
        return Database.query(query);
    }
}