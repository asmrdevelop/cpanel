/*
# countriesService.js                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/io/whm-v1-request",
        "cjt/modules",
        "cjt/io/api",
        "cjt/io/whm-v1",
        "cjt/services/APICatcher"
    ],
    function(angular, _, APIRequest) {

        "use strict";

        var MODULE_NAMESPACE = "whm.eximBlockCountries.services.countries";
        var SERVICE_NAME = "eximBlockCountries";
        var MODULE_REQUIREMENTS = [ "cjt2.services.apicatcher" ];
        var SERVICE_INJECTABLES = ["APICatcher", "$q"];

        /**
         *
         * Service Factory to generate the Exim Block Countries service
         *
         * @module countriesService
         * @memberof whm.eximBlockCountries
         *
         * @param {Object} APICatcher base service
         * @returns {Service} instance of the eximBlockCountries service
         */
        var SERVICE_FACTORY = function SERVICE_FACTORY(APICatcher, $q) {

            var Service = function Service() {};

            Service.prototype = Object.create(APICatcher);

            _.assign(Service.prototype, {

                /**
                 * Wrapper for building an apiCall
                 *
                 * @private
                 *
                 * @param {String} module module name to call
                 * @param {String} func api function name to call
                 * @param {Object} args key value pairs to pass to the api
                 * @returns {UAPIRequest} returns the api call
                 *
                 * @example _apiCall( "", "list_blocked_incoming_email_countries")
                 */
                _apiCall: function _createApiCall(module, func, args) {
                    var apiCall = new APIRequest.Class();
                    apiCall.initialize(module, func, args);
                    return apiCall;
                },

                /**
                 * List the Currently Blocked Email Countries
                 *
                 * @returns {Promise<Object[]>} List of blocked countries
                 *
                 * @example $service.listBlockedIncomingEmailCountries();
                 */
                listBlockedIncomingEmailCountries: function listBlockedIncomingEmailCountries() {
                    if (_.isArray(PAGE.blocked_incoming_email_countries)) {
                        return $q.resolve(PAGE.blocked_incoming_email_countries);
                    }

                    var apiCall = this._apiCall("", "list_blocked_incoming_email_countries");
                    return this._promise(apiCall).then(function _parseBlockedCountries(result) {
                        return result && result.data || [];
                    });
                },

                /**
                 * List the Countries With Known IP Ranges
                 *
                 * @returns {Promise<Object[]>} List of countries
                 *
                 * @example $service.getCountriesWithKnownIPRanges();
                 */
                getCountriesWithKnownIPRanges: function getCountriesWithKnownIPRanges() {
                    if (_.isArray(PAGE.countries_with_known_ip_ranges)) {
                        return $q.resolve(PAGE.countries_with_known_ip_ranges);
                    }
                    var apiCall = this._apiCall("", "get_countries_with_known_ip_ranges");
                    return this._promise(apiCall).then(function _parseCountries(result) {
                        return result && result.data || [];
                    });
                },

                _verifyCountryCodesArray: function _verifyCountryCodesArray(countryCodes) {
                    if (!_.isArray(countryCodes)) {
                        throw "countryCodes must be an array";
                    }
                    var notStringIndex = _.findIndex(countryCodes, function(countryCode) {
                        if (typeof (countryCode) !== "string") {
                            return true;
                        }
                        return false;
                    });
                    if (notStringIndex !== -1) {
                        var msg = "";
                        msg += "countryCodes must be an array of country code strings. ";
                        msg += "“" + notStringIndex + "” is not a string (" + (typeof countryCodes[notStringIndex]) + ")";
                        throw msg;
                    }

                    return true;
                },

                /**
                 * Block a Country
                 *
                 * @param {String[]} countryCodes Country code to block
                 *
                 * @returns {Promise}
                 * @throws an error if countryCodes is not an array
                 * @throws an error if countryCodes is not an array of strings
                 *
                 * @example $service.blockIncomingEmailFromCountries('RU');
                 */
                blockIncomingEmailFromCountries: function blockIncomingEmailFromCountries(countryCodes) {
                    this._verifyCountryCodesArray(countryCodes);
                    var apiCall = this._apiCall("", "block_incoming_email_from_country", { country_code: countryCodes });

                    return this._promise(apiCall);
                },

                /**
                 * Unblock a Country
                 *
                 * @param {String[]} countryCode Country code to unblock
                 *
                 * @returns {Promise}
                 * @throws an error if countryCodes is not an array
                 * @throws an error if countryCodes is not an array of strings
                 *
                 * @example $service.unblockIncomingEmailFromCountries('RU');
                 */
                unblockIncomingEmailFromCountries: function unblockIncomingEmailFromCountries(countryCodes) {
                    this._verifyCountryCodesArray(countryCodes);
                    var apiCall = this._apiCall("", "unblock_incoming_email_from_country", { country_code: countryCodes });

                    return this._promise(apiCall);
                },

                /**
                 * Wrapper for .promise method from APICatcher
                 *
                 * @private
                 *
                 * @param {Object} apiCall api call to pass to .promise
                 * @returns {Promise}
                 *
                 * @example $service._promise( $service._apiCall( "Email", "get_mailbox_autocreate", { email:"foo@bar.com" } ) );
                 */
                _promise: function _promise() {

                    // Because nested inheritence is annoying
                    return APICatcher.promise.apply(this, arguments);
                }
            });

            return new Service();
        };

        SERVICE_INJECTABLES.push(SERVICE_FACTORY);

        var app = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);
        app.factory(SERVICE_NAME, SERVICE_INJECTABLES);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);
