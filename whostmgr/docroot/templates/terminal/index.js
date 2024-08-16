/*
# whostmgr/docroot/templates/terminal/index.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define( [
    "angular",
    "lodash",
    "cjt/io/whm-v1-request",
    "cjt/io/whm-v1",
    "cjt/core",
    "cjt/modules",
    "cjt/services/alertService",
    "cjt/directives/alert",
    "cjt/directives/alertList",
    "cjt/directives/terminal",
    "uiBootstrap",
], function(angular, _, APIREQUEST) {
    "use strict";

    return function() {
        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
            "ui.bootstrap",
            "cjt2.whm",
            "cjt2.directives.terminal",
        ]);

        return require(
            [
                "cjt/bootstrap",

                // Application Modules
                "uiBootstrap",

                "cjt/directives/terminal",
            ], function(BOOTSTRAP) {
                var app = angular.module("App");
                app.controller("BaseController", [
                    "$scope",
                    "APICatcher",
                    "alertService",
                    function( $scope, APICatcher, alertService ) {

                        _.assign(
                            $scope,
                            {
                                terminal_warning_accepted: PAGE.terminal_warning_accepted,

                                acceptWarning: function _acceptWarning() {
                                    var apicall = new APIREQUEST.Class().initialize(
                                        undefined,
                                        "nvset",
                                        {
                                            key0: "terminal_warning_accepted",
                                            value0: 1,
                                        }
                                    );

                                    APICatcher.promise(apicall);

                                    $scope.terminal_warning_accepted = 1;
                                },
                            }
                        );
                    },
                ]);
                BOOTSTRAP();
            }
        );
    };
} );
