/*
# cjt/services/whm/userDomainListService.js          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, Promise: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready"
    ],
    function(angular, LOCALE, APIREQUEST) {
        "use strict";

        var module = angular.module("cjt2.services.whm.userDomainListService", []);

        module.factory("userDomainListService", ["APICatcher", function(api) {

            var packages = {};
            var accountSummaries = {};
            var NO_MODULE = "";

            /**
             * Obtain the package details of a plan
             *
             * @method getPackageDetails
             * @param  {String} plan string key of plan to obtain details of
             * @return {Promise} returns a promise that returns the package details
             */
            function getPackageDetails(plan) {

                if (packages[plan]) {
                    return Promise.resolve(packages[plan]);
                }

                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "getpkginfo", {
                        pkg: plan
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    packages[plan] = result.data.pkg;
                    return packages[plan];
                });
            }

            /**
             * Obtain the account summary for a given user
             *
             * @method getAccountSummary
             * @param  {String} username username to obtain account summary for
             * @return {Promise} returns a promise then the account summary for a user
             */
            function getAccountSummary(username) {
                if (username === "root") {
                    return Promise.resolve({ user: "root" });
                }
                if (accountSummaries[username]) {
                    return Promise.resolve(accountSummaries[username]);
                }

                var apiCall = new APIREQUEST.Class().initialize(
                    NO_MODULE,
                    "accountsummary", {
                        user: username
                    }
                );

                return api.promise(apiCall).then(function(result) {
                    var summary = result.data.pop();

                    // if only email entry is "*unknown*" or localized equivalent, don't include
                    // front end better handles display of that
                    if (summary.email.match(/^\*[^@]+\*$/)) {
                        summary.emails = [];
                    } else {
                        summary.emails = summary.email.split(", ");
                    }

                    summary.localStartdate = /^[0-9]+$/.test(summary.unix_startdate) ? LOCALE.local_datetime(summary.unix_startdate, "datetime_format_short") : LOCALE.maketext("Unknown");

                    accountSummaries[username] = summary;

                    return summary;
                });
            }

            return {
                getAccountSummary: getAccountSummary,
                getPackageDetails: getPackageDetails
            };

        }]);

    });
