import LightningDatatable from 'lightning/datatable';
import picklistCellTemplate from './picklistCellTemplate.html';
import picklistEditTemplate from './picklistEditTemplate.html';
import lookupCellTemplate from './lookupCellTemplate.html';
import lookupEditTemplate from './lookupEditTemplate.html';

export default class CustomDatatable extends LightningDatatable {
    static customTypes = {
        customPicklist: {
            template: picklistCellTemplate,
            editTemplate: picklistEditTemplate,
            standardCellLayout: true,
            typeAttributes: ['options', 'value', 'rowId', 'fieldName']
        },
        customLookup: {
            template: lookupCellTemplate,
            editTemplate: lookupEditTemplate,
            standardCellLayout: true,
            typeAttributes: ['objectApiName', 'value', 'rowId', 'fieldName', 'displayValue']
        }
    };
}