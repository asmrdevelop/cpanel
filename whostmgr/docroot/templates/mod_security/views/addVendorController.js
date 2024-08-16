/*
# templates/mod_security/views/addVendorController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "app/directives/ruleVendorUrlValidator",
        "cjt/filters/notApplicableFilter",
    ],
    function(angular, _, LOCALE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addVendorController", [
                "$scope",
                "$filter",
                "spinnerAPI",
                "alertService",
                "vendorService",
                function(
                    $scope,
                    $filter,
                    spinnerAPI,
                    alertService,
                    vendorService) {

                    /**
                         * Disable buttons based on form state
                         *
                         * @method disableForm
                         * @param  {FormController} form
                         * @return {Boolean}
                         */
                    $scope.disableForm = function(form) {
                        return form.$pristine || (form.$dirty && form.$invalid) || $scope.loading;
                    };

                    /**
                         * Load the form with vendor configuration from a specified URL
                         *
                         * @method load
                         * @param  {String} url Address of the YAML configuration file
                         * @return {Promise}
                         */
                    $scope.load = function(url) {
                        alertService.clear();
                        spinnerAPI.start("loadingSpinner");
                        $scope.loading = true;
                        return vendorService
                            .loadVendor(url)
                            .then(function(vendor) {
                                angular.extend($scope.vendor, vendor);
                                $scope.vendor.isLoaded = true;
                                $scope.vendor.report_url = $filter("na")($scope.vendor.report_url);
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorLoadVendorConfig",
                                });
                                $scope.vendor.isLoaded = false;
                            })
                            .finally(function() {
                                spinnerAPI.stop("loadingSpinner");
                                $scope.loading = false;
                            });
                    };

                    /**
                         * Save the form
                         *
                         * @method save
                         * @param  {String} url         Address of the YAML configuration file
                         * @return {Promise}
                         */
                    $scope.save = function(url) {
                        alertService.clear();
                        spinnerAPI.start("savingSpinner");
                        return vendorService
                            .saveVendor(url)
                            .then(function(vendor) {

                                // success
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You have successfully added “[_1]” to the vendor configuration list.", vendor.name),
                                    id: "successSaveVendorConfig",
                                });
                                $scope.loadView("/vendors");
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorSaveVendorConfig",
                                });
                                $scope.scrollTo("top");
                            })
                            .finally(function() {
                                spinnerAPI.stop("savingSpinner");
                            });
                    };

                    /**
                         * Navigate to the previous view.
                         *
                         * @method  cancel
                         */
                    $scope.cancel = function() {
                        alertService.clear();
                        $scope.loadView("vendors");
                    };

                    /**
                         * Clear alerts and restore form defaults
                         *
                         * @method clearForm
                         */
                    $scope.clearForm = function() {
                        $scope.vendor = {
                            enabled: true,
                            isLoaded: false,
                        };
                        alertService.clear();
                    };

                    // Use SSL for YAML URL recommendation warning

                    $scope.showSSLwarning = false;

                    $scope.vendorURLchange = function(url) {
                        var show = false;
                        var matches = /^(https?):\/\//.exec(url);
                        if (matches && ( matches[1] === "http" ) ) {
                            show = true;
                        }
                        $scope.showSSLwarning = show;
                    };

                    // Initialize the form on first load.
                    $scope.isEditor = false;
                    $scope.clearForm();
                },
            ]
        );

        return controller;
    }
);
