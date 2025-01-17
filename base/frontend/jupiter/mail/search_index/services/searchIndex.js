/*
 * mail/search_index/services/searchIndex.js                           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define, PAGE */
define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/io/uapi-request",
        "cjt/io/api",
        "cjt/io/uapi",
        "cjt/services/APIService"
    ],
    function(angular, LOCALE, UAPIREQUEST) {

        var app = angular.module("cpanel.searchIndex.searchIndex.service", []);
        app.value("PAGE", PAGE);
        app.value("userEmailAccount", PAGE.emailAccount);

        app.factory("searchIndex", ["$q", "APIService", "userEmailAccount", "$timeout", function($q, APIService, userEmailAccount, $timeout) {

            var SearchIndex = function() {};

            function reIndexEmail() {

                var apiCall = new UAPIREQUEST.Class();
                apiCall.initialize("Email", "fts_rescan_mailbox", {
                    account: userEmailAccount
                });

                var deferred = this.deferred(apiCall);
                return deferred.promise;

            }


            SearchIndex.prototype = new APIService();

            angular.extend(SearchIndex.prototype, {
                reIndexEmail: reIndexEmail
            });

            return new SearchIndex();
        }]);
    }
);
