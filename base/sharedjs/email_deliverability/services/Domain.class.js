/*
# email_deliverability/services/Domain.class.js      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define([
    "lodash"
], function(_) {

    "use strict";

    /**
     * Class to contain domain object functions
     *
     * @property {Boolean} recordsLoaded whether setRecordsLoaded has been called
     * @property {Boolean} recordsValid whether the current records make the domain valid
     * @memberof cpanel.emailDeliverability
     * @class
     */
    var Domain = function Domain(domainObject) {
        var self = this;

        var _requiredArgs = ["domain"];

        this.records = [];
        this._recordDetails = {};
        this.reloadingIn = 0;
        this.nameservers = [];
        this.zone = "";
        this.recordsLoaded = false;
        this.recordsValid = false;
        this._recordTypesLoaded = [];
        this._recordsTypesWithIssues = [];
        this._suggestedRecords = {};
        this._expectedMatch = {};
        this.hasNSAuthority = false;
        this.mailIP = {
            version: null,
            address: null
        };
        this.hadAnyNSErrors = false;

        /**
         *
         * Initiate the domain object
         *
         * @param {Object} domainObject object to process in construction
         */
        function init(domainObject) {

            Object.keys(domainObject).forEach(function(key) {
                self[key] = domainObject[key];
            });

            self.protocol = "http";
            self.isWildcard = self["domain"] && self["domain"].substr(0, 1) === "*";

            _requiredArgs.forEach(function(reqArg) {
                if (!self[reqArg]) {
                    throw new Error("“" + reqArg + "” is a required parameter.");
                }
            });
        }

        /**
         * Add a DNS Record to the Domain
         *
         * @method
         * @param  {Object} record new record to be added to the domain
         *
         */
        function addRecord(record) {
            if (_.isUndefined(record.recordType)) {
                throw new Error("recordType must be defined on a record");
            }
            if (_.isUndefined(record.valid)) {
                throw new Error("valid must be defined on a record of type “" + record.recordType + "” for domain “" + this.domain + "”");
            }
            this.records.push(record);
        }

        /**
         * Updates the status and validity of the domain based on existing records
         *
         * @method
         *
         */
        function setRecordsLoaded(recordTypesLoaded) {
            this._recordTypesLoaded = recordTypesLoaded;
            this.recordsLoaded = true;
            this._recordsTypesWithIssues = [];
            recordTypesLoaded.forEach(function(recordType) {
                var records = this.getRecords(recordType);
                if (records.length !== 1 || !records[0].valid) {
                    this._recordsTypesWithIssues.push(recordType);
                }
            }, this);
            var details = this.getRecordDetails();
            Object.keys(details).forEach(function(recordType) {
                if ( details[recordType].error ) {
                    this.hadAnyNSErrors = true;
                }
            }, this);
            this.recordsValid = this._recordsTypesWithIssues.length === 0;
        }

        /**
         *
         * Get the record types that have been loaded into this Domain
         *
         * @returns {Array<String>} array of record types
         */
        function getRecordTypesLoaded() {
            return this._recordTypesLoaded;
        }

        /**
         *
         * Reset loaded records
         *
         */
        function resetRecordLoaded() {
            this.recordsLoaded = false;
            this.recordTypesLoaded = [];
            this.reloadingIn = 0;
            this.records = [];
            this.hasNSAuthority = false;
            this.recordsValid = false;
            this._recordsTypesWithIssues = [];
            this.hadAnyNSErrors = false;
        }

        /**
         *
         * Is a specific record type valid
         *
         * @param {String} recordType record type to check
         * @returns {Boolean} is the record type valid
         */
        function isRecordValid(recordType) {
            return this._recordsTypesWithIssues.indexOf(recordType) === -1;
        }

        /**
         * Get the record status for the domain
         *
         * @method
         * @return  {Array<Object>} an array of DNS records stored on the domain
         *
         */
        function getRecords(recordTypes) {
            var records = this.records;
            if (recordTypes) {
                records = records.filter(function(record) {
                    if (recordTypes.indexOf(record.recordType) !== -1) {
                        return true;
                    }
                    return false;
                });
            }
            return records;
        }

        /**
         *
         * Get the suggested valid record of a type for this domain
         *
         * @param {String} recordType record type to get the suggestion for
         * @returns {Object} suggested record
         */
        function getSuggestedRecord(recordType) {
            if (this.recordsLoaded && this.isRecordValid(recordType)) {
                return this.getCurrentRecord(recordType);
            }
            return this._suggestedRecords[recordType];
        }

        /**
         *
         * Set the suggested record for the domain
         *
         * @param {String} recordType record type to set the suggestion for
         * @param {Object} recordObject record suggestion
         */
        function setSuggestedRecord(recordType, recordObject) {
            this._suggestedRecords[recordType] = recordObject;
        }

        /**
         *
         * Get the expected valid record of a type for this domain
         *
         * @param {String} recordType record type to get the suggestion for
         * @returns {Object} expected record
         */
        function getExpectedMatch(recordType) {
            return this._expectedMatch[recordType];
        }

        /**
         *
         * Set the expected record for the domain
         *
         * @param {String} recordType record type to set the suggestion for
         * @param {Object} recordObject record suggestion
         */
        function setExpectedMatch(recordType, recordObject) {
            this._expectedMatch[recordType] = recordObject;
        }

        function getCurrentRecord(recordType) {
            var records = this.getRecords([recordType]);
            var topRecord = records[0];

            return topRecord ? topRecord.current : {};
        }

        /**
         * Get a list of record types with issues
         *
         * @method
         * @return  {Array<String>} an array of record types stored on the domain
         *
         */
        function getRecordTypesWithIssues() {
            return this._recordsTypesWithIssues;
        }

        /**
         * Get a list of record types with NS errors
         *
         * @method
         * @return {Array<String>} an array of record types that had NS errors
         */
        function getRecordTypesWithNSErrors() {
            var types = [];
            Object.keys(this._recordDetails).forEach(function(recordType) {
                if ( this._recordDetails[recordType].error ) {
                    types.push(recordType);
                }
            }, this);

            return types;
        }

        /**
         *
         * Set the mail ip object for this domain
         *
         * @param {int} version IP Version 4 or Version 6
         * @param {String} address IP Address
         */
        function setMailIP(version, address) {
            this.mailIP.version = version;
            this.mailIP.address = address;
        }

        /**
         *
         * Get the mail IP object for the domain
         *
         * @returns {Object} object containing the .version and .address
         */
        function getMailIP() {
            return this.mailIP;
        }

        function recordHadNSError(recordType) {
            return !!this._recordDetails[recordType].error;
        }

        this.init = init.bind(this);
        this.addRecord = addRecord.bind(this);
        this.setRecordsLoaded = setRecordsLoaded.bind(this);
        this.getRecords = getRecords.bind(this);
        this.isRecordValid = isRecordValid.bind(this);
        this.getRecordTypesWithIssues = getRecordTypesWithIssues.bind(this);
        this.getRecordTypesWithNSErrors = getRecordTypesWithNSErrors.bind(this);
        this.getSuggestedRecord = getSuggestedRecord.bind(this);
        this.setSuggestedRecord = setSuggestedRecord.bind(this);
        this.getExpectedMatch = getExpectedMatch.bind(this);
        this.setExpectedMatch = setExpectedMatch.bind(this);
        this.resetRecordLoaded = resetRecordLoaded.bind(this);
        this.setMailIP = setMailIP.bind(this);
        this.getMailIP = getMailIP.bind(this);
        this.getRecordTypesLoaded = getRecordTypesLoaded.bind(this);
        this.getCurrentRecord = getCurrentRecord.bind(this);
        this.recordHadNSError = recordHadNSError.bind(this);

        this.init(domainObject);
    };

    _.assign(
        Domain.prototype,
        {
            setRecordDetails: function(rtype, details) {

                // sanity check - enforce lower-case
                if (!/^[a-z]+$/.test(rtype)) {
                    throw new Error("Invalid record type: " + rtype);
                }

                this._recordDetails[rtype] = details;
            },

            getRecordDetails: function(rtype) {

                if ( !rtype ) {
                    return this._recordDetails;
                }

                if (!this._recordDetails.hasOwnProperty(rtype)) {
                    throw new Error("No stored details: " + rtype);
                }

                return this._recordDetails[rtype];
            },
        }
    );

    return Domain;
}
);
