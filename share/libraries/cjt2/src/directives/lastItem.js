/*
# cjt/directives/lastItem.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {
        var module = angular.module("cjt2.directives.lastItem", []);

        /**
         * Directive the calls a method when it sees the last item of a repeater.
         * @example
         * <div ng-repeat="..." cp-last-item="done()" />
         */
        module.directive("cpLastItem", ["$parse", "$timeout", function($parse, $timeout) {
            return {
                restrict: "A",
                link: function(scope, element, attrs) {
                    scope.$watchGroup(["$index", "$last"], function watchLast() {
                        if (scope.$last && attrs.cpLastItem) {
                            $timeout(function() {
                                scope.$eval(attrs.cpLastItem);
                            }, 5);
                        }
                    });
                }
            };
        }]);
    }
);
