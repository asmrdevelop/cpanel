/*
# cjt/directives/toggleLabelInfoDirective.js       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


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

        var module = angular.module("cjt2.directives.toggleLabelInfo", [
            "cjt2.templates"
        ]);

        /**
         * Directive that helps to toggle form label help
         *
         * @name toggleLabelInfo
         * @attribute {string} for - The control associated with the label
         * @attribute {string} labelText -  Label Text
         * @attribute {string} labelID - Label ID
         * @attribute {string} infoIconID - Information Icon ID
         * @attribute {string} infoBlockID - Information block ID
         * @example
         *
         * <toggle-label-info
         *      for="ips"
         *      label-text="IP Addresses"
         *      label-id="lblIps"
         *      info-icon-id="iconToggleIps"
         *      info-block-id="ips.info.block">
         *      Provide a list of IPs for this site.
         * </toggle-label-info>
         *
         * @example
         *
         * <toggle-label-info
         *      for="ips"
         *      label-text="IP Addresses"
         *      label-id="lblIps"
         *      info-icon-id="iconToggleIps"
         *      info-block-id="ips.info.block"
         *      on-toggle="toggleHelp(show)">
         *      Provide a list of IPs for this site.
         * </toggle-label-info>
         * <div
         */
        module.directive("toggleLabelInfo", function() {
            var RELATIVE_PATH = "libraries/cjt2/directives/toggleLabelInfoDirective.phtml";
            var ctr = 0;
            var DEFAULT_CONTROL_NAME = "toggleLabelInfo";
            var DEFAULT_LABEL_ID = "lbl";
            var DEFAULT_INFO_ICON_ID = "infoIcon";
            var DEFAULT_INFO_BLOCK_ID = "infoText";
            var DEFAULT_SHOW_INFO_BLOCK = false;


            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                restrict: "E",
                replace: true,
                transclude: true,
                scope: {
                    for: "@",
                    labelText: "@",
                    onToggle: "&",
                },
                link: {
                    pre: function(scope, elem, attrs) {
                        var id = angular.isDefined(attrs.id) && attrs.id !== "" ? attrs.id : DEFAULT_CONTROL_NAME + ctr++;
                        scope.labelID = angular.isDefined(attrs.labelId) && attrs.labelId !== "" ? attrs.labelId : ("lbl" + id  || DEFAULT_LABEL_ID) + ctr++;
                        scope.infoIconID = angular.isDefined(attrs.infoIconId) && attrs.infoIconId !== "" ? attrs.infoIconId : (id + "infoIcon" || DEFAULT_INFO_ICON_ID) + ctr++;
                        scope.infoBlockID = angular.isDefined(attrs.infoBlockId) && attrs.infoBlockId !== "" ? attrs.infoBlockId : (id + "infoText" || DEFAULT_INFO_BLOCK_ID) + ctr++;
                        scope.showInfoBlock = angular.isDefined(attrs.showInfoBlock) && attrs.showInfoBlock !== "" ? PARSE.parseBoolean(attrs.showInfoBlock) : DEFAULT_SHOW_INFO_BLOCK;
                        scope.toggleActionTitle = scope.showInfoBlock ? LOCALE.maketext("Collapse") : LOCALE.maketext("Expand");
                    },

                    post: function(scope, elem, attrs) {
                        scope.toggleInfoBlock = function() {
                            scope.showInfoBlock = !scope.showInfoBlock;
                            scope.toggleActionTitle = scope.showInfoBlock ? LOCALE.maketext("Collapse") : LOCALE.maketext("Expand");
                            if (angular.isDefined(attrs.onToggle)) {
                                scope.onToggle({ show: scope.showInfoBlock });
                            }
                        };

                        attrs.$observe("includeLabelSuffix", function(val) {
                            scope.includeLabelSuffix = "includeLabelSuffix" in attrs;
                        });

                        attrs.$observe("showInfoBlock", function(val) {
                            scope.showInfoBlock = angular.isDefined(attrs.showInfoBlock) && attrs.showInfoBlock !== "" ? PARSE.parseBoolean(attrs.showInfoBlock) : DEFAULT_SHOW_INFO_BLOCK;
                        });

                        scope.$on("showHideAllChange", function(event, show) {
                            scope.showInfoBlock = show;
                        });
                    },

                }
            };
        });
    }
);
