/*
* templates/multiphp_ini_editor/index.js            Copyright(c) 2020 cPanel, L.L.C.
*                                                           All rights reserved.
* copyright@cpanel.net                                         http://cpanel.net
* This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define, PAGE */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngAnimate"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm",
                "whm.multiPhpIniEditor.configService"

            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/basicMode",
                    "app/views/editorMode",
                    "cjt/directives/actionButtonDirective"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    // Setup Routing
                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/basic", {
                                controller: "basicMode",
                                templateUrl: CJT.buildFullPath("multiphp_ini_editor/views/basicMode.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.when("/editor", {
                                controller: "editorMode",
                                templateUrl: CJT.buildFullPath("multiphp_ini_editor/views/editorMode.ptt"),
                                reloadOnSearch: false
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/basic"
                            });
                        }
                    ]);

                    app.run(["$rootScope", "$location", "growlMessages", function($rootScope, $location, growlMessages) {

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                            growlMessages.destroyAllMessages();
                        });
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
