/*
# cjt/services/nvDataServiceFactory.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/**
 * This module returns a factory function to generate NVDataService instances
 * scoped to a specific application: whostmgr, cpanel, webmail. To work in
 * an application, the application must expose an API for Personalization::get
 * and Personalization::set. See the relevant back-end API modules in:
 *
 *  Whostmgr/API/1/Personalization.pm
 *  Cpanel/API/Personalization.pm
 *
 * Instances created by this factory are available in cjt2 in for whostmgr,
 * cpanel and webmail in:
 *
 *   [NVDataService for cpanel and webmail]{@link module:cjt/services/cpanel/NVDataService}
 *   [NVDataService for whostmgr]{@link module:cjt/services/whm/NVDataService}
 *
 * @module cjt/services/nvDataServiceFactory
 */

define([

    // Libraries
    "angular"
],
function(angular) {
    "use strict";

    /**
     * Factory method to generate specific NVDataServices that work in one of the
     * applications: whostmgr, cpanel, webmail depending on the arguments passed.
     *
     * @function module:cjt/services/nvDataServiceFactory
     * @param  {module:cjt/io/request:Request} APIREQUEST
     * @param  {module:cjt/service/APIService:APIService} APIService
     * @return {module:cjt/services/nvDataServiceFactory:NVDataService} Instance of the NVDataService for the specific application.
     */
    return function(APIREQUEST, APIService) {


        /**
         * NVDataService for a specific application environment.
         *
         * @class
         * @exports module:cjt/services/nvDataServiceFactory:NVDataService
         */
        var NVDataService = function() {};
        NVDataService.prototype = new APIService();

        // Extend the prototype with any class-specific functionality
        angular.extend(NVDataService.prototype, {

            /**
             * @global
             * @typedef {Object} NameValuePair
             * @property {String}  name  Name of the pair
             * @property {?String} value Value of the named item
             */

            /**
             * @global
             * @typedef {Object} SavedNameValuePair
             * @property {String} name    Name of the pair
             * @property {Any}    [value] Value of the named item if saved correctly
             * @property {String} [error] Problem if the named item could not be saved.
             */

            /**
             * Gets one or more user preferences (nvdata) data elements
             *
             * @example "xmainrollstatus|xmaingroupsorder"
             *
             * @method get
             * @instance
             * @async
             * @param  {String|String[]} names one of the following:
             *   * name of one nvdata element as a string
             *   * an array of one or more nvdata names
             * @return {Promise.<NameValuePair[]>} Promise that will fulfill the request.
             */
            get: function(names) {
                if (!angular.isArray(names)) {
                    names = [names];
                }

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("Personalization", "get", null, null, { json: true });
                apiCall.addArgument("names", names);
                return this.deferred(apiCall, {
                    apiSuccess: function(response, deferred) {
                        var list = [];
                        var personalization = response.data.personalization;
                        names.forEach(function(name) {
                            list.push({ name: name, value: personalization[name].value } );
                        });
                        deferred.resolve(list);
                    }
                }).promise;
            },

            /**
             * Set a single name/value pair on the server
             *
             * @method set
             * @instance
             * @async
             * @param  {String} name  Name of the property to store
             * @param  {Any}    value Value to store for the name
             * @returns {Promise.<SavedNameValuePair>}
             */
            set: function(name, value) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("Personalization", "set", null, null, { json: true });
                var pairs = {};
                pairs[name] = value;
                apiCall.setArguments({
                    personalization: pairs
                });
                return this.deferred(apiCall, {
                    apiSuccess: function(response, deferred) {
                        var personalization = response.data.personalization;
                        var pair = personalization[name];
                        var ret = { set: name, value: pair.value };
                        if (!pair.success) {
                            ret.error = pair.reason || "Unknown failure.";
                        }
                        deferred.resolve(ret);
                    }
                }).promise;
            },

            /**
             * Builds the NVData name/value pairs in a single object
             * for the passed in names.
             *
             * @method getObject
             * @instance
             * @async
             * @param  {String|String[]} names one of the following:
             *   * name of one nvdata element as a string
             *   * an array of one or more nvdata names
             * @return {Promise.<Object.<string, value>>} Promise that will fulfill the request.
             * @example
             * var names = [
             *     "xmainrollstatus",
             *     "xmaingroupsorder"
             * ];
             *
             * nvDataService.getObject(names).then(function(data){
             *     console.log(data);
             * });
             *
             * In this example, the following will be printed to the console:
             *
             * {
             *      xmainrollstatus:  "databases=0|domains=0",
             *      xmaingroupsorder: "databases|files|domains|email"
             * }
             */
            getObject: function(names) {
                if (!angular.isArray(names)) {
                    names = [names];
                }

                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("Personalization", "get", null, null, { json: true });
                apiCall.addArgument("names", names);
                return this.deferred(apiCall, {
                    apiSuccess: function(response, deferred) {
                        var personalization = response.data.personalization;
                        var xform = {};
                        Object.keys(personalization).forEach(function(name) {
                            xform[name] = personalization[name].value;
                        });
                        deferred.resolve(xform);
                    }
                }).promise;
            },

            /**
             * Sets NVData values passed as key value pairs in an object
             *
             * @example
             * {
             *      xmainrollstatus:  "databases=0|domains=0",
             *      xmaingroupsorder: "databases|files|domains|email"
             * }
             *
             * @method setObject
             * @param  {Object.<string,string>} data NVData pairs to be set where each property
             *                       is the name of the pair and each property value is the value
             *                       of the pair.
             * @return {Promise.<SavedNameValuePair[]>} Promise that will fulfill the request.
             */
            setObject: function(data) {
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("Personalization", "set", null, null, { json: true });
                apiCall.setArguments({
                    personalization: data
                });
                return this.deferred(apiCall, {
                    apiSuccess: function(response, deferred) {
                        var list = [];
                        var personalization = response.data.personalization;
                        Object.keys(personalization).forEach(function(name) {
                            var pair = personalization[name];
                            var ret = { set: name, value: pair.value };
                            if (!pair.success) {
                                ret.error = pair.reason || "Unknown failure.";
                            }
                            list.push(ret);
                        });
                        deferred.resolve(list);
                    }
                }).promise;
            }
        });

        return new NVDataService();
    };
});
