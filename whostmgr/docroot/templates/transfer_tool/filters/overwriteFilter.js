/*
# templates/transfer_tool/filters/overwriteFilter.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }

        /**
         * Returns true for account that can be overwritten
         * @param  {object} item
         * @return {array}
         */
        app.filter("overwriteFilter", function() {
            var localUsers = PAGE.local.users;
            var localDomains = PAGE.local.domains;
            return function(accounts) {
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {
                    if (localUsers[account.user] ||
                        localUsers[account.localuser] ||
                        localDomains[account.domain] === account.localuser) {
                        filteredAccounts.push(account);
                    }
                });
                return filteredAccounts;
            };
        });
    }
);
