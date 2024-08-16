/*
# email_deliverability/services/SPFRecordProcessor       Copyright 2022 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define([
    "shared/js/email_deliverability/services/spfParser"
], function(SPFParser) {

    "use strict";

    function SPFRecordProcessor() {

        /**
         *
         * @module SPFRecordProcessor
         * @memberof cpanel.emailDeliverability
         *
         */

        /**
         * Get the Validate API call for this Record Processor
         *
         * @method getValidateAPI
         * @public
         *
         *
         * @returns {Object} api call .module and .func
         */
        function _getValidateAPI() {
            return { module: "EmailAuth", func: "validate_current_spfs" };
        }

        /**
         * Get the Install API call for this Record Processor
         *
         * @method getInstallAPI
         * @public
         *
         *
         * @returns {Object} api call .module and .func
         */
        function _getInstallAPI() {
            return { module: "EmailAuth", func: "install_spf_records" };
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
            var currentName = record.current.name;
            var currentValue = record.current.value;
            var parsedRecord = this._parseSPF(currentValue);
            parsedRecord.state = record.state;
            parsedRecord.recordType = "spf";
            parsedRecord.current = { name: currentName, value: currentValue };
            parsedRecord = this.validateState(parsedRecord);
            return parsedRecord;
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
                case "SOFTFAIL":
                case "PERMERROR":
                    break;
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
            results.data.forEach(function(resultItem) {
                var recordName = resultItem.domain;
                resultItem.records.forEach(function(record) {
                    record.current = {
                        name: recordName + ".",
                        value: record.current
                    };
                });
            });
            return results;
        }

        /**
         * Combine a string record with new mechanisms and de-dupe
         *
         * @method generatedExpectedRecord
         * @public
         *
         * @param {String} record record to combine with new mechanisms
         * @param {Array<String>} mechanisms new mechanisms to inject into the record
         * @returns {String} combined string record
         */
        function _combineRecords(oldRecord, mechanisms) {
            oldRecord = oldRecord || "";
            var parsedRecord = this._parseSPF(oldRecord);

            // de-dupe (remove instances of updated mechanisms in old record)
            var mechanismsToRemove = [];
            mechanisms.forEach(function(mechanism) {
                parsedRecord.mechanisms.forEach(function(oldRecordMech, index) {
                    if (oldRecordMech.type === mechanism.type && oldRecordMech.value === mechanism.value) {

                        // Item with type and value exist, regardless of prefix, remove it.
                        mechanismsToRemove.push(index);
                    }
                });
            });

            // Starting from the last index, remove all matching indexes
            mechanismsToRemove = mechanismsToRemove.sort().reverse();
            mechanismsToRemove.forEach(function(mechanismIndex) {
                parsedRecord.mechanisms.splice(mechanismIndex, 1);
            });
            var finalRecordMechanisms = [];

            // Add preceeding old mechanisms
            var insertIndex = 0;
            while (parsedRecord.mechanisms[insertIndex] && parsedRecord.mechanisms[insertIndex].type && parsedRecord.mechanisms[insertIndex].type.match(/^(version|ip|mx|a)$/)) {
                finalRecordMechanisms.push(parsedRecord.mechanisms[insertIndex]);
                insertIndex++;
            }

            // Add new mechanisms
            mechanisms.forEach(function(mechanism) {
                finalRecordMechanisms.push(mechanism);
            });

            // Add rest of old mechanisms
            while (insertIndex < parsedRecord.mechanisms.length) {
                finalRecordMechanisms.push(parsedRecord.mechanisms[insertIndex]);
                insertIndex++;
            }

            // convert to a string
            var newRecord = finalRecordMechanisms.map(function(mechanism) {
                var mechanismString;
                if (mechanism.type === "version") {
                    mechanismString = mechanism.prefix + "=" + mechanism.value;
                } else {
                    mechanismString = mechanism.prefix + mechanism.type;
                    if (mechanism.value) {
                        mechanismString += ":" + mechanism.value;
                    }
                }
                return mechanismString;
            }).join(" ");

            // return the completed record
            return newRecord;
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
            var missingPieces = resultItem.expected || "";
            var missingMechanisms = missingPieces.split(/\s+/).map(this._parseSPFTerm);
            var suggestedRecord = "";
            if (resultItem.records.length) {
                var firstCurrent = resultItem.records[0].current;
                suggestedRecord = this.combineRecords(firstCurrent.value, missingMechanisms);
            } else {
                suggestedRecord = this.combineRecords("v=spf1 +mx +a ~all", missingMechanisms);
            }
            return { name: resultItem.domain + ".", value: suggestedRecord, originalExpected: resultItem.expected };
        }

        this.generateSuggestedRecord = _generateSuggestedRecord.bind(this);
        this.normalizeResults = _normalizeResults.bind(this);
        this.getValidateAPI = _getValidateAPI.bind(this);
        this.getInstallAPI = _getInstallAPI.bind(this);
        this.processResultItem = _processResultItem.bind(this);
        this.processResultItems = _processResultItems.bind(this);
        this.parseRecord = _parseRecord.bind(this);
        this.validateState = _validateState.bind(this);
        this._parseSPF = SPFParser.parse.bind(SPFParser);
        this._parseSPFTerm = SPFParser.parseTerm.bind(SPFParser);
        this.combineRecords = _combineRecords.bind(this);
    }

    return new SPFRecordProcessor();

});
