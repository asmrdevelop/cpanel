/*
# services/pageDataService.js                     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Setup the domainlist models API service
         */
        app.factory("pageDataService", [ function() {

            return {

                /**
                 * Helper method to remodel the default data passed from the backend
                 * @param  {Object} defaults - Defaults object passed from the backend
                 * @return {Object}
                 */
                prepareDefaultInfo: function(defaults) {
                    defaults.security_token = defaults.security_token || "";
                    defaults.addon_domains = defaults.addon_domains || [];
                    defaults.username_restrictions = defaults.username_restrictions || {};
                    defaults.username_restrictions.maxLength = Number(defaults.username_restrictions.maxLength) || 16;
                    return defaults;
                }

            };
        }]);
    }
);
