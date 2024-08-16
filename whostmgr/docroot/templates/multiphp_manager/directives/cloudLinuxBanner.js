/*
# templates/multiphp_manager/directives/cloudLinuxBanner.js            Copyright 2022 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/services/configService"
    ],
    function(angular, CJT, LOCALE, PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("whm.multiphpManager.cloudLinuxBanner", []);

        /**
         * This is a directive that renders CloudLinux banner where it is needed.
         *
         * Basic usage in a template:
         * <cloud-linux-banner id-prefix="someIdPrefix"
                cl-data = clDataObjectFromApi
                banner-text="clBannerTextFromView">
         * </cloud-linux-banner>
         */
        app.directive("cloudLinuxBanner",
            ["configService",
                function(configService) {
                    var TEMPLATE_PATH = "directives/cloudLinuxBanner.ptt";
                    var RELATIVE_PATH = "templates/multiphp_manager/" + TEMPLATE_PATH;
                    var checkToHideUpgradeOption = function(data) {
                        var purchaseData = data.purchase_cl_data;
                        return (purchaseData.server_timeout ||
                            (purchaseData.error_msg && purchaseData.error_msg !== ""));
                    };

                    var ddo = {
                        replace: true,
                        restrict: "E",
                        templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                        scope: {
                            idPrefix: "@",
                            clData: "=",
                            bannerText: "="
                        },
                        link: function postLink(scope, element, attrs) {
                            var scopeData = configService.setCloudLinuxInfo(scope.clData);
                            scope.data = scopeData.data;
                            scope.linkTarget = scopeData.linkTarget;
                            scope.purchaseLink = scopeData.purchaseLink;
                            scope.showBanner = scopeData.showBanner;
                            scope.actionText = scopeData.actionText;

                            scope.hideUpgradeOption = checkToHideUpgradeOption(scope.data);
                        }

                    };
                    return ddo;
                }
            ]
        );
    }
);
