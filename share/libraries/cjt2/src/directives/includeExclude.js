/*
# cjt/directives/includeExclude.js                Copyright(c) 2020 cPanel, L.L.C.
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

        var module = angular.module("cjt2.directives.includeCharacters", []);

        module.directive("includeCharacters", ["$parse", function($parse) {
            return {
                restrict: "A",
                require: "ngModel",
                link: function(scope, iElement, iAttrs, controller) {
                    var replaceRegex = new RegExp("[^" + iAttrs.includeCharacters + "]", "g");
                    scope.$watch(iAttrs.ngModel, function(value) {
                        if (!value) {
                            return;
                        }
                        $parse(iAttrs.ngModel).assign(scope, value.replace(replaceRegex, ""));
                    });
                }
            };
        }
        ]);

        module = angular.module("cjt2.directives.excludeCharacters", []);

        module.directive("excludeCharacters", ["$parse", function($parse) {
            return {
                restrict: "A",
                require: "ngModel",
                link: function(scope, iElement, iAttrs, controller) {
                    var replaceRegex = new RegExp("[" + iAttrs.excludeCharacters + "]", "g");
                    scope.$watch(iAttrs.ngModel, function(value) {
                        if (!value) {
                            return;
                        }
                        $parse(iAttrs.ngModel).assign(scope, value.replace(replaceRegex, ""));
                    });
                }
            };
        }
        ]);
    }
);
