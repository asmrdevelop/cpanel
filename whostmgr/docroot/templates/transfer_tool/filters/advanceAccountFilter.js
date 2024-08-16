/*
# templates/transfer_tool/filters/advanceAccountFilter.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

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
         * Filter that uses the options set in the advance filter form to further filter accounts.  Will return true if the account passes the filter.
         * @param  {object} item
         * @return {?array}
         */
        app.filter("advanceAccountFilter", function() {
            return function(accounts, advanceFilter) {
                if (!advanceFilter) {
                    return accounts;
                }
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {
                    if (account.remote_user.indexOf(advanceFilter.user) === -1) {
                        return;
                    }
                    if (account.domain.indexOf(advanceFilter.domain) === -1) {
                        return;
                    }
                    if (advanceFilter.owner && advanceFilter.owner.length && advanceFilter.owner.indexOf(account.owner) === -1) {
                        return;
                    }
                    if (advanceFilter.dedicated_ip >= 0 && account.dedicated_ip !== advanceFilter.dedicated_ip) {
                        return;
                    }

                    filteredAccounts.push(account);
                });

                return filteredAccounts;
            };
        });
    }
);
