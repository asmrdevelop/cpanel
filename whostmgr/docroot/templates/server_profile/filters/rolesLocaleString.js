/*
#  cpanel - whostmgr/docroot/templates/server_profile/filters/rolesLocaleStringFilter.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash"
    ],
    function(angular, LOCALE, _) {
        "use strict";

        /**
         * Filter that accepts a list of roles and a locale string and returns the localized text
         * @param {String} roles        The list of roles to inject into the locale string
         * @param {String} localeString The locale string to inject the roles into
         *
         * @example
         * <div>{{ profile.roles | rolesLocaleString:'Enables: [list_and,_1]'">
         *
         * NOTE: The locale string passed to this filter must be defined in a maketext string. ## no extract maketext
         */

        var module = angular.module("whm.serverProfile.rolesLocaleString", []);

        module.filter("rolesLocaleString", function() {
            return function(roles, localeString) {
                var roleNames = _.map(roles, "name");
                return LOCALE.makevar(localeString, roleNames, roles.length);
            };
        });

    }
);
