/*
# templates/transfer_tool/filters/accountFilter.js                  Copyright(c) 2020 cPanel, L.L.C.
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
         * Filter that filters only on specific field based on $scope.acctsFilter.  Will return true if the account passes the filter.  Necessary for performance optimization.
         * @param  {onject} item
         * @return {array}
         */
        app.filter("accountFilter", function() {
            return function(accounts, filterText) {
                if (!filterText) {
                    return accounts;
                }
                var filteredAccounts = [];
                angular.forEach(accounts, function(account) {

                    /* isUser */
                    if (account.user.indexOf(filterText) !== -1) {
                        filteredAccounts.push(account);
                    } else if (account.domain.indexOf(filterText) !== -1) {

                        /* isDomain */
                        filteredAccounts.push(account);
                    } else if (account.owner.indexOf(filterText) !== -1) {

                        /* isOwner */
                        filteredAccounts.push(account);
                    }
                });

                return filteredAccounts;
            };
        });
    }
);
