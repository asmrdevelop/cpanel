/*
# mod_security/services/reportService.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",

        // CJT
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/services/APIService",

        // Feature-specific
        "app/services/hitlistService",
        "app/services/ruleService"
    ],
    function(angular, LOCALE, APIREQUEST) {

        var NO_MODULE = "";

        // Fetch the current application
        var app;

        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", ["cjt2.services.api"]); // Fall-back for unit testing
        }

        /**
         * This service uses the ruleService and hitListService to allow for better front-end
         * visualization of the relationships between hits and rules. Using setHit or setRule
         * will return a promise that will resolve with a report object, which is just a
         * conglomerate object of related rules and hits. The two methods differ slightly in
         * their output and more information is provided in their documentation blocks.
         */
        app.factory("reportService", [
            "$q",
            "APIService",
            "ruleService",
            "hitListService",
            function(
                $q,
                APIService,
                ruleService,
                hitListService
            ) {

                var currentReport; // Will be a promise

                /**
                 * Extracts the vendor id from a config file path.
                 *
                 * @method _getVendorFromFile
                 * @private
                 * @param  {String} file   The full file path to the config file.
                 *
                 * @return {String}        The vendor id if it's a vendor config or undefined if we
                 *                         can't parse the file path properly.
                 */
                function _getVendorFromFile(file) {
                    var VENDOR_REGEX = /\/modsec_vendor_configs\/(\w+)/;

                    var match = file && file.match(VENDOR_REGEX);
                    return match ? match[1] : void 0;
                }

                /**
                 * Given a unique hit ID (the id column from modsec.hits) or an actual hit object,
                 * this method will kick off a promise chain that will package together the full
                 * hit object along with its associated rule. The resolved report object from this
                 * method will differ from the report object provided by the setRule promise in
                 * that it will ONLY include the hit given as an argument.
                 *
                 * @method setHit
                 * @param  {String|Number|Object} hit   Either a bare hit ID or a hit object
                 *
                 * @return {Promise}                    This promise will resolve with a report object,
                 *                                      which essentially just packages a rule object
                 *                                      with an array of associated hits. For this
                 *                                      method, there will only be one hit in the array.
                 */
                function fetchByHit(hit) {
                    var fetched = {}; // This will house the eventual response
                    var hitPromise;

                    if (!angular.isObject(hit)) {

                        // This is a bare hitId so we need to fetch the actual hit object first
                        hitPromise = hitListService.fetchById(hit)
                            .then(function(response) {
                                fetched.hits = response.items;
                                return response.items[0]; // This length is guaranteed by the hitListService
                            });
                    } else {

                        // We already have the hit object, so just wrap it in an array and a promise
                        fetched.hits = [hit];

                        var deferred = $q.defer();
                        deferred.resolve(hit);
                        hitPromise = deferred.promise;
                    }

                    currentReport = hitPromise.then(function(hit) {

                        // Reports only work with vendors right now, so check that this is a vendor rule
                        var vendor = _getVendorFromFile(hit.meta_file);
                        if (!vendor) {
                            return $q.reject( LOCALE.maketext("You can only report [asis,ModSecurity] rules that a vendor provided.") );
                        }

                        // Fetch the rule
                        return ruleService.fetchRulesById(hit.meta_id, vendor);
                    }).then(function(response) {
                        fetched.rule = response.items[0]; // The length is guaranteed by the ruleService
                        return fetched;
                    });

                    return currentReport;
                }


                /**
                 * Given a unique rule ID or an actual rule object, this method will kick off a promise
                 * chain that will package together the full rule object along with any associated hits.
                 * The resolved report object from this method will differ from the report object
                 * provided by the setHit promise in that it will include ALL hits associated with the
                 * rule argument.
                 *
                 * @method setRule
                 * @param  {String|Number|Object} rule     Either a rule ID or a rule object
                 * @param  {String}               vendor   A vendor ID string
                 *
                 * @return {Promise}                       This promise will resolve with a report object,
                 *                                         which essentially just packages a rule object
                 *                                         with an array of associated hits.
                 */
                function fetchByRule(rule, vendor) {
                    var fetched = {};
                    var rulePromise;

                    if (!angular.isObject(rule)) { // This is a bare ruleId so we need to fetch the actual rule object first
                        // Reports only work with vendors right now, so check that one was provided
                        if (!vendor) {
                            return $q.reject( LOCALE.maketext("You can only report [asis,ModSecurity] rules that a vendor provided.") );
                        }

                        rulePromise = ruleService.fetchRulesById(rule, vendor).then(function(response) {
                            fetched.rule = response.items[0]; // The length is guaranteed by the ruleService
                            return fetched.rule;
                        });
                    } else { // We already have the rule object, so just wrap it in a promise

                        // Reports only work with vendors, so check that one was provided
                        if (!rule.vendor_id) {
                            return $q.reject( LOCALE.maketext("Only [asis,ModSecurity] rules provided by vendors may be reported.") );
                        }

                        fetched.rule = rule;

                        var deferred = $q.defer();
                        deferred.resolve(rule);
                        rulePromise = deferred.promise;
                    }

                    currentReport = rulePromise.then(function(rule) {
                        return hitListService.fetchList({
                            filterBy: "meta_id",
                            filterValue: rule.id,
                            filterCompare: "eq"
                        });
                    }).then(function(response) {
                        fetched.hits = response.items;
                        return fetched;
                    });

                    return currentReport;
                }

                /**
                 * Returns the current report promise. This is useful when changing views/controllers.
                 *
                 * @method getCurrent
                 * @return {Promise}   Either undefined if there is no current report promise,
                 *                     or a promise that will resolve with a report object,
                 *                     which essentially just packages a rule object with an
                 *                     array of associated hits.
                 */
                function getCurrent() {
                    return currentReport;
                }

                /**
                 * Unsets the current report so that it doesn't become stale.
                 * @method clearCurrent
                 */
                function clearCurrent() {
                    currentReport = void 0;
                }

                /**
                 * Generates a report but doesn't send it.
                 *
                 * @method viewReport
                 * @param  {Object} reportParams   See _generateReport documentation
                 *
                 * @return {Promise}
                 */
                function viewReport(reportParams) {
                    reportParams.send = false;
                    return _generateReport.call(this, reportParams);
                }

                /**
                 * Generates a report and sends it. Optionally disables the rule as well.
                 *
                 * @method sendReport
                 * @param  {Object} reportParams      See _generateReport documentation
                 * @param  {Object} [disableParams]   A set of params required for disabling the rule.
                 *     @param {Number}  disableParams.ruleId        The id of the rule to be disabled.
                 *     @param {Boolean} disableParams.deployRule    Should the disable change be deployed?
                 *     @param {String}  disableParams.ruleConfig    The path of the config file housing the rule.
                 *
                 * @return {Promise}                  Resolves when both operations are complete (or just the report, if no disableParams were given)
                 */
                function sendReport(reportParams, disableParams) {
                    var promises = {};

                    reportParams.send = true;
                    promises.report = _generateReport.call(this, reportParams);

                    if (disableParams) {
                        promises.disable = ruleService.disableRule(disableParams.ruleConfig, disableParams.ruleId, disableParams.deployRule);
                    }

                    return $q.all(promises);
                }

                /**
                 * Uses the modsec_report_rule API to either send a report or only perform a dry
                 * run and generate what would be sent without actually sending the payload.
                 *
                 * @method _generateReport
                 * @param  {Object}  params           Contains the key/value pairs for the parameters that will be passed with the API call.
                 * @param  {Array}   params.hits      An array of hit IDs that correspond to the id column in the modsec.hits table.
                 * @param  {String}  params.message   A short message to accompany the report.
                 * @param  {String}  params.email     The sender's email address.
                 * @param  {String}  params.reason    The reason for which the report is being submitted.
                 * @param  {Boolean} params.send      If true, the generated report will be sent by the API.
                 *
                 * @return {Promise}                  Resolves with the raw JSON generated by the API.
                 */
                function _generateReport(params) {

                    var apiCall = new APIREQUEST.Class();
                    apiCall.initialize(NO_MODULE, "modsec_report_rule");

                    angular.forEach({
                        row_ids: params.hits.join(","),
                        message: params.message,
                        email: params.email,
                        type: params.reason,
                        send: params.send ? 1 : 0
                    }, function(val, key) {
                        apiCall.addArgument(key, val);
                    });

                    return this.deferred(apiCall, {
                        transformAPISuccess: _extractReport
                    }).promise;
                }

                /**
                 * Extracts the report object from the response.
                 * @param  {Object} response   The response from the API.
                 * @return {Object}            The report object.
                 */
                function _extractReport(response) {
                    return response.data.report;
                }


                // Set up the service's constructor and parent
                var ReportService = function() {};
                ReportService.prototype = new APIService();

                // Extend the prototype with any class-specific functionality
                angular.extend(ReportService.prototype, {
                    fetchByHit: fetchByHit,
                    fetchByRule: fetchByRule,
                    getCurrent: getCurrent,
                    clearCurrent: clearCurrent,
                    viewReport: viewReport,
                    sendReport: sendReport
                });

                return new ReportService();
            }
        ]);
    }
);
