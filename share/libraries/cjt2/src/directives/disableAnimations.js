/*
# cjt/directives/disableAnimations.js             Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "ngAnimate"
    ],
    function(angular) {
        var module = angular.module("cjt2.directives.disableAnimations", ["ngAnimate"]);

        /**
         * Directive that disables animations for the element and all children.
         */
        module.directive("disableAnimations", ["$animate", function($animate) {
            return {
                restrict: "A",
                link: function(scope, element, attrs) {
                    $animate.enabled(element, false);
                }
            };
        }]);
    }
);
