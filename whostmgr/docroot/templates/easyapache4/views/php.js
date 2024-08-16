/*
# templates/easyapache4/views/php.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "cjt/util/locale"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("php",
            ["$scope", "PAGE",
                function($scope, PAGE) {

                    /**
                    * Builds the CloudLinux promotion banner and shows it off.
                    *
                    * @method setClBanner
                    */
                    var setClBanner = function() {
                        var clData = PAGE.cl_data;
                        var clLicensed = PAGE.cl_licensed;
                        $scope.linkTarget = "_blank";
                        $scope.purchaseLink = "";
                        $scope.clActionText = "";
                        $scope.hasCustomUrl = clData.purchase_cl_data.is_url;

                        if ( typeof clData !== "undefined" ) {
                            var purchaseCLData = clData.purchase_cl_data;
                            if (clData.cl_is_supported && !clData.cl_is_installed && !purchaseCLData.disable_upgrade) {
                                $scope.showCLBanner = true;
                                if (
                                    purchaseCLData.server_timeout ||
                                    purchaseCLData.error_msg && purchaseCLData.error_msg !== "") {
                                    $scope.hideUpgradeOption = true;
                                } else {
                                    $scope.hideUpgradeOption = false;
                                    if (clLicensed) {
                                        $scope.purchaseLink = "scripts13/install_cloudlinux_EA4";
                                        $scope.clActionText = LOCALE.maketext("Install [asis,CloudLinux]");
                                        $scope.linkTarget = "_self"; // No need for popup if staying in WHM
                                    } else {
                                        $scope.purchaseLink = clData.purchase_cl_data.url;
                                        $scope.clActionText = LOCALE.maketext("Upgrade to [asis,CloudLinux]");
                                    }
                                }
                            } else {
                                $scope.showCLBanner = false;
                            }
                            $scope.purchaseClData = purchaseCLData;
                        }
                    };

                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("php");
                        setClBanner();
                    });
                }
            ]
        );
    }
);
