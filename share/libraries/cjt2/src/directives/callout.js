/*
# cjt/directives/callout.js                       Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/templates"
    ],
    function(angular, CJT, LOCALE, TEST) {
        "use strict";

        var module = angular.module("cjt2.directives.callout", ["cjt2.templates"]);

        /**
         * Directive that lets users highlight information on a page.
         *
         * @attribute {String} callout-type Type of callout (warning, info, danger)
         * @attribute {String} [callout-heading] Optional heading for callout.
         *
         * @example
         *
         * Basic usage with heading:
         * <callout callout-type="warning" callout-heading="Heading Text">Call out body text</callout>
         * <callout callout-type="info" callout-heading="Heading Text">Call out body text</callout>
         * <callout callout-type="danger" callout-heading="Heading Text">Call out body text</callout>
         *
         * Basic usage without heading
         * <callout callout-type="warning">Call out body text</callout>
         * <callout callout-type="info">Call out body text</callout>
         * <callout callout-type="danger">Call out body text</callout>
         */
        module.directive("callout", [function() {
            var RELATIVE_PATH = "libraries/cjt2/directives/callout.phtml";
            var DEFAULT_CALLOUT_TYPE = "info";

            return {
                restrict: "EA",
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                transclude: true,
                scope: {
                    calloutType: "=calloutType",
                    calloutHeading: "@calloutHeading",
                    closeable: "@",
                    onClose: "&"
                },
                link: function(scope, element, attr) {
                    scope.hasHeading = false;
                    scope.closeText = LOCALE.maketext("Close");

                    scope.runClose = function() {
                        scope.onClose();
                    };

                    // Handles calloutType enumeration defaulting
                    if (angular.isDefined(attr.calloutType)) {
                        switch (attr.calloutType) {
                            case "warning":
                            case "danger":
                                scope.calloutType = attr.calloutType;
                                break;

                            default:
                                scope.calloutType = DEFAULT_CALLOUT_TYPE;
                                break;
                        }
                    } else {
                        scope.calloutType = DEFAULT_CALLOUT_TYPE;
                    }

                    // Handles calloutHeading display
                    if (angular.isDefined(attr.calloutHeading)) {
                        scope.hasHeading = true;
                    }
                }
            };
        }]);
    }
);
