/*
* templates/multiphp_manager/index.js            Copyright(c) 2020 cPanel, L.L.C.
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
        "uiBootstrap"
    ],
    function(angular, $, _, CJT) {
        return function() {

            // First create the application
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.multiphpManager.cloudLinuxBanner"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "app/views/phpManagerConfig",
                    "app/views/phpHandlers",
                    "app/views/conversion",
                    "app/directives/cloudLinuxBanner",
                    "app/views/poolOptions",
                    "app/directives/nonStringSelect",
                    "cjt/directives/actionButtonDirective",
                    "cjt/directives/pageSizeDirective",
                    "cjt/decorators/paginationDecorator",
                    "cjt/directives/searchDirective",
                    "cjt/directives/toggleSortDirective"
                ], function(BOOTSTRAP) {

                    var app = angular.module("App");
                    app.value("PAGE", PAGE);

                    app.firstLoad = {
                        phpAccountList: true
                    };

                    // Setup Routing
                    app.config(["$routeProvider", "growlProvider", "$animateProvider",
                        function($routeProvider, growlProvider, $animateProvider) {

                            // This prevents performance issues
                            // when the queue gets large.
                            // cf. https://docs.angularjs.org/guide/animations#which-directives-support-animations-
                            $animateProvider.classNameFilter(/INeverWantThisToAnimate/);

                            // Setup the routes
                            $routeProvider.when("/config", {
                                controller: "phpManagerController",
                                templateUrl: CJT.buildFullPath("multiphp_manager/views/phpManagerConfig.ptt"),
                                reloadOnSearch: false
                            })
                                .when("/handlers", {
                                    controller: "phpHandlers",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/phpHandlers.ptt"),
                                    reloadOnSearch: false
                                })
                                .when("/conversion", {
                                    controller: "conversion",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/conversion.ptt"),
                                    reloadOnSearch: false
                                })
                                .when("/poolOptions", {
                                    controller: "poolOptionsController",
                                    templateUrl: CJT.buildFullPath("multiphp_manager/views/poolOptions.ptt"),
                                    reloadOnSearch: false
                                })
                                .otherwise({
                                    "redirectTo": "/config"
                                });

                        }
                    ]);

                    app.run(["$rootScope", "$location", function($rootScope, $location) {
                        $("#content").show();

                        // register listener to watch route changes
                        $rootScope.$on("$routeChangeStart", function() {
                            $rootScope.currentRoute = $location.path();
                        });
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);
