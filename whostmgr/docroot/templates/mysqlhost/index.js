/*
# templates/mysqlhost/index.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W100 */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
        "ngAnimate"
    ],
    function(angular, $, _, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/util/locale",
                    "cjt/util/inet6",

                    // Application Modules
                    "app/views/profiles",
                    "app/views/profile_details",
                    "app/views/add_profile",
                    "app/directives/mysqlhost_domain_validators"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/profiles", {
                                controller: "profilesController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/profiles.ptt"),
                            });

                            $routeProvider.when("/profiles/profile-:profileName", {
                                controller: "profileDetailsController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/profile_details.ptt"),
                            });

                            $routeProvider.when("/profiles/new", {
                                controller: "addProfileController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/add_profile.ptt"),
                            });

                            $routeProvider.when("/profiles/newlocalhost", {
                                controller: "addProfileController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/add_profile.ptt"),
                            });


                            $routeProvider.otherwise({
                                "redirectTo": "/profiles"
                            });

                        }
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "growl", "growlMessages", function($rootScope, $timeout, $location, growl, growlMessages) {
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
