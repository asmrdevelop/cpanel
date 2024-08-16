/*
* base/frontend/jupiter/security/tls_wizard/services/CountriesService.js
*                                                 Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* jshint -W100 */
/* eslint-disable camelcase */
define(
    [
        "angular",
    ],
    function(angular) {
        "use strict";

        return angular.module("App").factory( "CountriesService", [
            function the_factory() {
                return CPANEL.PAGE.countries;
            },
        ] );
    }
);
