/*
# email_deliverability/services/PTRRecordProcessor       Copyright 2022 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define([], function() {

    "use strict";

    function PTRRecordProcessor() {

        /**
         *
         * @module PTRRecordProcessor
         * @memberof cpanel.emailDeliverability
         *
         */

        /**
         * Get the Validate API call for this Record Processor
         *
         * @method getValidateAPI
         * @public
         *
         * @returns {Object} api call .module and .func
         */
        function _getValidateAPI() {
            return { module: "EmailAuth", func: "validate_current_ptrs" };
        }

        /**
         * Get the Install API call for this Record Processor
         *
         * @method getInstallAPI
         * @public
         *
         * @returns {Object} api call .module and .func
         */
        function _getInstallAPI() {
            throw new Error("ptr does not do install in this interface");
        }

        /**
         * Process an Individual API result item
         *
         * @method processResultItem
         * @public
         *
         * @param {Object} resultItem API result item
         * @returns {Array<Object>} parsed records for the result item
         */
        function _processResultItem(resultItem) {
            var records = [];
            if (resultItem) {
                records = resultItem.records.map(this.parseRecord.bind(this));
            }
            return records;
        }

        /**
         * Process the result items for an API
         *
         * @method processResultItems
         * @public
         *
         * @param {Array<Object>} resultItems
         * @returns {Array<Array>} processed records organized by domain
         */
        function _processResultItems(resultItems) {
            var domainRecords = [];
            resultItems.forEach(function(resultItem) {
                domainRecords.push(this.processResultItem(resultItem));
            }, this);
            return domainRecords;
        }

        /**
         * Parse a record of this processor's type
         *
         * @method parseRecord
         * @public
         *
         * @param {Object} record record object
         * @returns validated and parsed record
         */
        function _parseRecord(record) {
            record.recordType = "ptr";
            return this.validateState(record);
        }

        /**
         * Validate a record of this processor's type
         *
         * @method validateState
         * @public
         *
         * @param {Object} record record object
         * @returns validated record
         */
        function _validateState(record) {
            record.valid = false;
            switch (record.state) {
                case "PASS":
                case "VALID":
                    record.valid = true;
                    break;
            }
            return record;
        }

        /**
         * Preporocess result items for consistent results during processResultItems call
         *
         * @method normalizeResults
         * @public
         *
         * @param {Array<Object>} results unprocessed results
         * @returns {Array<Object>} normalized results
         */
        function _normalizeResults(results) {
            var normalized = results.data.map( function(ptrEntry) {
                var mailDomain = ptrEntry.domain;

                var ptrRecords = ptrEntry.ptr_records.map( function(record) {
                    return {
                        current: {
                            name: ptrEntry.arpa_domain + ".",
                            value: record.domain,
                        },
                        domain: mailDomain,
                        state: record.state,
                    };
                } );

                return {
                    expected: ptrEntry.arpa_domain,
                    domain: mailDomain,
                    records: ptrRecords,
                    details: ptrEntry,
                };
            } );

            return { data: normalized };
        }

        /**
         * Generated an expected record for this processor type
         *
         * @method generateSuggestedRecord
         * @public
         *
         * @param {Object} resultItem result item to generate a record for
         * @returns {String} expected record string
         */
        function _generateSuggestedRecord(resultItem) {
            var expected = resultItem.expected;
            return { name: expected + ".", value: "unknown" };
        }

        this.generateSuggestedRecord = _generateSuggestedRecord.bind(this);
        this.normalizeResults = _normalizeResults.bind(this);
        this.getValidateAPI = _getValidateAPI.bind(this);
        this.getInstallAPI = _getInstallAPI.bind(this);
        this.processResultItem = _processResultItem.bind(this);
        this.processResultItems = _processResultItems.bind(this);
        this.parseRecord = _parseRecord.bind(this);
        this.validateState = _validateState.bind(this);
    }

    return new PTRRecordProcessor();

});
