import { LightningElement, api, track } from 'lwc';
import searchRecords from '@salesforce/apex/RelatedListController.searchRecords';

export default class LookupEditCell extends LightningElement {
    @api columnLabel;
    @api typeAttributes = {};
    @track displayValue = '';
    @track searchResults = [];
    @track showDropdown = false;
    @track isSearching = false;
    _value;
    _searchTimeout;

    @api
    get editedValue() {
        return this._value;
    }
    set editedValue(val) {
        this._value = val;
    }

    // This is what the datatable reads on save
    @api
    get value() {
        return this._value;
    }

    connectedCallback() {
        this.displayValue = this.typeAttributes.displayValue || '';
        this._value = this.typeAttributes.value || '';
    }

    get objectApiName() {
        return this.typeAttributes.objectApiName;
    }

    get hasResults() {
        return this.searchResults.length > 0;
    }

    @api
    get validity() {
        return { valid: true, valueMissing: false };
    }

    @api
    showHelpMessageIfInvalid() {}

    handleFocus() {
        if (this.displayValue && this.displayValue.length >= 2) {
            this.handleSearch(this.displayValue);
        }
    }

    handleInputChange(event) {
        const searchTerm = event.target.value;
        this.displayValue = searchTerm;

        if (this._searchTimeout) clearTimeout(this._searchTimeout);

        if (searchTerm.length < 2) {
            this.showDropdown = false;
            return;
        }

        this._searchTimeout = setTimeout(() => {
            this.handleSearch(searchTerm);
        }, 300);
    }

    handleSearch(searchTerm) {
        this.isSearching = true;
        this.showDropdown = true;

        searchRecords({
            objectApiName: this.objectApiName,
            searchTerm: searchTerm
        })
        .then(results => {
            this.searchResults = results;
            this.isSearching = false;
        })
        .catch(() => {
            this.searchResults = [];
            this.isSearching = false;
        });
    }

    handleSelect(event) {
        const selectedId = event.currentTarget.dataset.id;
        const selectedName = event.currentTarget.dataset.name;
        
        this._value = selectedId;
        this.displayValue = selectedName;
        this.showDropdown = false;

        // Dispatch with both ID and name
        this.dispatchEvent(new CustomEvent('lookupselect', {
            bubbles: true,
            composed: true,
            detail: { 
                fieldName: this.typeAttributes.fieldName,
                value: selectedId,
                displayName: selectedName,
                rowId: this.typeAttributes.rowId
            }
        }));

        // Also dispatch change for datatable draft values
        this.dispatchEvent(new CustomEvent('change', {
            bubbles: true,
            composed: true,
            detail: { value: selectedId }
        }));
    }
}