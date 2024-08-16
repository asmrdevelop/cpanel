/*
# templates/mod_security/vendors.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
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

        // First create the application
        angular.module("App", [
            "cjt2.config.whm.configProvider", // This needs to load first
            "ngRoute",
            "ui.bootstrap",
            "cjt2.whm"
        ]);

        // Then load the application dependencies
        var app = require(
            [
                "cjt/bootstrap",
                "cjt/util/locale",

                // Application Modules
                "cjt/views/applicationController",
                "app/views/commonController",
                "app/views/vendorListController",
                "app/views/addVendorController",
                "app/views/enableDisableConfigController",
                "app/views/editVendorController",
                "cjt/services/autoTopService",
                "cjt/services/whm/breadcrumbService",
                "cjt/services/whm/titleService"
            ], function(BOOTSTRAP, LOCALE) {

                var app = angular.module("App");
                app.value("PAGE", PAGE);

                app.firstLoad = {
                    configs: true,
                    vendors: true
                };

                // routing
                app.config(["$routeProvider",
                    function($routeProvider) {

                        // List of vendors
                        $routeProvider.when("/vendors", {
                            controller: "vendorListController",
                            templateUrl: CJT.buildFullPath("mod_security/views/vendorListView.ptt"),
                            breadcrumb: LOCALE.maketext("Manage Vendors"),
                            title: LOCALE.maketext("Manage Vendors"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "vendors"
                        });

                        // Add a vendor
                        $routeProvider.when("/vendors/add", {
                            controller: "addVendorController",
                            templateUrl: CJT.buildFullPath("mod_security/views/addEditVendor.ptt"),
                            breadcrumb: LOCALE.maketext("Add Vendor"),
                            title: LOCALE.maketext("Add Vendor"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "add"
                        });

                        // Edit a vendor
                        $routeProvider.when("/vendors/edit", {
                            controller: "editVendorController",
                            templateUrl: CJT.buildFullPath("mod_security/views/addEditVendor.ptt"),
                            breadcrumb: LOCALE.maketext("Select Vendor Rule Sets"),
                            title: LOCALE.maketext("Select Vendor Rule Sets"),
                            reloadOnSearch: false,
                            group: "vendor",
                            name: "edit"
                        });

                        $routeProvider.otherwise({
                            redirectTo: function(routeParams, path, search) {
                                return "/vendors?" + window.location.search;
                            }
                        });
                    }
                ]);

                app.run(["autoTopService", "breadcrumbService", "titleService", function(autoTopService, breadcrumbService, titleService) {

                    // Setup the automatic scroll to top for view changes
                    autoTopService.initialize();

                    // Setup the breadcrumbs service
                    breadcrumbService.initialize();

                    // Setup the title update service
                    titleService.initialize();
                }]);

                BOOTSTRAP(document);
            });

        return app;
    }
);
