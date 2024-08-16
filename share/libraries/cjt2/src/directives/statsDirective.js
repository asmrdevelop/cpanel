/*
# limitDirective.js                               Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/util/parse",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, LOCALE, PARSE) {

        "use strict";

        var module = angular.module("cjt2.directives.statsDirective", [
            "cjt2.templates"
        ]);

        /**
         * Directive that helps to display account limit statistics
         *
         * @name stats
         * @attribute {}
         * @example
         *
         * <stats
         *      used-id=""
         *      used=""
         *      available-id=""
         *      available=""
         *      upgrade-link-id=""
         *      upgrade-link=""
         *      upgrade-link-text="CLICK ME"
         *      show-upgrade-link=""
         *      upgrade-link-target="">
         * </stats>
         */
        module.directive("stats", ["$parse", function($parse) {

            var RELATIVE_PATH = "libraries/cjt2/directives/statsDirective.phtml";

            var ctr = 0;
            var DEFAULT_CONTROL_NAME = "stats";
            var DEFAULT_USED_ID = "lbl";
            var DEFAULT_AVAILABLE_ID = "lbl";
            var DEFAULT_UPGRADE_LINK_ID = "upgradeLinkID";
            var DEFAULT_SHOW_UPGRADE_LINK = false;

            return {

                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                restrict: "E",
                replace: true,
                require: "?ngModel",
                scope: {
                    upgradeLink: "@",
                    upgradeLinkTarget: "@",
                    upgradeTooltip: "@",
                    upgradeLinkText: "@",
                    max: "=",
                    showWarningDetails: "&onShowWarningDetails",
                },
                link: {
                    pre: function(scope, elem, attrs, ngModel) {
                        if (!ngModel) {
                            return; // do nothing if no ng-model
                        }
                        var id = angular.isDefined(attrs.id) && attrs.id !== "" ? attrs.id : DEFAULT_CONTROL_NAME + ctr++;

                        scope.usedID = angular.isDefined(attrs.usedId) && attrs.usedId !== "" ? attrs.usedId : (id + "used"  || DEFAULT_USED_ID) + ctr++;
                        scope.availableID = angular.isDefined(attrs.availableId) && attrs.availableId !== "" ? attrs.availableId : (id + "available" || DEFAULT_AVAILABLE_ID) + ctr++;
                        scope.upgradeLinkID = angular.isDefined(attrs.upgradeLinkId) && attrs.upgradeLinkId !== "" ? attrs.upgradeLinkId : ("lnkUpgrade" + id || DEFAULT_UPGRADE_LINK_ID) + ctr++;

                        scope.showUpgradeLink = angular.isDefined(attrs.showUpgradeLink) && attrs.showUpgradeLink !== "" ? PARSE.parseBoolean(attrs.showUpgradeLink) : DEFAULT_SHOW_UPGRADE_LINK;
                        scope.upgradeLink = angular.isDefined(attrs.upgradeLink) && attrs.upgradeLink !== "" ? attrs.upgradeLink : "";
                        scope.upgradeTooltip = angular.isDefined(attrs.upgradeTooltip) && attrs.upgradeTooltip !== "" ? attrs.upgradeTooltip : LOCALE.maketext("Upgrade");

                        scope.upgradeLinkText = angular.isDefined(attrs.upgradeLinkText) && attrs.upgradeLinkText !== "" ? attrs.upgradeLinkText : LOCALE.maketext("Upgrade");

                        scope.usedTitle = LOCALE.maketext("Used");
                        scope.availableTitle = LOCALE.maketext("Available");
                        scope.viewDetailsText = LOCALE.maketext("Details");
                        scope.detailsTooltip = LOCALE.maketext("View Warning Details");

                        scope.max = angular.isDefined(scope.max) ? scope.max : -1;

                        function updateValues(value) {
                            scope.usedValue = angular.isDefined(value) && value !== "" ? LOCALE.numf(value) : 0;

                            if (scope.max > -1) {
                                scope.availableValue = LOCALE.numf(scope.max - value);
                                scope.showWarning = (scope.max - value) === 0;
                            } else {
                                scope.availableValue = "∞";
                                scope.showWarning = false;
                            }
                        }

                        scope.$watch(
                            function() {
                                return ngModel.$modelValue;
                            },
                            updateValues
                        );
                    }

                }
            };
        }]);
    }
);
