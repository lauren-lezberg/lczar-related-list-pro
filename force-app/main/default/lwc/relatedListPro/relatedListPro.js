import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getRelatedRecords from '@salesforce/apex/RelatedListController.getRelatedRecords';
import getRelationshipName from '@salesforce/apex/RelatedListController.getRelationshipName';
import saveRecords from '@salesforce/apex/RelatedListController.saveRecords';
import getFieldMetadata from '@salesforce/apex/RelatedListController.getFieldMetadata';
import lczarLogo from '@salesforce/resourceUrl/lczarLabsLogo';

export default class RelatedListPro extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api childObjectApiName;
    @api parentFieldApiName;
    @api fieldsString;
    @api componentTitle = 'Related Records';
    @api objectIconName = 'standard:related_list';
    @api pageSize = 10;

    @track records = [];
    @track columns = [];
    @track draftValues = [];
    @track isLoading = true;
    @track isPro = false;
    @track totalCount = 0;
    @track pageNumber = 1;
    @track sortField = 'Name';
    @track sortDirection = 'ASC';
    @track relationshipName;
    @track logoUrl = lczarLogo;
    @track searchTerm = '';
    @track filteredRecords = [];
    @track lookupDisplayNames = {};
    @track fieldMetadata = {};
    @track isObjectCreatable = true;
    @track hideComponent = false;
    @track showNewButton = false;

    connectedCallback() {
        this.loadRelationshipName();
        this.loadFieldMetadataFirst();
    }

    loadFieldMetadataFirst() {
        if (!this.childObjectApiName || !this.fieldsString) return;

        getFieldMetadata({
            objectApiName: this.childObjectApiName,
            fieldsString: this.fieldsString
        })
        .then(result => {
            this.fieldMetadata = result.fields || {};
            this.hideComponent
            this.isObjectCreatable = result.isObjectCreatable !== false;
            this.loadRecords();
        })
        .catch(error => {
            const message = error?.body?.message || error?.message || '';
            if (message.includes('not have access to the Apex class')) {
                this.hideComponent = true;
                this.isLoading = false;
            } else {
                console.error('Error loading field metadata:', error);
                this.loadRecords();
            }
        });
    }

    loadRelationshipName() {
        getRelationshipName({
            parentObjectApiName: this.objectApiName,
            childObjectApiName: this.childObjectApiName,
            parentFieldApiName: this.parentFieldApiName
        })
        .then(result => {
            this.relationshipName = result;
        })
        .catch(() => {
            this.relationshipName = null;
        });
    }

    loadRecords() {
        this.isLoading = true;
        getRelatedRecords({
            recordId: this.recordId,
            objectApiName: this.childObjectApiName,
            parentFieldApiName: this.parentFieldApiName,
            fieldsString: this.fieldsString,
            pageSize: this.pageSize,
            pageNumber: this.pageNumber,
            sortField: this.sortField,
            sortDirection: this.sortDirection
        })
        .then(result => {
            if (result === null) {
                this.hideComponent = true;
                this.isLoading = false;
                return;
            }
            this.records = result.records.map(record => {
                const mapped = { ...record, recordUrl: '/' + record.Id };
                Object.keys(this.fieldMetadata).forEach(field => {
                    const meta = this.fieldMetadata[field];
                    if (meta && meta.type === 'REFERENCE') {
                        const relationshipName = field.endsWith('Id') 
                            ? field.slice(0, -2) 
                            : field.replace('__c', '__r');
                        if (record[relationshipName] && record[relationshipName].Name) {
                            mapped[field + '_Name'] = record[relationshipName].Name;
                        }
                    }
                });
                return mapped;
            });
            this.isPro = result.isPro;
            this.totalCount = result.totalCount;
            this.columns = this.buildColumns();
            this.isLoading = false;
            this.applyFilter();
        })
        .catch(error => {
            const message = error?.body?.message || error?.message || 'An unexpected error occurred';
            this.showToast('Error', message, 'error');
            this.isLoading = false;
        });
    }

    cleanLabel(label, fieldType, trimmed) {
        if (fieldType === 'REFERENCE') {
            // Remove " ID" suffix from standard lookups e.g. "Account ID" -> "Account"
            if (label.endsWith(' ID')) {
                return label.slice(0, -3);
            }
            // Remove "Id" suffix from custom lookups e.g. "My Object Id" -> "My Object"
            if (label.endsWith(' Id')) {
                return label.slice(0, -3);
            }
        }
        return label;
    }

    buildColumns() {
        if (!this.fieldsString) return [];
        return this.fieldsString.split(',').map((field, index) => {
            const trimmed = field.trim();
            const meta = this.fieldMetadata[trimmed];

            // First field is always the name/link column
            if (index === 0) {
                return {
                    label: meta ? meta.label : trimmed,
                    fieldName: 'recordUrl',
                    type: 'url',
                    typeAttributes: {
                        label: { fieldName: trimmed },
                        target: '_self'
                    },
                    sortable: this.isPro,
                    initialWidth: 200
                };
            }

            // Skip inaccessible fields
            if (!meta) return null;

            const label = meta.label;
            const editable = meta.editable;
            const fieldType = meta.type;

            // Picklist
            if (fieldType === 'PICKLIST' || fieldType === 'MULTIPICKLIST') {
                if (this.isPro && meta.picklistValues) {
                    return {
                        label,
                        fieldName: trimmed,
                        type: 'customPicklist',
                        typeAttributes: {
                            options: meta.picklistValues,
                            value: { fieldName: trimmed },
                            rowId: { fieldName: 'Id' },
                            fieldName: trimmed
                        },
                        editable: editable && this.isPro,
                        sortable: this.isPro
                    };
                }
                return { label, fieldName: trimmed, type: 'text', editable: false, sortable: false };
            }

            // Lookup
            if (fieldType === 'REFERENCE' && meta.lookupTarget) {
                const cleanedLabel = this.cleanLabel(label, fieldType, trimmed);
                if (this.isPro) {
                    return {
                        label: cleanedLabel,
                        fieldName: trimmed,
                        type: 'customLookup',
                        typeAttributes: {
                            objectApiName: meta.lookupTarget,
                            fieldName: trimmed,
                            value: { fieldName: trimmed },
                            rowId: { fieldName: 'Id' },
                            displayValue: { fieldName: trimmed + '_Name' }
                        },
                        editable: editable && this.isPro,
                        sortable: this.isPro
                    };
                }
                return { label: cleanedLabel, fieldName: trimmed + '_Name', type: 'text', editable: false, sortable: false };
            }

            // Currency
            if (fieldType === 'CURRENCY') {
                return { label, fieldName: trimmed, type: 'currency', typeAttributes: { currencyCode: 'USD' }, sortable: this.isPro, editable };
            }

            // Date
            if (fieldType === 'DATE') {
                return { label, fieldName: trimmed, type: 'date', typeAttributes: { year: 'numeric', month: 'numeric', day: 'numeric' }, sortable: this.isPro, editable };
            }

            // DateTime
            if (fieldType === 'DATETIME') {
                return { label, fieldName: trimmed, type: 'date', typeAttributes: { year: 'numeric', month: 'numeric', day: 'numeric', hour: '2-digit', minute: '2-digit' }, sortable: this.isPro, editable };
            }

            // Phone
            if (fieldType === 'PHONE') {
                return { label, fieldName: trimmed, type: 'phone', sortable: this.isPro, editable };
            }

            // Email
            if (fieldType === 'EMAIL') {
                return { label, fieldName: trimmed, type: 'email', sortable: this.isPro, editable };
            }

            // Percent
            if (fieldType === 'PERCENT') {
                return { label, fieldName: trimmed, type: 'percent', sortable: this.isPro, editable };
            }

            // Boolean
            if (fieldType === 'BOOLEAN') {
                return { label, fieldName: trimmed, type: 'boolean', sortable: this.isPro, editable };
            }

            // Default text
            return { label, fieldName: trimmed, type: 'text', editable, sortable: this.isPro };

        }).filter(col => col !== null);
    }

    handleSave(event) {
        const updatedFields = event.detail.draftValues;
        saveRecords({ records: updatedFields })
            .then(() => {
                this.showToast('Success', 'Records updated successfully', 'success');
                this.draftValues = [];
                this.lookupDisplayNames = {};
                this.loadRecords();
            })
            .catch(error => {
                const message = error?.body?.message || error?.message || 'An unexpected error occurred';
                this.showToast('Error', message, 'error');
                this.isLoading = false;
            });
    }

    handleSort(event) {
        if (!this.isPro) return;
        const fieldName = event.detail.fieldName;
        const actualField = fieldName === 'recordUrl' 
            ? this.fieldsString.split(',')[0].trim() 
            : fieldName;
        if (actualField === this.sortField) {
            this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        } else {
            this.sortField = actualField;
            this.sortDirection = 'ASC';
        }
        this.loadRecords();
    }

    handleNew() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: this.childObjectApiName,
                actionName: 'new'
            },
            state: {
                defaultFieldValues: encodeDefaultFieldValues({
                    [this.parentFieldApiName]: this.recordId
                })
            }
        });
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber--;
            this.loadRecords();
        }
    }

    handleNext() {
        if (this.pageNumber < this.totalPages) {
            this.pageNumber++;
            this.loadRecords();
        }
    }

    get totalPages() {
        return Math.ceil(this.totalCount / this.pageSize);
    }

    get hasPrevious() {
        return this.pageNumber <= 1;
    }

    get hasNext() {
        return this.pageNumber >= this.totalPages;
    }

    get showPagination() {
        return this.isPro && this.totalCount > this.pageSize;
    }

    get displayRecords() {
        const base = this.searchTerm ? this.filteredRecords : this.records;
        if (Object.keys(this.lookupDisplayNames).length === 0) return base;
        return base.map(record => {
            const updated = { ...record };
            Object.keys(this.fieldMetadata).forEach(field => {
                const meta = this.fieldMetadata[field];
                if (meta && meta.type === 'REFERENCE') {
                    const key = `${record.Id}_${field}`;
                    if (this.lookupDisplayNames[key]) {
                        updated[field + '_Name'] = this.lookupDisplayNames[key];
                    }
                }
            });
            return updated;
        });
    }

    get hasRecords() {
        return this.displayRecords.length > 0;
    }

    get noRecords() {
        return !this.isLoading && this.displayRecords.length === 0;
    }

    get recordCountSuffix() {
        return this.displayRecords.length === 1 ? '' : 's';
    }

    handleViewAll() {
        if (this.relationshipName) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordRelationshipPage',
                attributes: {
                    recordId: this.recordId,
                    objectApiName: this.objectApiName,
                    relationshipApiName: this.relationshipName,
                    actionName: 'view'
                }
            });
        }
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.applyFilter();
    }

    applyFilter() {
        if (!this.searchTerm) {
            this.filteredRecords = this.records;
            return;
        }
        const lowerSearch = this.searchTerm.toLowerCase();
        this.filteredRecords = this.records.filter(record => {
            return this.fieldsString.split(',').some(field => {
                const value = record[field.trim()];
                return value && String(value).toLowerCase().includes(lowerSearch);
            });
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleCellChange(event) {
        const draftValues = event.detail.draftValues;
        this.records = this.records.map(record => {
            const draft = draftValues.find(d => d.Id === record.Id);
            return draft ? { ...record, ...draft } : record;
        });
        this.draftValues = draftValues;
        this.applyFilter();
    }

    handleLookupSelect(event) {
        const { fieldName, value, displayName, rowId } = event.detail;
        const key = `${rowId}_${fieldName}`;
        this.lookupDisplayNames = { ...this.lookupDisplayNames, [key]: displayName };
    }

}