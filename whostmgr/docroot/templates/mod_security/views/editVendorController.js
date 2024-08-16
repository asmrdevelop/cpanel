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
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/autoFocus",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/vendorService",
        "app/views/enableDisableConfigController",
        "cjt/filters/notApplicableFilter"
    ],
    function(angular, LOCALE, PARSE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller(
            "editVendorController", [
                "$scope",
                "$filter",
                "$routeParams",
                "spinnerAPI",
                "alertService",
                "vendorService",
                function(
                    $scope,
                    $filter,
                    $routeParams,
                    spinnerAPI,
                    alertService,
                    vendorService) {

                    /**
                         * Helper function to just make danger alerts a little more dense.
                         *
                         * @private
                         * @method _dangetAlert
                         * @param  {String} msg Message for the alert
                         * @param  {String} id  HTML ID requested from the alertService
                         */
                    function _dangerAlert(msg, id) {
                        alertService.add({
                            type: "danger",
                            message: msg,
                            id: id
                        });
                        $scope.scrollTo("top");
                    }

                    /**
                         * Loads the form with vendor meta-data from the WHM API.
                         *
                         * @method loadVendor
                         * @param  {String} vendorId This will correspond to the vendor_id field from the API
                         */
                    $scope.loadVendor = function(vendorId) {
                        if (!$routeParams["suppress-clear-alert"] ||
                                !PARSE.parseBoolean($routeParams["suppress-clear-alert"])) {
                            alertService.clear();
                        }

                        var promise;
                        if (vendorId) {
                            spinnerAPI.start("loadingSpinner");
                            promise = vendorService.fetchVendorById(vendorId)
                                .then(function success(data) {
                                    angular.extend($scope.vendor, data);
                                    $scope.vendor.report_url = $filter("na")($scope.vendor.report_url);
                                }, function failure(error) {
                                    _dangerAlert(error, "errorLoadVendorConfig");
                                });

                            promise["finally"](function() {
                                spinnerAPI.stop("loadingSpinner");
                            });
                        } else {
                            _dangerAlert(LOCALE.maketext("An error occurred in the attempt to retrieve the vendor information."), "errorNoVendorID");
                        }
                    };

                    /**
                         * Toggle the show/hide vendor details flag.
                         *
                         * @method toggleDetails
                         */
                    $scope.toggleDetails = function() {
                        $scope.hideDetails = !$scope.hideDetails;
                    };

                    // Initialize the form on first load.
                    $scope.isEditor = true;
                    $scope.hideDetails = true;
                    $scope.vendor = { id: $routeParams.id };

                    $scope.$on("$viewContentLoaded", function() {
                        $scope.loadVendor($scope.vendor.id);
                    });
                }
            ]
        );
    }
);
