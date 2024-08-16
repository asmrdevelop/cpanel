/*
# cjt/directives/loadingPanel.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {

        var module = angular.module("cjt2.directives.loadingPanel", []);

        /**
         * Directive that shows a "loading" box with a spinner and message.
         * The message is specified in the body of the element. If you want
         * to make this directive's visibility conditional, just use ng-show
         * or similar.
         *
         * @example
         *
         * Example of how to use it:
         *
         * <div cp-loading-panel id="loadingUsers" ng-show="loading">
         *     The system is loading the user list …
         * </div>
         *
         * Or as its own element:
         *
         * <cp-loading-panel id="loadingUsers" ng-show="loading">
         *     The system is loading the user list …
         * </cp-loading-panel>
         */

        module.directive("cpLoadingPanel", [
            function() {
                var idCounter = 0;
                var RELATIVE_PATH = "libraries/cjt2/directives/loadingPanel.phtml";
                return {
                    restrict: "EA",
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    transclude: true,
                    scope: {
                        id: "@"
                    },
                    compile: function(element0, attrs0) {
                        return {
                            pre: function(scope, element, attrs) {
                                if (!angular.isDefined(attrs.id)) {
                                    attrs.id = "loadingPanel" + idCounter++;
                                }
                            }
                        };
                    }
                };
            }
        ]);
    }
);
