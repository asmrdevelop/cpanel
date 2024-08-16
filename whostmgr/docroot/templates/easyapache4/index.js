/*
# cpanel - whostmgr/docroot/templates/easyapache4/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    [
        "angular",
        "cjt/core",
        "lodash",
        "cjt/modules",
    ],
    function(angular, CJT, _) {
        "use strict";

        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "angular-growl",
                "whm.easyapache4.ea4Util",
                "whm.easyapache4.ea4Data",
                "whm.easyapache4.pkgResolution",
                "whm.easyapache4.wizardApi",
            ]);

            // Then load the application dependencies
            var appModule = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",

                    // Application Modules
                    "cjt/directives/toggleSwitchDirective",
                    "cjt/directives/searchDirective",
                    "app/directives/eaWizard",
                    "app/directives/saveAsProfile",
                    "app/services/ea4Data",
                    "app/services/ea4Util",
                    "app/services/pkgResolution",
                    "app/services/wizardApi",
                    "cjt/views/applicationController",
                    "app/views/profile",
                    "app/views/yumUpdate",
                    "app/views/customize",
                    "app/views/loadPackages",
                    "app/views/mpm",
                    "app/views/modules",
                    "app/views/php",
                    "app/views/extensions",
                    "app/views/additionalPackages",
                    "app/views/review",
                    "app/views/provision",
                    "app/views/ruby",
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    // REFACTOR: This can be sent into ea4Data service.
                    app.firstLoad = true;

                    var wizardState = {};

                    app.value("wizardState", wizardState);

                    app.config(["$routeProvider", "$compileProvider",
                        function($routeProvider, $compileProvider) {

                            // Setup the routes
                            $routeProvider
                                .when("/profile", {
                                    controller: "profile",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/profile.ptt"),
                                })
                                .when("/loadPackages", {
                                    controller: "loadPackages",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/loadPackages.ptt"),
                                })
                                .when("/mpm", {
                                    controller: "mpm",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/mpm.phtml"),
                                })
                                .when("/modules", {
                                    controller: "modules",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/modules.phtml"),
                                })
                                .when("/php", {
                                    controller: "php",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/php.ptt"),
                                })
                                .when("/extensions", {
                                    controller: "extensions",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/extensions.phtml"),
                                })
                                .when("/additional", {
                                    controller: "additionalPackages",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/additionalPackages.phtml"),
                                })
                                .when("/review", {
                                    controller: "review",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/review.ptt"),
                                })
                                .when("/ruby", {
                                    controller: "ruby",
                                    templateUrl: CJT.buildFullPath("templates/easyapache4/views/ruby.phtml"),
                                })
                                .when("/provision", {
                                    controller: "provision",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/provision.ptt"),
                                })
                                .when("/yumUpdate", {
                                    controller: "yumUpdate",
                                    templateUrl: CJT.buildFullPath("easyapache4/views/yumUpdate.ptt"),
                                })
                                .otherwise({
                                    "redirectTo": "/profile",
                                });

                            $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/);

                        },
                    ]);

                    app.run(["$rootScope", "$location", "ea4Util", "wizardApi", "wizardState", function($rootScope, $location, ea4Util, wizardApi, wizardState) {
                        if (_.isEmpty(wizardState)) {
                            wizardApi.init();
                            ea4Util.hideFooter();
                        }

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });
                    }]);
                    BOOTSTRAP(document);
                }
            );
            return appModule;
        };
    }
);
