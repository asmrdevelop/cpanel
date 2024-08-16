/*
# zone_editor/services/dnssec.js                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/api",
        "cjt/io/uapi-request",
        "cjt/io/uapi",
        "cjt/services/APIService",
        "cjt/services/viewNavigationApi"
    ],
    function(angular, _, LOCALE, API, APIREQUEST, APIDRIVER) {
        "use strict";

        var app = angular.module("cpanel.zoneEditor.services.dnssec", ["cjt2.services.api"]);

        var ONE_YEAR = 60 * 60 * 24 * 365;  // This is a suggested rotation time and does not need to be absolutely correct, hence no leap year check
        var HALF_YEAR = ONE_YEAR / 2;

        /**
         * Service wrapper for dnssec
         *
         * @module DnsSecService
         *
         * @param  {Object} $q angular $q object
         * @param  {Object} APIService cjt2 api service
         */
        var factory = app.factory("DnsSecService", ["$q", "APIService", "viewNavigationApi", function($q, APIService, viewNavigationApi) {
            var DnsSecApi = function() {};
            DnsSecApi.prototype = new APIService();

            angular.extend(DnsSecApi.prototype, {
                generate: generate,
                fetch: fetchDsRecords,
                activate: activate,
                deactivate: deactivate,
                remove: remove,
                importKey: importKey,
                exportKey: exportKey,
                exportPublicDnsKey: exportPublicDnsKey,
                copyTextToClipboard: copyTextToClipboard,
                goToInnerView: goToInnerView,
                getSuggestedKeyRotationDate: getSuggestedKeyRotationDate
            });


            return new DnsSecApi();

            /**
             * @typedef GenerateKeyDetails
             * @type Object
             * @property {EnabledDetails} enabled
             */

            /**
             * @typedef EnabledDetails
             * @type Object
             * @property {EnabledDomainDetails} your domain name
             */

            /**
             * @typedef EnabledDomainDetails
             * @type Object
             * @property {string} nsec_version - the nsec version for the key.
             * @property {Number} enabled - 1 if enabled, 0 if not.
             * @property {string} new_key_id - the id of the key.
             */

            /**
             * Generates DNSSEC keys according to a particular setup
             *
             * @method generate
             * @async
             * @param {string} domain - the domain
             * @param {string} [algoNum] - the algorithm number
             * @param {string} [setup] - how to setup the keys, "classic" or "simple"
             * @param {boolean} [active] - set the status of the key
             * @return {GenerateKeyDetails} Details about the key.
             * @throws When the back-end throws errors.
             */
            function generate(domain, algoNum, setup, active) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "enable_dnssec");
                apiCall.addArgument("domain", domain);

                if (algoNum !== void 0) {
                    apiCall.addArgument("algo_num", algoNum);
                }

                if (setup !== void 0) {
                    apiCall.addArgument("key_setup", setup);
                }

                if (active !== void 0) {
                    apiCall.addArgument("active", (active) ? 1 : 0);
                }

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // The API call can succeed but you can still get an error message
                        // so check for that message and return it
                        if (response.data && response.data.failed) {
                            return $q.reject(response.data.failed[domain]);
                        }
                        return response.data;
                    });
            }

            /**
             * @typedef FetchDSRecordsReturn
             * @type Object
             * @property {FetchDSRecordsKeyDetails} keys
             */

            /**
             * @typedef FetchDSRecordsKeyDetails
             * @type Object
             * @property {Number} active - 1 if active, 0 if not.
             * @property {string} algo_desc - the key algorithm.
             * @property {string} algo_num - the number for the key algorithm.
             * @property {string} algo_tag - the tag for the key algorithm.
             * @property {string} bits - the number of bits for the key algorithm.
             * @property {string} created - the unix epoch when the key was created.
             * @property {Digests[]} digests - the digests for the key; only a KSK or CSK will have this.
             * @property {string} flags - the flags of the key.
             * @property {string} key_id - the id of the key.
             * @property {string} key_tag - the tag of the key.
             * @property {string} key_type - the type of the key (either ZSK, KSK, CSK).
             */

            /**
             * @typedef Digests
             * @type Object
             * @property {string} algo_desc - The algorithm for the digest.
             * @property {string} algo_num - The number for the digest algorithm.
             * @property {string} digest - The digest hash.
             */

            /**
             * Retrieve the DS records for a domain
             *
             * @method fetchDsRecords
             * @async
             * @param {string} domain - the domain
             * @return {FetchDSRecordsReturn} - An object of all keys for this domain.
             * @throws When the back-end throws errors.
             */
            function fetchDsRecords(domain) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "fetch_ds_records");
                apiCall.addArgument("domain", domain);

                return this.deferred(apiCall).promise
                    .then(function(response) {
                        if (response.data[domain].keys) {

                            // sort by key type (ksk first), then by active state (active first), then by key tag
                            return _.chain(response.data[domain].keys)
                                .orderBy(["key_type", "active", function(i) {
                                    return Number(i.key_tag); // convert to number so it sorts numerically rather than lexically
                                }], ["asc", "desc", "asc"])
                                .value();
                        } else {
                            return [];
                        }
                    });
            }

            /**
             * @typedef ActivateKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} key_id - The id of the key.
             * @property {Number} success - 1 for success, 0 for failure.
             */

            /**
             * Activate a DNSSEC key
             *
             * @method activate
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function activate(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "activate_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // The API call can succeed but you can still get an error message
                        // so check for that message and return it
                        if (response.data.error) {
                            return $q.reject(response.data.error);
                        }

                        return response.data;
                    });
            }

            /**
             * Deactivate a DNSSEC zone key
             *
             * @method deactivate
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function deactivate(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "deactivate_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (response.data.error) {
                            return $q.reject(response.data.error);
                        }
                        return response.data;
                    });
            }

            /**
             * Remove a DNSSEC zone key
             *
             * @method remove
             * @async
             * @param {string} domain - the domain
             * @param {string|number} keyId - the id of the key
             * @return {ActivateKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function remove(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "remove_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (response.data.error) {
                            return $q.reject(response.data.error);
                        }
                        return response.data;
                    });
            }

            /**
             * @typedef ImportKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} new_key_id - The id of the new key.
             * @property {Number} success - 1 for success, 0 for failure.
             */

            /**
             * Imports a DNSSEC zone key
             *
             * @method importKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyType - type of key, KSK or ZSK
             * @param {string} key - the key data in a text format
             * @return {ImportKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function importKey(domain, keyType, key) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "import_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_data", key);
                apiCall.addArgument("key_type", keyType.toLocaleLowerCase("en-US"));

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (response.data.error) {
                            return $q.reject(response.data.error);
                        }
                        return response.data;
                    });
            }

            /**
             * @typedef ExportKeyReturn
             * @type Object
             * @property {string} domain - The domain for the key.
             * @property {string} key_content - The key data in a text format.
             * @property {string} key_id - The id of the key.
             * @property {string} key_tag - The tag for the key.
             * @property {string} key_type - The type of the key.
             * @property {Number} success - 1 for success, 0 for failure.
             */


            /**
             * Exports a DNSSEC zone key
             *
             * @method exportKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyId - the id of the key
             * @return {ExportKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function exportKey(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "export_zone_key");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {
                        return response.data;
                    });
            }

            /**
             * @typedef ExportPublicDnsKeyReturn
             * @type Object
             * @property {string} key_id - The id of the key.
             * @property {Number} success - 1 for success, 0 for failure.
             * @property {string} dnskey - The public dns key for the specified dnssec key.
             */

            /**
             * Exports the public DNSKEY
             *
             * @method exportPublicDnsKey
             * @async
             * @param {string} domain - the domain
             * @param {string} keyId - the id of the key
             * @return {ExportPublicDnsKeyReturn} Details about the key.
             * @throws When the back-end throws errors.
             */
            function exportPublicDnsKey(domain, keyId) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("DNSSEC", "export_zone_dnskey");
                apiCall.addArgument("domain", domain);
                apiCall.addArgument("key_id", keyId);

                return this.deferred(apiCall).promise
                    .then(function(response) {

                        // Don't forget to check for errors
                        if (response.data.success !== 1 && response.data.success !== "1") {
                            return $q.reject(response.data.error);
                        }

                        return response.data;
                    });
            }

            /**
             * Puts some text on the clipboard
             *
             * @method copyTextToClipboard
             * @param {string} text - the text you want to put on the clipboard
             * @return Nothing
             * @throws When the copy command does not succeed
             */
            function copyTextToClipboard(text) {
                var textArea = document.createElement("textarea");
                textArea.value = text;
                document.body.appendChild(textArea);
                textArea.select();
                var success = document.execCommand("copy");
                if (!success) {
                    throw LOCALE.maketext("Copy failed.");
                }
                document.body.removeChild(textArea);
            }

            /**
             * Helper function to navigate to "sub-views" within dnssec
             *
             * @method goToInnerView
             * @param {string} view - the view you want to go to.
             * @param {string} domain - the domain associated with the key.
             * @param {string} keyId - the key id; used to load information about the key on that view.
             * @return {$location} The Angular $location service used to perform the view changes.
             */
            function goToInnerView(view, domain, keyId) {
                var path = "/dnssec/" + view;
                var query = { domain: domain };
                if (keyId) {
                    query.keyid = keyId;
                }
                return viewNavigationApi.loadView(path, query);
            }

            /**
             * Calculates the suggested rotation date for a key
             *
             * @method getSuggestedKeyRotationDate
             * @param {number|string} date - an epoch date
             * @param {string} keyType - key type, either ksk, zsk, or csk
             * @return {number} The suggested rotation date
             */
            function getSuggestedKeyRotationDate(date, keyType) {
                if (typeof date === "string") {
                    date = Number(date);
                }

                var suggestedDate = date;
                if (keyType.toLowerCase() === "zsk") {
                    suggestedDate += HALF_YEAR;
                } else {
                    suggestedDate += ONE_YEAR;
                }
                return suggestedDate;
            }

        }]);

        return factory;
    }
);
